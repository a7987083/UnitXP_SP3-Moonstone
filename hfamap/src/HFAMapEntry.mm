#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// fenpingvip v6
// Final composition for the authorized runtime test build:
//   - Floating entry/lifecycle: v1 HF shell behavior.
//   - Clicked panel/content: v2 NVideo VIP Diagnostic UI.
//   - Level 0/1/2/3: real buttons calling DIYVIP's own updateStatus:type: path.
// No legacy Key Register / Auto Detect / Full Scan UI is created by this file.

typedef void (^HFAVIPGateCompletion)(BOOL allowed);

static UIWindow *HFAWindow(void);
static void HFARefreshPanel(void);
static void HFAInstallHooksIfPossible(void);

static UIView *gPanel = nil;
static UIButton *gFloatingButton = nil;
static UILabel *gValueLabel = nil;
static UILabel *gHookLabel = nil;
static __unsafe_unretained UIWindow *gWindow = nil;
static NSString *gLogPath = nil;

static __unsafe_unretained id gVIP = nil;
static BOOL gHooksReady = NO;
static BOOL gHooksAttempted = NO;
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
static BOOL gTransitionReturn = NO;

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
    gTransitionReturn = result;

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
            source ?: @"unknown", (long)operation, (long)gGateStatus,
            gGateVIP ? 1 : 0, allowed ? 1 : 0]);
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
    HFALog([NSString stringWithFormat:@"[VIP][HOOK_OK] %s types=%s",
            name, method_getTypeEncoding(m) ?: "?"]);
    return YES;
}

static void HFAInstallHooksIfPossible(void) {
    if (gHooksAttempted) return;
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return;

    gHooksAttempted = YES;
    BOOL ok = YES;
    ok &= HFAHook(cls, "isVIP", (IMP)HFAIsVIPHook, &gOrigIsVIP);
    ok &= HFAHook(cls, "updateStatus:type:", (IMP)HFAUpdateStatusHook, &gOrigUpdateStatus);
    ok &= HFAHook(cls, "judgeOperationValid:completion:", (IMP)HFAJudgeHook, &gOrigJudge);
    ok &= HFAHook(cls, "judgeOperationValid:reportParameters:completion:", (IMP)HFAJudgeReportHook, &gOrigJudgeReport);
    ok &= HFAHook(cls, "verifyCurrentStatus", (IMP)HFAVerifyHook, &gOrigVerify);
    gHooksReady = ok;

    HFALog(ok ? @"[VIP][HOOK_READY] all pass-through hooks installed"
               : @"[VIP][HOOK_PARTIAL] one or more selectors missing");
}

// v1 shell semantics: prefer keyWindow, otherwise use the last app window.
static UIWindow *HFAWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *window = app.keyWindow;
    if (window) return window;
    NSArray *windows = app.windows;
    return windows.count ? [windows lastObject] : nil;
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
        ? [NSString stringWithFormat:@"%ld → %ld (req=%ld,type=%ld,r=%d)",
           (long)gTransitionOld, (long)gTransitionNew,
           (long)gTransitionRequested, (long)gTransitionType,
           gTransitionReturn ? 1 : 0]
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

    if (!objc_getClass("DIYVIP")) {
        gHookLabel.text = @"○ Waiting for DIYVIP";
        gHookLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    } else if (gHooksReady) {
        gHookLabel.text = @"● Probe Ready · 只读/透传";
        gHookLabel.textColor = [UIColor colorWithRed:0.45 green:0.95 blue:0.58 alpha:1.0];
    } else {
        gHookLabel.text = @"● Probe Partial · 查看日志";
        gHookLabel.textColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.32 alpha:1.0];
    }
}

static void HFASetRealLevel(NSInteger target) {
    id vip = HFASharedVIP();
    if (!vip) {
        HFALog(@"[VIP][STATE_SET] unavailable: DIYVIP missing");
        return;
    }

    SEL updateSel = sel_registerName("updateStatus:type:");
    if (![vip respondsToSelector:updateSel]) {
        HFALog(@"[VIP][STATE_SET] unavailable: updateStatus:type: missing");
        return;
    }

    NSInteger before = HFAStatus(vip);
    BOOL result = ((BOOL(*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(vip, updateSel, target, 0);
    NSInteger after = HFAStatus(vip);
    BOOL isVIP = HFAOriginalIsVIP(vip);
    BOOL expectedVIP = (target == 1 || target == 3);
    BOOL pass = (after == target && isVIP == expectedVIP);

    HFALog([NSString stringWithFormat:
        @"[VIP][STATE_SET] before=%ld target=%ld after=%ld isVIP=%d updateReturn=%d pass=%d noAutoRestore=1",
        (long)before, (long)target, (long)after,
        isVIP ? 1 : 0, result ? 1 : 0, pass ? 1 : 0]);

    HFARefreshPanel();
}

@interface HFAVIPFloatingTarget : NSObject
+ (instancetype)shared;
- (void)toggle;
- (void)refresh;
- (void)pan:(UIPanGestureRecognizer *)gesture;
- (void)panelPan:(UIPanGestureRecognizer *)gesture;
- (void)setLevel:(UIButton *)sender;
- (void)tick:(NSTimer *)timer;
@end

@implementation HFAVIPFloatingTarget

+ (instancetype)shared {
    static HFAVIPFloatingTarget *obj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [[HFAVIPFloatingTarget alloc] init]; });
    return obj;
}

- (void)toggle {
    if (!gPanel) return;
    gPanel.hidden = !gPanel.hidden;
    if (!gPanel.hidden) HFARefreshPanel();
}

- (void)refresh {
    HFARefreshPanel();
}

- (void)setLevel:(UIButton *)sender {
    NSInteger target = sender.tag;
    if (target < 0 || target > 3) return;
    HFASetRealLevel(target);
}

// Exact v1-style floating-button dragging + edge clamp.
- (void)pan:(UIPanGestureRecognizer *)gesture {
    if (!gFloatingButton || !gWindow) return;
    UIGestureRecognizerState state = gesture.state;
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) return;

    CGPoint translation = [gesture translationInView:gWindow];
    CGPoint center = gFloatingButton.center;
    center.x += translation.x;
    center.y += translation.y;

    CGRect bounds = gWindow.bounds;
    CGFloat half = 26.0;
    if (center.x < half) center.x = half;
    if (center.x > bounds.size.width - half) center.x = bounds.size.width - half;
    if (center.y < half) center.y = half;
    if (center.y > bounds.size.height - half) center.y = bounds.size.height - half;

    gFloatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:gWindow];
}

// Keep v1 shell interaction: the opened panel can also be dragged.
- (void)panelPan:(UIPanGestureRecognizer *)gesture {
    if (!gPanel || !gWindow) return;
    UIGestureRecognizerState state = gesture.state;
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) return;

    CGPoint translation = [gesture translationInView:gWindow];
    CGPoint center = gPanel.center;
    center.x += translation.x;
    center.y += translation.y;
    gPanel.center = center;
    [gesture setTranslation:CGPointZero inView:gWindow];
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    HFAInstallHooksIfPossible();

    UIWindow *window = HFAWindow();
    if (!window) return;

    if (!gFloatingButton || !gPanel) {
        extern BOOL HFAInstallUIOnWindow(UIWindow *window);
        HFAInstallUIOnWindow(window);
    }

    if (gFloatingButton && gPanel && (gWindow != window || !gFloatingButton.superview || !gPanel.superview)) {
        [window addSubview:gPanel];
        [window addSubview:gFloatingButton];
        gWindow = window;
        HFALog(@"[VIP][FLOATING_V1_REATTACH] window changed/recovered");
    }

    if (gPanel && gFloatingButton) {
        [window bringSubviewToFront:gPanel];
        [window bringSubviewToFront:gFloatingButton];
    }
}

@end

BOOL HFAInstallUIOnWindow(UIWindow *window) {
    if (!window) return NO;
    if (gFloatingButton && gPanel) return YES;

    CGRect bounds = window.bounds;
    CGFloat safeTop = window.safeAreaInsets.top;

    // v1 floating shell: 52x52, left side, title "HF", pan-enabled.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(18.0, 165.0, 52.0, 52.0);
    button.layer.cornerRadius = 26.0;
    button.layer.masksToBounds = YES;
    button.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:0.94];
    [button setTitle:@"HF" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [button addTarget:[HFAVIPFloatingTarget shared]
               action:@selector(toggle)
     forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *buttonPan = [[[UIPanGestureRecognizer alloc]
        initWithTarget:[HFAVIPFloatingTarget shared]
                action:@selector(pan:)] autorelease];
    [button addGestureRecognizer:buttonPan];

    // v2 clicked page/content, preserved as the project panel.
    CGFloat panelW = MIN(336.0, MAX(280.0, bounds.size.width - 24.0));
    CGFloat panelH = 420.0;
    CGFloat panelX = (bounds.size.width - panelW) / 2.0;
    CGFloat panelY = MAX(safeTop + 20.0, (bounds.size.height - panelH) / 2.0);

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.96];
    panel.layer.cornerRadius = 16.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    panel.hidden = YES;

    UIPanGestureRecognizer *panelPan = [[[UIPanGestureRecognizer alloc]
        initWithTarget:[HFAVIPFloatingTarget shared]
                action:@selector(panelPan:)] autorelease];
    panelPan.cancelsTouchesInView = NO;
    [panel addGestureRecognizer:panelPan];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 14.0, panelW - 32.0, 24.0)];
    title.text = @"HFAMapUniversal";
    title.textColor = [UIColor whiteColor];
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

    UILabel *levelTitle = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 316.0, panelW - 32.0, 18.0)];
    levelTitle.text = @"真实等级按钮 · 调用 updateStatus:type: · 不自动恢复";
    levelTitle.textColor = [UIColor colorWithWhite:0.76 alpha:1.0];
    levelTitle.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium];
    [panel addSubview:levelTitle];

    CGFloat gap = 6.0;
    CGFloat levelW = (panelW - 32.0 - gap * 3.0) / 4.0;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *level = [UIButton buttonWithType:UIButtonTypeSystem];
        level.tag = i;
        level.frame = CGRectMake(16.0 + (levelW + gap) * i, 337.0, levelW, 32.0);
        [level setTitle:[NSString stringWithFormat:@"等级 %ld", (long)i] forState:UIControlStateNormal];
        [level setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        level.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        level.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.96];
        level.layer.cornerRadius = 7.0;
        level.layer.borderWidth = 0.5;
        level.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        [level addTarget:[HFAVIPFloatingTarget shared]
                  action:@selector(setLevel:)
        forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:level];
    }

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.frame = CGRectMake(16.0, 379.0, panelW - 32.0, 29.0);
    refresh.layer.cornerRadius = 8.0;
    refresh.backgroundColor = [UIColor colorWithRed:0.23 green:0.36 blue:0.92 alpha:1.0];
    [refresh setTitle:@"刷新真实状态" forState:UIControlStateNormal];
    [refresh setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    refresh.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [refresh addTarget:[HFAVIPFloatingTarget shared]
                action:@selector(refresh)
      forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:refresh];

    [window addSubview:panel];
    [window addSubview:button];
    [window bringSubviewToFront:panel];
    [window bringSubviewToFront:button];

    gPanel = panel;
    gFloatingButton = button;
    gValueLabel = values;
    gHookLabel = hook;
    gWindow = window;

    [title release];
    [subtitle release];
    [hook release];
    [line release];
    [values release];
    [levelTitle release];
    [panel release];

    HFARefreshPanel();
    HFALog(@"[VIP][FLOATING_V1_READY] HF 52x52 draggable shell installed");
    HFALog(@"[VIP][UI_READY] v2 NVideo VIP Diagnostic panel + real 0/1/2/3 controls");
    return YES;
}

__attribute__((constructor))
static void HFANVideoVIPConstructor(void) {
    @autoreleasepool {
        HFALog(@"[VIP][LOAD] HFAMapUniversal fenpingvip v6 v1-shell + v2-panel + real-level-buttons");
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                             target:[HFAVIPFloatingTarget shared]
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
}
