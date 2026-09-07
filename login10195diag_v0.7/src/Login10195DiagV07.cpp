#include <mach-o/dyld.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <atomic>
#include <string>
#include <objc/runtime.h>
#include <objc/message.h>
#include "dobby.h"

namespace {
std::atomic<bool> gInstalled{false};
std::atomic<uintptr_t> gUnityBase{0};
std::atomic<unsigned> gCapabilityCalls{0};
int gLogFd=-1;
pthread_mutex_t gLogLock=PTHREAD_MUTEX_INITIALIZER;

static uint64_t tid_now(){ uint64_t t=0; pthread_threadid_np(nullptr,&t); return t; }
static void ensure_log(){
  if(gLogFd>=0)return;
  pthread_mutex_lock(&gLogLock);
  if(gLogFd<0){ const char*home=getenv("HOME"); char p[1024]; snprintf(p,sizeof(p),"%s/Documents/Login10195Diag_v0.7.log",(home&&*home)?home:"/tmp"); gLogFd=open(p,O_CREAT|O_WRONLY|O_APPEND,0644); }
  pthread_mutex_unlock(&gLogLock);
}
static void log_line(const char*fmt,...){
  ensure_log(); if(gLogFd<0)return;
  timeval tv{}; gettimeofday(&tv,nullptr); tm tmv{}; localtime_r(&tv.tv_sec,&tmv);
  char pre[192]; int pn=snprintf(pre,sizeof(pre),"%04d-%02d-%02d %02d:%02d:%02d.%03d [tid=%llu] ",tmv.tm_year+1900,tmv.tm_mon+1,tmv.tm_mday,tmv.tm_hour,tmv.tm_min,tmv.tm_sec,(int)(tv.tv_usec/1000),(unsigned long long)tid_now());
  char body[8192]; va_list ap; va_start(ap,fmt); int bn=vsnprintf(body,sizeof(body),fmt,ap); va_end(ap); if(bn<0)return; if(bn>=(int)sizeof(body))bn=(int)sizeof(body)-1;
  pthread_mutex_lock(&gLogLock); if(pn>0)write(gLogFd,pre,(size_t)pn); if(bn>0)write(gLogFd,body,(size_t)bn); write(gLogFd,"\n",1); pthread_mutex_unlock(&gLogLock);
}
static uintptr_t find_unity_base(){ for(uint32_t i=0;i<_dyld_image_count();++i){ const char*n=_dyld_get_image_name(i); if(!n)continue; if(strstr(n,"UnityFramework.framework/UnityFramework")||strstr(n,"/UnityFramework")){ auto*h=_dyld_get_image_header(i); if(h)return (uintptr_t)h; }} return 0; }

static bool has_sel(id o,SEL s){ if(!o||!s)return false; Class c=object_getClass(o); return c&&class_getInstanceMethod(c,s); }
static id msg_obj(id o,const char*name){ if(!o)return nullptr; SEL s=sel_registerName(name); if(!has_sel(o,s))return nullptr; using F=id(*)(id,SEL); return ((F)objc_msgSend)(o,s); }
static long long msg_i64(id o,const char*name,long long def=-1){ if(!o)return def; SEL s=sel_registerName(name); if(!has_sel(o,s))return def; using F=long long(*)(id,SEL); return ((F)objc_msgSend)(o,s); }
static bool msg_bool(id o,const char*name,bool def=false){ if(!o)return def; SEL s=sel_registerName(name); if(!has_sel(o,s))return def; using F=bool(*)(id,SEL); return ((F)objc_msgSend)(o,s); }
static id class_obj(const char*cls,const char*sel){ Class c=(Class)objc_getClass(cls); if(!c)return nullptr; SEL s=sel_registerName(sel); Class mc=object_getClass((id)c); if(!mc||!class_getInstanceMethod(mc,s))return nullptr; using F=id(*)(id,SEL); return ((F)objc_msgSend)((id)c,s); }
static std::string ns_text(id o){
  if(!o)return "<nil>";
  SEL u=sel_registerName("UTF8String"); if(has_sel(o,u)){ using F=const char*(*)(id,SEL); const char*s=((F)objc_msgSend)(o,u); if(s)return std::string(s); }
  SEL d=sel_registerName("description"); if(has_sel(o,d)){ using G=id(*)(id,SEL); id z=((G)objc_msgSend)(o,d); if(z&&has_sel(z,u)){ using F=const char*(*)(id,SEL); const char*s=((F)objc_msgSend)(z,u); if(s)return std::string(s); }}
  return "<unavailable>";
}
static std::string short_text(id o,size_t max=1800){ std::string s=ns_text(o); if(s.size()>max){s.resize(max);s+="...";} return s; }
static std::string mask_token(const std::string&s){ if(s.empty()||s=="<nil>"||s=="<unavailable>")return s; if(s.size()<=8)return std::string("<len=")+std::to_string(s.size())+">"; return s.substr(0,4)+"..."+s.substr(s.size()-4)+"(len="+std::to_string(s.size())+")"; }
static id ivar_obj(id o,const char*n1,const char*n2=nullptr){ if(!o)return nullptr; Class c=object_getClass(o); Ivar iv=class_getInstanceVariable(c,n1); if(!iv&&n2)iv=class_getInstanceVariable(c,n2); return iv?object_getIvar(o,iv):nullptr; }

static void snapshot(const char*reason){
  id coop=class_obj("SDKCooperater","shareCooperater");
  id sdk=class_obj("SMPCQuickSDK","defaultInstance");
  id ch=class_obj("SMPCQuickChannel","defaultChannel");
  id pm=class_obj("PlugManager","sharedInstance");
  id cc=class_obj("SMPCQuickChannelCooperater","sharedInstance");

  std::string uid=sdk?short_text(msg_obj(sdk,"userId"),256):"<no-sdk>";
  std::string nick=sdk?short_text(msg_obj(sdk,"userNick"),256):"<no-sdk>";
  std::string tok=sdk?mask_token(short_text(msg_obj(sdk,"userToken"),2048)):"<no-sdk>";
  std::string cname=sdk?short_text(msg_obj(sdk,"channelName"),256):"<no-sdk>";
  long long ctype=sdk?msg_i64(sdk,"channelType",-1):-1;
  std::string cver=sdk?short_text(msg_obj(sdk,"channelVersion"),256):"<no-sdk>";

  std::string chUid=ch?short_text(msg_obj(ch,"userId"),256):"<no-channel>";
  std::string chNick=ch?short_text(msg_obj(ch,"userNick"),256):"<no-channel>";
  std::string sid=ch?mask_token(short_text(msg_obj(ch,"sessionId"),2048)):"<no-channel>";
  id unsupported=ch?ivar_obj(ch,"unsupportedFunctionList","_unsupportedFunctionList"):nullptr;

  log_line("[STATE] reason=%s init=%d logout=%d callLogin=%d channel=%s type=%lld ver=%s sdkUid=%s sdkNick=%s token=%s chUid=%s chNick=%s sid=%s unsupported=%s plugins=%s coopLogin=%d coopUid=%s",
           reason,
           coop?msg_bool(coop,"isInitSuccess",false):-1,
           coop?msg_bool(coop,"isLogout",false):-1,
           coop?msg_bool(coop,"isCallLogin",false):-1,
           cname.c_str(),ctype,cver.c_str(),uid.c_str(),nick.c_str(),tok.c_str(),chUid.c_str(),chNick.c_str(),sid.c_str(),
           short_text(unsupported,1600).c_str(),
           pm?short_text(msg_obj(pm,"pluginsInfo"),1600).c_str():"<no-pm>",
           cc?msg_bool(cc,"isLogin",false):-1,
           cc?short_text(msg_obj(cc,"userId"),256).c_str():"<no-cc>");
}

static int hook_objc(const char*cls,const char*sel,void*rep,void**orig){
  Class c=(Class)objc_getClass(cls); if(!c){log_line("[INSTALL] class missing %s",cls);return -100;}
  Method m=class_getInstanceMethod(c,sel_registerName(sel)); if(!m){log_line("[INSTALL] method missing %s %s",cls,sel);return -101;}
  void*imp=(void*)method_getImplementation(m); int rc=DobbyHook(imp,rep,orig); uintptr_t ub=gUnityBase.load(); uintptr_t rva=(ub&&(uintptr_t)imp>=ub)?(uintptr_t)imp-ub:0;
  log_line("[INSTALL] %s %s imp=%p rva=0x%llX rc=%d",cls,sel,imp,(unsigned long long)rva,rc); return rc;
}

// SDKCooperater
using V0=void(*)(id,SEL); using V1=void(*)(id,SEL,id); using I0=int(*)(id,SEL); using I2=int(*)(id,SEL,id,id); using BInt=bool(*)(id,SEL,int); using Q0=long long(*)(id,SEL); using Q3=long long(*)(id,SEL,id,id,id);
V0 oBeginInit=nullptr; V1 oInitRes=nullptr,oLoginRes=nullptr,oLogoutRes=nullptr,oPayRes=nullptr;
static void hBeginInit(id s,SEL c){ log_line("[SDK] beginQuickSDKInit ENTER"); oBeginInit(s,c); log_line("[SDK] beginQuickSDKInit LEAVE"); snapshot("beginInit.leave"); }
static void hInitRes(id s,SEL c,id x){ log_line("[SDK] channelPlatformInitResult info=%s",short_text(x).c_str()); oInitRes(s,c,x); snapshot("initResult"); }
static void hLoginRes(id s,SEL c,id x){ log_line("[SDK] channelPlatformLoginResult info=%s",short_text(x).c_str()); oLoginRes(s,c,x); snapshot("loginResult"); }
static void hLogoutRes(id s,SEL c,id x){ log_line("[ACCOUNT] channelPlatformLogoutResult info=%s",short_text(x).c_str()); oLogoutRes(s,c,x); snapshot("logoutResult"); }
static void hPayRes(id s,SEL c,id x){ log_line("[PAY] channelPlatformPayResult info=%s",short_text(x).c_str()); oPayRes(s,c,x); snapshot("payResult"); }

// SMPCQuickSDK
I0 oSDKLogin=nullptr,oSDKLogout=nullptr,oEnterUserCenter=nullptr; BInt oCap=nullptr; I2 oPayOrder=nullptr;
static int hSDKLogin(id s,SEL c){ log_line("[SDK] SMPCQuickSDK login ENTER"); int r=oSDKLogin(s,c); log_line("[SDK] SMPCQuickSDK login LEAVE ret=%d",r); snapshot("sdk.login"); return r; }
static int hSDKLogout(id s,SEL c){ log_line("[ACCOUNT] SMPCQuickSDK logout ENTER"); int r=oSDKLogout(s,c); log_line("[ACCOUNT] SMPCQuickSDK logout LEAVE ret=%d",r); snapshot("sdk.logout"); return r; }
static int hEnterUserCenter(id s,SEL c){ log_line("[ACCOUNT] enterUserCenter ENTER"); int r=oEnterUserCenter(s,c); log_line("[ACCOUNT] enterUserCenter LEAVE ret=%d",r); return r; }
static bool hCap(id s,SEL c,int t){ bool r=oCap(s,c,t); unsigned n=gCapabilityCalls.fetch_add(1); if(n<256)log_line("[CAP] isFunctionTypeSupported type=%d ret=%d",t,(int)r); return r; }
static int hPayOrder(id s,SEL c,id order,id role){ log_line("[PAY] payOrderInfo ENTER order=%s role=%s",short_text(order).c_str(),short_text(role).c_str()); int r=oPayOrder(s,c,order,role); log_line("[PAY] payOrderInfo LEAVE ret=%d",r); snapshot("payOrder.leave"); return r; }

// PlugManager
V0 oPMStart=nullptr; V1 oPMInitDone=nullptr,oPMLoginDone=nullptr,oPMWillRecharge=nullptr,oPMRechargeOver=nullptr,oPMCheckLogin=nullptr;
static void hPMStart(id s,SEL c){ log_line("[PLUG] startManager ENTER"); oPMStart(s,c); log_line("[PLUG] startManager LEAVE plugins=%s",short_text(msg_obj(s,"pluginsInfo"),1800).c_str()); }
#define HOOK_V1_WRAPPER(fn,orig,tag) static void fn(id s,SEL c,id x){ log_line(tag " info=%s",short_text(x).c_str()); orig(s,c,x); snapshot(tag); }
HOOK_V1_WRAPPER(hPMInitDone,oPMInitDone,"[PLUG] initDone")
HOOK_V1_WRAPPER(hPMLoginDone,oPMLoginDone,"[PLUG] loginDone")
HOOK_V1_WRAPPER(hPMWillRecharge,oPMWillRecharge,"[PAY] willRecharge")
HOOK_V1_WRAPPER(hPMRechargeOver,oPMRechargeOver,"[PAY] rechargeOver")
HOOK_V1_WRAPPER(hPMCheckLogin,oPMCheckLogin,"[PLUG] checkLoginResult")

// SMPCQuickChannel
Q0 oCHLogin=nullptr,oCHLogout=nullptr; V1 oCHLoginCB=nullptr,oCHLogoutCB=nullptr,oCHPayCB=nullptr; Q3 oCHBuy=nullptr;
static long long hCHLogin(id s,SEL c){ log_line("[CHANNEL] login ENTER"); auto r=oCHLogin(s,c); log_line("[CHANNEL] login LEAVE ret=%lld",r); return r; }
static void hCHLoginCB(id s,SEL c,id x){ log_line("[CHANNEL] loginCallBack info=%s",short_text(x).c_str()); oCHLoginCB(s,c,x); snapshot("channel.loginCB"); }
static long long hCHLogout(id s,SEL c){ log_line("[ACCOUNT] channel logout ENTER"); auto r=oCHLogout(s,c); log_line("[ACCOUNT] channel logout LEAVE ret=%lld",r); return r; }
static void hCHLogoutCB(id s,SEL c,id x){ log_line("[ACCOUNT] channel logoutCallBack info=%s",short_text(x).c_str()); oCHLogoutCB(s,c,x); snapshot("channel.logoutCB"); }
static long long hCHBuy(id s,SEL c,id oid,id product,id role){ log_line("[PAY] channel buyOrder ENTER oid=%s product=%s role=%s",short_text(oid).c_str(),short_text(product).c_str(),short_text(role).c_str()); auto r=oCHBuy(s,c,oid,product,role); log_line("[PAY] channel buyOrder LEAVE ret=%lld",r); return r; }
static void hCHPayCB(id s,SEL c,id x){ log_line("[PAY] channel payCallBack info=%s",short_text(x).c_str()); oCHPayCB(s,c,x); snapshot("channel.payCB"); }

// SDKNetworkManager request starts
using Net2=void(*)(id,SEL,id,void*); using Net4=void(*)(id,SEL,id,id,id,void*);
Net2 oLoginVerify=nullptr,oLogoutNet=nullptr; Net4 oReqURL=nullptr,oTimerReq=nullptr;
static void hLoginVerify(id s,SEL c,id data,void*blk){ log_line("[NETSDK] loginVerifyInterface data=%s",short_text(data).c_str()); oLoginVerify(s,c,data,blk); }
static void hLogoutNet(id s,SEL c,id data,void*blk){ log_line("[NETSDK] logoutWithData data=%s",short_text(data).c_str()); oLogoutNet(s,c,data,blk); }
static void hReqURL(id s,SEL c,id url,id param,id method,void*blk){ log_line("[NETSDK] requestUrl url=%s method=%s param=%s",short_text(url,1024).c_str(),short_text(method,128).c_str(),short_text(param,1800).c_str()); oReqURL(s,c,url,param,method,blk); }
static void hTimerReq(id s,SEL c,id url,id param,id method,void*blk){ log_line("[NETSDK] timerRequest url=%s method=%s param=%s",short_text(url,1024).c_str(),short_text(method,128).c_str(),short_text(param,1800).c_str()); oTimerReq(s,c,url,param,method,blk); }

// Channel cooperater + game bridge result callbacks
V1 oCCInit=nullptr,oCCLoginOK=nullptr,oCCLoginFail=nullptr,oCCLogout=nullptr,oCCPayOK=nullptr,oCCPayFail=nullptr;
HOOK_V1_WRAPPER(hCCInit,oCCInit,"[CHANNELCOOP] initSuccess")
HOOK_V1_WRAPPER(hCCLoginOK,oCCLoginOK,"[CHANNELCOOP] loginSuccess")
HOOK_V1_WRAPPER(hCCLoginFail,oCCLoginFail,"[CHANNELCOOP] loginFail")
HOOK_V1_WRAPPER(hCCLogout,oCCLogout,"[ACCOUNT] channelCoop logoutSuccess")
HOOK_V1_WRAPPER(hCCPayOK,oCCPayOK,"[PAY] channelCoop paySuccess")
HOOK_V1_WRAPPER(hCCPayFail,oCCPayFail,"[PAY] channelCoop payFail")

V1 oDMInit=nullptr,oDMLogin=nullptr,oDMLogout=nullptr,oCAInit=nullptr,oCALogin=nullptr,oCALogout=nullptr,oCAPay=nullptr;
HOOK_V1_WRAPPER(hDMInit,oDMInit,"[GAMEBRIDGE] DeliberateMain initResult")
HOOK_V1_WRAPPER(hDMLogin,oDMLogin,"[GAMEBRIDGE] DeliberateMain loginResult")
HOOK_V1_WRAPPER(hDMLogout,oDMLogout,"[ACCOUNT] DeliberateMain logoutResult")
HOOK_V1_WRAPPER(hCAInit,oCAInit,"[GAMEBRIDGE] AppController initResult")
HOOK_V1_WRAPPER(hCALogin,oCALogin,"[GAMEBRIDGE] AppController loginResult")
HOOK_V1_WRAPPER(hCALogout,oCALogout,"[ACCOUNT] AppController logoutResult")
HOOK_V1_WRAPPER(hCAPay,oCAPay,"[PAY] AppController rechargeResult")

static void capability_snapshot(){
  id sdk=class_obj("SMPCQuickSDK","defaultInstance"); if(!sdk)return; SEL s=sel_registerName("isFunctionTypeSupported:"); if(!has_sel(sdk,s))return; using F=bool(*)(id,SEL,int); F f=(F)objc_msgSend;
  std::string line; for(int i=0;i<=32;++i){ bool r=f(sdk,s,i); char b[32]; snprintf(b,sizeof(b),"%d:%d ",i,(int)r); line+=b; } log_line("[CAP] initial map %s",line.c_str());
}
static void*monitor_thread(void*){
  std::string last;
  for(int i=0;i<180;++i){ sleep(2); id sdk=class_obj("SMPCQuickSDK","defaultInstance"); id ch=class_obj("SMPCQuickChannel","defaultChannel"); id coop=class_obj("SDKCooperater","shareCooperater");
    std::string cur=(sdk?short_text(msg_obj(sdk,"userId"),256):"")+"|"+(ch?short_text(msg_obj(ch,"userId"),256):"")+"|"+(ch?mask_token(short_text(msg_obj(ch,"sessionId"),1024)):"")+"|"+(coop?(msg_bool(coop,"isInitSuccess",false)?"1":"0"):"x")+"|"+(coop?(msg_bool(coop,"isLogout",false)?"1":"0"):"x");
    if(cur!=last){ last=cur; snapshot("monitor.change"); }
  }
  return nullptr;
}

static void install(){
  if(gInstalled.exchange(true))return; uintptr_t ub=find_unity_base(); if(!ub){gInstalled.store(false);return;} gUnityBase.store(ub); log_line("[INSTALL] Login10195Diag v0.7 UnityBase=%p",(void*)ub);

  hook_objc("SDKCooperater","beginQuickSDKInit",(void*)hBeginInit,(void**)&oBeginInit);
  hook_objc("SDKCooperater","channelPlatformInitResult:",(void*)hInitRes,(void**)&oInitRes);
  hook_objc("SDKCooperater","channelPlatformLoginResult:",(void*)hLoginRes,(void**)&oLoginRes);
  hook_objc("SDKCooperater","channelPlatformLogoutResult:",(void*)hLogoutRes,(void**)&oLogoutRes);
  hook_objc("SDKCooperater","channelPlatformPayResult:",(void*)hPayRes,(void**)&oPayRes);

  hook_objc("SMPCQuickSDK","login",(void*)hSDKLogin,(void**)&oSDKLogin);
  hook_objc("SMPCQuickSDK","logout",(void*)hSDKLogout,(void**)&oSDKLogout);
  hook_objc("SMPCQuickSDK","enterUserCenter",(void*)hEnterUserCenter,(void**)&oEnterUserCenter);
  hook_objc("SMPCQuickSDK","isFunctionTypeSupported:",(void*)hCap,(void**)&oCap);
  hook_objc("SMPCQuickSDK","payOrderInfo:roleInfo:",(void*)hPayOrder,(void**)&oPayOrder);

  hook_objc("PlugManager","startManager",(void*)hPMStart,(void**)&oPMStart);
  hook_objc("PlugManager","initDone:",(void*)hPMInitDone,(void**)&oPMInitDone);
  hook_objc("PlugManager","loginDone:",(void*)hPMLoginDone,(void**)&oPMLoginDone);
  hook_objc("PlugManager","willRecharge:",(void*)hPMWillRecharge,(void**)&oPMWillRecharge);
  hook_objc("PlugManager","rechargeOver:",(void*)hPMRechargeOver,(void**)&oPMRechargeOver);
  hook_objc("PlugManager","checkLoginResult:",(void*)hPMCheckLogin,(void**)&oPMCheckLogin);

  hook_objc("SMPCQuickChannel","login",(void*)hCHLogin,(void**)&oCHLogin);
  hook_objc("SMPCQuickChannel","loginCallBack:",(void*)hCHLoginCB,(void**)&oCHLoginCB);
  hook_objc("SMPCQuickChannel","logout",(void*)hCHLogout,(void**)&oCHLogout);
  hook_objc("SMPCQuickChannel","logoutCallBack:",(void*)hCHLogoutCB,(void**)&oCHLogoutCB);
  hook_objc("SMPCQuickChannel","buyOrderId:productInfo:roleInfo:",(void*)hCHBuy,(void**)&oCHBuy);
  hook_objc("SMPCQuickChannel","payCallBack:",(void*)hCHPayCB,(void**)&oCHPayCB);

  hook_objc("SDKNetworkManager","loginVerifyInterface:handler:",(void*)hLoginVerify,(void**)&oLoginVerify);
  hook_objc("SDKNetworkManager","logoutWithData:handler:",(void*)hLogoutNet,(void**)&oLogoutNet);
  hook_objc("SDKNetworkManager","requestUrlInterface:param:method:completionBlock:",(void*)hReqURL,(void**)&oReqURL);
  hook_objc("SDKNetworkManager","timerRequestUrlInterface:param:method:completionBlock:",(void*)hTimerReq,(void**)&oTimerReq);

  hook_objc("SMPCQuickChannelCooperater","initSuccess:",(void*)hCCInit,(void**)&oCCInit);
  hook_objc("SMPCQuickChannelCooperater","loginSuccess:",(void*)hCCLoginOK,(void**)&oCCLoginOK);
  hook_objc("SMPCQuickChannelCooperater","loginFail:",(void*)hCCLoginFail,(void**)&oCCLoginFail);
  hook_objc("SMPCQuickChannelCooperater","logoutSuccess:",(void*)hCCLogout,(void**)&oCCLogout);
  hook_objc("SMPCQuickChannelCooperater","paySuccess:",(void*)hCCPayOK,(void**)&oCCPayOK);
  hook_objc("SMPCQuickChannelCooperater","payFail:",(void*)hCCPayFail,(void**)&oCCPayFail);

  hook_objc("DeliberateMain","smpcQpInitResult:",(void*)hDMInit,(void**)&oDMInit);
  hook_objc("DeliberateMain","smpcQpLoginResult:",(void*)hDMLogin,(void**)&oDMLogin);
  hook_objc("DeliberateMain","smpcQpLogoutResult:",(void*)hDMLogout,(void**)&oDMLogout);
  hook_objc("CustomAppController","smpcQpInitResult:",(void*)hCAInit,(void**)&oCAInit);
  hook_objc("CustomAppController","smpcQpLoginResult:",(void*)hCALogin,(void**)&oCALogin);
  hook_objc("CustomAppController","smpcQpLogoutResult:",(void*)hCALogout,(void**)&oCALogout);
  hook_objc("CustomAppController","smpcQpRechargeResult:",(void*)hCAPay,(void**)&oCAPay);

  snapshot("install"); capability_snapshot();
  pthread_t m{}; if(pthread_create(&m,nullptr,monitor_thread,nullptr)==0)pthread_detach(m);
}
static void*wait_thread(void*){ for(int i=0;i<600;++i){ if(find_unity_base()){ install(); return nullptr; } usleep(100000); } log_line("[INSTALL] timeout waiting UnityFramework"); return nullptr; }
__attribute__((constructor)) static void entry(){ ensure_log(); log_line("[BOOT] Login10195Diag v0.7 SDK/Account/Pay probe loaded"); pthread_t t{}; if(pthread_create(&t,nullptr,wait_thread,nullptr)==0)pthread_detach(t); else log_line("[BOOT] pthread_create failed"); }
} // namespace
