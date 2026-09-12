#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <stdarg.h>

typedef void (^HFAVIPGateCompletion)(BOOL allowed);

// fenpingvip v5
// IMPORTANT: this module does NOT create the floating button/window/panel shell.
// HFAMapLegacy.m owns the original HFAMapUniversal floating UI completely.
// This module only replaces the INSIDE of the original panel with NVideo VIP diagnostics.
// v5 fixes the old first-label/app.windows-only lookup by recursively validating
// the exact legacy panel across keyWindow, UIApplication.windows and UIWindowScene.windows.

static IMP gOrigIsVIP = NULL;
static IMP gOrigUpdateStatus = NULL;
static IMP gOrigJudge = NULL;
static IMP gOrigJudgeReport = NULL;
static IMP gOrigVerify = NULL;

static __unsafe_unretained id gVIP = nil;
static BOOL gHooksAttempted = NO;
static BOOL gHooksReady = NO;
static NSUInteger gIsVIPCalls = 0;
static NSUInteger gVerifyCalls = 0;

static BOOL gGateSeen = NO;
static BOOL gGateAllowed = NO;
static NSInteger gGateOperation = -1;
static NSInteger gGateStatus = -1;
static BOOL gGateVIP = NO;
static NSUInteger gGateCount = 0;

static BOOL gTransitionSeen = NO;
static NSInteger gTransitionOld = -1;
static NSInteger gTransitionRequested = -1;
static NSInteger gTransitionNew = -1;
static NSInteger gTransitionType = -1;
static BOOL gTransitionReturn = NO;

static __unsafe_unretained UIView *gHostPanel = nil;
static __unsafe_unretained UILabel *gProbeLabel = nil;
static __unsafe_unretained UILabel *gValueLabel = nil;
static NSString *gLogPath = nil;
static NSUInteger gPanelSearchAttempts = 0;

static void HFALog(NSString *format, ...) {
    if (!format) return;
    if (!gLogPath) {
        NSString *home = NSHomeDirectory();
        if (home.length) gLogPath = [[home stringByAppendingPathComponent:@"Documents/HFAMap_NVideoVIP.log"] copy];
    }
    va_list ap;
    va_start(ap, format);
    NSString *line = [[[NSString alloc] initWithFormat:format arguments:ap] autorelease];
    va_end(ap);
    if (!line) return;
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

static NSString *HFAExpiryText(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"vipExpiredTime"];
    return value ? [value description] : @"-";
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
    if (gIsVIPCalls <= 24 || (gIsVIPCalls % 1000) == 0) {
        HFALog(@"[VIP][ISVIP] count=%lu status=%ld return=%d",
               (unsigned long)gIsVIPCalls, (long)HFAStatus(self), result ? 1 : 0);
    }
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
    HFALog(@"[VIP][TRANSITION] before=%ld requested=%ld after=%ld type=%ld return=%d",
           (long)before, (long)requested, (long)after, (long)type, result ? 1 : 0);
    return result;
}

static void HFARecordGate(id self, NSInteger operation, BOOL allowed, NSString *source) {
    gVIP = self;
    gGateSeen = YES;
    gGateAllowed = allowed;
    gGateOperation = operation;
    gGateStatus = HFAStatus(self);
    gGateVIP = HFAOriginalIsVIP(self);
    gGateCount++;
    HFALog(@"[VIP][GATE] source=%@ op=%ld status=%ld isVIP=%d allowed=%d count=%lu",
           source ?: @"unknown", (long)operation, (long)gGateStatus,
           gGateVIP ? 1 : 0, allowed ? 1 : 0, (unsigned long)gGateCount);
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
    HFALog(@"[VIP][VERIFY_BEGIN] count=%lu status=%ld",
           (unsigned long)gVerifyCalls, (long)HFAStatus(self));
    ((void(*)(id, SEL))gOrigVerify)(self, _cmd);
    HFALog(@"[VIP][VERIFY_RETURN] count=%lu status=%ld",
           (unsigned long)gVerifyCalls, (long)HFAStatus(self));
}

static BOOL HFAHook(Class cls, const char *name, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method) {
        HFALog(@"[VIP][HOOK_MISSING] %s", name);
        return NO;
    }
    IMP old = method_getImplementation(method);
    if (!old) return NO;
    if (original) *original = old;
    method_setImplementation(method, replacement);
    HFALog(@"[VIP][HOOK_OK] %s types=%s", name, method_getTypeEncoding(method) ?: "?");
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

static BOOL HFAViewHasLegacyTitle(UIView *view) {
    if (!view) return NO;
    for (UIView *child in view.subviews) {
        if (![child isKindOfClass:[UILabel class]]) continue;
        NSString *text = ((UILabel *)child).text;
        if ([text rangeOfString:@"HFAMap v1.8.7 Key Register" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL HFAViewHasLegacyScanButton(UIView *view) {
    if (!view) return NO;
    for (UIView *child in view.subviews) {
        if (![child isKindOfClass:[UIButton class]]) continue;
        NSString *title = [(UIButton *)child titleForState:UIControlStateNormal];
        if ([title rangeOfString:@"Auto Detect / Full Scan" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static UIView *HFAFindLegacyPanelInView(UIView *view) {
    if (!view) return nil;
    CGFloat width = view.bounds.size.width;
    if (width >= 250.0 && width <= 450.0 && HFAViewHasLegacyTitle(view) && HFAViewHasLegacyScanButton(view)) {
        return view;
    }
    for (UIView *child in view.subviews) {
        UIView *found = HFAFindLegacyPanelInView(child);
        if (found) return found;
    }
    return nil;
}

static UIView *HFAFindLegacyPanelInWindow(UIWindow *window) {
    if (!window || window.hidden || window.alpha <= 0.0) return nil;
    return HFAFindLegacyPanelInView(window);
}

static UIView *HFAFindOriginalPanel(void) {
    UIApplication *app = [UIApplication sharedApplication];
    gPanelSearchAttempts++;

    UIWindow *key = app.keyWindow;
    UIView *found = HFAFindLegacyPanelInWindow(key);
    if (found) {
        HFALog(@"[VIP][UI_BIND_DIRECT] source=keyWindow attempt=%lu panel=%p", (unsigned long)gPanelSearchAttempts, found);
        return found;
    }

    for (UIWindow *window in app.windows) {
        found = HFAFindLegacyPanelInWindow(window);
        if (found) {
            HFALog(@"[VIP][UI_BIND_DIRECT] source=application.windows attempt=%lu panel=%p", (unsigned long)gPanelSearchAttempts, found);
            return found;
        }
    }

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                found = HFAFindLegacyPanelInWindow(window);
                if (found) {
                    HFALog(@"[VIP][UI_BIND_DIRECT] source=windowScene.windows attempt=%lu panel=%p", (unsigned long)gPanelSearchAttempts, found);
                    return found;
                }
            }
        }
    }

    if (gPanelSearchAttempts <= 20 || (gPanelSearchAttempts % 100) == 0) {
        HFALog(@"[VIP][UI_BIND_WAIT] attempt=%lu key=%p appWindows=%lu",
               (unsigned long)gPanelSearchAttempts, key, (unsigned long)app.windows.count);
    }
    return nil;
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
        ? [NSString stringWithFormat:@"%@ (op=%ld,#%lu)", gGateAllowed ? @"ALLOW" : @"DENY",
           (long)gGateOperation, (unsigned long)gGateCount]
        : @"WAIT（实际操作后更新）";
    NSString *transition = gTransitionSeen
        ? [NSString stringWithFormat:@"%ld → %ld (req=%ld,type=%ld,r=%d)",
           (long)gTransitionOld, (long)gTransitionNew, (long)gTransitionRequested,
           (long)gTransitionType, gTransitionReturn ? 1 : 0]
        : @"-";

    gValueLabel.text = [NSString stringWithFormat:
        @"当前等级：%ld  %@\n"
         "isVIP：%@   isFreeVIP：%@\n"
         "Gate：%@\n"
         "一致性：%@\n"
         "Product：%ld %@\n"
         "Trial：%@  Redeem：%@  Weekly：%@\n"
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
        gProbeLabel.text = @"○ Waiting for DIYVIP";
        gProbeLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    } else if (gHooksReady) {
        gProbeLabel.text = @"● Probe Ready · 只读/透传";
        gProbeLabel.textColor = [UIColor colorWithRed:0.55 green:0.92 blue:0.64 alpha:1.0];
    } else {
        gProbeLabel.text = @"● Probe Partial · 查看日志";
        gProbeLabel.textColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.32 alpha:1.0];
    }
}

@interface HFANVideoVIPPanelTarget : NSObject
+ (instancetype)shared;
- (void)refreshTapped:(id)sender;
- (void)gateTapped:(id)sender;
- (void)timerFired:(NSTimer *)timer;
@end

@implementation HFANVideoVIPPanelTarget
+ (instancetype)shared {
    static HFANVideoVIPPanelTarget *obj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [[HFANVideoVIPPanelTarget alloc] init]; });
    return obj;
}

- (void)refreshTapped:(id)sender {
    (void)sender;
    HFARefreshPanel();
    id vip = HFASharedVIP();
    HFALog(@"[VIP][MANUAL_REFRESH] vip=%p status=%ld isVIP=%d",
           vip, (long)HFAStatus(vip), HFAOriginalIsVIP(vip) ? 1 : 0);
}

- (void)gateTapped:(id)sender {
    (void)sender;
    id vip = HFASharedVIP();
    if (!vip || !gOrigJudge) {
        HFALog(@"[VIP][SELFTEST] unavailable vip=%p origJudge=%p", vip, gOrigJudge);
        return;
    }
    SEL sel = sel_registerName("judgeOperationValid:completion:");
    NSInteger operation = 7;
    HFALog(@"[VIP][SELFTEST_BEGIN] op=%ld status=%ld", (long)operation, (long)HFAStatus(vip));
    HFAVIPGateCompletion completion = ^(BOOL allowed) {
        HFARecordGate(vip, operation, allowed, @"selftest");
        dispatch_async(dispatch_get_main_queue(), ^{ HFARefreshPanel(); });
    };
    ((void(*)(id, SEL, NSInteger, HFAVIPGateCompletion))gOrigJudge)(vip, sel, operation, completion);
}

- (void)timerFired:(NSTimer *)timer {
    (void)timer;
    HFAInstallHooksIfPossible();

    if (!gHostPanel) {
        UIView *panel = HFAFindOriginalPanel();
        if (panel) {
            gHostPanel = panel;

            NSArray *children = [[panel subviews] copy];
            for (UIView *child in children) [child removeFromSuperview];
            [children release];

            CGRect frame = panel.frame;
            frame.size.height = 330.0;
            panel.frame = frame;

            CGFloat w = panel.bounds.size.width;

            UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(14.0, 10.0, w - 28.0, 26.0)] autorelease];
            title.text = @"HFAMapUniversal";
            title.textColor = [UIColor whiteColor];
            title.font = [UIFont boldSystemFontOfSize:18.0];
            [panel addSubview:title];

            UILabel *subtitle = [[[UILabel alloc] initWithFrame:CGRectMake(14.0, 35.0, w - 28.0, 21.0)] autorelease];
            subtitle.text = @"NVideo VIP Diagnostic";
            subtitle.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
            subtitle.font = [UIFont boldSystemFontOfSize:13.0];
            [panel addSubview:subtitle];

            UILabel *probe = [[[UILabel alloc] initWithFrame:CGRectMake(14.0, 58.0, w - 28.0, 20.0)] autorelease];
            probe.font = [UIFont systemFontOfSize:11.5];
            [panel addSubview:probe];
            gProbeLabel = probe;

            UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(14.0, 84.0, w - 28.0, 1.0)] autorelease];
            line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
            [panel addSubview:line];

            UILabel *value = [[[UILabel alloc] initWithFrame:CGRectMake(14.0, 94.0, w - 28.0, 176.0)] autorelease];
            value.textColor = [UIColor colorWithWhite:0.94 alpha:1.0];
            value.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
            value.numberOfLines = 10;
            value.adjustsFontSizeToFitWidth = YES;
            value.minimumScaleFactor = 0.78;
            [panel addSubview:value];
            gValueLabel = value;

            CGFloat bw = (w - 42.0) / 2.0;
            UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
            refresh.frame = CGRectMake(14.0, 282.0, bw, 36.0);
            [refresh setTitle:@"刷新真实状态" forState:UIControlStateNormal];
            [refresh setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            refresh.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
            refresh.backgroundColor = [UIColor colorWithRed:0.18 green:0.31 blue:0.62 alpha:1.0];
            refresh.layer.cornerRadius = 7.0;
            [refresh addTarget:[HFANVideoVIPPanelTarget shared] action:@selector(refreshTapped:) forControlEvents:UIControlEventTouchUpInside];
            [panel addSubview:refresh];

            UIButton *gate = [UIButton buttonWithType:UIButtonTypeSystem];
            gate.frame = CGRectMake(28.0 + bw, 282.0, bw, 36.0);
            [gate setTitle:@"Gate 自检" forState:UIControlStateNormal];
            [gate setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            gate.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
            gate.backgroundColor = [UIColor colorWithRed:0.34 green:0.22 blue:0.52 alpha:1.0];
            gate.layer.cornerRadius = 7.0;
            [gate addTarget:[HFANVideoVIPPanelTarget shared] action:@selector(gateTapped:) forControlEvents:UIControlEventTouchUpInside];
            [panel addSubview:gate];

            HFALog(@"[VIP][UI_REPLACED] v5 original HFAMap panel=%p size=%.0fx%.0f", panel, w, panel.bounds.size.height);
        }
    }

    HFARefreshPanel();
}
@end

__attribute__((constructor))
static void HFANVideoVIPShellAdapterInit(void) {
    @autoreleasepool {
        HFALog(@"[VIP][LOAD] HFAMapUniversal fenpingvip v5 scene-safe shell adapter");
        HFAInstallHooksIfPossible();
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.05
                                             target:[HFANVideoVIPPanelTarget shared]
                                           selector:@selector(timerFired:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
}
