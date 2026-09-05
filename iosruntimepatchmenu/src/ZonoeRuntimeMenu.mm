#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const kZNMenuVersion = @"0.1.0-ui";
static const CGFloat kZNFloatSize = 54.0;
static const CGFloat kZNMargin = 10.0;

static CGFloat ZNClamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    if (maxValue < minValue) return minValue;
    return MIN(MAX(value, minValue), maxValue);
}

static NSString *ZNOrientationText(CGSize size) {
    return size.width >= size.height ? @"Landscape" : @"Portrait";
}

@interface ZNRuntimeMenuController : NSObject
@property(nonatomic, strong) UIButton *floatButton;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *testLabel;
@property(nonatomic, strong) UILabel *noteLabel;
@property(nonatomic, strong) UISwitch *testSwitch;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, assign) CGRect lastHostBounds;
@property(nonatomic, assign) UIEdgeInsets lastSafeInsets;
@property(nonatomic, assign) BOOL uiReady;
@end

@implementation ZNRuntimeMenuController

+ (instancetype)shared {
    static ZNRuntimeMenuController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZNRuntimeMenuController alloc] init];
    });
    return instance;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];

    if (@available(iOS 13.0, *)) {
        UIWindow *fallback = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.hidden || window.alpha <= 0.01) continue;
                if (window.isKeyWindow) return window;
                if (!fallback && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                    fallback = window;
                }
            }
        }
        if (fallback) return fallback;
    }

    UIWindow *key = app.keyWindow;
    if (key && !key.hidden && key.alpha > 0.01) return key;

    for (UIWindow *window in [app.windows reverseObjectEnumerator]) {
        if (window.hidden || window.alpha <= 0.01) continue;
        if (window.windowLevel == UIWindowLevelNormal && window.rootViewController) return window;
    }
    return app.windows.lastObject;
}

- (void)updateStatus {
    if (!self.statusLabel || !self.hostWindow) return;

    CGSize size = self.hostWindow.bounds.size;
    NSString *testState = self.testSwitch.isOn ? @"ON" : @"OFF";
    self.statusLabel.text = [NSString stringWithFormat:@"Runtime: UI ONLY   Test: %@\niOS %@   %@   %.0fx%.0f",
                             testState,
                             [UIDevice currentDevice].systemVersion,
                             ZNOrientationText(size),
                             size.width,
                             size.height];
}

- (CGPoint)clampedButtonCenter:(CGPoint)center inWindow:(UIWindow *)window {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat half = kZNFloatSize * 0.5;
    CGFloat minX = safe.left + kZNMargin + half;
    CGFloat maxX = CGRectGetWidth(bounds) - safe.right - kZNMargin - half;
    CGFloat minY = safe.top + kZNMargin + half;
    CGFloat maxY = CGRectGetHeight(bounds) - safe.bottom - kZNMargin - half;
    return CGPointMake(ZNClamp(center.x, minX, maxX), ZNClamp(center.y, minY, maxY));
}

- (CGPoint)clampedPanelCenter:(CGPoint)center inWindow:(UIWindow *)window {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGSize panelSize = self.panel.bounds.size;
    CGFloat halfW = panelSize.width * 0.5;
    CGFloat halfH = panelSize.height * 0.5;
    CGFloat minX = safe.left + kZNMargin + halfW;
    CGFloat maxX = CGRectGetWidth(bounds) - safe.right - kZNMargin - halfW;
    CGFloat minY = safe.top + kZNMargin + halfH;
    CGFloat maxY = CGRectGetHeight(bounds) - safe.bottom - kZNMargin - halfH;
    return CGPointMake(ZNClamp(center.x, minX, maxX), ZNClamp(center.y, minY, maxY));
}

- (void)layoutPanelContents {
    CGFloat width = CGRectGetWidth(self.panel.bounds);

    self.titleLabel.frame = CGRectMake(16, 12, MAX(80, width - 72), 28);
    self.closeButton.frame = CGRectMake(MAX(0, width - 48), 8, 40, 36);
    self.statusLabel.frame = CGRectMake(16, 48, MAX(80, width - 32), 48);

    UIView *separator = [self.panel viewWithTag:9001];
    separator.frame = CGRectMake(16, 103, MAX(0, width - 32), 1);

    self.testLabel.frame = CGRectMake(16, 118, MAX(80, width - 92), 34);
    self.testSwitch.frame = CGRectMake(MAX(16, width - 68), 119, 52, 32);
    self.noteLabel.frame = CGRectMake(16, 166, MAX(80, width - 32), 74);
}

- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial {
    if (!window || !self.uiReady) return;

    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat availableW = MAX(220.0, CGRectGetWidth(bounds) - safe.left - safe.right - kZNMargin * 2.0);
    CGFloat availableH = MAX(220.0, CGRectGetHeight(bounds) - safe.top - safe.bottom - kZNMargin * 2.0);
    CGFloat panelW = MIN(360.0, availableW);
    CGFloat panelH = MIN(270.0, availableH);

    CGPoint oldPanelCenter = self.panel.center;
    self.panel.bounds = CGRectMake(0, 0, panelW, panelH);
    [self layoutPanelContents];

    if (initial) {
        self.floatButton.center = [self clampedButtonCenter:CGPointMake(safe.left + kZNMargin + kZNFloatSize * 0.5,
                                                                       safe.top + 120.0 + kZNFloatSize * 0.5)
                                                       inWindow:window];
        self.panel.center = [self clampedPanelCenter:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
                                               inWindow:window];
    } else {
        self.floatButton.center = [self clampedButtonCenter:self.floatButton.center inWindow:window];
        self.panel.center = [self clampedPanelCenter:oldPanelCenter inWindow:window];
    }

    self.lastHostBounds = bounds;
    self.lastSafeInsets = safe;
    [self updateStatus];
}

- (void)makeUI:(UIWindow *)window {
    if (self.uiReady || !window) return;

    self.hostWindow = window;

    UIButton *floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    floatButton.bounds = CGRectMake(0, 0, kZNFloatSize, kZNFloatSize);
    floatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    floatButton.layer.cornerRadius = kZNFloatSize * 0.5;
    floatButton.layer.borderWidth = 1.0;
    floatButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    floatButton.layer.shadowOpacity = 0.28;
    floatButton.layer.shadowRadius = 6.0;
    floatButton.layer.shadowOffset = CGSizeMake(0, 2);
    [floatButton setTitle:@"ZN" forState:UIControlStateNormal];
    [floatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [floatButton addTarget:self action:@selector(togglePanel:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *buttonPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)];
    buttonPan.cancelsTouchesInView = NO;
    [floatButton addGestureRecognizer:buttonPan];
    self.floatButton = floatButton;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.97];
    panel.layer.cornerRadius = 16.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.35;
    panel.layer.shadowRadius = 12.0;
    panel.layer.shadowOffset = CGSizeMake(0, 4);
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    panelPan.cancelsTouchesInView = NO;
    [panel addGestureRecognizer:panelPan];
    self.panel = panel;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Zonoe Runtime Patch";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel = title;
    [panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:0.86 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightLight];
    [close addTarget:self action:@selector(closePanel:) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton = close;
    [panel addSubview:close];

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
    status.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    status.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    status.numberOfLines = 2;
    self.statusLabel = status;
    [panel addSubview:status];

    UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
    separator.tag = 9001;
    separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    [panel addSubview:separator];

    UILabel *testLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    testLabel.text = @"UI 测试开关";
    testLabel.textColor = [UIColor whiteColor];
    testLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.testLabel = testLabel;
    [panel addSubview:testLabel];

    UISwitch *testSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [testSwitch addTarget:self action:@selector(testSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    self.testSwitch = testSwitch;
    [panel addSubview:testSwitch];

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectZero];
    note.text = @"V0.1 仅验证悬浮窗基础：按钮/面板拖拽、窗口重挂、前后台与横竖屏适配。当前没有任何 Patch 或 Hook。";
    note.textColor = [UIColor colorWithWhite:0.66 alpha:1.0];
    note.font = [UIFont systemFontOfSize:11];
    note.numberOfLines = 4;
    self.noteLabel = note;
    [panel addSubview:note];

    panel.hidden = YES;
    [window addSubview:floatButton];
    [window addSubview:panel];

    self.uiReady = YES;
    [self layoutForWindow:window initial:YES];
    NSLog(@"[ZonoeRuntimeMenu v0.1] UI ready on window=%@ bounds=%@", window, NSStringFromCGRect(window.bounds));
}

- (void)attachToWindow:(UIWindow *)window {
    if (!window || !self.uiReady) return;
    if (self.hostWindow == window && self.floatButton.superview == window && self.panel.superview == window) return;

    [self.floatButton removeFromSuperview];
    [self.panel removeFromSuperview];
    [window addSubview:self.floatButton];
    [window addSubview:self.panel];
    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    NSLog(@"[ZonoeRuntimeMenu v0.1] reattached window=%@", window);
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *window = [self currentWindow];
    if (!window) return;

    if (!self.uiReady) {
        [self makeUI:window];
        return;
    }

    if (self.hostWindow != window || self.floatButton.superview != window || self.panel.superview != window) {
        [self attachToWindow:window];
    }

    if (!CGRectEqualToRect(self.lastHostBounds, window.bounds) ||
        !UIEdgeInsetsEqualToEdgeInsets(self.lastSafeInsets, window.safeAreaInsets)) {
        [self layoutForWindow:window initial:NO];
    }

    [window bringSubviewToFront:self.panel];
    [window bringSubviewToFront:self.floatButton];
}

- (void)start {
    if (self.timer) return;
    [self tick:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                 target:self
                                               selector:@selector(tick:)
                                               userInfo:nil
                                                repeats:YES];
    NSLog(@"[ZonoeRuntimeMenu v0.1] bootstrap version=%@", kZNMenuVersion);
}

- (void)togglePanel:(id)sender {
    (void)sender;
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden && self.hostWindow) {
        self.panel.center = [self clampedPanelCenter:self.panel.center inWindow:self.hostWindow];
        [self.hostWindow bringSubviewToFront:self.panel];
        [self.hostWindow bringSubviewToFront:self.floatButton];
    }
    [self updateStatus];
}

- (void)closePanel:(id)sender {
    (void)sender;
    self.panel.hidden = YES;
}

- (void)testSwitchChanged:(UISwitch *)sender {
    (void)sender;
    [self updateStatus];
    NSLog(@"[ZonoeRuntimeMenu v0.1] UI test switch=%@", self.testSwitch.isOn ? @"ON" : @"OFF");
}

- (void)panButton:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.hostWindow;
    if (!window) return;

    CGPoint translation = [gesture translationInView:window];
    CGPoint center = self.floatButton.center;
    center.x += translation.x;
    center.y += translation.y;
    self.floatButton.center = [self clampedButtonCenter:center inWindow:window];
    [gesture setTranslation:CGPointZero inView:window];
}

- (void)panPanel:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.hostWindow;
    if (!window) return;

    CGPoint location = [gesture locationInView:self.panel];
    if (location.y > 52.0 && gesture.state == UIGestureRecognizerStateBegan) return;

    CGPoint translation = [gesture translationInView:window];
    CGPoint center = self.panel.center;
    center.x += translation.x;
    center.y += translation.y;
    self.panel.center = [self clampedPanelCenter:center inWindow:window];
    [gesture setTranslation:CGPointZero inView:window];
}

@end

extern "C" __attribute__((visibility("default"))) const char *ZNRuntimeMenuVersion(void) {
    return "0.1.0-ui";
}

__attribute__((constructor)) static void ZNRuntimeMenuBootstrap(void) {
    @autoreleasepool {
        NSLog(@"[ZonoeRuntimeMenu v0.1] dylib loaded");
        dispatch_async(dispatch_get_main_queue(), ^{
            [[ZNRuntimeMenuController shared] start];
        });
    }
}
