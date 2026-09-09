#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>

static NSString * const kLocalBase = @"http://43.242.203.214";
static NSString * const kModeKey = @"ZonoeLocalAuth.Phase4DualMode.Mode";
static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;

typedef NS_ENUM(NSInteger, ZonoeAuthMode) {
    ZonoeAuthModeOriginal = 0,
    ZonoeAuthModeLocal = 1,
};

typedef void (*KCNetworkIMP)(id, SEL, NSString *, NSString *, BOOL);
static KCNetworkIMP gOrigKCNetwork = NULL;
static BOOL gInstalled = NO;
static UIWindow *gWindow = nil;
static UIButton *gFloatButton = nil;
static NSMutableArray<NSURLConnection *> *gActiveConnections = nil;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase4_DualMode.log"];
}

static void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body ?: @""];
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

static ZonoeAuthMode CurrentMode(void) {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kModeKey];
    return value == ZonoeAuthModeLocal ? ZonoeAuthModeLocal : ZonoeAuthModeOriginal;
}

static NSString *ModeText(void) {
    return CurrentMode() == ZonoeAuthModeLocal ? @"本地登录" : @"原 SDK 登录";
}

static void SetMode(ZonoeAuthMode mode) {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    ZLog(@"[P4D] mode=%@", mode == ZonoeAuthModeLocal ? @"LOCAL" : @"ORIGINAL");
}

static NSString *MappedPath(NSString *domain) {
    if (![domain isKindOfClass:NSString.class] || domain.length == 0) return nil;
    NSString *lower = domain.lowercaseString;
    if ([lower containsString:@"/api/common/login"]) return @"/auth/login?compat=pandora";
    if ([lower containsString:@"/api/common/register"]) return @"/auth/register?compat=pandora";
    if ([lower containsString:@"forgetpwd"] ||
        [lower containsString:@"change_password"] ||
        [lower containsString:@"changepassword"] ||
        [lower containsString:@"resetpassword"] ||
        [lower containsString:@"reset_password"]) {
        return @"/auth/change_password?compat=pandora";
    }
    return nil;
}

static void HoldConnection(NSURLConnection *conn) {
    if (!conn) return;
    @synchronized([NSURLConnection class]) {
        if (!gActiveConnections) gActiveConnections = [NSMutableArray array];
        [gActiveConnections addObject:conn];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized([NSURLConnection class]) {
            [gActiveConnections removeObject:conn];
        }
    });
}

static void SendToLocalBackend(id manager, NSString *domain, NSString *body, BOOL load) {
    NSString *path = MappedPath(domain);
    if (!path) return;

    NSString *urlString = [kLocalBase stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        ZLog(@"[P4D] invalid local URL route=%@", path);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:15.0];
    req.HTTPMethod = @"POST";
    if ([body isKindOfClass:NSString.class] && body.length > 0) {
        req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    }
    [req setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    ZLog(@"[P4D] local route %@ -> %@ load=%d bodyBytes=%lu",
         domain ?: @"<nil>", path, load, (unsigned long)req.HTTPBody.length);

    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:req delegate:manager startImmediately:YES];
    if (conn) {
        HoldConnection(conn);
        ZLog(@"[P4D] connection created route=%@ active=%lu", path, (unsigned long)gActiveConnections.count);
    } else {
        ZLog(@"[P4D] connection create failed route=%@", path);
    }
}

static void ZonoeKCNetworkHandle(id self, SEL _cmd, NSString *domain, NSString *body, BOOL load) {
    NSString *mapped = MappedPath(domain);
    if (!mapped || CurrentMode() == ZonoeAuthModeOriginal) {
        if (mapped) ZLog(@"[P4D] original route %@", domain ?: @"<nil>");
        if (gOrigKCNetwork) gOrigKCNetwork(self, _cmd, domain, body, load);
        return;
    }
    SendToLocalBackend(self, domain, body, load);
}

static UIViewController *TopViewController(void) {
    UIWindow *window = gWindow ?: UIApplication.sharedApplication.keyWindow;
    if (!window) window = UIApplication.sharedApplication.windows.lastObject;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static void UpdateButtonTitle(void) {
    if (!gFloatButton) return;
    [gFloatButton setTitle:(CurrentMode() == ZonoeAuthModeLocal ? @"本地" : @"SDK") forState:UIControlStateNormal];
}

@interface ZonoeDualModeUI : NSObject
+ (instancetype)shared;
- (void)showChooser;
- (void)tapButton:(id)sender;
- (void)panButton:(UIPanGestureRecognizer *)g;
- (void)installUI;
@end

@implementation ZonoeDualModeUI
+ (instancetype)shared {
    static ZonoeDualModeUI *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [ZonoeDualModeUI new]; });
    return obj;
}

- (void)showChooser {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopViewController();
        if (!vc) return;
        NSString *msg = [NSString stringWithFormat:@"当前模式：%@\n选择后立即生效。", ModeText()];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"登录模式" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"原 SDK 登录" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            SetMode(ZonoeAuthModeOriginal);
            UpdateButtonTitle();
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"本地登录" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            SetMode(ZonoeAuthModeLocal);
            UpdateButtonTitle();
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

- (void)tapButton:(id)sender {
    (void)sender;
    [self showChooser];
}

- (void)panButton:(UIPanGestureRecognizer *)g {
    if (!gWindow || !gFloatButton) return;
    CGPoint d = [g translationInView:gWindow];
    CGPoint c = gFloatButton.center;
    c.x += d.x; c.y += d.y;
    CGRect b = gWindow.bounds;
    c.x = MAX(28, MIN(b.size.width - 28, c.x));
    c.y = MAX(24, MIN(b.size.height - 24, c.y));
    gFloatButton.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}

- (void)installUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.lastObject;
        if (!w) return;
        gWindow = w;
        if (!gFloatButton) {
            gFloatButton = [UIButton buttonWithType:UIButtonTypeCustom];
            gFloatButton.frame = CGRectMake(18, 150, 58, 48);
            gFloatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.90];
            gFloatButton.layer.cornerRadius = 24;
            gFloatButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [gFloatButton addTarget:self action:@selector(tapButton:) forControlEvents:UIControlEventTouchUpInside];
            [gFloatButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)]];
            [w addSubview:gFloatButton];
            UpdateButtonTitle();
        } else if (gFloatButton.superview != w) {
            [w addSubview:gFloatButton];
        }
        [w bringSubviewToFront:gFloatButton];
    });
}
@end

static void TryInstall(void) {
    @synchronized(NSClassFromString(@"NSObject")) {
        if (gInstalled) return;
        Class cls = NSClassFromString(@"KCNetworkManager");
        if (!cls) return;
        SEL sel = NSSelectorFromString(@"KCNetworkHandleWithDomain:andBodyStr:andLoad:");
        Method method = class_getInstanceMethod(cls, sel);
        if (!method) {
            ZLog(@"[P4D] KCNetworkManager found but selector missing");
            return;
        }
        IMP current = method_getImplementation(method);
        if (current == (IMP)ZonoeKCNetworkHandle) {
            gInstalled = YES;
            return;
        }
        gOrigKCNetwork = (KCNetworkIMP)current;
        method_setImplementation(method, (IMP)ZonoeKCNetworkHandle);
        gInstalled = YES;
        ZLog(@"[P4D] installed KCNetworkManager dual-mode bridge");
    }
}

static void ImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)mh; (void)slide;
    TryInstall();
}

__attribute__((constructor)) static void ZonoeBackendDualModeEntry(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase4 DualMode loaded ===");
        ZLog(@"[P4D] modes: ORIGINAL / LOCAL; request bodies and credentials are not logged");
        _dyld_register_func_for_add_image(ImageAdded);
        TryInstall();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[ZonoeDualModeUI shared] installUI];
            [[ZonoeDualModeUI shared] showChooser];
        });
    }
}
