#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

static NSString * const kCacheKey = @"zonoe.localauth.phase1.v02.pandoraLogin";
static NSString * const kPandoraLoginNotification = @"kPandoraSDKNotifyLogin";

static IMP gOrigChannelLogin = NULL;
static IMP gOrigChannelLoginCallback = NULL;
static IMP gOrigCoopLoginResult = NULL;
static IMP gOrigGameLoginResult = NULL;
static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;
static BOOL gPromptVisible = NO;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase1_v0.2.log"];
}

static void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    os_unfair_lock_lock(&gLogLock);
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    if (!h) {
        [[NSFileManager defaultManager] createFileAtPath:LogPath() contents:nil attributes:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    }
    [h seekToEndOfFile];
    [h writeData:data];
    [h closeFile];
    os_unfair_lock_unlock(&gLogLock);
}

static NSString *StringValue(id value) {
    if (!value || value == [NSNull null]) return nil;
    if ([value isKindOfClass:NSString.class]) return value;
    return [value description];
}

static NSDictionary *SanitizedPandoraLoginInfo(NSNotification *notification) {
    NSDictionary *u = [notification.userInfo isKindOfClass:NSDictionary.class] ? notification.userInfo : nil;
    if (!u) return nil;

    NSString *username = StringValue(u[@"username"]);
    NSString *gametoken = StringValue(u[@"gametoken"]);
    NSString *time = StringValue(u[@"time"]);
    NSString *sessid = StringValue(u[@"sessid"]);
    if (!username.length || !gametoken.length || !time.length || !sessid.length) return nil;

    return @{
        @"username": username,
        @"gametoken": gametoken,
        @"time": time,
        @"sessid": sessid
    };
}

static NSDictionary *CachedPandoraLoginInfo(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kCacheKey];
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *u = value;
    NSString *username = StringValue(u[@"username"]);
    NSString *gametoken = StringValue(u[@"gametoken"]);
    NSString *time = StringValue(u[@"time"]);
    NSString *sessid = StringValue(u[@"sessid"]);
    if (!username.length || !gametoken.length || !time.length || !sessid.length) return nil;
    return u;
}

static id SendObject(id obj, const char *selectorName) {
    if (!obj) return nil;
    SEL sel = sel_registerName(selectorName);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(obj, sel);
}

static UIViewController *TopViewController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *window = app.keyWindow;
    if (!window) {
        for (UIWindow *candidate in app.windows) {
            if (!candidate.hidden && candidate.alpha > 0.0) {
                window = candidate;
                break;
            }
        }
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).visibleViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static void ReplayPandoraLogin(id channel) {
    NSDictionary *cache = CachedPandoraLoginInfo();
    if (!cache || !gOrigChannelLoginCallback) {
        ZLog(@"[LOCAL] refused cache=%d callback=%d", cache != nil, gOrigChannelLoginCallback != NULL);
        return;
    }

    NSString *username = StringValue(cache[@"username"]);
    ZLog(@"[LOCAL] replay Pandora callback user=%@ gametokenLen=%lu timeLen=%lu sessidLen=%lu",
         username,
         (unsigned long)[StringValue(cache[@"gametoken"]) length],
         (unsigned long)[StringValue(cache[@"time"]) length],
         (unsigned long)[StringValue(cache[@"sessid"]) length]);

    NSNotification *notification = [NSNotification notificationWithName:kPandoraLoginNotification
                                                                  object:nil
                                                                userInfo:cache];
    ((void(*)(id,SEL,id))gOrigChannelLoginCallback)(channel, sel_registerName("loginCallBack:"), notification);

    NSString *uid = StringValue(SendObject(channel, "userId"));
    NSString *session = StringValue(SendObject(channel, "sessionId"));
    NSString *nick = StringValue(SendObject(channel, "userNick"));
    ZLog(@"[LOCAL] channel state after replay uid=%@ nickLen=%lu sessionLen=%lu",
         uid ?: @"<nil>", (unsigned long)nick.length, (unsigned long)session.length);
}

static NSInteger ChannelLoginReplacement(id self, SEL _cmd) {
    NSDictionary *cache = CachedPandoraLoginInfo();
    if (!cache) {
        ZLog(@"[MODE] no v0.2 raw cache -> original channel login");
        return gOrigChannelLogin ? ((NSInteger(*)(id,SEL))gOrigChannelLogin)(self, _cmd) : -1;
    }

    void (^presentChoice)(void) = ^{
        if (gPromptVisible) return;
        gPromptVisible = YES;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Zonoe LocalAuth Phase1 v0.2"
                                                                        message:@"测试点已下移到 SMPCQuickChannel。\n本地回放会执行原 loginCallBack:，继续走原 SDKCooperater / checklogin / 游戏回调。"
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"原渠道登录"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            gPromptVisible = NO;
            ZLog(@"[MODE] original channel login selected");
            if (gOrigChannelLogin) ((NSInteger(*)(id,SEL))gOrigChannelLogin)(self, _cmd);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"本地通道回放（测试）"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            gPromptVisible = NO;
            ZLog(@"[MODE] local channel replay selected");
            ReplayPandoraLogin(self);
        }]];

        UIViewController *vc = TopViewController();
        if (vc) {
            [vc presentViewController:alert animated:YES completion:nil];
        } else {
            gPromptVisible = NO;
            ZLog(@"[UI] no top view controller -> fallback original channel login");
            if (gOrigChannelLogin) ((NSInteger(*)(id,SEL))gOrigChannelLogin)(self, _cmd);
        }
    };

    if ([NSThread isMainThread]) presentChoice();
    else dispatch_async(dispatch_get_main_queue(), presentChoice);
    return 0;
}

static void ChannelLoginCallbackReplacement(id self, SEL _cmd, NSNotification *notification) {
    NSDictionary *safe = SanitizedPandoraLoginInfo(notification);
    if (safe) {
        [[NSUserDefaults standardUserDefaults] setObject:safe forKey:kCacheKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        ZLog(@"[CAPTURE] saved raw Pandora login user=%@ gametokenLen=%lu timeLen=%lu sessidLen=%lu",
             safe[@"username"],
             (unsigned long)[safe[@"gametoken"] length],
             (unsigned long)[safe[@"time"] length],
             (unsigned long)[safe[@"sessid"] length]);
    } else {
        ZLog(@"[CAPTURE] Pandora callback did not contain required username/gametoken/time/sessid");
    }

    if (gOrigChannelLoginCallback) {
        ((void(*)(id,SEL,id))gOrigChannelLoginCallback)(self, _cmd, notification);
    }

    NSString *uid = StringValue(SendObject(self, "userId"));
    NSString *session = StringValue(SendObject(self, "sessionId"));
    ZLog(@"[CHANNEL] original callback complete uid=%@ sessionLen=%lu", uid ?: @"<nil>", (unsigned long)session.length);
}

static void CooperaterLoginResultReplacement(id self, SEL _cmd, NSNotification *notification) {
    NSDictionary *u = [notification.userInfo isKindOfClass:NSDictionary.class] ? notification.userInfo : nil;
    NSString *uid = StringValue(u[@"userId"]);
    NSString *session = StringValue(u[@"sessionId"]);
    NSString *error = StringValue(u[@"error"]);
    ZLog(@"[FLOW] SDKCooperater channelPlatformLoginResult error=%@ uid=%@ sessionLen=%lu",
         error ?: @"<nil>", uid ?: @"<nil>", (unsigned long)session.length);
    if (gOrigCoopLoginResult) ((void(*)(id,SEL,id))gOrigCoopLoginResult)(self, _cmd, notification);
}

static void GameLoginResultReplacement(id self, SEL _cmd, NSNotification *notification) {
    NSDictionary *u = [notification.userInfo isKindOfClass:NSDictionary.class] ? notification.userInfo : nil;
    NSString *uid = StringValue(u[@"uid"]);
    NSString *token = StringValue(u[@"user_token"]);
    NSString *error = StringValue(u[@"error"]);
    ZLog(@"[GAME] CustomAppController login result error=%@ uid=%@ userTokenLen=%lu",
         error ?: @"<nil>", uid ?: @"<nil>", (unsigned long)token.length);
    if (gOrigGameLoginResult) ((void(*)(id,SEL,id))gOrigGameLoginResult)(self, _cmd, notification);
}

static BOOL ReplaceInstanceMethod(const char *className, const char *selectorName, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    if (!cls) {
        ZLog(@"[INSTALL] missing class %s", className);
        return NO;
    }
    Method method = class_getInstanceMethod(cls, sel_registerName(selectorName));
    if (!method) {
        ZLog(@"[INSTALL] missing method %s %s", className, selectorName);
        return NO;
    }
    IMP old = method_getImplementation(method);
    if (original) *original = old;
    method_setImplementation(method, replacement);
    ZLog(@"[INSTALL] replaced %s %s old=%p new=%p", className, selectorName, old, replacement);
    return YES;
}

static void Install(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase1 v0.2 start ===");
        for (int i = 0; i < 160; ++i) {
            if (objc_getClass("SMPCQuickChannel") && objc_getClass("SDKCooperater") && objc_getClass("CustomAppController")) break;
            [NSThread sleepForTimeInterval:0.25];
        }

        ReplaceInstanceMethod("SMPCQuickChannel", "login", (IMP)ChannelLoginReplacement, &gOrigChannelLogin);
        ReplaceInstanceMethod("SMPCQuickChannel", "loginCallBack:", (IMP)ChannelLoginCallbackReplacement, &gOrigChannelLoginCallback);
        ReplaceInstanceMethod("SDKCooperater", "channelPlatformLoginResult:", (IMP)CooperaterLoginResultReplacement, &gOrigCoopLoginResult);
        ReplaceInstanceMethod("CustomAppController", "smpcQpLoginResult:", (IMP)GameLoginResultReplacement, &gOrigGameLoginResult);

        NSDictionary *cache = CachedPandoraLoginInfo();
        ZLog(@"[CACHE] present=%d user=%@", cache != nil, cache ? cache[@"username"] : @"<nil>");
        ZLog(@"[NOTE] v0.2 does not forge the final game notification; it replays the original channel callback and leaves SDKCooperater/checklogin/game flow intact");
    }
}

__attribute__((constructor)) static void Entry(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        Install();
    });
}
