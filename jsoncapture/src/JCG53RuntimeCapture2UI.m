#import "JCG53RuntimeCapture2.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define JCG53_SCROLL_TAG 50501
#define JCG53_UI_REFRESH_SECONDS 1.0

typedef void (*JCG53ObjcVoidFn)(id self, SEL _cmd);
static IMP gOrigToggleCapture;
static BOOL gToggleHookReady=NO;
static BOOL gUIAttached=NO;

static void JCG53SyncFromMasterButton(UIView *panel) {
    UIButton*b=(UIButton*)[panel viewWithTag:200];if(![b isKindOfClass:[UIButton class]])return;NSString*t=[b titleForState:UIControlStateNormal];
    if(t.length&&[t rangeOfString:@"抓取：关"].location!=NSNotFound)JCG53Runtime2SetEnabled(NO);else if(t.length&&[t rangeOfString:@"抓取：开"].location!=NSNotFound)JCG53Runtime2SetEnabled(YES);
}

static void JCG53SyncFromController(id controller) {
    UIView *panel=nil;@try{panel=[controller valueForKey:@"panel"];}@catch(__unused NSException*e){return;}if([panel isKindOfClass:[UIView class]])JCG53SyncFromMasterButton(panel);
}

static void JCG53ToggleCaptureHook(id self,SEL _cmd) {
    if(gOrigToggleCapture)((JCG53ObjcVoidFn)gOrigToggleCapture)(self,_cmd);
    JCG53SyncFromController(self);
}

static BOOL JCG53InstallToggleHook(void) {
    if(gToggleHookReady)return YES;Class cls=NSClassFromString(@"JCG5Controller");Method m=class_getInstanceMethod(cls,NSSelectorFromString(@"toggleCapture"));if(!m)return NO;
    IMP current=method_getImplementation(m);if(current==(IMP)JCG53ToggleCaptureHook){gToggleHookReady=YES;return YES;}gOrigToggleCapture=current;method_setImplementation(m,(IMP)JCG53ToggleCaptureHook);gToggleHookReady=YES;return YES;
}

static void JCG53PollToggleHook(NSUInteger attempt) {
    if(JCG53InstallToggleHook())return;if(attempt>=50)return;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG53PollToggleHook(attempt+1);});
}

static id JCG53FindController(void) {
    Class cls=NSClassFromString(@"JCG5Controller");if(!cls)return nil;for(UIWindow*w in [UIApplication sharedApplication].windows){UIViewController*root=w.rootViewController;if([root isKindOfClass:cls])return root;}return nil;
}

static BOOL JCG53AttachUI(id controller) {
    if(!controller)return NO;NSMutableDictionary*labels=nil;UIView*panel=nil;@try{labels=[controller valueForKey:@"labels"];panel=[controller valueForKey:@"panel"];}@catch(__unused NSException*e){return NO;}
    if(![labels isKindOfClass:[NSMutableDictionary class]]||![panel isKindOfClass:[UIView class]])return NO;UILabel*existing=labels[@"capture2"];if([existing isKindOfClass:[UILabel class]]){gUIAttached=YES;return YES;}
    UIScrollView*scroll=(UIScrollView*)[panel viewWithTag:JCG53_SCROLL_TAG];UILabel*capture=labels[@"capture"];if(![scroll isKindOfClass:[UIScrollView class]]||![capture isKindOfClass:[UILabel class]]||capture.superview!=scroll)return NO;
    CGFloat delta=58.0,insertY=CGRectGetMaxY(capture.frame)+2.0;NSArray*views=[[scroll.subviews copy]autorelease];for(UIView*v in views){if(CGRectGetMinY(v.frame)+0.5<insertY)continue;CGRect f=v.frame;f.origin.y+=delta;v.frame=f;}
    CGFloat x=CGRectGetMinX(capture.frame),w=CGRectGetWidth(capture.frame);UILabel*h=[[[UILabel alloc]initWithFrame:CGRectMake(x,insertY,w,18)]autorelease];h.text=@"运行时抓取二";h.textColor=[UIColor colorWithRed:0.45 green:0.9 blue:0.62 alpha:1];h.font=[UIFont boldSystemFontOfSize:12];h.numberOfLines=0;
    UILabel*l=[[[UILabel alloc]initWithFrame:CGRectMake(x,insertY+18,w,38)]autorelease];l.textColor=[UIColor colorWithWhite:0.95 alpha:1];l.font=[UIFont systemFontOfSize:11.5];l.numberOfLines=0;l.text=JCG53Runtime2StatusText();
    [scroll addSubview:h];[scroll addSubview:l];labels[@"capture2"]=l;CGSize size=scroll.contentSize;size.height+=delta;scroll.contentSize=size;gUIAttached=YES;return YES;
}

static void JCG53RefreshUI(void) {
    id controller=JCG53FindController();if(controller){UIView*panel=nil;NSMutableDictionary*labels=nil;@try{panel=[controller valueForKey:@"panel"];labels=[controller valueForKey:@"labels"];}@catch(__unused NSException*e){}
        if([panel isKindOfClass:[UIView class]])JCG53SyncFromMasterButton(panel);if(!gUIAttached)JCG53AttachUI(controller);UILabel*l=labels[@"capture2"];if([l isKindOfClass:[UILabel class]])l.text=JCG53Runtime2StatusText();}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(JCG53_UI_REFRESH_SECONDS*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG53RefreshUI();});
}

__attribute__((constructor)) static void JCG53UIEntry(void) {
    @autoreleasepool{JCG53Runtime2Start();dispatch_async(dispatch_get_main_queue(),^{JCG53PollToggleHook(0);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG53RefreshUI();});});}
}
