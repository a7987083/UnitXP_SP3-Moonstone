#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

static NSString * const kCacheKey = @"zonoe.localauth.phase1.loginUserInfo";
static NSString * const kModeKey  = @"zonoe.localauth.phase1.preferLocal";
static NSString * const kLoginNotification = @"kSmpcQPLoginNotification";
static IMP gOrigSDKLogin = NULL;
static IMP gOrigGameLoginResult = NULL;
static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static BOOL gPromptVisible = NO;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase1_v0.1.log"];
}
static void ZLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt); NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body];
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    os_unfair_lock_lock(&gLock);
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    if (!h) { [[NSFileManager defaultManager] createFileAtPath:LogPath() contents:nil attributes:nil]; h = [NSFileHandle fileHandleForWritingAtPath:LogPath()]; }
    [h seekToEndOfFile]; [h writeData:d]; [h closeFile];
    os_unfair_lock_unlock(&gLock);
}
static UIViewController *TopVC(void) {
    UIWindow *w = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:UIWindowScene.class]) { for (UIWindow *x in ((UIWindowScene*)s).windows) if (x.isKeyWindow) { w=x; break; } }
    if (!w) w = UIApplication.sharedApplication.keyWindow;
    UIViewController *v=w.rootViewController;
    while (v.presentedViewController) v=v.presentedViewController;
    if ([v isKindOfClass:UINavigationController.class]) v=((UINavigationController*)v).visibleViewController;
    if ([v isKindOfClass:UITabBarController.class]) v=((UITabBarController*)v).selectedViewController;
    return v;
}
static NSDictionary *CachedUserInfo(void) {
    id x=[[NSUserDefaults standardUserDefaults] objectForKey:kCacheKey];
    return [x isKindOfClass:NSDictionary.class] ? x : nil;
}
static BOOL ValidUserInfo(NSDictionary *u) {
    return [u[@"uid"] description].length && [u[@"user_name"] description].length && [u[@"user_token"] description].length;
}
static void ReplayLocalLogin(void) {
    NSDictionary *u=CachedUserInfo();
    if (!ValidUserInfo(u)) { ZLog(@"[LOCAL] replay refused: no valid cache"); return; }
    ZLog(@"[LOCAL] replay login uid=%@ tokenLen=%lu", u[@"uid"], (unsigned long)[[u[@"user_token"] description] length]);
    NSNotification *n=[NSNotification notificationWithName:kLoginNotification object:nil userInfo:u];
    [[NSNotificationCenter defaultCenter] postNotification:n];
}
static NSInteger SDKLoginReplacement(id self, SEL _cmd) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gPromptVisible) return; gPromptVisible=YES;
        NSDictionary *cache=CachedUserInfo(); BOOL has=ValidUserInfo(cache);
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Zonoe LocalAuth Phase1" message:has ? [NSString stringWithFormat:@"已缓存账号 %@。选择本地缓存登录可测试绕过第三方登录 UI。", cache[@"uid"]] : @"尚无缓存。请先使用一次原 SDK 正常登录，成功后会自动保存游戏登录回调。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"原 SDK 登录" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ gPromptVisible=NO; ZLog(@"[MODE] original SDK login"); if(gOrigSDKLogin) ((NSInteger(*)(id,SEL))gOrigSDKLogin)(self,_cmd); }]];
        if (has) [a addAction:[UIAlertAction actionWithTitle:@"本地缓存登录（测试）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ gPromptVisible=NO; [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kModeKey]; ZLog(@"[MODE] local replay selected"); ReplayLocalLogin(); }]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *x){ gPromptVisible=NO; }]];
        UIViewController *v=TopVC(); if(v) [v presentViewController:a animated:YES completion:nil]; else { gPromptVisible=NO; ZLog(@"[UI] no top view controller"); }
    });
    return 0;
}
static void GameLoginResultReplacement(id self, SEL _cmd, NSNotification *n) {
    NSDictionary *u=[n.userInfo isKindOfClass:NSDictionary.class] ? n.userInfo : nil;
    if (ValidUserInfo(u)) {
        NSDictionary *safe=@{ @"uid":[u[@"uid"] description], @"user_name":[u[@"user_name"] description], @"user_token":[u[@"user_token"] description] };
        [[NSUserDefaults standardUserDefaults] setObject:safe forKey:kCacheKey]; [[NSUserDefaults standardUserDefaults] synchronize];
        ZLog(@"[CAPTURE] saved login callback uid=%@ tokenLen=%lu", safe[@"uid"], (unsigned long)[safe[@"user_token"] length]);
    }
    if(gOrigGameLoginResult) ((void(*)(id,SEL,id))gOrigGameLoginResult)(self,_cmd,n);
}
static BOOL ReplaceInstanceMethod(const char *clsName,const char *selName,IMP replacement,IMP *orig) {
    Class c=objc_getClass(clsName); if(!c){ZLog(@"[INSTALL] missing class %s",clsName);return NO;}
    Method m=class_getInstanceMethod(c,sel_registerName(selName)); if(!m){ZLog(@"[INSTALL] missing method %s %s",clsName,selName);return NO;}
    IMP old=method_getImplementation(m); if(orig)*orig=old; method_setImplementation(m,replacement);
    ZLog(@"[INSTALL] replaced %s %s old=%p new=%p",clsName,selName,old,replacement); return YES;
}
static void Install(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase1 v0.1 start ===");
        for(int i=0;i<120;i++){
            if(objc_getClass("SMPCQuickSDK") && objc_getClass("CustomAppController")) break;
            [NSThread sleepForTimeInterval:0.25];
        }
        ReplaceInstanceMethod("CustomAppController","smpcQpLoginResult:",(IMP)GameLoginResultReplacement,&gOrigGameLoginResult);
        ReplaceInstanceMethod("SMPCQuickSDK","login",(IMP)SDKLoginReplacement,&gOrigSDKLogin);
        NSDictionary *u=CachedUserInfo(); ZLog(@"[CACHE] present=%d uid=%@ tokenLen=%lu",ValidUserInfo(u),u[@"uid"],(unsigned long)[[u[@"user_token"] description] length]);
        ZLog(@"[NOTE] phase1 only: cached user_token may expire; final independence requires server-owned local session/token");
    }
}
__attribute__((constructor)) static void Entry(void){ dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ Install(); }); }
