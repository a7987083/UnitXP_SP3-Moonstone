#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
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
constexpr uint16_t MSG_BOOTSTRAP = 0x2713;      // 10003
constexpr uint16_t MSG_ZONE_LIST = 0x27D3;      // 10195
constexpr uint16_t MSG_BOOTSTRAP_RSP = 0x4E23;  // 20003
constexpr uint16_t MSG_ZONE_LIST_RSP = 0x4EE3;  // 20195
constexpr uint64_t STARTUP_WINDOW_MS = 45000;
constexpr size_t BODY_PREVIEW_MAX = 768;

std::atomic<bool> gInstalled{false};
std::atomic<uintptr_t> gUnityBase{0};
std::atomic<uint64_t> gWatchUntilMs{0};
uint64_t gBootMs = 0;
int gLogFd = -1;
pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
thread_local int gDepth = 0;

using FnWrite = ssize_t(*)(int,const void*,size_t);
FnWrite orig_Write = nullptr;

static uint64_t now_ms(){ timeval tv{}; gettimeofday(&tv,nullptr); return (uint64_t)tv.tv_sec*1000ULL+(uint64_t)tv.tv_usec/1000ULL; }
static uint64_t tid_now(){ uint64_t t=0; pthread_threadid_np(nullptr,&t); return t; }
static ssize_t raw_write(int fd,const void*buf,size_t len){ return orig_Write ? orig_Write(fd,buf,len) : ::write(fd,buf,len); }

static void ensure_log(){
  if(gLogFd>=0) return;
  pthread_mutex_lock(&gLogLock);
  if(gLogFd<0){
    const char*home=getenv("HOME"); char p[1024];
    snprintf(p,sizeof(p),"%s/Documents/Login10195Diag_v0.6.log",(home&&*home)?home:"/tmp");
    gLogFd=open(p,O_CREAT|O_WRONLY|O_APPEND,0644);
  }
  pthread_mutex_unlock(&gLogLock);
}
static void log_line(const char*fmt,...){
  ensure_log(); if(gLogFd<0) return;
  timeval tv{}; gettimeofday(&tv,nullptr); tm tmv{}; localtime_r(&tv.tv_sec,&tmv);
  char pre[192]; int pn=snprintf(pre,sizeof(pre),"%04d-%02d-%02d %02d:%02d:%02d.%03d [tid=%llu] ",tmv.tm_year+1900,tmv.tm_mon+1,tmv.tm_mday,tmv.tm_hour,tmv.tm_min,tmv.tm_sec,(int)(tv.tv_usec/1000),(unsigned long long)tid_now());
  char body[6144]; va_list ap; va_start(ap,fmt); int bn=vsnprintf(body,sizeof(body),fmt,ap); va_end(ap); if(bn<0)return; if(bn>=(int)sizeof(body))bn=(int)sizeof(body)-1;
  pthread_mutex_lock(&gLogLock);
  if(pn>0) raw_write(gLogFd,pre,(size_t)pn);
  if(bn>0) raw_write(gLogFd,body,(size_t)bn);
  raw_write(gLogFd,"\n",1);
  pthread_mutex_unlock(&gLogLock);
}

static uintptr_t find_unity_base(){
  for(uint32_t i=0;i<_dyld_image_count();++i){
    const char*n=_dyld_get_image_name(i); if(!n) continue;
    if(strstr(n,"UnityFramework.framework/UnityFramework")||strstr(n,"/UnityFramework")){
      const auto*h=_dyld_get_image_header(i); if(h) return (uintptr_t)h;
    }
  }
  return 0;
}
static uint16_t be16(const uint8_t*p){return (uint16_t)(((uint16_t)p[0]<<8)|p[1]);}
static uint32_t be32(const uint8_t*p){return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];}
static std::string peer_text(int fd){
  sockaddr_storage ss{}; socklen_t sl=sizeof(ss);
  if(getpeername(fd,(sockaddr*)&ss,&sl)!=0) return "<not-socket>";
  char ip[INET6_ADDRSTRLEN]{}; uint16_t p=0;
  if(ss.ss_family==AF_INET){auto*a=(sockaddr_in*)&ss;inet_ntop(AF_INET,&a->sin_addr,ip,sizeof(ip));p=ntohs(a->sin_port);}
  else if(ss.ss_family==AF_INET6){auto*a=(sockaddr_in6*)&ss;inet_ntop(AF_INET6,&a->sin6_addr,ip,sizeof(ip));p=ntohs(a->sin6_port);}
  else return "<non-ip>";
  char out[160]; snprintf(out,sizeof(out),"%s:%u",ip,p); return out;
}
static bool peer_is_agent(int fd){ std::string p=peer_text(fd); return p.find(":7000")!=std::string::npos||p.find(":7001")!=std::string::npos; }

static bool has_sel(id o,SEL s){ if(!o||!s)return false; Class c=object_getClass(o); return c&&class_getInstanceMethod(c,s); }
static std::string ns_text(id o){
  if(!o) return "<nil>";
  SEL u=sel_registerName("UTF8String");
  if(has_sel(o,u)){ using F=const char*(*)(id,SEL); const char*s=((F)objc_msgSend)(o,u); if(s)return std::string(s); }
  SEL d=sel_registerName("description");
  if(has_sel(o,d)){ using G=id(*)(id,SEL); id z=((G)objc_msgSend)(o,d); if(z&&has_sel(z,u)){ using F=const char*(*)(id,SEL); const char*s=((F)objc_msgSend)(z,u); if(s)return std::string(s); }}
  return "<unavailable>";
}
static id msg_id(id o,const char*name){ if(!o)return nullptr; SEL s=sel_registerName(name); if(!has_sel(o,s))return nullptr; using F=id(*)(id,SEL); return ((F)objc_msgSend)(o,s); }
static long long msg_i64(id o,const char*name,long long def=-1){ if(!o)return def; SEL s=sel_registerName(name); if(!has_sel(o,s))return def; using F=long long(*)(id,SEL); return ((F)objc_msgSend)(o,s); }
static std::string request_url(id req){ id url=msg_id(req,"URL"); id abs=msg_id(url,"absoluteString"); return ns_text(abs); }
static std::string request_method(id req){ return ns_text(msg_id(req,"HTTPMethod")); }
static std::string response_url(id rsp){ id url=msg_id(rsp,"URL"); id abs=msg_id(url,"absoluteString"); return ns_text(abs); }
static long long response_status(id rsp){ return msg_i64(rsp,"statusCode",-1); }
static bool interesting_url(const std::string&s){
  static const char*keys[]={"login_ing","/master/GM/api/chpy","validationRole","writNoinfo","getresource","43.242.203.214","gamedachen"};
  for(const char*k:keys) if(s.find(k)!=std::string::npos) return true;
  return false;
}
static std::string data_preview(id data){
  if(!data)return "<nil>";
  long long n=msg_i64(data,"length",0); if(n<=0)return "";
  SEL bs=sel_registerName("bytes"); if(!has_sel(data,bs))return "<no-bytes>";
  using BF=const void*(*)(id,SEL); const uint8_t*p=(const uint8_t*)((BF)objc_msgSend)(data,bs); if(!p)return "<null-bytes>";
  size_t m=(size_t)n; if(m>BODY_PREVIEW_MAX)m=BODY_PREVIEW_MAX;
  std::string out; out.reserve(m);
  for(size_t i=0;i<m;++i){ unsigned char c=p[i]; out.push_back((c>=32&&c<=126)?(char)c:'.'); }
  return out;
}
static std::string task_url(id task){ id req=msg_id(task,"currentRequest"); if(!req)req=msg_id(task,"originalRequest"); return request_url(req); }

// ----- UnityWebRequestDelegate safe Objective-C hooks -----
using FDidResp=void(*)(id,SEL,id,id,id,void*);
using FHandleHTTP=void(*)(id,SEL,id,id);
using FDidData=void(*)(id,SEL,id,id,id);
using FDidComplete=void(*)(id,SEL,id,id,id);
FDidResp oDidResp=nullptr;
FHandleHTTP oHandleHTTP=nullptr;
FDidData oDidData=nullptr;
FDidComplete oDidComplete=nullptr;

static void hDidResp(id self,SEL cmd,id session,id task,id response,void*completion){
  std::string url=response_url(response); long long st=response_status(response);
  log_line("[HTTP] RESPONSE url=%s status=%lld task=%p",url.c_str(),st,(void*)task);
  oDidResp(self,cmd,session,task,response,completion);
}
static void hHandleHTTP(id self,SEL cmd,id response,id urequest){
  std::string url=request_url(urequest); long long st=response_status(response);
  log_line("[HTTP] HANDLE url=%s method=%s status=%lld urequest=%p",url.c_str(),request_method(urequest).c_str(),st,(void*)urequest);
  oHandleHTTP(self,cmd,response,urequest);
}
static void hDidData(id self,SEL cmd,id session,id task,id data){
  std::string url=task_url(task);
  if(interesting_url(url)){
    long long n=msg_i64(data,"length",0); std::string pv=data_preview(data);
    log_line("[HTTP] DATA url=%s len=%lld preview=%s",url.c_str(),n,pv.c_str());
  }
  oDidData(self,cmd,session,task,data);
}
static void hDidComplete(id self,SEL cmd,id session,id task,id error){
  std::string url=task_url(task); id rsp=msg_id(task,"response"); long long st=response_status(rsp);
  std::string err=error?ns_text(error):"<nil>";
  log_line("[HTTP] COMPLETE url=%s status=%lld error=%s task=%p",url.c_str(),st,err.c_str(),(void*)task);
  oDidComplete(self,cmd,session,task,error);
}

static int hook_objc_method(const char*clsName,const char*selName,void*replacement,void**original){
  Class c=(Class)objc_getClass(clsName); if(!c){log_line("[INSTALL] class missing %s",clsName);return -100;}
  Method m=class_getInstanceMethod(c,sel_registerName(selName)); if(!m){log_line("[INSTALL] method missing %s %s",clsName,selName);return -101;}
  void*imp=(void*)method_getImplementation(m); int rc=DobbyHook(imp,replacement,original);
  uintptr_t ub=gUnityBase.load(); uintptr_t rva=(ub&&(uintptr_t)imp>=ub)?(uintptr_t)imp-ub:0;
  log_line("[INSTALL] objc %s %s imp=%p rva=0x%llX rc=%d",clsName,selName,imp,(unsigned long long)rva,rc);
  return rc;
}

// ----- minimal stable Agent TX/RX hooks -----
using FnSend=ssize_t(*)(int,const void*,size_t,int);
using FnRecv=ssize_t(*)(int,void*,size_t,int);
FnSend oSend=nullptr; FnRecv oRecv=nullptr;
static void inspect_tx(int fd,const void*b,size_t n){
  if(!b||n<10)return; const uint8_t*p=(const uint8_t*)b; size_t sn=n<4096?n:4096;
  for(size_t off=0;off+10<=sn;++off){
    uint16_t m=be16(p+off+4); if(m!=MSG_BOOTSTRAP&&m!=MSG_ZONE_LIST)continue;
    uint32_t body=be32(p+off),seq=be32(p+off+6);
    log_line("[TX] fd=%d peer=%s off=%zu len=%zu msg=%u/0x%04X body=%u seq=%u",fd,peer_text(fd).c_str(),off,n,m,m,body,seq);
    if(m==MSG_BOOTSTRAP)gWatchUntilMs.store(now_ms()+5000ULL);
    return;
  }
}
static void inspect_rx(int fd,const void*b,size_t n){
  if(!b||n==0||!peer_is_agent(fd))return; const uint8_t*p=(const uint8_t*)b; bool watch=now_ms()<=gWatchUntilMs.load();
  size_t sn=n<4096?n:4096; bool hit=false;
  for(size_t off=0;off+10<=sn;++off){
    uint16_t m=be16(p+off+4); if(m!=MSG_BOOTSTRAP_RSP&&m!=MSG_ZONE_LIST_RSP)continue;
    log_line("[RX] fd=%d peer=%s off=%zu len=%zu msg=%u/0x%04X body=%u seq=%u",fd,peer_text(fd).c_str(),off,n,m,m,be32(p+off),be32(p+off+6)); hit=true; break;
  }
  if(watch&&!hit)log_line("[RX] WATCH fd=%d peer=%s len=%zu",fd,peer_text(fd).c_str(),n);
}
static ssize_t hSend(int fd,const void*b,size_t n,int f){ if(gDepth++==0)inspect_tx(fd,b,n); --gDepth; return oSend(fd,b,n,f); }
static ssize_t hRecv(int fd,void*b,size_t n,int f){ ssize_t r=oRecv(fd,b,n,f); if(r>0&&gDepth++==0)inspect_rx(fd,b,(size_t)r); if(r>0)--gDepth; return r; }

static void install(){
  if(gInstalled.exchange(true))return;
  uintptr_t ub=find_unity_base(); if(!ub){gInstalled.store(false);return;} gUnityBase.store(ub);
  log_line("[INSTALL] v0.6 UnityBase=%p startupWindow=%llums",(void*)ub,(unsigned long long)STARTUP_WINDOW_MS);

  hook_objc_method("UnityWebRequestDelegate","URLSession:dataTask:didReceiveResponse:completionHandler:",(void*)hDidResp,(void**)&oDidResp);
  hook_objc_method("UnityWebRequestDelegate","handleHTTPResponse:urequest:",(void*)hHandleHTTP,(void**)&oHandleHTTP);
  hook_objc_method("UnityWebRequestDelegate","URLSession:dataTask:didReceiveData:",(void*)hDidData,(void**)&oDidData);
  hook_objc_method("UnityWebRequestDelegate","URLSession:task:didCompleteWithError:",(void*)hDidComplete,(void**)&oDidComplete);

  void*s=dlsym(RTLD_DEFAULT,"send"); if(s){int rc=DobbyHook(s,(void*)hSend,(void**)&oSend);log_line("[INSTALL] send=%p rc=%d",s,rc);} else log_line("[INSTALL] send missing");
  void*r=dlsym(RTLD_DEFAULT,"recv"); if(r){int rc=DobbyHook(r,(void*)hRecv,(void**)&oRecv);log_line("[INSTALL] recv=%p rc=%d",r,rc);} else log_line("[INSTALL] recv missing");
}
static void*thread_main(void*){
  for(int i=0;i<600;++i){ if(find_unity_base()){install();return nullptr;} usleep(100000); }
  log_line("[INSTALL] timeout waiting UnityFramework"); return nullptr;
}
__attribute__((constructor)) static void entry(){
  gBootMs=now_ms(); ensure_log(); log_line("[BOOT] Login10195Diag v0.6 loaded");
  pthread_t t{}; if(pthread_create(&t,nullptr,thread_main,nullptr)==0)pthread_detach(t); else log_line("[BOOT] pthread_create failed");
}
} // namespace
