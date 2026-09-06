#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <execinfo.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <atomic>
#include <string>
#include <time.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include "dobby.h"

namespace {
constexpr uintptr_t RVA_QUICKSDK_BEGIN_INIT = 0x0107FEBC;
constexpr uintptr_t RVA_HTTP_SYNC_REQUEST2  = 0x01085044;
constexpr uintptr_t RVA_UPDATE_SERVER_LIST  = 0x0109BFBC;
constexpr uint16_t MSG_BOOTSTRAP = 0x2713; // 10003
constexpr uint16_t MSG_ZONE_LIST = 0x27D3; // 10195
constexpr uint16_t MSG_BOOTSTRAP_RSP = 0x4E23; // 20003
constexpr uint16_t MSG_ZONE_LIST_RSP = 0x4EE3; // 20195
constexpr size_t MAX_SCAN_BYTES = 8192;
constexpr size_t MAX_HEX_BYTES = 256;
constexpr int MAX_TRACE_FRAMES = 20;

std::atomic<bool> gInstalled{false};
std::atomic<uintptr_t> gUnityBase{0};
std::atomic<uint64_t> gWatchUntilMs{0};
int gLogFd = -1;
pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
thread_local int gNetHookDepth = 0;

using FnWrite = ssize_t (*)(int,const void*,size_t);
FnWrite orig_Write = nullptr;

static uint64_t now_ms(){ timeval tv{}; gettimeofday(&tv,nullptr); return (uint64_t)tv.tv_sec*1000ULL+(uint64_t)tv.tv_usec/1000ULL; }
static uint64_t tid_now(){ uint64_t t=0; pthread_threadid_np(nullptr,&t); return t; }
static ssize_t raw_write(int fd,const void*buf,size_t len){ return orig_Write?orig_Write(fd,buf,len):::write(fd,buf,len); }

static void ensure_log_open(){
  if(gLogFd>=0) return;
  pthread_mutex_lock(&gLogLock);
  if(gLogFd<0){ const char*home=getenv("HOME"); char p[1024];
    snprintf(p,sizeof(p),"%s/Documents/Login10195Diag_v0.4.log",(home&&*home)?home:"/tmp");
    gLogFd=open(p,O_CREAT|O_WRONLY|O_APPEND,0644);
  }
  pthread_mutex_unlock(&gLogLock);
}

static void log_line(const char*fmt,...){
  ensure_log_open(); if(gLogFd<0) return;
  timeval tv{}; gettimeofday(&tv,nullptr); tm tmv{}; localtime_r(&tv.tv_sec,&tmv);
  char pre[192]; int pn=snprintf(pre,sizeof(pre),"%04d-%02d-%02d %02d:%02d:%02d.%03d [tid=%llu] ",tmv.tm_year+1900,tmv.tm_mon+1,tmv.tm_mday,tmv.tm_hour,tmv.tm_min,tmv.tm_sec,(int)(tv.tv_usec/1000),(unsigned long long)tid_now());
  char body[8192]; va_list ap; va_start(ap,fmt); int bn=vsnprintf(body,sizeof(body),fmt,ap); va_end(ap); if(bn<0) return; if(bn>=(int)sizeof(body)) bn=(int)sizeof(body)-1;
  pthread_mutex_lock(&gLogLock); if(pn>0) raw_write(gLogFd,pre,(size_t)pn); if(bn>0) raw_write(gLogFd,body,(size_t)bn); raw_write(gLogFd,"\n",1); fsync(gLogFd); pthread_mutex_unlock(&gLogLock);
}

static uintptr_t find_unity_base(){ for(uint32_t i=0;i<_dyld_image_count();++i){ const char*n=_dyld_get_image_name(i); if(!n)continue; if(strstr(n,"UnityFramework.framework/UnityFramework")||strstr(n,"/UnityFramework")){ auto*h=_dyld_get_image_header(i); if(h)return (uintptr_t)h; }} return 0; }
static void* rva_ptr(uintptr_t r){ return (void*)(gUnityBase.load()+r); }

static void log_address(const char*tag,void*addr){ Dl_info di{}; uintptr_t ub=gUnityBase.load(); if(addr&&dladdr(addr,&di)&&di.dli_fname){ uintptr_t ib=(uintptr_t)di.dli_fbase, off=(uintptr_t)addr-ib; if(ub&&strstr(di.dli_fname,"UnityFramework")) log_line("%s addr=%p imageOff=0x%llX UnityRVA=0x%llX",tag,addr,(unsigned long long)off,(unsigned long long)((uintptr_t)addr-ub)); else log_line("%s addr=%p imageOff=0x%llX image=%s",tag,addr,(unsigned long long)off,di.dli_fname); } else log_line("%s addr=%p",tag,addr); }
static void log_trace(const char*tag){ void*f[MAX_TRACE_FRAMES]{}; int n=backtrace(f,MAX_TRACE_FRAMES); log_line("%s backtrace count=%d",tag,n); for(int i=0;i<n;++i){ char t[96]; snprintf(t,sizeof(t),"%s #%02d",tag,i); log_address(t,f[i]); }}

static const char* class_name_safe(void*o){ if(!o)return "<nil>"; Class c=object_getClass((id)o); return c?class_getName(c):"<unknown>"; }
static bool has_sel(void*o,SEL s){ if(!o||!s)return false; Class c=object_getClass((id)o); return c&&class_getInstanceMethod(c,s); }
static std::string objc_text(void*o){ if(!o)return "<nil>"; std::string x; SEL u=sel_registerName("UTF8String"); if(has_sel(o,u)){ using F=const char*(*)(id,SEL); const char*s=((F)objc_msgSend)((id)o,u); if(s)x=s; } if(x.empty()){ SEL d=sel_registerName("description"); if(has_sel(o,d)){ using G=id(*)(id,SEL); id z=((G)objc_msgSend)((id)o,d); if(z&&has_sel((void*)z,u)){ using F=const char*(*)(id,SEL); const char*s=((F)objc_msgSend)(z,u); if(s)x=s; }}} if(x.size()>1536){x.resize(1536);x+="...";} char h[128]; snprintf(h,sizeof(h),"class=%s ptr=%p text=",class_name_safe(o),o); return std::string(h)+(x.empty()?"<unavailable>":x); }

static uint16_t be16(const uint8_t*p){ return (uint16_t)(((uint16_t)p[0]<<8)|p[1]); }
static uint32_t be32(const uint8_t*p){ return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3]; }
static std::string hx(const uint8_t*p,size_t n){ if(n>MAX_HEX_BYTES)n=MAX_HEX_BYTES; static const char H[]="0123456789ABCDEF"; std::string s; s.reserve(n*3); for(size_t i=0;i<n;++i){ if(i)s.push_back(' '); s.push_back(H[p[i]>>4]); s.push_back(H[p[i]&15]); } return s; }
static std::string peer_text(int fd){ sockaddr_storage ss{}; socklen_t sl=sizeof(ss); if(getpeername(fd,(sockaddr*)&ss,&sl)!=0)return "<not-socket>"; char ip[INET6_ADDRSTRLEN]{}; uint16_t p=0; if(ss.ss_family==AF_INET){auto*a=(sockaddr_in*)&ss;inet_ntop(AF_INET,&a->sin_addr,ip,sizeof(ip));p=ntohs(a->sin_port);} else if(ss.ss_family==AF_INET6){auto*a=(sockaddr_in6*)&ss;inet_ntop(AF_INET6,&a->sin6_addr,ip,sizeof(ip));p=ntohs(a->sin6_port);} else return "<non-ip>"; char out[160]; snprintf(out,sizeof(out),"%s:%u",ip,p); return out; }
static bool peer_is_agent(int fd){ std::string p=peer_text(fd); return p.find(":7000")!=std::string::npos||p.find(":7001")!=std::string::npos; }

static bool plausible(const uint8_t*p,size_t len,size_t off){ if(off+10>len)return false; uint32_t b=be32(p+off); return b<=16U*1024U*1024U && (b==0||b+10<=len-off||len-off<4096); }
static void inspect_out(const char*api,int fd,const void*buf,size_t len,void*caller){ if(!buf||len<10)return; const uint8_t*p=(const uint8_t*)buf; size_t sn=len<MAX_SCAN_BYTES?len:MAX_SCAN_BYTES; for(size_t off=0;off+10<=sn;++off){ uint16_t m=be16(p+off+4); if(m!=MSG_BOOTSTRAP&&m!=MSG_ZONE_LIST)continue; if(!plausible(p,len,off))continue; uint32_t b=be32(p+off), seq=be32(p+off+6); log_line("[TX] api=%s fd=%d peer=%s off=%zu len=%zu msg=%u/0x%04X body=%u seq=%u caller=%p",api,fd,peer_text(fd).c_str(),off,len,m,m,b,seq,caller); log_line("[TX] HEX %s",hx(p+off,len-off).c_str()); log_address("[TX] CALLER",caller); log_trace(m==MSG_ZONE_LIST?"[TX-10195]":"[TX-10003]"); if(m==MSG_BOOTSTRAP) gWatchUntilMs.store(now_ms()+5000ULL); return; }}

static void inspect_in(const char*api,int fd,const void*buf,size_t len,void*caller){ if(!buf||len==0||!peer_is_agent(fd))return; const uint8_t*p=(const uint8_t*)buf; bool watch=now_ms()<=gWatchUntilMs.load(); bool matched=false; size_t sn=len<MAX_SCAN_BYTES?len:MAX_SCAN_BYTES; for(size_t off=0;off+10<=sn;++off){ if(!plausible(p,len,off))continue; uint16_t m=be16(p+off+4); if(m==MSG_BOOTSTRAP_RSP||m==MSG_ZONE_LIST_RSP){ uint32_t b=be32(p+off),seq=be32(p+off+6); log_line("[RX] TARGET api=%s fd=%d peer=%s off=%zu len=%zu msg=%u/0x%04X body=%u seq=%u caller=%p",api,fd,peer_text(fd).c_str(),off,len,m,m,b,seq,caller); log_line("[RX] HEX %s",hx(p+off,len-off).c_str()); log_address("[RX] CALLER",caller); log_trace(m==MSG_ZONE_LIST_RSP?"[RX-20195]":"[RX-20003]"); matched=true; break; }} if(watch&&!matched){ log_line("[RX] WATCH api=%s fd=%d peer=%s len=%zu caller=%p",api,fd,peer_text(fd).c_str(),len,caller); log_line("[RX] WATCH HEX %s",hx(p,len).c_str()); log_address("[RX] WATCH CALLER",caller); }}

using FnSend=ssize_t(*)(int,const void*,size_t,int); using FnSendTo=ssize_t(*)(int,const void*,size_t,int,const sockaddr*,socklen_t); using FnSendMsg=ssize_t(*)(int,const msghdr*,int); using FnWritev=ssize_t(*)(int,const iovec*,int);
using FnRecv=ssize_t(*)(int,void*,size_t,int); using FnRecvFrom=ssize_t(*)(int,void*,size_t,int,sockaddr*,socklen_t*); using FnRecvMsg=ssize_t(*)(int,msghdr*,int); using FnRead=ssize_t(*)(int,void*,size_t); using FnReadv=ssize_t(*)(int,const iovec*,int);
FnSend oSend=nullptr; FnSendTo oSendTo=nullptr; FnSendMsg oSendMsg=nullptr; FnWritev oWritev=nullptr; FnRecv oRecv=nullptr; FnRecvFrom oRecvFrom=nullptr; FnRecvMsg oRecvMsg=nullptr; FnRead oRead=nullptr; FnReadv oReadv=nullptr;
static size_t merge_iov(const iovec*i,int c,uint8_t*out,size_t cap){ size_t u=0; if(!i||c<=0)return 0; for(int k=0;k<c&&u<cap;++k){ if(!i[k].iov_base||!i[k].iov_len)continue; size_t n=i[k].iov_len; if(n>cap-u)n=cap-u; memcpy(out+u,i[k].iov_base,n); u+=n;}return u;}
static ssize_t hSend(int fd,const void*b,size_t n,int f){ if(gNetHookDepth++==0)inspect_out("send",fd,b,n,__builtin_return_address(0));--gNetHookDepth;return oSend(fd,b,n,f);} static ssize_t hSendTo(int fd,const void*b,size_t n,int f,const sockaddr*a,socklen_t l){if(gNetHookDepth++==0)inspect_out("sendto",fd,b,n,__builtin_return_address(0));--gNetHookDepth;return oSendTo(fd,b,n,f,a,l);} static ssize_t hWrite(int fd,const void*b,size_t n){if(fd==gLogFd)return orig_Write(fd,b,n);if(gNetHookDepth++==0)inspect_out("write",fd,b,n,__builtin_return_address(0));--gNetHookDepth;return orig_Write(fd,b,n);} static ssize_t hWritev(int fd,const iovec*i,int c){if(gNetHookDepth++==0){uint8_t m[MAX_SCAN_BYTES];size_t n=merge_iov(i,c,m,sizeof(m));inspect_out("writev",fd,m,n,__builtin_return_address(0));}--gNetHookDepth;return oWritev(fd,i,c);} static ssize_t hSendMsg(int fd,const msghdr*m,int f){if(gNetHookDepth++==0&&m){uint8_t b[MAX_SCAN_BYTES];size_t n=merge_iov(m->msg_iov,(int)m->msg_iovlen,b,sizeof(b));inspect_out("sendmsg",fd,b,n,__builtin_return_address(0));}--gNetHookDepth;return oSendMsg(fd,m,f);}
static ssize_t hRecv(int fd,void*b,size_t n,int f){ssize_t r=oRecv(fd,b,n,f);if(r>0&&gNetHookDepth++==0)inspect_in("recv",fd,b,(size_t)r,__builtin_return_address(0));if(r>0)--gNetHookDepth;return r;} static ssize_t hRecvFrom(int fd,void*b,size_t n,int f,sockaddr*a,socklen_t*l){ssize_t r=oRecvFrom(fd,b,n,f,a,l);if(r>0&&gNetHookDepth++==0)inspect_in("recvfrom",fd,b,(size_t)r,__builtin_return_address(0));if(r>0)--gNetHookDepth;return r;} static ssize_t hRead(int fd,void*b,size_t n){ssize_t r=oRead(fd,b,n);if(r>0&&gNetHookDepth++==0)inspect_in("read",fd,b,(size_t)r,__builtin_return_address(0));if(r>0)--gNetHookDepth;return r;} static ssize_t hReadv(int fd,const iovec*i,int c){ssize_t r=oReadv(fd,i,c);if(r>0&&gNetHookDepth++==0){uint8_t m[MAX_SCAN_BYTES];size_t n=merge_iov(i,c,m,(size_t)r<sizeof(m)?(size_t)r:sizeof(m));inspect_in("readv",fd,m,n,__builtin_return_address(0));}if(r>0)--gNetHookDepth;return r;} static ssize_t hRecvMsg(int fd,msghdr*m,int f){ssize_t r=oRecvMsg(fd,m,f);if(r>0&&m&&gNetHookDepth++==0){uint8_t b[MAX_SCAN_BYTES];size_t n=merge_iov(m->msg_iov,(int)m->msg_iovlen,b,(size_t)r<sizeof(b)?(size_t)r:sizeof(b));inspect_in("recvmsg",fd,b,n,__builtin_return_address(0));}if(r>0)--gNetHookDepth;return r;}

using FInit=void(*)(void*,void*); FInit oInit=nullptr; static void hInit(void*s,void*sel){log_line("[QuickInit] ENTER self=%p class=%s",s,class_name_safe(s));uint64_t t=now_ms();oInit(s,sel);log_line("[QuickInit] LEAVE elapsed=%llums",(unsigned long long)(now_ms()-t));}
using FList=void(*)(void*,void*,void*,void*); FList oList=nullptr; static void hList(void*s,void*sel,void*p,void*h){log_line("[ServerList] ENTER self=%p handler=%p",s,h);log_line("[ServerList] params %s",objc_text(p).c_str());uint64_t t=now_ms();oList(s,sel,p,h);log_line("[ServerList] LEAVE elapsed=%llums",(unsigned long long)(now_ms()-t));}
using FHttp=void*(*)(void*,void*,void*,void*,void*); FHttp oHttp=nullptr; static void*hHttp(void*s,void*sel,void*u,void*p,void*m){log_line("[HTTP2] url %s",objc_text(u).c_str());log_line("[HTTP2] method %s",objc_text(m).c_str());uint64_t t=now_ms();void*r=oHttp(s,sel,u,p,m);log_line("[HTTP2] LEAVE elapsed=%llums result=%s",(unsigned long long)(now_ms()-t),objc_text(r).c_str());return r;}

static bool hook_sym(const char*n,void*r,void**o){void*t=dlsym(RTLD_DEFAULT,n);if(!t){log_line("[INSTALL] symbol %s not found",n);return false;}int rc=DobbyHook(t,r,o);log_line("[INSTALL] symbol %s rc=%d target=%p original=%p",n,rc,t,o?*o:nullptr);return rc==0;}
static bool hook_rva(const char*n,uintptr_t r,void*x,void**o){void*t=rva_ptr(r);int rc=DobbyHook(t,x,o);log_line("[INSTALL] %s RVA=0x%llX rc=%d target=%p",n,(unsigned long long)r,rc,t);return rc==0;}
static void install(){if(gInstalled.exchange(true))return;uintptr_t b=find_unity_base();if(!b){gInstalled=false;return;}gUnityBase=b;log_line("============================================================");log_line("Login10195Diag v0.4 start");log_line("UnityFramework base=%p",(void*)b);bool ok=true;ok&=hook_rva("beginQuickSDKInit",RVA_QUICKSDK_BEGIN_INIT,(void*)hInit,(void**)&oInit);ok&=hook_rva("addSyncHttpRequest2",RVA_HTTP_SYNC_REQUEST2,(void*)hHttp,(void**)&oHttp);ok&=hook_rva("updateServerList",RVA_UPDATE_SERVER_LIST,(void*)hList,(void**)&oList);ok&=hook_sym("write",(void*)hWrite,(void**)&orig_Write);ok&=hook_sym("writev",(void*)hWritev,(void**)&oWritev);ok&=hook_sym("send",(void*)hSend,(void**)&oSend);ok&=hook_sym("sendto",(void*)hSendTo,(void**)&oSendTo);ok&=hook_sym("sendmsg",(void*)hSendMsg,(void**)&oSendMsg);ok&=hook_sym("recv",(void*)hRecv,(void**)&oRecv);ok&=hook_sym("recvfrom",(void*)hRecvFrom,(void**)&oRecvFrom);ok&=hook_sym("recvmsg",(void*)hRecvMsg,(void**)&oRecvMsg);ok&=hook_sym("read",(void*)hRead,(void**)&oRead);ok&=hook_sym("readv",(void*)hReadv,(void**)&oReadv);log_line("[INSTALL] complete ok=%d",ok?1:0);}
static void*thread_main(void*){for(int i=0;i<600;++i){if(find_unity_base()){install();return nullptr;}usleep(100000);}log_line("[INSTALL] timeout");return nullptr;}
__attribute__((constructor)) static void entry(){ensure_log_open();log_line("[BOOT] Login10195Diag v0.4 loaded");pthread_t t{};if(pthread_create(&t,nullptr,thread_main,nullptr)==0)pthread_detach(t);else log_line("[BOOT] pthread_create failed");}
} // namespace
