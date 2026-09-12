#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// fenpingvip v4
// Real DIYVIP object state-machine verifier.
// It temporarily writes DIYVIP::_status only inside one synchronous test call,
// calls the app's real -status and -isVIP, then restores the original raw value
// before returning. It does not persist membership state, touch receipts, or run
// business Gate while a synthetic status is active.

static __unsafe_unretained UIView *gVerifierPanel = nil;
static __unsafe_unretained UILabel *gVerifierResultLabel = nil;
static NSString *gLastVerifierResult = nil;

static NSInteger HFAStatus(id vip) {
    if (!vip) return -1;
    SEL sel = sel_registerName("status");
    if (![vip respondsToSelector:sel]) return -1;
    return ((NSInteger(*)(id, SEL))objc_msgSend)(vip, sel);
}

static BOOL HFAIsVIP(id vip) {
    if (!vip) return NO;
    SEL sel = sel_registerName("isVIP");
    if (![vip respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(vip, sel);
}

static id HFASharedVIP(void) {
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return nil;
    SEL shared = sel_registerName("shared");
    if (![(id)cls respondsToSelector:shared]) return nil;
    return ((id(*)(id, SEL))objc_msgSend)((id)cls, shared);
}

static UILabel *HFAFindLabelWithText(UIView *view, NSString *needle) {
    if (!view || !needle.length) return nil;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if ([label.text rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return label;
    }
    for (UIView *sub in view.subviews) {
        UILabel *found = HFAFindLabelWithText(sub, needle);
        if (found) return found;
    }
    return nil;
}

static UIView *HFAFindDiagnosticPanel(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *window in app.windows) {
        if (window.hidden || window.alpha <= 0.0) continue;
        UILabel *subtitle = HFAFindLabelWithText(window, @"NVideo VIP Diagnostic");
        if (!subtitle) continue;
        UIView *panel = subtitle.superview;
        if (panel && panel.bounds.size.width >= 300.0 && panel.bounds.size.width <= 360.0) return panel;
    }
    return nil;
}

static void HFASetVerifierResult(NSString *text) {
    if (gLastVerifierResult != text) {
        [gLastVerifierResult release];
        gLastVerifierResult = [text copy];
    }
    if (gVerifierResultLabel) gVerifierResultLabel.text = gLastVerifierResult ?: @"尚未测试";
}

static void HFARunStatusTest(NSInteger target) {
    id vip = HFASharedVIP();
    if (!vip) {
        HFASetVerifierResult(@"DIYVIP unavailable");
        return;
    }

    Class cls = [vip class];
    Ivar ivar = class_getInstanceVariable(cls, "_status");
    if (!ivar) {
        HFASetVerifierResult(@"_status ivar not found");
        return;
    }

    ptrdiff_t offset = ivar_getOffset(ivar);
    NSInteger *slot = (NSInteger *)((char *)(void *)vip + offset);
    NSInteger rawBefore = *slot;
    NSInteger getterBefore = HFAStatus(vip);
    NSInteger observed = -1;
    BOOL isVIP = NO;
    NSInteger restored = -1;

    @try {
        *slot = target;
        observed = HFAStatus(vip);
        isVIP = HFAIsVIP(vip);
    }
    @finally {
        *slot = rawBefore;
        restored = HFAStatus(vip);
    }

    BOOL expectedVIP = (target == 1 || target == 3);
    BOOL pass = (observed == target && isVIP == expectedVIP && restored == getterBefore);

    NSString *result = [NSString stringWithFormat:
        @"真实对象测试 %ld → status=%ld / isVIP=%@ / 恢复=%ld  %@",
        (long)target,
        (long)observed,
        isVIP ? @"YES" : @"NO",
        (long)restored,
        pass ? @"PASS" : @"CONFLICT"];
    HFASetVerifierResult(result);

    NSLog(@"[HFAMap][NVideoVIP][STATE_TEST] target=%ld rawBefore=%ld getterBefore=%ld observed=%ld isVIP=%d restored=%ld pass=%d",
          (long)target, (long)rawBefore, (long)getterBefore, (long)observed,
          isVIP ? 1 : 0, (long)restored, pass ? 1 : 0);
}

@interface HFANVideoVIPStateVerifierTarget : NSObject
+ (instancetype)shared;
- (void)testTapped:(UIButton *)sender;
- (void)timerFired:(NSTimer *)timer;
@end

@implementation HFANVideoVIPStateVerifierTarget

+ (instancetype)shared {
    static HFANVideoVIPStateVerifierTarget *obj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [[HFANVideoVIPStateVerifierTarget alloc] init]; });
    return obj;
}

- (void)testTapped:(UIButton *)sender {
    NSInteger target = sender.tag;
    if (target < 0 || target > 3) return;
    HFARunStatusTest(target);
}

- (void)timerFired:(NSTimer *)timer {
    (void)timer;
    if (gVerifierPanel) return;

    UIView *panel = HFAFindDiagnosticPanel();
    if (!panel) return;

    gVerifierPanel = panel;

    CGRect frame = panel.frame;
    if (frame.size.height < 404.0) {
        frame.size.height = 404.0;
        panel.frame = frame;
    }

    CGFloat w = panel.bounds.size.width;

    UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(14.0, 325.0, w - 28.0, 1.0)] autorelease];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    [panel addSubview:line];

    UILabel *caption = [[[UILabel alloc] initWithFrame:CGRectMake(14.0, 330.0, 96.0, 18.0)] autorelease];
    caption.text = @"真实等级验证";
    caption.font = [UIFont boldSystemFontOfSize:11.0];
    caption.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    [panel addSubview:caption];

    UILabel *result = [[[UILabel alloc] initWithFrame:CGRectMake(110.0, 330.0, w - 124.0, 18.0)] autorelease];
    result.text = gLastVerifierResult ?: @"尚未测试";
    result.font = [UIFont systemFontOfSize:8.5];
    result.textAlignment = NSTextAlignmentRight;
    result.adjustsFontSizeToFitWidth = YES;
    result.minimumScaleFactor = 0.65;
    result.textColor = [UIColor colorWithRed:0.70 green:0.90 blue:1.0 alpha:1.0];
    [panel addSubview:result];
    gVerifierResultLabel = result;

    CGFloat gap = 8.0;
    CGFloat buttonW = (w - 28.0 - gap * 3.0) / 4.0;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = i;
        button.frame = CGRectMake(14.0 + (buttonW + gap) * i, 354.0, buttonW, 34.0);
        [button setTitle:[NSString stringWithFormat:@"等级 %ld", (long)i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        button.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.96];
        button.layer.cornerRadius = 6.0;
        button.layer.borderWidth = 0.5;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        [button addTarget:[HFANVideoVIPStateVerifierTarget shared]
                   action:@selector(testTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:button];
    }

    NSLog(@"[HFAMap][NVideoVIP][STATE_VERIFIER_READY] real-object transient 0/1/2/3 verifier installed");
}

@end

__attribute__((constructor))
static void HFANVideoVIPStateVerifierInit(void) {
    @autoreleasepool {
        NSLog(@"[HFAMap][NVideoVIP] HFAMapUniversal fenpingvip v4 state verifier loaded");
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.10
                                             target:[HFANVideoVIPStateVerifierTarget shared]
                                           selector:@selector(timerFired:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
}
