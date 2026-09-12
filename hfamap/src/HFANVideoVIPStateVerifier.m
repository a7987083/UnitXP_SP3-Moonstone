#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// fenpingvip v4
// Authorized state-machine test controller for the real DIYVIP object.
// The four buttons call the app's own -updateStatus:type: path and DO NOT
// automatically restore the previous status. This intentionally exercises the
// real in-process state transition/notification chain without touching receipts,
// StoreKit transactions, purchase records, or persistent entitlement storage.

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

static void HFARunStatusSet(NSInteger target) {
    id vip = HFASharedVIP();
    if (!vip) {
        HFASetVerifierResult(@"DIYVIP unavailable");
        return;
    }

    SEL updateSel = sel_registerName("updateStatus:type:");
    if (![vip respondsToSelector:updateSel]) {
        HFASetVerifierResult(@"updateStatus:type: unavailable");
        return;
    }

    NSInteger before = HFAStatus(vip);
    BOOL updateResult = ((BOOL(*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(vip, updateSel, target, 0);
    NSInteger after = HFAStatus(vip);
    BOOL isVIP = HFAIsVIP(vip);

    BOOL expectedVIP = (target == 1 || target == 3);
    BOOL pass = (after == target && isVIP == expectedVIP);

    NSString *result = [NSString stringWithFormat:
        @"真实等级切换 %ld → %ld / isVIP=%@ / update=%d  %@",
        (long)before,
        (long)after,
        isVIP ? @"YES" : @"NO",
        updateResult ? 1 : 0,
        pass ? @"PASS" : @"CONFLICT"];
    HFASetVerifierResult(result);

    NSLog(@"[HFAMap][NVideoVIP][STATE_SET] before=%ld target=%ld after=%ld isVIP=%d updateReturn=%d pass=%d",
          (long)before, (long)target, (long)after,
          isVIP ? 1 : 0, updateResult ? 1 : 0, pass ? 1 : 0);
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
    HFARunStatusSet(target);
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

    UILabel *caption = [[[UILabel alloc] initWithFrame:CGRectMake(14.0, 330.0, 138.0, 18.0)] autorelease];
    caption.text = @"真实等级切换（不自动恢复）";
    caption.font = [UIFont boldSystemFontOfSize:10.0];
    caption.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    [panel addSubview:caption];

    UILabel *result = [[[UILabel alloc] initWithFrame:CGRectMake(152.0, 330.0, w - 166.0, 18.0)] autorelease];
    result.text = gLastVerifierResult ?: @"尚未测试";
    result.font = [UIFont systemFontOfSize:8.3];
    result.textAlignment = NSTextAlignmentRight;
    result.adjustsFontSizeToFitWidth = YES;
    result.minimumScaleFactor = 0.58;
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

    NSLog(@"[HFAMap][NVideoVIP][STATE_CONTROLLER_READY] real updateStatus:type: 0/1/2/3 controller installed");
}

@end

__attribute__((constructor))
static void HFANVideoVIPStateVerifierInit(void) {
    @autoreleasepool {
        NSLog(@"[HFAMap][NVideoVIP] HFAMapUniversal fenpingvip v4 state controller loaded");
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.10
                                             target:[HFANVideoVIPStateVerifierTarget shared]
                                           selector:@selector(timerFired:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
}
