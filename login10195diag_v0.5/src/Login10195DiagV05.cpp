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
#include "dobby.h"

namespace {
constexpr uintptr_t RVAS[] = {
  0x01137C04,
  0x01137EA4,
  0x01138FB0,
  0x01148A58,
  0x01148C80,
};
constexpr size_t RVA_COUNT = sizeof(RVAS)/sizeof(RVAS[0]);
constexpr uint16_t MSG_BOOTSTRAP = 0x2713;
constexpr uint16_t MSG_ZONE_LIST = 0x27D3;

std::atomic<uintptr_t> gUnityBase{0};
std::atomic<bool> gInstalled{false};
int gLogFd = -1;
pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
thread_local int gDepth = 0;

using FnSend = ssize_t(*)(int,const void*,size_t,int);
FnSend orig_Send = nullptr;

static uint64_t tid_now(){ uint64_t t=0; pthread_threadid_np(nullptr,&t); return t; }
static void ensure_log(){
  if(gLogFd>=0) return;
  pthread_mutex_lock(&gLogLock);
  if(gLogFd<0){
    const char*home=getenv("HOME"); char p[1024];
    snprintf(p,sizeof(p),"%s/Documents/Login10195Diag_v0.5.log",(home&&*home)?home:"/tmp");
    gLogFd=open(p,O_CREAT|O_WRONLY|O_APPEND,0644);
  }
  pthread_mutex_unlock(&gLogLock);
}
static void log_line(const char*fmt,...){
  ensure_log(); if(gLogFd<0) return;
  timeval tv{}; gettimeofday(&tv,nullptr); tm tmv{}; localtime_r(&tv.tv_sec,&tmv);
  char pre[192]; int pn=snprintf(pre,sizeof(pre),"%04d-%02d-%02d %02d:%02d:%02d.%03d [tid=%llu] ",tmv.tm_year+1900,tmv.tm_mon+1,tmv.tm_mday,tmv.tm_hour,tmv.tm_min,tmv.tm_sec,(int)(tv.tv_usec/1000),(unsigned long long)tid_now());
  char body[4096]; va_list ap; va_start(ap,fmt); int bn=vsnprintf(body,sizeof(body),fmt,ap); va_end(ap); if(bn<0)return; if(bn>=(int)sizeof(body))bn=(int)sizeof(body)-1;
  pthread_mutex_lock(&gLogLock);
  if(pn>0) write(gLogFd,pre,(size_t)pn);
  if(bn>0) write(gLogFd,body,(size_t)bn);
  write(gLogFd,"\n",1); fsync(gLogFd);
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
static std::string peer_text(int fd){
  sockaddr_storage ss{}; socklen_t sl=sizeof(ss);
  if(getpeername(fd,(sockaddr*)&ss,&sl)!=0) return "<not-socket>";
  char ip[INET6_ADDRSTRLEN]{}; uint16_t p=0;
  if(ss.ss_family==AF_INET){auto*a=(sockaddr_in*)&ss;inet_ntop(AF_INET,&a->sin_addr,ip,sizeof(ip));p=ntohs(a->sin_port);}
  else if(ss.ss_family==AF_INET6){auto*a=(sockaddr_in6*)&ss;inet_ntop(AF_INET6,&a->sin6_addr,ip,sizeof(ip));p=ntohs(a->sin6_port);}
  else return "<non-ip>";
  char out[160]; snprintf(out,sizeof(out),"%s:%u",ip,p); return out;
}
static uint16_t be16(const uint8_t*p){return (uint16_t)(((uint16_t)p[0]<<8)|p[1]);}
static uint32_t be32(const uint8_t*p){return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];}

static const char* tag_for(uintptr_t r){
  switch(r){
    case 0x01137C04:return "P1137C04";
    case 0x01137EA4:return "P1137EA4";
    case 0x01138FB0:return "P1138FB0";
    case 0x01148A58:return "P1148A58";
    case 0x01148C80:return "P1148C80";
    default:return "PUNKNOWN";
  }
}

static void probe_cb(void*address,DobbyRegisterContext*ctx){
  if(!ctx) return;
  uintptr_t ub=gUnityBase.load(); uintptr_t pc=(uintptr_t)address; uintptr_t rva=(ub&&pc>=ub)?pc-ub:0;
  log_line("[%s] HIT pc=%p rva=0x%llX lr=0x%llX lrRVA=0x%llX sp=0x%llX fp=0x%llX x0=0x%llX x1=0x%llX x2=0x%llX x3=0x%llX x4=0x%llX x5=0x%llX x6=0x%llX x7=0x%llX",
    tag_for(rva),address,(unsigned long long)rva,(unsigned long long)ctx->lr,
    (unsigned long long)((ub&&ctx->lr>=ub)?ctx->lr-ub:0),
    (unsigned long long)ctx->sp,(unsigned long long)ctx->fp,
    (unsigned long long)ctx->general.regs.x0,(unsigned long long)ctx->general.regs.x1,
    (unsigned long long)ctx->general.regs.x2,(unsigned long long)ctx->general.regs.x3,
    (unsigned long long)ctx->general.regs.x4,(unsigned long long)ctx->general.regs.x5,
    (unsigned long long)ctx->general.regs.x6,(unsigned long long)ctx->general.regs.x7);
}

static ssize_t hook_send(int fd,const void*b,size_t n,int f){
  if(gDepth++==0 && b && n>=10){
    const uint8_t*p=(const uint8_t*)b; size_t sn=n<4096?n:4096;
    for(size_t off=0;off+10<=sn;++off){
      uint16_t m=be16(p+off+4); if(m!=MSG_BOOTSTRAP&&m!=MSG_ZONE_LIST) continue;
      uint32_t body=be32(p+off), seq=be32(p+off+6);
      log_line("[TX] fd=%d peer=%s off=%zu len=%zu msg=%u/0x%04X body=%u seq=%u caller=%p callerRVA=0x%llX",
        fd,peer_text(fd).c_str(),off,n,m,m,body,seq,__builtin_return_address(0),
        (unsigned long long)((gUnityBase.load()&&(uintptr_t)__builtin_return_address(0)>=gUnityBase.load())?((uintptr_t)__builtin_return_address(0)-gUnityBase.load()):0));
      break;
    }
  }
  --gDepth;
  return orig_Send(fd,b,n,f);
}

static void install(){
  if(gInstalled.exchange(true)) return;
  uintptr_t ub=find_unity_base(); if(!ub){gInstalled.store(false);return;} gUnityBase.store(ub);
  log_line("[INSTALL] v0.5 UnityBase=%p",(void*)ub);
  for(size_t i=0;i<RVA_COUNT;++i){
    void*addr=(void*)(ub+RVAS[i]); int rc=DobbyInstrument(addr,probe_cb);
    log_line("[INSTALL] instrument rva=0x%llX addr=%p rc=%d",(unsigned long long)RVAS[i],addr,rc);
  }
  void*s=dlsym(RTLD_DEFAULT,"send");
  if(s){int rc=DobbyHook(s,(void*)hook_send,(void**)&orig_Send);log_line("[INSTALL] send=%p rc=%d",s,rc);} else log_line("[INSTALL] send symbol missing");
}
static void*thread_main(void*){
  for(int i=0;i<600;++i){if(find_unity_base()){install();return nullptr;}usleep(100000);} log_line("[INSTALL] timeout waiting UnityFramework"); return nullptr;
}
__attribute__((constructor)) static void entry(){ensure_log();log_line("[BOOT] Login10195Diag v0.5 loaded");pthread_t t{};if(pthread_create(&t,nullptr,thread_main,nullptr)==0)pthread_detach(t);else log_line("[BOOT] pthread_create failed");}
} // namespace
