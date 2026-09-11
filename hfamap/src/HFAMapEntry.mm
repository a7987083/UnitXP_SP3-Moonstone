#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// fenpingvip v2
// HFAMapUniversal floating shell + NVideo VIP read-only diagnostic.
// All hooks are pass-through: no membership result/status is modified.

typedef void (^HFAVIPGateCompletion)(BOOL allowed);

static UIWindow *HFAWindow(void);
static void HFARefreshPanel(void);
static void HFAInstallHooksIfPossible(void);

static UIView *gPanel = nil;
static UIButton *gFloatingButton = nil;
static UILabel *gValueLabel = nil;
static UILabel *gHookLabel = nil;
static NSString *gLogPath = nil;

static __unsafe_unretained id gVIP = nil;
static BOOL gHooksReady = NO;
static IMP gOrigIsVIP = NULL;
static IMP gOrigUpdateStatus = NULL;
static IMP gOrigJudge = NULL;
static IMP gOrigJudgeReport = NULL;
static IMP gOrigVerify = NULL;

static NSUInteger gIsVIPCalls = 0;
static NSUInteger gVerifyCalls = 0;
static BOOL gGateSeen = NO;
static BOOL gGateAllowed = NO;
static NSInteger gGateOperation = -1;
static NSInteger gGateStatus = -1;
static BOOL gGateVIP = NO;
static BOOL gTransitionSeen = NO;
static NSInteger gTransitionOld = -1;
static NSInteger gTransitionRequested = -1;
static NSInteger gTransitionNew = -1;
static NSInteger gTransitionType = -1;

static void HFALog(NSString *line) {
    if (!line.length) return;
    if (!gLogPath) {
        NSString *home = NSHomeDirectory();
        if (home.length) gLogPath = [[home stringByAppendingPathComponent:@"Documents/HFAMap_NVideoVIP.log"] copy];
    }
    NSLog(@"[HFAMap][NVideoVIP] %@", line);
    if (!gLogPath) return;
    NSString *out = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    @synchronized([NSUserDefaults class]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:gLogPath]) {
            [data writeToFile:gLogPath atomically:YES];
        } else {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
            if (h) {
                [h seekToEndOfFile];
                [h writeData:data];
                [h closeFile];
            }
        }
    }
}

static NSInteger HFAInteger(id obj, const char *name, NSInteger fallback) {
    if (!obj || !name) return fallback;
    SEL sel = sel_registerName(name);
    if (![obj respondsToSelector:sel]) return fallback;
    return ((NSInteger(*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL HFABool(id obj, const char *name, BOOL fallback) {
    if (!obj || !name) return fallback;
    SEL sel = sel_registerName(name);
    if (![obj respondsToSelector:sel]) return fallback;
    return ((BOOL(*)(id, SEL))objc_msgSend)(obj, sel);
}

static id HFASharedVIP(void) {
    if (gVIP) return gVIP;
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return nil;
    SEL shared = sel_registerName("shared");
    if (![(id)cls respondsToSelector:shared]) return nil;
    id vip = ((id(*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (vip) gVIP = vip;
    return vip;
}

static NSInteger HFAStatus(id vip) {
    return HFAInteger(vip, "status", -1);
}

static BOOL HFAOriginalIsVIP(id vip) {
    if (!vip) return NO;
    SEL sel = sel_registerName("isVIP");
    if (gOrigIsVIP) return ((BOOL(*)(id, SEL))gOrigIsVIP)(vip, sel);
    if (![vip respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(vip, sel);
}

static NSString *HFAStatusName(NSInteger status) {
    switch (status) {
        case 0: return @"验证中/失败 · 上次普通";
        case 1: return @"验证中/失败 · 上次VIP";
        case 2: return @"普通用户";
        case 3: return @"VIP";
        default: return @"未知";
    }
}

static NSString *HFAProductName(NSInteger type) {
    switch (type) {
        case 0: return @"Week";
        case 1: return @"Month";
        case 2: return @"Year";
        case 3: return @"Forever";
        default: return @"Unknown";
    }
}

static NSString *HFAConsistency(NSInteger status, BOOL isVIP) {
    if (status < 0 || status > 3) return @"UNKNOWN";
    BOOL expected = (status == 1 || status == 3);
    if (expected != isVIP) return @"CORE CONFLICT";
    if (!gGateSeen) return @"CORE PASS / GATE WAIT";
    if (gGateStatus != status) return @"CORE PASS / GATE STALE";
    if (gGateVIP != isVIP || gGateAllowed != isVIP) return @"GATE CONFLICT";
    return @"PASS";
}

static BOOL HFAIsVIPHook(id self, SEL _cmd) {
    gVIP = self;
    BOOL result = ((BOOL(*)(id, SEL))gOrigIsVIP)(self, _cmd);
    gIsVIPCalls++;
    if (gIsVIPCalls <= 16 || (gIsVIPCalls % 100) == 0) {
        HFALog([NSString stringWithFormat:@"[VIP][ISVIP] count=%lu status=%ld return=%d",
                (unsigned long)gIsVIPCalls, (long)HFAStatus(self), result ? 1 : 0]);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ HFARefreshPanel(); });
    return result;
}

static BOOL HFAUpdateStatusHook(id self, SEL _cmd, NSInteger requested, NSInteger type) {
    gVIP = self;
    NSInteger before = HFAStatus(self);
    BOOL result = ((BOOL(*)(id, SEL, NSInteger, NSInteger))gOrigUpdateStatus)(self, _cmd, requested, type);
    NSInteger after = HFAStatus(self);
    gTransitionSeen = YES;
    gTransitionOld = before;
    gTransitionRequested = requested;
    gTransitionNew = after;
    gTransitionType = type;
    HFALog([NSString stringWithFormat:@"[VIP][TRANSITION] before=%ld requested=%ld after=%ld type=%ld return=%d",
            (long)before, (long)requested, (long)after, (long)type, result ? 1 : 0]);
    dispatch_async(dispatch_get_main_queue(), ^{ HFARefreshPanel(); });
    return result;
}

static void HFARecordGate(id self, NSInteger operation, BOOL allowed, NSString *source) {
    gVIP = self;
    gGateSeen = YES;
    gGateAllowed = allowed;
    gGateOperation = operation;
    gGateStatus = HFAStatus(self);
    gGateVIP = HFAOriginalIsVIP(self);
    HFALog([NSString stringWithFormat:@"[VIP][GATE] source=%@ op=%ld status=%ld isVIP=%d allowed=%d",
            source, (long)operation, (long)gGateStatus, gGateVIP ? 1 : 0, allowed ? 1 : 0]);
    dispatch_async(dispatch_get_main_queue(), ^{ HFARefreshPanel(); });
}

static void HFAJudgeHook(id self, SEL _cmd, NSInteger operation, HFAVIPGateCompletion completion) {
    gVIP = self;
    HFAVIPGateCompletion wrapped = ^(BOOL allowed) {
        HFARecordGate(self, operation, allowed, @"judgeOperationValid");
        if (completion) completion(allowed);
    };
    ((void(*)(id, SEL, NSInteger, HFAVIPGateCompletion))gOrigJudge)(self, _cmd, operation, wrapped);
}

static void HFAJudgeReportHook(id self, SEL _cmd, NSInteger operation, id parameters, HFAVIPGateCompletion completion) {
    gVIP = self;
    HFAVIPGateCompletion wrapped = ^(BOOL allowed) {
        HFARecordGate(self, operation, allowed, @"judgeOperationValid:reportParameters");
        if (completion) completion(allowed);
    };
    ((void(*)(id, SEL, NSInteger, id, HFAVIPGateCompletion))gOrigJudgeReport)(self, _cmd, operation, parameters, wrapped);
}

static void HFAVerifyHook(id self, SEL _cmd) {
    gVIP = self;
    gVerifyCalls++;
    NSInteger before = HFAStatus(self);
    HFALog([NSString stringWithFormat:@"[VIP][VERIFY_BEGIN] count=%lu status=%ld",
            (unsigned long)gVerifyCalls, (long)before]);
    ((void(*)(id, SEL))gOrigVerify)(self, _cmd);
    HFALog([NSString stringWithFormat:@"[VIP][VERIFY_RETURN] count=%lu status=%ld",
            (unsigned long)gVerifyCalls, (long)HFAStatus(self)]);
    dispatch_async(dispatch_get_main_queue(), ^{ HFARefreshPanel(); });
}

static BOOL HFAHook(Class cls, const char *name, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(cls, sel_registerName(name));
    if (!m) {
        HFALog([NSString stringWithFormat:@"[VIP][HOOK_MISSING] %s", name]);
        return NO;
    }
    IMP old = method_getImplementation(m);
    if (!old) return NO;
    if (original) *original = old;
    method_setImplementation(m, replacement);
    HFALog([NSString stringWithFormat:@"[VIP][HOOK_OK] %s types=%s", name, method_getTypeEncoding(m) ?: "?"]);
    return YES;
}

static void HFAInstallHooksIfPossible(void) {
    if (gHooksReady) return;
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return;

    BOOL ok = YES;
    ok &= HFAHook(cls, "isVIP", (IMP)HFAIsVIPHook, &gOrigIsVIP);
    ok &= HFAHook(cls, "updateStatus:type:", (IMP)HFAUpdateStatusHook, &gOrigUpdateStatus);
    ok &= HFAHook(cls, "judgeOperationValid:completion:", (IMP)HFAJudgeHook, &gOrigJudge);
    ok &= HFAHook(cls, "judgeOperationValid:reportParameters:completion:", (IMP)HFAJudgeReportHook, &gOrigJudgeReport);
    ok &= HFAHook(cls, "verifyCurrentStatus", (IMP)HFAVerifyHook, &gOrigVerify);
    gHooksReady = YES;
    HFALog(ok ? @"[VIP][HOOK_READY] all pass-through hooks installed" : @"[VIP][HOOK_PARTIAL] one or more selectors missing");
}

static UIWindow *HFAWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIWindow *window in app.windows) {
        if (window.isKeyWindow && !window.hidden && window.alpha > 0.0) return window;
    }
    for (UIWindow *window in [app.windows reverseObjectEnumerator]) {
        if (!window.hidden && window.alpha > 0.0 && window.windowLevel == UIWindowLevelNormal) return window;
    }
    return app.keyWindow;
}

static NSString *HFAExpiryText(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"vipExpiredTime"];
    return value ? [value description] : @"-";
}

static void HFARefreshPanel(void) {
    if (!gValueLabel) return;
    HFAInstallHooksIfPossible();
    id vip = HFASharedVIP();
    NSInteger status = HFAStatus(vip);
    BOOL isVIP = HFAOriginalIsVIP(vip);
    BOOL freeVIP = HFABool(vip, "isFreeVIP", NO);
    BOOL trial = HFABool(vip, "isFreeTrialVIP", NO);
    BOOL redeem = HFABool(vip, "isRedemptionCodeVIP", NO);
    BOOL weekly = HFABool(vip, "isWeeklySubscription", NO);
    NSInteger product = HFAInteger(vip, "currentProductType", -1);

    NSString *gate = gGateSeen
        ? [NSString stringWithFormat:@"%@  op=%ld", gGateAllowed ? @"ALLOW" : @"DENY", (long)gGateOperation]
        : @"WAIT（实际操作后更新）";
    NSString *transition = gTransitionSeen
        ? [NSString stringWithFormat:@"%ld → %ld (req=%ld,type=%ld)",
           (long)gTransitionOld, (long)gTransitionNew, (long)gTransitionRequested, (long)gTransitionType]
        : @"-";

    gValueLabel.text = [NSString stringWithFormat:
        @"当前等级：%ld\n"
         "状态：%@\n"
         "isVIP：%@   isFreeVIP：%@\n"
         "Gate：%@\n"
         "一致性：%@\n"
         "Product：%ld %@\n"
         "Trial：%@   Redeem：%@   Weekly：%@\n"
         "Transition：%@\n"
         "Verify：%lu   isVIP Calls：%lu\n"
         "Expired：%@",
         (long)status, HFAStatusName(status),
         isVIP ? @"YES" : @"NO", freeVIP ? @"YES" : @"NO",
         gate, HFAConsistency(status, isVIP),
         (long)product, HFAProductName(product),
         trial ? @"YES" : @"NO", redeem ? @"YES" : @"NO", weekly ? @"YES" : @"NO",
         transition, (unsigned long)gVerifyCalls, (unsigned long)gIsVIPCalls,
         HFAExpiryText()];

    gHookLabel.text = gHooksReady ? @"● Probe Ready · 只读/透传" : @"○ Waiting for DIYVIP";
}

@interface HFAVIPFloatingTarget : NSObject
+ (instancetype)shared;
- (void)toggle;
- (void)refresh;
@end

@implementation HFAVIPFloatingTarget
+ (instancetype)shared {
    static HFAVIPFloatingTarget *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [HFAVIPFloatingTarget new]; });
    return obj;
}
- (void)toggle {
    if (!gPanel) return;
    gPanel.hidden = !gPanel.hidden;
    if (!gPanel.hidden) HFARefreshPanel();
}
- (void)refresh { HFARefreshPanel(); }
@end

static BOOL HFAInstallUI(void) {
    if (gFloatingButton.superview) return YES;
    UIWindow *window = HFAWindow();
    if (!window) return NO;

    CGRect bounds = window.bounds;
    CGFloat safeTop = window.safeAreaInsets.top;
    CGFloat buttonSize = 52.0;
    CGFloat bx = MAX(12.0, bounds.size.width - buttonSize - 14.0);
    CGFloat by = MAX(86.0, safeTop + 48.0);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(bx, by, buttonSize, buttonSize);
    button.layer.cornerRadius = buttonSize / 2.0;
    button.layer.masksToBounds = YES;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    [button setTitle:@"HFA" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [button addTarget:[HFAVIPFloatingTarget shared] action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    CGFloat panelW = MIN(336.0, MAX(280.0, bounds.size.width - 24.0));
    CGFloat panelH = 360.0;
    CGFloat panelX = (bounds.size.width - panelW) / 2.0;
    CGFloat panelY = MAX(safeTop + 20.0, (bounds.size.height - panelH) / 2.0);

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.96];
    panel.layer.cornerRadius = 16.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    panel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 14.0, panelW - 32.0, 24.0)];
    title.text = @"HFAMapUniversal";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17.0];
    [panel addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 39.0, panelW - 32.0, 20.0)];
    subtitle.text = @"NVideo VIP Diagnostic";
    subtitle.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    subtitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    [panel addSubview:subtitle];

    UILabel *hook = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 64.0, panelW - 32.0, 20.0)];
    hook.textColor = [UIColor colorWithRed:0.45 green:0.95 blue:0.58 alpha:1.0];
    hook.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
    hook.text = @"○ Waiting for DIYVIP";
    [panel addSubview:hook];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(16.0, 91.0, panelW - 32.0, 1.0)];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [panel addSubview:line];

    UILabel *values = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 101.0, panelW - 32.0, 214.0)];
    values.numberOfLines = 0;
    values.textColor = [UIColor colorWithWhite:0.93 alpha:1.0];
    values.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    values.adjustsFontSizeToFitWidth = YES;
    values.minimumScaleFactor = 0.82;
    [panel addSubview:values];

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.frame = CGRectMake(16.0, panelH - 41.0, panelW - 32.0, 29.0);
    refresh.layer.cornerRadius = 8.0;
    refresh.backgroundColor = [UIColor colorWithRed:0.23 green:0.36 blue:0.92 alpha:1.0];
    [refresh setTitle:@"刷新真实状态" forState:UIControlStateNormal];
    [refresh setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    refresh.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [refresh addTarget:[HFAVIPFloatingTarget shared] action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:refresh];

    [window addSubview:panel];
    [window addSubview:button];
    [window bringSubviewToFront:panel];
    [window bringSubviewToFront:button];

    gPanel = panel;
    gFloatingButton = button;
    gValueLabel = values;
    gHookLabel = hook;

    [title release];
    [subtitle release];
    [hook release];
    [line release];
    [values release];
    [panel release];

    HFARefreshPanel();
    HFALog(@"[VIP][UI_READY] HFAMapUniversal NVideo VIP Diagnostic");
    return YES;
}

static void HFASchedule(NSUInteger attempt) {
    dispatch_async(dispatch_get_main_queue(), ^{
        HFAInstallHooksIfPossible();
        BOOL ui = HFAInstallUI();
        if (ui && gHooksReady) return;
        if (attempt >= 40) {
            HFALog(@"[VIP][INIT_TIMEOUT] UI or DIYVIP not ready after retries");
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            HFASchedule(attempt + 1);
        });
    });
}

__attribute__((constructor))
static void HFANVideoVIPConstructor(void) {
    @autoreleasepool {
        HFALog(@"[VIP][LOAD] HFAMapUniversal fenpingvip v2");
        HFASchedule(0);
    }
}
