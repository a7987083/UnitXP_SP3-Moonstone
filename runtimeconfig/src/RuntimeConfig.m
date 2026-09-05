#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>

#include "../../logintcppayload/vendor/fishhook.h"

#define RC_VERSION @"RuntimeConfig v0.1"
#define ORIGINAL_IP "118.145.146.208"
#define DEFAULT_TARGET_IP "43.242.203.214"
#define PREF_MODE_KEY @"RuntimeConfigV01.Mode"
#define PREF_TARGET_KEY @"RuntimeConfigV01.TargetIPv4"

// dump.cs / AesHelper
#define RVA_CUSTOM_DECRYPT_STRING 0x186A4B8ULL
#define RVA_CUSTOM_DECRYPT_BYTES  0x186FA64ULL

typedef NS_ENUM(NSInteger, RCMode) {
    RCModeFile = 0,       // RuntimeConfig.js -> full decrypted JSON override
    RCModeRedirect = 1,   // original config + connect() redirect
    RCModeLoginHost = 2,  // original config + runtime LOGIN_HOST override only
};

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} RCIl2CppString;

typedef void *(*RCCustomDecryptFn)(void *data, const void *method);
typedef void *(*RCIl2CppStringNewFn)(const char *utf8);
typedef int (*RCConnectFn)(int, const struct sockaddr *, socklen_t);
typedef void (*RCMSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*RCDobbyHookFn)(void *address, void *replace, void **origin);

static RCCustomDecryptFn gOrigDecryptString = NULL;
static RCCustomDecryptFn gOrigDecryptBytes = NULL;
static RCIl2CppStringNewFn gIl2CppStringNew = NULL;
static RCConnectFn gOrigConnect = NULL;

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
static __thread int gInsideDecrypt = 0;
static __thread int gInsideConnect = 0;

static NSInteger gMode = RCModeFile;
static char gTargetIP[INET_ADDRSTRLEN] = {0};
static NSString *gConfigPath = nil;
static NSString *gLogPath = nil;
static NSString *gLastOriginalJSON = nil;
static NSString *gLastOriginalHost = nil;
static NSString *gHookAPI = nil;

static BOOL gDecryptHookInstalled = NO;
static BOOL gConnectHookInstalled = NO;
static unsigned long long gConfigMatchCount = 0;
static unsigned long long gFileOverrideCount = 0;
static unsigned long long gHostOverrideCount = 0;
static unsigned long long gRedirectCount = 0;

static UIWindow *gWindow = nil;
static UIButton *gButton = nil;

#pragma mark - Logging / prefs

static NSString *RCNow(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static void RCLog(NSString *text) {
    if (!text.length) return;
    NSString *line = [NSString stringWithFormat:@"[%@] %@", RCNow(), text];
    NSLog(@"[RuntimeConfig] %@", text);
    if (!gLogPath.length) return;
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

static NSInteger RCGetMode(void) {
    pthread_mutex_lock(&gLock);
    NSInteger mode = gMode;
    pthread_mutex_unlock(&gLock);
    return mode;
}

static void RCSetMode(NSInteger mode, BOOL persist) {
    if (mode < RCModeFile || mode > RCModeLoginHost) mode = RCModeFile;
    pthread_mutex_lock(&gLock);
    gMode = mode;
    pthread_mutex_unlock(&gLock);
    if (persist) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:mode forKey:PREF_MODE_KEY];
        [ud synchronize];
    }
    RCLog([NSString stringWithFormat:@"MODE changed -> %ld (restart recommended)", (long)mode]);
}

static NSString *RCModeText(void) {
    switch (RCGetMode()) {
        case RCModeRedirect: return @"Mode 1 · 原版配置 + connect重定向";
        case RCModeLoginHost: return @"Mode 2 · 运行时仅改LOGIN_HOST";
        default: return @"Mode 0 · RuntimeConfig.js";
    }
}

static BOOL RCSetTargetIP(NSString *text, BOOL persist) {
    NSString *trim = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    struct in_addr addr;
    if (!trim.length || inet_pton(AF_INET, trim.UTF8String, &addr) != 1) return NO;
    pthread_mutex_lock(&gLock);
    snprintf(gTargetIP, sizeof(gTargetIP), "%s", trim.UTF8String);
    pthread_mutex_unlock(&gLock);
    if (persist) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:trim forKey:PREF_TARGET_KEY];
        [ud synchronize];
    }
    RCLog([NSString stringWithFormat:@"TARGET -> %@", trim]);
    return YES;
}

static NSString *RCTargetText(void) {
    char tmp[INET_ADDRSTRLEN] = {0};
    pthread_mutex_lock(&gLock);
    snprintf(tmp, sizeof(tmp), "%s", gTargetIP);
    pthread_mutex_unlock(&gLock);
    return tmp[0] ? [NSString stringWithUTF8String:tmp] : @"未设置";
}

static BOOL RCCopyTarget(char out[INET_ADDRSTRLEN]) {
    pthread_mutex_lock(&gLock);
    snprintf(out, INET_ADDRSTRLEN, "%s", gTargetIP);
    pthread_mutex_unlock(&gLock);
    if (!out[0]) return NO;
    struct in_addr addr;
    return inet_pton(AF_INET, out, &addr) == 1;
}

#pragma mark - IL2CPP string helpers

static NSString *RCNSStringFromIl2Cpp(void *ptr) {
    if (!ptr) return nil;
    RCIl2CppString *s = (RCIl2CppString *)ptr;
    int32_t len = s->length;
    if (len <= 0 || len > (2 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)len] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void *RCMakeIl2CppString(NSString *text) {
    if (!text.length || !gIl2CppStringNew) return NULL;
    const char *utf8 = [text UTF8String];
    if (!utf8) return NULL;
    return gIl2CppStringNew(utf8);
}

static BOOL RCLooksLikeStartupConfig(NSString *text) {
    if (text.length < 64) return NO;
    return [text rangeOfString:@"\"ResVersion\""].location != NSNotFound &&
           [text rangeOfString:@"\"LOGIN_HOST\""].location != NSNotFound &&
           [text rangeOfString:@"\"PACKAGE\""].location != NSNotFound &&
           [text rangeOfString:@"\"FAXINGNAME\""].location != NSNotFound;
}

static NSDictionary *RCJSONObject(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return nil;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![obj isKindOfClass:[NSDictionary class]]) return nil;
    return (NSDictionary *)obj;
}

static BOOL RCWriteTextAtomically(NSString *text, NSString *path) {
    if (!text.length || !path.length) return NO;
    NSError *err = nil;
    BOOL ok = [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) RCLog([NSString stringWithFormat:@"WRITE failed path=%@ err=%@", path, err.localizedDescription ?: @"unknown"]);
    return ok;
}

static void RCRememberOriginal(NSString *text, NSDictionary *obj) {
    pthread_mutex_lock(&gLock);
    [gLastOriginalJSON release];
    gLastOriginalJSON = [text copy];
    [gLastOriginalHost release];
    id host = obj[@"LOGIN_HOST"];
    gLastOriginalHost = [host isKindOfClass:[NSString class]] ? [host copy] : nil;
    pthread_mutex_unlock(&gLock);
}

static void RCExportOriginalIfNeeded(NSString *text) {
    if (!gConfigPath.length) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:gConfigPath]) return;
    if (RCWriteTextAtomically(text, gConfigPath)) {
        RCLog([NSString stringWithFormat:@"EXPORT original config -> %@", gConfigPath]);
    }
}

static NSString *RCLoadExternalConfig(void) {
    if (!gConfigPath.length) return nil;
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfFile:gConfigPath encoding:NSUTF8StringEncoding error:&err];
    if (!text.length) {
        if (err) RCLog([NSString stringWithFormat:@"MODE0 read failed: %@", err.localizedDescription ?: @"unknown"]);
        return nil;
    }
    NSDictionary *obj = RCJSONObject(text);
    if (!obj || !RCLooksLikeStartupConfig(text)) {
        RCLog(@"MODE0 RuntimeConfig.js invalid -> fallback original");
        return nil;
    }
    return text;
}

static NSString *RCBuildLoginHostOverride(NSString *original, NSDictionary *obj) {
    NSMutableDictionary *m = [[obj mutableCopy] autorelease];
    NSString *target = RCTargetText();
    if (!target.length || [target isEqualToString:@"未设置"]) return nil;
    m[@"LOGIN_HOST"] = target;
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:m options:0 error:&err];
    if (err || !data.length) {
        RCLog([NSString stringWithFormat:@"MODE2 JSON encode failed: %@", err.localizedDescription ?: @"unknown"]);
        return nil;
    }
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

static void *RCProcessDecrypted(void *ret, const char *source) {
    if (!ret || gInsideDecrypt) return ret;
    gInsideDecrypt++;
    @autoreleasepool {
        NSString *text = RCNSStringFromIl2Cpp(ret);
        if (!RCLooksLikeStartupConfig(text)) {
            gInsideDecrypt--;
            return ret;
        }

        NSDictionary *obj = RCJSONObject(text);
        if (!obj) {
            RCLog([NSString stringWithFormat:@"MATCH[%s] startup markers but JSON parse failed", source]);
            gInsideDecrypt--;
            return ret;
        }

        __sync_add_and_fetch(&gConfigMatchCount, 1);
        RCRememberOriginal(text, obj);
        RCExportOriginalIfNeeded(text);

        NSString *oldHost = [obj[@"LOGIN_HOST"] isKindOfClass:[NSString class]] ? obj[@"LOGIN_HOST"] : @"?";
        NSInteger mode = RCGetMode();
        RCLog([NSString stringWithFormat:@"MATCH[%s] mode=%ld original LOGIN_HOST=%@", source, (long)mode, oldHost]);

        NSString *replacement = nil;
        if (mode == RCModeFile) {
            replacement = RCLoadExternalConfig();
            if (replacement.length && ![replacement isEqualToString:text]) {
                __sync_add_and_fetch(&gFileOverrideCount, 1);
                NSDictionary *fobj = RCJSONObject(replacement);
                NSString *newHost = [fobj[@"LOGIN_HOST"] isKindOfClass:[NSString class]] ? fobj[@"LOGIN_HOST"] : @"?";
                RCLog([NSString stringWithFormat:@"MODE0 override applied LOGIN_HOST=%@", newHost]);
            }
        } else if (mode == RCModeLoginHost) {
            replacement = RCBuildLoginHostOverride(text, obj);
            if (replacement.length) {
                __sync_add_and_fetch(&gHostOverrideCount, 1);
                RCLog([NSString stringWithFormat:@"MODE2 LOGIN_HOST %@ -> %@", oldHost, RCTargetText()]);
            }
        }

        if (mode == RCModeRedirect) replacement = nil;
        if (replacement.length && ![replacement isEqualToString:text]) {
            void *managed = RCMakeIl2CppString(replacement);
            if (managed) ret = managed;
            else RCLog(@"override prepared but il2cpp_string_new unavailable -> fallback original");
        }
    }
    gInsideDecrypt--;
    return ret;
}

static void *RCHookDecryptString(void *data, const void *method) {
    void *ret = gOrigDecryptString ? gOrigDecryptString(data, method) : NULL;
    return RCProcessDecrypted(ret, "string");
}

static void *RCHookDecryptBytes(void *data, const void *method) {
    void *ret = gOrigDecryptBytes ? gOrigDecryptBytes(data, method) : NULL;
    return RCProcessDecrypted(ret, "bytes");
}

#pragma mark - Internal hook resolution

static void *RCResolveHookSymbol(const char *symbol) {
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    const char *libs[] = {
        "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/var/jb/usr/lib/libsubstrate.dylib",
        "/usr/lib/libhooker.dylib",
        "/var/jb/usr/lib/libhooker.dylib",
        "/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libellekit.dylib"
    };
    for (size_t i = 0; i < sizeof(libs) / sizeof(libs[0]); i++) {
        void *h = dlopen(libs[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, symbol);
        if (p) return p;
    }
    return NULL;
}

static BOOL RCHookAddress(void *address, void *replacement, void **original) {
    RCMSHookFunctionFn ms = (RCMSHookFunctionFn)RCResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (!gHookAPI) gHookAPI = [@"MSHookFunction" retain];
            return YES;
        }
    }
    RCDobbyHookFn dobby = (RCDobbyHookFn)RCResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (!gHookAPI) gHookAPI = [@"DobbyHook" retain];
            return YES;
        }
    }
    return NO;
}

static uintptr_t RCUnityFrameworkBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name, "UnityFramework.framework/UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static void RCResolveIl2CppAPI(void) {
    if (gIl2CppStringNew) return;
    gIl2CppStringNew = (RCIl2CppStringNewFn)dlsym(RTLD_DEFAULT, "il2cpp_string_new");
    if (gIl2CppStringNew) RCLog(@"il2cpp_string_new resolved");
}

static void RCInstallDecryptHooks(uintptr_t base) {
    if (!base || gDecryptHookInstalled) return;
    RCResolveIl2CppAPI();
    void *fn1 = (void *)(base + RVA_CUSTOM_DECRYPT_STRING);
    void *fn2 = (void *)(base + RVA_CUSTOM_DECRYPT_BYTES);
    BOOL ok1 = RCHookAddress(fn1, (void *)RCHookDecryptString, (void **)&gOrigDecryptString);
    BOOL ok2 = RCHookAddress(fn2, (void *)RCHookDecryptBytes, (void **)&gOrigDecryptBytes);
    gDecryptHookInstalled = ok1 || ok2;
    RCLog([NSString stringWithFormat:@"DECRYPT-HOOK base=0x%llx string=%@ bytes=%@ api=%@ stringNew=%@",
           (unsigned long long)base,
           ok1 ? @"YES" : @"NO", ok2 ? @"YES" : @"NO",
           gHookAPI ?: @"none", gIl2CppStringNew ? @"YES" : @"NO"]);
}

static void RCPollDecryptHook(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (gDecryptHookInstalled) return;
        uintptr_t base = RCUnityFrameworkBase();
        if (base) RCInstallDecryptHooks(base);
        if (!gDecryptHookInstalled && attempt < 160) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                RCPollDecryptHook(attempt + 1);
            });
        } else if (!gDecryptHookInstalled) {
            RCLog(@"DECRYPT-HOOK timeout / hook API unavailable");
        }
    });
}

#pragma mark - Mode 1 connect redirect

static BOOL RCResolveRedirectPort(uint16_t srcPort, uint16_t *dstPort) {
    if (srcPort == 80 || srcPort == 81 || srcPort == 10008) {
        if (dstPort) *dstPort = 81;
        return YES;
    }
    if (srcPort == 10003 || (srcPort >= 7000 && srcPort <= 7010)) {
        if (dstPort) *dstPort = srcPort;
        return YES;
    }
    return NO;
}

static int RCHookConnect(int fd, const struct sockaddr *addr, socklen_t len) {
    if (!gOrigConnect) { errno = ENOSYS; return -1; }
    if (gInsideConnect || RCGetMode() != RCModeRedirect) return gOrigConnect(fd, addr, len);
    if (!addr || len < sizeof(struct sockaddr_in) || addr->sa_family != AF_INET) return gOrigConnect(fd, addr, len);

    const struct sockaddr_in *sin = (const struct sockaddr_in *)addr;
    char srcIP[INET_ADDRSTRLEN] = {0};
    if (!inet_ntop(AF_INET, &sin->sin_addr, srcIP, sizeof(srcIP))) return gOrigConnect(fd, addr, len);
    if (strcmp(srcIP, ORIGINAL_IP) != 0) return gOrigConnect(fd, addr, len);

    uint16_t srcPort = ntohs(sin->sin_port);
    uint16_t dstPort = 0;
    if (!RCResolveRedirectPort(srcPort, &dstPort)) return gOrigConnect(fd, addr, len);

    char target[INET_ADDRSTRLEN] = {0};
    if (!RCCopyTarget(target)) return gOrigConnect(fd, addr, len);

    struct sockaddr_in redirected = *sin;
    if (inet_pton(AF_INET, target, &redirected.sin_addr) != 1) return gOrigConnect(fd, addr, len);
    redirected.sin_port = htons(dstPort);

    __sync_add_and_fetch(&gRedirectCount, 1);
    RCLog([NSString stringWithFormat:@"MODE1 REDIRECT fd=%d %s:%u -> %s:%u", fd, srcIP, srcPort, target, dstPort]);

    gInsideConnect++;
    int rc = gOrigConnect(fd, (const struct sockaddr *)&redirected, sizeof(redirected));
    int saved = errno;
    gInsideConnect--;
    errno = saved;
    return rc;
}

static void RCInstallConnectHook(void) {
    gOrigConnect = (RCConnectFn)dlsym(RTLD_DEFAULT, "connect");
    if (!gOrigConnect) {
        RCLog(@"CONNECT-HOOK connect symbol missing");
        return;
    }
    struct rebinding rb = {"connect", (void *)RCHookConnect, (void **)&gOrigConnect};
    int rc = rebind_symbols(&rb, 1);
    gConnectHookInstalled = (rc == 0 && gOrigConnect != NULL);
    RCLog([NSString stringWithFormat:@"CONNECT-HOOK installed=%@ rc=%d", gConnectHookInstalled ? @"YES" : @"NO", rc]);
}

#pragma mark - UI

static UIViewController *RCTopViewController(void) {
    UIWindow *w = gWindow ?: [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) vc = [(UINavigationController *)vc topViewController];
    if ([vc isKindOfClass:[UITabBarController class]]) vc = [(UITabBarController *)vc selectedViewController];
    return vc;
}

@interface RuntimeConfigTarget : NSObject
+ (instancetype)shared;
- (void)tick:(NSTimer *)timer;
- (void)tap:(id)sender;
- (void)pan:(UIPanGestureRecognizer *)g;
@end

@implementation RuntimeConfigTarget
+ (instancetype)shared {
    static RuntimeConfigTarget *obj;
    if (!obj) obj = [[self alloc] init];
    return obj;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];
    return app.keyWindow ?: app.windows.lastObject;
}

- (void)makeButton:(UIWindow *)w {
    if (gButton || !w) return;
    gWindow = w;
    gButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gButton.frame = CGRectMake(18, 225, 58, 58);
    gButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    gButton.layer.cornerRadius = 29;
    gButton.layer.borderWidth = 1.0;
    gButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    [gButton setTitle:@"RC" forState:UIControlStateNormal];
    gButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [gButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)] autorelease];
    [gButton addGestureRecognizer:pan];
    [w addSubview:gButton];
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *w = [self currentWindow];
    if (!w) return;
    if (!gButton) [self makeButton:w];
    if (gWindow != w) {
        [w addSubview:gButton];
        gWindow = w;
    }
    [w bringSubviewToFront:gButton];
}

- (void)tap:(id)sender {
    (void)sender;
    UIViewController *vc = RCTopViewController();
    if (!vc) return;

    NSString *host = nil;
    pthread_mutex_lock(&gLock);
    host = [gLastOriginalHost copy];
    pthread_mutex_unlock(&gLock);

    NSString *msg = [NSString stringWithFormat:@"%@\n\n模式: %@\n目标IP: %@\nDecrypt Hook: %@ (%@)\nconnect Hook: %@\n原版LOGIN_HOST: %@\n命中:%llu  文件覆盖:%llu  Host覆盖:%llu  Redirect:%llu\n\n文件: Documents/RuntimeConfig.js\n修改模式后建议重启游戏。",
                     RC_VERSION, RCModeText(), RCTargetText(),
                     gDecryptHookInstalled ? @"ACTIVE" : @"WAIT/FAILED", gHookAPI ?: @"none",
                     gConnectHookInstalled ? @"ACTIVE" : @"FAILED",
                     host ?: @"尚未捕获",
                     gConfigMatchCount, gFileOverrideCount, gHostOverrideCount, gRedirectCount];
    [host release];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Runtime Config" message:msg preferredStyle:UIAlertControllerStyleAlert];

    [a addAction:[UIAlertAction actionWithTitle:@"Mode 0 · JS配置" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        RCSetMode(RCModeFile, YES);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Mode 1 · connect重定向" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        RCSetMode(RCModeRedirect, YES);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Mode 2 · 仅改LOGIN_HOST" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        RCSetMode(RCModeLoginHost, YES);
    }]];

    [a addAction:[UIAlertAction actionWithTitle:@"设置目标 IP" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIAlertController *b = [UIAlertController alertControllerWithTitle:@"目标 IPv4" message:@"Mode 1 / Mode 2 共用。默认 43.242.203.214" preferredStyle:UIAlertControllerStyleAlert];
        [b addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.text = RCTargetText();
            f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        }];
        [b addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [b addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *z) {
            NSString *ip = b.textFields.firstObject.text;
            if (!RCSetTargetIP(ip, YES)) RCLog(@"TARGET invalid IPv4");
        }]];
        [vc presentViewController:b animated:YES completion:nil];
    }]];

    [a addAction:[UIAlertAction actionWithTitle:@"重导原版 RuntimeConfig.js" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *original = nil;
        pthread_mutex_lock(&gLock);
        original = [gLastOriginalJSON copy];
        pthread_mutex_unlock(&gLock);
        if (original.length) {
            if (RCWriteTextAtomically(original, gConfigPath)) RCLog(@"RuntimeConfig.js reset to captured original");
        } else {
            RCLog(@"cannot re-export: startup config not captured yet");
        }
        [original release];
    }]];

    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    if (!gWindow || !gButton) return;
    CGPoint d = [g translationInView:gWindow];
    CGPoint c = gButton.center;
    c.x += d.x;
    c.y += d.y;
    CGRect b = gWindow.bounds;
    c.x = MAX(29, MIN(b.size.width - 29, c.x));
    c.y = MAX(29, MIN(b.size.height - 29, c.y));
    gButton.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}
@end

static void RCScheduleUI(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RuntimeConfigTarget *t = [RuntimeConfigTarget shared];
        [t tick:nil];
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:t selector:@selector(tick:) userInfo:nil repeats:YES];
    });
}

#pragma mark - Entry

__attribute__((constructor)) static void RuntimeConfigInit(void) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (home.length) {
            gConfigPath = [[home stringByAppendingPathComponent:@"Documents/RuntimeConfig.js"] retain];
            gLogPath = [[home stringByAppendingPathComponent:@"Documents/RuntimeConfig_v0.1.log"] retain];
        }

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:PREF_MODE_KEY]) RCSetMode([ud integerForKey:PREF_MODE_KEY], NO);
        else RCSetMode(RCModeFile, NO);

        NSString *target = [ud stringForKey:PREF_TARGET_KEY];
        if (!target.length) target = @DEFAULT_TARGET_IP;
        RCSetTargetIP(target, NO);

        RCLog(@"\n========== RuntimeConfig v0.1 loaded ==========");
        RCLog([NSString stringWithFormat:@"mode=%@ target=%@", RCModeText(), RCTargetText()]);
        RCLog([NSString stringWithFormat:@"config=%@", gConfigPath ?: @"(none)"]);
        RCLog([NSString stringWithFormat:@"RVA string=0x%llx bytes=0x%llx", RVA_CUSTOM_DECRYPT_STRING, RVA_CUSTOM_DECRYPT_BYTES]);

        RCInstallConnectHook();
        RCPollDecryptHook(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RCScheduleUI();
        });
    }
}
