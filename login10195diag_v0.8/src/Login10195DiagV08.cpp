#include <mach-o/dyld.h>
#include <dlfcn.h>
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
std::atomic<unsigned> gCapCount{0};
int gLogFd=-1;
pthread_mutex_t gLogLock=PTHREAD_MUTEX_INITIALIZER;

static uint64_t tid_now(){uint64_t t=0;pthread_threadid_np(nullptr,&t);return t;}
static void ensure_log(){if(gLogFd>=0)return;pthread_mutex_lock(&gLogLock);if(gLogFd<0){const char*h=getenv("HOME");char p[1024];snprintf(p,sizeof(p),"%s/Documents/Login10195Diag_v0.8.log",(h&&*h)?h:"/tmp");gLogFd=open(p,O_CREAT|O_WRONLY|O_APPEND,0644);}pthread_mutex_unlock(&gLogLock);}
static void log_line(const char*fmt,...){ensure_log();if(gLogFd<0)return;timeval tv{};gettimeofday(&tv,nullptr);tm tmv{};localtime_r(&tv.tv_sec,&tmv);char pre[192];int pn=snprintf(pre,sizeof(pre),"%04d-%02d-%02d %02d:%02d:%02d.%03d [tid=%llu] ",tmv.tm_year+1900,tmv.tm_mon+1,tmv.tm_mday,tmv.tm_hour,tmv.tm_min,tmv.tm_sec,(int)(tv.tv_usec/1000),(unsigned long long)tid_now());char b[8192];va_list ap;va_start(ap,fmt);int bn=vsnprintf(b,sizeof(b),fmt,ap);va_end(ap);if(bn<0)return;if(bn>=(int)sizeof(b))bn=(int)sizeof(b)-1;pthread_mutex_lock(&gLogLock);if(pn>0)write(gLogFd,pre,pn);if(bn>0)write(gLogFd,b,bn);write(gLogFd,"\n",1);pthread_mutex_unlock(&gLogLock);}
static uintptr_t find_unity_base(){for(uint32_t i=0;i<_dyld_image_count();++i){const char*n=_dyld_get_image_name(i);if(n&&(strstr(n,"UnityFramework.framework/UnityFramework")||strstr(n,"/UnityFramework"))){auto*h=_dyld_get_image_header(i);if(h)return (uintptr_t)h;}}return 0;}
static bool has_sel(id o,SEL s){if(!o||!s)return false;Class c=object_getClass(o);return c&&class_getInstanceMethod(c,s);}
static id msg_obj(id o,const char*n){if(!o)return nullptr;SEL s=sel_registerName(n);if(!has_sel(o,s))return nullptr;using F=id(*)(id,SEL);return ((F)objc_msgSend)(o,s);}
static bool msg_bool(id o,const char*n,bool d=false){if(!o)return d;SEL s=sel_registerName(n);if(!has_sel(o,s))return d;using F=bool(*)(id,SEL);return ((F)objc_msgSend)(o,s);}
static std::string text(id o,size_t max=1800){if(!o)return "<nil>";SEL u=sel_registerName("UTF8String");if(has_sel(o,u)){using F=const char*(*)(id,SEL);const char*s=((F)objc_msgSend)(o,u);if(s){std::string x=s;if(x.size()>max)x.resize(max);return x;}}SEL d=sel_registerName("description");if(has_sel(o,d)){using G=id(*)(id,SEL);id z=((G)objc_msgSend)(o,d);if(z&&has_sel(z,u)){using F=const char*(*)(id,SEL);const char*s=((F)objc_msgSend)(z,u);if(s){std::string x=s;if(x.size()>max)x.resize(max);return x;}}}return "<unavailable>";}
static void caller(const char*tag){void*ra=__builtin_return_address(0);Dl_info di{};uintptr_t ub=gUnityBase.load();if(dladdr(ra,&di)){uintptr_t rva=(ub&&(uintptr_t)ra>=ub)?(uintptr_t)ra-ub:0;log_line("[CALLER] %s ra=%p unityRVA=0x%llX image=%s symbol=%s",tag,ra,(unsigned long long)rva,di.dli_fname?di.dli_fname:"?",di.dli_sname?di.dli_sname:"?");}else log_line("[CALLER] %s ra=%p",tag,ra);}
static int hook_objc(const char*cls,const char*sel,void*rep,void**orig){Class c=(Class)objc_getClass(cls);if(!c){log_line("[INSTALL] class missing %s",cls);return -100;}Method m=class_getInstanceMethod(c,sel_registerName(sel));if(!m){log_line("[INSTALL] method missing %s %s",cls,sel);return -101;}void*imp=(void*)method_getImplementation(m);int rc=DobbyHook(imp,rep,orig);uintptr_t ub=gUnityBase.load();uintptr_t rva=(ub&&(uintptr_t)imp>=ub)?(uintptr_t)imp-ub:0;log_line("[INSTALL] %s %s imp=%p rva=0x%llX rc=%d",cls,sel,imp,(unsigned long long)rva,rc);return rc;}

using V1=void(*)(id,SEL,id);using V2=void(*)(id,SEL,id,id);using V4=void(*)(id,SEL,id,id,id,void*);using V2B=void(*)(id,SEL,id,void*);using BInt=bool(*)(id,SEL,int);using I2=int(*)(id,SEL,id,id);

BInt oCap=nullptr;
static bool hCap(id s,SEL c,int t){bool r=oCap(s,c,t);unsigned n=gCapCount.fetch_add(1);if(n<512){log_line("[CAP] type=%d ret=%d",t,(int)r);caller("isFunctionTypeSupported");}return r;}

I2 oPayOrder=nullptr;
static int hPayOrder(id s,SEL c,id order,id role){log_line("[PAY] payOrderInfo ENTER order=%s role=%s",text(order).c_str(),text(role).c_str());caller("payOrderInfo");int r=oPayOrder(s,c,order,role);log_line("[PAY] payOrderInfo LEAVE ret=%d",r);return r;}

V1 oLoginResult=nullptr,oLogoutResult=nullptr,oPayResult=nullptr;
static void hLoginResult(id s,SEL c,id x){log_line("[ACCOUNT] channelPlatformLoginResult %s",text(x).c_str());oLoginResult(s,c,x);}
static void hLogoutResult(id s,SEL c,id x){log_line("[ACCOUNT] channelPlatformLogoutResult %s",text(x).c_str());caller("channelPlatformLogoutResult");oLogoutResult(s,c,x);}
static void hPayResult(id s,SEL c,id x){log_line("[PAY] channelPlatformPayResult %s",text(x).c_str());oPayResult(s,c,x);}

V2B oLoginVerify=nullptr,oLogoutNet=nullptr;V4 oReq=nullptr;V1 oGetPayData=nullptr;
static void hLoginVerify(id s,SEL c,id data,void*blk){log_line("[NETSDK] loginVerifyInterface data=%s",text(data,3000).c_str());caller("loginVerifyInterface");oLoginVerify(s,c,data,blk);}
static void hLogoutNet(id s,SEL c,id data,void*blk){log_line("[NETSDK] logoutWithData data=%s",text(data,3000).c_str());caller("logoutWithData");oLogoutNet(s,c,data,blk);}
static void hReq(id s,SEL c,id url,id param,id method,void*blk){std::string u=text(url,1600);if(u.find("checklogin")!=std::string::npos||u.find("logout")!=std::string::npos||u.find("order")!=std::string::npos||u.find("pay")!=std::string::npos){log_line("[NETSDK] request url=%s method=%s param=%s",u.c_str(),text(method,128).c_str(),text(param,3000).c_str());caller("requestUrlInterface");}oReq(s,c,url,param,method,blk);}
static void hGetPayData(id s,SEL c,id blk){log_line("[PAY] SDKNetworkManager getPayData");caller("getPayData");oGetPayData(s,c,blk);}

V1 oCheckLogin=nullptr,oQuickOrder=nullptr,oWillRecharge=nullptr,oWillRechargeOrdered=nullptr,oRechargeOver=nullptr;
static void hCheckLogin(id s,SEL c,id x){log_line("[ACCOUNT] PlugManager checkLoginResult=%s",text(x,3000).c_str());caller("checkLoginResult");oCheckLogin(s,c,x);}
static void hQuickOrder(id s,SEL c,id x){log_line("[PAY] PlugManager quickGetOrderResult=%s",text(x,3000).c_str());caller("quickGetOrderResult");oQuickOrder(s,c,x);}
static void hWillRecharge(id s,SEL c,id x){log_line("[PAY] PlugManager willRecharge=%s",text(x,3000).c_str());caller("willRecharge");oWillRecharge(s,c,x);}
static void hWillRechargeOrdered(id s,SEL c,id x){log_line("[PAY] PlugManager willRechargeOrdered=%s",text(x,3000).c_str());caller("willRechargeOrdered");oWillRechargeOrdered(s,c,x);}
static void hRechargeOver(id s,SEL c,id x){log_line("[PAY] PlugManager rechargeOver=%s",text(x,3000).c_str());oRechargeOver(s,c,x);}

static void snapshot(){Class cc=(Class)objc_getClass("SDKCooperater");Class mc=cc?object_getClass((id)cc):nullptr;id coop=nullptr;if(mc&&class_getInstanceMethod(mc,sel_registerName("shareCooperater"))){using F=id(*)(id,SEL);coop=((F)objc_msgSend)((id)cc,sel_registerName("shareCooperater"));}Class sc=(Class)objc_getClass("SMPCQuickSDK");Class sm=sc?object_getClass((id)sc):nullptr;id sdk=nullptr;if(sm&&class_getInstanceMethod(sm,sel_registerName("defaultInstance"))){using F=id(*)(id,SEL);sdk=((F)objc_msgSend)((id)sc,sel_registerName("defaultInstance"));}log_line("[STATE] init=%d logout=%d callLogin=%d uid=%s token=%s",coop?msg_bool(coop,"isInitSuccess",false):-1,coop?msg_bool(coop,"isLogout",false):-1,coop?msg_bool(coop,"isCallLogin",false):-1,sdk?text(msg_obj(sdk,"userId"),256).c_str():"<nil>",sdk?text(msg_obj(sdk,"userToken"),256).c_str():"<nil>");}

static void install(){if(gInstalled.exchange(true))return;uintptr_t ub=find_unity_base();if(!ub){gInstalled.store(false);return;}gUnityBase.store(ub);log_line("[BOOT] Login10195Diag v0.8 UnityBase=%p",(void*)ub);
 hook_objc("SMPCQuickSDK","isFunctionTypeSupported:",(void*)hCap,(void**)&oCap);
 hook_objc("SMPCQuickSDK","payOrderInfo:roleInfo:",(void*)hPayOrder,(void**)&oPayOrder);
 hook_objc("SDKCooperater","channelPlatformLoginResult:",(void*)hLoginResult,(void**)&oLoginResult);
 hook_objc("SDKCooperater","channelPlatformLogoutResult:",(void*)hLogoutResult,(void**)&oLogoutResult);
 hook_objc("SDKCooperater","channelPlatformPayResult:",(void*)hPayResult,(void**)&oPayResult);
 hook_objc("SDKNetworkManager","loginVerifyInterface:handler:",(void*)hLoginVerify,(void**)&oLoginVerify);
 hook_objc("SDKNetworkManager","logoutWithData:handler:",(void*)hLogoutNet,(void**)&oLogoutNet);
 hook_objc("SDKNetworkManager","requestUrlInterface:param:method:completionBlock:",(void*)hReq,(void**)&oReq);
 hook_objc("SDKNetworkManager","getPayData:",(void*)hGetPayData,(void**)&oGetPayData);
 hook_objc("PlugManager","checkLoginResult:",(void*)hCheckLogin,(void**)&oCheckLogin);
 hook_objc("PlugManager","quickGetOrderResult:",(void*)hQuickOrder,(void**)&oQuickOrder);
 hook_objc("PlugManager","willRecharge:",(void*)hWillRecharge,(void**)&oWillRecharge);
 hook_objc("PlugManager","willRechargeOrdered:",(void*)hWillRechargeOrdered,(void**)&oWillRechargeOrdered);
 hook_objc("PlugManager","rechargeOver:",(void*)hRechargeOver,(void**)&oRechargeOver);
 snapshot();}
static void*thread_main(void*){for(int i=0;i<600;++i){if(find_unity_base()){install();return nullptr;}usleep(100000);}log_line("[INSTALL] timeout");return nullptr;}
__attribute__((constructor)) static void entry(){ensure_log();log_line("[BOOT] Login10195Diag v0.8 loaded");pthread_t t{};if(pthread_create(&t,nullptr,thread_main,nullptr)==0)pthread_detach(t);}
}