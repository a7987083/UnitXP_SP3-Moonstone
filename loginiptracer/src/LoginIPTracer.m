#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


typedef unsigned long size_t_hfa;
typedef unsigned long long u64;
typedef signed char BOOL;
typedef struct objc_object* id;
typedef struct objc_class* Class;
typedef struct objc_selector* SEL;
typedef void(*IMP)(void);
typedef struct { double x,y; } CGPoint;
typedef struct { double width,height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;

extern Class objc_getClass(const char*);
extern SEL sel_registerName(const char*);
extern void objc_msgSend(void);
extern Class objc_allocateClassPair(Class,const char*,size_t_hfa);
extern BOOL class_addMethod(Class,SEL,IMP,const char*);
extern void objc_registerClassPair(Class);

#define M0(r,o,s) ((r(*)(id,SEL))objc_msgSend)((id)(o),sel_registerName(s))
#define M1(r,o,s,t,a) ((r(*)(id,SEL,t))objc_msgSend)((id)(o),sel_registerName(s),(a))
#define M2(r,o,s,t,a,u,b) ((r(*)(id,SEL,t,u))objc_msgSend)((id)(o),sel_registerName(s),(a),(b))
#define M3(r,o,s,t,a,u,b,v,c) ((r(*)(id,SEL,t,u,v))objc_msgSend)((id)(o),sel_registerName(s),(a),(b),(c))
#define M4(r,o,s,t,a,u,b,v,c,w,d) ((r(*)(id,SEL,t,u,v,w))objc_msgSend)((id)(o),sel_registerName(s),(a),(b),(c),(d))
#define M5(r,o,s,t,a,u,b,v,c,w,d,x,e) ((r(*)(id,SEL,t,u,v,w,x))objc_msgSend)((id)(o),sel_registerName(s),(a),(b),(c),(d),(e))
#define TOUCHUP (1ULL<<6)

static id gTarget=0,gButton=0,gPanel=0,gWindow=0,gStatus=0,gAction=0;
static int gMade=0,gCapturing=0,gTickPhase=0;
static char gLogPath[768];
static char gSeen[128][128];
static unsigned int gSeenCount=0;

static id ns(const char*s){
    Class c=objc_getClass("NSString");
    return c?M1(id,(id)c,"stringWithUTF8String:",const char*,s?s:""):0;
}

static id color(double r,double g,double b,double a){
    Class c=objc_getClass("UIColor");
    return c?M4(id,(id)c,"colorWithRed:green:blue:alpha:",double,r,double,g,double,b,double,a):0;
}

static void logf0(const char*fmt,...){
    if(!gLogPath[0])return;
    FILE*f=fopen(gLogPath,"a");
    if(!f)return;
    __builtin_va_list ap;
    __builtin_va_start(ap,fmt);
    vfprintf(f,fmt,ap);
    __builtin_va_end(ap);
    fflush(f);
    fclose(f);
}

static void initlog(void){
    char*h=getenv("HOME");
    if(!h)return;
    snprintf(gLogPath,sizeof(gLogPath),"%s/Documents/LoginIPTrace.log",h);
    logf0("\n[LoginIPTracer v2 HFAMap187] loaded pid=%d\n",getpid());
}

static void copyc(char*d,const char*s,size_t_hfa cap){
    if(!d||!cap)return;
    size_t_hfa i=0;
    if(s)for(;s[i]&&i+1<cap;i++)d[i]=s[i];
    d[i]=0;
}

static int ceq(const char*a,const char*b){
    if(!a||!b)return 0;
    while(*a&&*b&&*a==*b){a++;b++;}
    return *a==0&&*b==0;
}

static int seen_endpoint(const char*s){
    if(!s||!*s)return 1;
    for(unsigned int i=0;i<gSeenCount;i++)if(ceq(gSeen[i],s))return 1;
    if(gSeenCount<128){copyc(gSeen[gSeenCount],s,sizeof(gSeen[gSeenCount]));gSeenCount++;}
    return 0;
}

static int format_addr(const struct sockaddr*sa,char*out,size_t_hfa cap){
    if(!sa||!out||cap<8)return 0;
    out[0]=0;
    char ip[INET6_ADDRSTRLEN]={0};
    if(sa->sa_family==AF_INET){
        const struct sockaddr_in*a=(const struct sockaddr_in*)sa;
        if(!inet_ntop(AF_INET,&a->sin_addr,ip,sizeof(ip)))return 0;
        snprintf(out,cap,"%s:%u",ip,(unsigned)ntohs(a->sin_port));
        return 1;
    }
    if(sa->sa_family==AF_INET6){
        const struct sockaddr_in6*a=(const struct sockaddr_in6*)sa;
        if(!inet_ntop(AF_INET6,&a->sin6_addr,ip,sizeof(ip)))return 0;
        snprintf(out,cap,"[%s]:%u",ip,(unsigned)ntohs(a->sin6_port));
        return 1;
    }
    return 0;
}

static void settext(id l,const char*s){if(l)M1(void,l,"setText:",id,ns(s));}
static void settitle(id b,const char*s){if(b)M2(void,b,"setTitle:forState:",id,ns(s),u64,0);}

static void scan_sockets(void){
    unsigned int found=0;
    char last[128]={0};
    for(int fd=0;fd<1024;fd++){
        struct sockaddr_storage peer;
        socklen_t plen=(socklen_t)sizeof(peer);
        memset(&peer,0,sizeof(peer));
        if(getpeername(fd,(struct sockaddr*)&peer,&plen)!=0)continue;
        if(peer.ss_family!=AF_INET&&peer.ss_family!=AF_INET6)continue;

        char remote[128]={0};
        if(!format_addr((const struct sockaddr*)&peer,remote,sizeof(remote)))continue;

        int type=0;
        socklen_t tlen=(socklen_t)sizeof(type);
        getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&tlen);

        struct sockaddr_storage local;
        socklen_t llen=(socklen_t)sizeof(local);
        memset(&local,0,sizeof(local));
        char localText[128]={0};
        if(getsockname(fd,(struct sockaddr*)&local,&llen)==0)
            format_addr((const struct sockaddr*)&local,localText,sizeof(localText));

        if(!seen_endpoint(remote)){
            found++;
            copyc(last,remote,sizeof(last));
            logf0("[PEER] fd=%d type=%d local=%s remote=%s\n",fd,type,localText[0]?localText:"?",remote);
        }
    }

    if(found&&gStatus){
        char s[320];
        snprintf(s,sizeof(s),"Capturing...\nNew endpoint: %s\nLog: Documents/LoginIPTrace.log",last);
        settext(gStatus,s);
    }
}

static id win(void){
    Class ac=objc_getClass("UIApplication");
    if(!ac)return 0;
    id app=M0(id,(id)ac,"sharedApplication");
    if(!app)return 0;
    id w=M0(id,app,"keyWindow");
    if(w)return w;
    id a=M0(id,app,"windows");
    if(!a)return 0;
    u64 n=M0(u64,a,"count");
    return n?M1(id,a,"objectAtIndex:",u64,n-1):0;
}

static id mklabel(CGRect r,double fs){
    Class lc=objc_getClass("UILabel");
    if(!lc)return 0;
    id l=M0(id,(id)lc,"alloc");
    l=M1(id,l,"initWithFrame:",CGRect,r);
    M1(void,l,"setTextColor:",id,color(.95,.95,.98,1));
    M1(void,l,"setNumberOfLines:",long long,0);
    Class fc=objc_getClass("UIFont");
    if(fc)M1(void,l,"setFont:",id,M1(id,(id)fc,"systemFontOfSize:",double,fs));
    return l;
}

static void pan(id self,SEL c,id g){
    (void)self;(void)c;
    if(!gButton||!gWindow)return;
    long long st=M0(long long,g,"state");
    if(st==1||st==2){
        CGPoint tr=M1(CGPoint,g,"translationInView:",id,gWindow);
        CGPoint ce=M0(CGPoint,gButton,"center");
        ce.x+=tr.x;ce.y+=tr.y;
        CGRect b=M0(CGRect,gWindow,"bounds");
        double h=26;
        if(ce.x<h)ce.x=h;if(ce.x>b.size.width-h)ce.x=b.size.width-h;
        if(ce.y<h)ce.y=h;if(ce.y>b.size.height-h)ce.y=b.size.height-h;
        M1(void,gButton,"setCenter:",CGPoint,ce);
        CGPoint z={0,0};
        M2(void,g,"setTranslation:inView:",CGPoint,z,id,gWindow);
    }
}

static void panelpan(id self,SEL c,id g){
    (void)self;(void)c;
    if(!gPanel||!gWindow)return;
    long long st=M0(long long,g,"state");
    if(st==1||st==2){
        CGPoint tr=M1(CGPoint,g,"translationInView:",id,gWindow);
        CGPoint ce=M0(CGPoint,gPanel,"center");
        ce.x+=tr.x;ce.y+=tr.y;
        M1(void,gPanel,"setCenter:",CGPoint,ce);
        CGPoint z={0,0};
        M2(void,g,"setTranslation:inView:",CGPoint,z,id,gWindow);
    }
}

static void capture(id self,SEL c,id sender){
    (void)self;(void)c;(void)sender;
    if(!gCapturing){
        gCapturing=1;
        gSeenCount=0;
        memset(gSeen,0,sizeof(gSeen));
        settitle(gAction,"Stop Capture");
        settext(gStatus,"Capturing active sockets...\nNow perform login / server selection.\nLog: Documents/LoginIPTrace.log");
        logf0("[CAPTURE-START]\n");
        scan_sockets();
    }else{
        gCapturing=0;
        settitle(gAction,"Start Capture");
        settext(gStatus,"Capture stopped.\nCheck Documents/LoginIPTrace.log");
        logf0("[CAPTURE-STOP] unique=%u\n",gSeenCount);
    }
}

static void tap(id self,SEL c,id s){
    (void)self;(void)c;(void)s;
    if(gPanel){
        BOOL h=M0(BOOL,gPanel,"isHidden");
        M1(void,gPanel,"setHidden:",BOOL,!h);
    }
}

static void mkui(id w){
    if(gMade||!w)return;
    Class bc=objc_getClass("UIButton"),vc=objc_getClass("UIView");
    if(!bc||!vc)return;

    id b=M0(id,(id)bc,"alloc");
    b=M1(id,b,"initWithFrame:",CGRect,((CGRect){{18,165},{52,52}}));
    M2(void,b,"setTitle:forState:",id,ns("IP"),u64,0);
    M1(void,b,"setBackgroundColor:",id,color(.12,.12,.15,.94));
    id ly=M0(id,b,"layer");
    if(ly)M1(void,ly,"setCornerRadius:",double,26);
    M3(void,b,"addTarget:action:forControlEvents:",id,gTarget,SEL,sel_registerName("tap:"),u64,TOUCHUP);

    Class pc=objc_getClass("UIPanGestureRecognizer");
    if(pc){
        id pg=M0(id,(id)pc,"alloc");
        pg=M2(id,pg,"initWithTarget:action:",id,gTarget,SEL,sel_registerName("pan:"));
        M1(void,b,"addGestureRecognizer:",id,pg);
    }
    M1(void,w,"addSubview:",id,b);
    gButton=b;

    id p=M0(id,(id)vc,"alloc");
    p=M1(id,p,"initWithFrame:",CGRect,((CGRect){{70,90},{330,250}}));
    M1(void,p,"setBackgroundColor:",id,color(.055,.06,.075,.97));
    ly=M0(id,p,"layer");
    if(ly)M1(void,ly,"setCornerRadius:",double,14);
    if(pc){
        id pg=M0(id,(id)pc,"alloc");
        pg=M2(id,pg,"initWithTarget:action:",id,gTarget,SEL,sel_registerName("panelpan:"));
        M1(void,pg,"setCancelsTouchesInView:",BOOL,0);
        M1(void,p,"addGestureRecognizer:",id,pg);
    }

    id h=mklabel((CGRect){{14,10},{302,52}},18);
    settext(h,"Login IP Tracer v2\nHFAMap 1.8.7 injection shell");
    M1(void,p,"addSubview:",id,h);

    id a=M0(id,(id)bc,"alloc");
    a=M1(id,a,"initWithFrame:",CGRect,((CGRect){{14,76},{302,44}}));
    settitle(a,"Start Capture");
    M1(void,a,"setBackgroundColor:",id,color(.18,.32,.62,1));
    M3(void,a,"addTarget:action:forControlEvents:",id,gTarget,SEL,sel_registerName("capture:"),u64,TOUCHUP);
    M1(void,p,"addSubview:",id,a);
    gAction=a;

    gStatus=mklabel((CGRect){{14,136},{302,94}},11);
    settext(gStatus,"Press Start Capture, then login and select a server.\nNo connect/getaddrinfo hook is installed.");
    M1(void,p,"addSubview:",id,gStatus);

    M1(void,p,"setHidden:",BOOL,1);
    M1(void,w,"addSubview:",id,p);
    gPanel=p;gWindow=w;gMade=1;
    logf0("[UI-READY]\n");
}

static void tick(id self,SEL c,id timer){
    (void)self;(void)c;(void)timer;
    id w=win();
    if(!w)return;
    if(!gMade)mkui(w);
    if(gMade&&gWindow!=w){
        M1(void,w,"addSubview:",id,gPanel);
        M1(void,w,"addSubview:",id,gButton);
        gWindow=w;
    }
    if(gCapturing){
        gTickPhase++;
        if((gTickPhase&1)==0)scan_sockets();
    }
    if(gMade){
        M1(void,w,"bringSubviewToFront:",id,gPanel);
        M1(void,w,"bringSubviewToFront:",id,gButton);
    }
}

__attribute__((constructor)) static void init(void){
    initlog();
    Class base=objc_getClass("NSObject");
    if(!base)return;
    Class c=objc_allocateClassPair(base,"LoginIPTracerTarget187",0);
    if(!c)c=objc_getClass("LoginIPTracerTarget187");
    if(!c)return;
    class_addMethod(c,sel_registerName("tick:"),(IMP)tick,"v@:@");
    class_addMethod(c,sel_registerName("tap:"),(IMP)tap,"v@:@");
    class_addMethod(c,sel_registerName("pan:"),(IMP)pan,"v@:@");
    class_addMethod(c,sel_registerName("panelpan:"),(IMP)panelpan,"v@:@");
    class_addMethod(c,sel_registerName("capture:"),(IMP)capture,"v@:@");
    objc_registerClassPair(c);
    gTarget=M0(id,(id)c,"new");
    Class t=objc_getClass("NSTimer");
    if(t&&gTarget)
        M5(id,(id)t,"scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:",double,.5,id,gTarget,SEL,sel_registerName("tick:"),id,(id)0,BOOL,1);
}
