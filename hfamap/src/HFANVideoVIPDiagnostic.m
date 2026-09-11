#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <string.h>
#import <stdarg.h>

typedef void (^HFANVideoGateCompletion)(BOOL allowed);

static IMP gOrigIsVIP = NULL;
static IMP gOrigUpdateStatus = NULL;
static IMP gOrigJudge = NULL;
static IMP gOrigJudgeReport = NULL;
static IMP gOrigVerify = NULL;

static __unsafe_unretained id gVIPInstance = nil;
static BOOL gHooksInstalled = NO;

static NSInteger gLastStatus = -1;
static BOOL gLastIsVIP = NO;
static BOOL gLastIsVIPSeen = NO;

static BOOL gGateSeen = NO;
static BOOL gGateAllowed = NO;
static NSInteger gGateOperation = -1;
static NSInteger gGateStatusAtResult = -1;
static BOOL gGateVIPAtResult = NO;
static NSUInteger gGateCount = 0;

static BOOL gTransitionSeen = NO;
static NSInteger gTransitionOld = -1;
static NSInteger gTransitionNew = -1;
static NSInteger gTransitionType = -1;
static BOOL gTransitionReturn = NO;

static NSUInteger gVerifyCount = 0;
static NSUInteger gIsVIPCount = 0;

static __unsafe_unretained UIView *gHostPanel = nil;
static __unsafe_unretained UIView *gDiagnosticView = nil;
static __unsafe_unretained UILabel *gDiagnosticLabel = nil;
static __unsafe_unretained UILabel *gDiagnosticHeader = nil;
static __unsafe_unretained UIButton *gRefreshButton = nil;
static __unsafe_unretained UIButton *gGateButton = nil;

static NSString *gLogPath = nil;

static NSInteger HFANVideoStatus(id vip) {
    if (!vip) return -1;
    SEL sel = sel_registerName("status");
    if (![vip respondsToSelector:sel]) return -1;
    return ((NSInteger(*)(id, SEL))objc_msgSend)(vip, sel);
}

static BOOL HFANVideoOriginalIsVIP(id vip) {
    if (!vip) return NO;
    SEL sel = sel_registerName("isVIP");
    if (gOrigIsVIP) {
        return ((BOOL(*)(id, SEL))gOrigIsVIP)(vip, sel);
    }
    if (![vip respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(vip, sel);
}

static BOOL HFANVideoBoolSelector(id obj, const char *name) {
    if (!obj || !name) return NO;
    SEL sel = sel_registerName(name);
    if (![obj respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSInteger HFANVideoIntegerSelector(id obj, const char *name, NSInteger fallback) {
    if (!obj || !name) return fallback;
    SEL sel = sel_registerName(name);
    if (![obj respondsToSelector:sel]) return fallback;
    return ((NSInteger(*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSString *HFANVideoStatusName(NSInteger status) {
    switch (status) {
        case 0: return @"验证中/失败 · 上次普通";
        case 1: return @"验证中/失败 · 上次VIP";
        case 2: return @"普通用户";
        case 3: return @"VIP";
        default: return @"未知";
    }
}

static NSString *HFANVideoProductName(NSInteger type) {
    switch (type) {
        case 0: return @"Week";
        case 1: return @"Month";
        case 2: return @"Year";
        case 3: return @"Forever";
        default: return @"Unknown";
    }
}

static void HFANVideoEnsureLogPath(void) {
    if (gLogPath) return;
    NSString *home = NSHomeDirectory();
    if (!home.length) return;
    gLogPath = [[home stringByAppendingPathComponent:@"Documents/HFAMap_NVideoVIP.log"] copy];
}

static void HFANVideoLog(NSString *format, ...) {
    HFANVideoEnsureLogPath();
    if (!gLogPath || !format) return;

    va_list args;
    va_start(args, format);
    NSString *line = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);
    if (!line) return;

    NSString *final = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    NSData *payload = [final dataUsingEncoding:NSUTF8StringEncoding];
    if (!payload) return;

    @synchronized([NSUserDefaults class]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:gLogPath]) {
            [payload writeToFile:gLogPath atomically:YES];
        } else {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
            [h seekToEndOfFile];
            [h writeData:payload];
            [h closeFile];
        }
    }
}

static id HFANVideoSharedVIP(void) {
    if (gVIPInstance) return gVIPInstance;
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return nil;
    SEL sharedSel = sel_registerName("shared");
    if (![(id)cls respondsToSelector:sharedSel]) return nil;
    id vip = ((id(*)(id, SEL))objc_msgSend)((id)cls, sharedSel);
    if (vip) gVIPInstance = vip;
    return vip;
}

static void HFANVideoRecordGate(id vip, NSInteger operation, BOOL allowed, NSString *source) {
    gVIPInstance = vip;
    gGateSeen = YES;
    gGateAllowed = allowed;
    gGateOperation = operation;
    gGateStatusAtResult = HFANVideoStatus(vip);
    gGateVIPAtResult = HFANVideoOriginalIsVIP(vip);
    gGateCount++;

    HFANVideoLog(@"[VIP][GATE] source=%@ op=%ld status=%ld isVIP=%d allowed=%d count=%lu",
                 source ?: @"unknown",
                 (long)operation,
                 (long)gGateStatusAtResult,
                 gGateVIPAtResult ? 1 : 0,
                 allowed ? 1 : 0,
                 (unsigned long)gGateCount);
}

static BOOL HFANVideoIsVIPHook(id self, SEL _cmd) {
    gVIPInstance = self;
    BOOL result = ((BOOL(*)(id, SEL))gOrigIsVIP)(self, _cmd);
    NSInteger status = HFANVideoStatus(self);

    NSInteger previousStatus = gLastStatus;
    BOOL previousResult = gLastIsVIP;
    BOOL hadPrevious = gLastIsVIPSeen;

    gLastStatus = status;
    gLastIsVIP = result;
    gLastIsVIPSeen = YES;
    gIsVIPCount++;

    if (!hadPrevious || previousStatus != status || previousResult != result || gIsVIPCount <= 32 || (gIsVIPCount % 100) == 0) {
        HFANVideoLog(@"[VIP][ISVIP] count=%lu status=%ld return=%d",
                     (unsigned long)gIsVIPCount, (long)status, result ? 1 : 0);
    }
    return result;
}

static BOOL HFANVideoUpdateStatusHook(id self, SEL _cmd, NSInteger status, NSInteger type) {
    gVIPInstance = self;
    NSInteger before = HFANVideoStatus(self);
    BOOL result = ((BOOL(*)(id, SEL, NSInteger, NSInteger))gOrigUpdateStatus)(self, _cmd, status, type);
    NSInteger after = HFANVideoStatus(self);

    gTransitionSeen = YES;
    gTransitionOld = before;
    gTransitionNew = after;
    gTransitionType = type;
    gTransitionReturn = result;

    HFANVideoLog(@"[VIP][TRANSITION] before=%ld requested=%ld after=%ld type=%ld return=%d",
                 (long)before, (long)status, (long)after, (long)type, result ? 1 : 0);
    return result;
}

static void HFANVideoJudgeHook(id self, SEL _cmd, NSInteger operation, HFANVideoGateCompletion completion) {
    gVIPInstance = self;
    HFANVideoGateCompletion wrapped = ^(BOOL allowed) {
        HFANVideoRecordGate(self, operation, allowed, @"judgeOperationValid");
        if (completion) completion(allowed);
    };
    ((void(*)(id, SEL, NSInteger, HFANVideoGateCompletion))gOrigJudge)(self, _cmd, operation, wrapped);
}

static void HFANVideoJudgeReportHook(id self, SEL _cmd, NSInteger operation, id parameters, HFANVideoGateCompletion completion) {
    gVIPInstance = self;
    HFANVideoGateCompletion wrapped = ^(BOOL allowed) {
        HFANVideoRecordGate(self, operation, allowed, @"judgeOperationValid:reportParameters");
        if (completion) completion(allowed);
    };
    ((void(*)(id, SEL, NSInteger, id, HFANVideoGateCompletion))gOrigJudgeReport)(self, _cmd, operation, parameters, wrapped);
}

static void HFANVideoVerifyHook(id self, SEL _cmd) {
    gVIPInstance = self;
    gVerifyCount++;
    NSInteger before = HFANVideoStatus(self);
    HFANVideoLog(@"[VIP][VERIFY_BEGIN] count=%lu status=%ld",
                 (unsigned long)gVerifyCount, (long)before);
    ((void(*)(id, SEL))gOrigVerify)(self, _cmd);
    NSInteger after = HFANVideoStatus(self);
    HFANVideoLog(@"[VIP][VERIFY_RETURN] count=%lu status=%ld",
                 (unsigned long)gVerifyCount, (long)after);
}

static BOOL HFANVideoInstallOneHook(Class cls,
                                    const char *selectorName,
                                    IMP replacement,
                                    IMP *originalOut,
                                    const char *expectedTypes) {
    SEL sel = sel_registerName(selectorName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        HFANVideoLog(@"[VIP][HOOK_MISSING] selector=%s", selectorName);
        return NO;
    }

    const char *types = method_getTypeEncoding(method);
    if (expectedTypes && types && strcmp(types, expectedTypes) != 0) {
        HFANVideoLog(@"[VIP][HOOK_ABI_MISMATCH] selector=%s expected=%s actual=%s",
                     selectorName, expectedTypes, types);
        return NO;
    }

    IMP original = method_getImplementation(method);
    if (!original) return NO;
    if (originalOut) *originalOut = original;
    method_setImplementation(method, replacement);

    HFANVideoLog(@"[VIP][HOOK_OK] selector=%s types=%s original=%p replacement=%p",
                 selectorName, types ?: "?", original, replacement);
    return YES;
}

static void HFANVideoInstallHooksIfPossible(void) {
    if (gHooksInstalled) return;
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return;

    BOOL ok = YES;
    ok &= HFANVideoInstallOneHook(cls, "isVIP",
                                  (IMP)HFANVideoIsVIPHook, &gOrigIsVIP,
                                  "B16@0:8");
    ok &= HFANVideoInstallOneHook(cls, "updateStatus:type:",
                                  (IMP)HFANVideoUpdateStatusHook, &gOrigUpdateStatus,
                                  "B32@0:8q16q24");
    ok &= HFANVideoInstallOneHook(cls, "judgeOperationValid:completion:",
                                  (IMP)HFANVideoJudgeHook, &gOrigJudge,
                                  "v32@0:8q16@?24");
    ok &= HFANVideoInstallOneHook(cls, "judgeOperationValid:reportParameters:completion:",
                                  (IMP)HFANVideoJudgeReportHook, &gOrigJudgeReport,
                                  "v40@0:8q16@24@?32");
    ok &= HFANVideoInstallOneHook(cls, "verifyCurrentStatus",
                                  (IMP)HFANVideoVerifyHook, &gOrigVerify,
                                  "v16@0:8");

    if (ok) {
        gHooksInstalled = YES;
        HFANVideoLog(@"[VIP][HOOKS_READY] class=%s", class_getName(cls));
    } else {
        HFANVideoLog(@"[VIP][HOOKS_PARTIAL] waiting/retrying is disabled for ABI safety");
        gHooksInstalled = YES;
    }
}

static UILabel *HFANVideoFindHFATitleLabel(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        NSString *text = label.text;
        if ([text rangeOfString:@"HFAMap" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return label;
        }
    }
    for (UIView *sub in view.subviews) {
        UILabel *found = HFANVideoFindHFATitleLabel(sub);
        if (found) return found;
    }
    return nil;
}

static UIView *HFANVideoFindHFAPanel(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *window in app.windows) {
        if (window.hidden || window.alpha <= 0.0) continue;
        UILabel *title = HFANVideoFindHFATitleLabel(window);
        if (!title) continue;
        UIView *candidate = title.superview;
        if (candidate && candidate.bounds.size.width >= 250.0) {
            return candidate;
        }
    }
    return nil;
}

static NSString *HFANVideoExpiryDescription(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"vipExpiredTime"];
    if (!value) return @"-";
    NSString *text = [value description];
    if (text.length > 30) {
        return [text substringToIndex:30];
    }
    return text;
}

static NSString *HFANVideoConsistency(NSInteger status, BOOL isVIP) {
    if (status < 0 || status > 3) return @"UNKNOWN";
    BOOL expected = (status == 1 || status == 3);
    if (expected != isVIP) return @"CORE CONFLICT";

    if (!gGateSeen) return @"CORE PASS / GATE WAIT";
    if (gGateStatusAtResult != status) return @"CORE PASS / GATE STALE";
    if (gGateAllowed != isVIP) return @"GATE CONFLICT";
    return @"PASS";
}

static void HFANVideoRefreshUI(void) {
    if (!gDiagnosticLabel) return;

    id vip = HFANVideoSharedVIP();
    NSInteger status = HFANVideoStatus(vip);
    BOOL isVIP = HFANVideoOriginalIsVIP(vip);
    BOOL isFree = HFANVideoBoolSelector(vip, "isFreeVIP");
    BOOL trial = HFANVideoBoolSelector(vip, "isFreeTrialVIP");
    BOOL redeem = HFANVideoBoolSelector(vip, "isRedemptionCodeVIP");
    BOOL weekly = HFANVideoBoolSelector(vip, "isWeeklySubscription");
    NSInteger product = HFANVideoIntegerSelector(vip, "currentProductType", -1);

    gLastStatus = status;
    gLastIsVIP = isVIP;
    gLastIsVIPSeen = (vip != nil);

    NSString *gate = gGateSeen
        ? [NSString stringWithFormat:@"%@ (op=%ld, #%lu)",
           gGateAllowed ? @"ALLOW" : @"DENY",
           (long)gGateOperation,
           (unsigned long)gGateCount]
        : @"WAIT";

    NSString *transition = gTransitionSeen
        ? [NSString stringWithFormat:@"%ld → %ld (type=%ld,r=%d)",
           (long)gTransitionOld,
           (long)gTransitionNew,
           (long)gTransitionType,
           gTransitionReturn ? 1 : 0]
        : @"-";

    NSString *text =
        [NSString stringWithFormat:
         @"当前等级: %ld  %@\n"
          "isVIP: %@   isFreeVIP: %@\n"
          "Gate: %@\n"
          "一致性: %@\n"
          "Product: %ld %@\n"
          "Trial:%@  Redeem:%@  Weekly:%@\n"
          "Transition: %@\n"
          "Verify:%lu  isVIPCalls:%lu\nExpired:%@",
         (long)status,
         HFANVideoStatusName(status),
         isVIP ? @"YES" : @"NO",
         isFree ? @"YES" : @"NO",
         gate,
         HFANVideoConsistency(status, isVIP),
         (long)product,
         HFANVideoProductName(product),
         trial ? @"Y" : @"N",
         redeem ? @"Y" : @"N",
         weekly ? @"Y" : @"N",
         transition,
         (unsigned long)gVerifyCount,
         (unsigned long)gIsVIPCount,
         HFANVideoExpiryDescription()];

    gDiagnosticLabel.text = text;
}

@interface HFANVideoVIPTarget : NSObject
+ (instancetype)shared;
- (void)refreshTapped:(id)sender;
- (void)gateTapped:(id)sender;
- (void)timerFired:(NSTimer *)timer;
@end

@implementation HFANVideoVIPTarget

+ (instancetype)shared {
    static HFANVideoVIPTarget *target = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[HFANVideoVIPTarget alloc] init];
    });
    return target;
}

- (void)refreshTapped:(id)sender {
    (void)sender;
    HFANVideoRefreshUI();
    id vip = HFANVideoSharedVIP();
    HFANVideoLog(@"[VIP][MANUAL_REFRESH] vip=%p status=%ld isVIP=%d",
                 vip,
                 (long)HFANVideoStatus(vip),
                 HFANVideoOriginalIsVIP(vip) ? 1 : 0);
}

- (void)gateTapped:(id)sender {
    (void)sender;
    id vip = HFANVideoSharedVIP();
    if (!vip || !gOrigJudge) {
        HFANVideoLog(@"[VIP][SELFTEST] unavailable vip=%p origJudge=%p", vip, gOrigJudge);
        return;
    }

    SEL sel = sel_registerName("judgeOperationValid:completion:");
    NSInteger operation = 7; // DIYVIPLimitationNameNone
    HFANVideoLog(@"[VIP][SELFTEST_BEGIN] op=%ld status=%ld",
                 (long)operation, (long)HFANVideoStatus(vip));

    HFANVideoGateCompletion completion = ^(BOOL allowed) {
        HFANVideoRecordGate(vip, operation, allowed, @"selftest");
        dispatch_async(dispatch_get_main_queue(), ^{
            HFANVideoRefreshUI();
        });
    };

    ((void(*)(id, SEL, NSInteger, HFANVideoGateCompletion))gOrigJudge)(vip, sel, operation, completion);
}

- (void)timerFired:(NSTimer *)timer {
    (void)timer;
    HFANVideoInstallHooksIfPossible();

    if (!objc_getClass("DIYVIP")) return;

    if (!gDiagnosticView) {
        UIView *panel = HFANVideoFindHFAPanel();
        if (panel) {
            gHostPanel = panel;

            CGFloat baseHeight = panel.bounds.size.height;
            CGFloat extensionHeight = 222.0;

            CGRect panelFrame = panel.frame;
            panelFrame.size.height = baseHeight + extensionHeight;
            panel.frame = panelFrame;

            UIView *section = [[[UIView alloc] initWithFrame:
                                CGRectMake(0.0, baseHeight,
                                           panel.bounds.size.width,
                                           extensionHeight)] autorelease];
            section.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.98];

            UIView *separator = [[[UIView alloc] initWithFrame:
                                  CGRectMake(12.0, 0.0,
                                             panel.bounds.size.width - 24.0,
                                             1.0)] autorelease];
            separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
            [section addSubview:separator];

            UILabel *header = [[[UILabel alloc] initWithFrame:
                                CGRectMake(14.0, 7.0,
                                           panel.bounds.size.width - 28.0,
                                           22.0)] autorelease];
            header.text = @"NVideo VIP Diagnostic · Read Only";
            header.font = [UIFont boldSystemFontOfSize:13.0];
            header.textColor = [UIColor whiteColor];
            header.backgroundColor = [UIColor clearColor];
            [section addSubview:header];

            UILabel *label = [[[UILabel alloc] initWithFrame:
                               CGRectMake(14.0, 31.0,
                                          panel.bounds.size.width - 28.0,
                                          145.0)] autorelease];
            label.font = [UIFont systemFontOfSize:10.5];
            label.textColor = [UIColor colorWithWhite:0.90 alpha:1.0];
            label.backgroundColor = [UIColor clearColor];
            label.numberOfLines = 10;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.78;
            [section addSubview:label];

            CGFloat buttonWidth = (panel.bounds.size.width - 42.0) / 2.0;

            UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
            refresh.frame = CGRectMake(14.0, 179.0, buttonWidth, 34.0);
            [refresh setTitle:@"刷新真实状态" forState:UIControlStateNormal];
            refresh.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
            [refresh setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            refresh.backgroundColor = [UIColor colorWithRed:0.16 green:0.31 blue:0.58 alpha:1.0];
            refresh.layer.cornerRadius = 7.0;
            [refresh addTarget:[HFANVideoVIPTarget shared]
                        action:@selector(refreshTapped:)
              forControlEvents:UIControlEventTouchUpInside];
            [section addSubview:refresh];

            UIButton *gate = [UIButton buttonWithType:UIButtonTypeSystem];
            gate.frame = CGRectMake(28.0 + buttonWidth, 179.0, buttonWidth, 34.0);
            [gate setTitle:@"Gate 自检" forState:UIControlStateNormal];
            gate.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
            [gate setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            gate.backgroundColor = [UIColor colorWithRed:0.36 green:0.22 blue:0.52 alpha:1.0];
            gate.layer.cornerRadius = 7.0;
            [gate addTarget:[HFANVideoVIPTarget shared]
                     action:@selector(gateTapped:)
           forControlEvents:UIControlEventTouchUpInside];
            [section addSubview:gate];

            [panel addSubview:section];

            gDiagnosticView = section;
            gDiagnosticLabel = label;
            gDiagnosticHeader = header;
            gRefreshButton = refresh;
            gGateButton = gate;

            HFANVideoLog(@"[VIP][UI_ATTACH] host=%p baseHeight=%.1f newHeight=%.1f",
                         panel, baseHeight, panel.bounds.size.height);
        }
    }

    HFANVideoRefreshUI();
}

@end

__attribute__((constructor))
static void HFANVideoVIPDiagnosticInit(void) {
    @autoreleasepool {
        HFANVideoEnsureLogPath();
        HFANVideoLog(@"[VIP][LOAD] HFAMapUniversal NVideo VIP Diagnostic v1");
        HFANVideoInstallHooksIfPossible();
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                             target:[HFANVideoVIPTarget shared]
                                           selector:@selector(timerFired:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
}
