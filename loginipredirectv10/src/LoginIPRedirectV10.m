#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <string.h>
#include <sys/socket.h>

#include "../../logintcppayload/vendor/fishhook.h"

#define ORIGINAL_IP "118.145.146.208"
#define PREF_IP_KEY @"LoginIPRedirectV10.TargetIPv4"
#define PREF_MODE_KEY @"LoginIPRedirectV10.Mode"
#define LEGACY_V9_IP_KEY @"LoginIPRedirectV9.TargetIPv4"

typedef NS_ENUM(NSInteger, LIRV10Mode) {
    LIRV10ModeEntry81 = 0,
    LIRV10ModeFullChain = 1,
};

typedef int (*ConnectFn)(int, const struct sockaddr *, socklen_t);
static ConnectFn gOrigConnect;

static UIWindow *gWindow;
static UIButton *gFloatButton;
static NSString *gLogPath;
static BOOL gHookInstalled = NO;
static unsigned long long gRedirectCount = 0;
static unsigned long long gObserveCount = 0;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
static __thread int gInsideHook = 0;
static char gTargetIP[INET_ADDRSTRLEN] = {0};
static char gLastHit[128] = {0};
static NSInteger gMode = LIRV10ModeEntry81;

static void AppendLog(NSString *line) {
    if (!gLogPath || !line.length) return;
    pthread_mutex_lock(&gLogLock);
    FILE *f = fopen(gLogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gLogLock);
}

static NSString *NowText(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static void LogEvent(NSString *line) {
    AppendLog([NSString stringWithFormat:@"[%@] %@", NowText(), line ?: @""]);
}

static NSString *TargetText(void) {
    char tmp[INET_ADDRSTRLEN] = {0};
    pthread_mutex_lock(&gLock);
    snprintf(tmp, sizeof(tmp), "%s", gTargetIP);
    pthread_mutex_unlock(&gLock);
    return tmp[0] ? [NSString stringWithUTF8String:tmp] : @"未设置";
}

static NSInteger CurrentMode(void) {
    NSInteger mode;
    pthread_mutex_lock(&gLock);
    mode = gMode;
    pthread_mutex_unlock(&gLock);
    return mode;
}

static NSString *ModeText(void) {
    return CurrentMode() == LIRV10ModeFullChain ? @"全链路" : @"仅入口→81";
}

static NSString *LastHitText(void) {
    char tmp[sizeof(gLastHit)] = {0};
    pthread_mutex_lock(&gLock);
    snprintf(tmp, sizeof(tmp), "%s", gLastHit);
    pthread_mutex_unlock(&gLock);
    return tmp[0] ? [NSString stringWithUTF8String:tmp] : @"无";
}

static BOOL SetTarget(NSString *text, BOOL persist) {
    NSString *trim = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    struct in_addr addr;
    if (!trim.length || inet_pton(AF_INET, trim.UTF8String, &addr) != 1) return NO;
    pthread_mutex_lock(&gLock);
    snprintf(gTargetIP, sizeof(gTargetIP), "%s", trim.UTF8String);
    pthread_mutex_unlock(&gLock);
    if (persist) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:trim forKey:PREF_IP_KEY];
        [ud synchronize];
    }
    return YES;
}

static void ClearTarget(BOOL persist) {
    pthread_mutex_lock(&gLock);
    memset(gTargetIP, 0, sizeof(gTargetIP));
    pthread_mutex_unlock(&gLock);
    if (persist) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud removeObjectForKey:PREF_IP_KEY];
        [ud synchronize];
    }
}

static void SetMode(NSInteger mode, BOOL persist) {
    mode = (mode == LIRV10ModeFullChain) ? LIRV10ModeFullChain : LIRV10ModeEntry81;
    pthread_mutex_lock(&gLock);
    gMode = mode;
    pthread_mutex_unlock(&gLock);
    if (persist) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:mode forKey:PREF_MODE_KEY];
        [ud synchronize];
    }
}

static BOOL CopyTarget(char out[INET_ADDRSTRLEN]) {
    pthread_mutex_lock(&gLock);
    snprintf(out, INET_ADDRSTRLEN, "%s", gTargetIP);
    pthread_mutex_unlock(&gLock);
    if (!out[0]) return NO;
    struct in_addr addr;
    return inet_pton(AF_INET, out, &addr) == 1;
}

static BOOL IsEntryPort(uint16_t port) {
    return port == 80 || port == 81 || port == 10008;
}

static BOOL IsChainPort(uint16_t port) {
    return port == 10003 || (port >= 7000 && port <= 7010);
}

static BOOL ResolvePort(uint16_t srcPort, NSInteger mode, uint16_t *dstPort, const char **rule) {
    if (IsEntryPort(srcPort)) {
        if (dstPort) *dstPort = 81;
        if (rule) *rule = "ENTRY->81";
        return YES;
    }
    if (mode == LIRV10ModeFullChain && IsChainPort(srcPort)) {
        if (dstPort) *dstPort = srcPort;
        if (rule) *rule = "FULL-CHAIN";
        return YES;
    }
    return NO;
}

static int HookConnect(int fd, const struct sockaddr *addr, socklen_t len) {
    if (!gOrigConnect) { errno = ENOSYS; return -1; }
    if (gInsideHook) return gOrigConnect(fd, addr, len);
    if (!addr || len < sizeof(struct sockaddr_in) || addr->sa_family != AF_INET) return gOrigConnect(fd, addr, len);

    const struct sockaddr_in *sin = (const struct sockaddr_in *)addr;
    char srcIP[INET_ADDRSTRLEN] = {0};
    if (!inet_ntop(AF_INET, &sin->sin_addr, srcIP, sizeof(srcIP))) return gOrigConnect(fd, addr, len);
    if (strcmp(srcIP, ORIGINAL_IP) != 0) return gOrigConnect(fd, addr, len);

    uint16_t srcPort = ntohs(sin->sin_port);
    __sync_add_and_fetch(&gObserveCount, 1);

    NSInteger mode = CurrentMode();
    uint16_t dstPort = 0;
    const char *rule = NULL;
    if (!ResolvePort(srcPort, mode, &dstPort, &rule)) {
        @autoreleasepool {
            LogEvent([NSString stringWithFormat:@"OBSERVE fd=%d %s:%u mode=%@ no-redirect", fd, srcIP, srcPort, ModeText()]);
        }
        return gOrigConnect(fd, addr, len);
    }

    char target[INET_ADDRSTRLEN] = {0};
    if (!CopyTarget(target)) {
        @autoreleasepool {
            LogEvent([NSString stringWithFormat:@"MATCH[%s] fd=%d %s:%u target-not-set", rule, fd, srcIP, srcPort]);
        }
        return gOrigConnect(fd, addr, len);
    }

    struct sockaddr_in redirected = *sin;
    if (inet_pton(AF_INET, target, &redirected.sin_addr) != 1) return gOrigConnect(fd, addr, len);
    redirected.sin_port = htons(dstPort);

    pthread_mutex_lock(&gLock);
    snprintf(gLastHit, sizeof(gLastHit), "%s:%u -> %s:%u", srcIP, srcPort, target, dstPort);
    pthread_mutex_unlock(&gLock);
    __sync_add_and_fetch(&gRedirectCount, 1);

    gInsideHook++;
    @autoreleasepool {
        LogEvent([NSString stringWithFormat:@"REDIRECT[%s] fd=%d %s:%u -> %s:%u mode=%@", rule, fd, srcIP, srcPort, target, dstPort, ModeText()]);
    }
    int rc = gOrigConnect(fd, (const struct sockaddr *)&redirected, sizeof(redirected));
    int savedErrno = errno;
    @autoreleasepool {
        NSString *err = rc == 0 ? @"connected" : ([NSString stringWithUTF8String:strerror(savedErrno)] ?: @"unknown");
        LogEvent([NSString stringWithFormat:@"CONNECT-RESULT fd=%d %s:%u rc=%d errno=%d %@", fd, target, dstPort, rc, savedErrno, err]);
    }
    gInsideHook--;
    errno = savedErrno;
    return rc;
}

static void InstallHook(void) {
    if (gHookInstalled) return;
    gOrigConnect = (ConnectFn)dlsym(RTLD_DEFAULT, "connect");
    if (!gOrigConnect) {
        LogEvent(@"HOOK-ERROR connect symbol not found");
        return;
    }
    struct rebinding rb = {"connect", (void *)HookConnect, (void **)&gOrigConnect};
    int rc = rebind_symbols(&rb, 1);
    gHookInstalled = (rc == 0 && gOrigConnect != NULL);
    LogEvent([NSString stringWithFormat:@"HOOK installed=%@ rc=%d", gHookInstalled ? @"YES" : @"NO", rc]);
}

static UIViewController *TopViewController(void) {
    UIWindow *w = gWindow ?: [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) vc = [(UINavigationController *)vc topViewController];
    if ([vc isKindOfClass:[UITabBarController class]]) vc = [(UITabBarController *)vc selectedViewController];
    return vc;
}

@interface LoginIPRedirectV10Target : NSObject
+ (instancetype)shared;
- (void)tick:(NSTimer *)timer;
- (void)tap:(id)sender;
- (void)pan:(UIPanGestureRecognizer *)g;
@end

@implementation LoginIPRedirectV10Target
+ (instancetype)shared {
    static LoginIPRedirectV10Target *obj;
    if (!obj) obj = [[self alloc] init];
    return obj;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];
    return app.keyWindow ?: app.windows.lastObject;
}

- (void)makeButton:(UIWindow *)w {
    if (gFloatButton || !w) return;
    gWindow = w;
    gFloatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatButton.frame = CGRectMake(18, 165, 64, 54);
    gFloatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    gFloatButton.layer.cornerRadius = 27;
    [gFloatButton setTitle:@"IP10" forState:UIControlStateNormal];
    gFloatButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [gFloatButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)] autorelease];
    [gFloatButton addGestureRecognizer:pan];
    [w addSubview:gFloatButton];
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *w = [self currentWindow];
    if (!w) return;
    if (!gFloatButton) [self makeButton:w];
    if (gWindow != w) {
        [w addSubview:gFloatButton];
        gWindow = w;
    }
    [w bringSubviewToFront:gFloatButton];
}

- (void)tap:(id)sender {
    (void)sender;
    UIViewController *vc = TopViewController();
    if (!vc) return;
    NSString *msg = [NSString stringWithFormat:@"Hook: %@\n目标: %@\n模式: %@\n重定向: %llu  原IP连接: %llu\n最后命中: %@\n\n入口规则: 80/81/10008 -> 目标:81\n全链路额外: 10003 + 7000-7010",
                     gHookInstalled ? @"ACTIVE" : @"FAILED", TargetText(), ModeText(), gRedirectCount, gObserveCount, LastHitText()];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Login IP Redirect v10" message:msg preferredStyle:UIAlertControllerStyleAlert];

    [a addAction:[UIAlertAction actionWithTitle:@"设置目标 IP" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIAlertController *b = [UIAlertController alertControllerWithTitle:@"目标 IPv4" message:@"入口模式会把原 LOGIN_HOST 连接转到该 IP:81" preferredStyle:UIAlertControllerStyleAlert];
        [b addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.text = [TargetText() isEqualToString:@"未设置"] ? @"" : TargetText();
            f.placeholder = @"例如 212.189.107.53";
            f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        }];
        [b addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [b addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            NSString *ip = b.textFields.firstObject.text;
            if (SetTarget(ip, YES)) LogEvent([NSString stringWithFormat:@"TARGET-APPLIED %@", TargetText()]);
            else LogEvent(@"TARGET-INVALID");
        }]];
        [vc presentViewController:b animated:YES completion:nil];
    }]];

    NSString *modeTitle = CurrentMode() == LIRV10ModeFullChain ? @"切换：仅入口→81" : @"切换：全链路";
    [a addAction:[UIAlertAction actionWithTitle:modeTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSInteger next = CurrentMode() == LIRV10ModeFullChain ? LIRV10ModeEntry81 : LIRV10ModeFullChain;
        SetMode(next, YES);
        LogEvent([NSString stringWithFormat:@"MODE-CHANGED %@", ModeText()]);
    }]];

    [a addAction:[UIAlertAction actionWithTitle:@"清除目标 IP" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        ClearTarget(YES);
        LogEvent(@"TARGET-CLEARED");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    if (!gWindow) return;
    CGPoint d = [g translationInView:gWindow];
    CGPoint c = gFloatButton.center;
    c.x += d.x; c.y += d.y;
    CGRect b = gWindow.bounds;
    c.x = MAX(32, MIN(b.size.width - 32, c.x));
    c.y = MAX(27, MIN(b.size.height - 27, c.y));
    gFloatButton.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}
@end

__attribute__((constructor)) static void LoginIPRedirectV10Init(void) {
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSString *ip = [ud stringForKey:PREF_IP_KEY];
        if (!ip.length) ip = [ud stringForKey:LEGACY_V9_IP_KEY];
        if (ip.length) SetTarget(ip, NO);
        if ([ud objectForKey:PREF_MODE_KEY]) SetMode([ud integerForKey:PREF_MODE_KEY], NO);
        else SetMode(LIRV10ModeEntry81, NO);

        NSString *home = NSHomeDirectory();
        if (home.length) gLogPath = [[home stringByAppendingPathComponent:@"Documents/LoginIPRedirect_v10.log"] retain];
        AppendLog(@"\n[LoginIPRedirect v10] loaded");
        AppendLog([NSString stringWithFormat:@"[RULE] original=%s entry=80/81/10008->81 full=+10003,+7000-7010 target=%@ mode=%@", ORIGINAL_IP, TargetText(), ModeText()]);

        dispatch_async(dispatch_get_main_queue(), ^{
            InstallHook();
            LoginIPRedirectV10Target *t = [LoginIPRedirectV10Target shared];
            [NSTimer scheduledTimerWithTimeInterval:0.5 target:t selector:@selector(tick:) userInfo:nil repeats:YES];
        });
    }
}
