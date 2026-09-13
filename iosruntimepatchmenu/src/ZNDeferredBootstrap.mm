#import "ZNDeferredBootstrap.h"
#import <UIKit/UIKit.h>
#import <atomic>

extern "C" void ZNInstallSharedSiteExecutionProbeV3Deferred(void);
extern "C" void ZNInstallPublicCompactLayoutDeferred(void);
extern "C" void ZNInstallRuntimeExecutorV041Deferred(void);
extern "C" void ZNInstallRuntimeDiagnosticsV042Deferred(void);
extern "C" void ZNPrepareStaticDispatchRuntimeDeferred(void);
extern "C" void ZNInstallRuntimeMenuV055Deferred(void);
extern "C" void ZNInstallFeatureGroupUIDeferred(void);
extern "C" void ZNInstallPublicCompactDefaultsDeferred(void);
extern "C" void ZNInstallIL2CPPNamedOffsetWorkspaceDeferred(void);
extern "C" void ZNInstallFeatureBuilderUIDeferred(void);

extern "C" void ZonoePatchStart(void);
extern "C" void ZonoePatchShow(void);

typedef NS_ENUM(int, ZNDeferredState) {
    ZNDeferredStateCold = 0,
    ZNDeferredStateLoading = 1,
    ZNDeferredStateReady = 2,
    ZNDeferredStateFailed = 3,
};

static std::atomic<int> gZNDeferredState{ZNDeferredStateCold};
static NSString * const kZNDeferredFloatPositionKey = @"ZonoePatch.FloatCenter";
static const CGFloat kZNDeferredFloatSize = 52.0;
static const CGFloat kZNDeferredMargin = 10.0;

static void ZNRunActivationStage(NSString *name, void (^block)(void)) {
    (void)name;
    block();
}

extern "C" BOOL ZNDeferredBootstrapIsActivated(void) {
    int state = gZNDeferredState.load(std::memory_order_acquire);
    return state == ZNDeferredStateLoading || state == ZNDeferredStateReady;
}

extern "C" BOOL ZNDeferredBootstrapIsReady(void) {
    return gZNDeferredState.load(std::memory_order_acquire) == ZNDeferredStateReady;
}

static UIWindow *ZNDeferredCurrentWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        UIWindow *fallback = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha <= 0.01) continue;
                if (window.isKeyWindow) return window;
                if (!fallback && window.windowLevel == UIWindowLevelNormal && window.rootViewController) fallback = window;
            }
        }
        if (fallback) return fallback;
    }
    if (app.keyWindow && !app.keyWindow.hidden) return app.keyWindow;
    for (UIWindow *window in app.windows.reverseObjectEnumerator) {
        if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController) return window;
    }
    return nil;
}

@interface ZNDeferredLauncher : NSObject
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,weak) UIWindow *hostWindow;
- (void)installIfPossible;
@end

@implementation ZNDeferredLauncher

+ (instancetype)sharedLauncher {
    static ZNDeferredLauncher *launcher;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ launcher = [ZNDeferredLauncher new]; });
    return launcher;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(zn_windowChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(zn_windowChanged:) name:UIWindowDidBecomeKeyNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)zn_windowChanged:(NSNotification *)note {
    (void)note;
    [self installIfPossible];
}

- (CGPoint)zn_clamp:(CGPoint)center window:(UIWindow *)window {
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat half = kZNDeferredFloatSize * 0.5;
    CGFloat left = safe.left + kZNDeferredMargin + half;
    CGFloat right = CGRectGetWidth(window.bounds) - safe.right - kZNDeferredMargin - half;
    CGFloat top = safe.top + kZNDeferredMargin + half;
    CGFloat bottom = CGRectGetHeight(window.bounds) - safe.bottom - kZNDeferredMargin - half;
    center.x = MIN(MAX(center.x, left), MAX(left, right));
    center.y = MIN(MAX(center.y, top), MAX(top, bottom));
    return center;
}

- (void)installIfPossible {
    if (gZNDeferredState.load(std::memory_order_acquire) == ZNDeferredStateReady) return;
    UIWindow *window = ZNDeferredCurrentWindow();
    if (!window) return;

    if (!self.button) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.bounds = CGRectMake(0, 0, kZNDeferredFloatSize, kZNDeferredFloatSize);
        button.layer.cornerRadius = kZNDeferredFloatSize * 0.5;
        button.layer.borderWidth = 1.5;
        button.layer.borderColor = [UIColor colorWithRed:0.42 green:0.55 blue:1.0 alpha:1.0].CGColor;
        button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        [button setTitle:@"ZN" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.28;
        button.layer.shadowRadius = 8.0;
        button.layer.shadowOffset = CGSizeZero;
        [button addTarget:self action:@selector(zn_activate:) forControlEvents:UIControlEventTouchUpInside];
        [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(zn_pan:)]];
        self.button = button;
    }

    if (self.button.superview != window) {
        [self.button removeFromSuperview];
        self.hostWindow = window;
        NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kZNDeferredFloatPositionKey];
        UIEdgeInsets safe = window.safeAreaInsets;
        CGPoint fallback = CGPointMake(CGRectGetWidth(window.bounds) - safe.right - kZNDeferredMargin - kZNDeferredFloatSize * 0.5,
                                       CGRectGetMidY(window.bounds));
        self.button.center = [self zn_clamp:(stored.length ? CGPointFromString(stored) : fallback) window:window];
        [window addSubview:self.button];
    }
    [window bringSubviewToFront:self.button];
}

- (void)zn_pan:(UIPanGestureRecognizer *)gesture {
    if (gZNDeferredState.load(std::memory_order_acquire) != ZNDeferredStateCold) return;
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGPoint center = self.button.center;
    center.x += translation.x;
    center.y += translation.y;
    self.button.center = [self zn_clamp:center window:window];
    [gesture setTranslation:CGPointZero inView:window];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.button.center) forKey:kZNDeferredFloatPositionKey];
    }
}

- (void)zn_markFailed:(NSException *)exception {
    gZNDeferredState.store(ZNDeferredStateFailed, std::memory_order_release);
    self.button.enabled = NO;
    self.button.alpha = 1.0;
    [self.button setTitle:@"!" forState:UIControlStateNormal];
    NSLog(@"[ZonoPatch] v0.5.7 deferred activation failed: %@", exception.reason ?: @"unknown exception");
}

- (void)zn_finishActivation {
    @try {
        ZNRunActivationStage(@"RuntimeMenu", ^{ ZNInstallRuntimeMenuV055Deferred(); });
        ZNRunActivationStage(@"FeatureGroupUI", ^{ ZNInstallFeatureGroupUIDeferred(); });
        ZNRunActivationStage(@"PublicCompactDefaults", ^{ ZNInstallPublicCompactDefaultsDeferred(); });
        ZNRunActivationStage(@"IL2CPPNamedOffsetWorkspace", ^{ ZNInstallIL2CPPNamedOffsetWorkspaceDeferred(); });
        ZNRunActivationStage(@"FeatureBuilderUI", ^{ ZNInstallFeatureBuilderUIDeferred(); });

        gZNDeferredState.store(ZNDeferredStateReady, std::memory_order_release);
        ZNRunActivationStage(@"ZonoePatchStart", ^{ ZonoePatchStart(); });
        ZNRunActivationStage(@"ZonoePatchShow", ^{ ZonoePatchShow(); });

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.button removeFromSuperview];
            self.button = nil;
            self.hostWindow = nil;
        });
    } @catch (NSException *exception) {
        [self zn_markFailed:exception];
    }
}

- (void)zn_beginActivation {
    @try {
        // Old +load-era wrappers, then former constructor priorities 104/106/109.
        ZNRunActivationStage(@"SharedSiteExecutionProbeV3", ^{ ZNInstallSharedSiteExecutionProbeV3Deferred(); });
        ZNRunActivationStage(@"PublicCompactLayout", ^{ ZNInstallPublicCompactLayoutDeferred(); });
        ZNRunActivationStage(@"RuntimeExecutorV041", ^{ ZNInstallRuntimeExecutorV041Deferred(); });
        ZNRunActivationStage(@"RuntimeDiagnosticsV042", ^{ ZNInstallRuntimeDiagnosticsV042Deferred(); });
        ZNRunActivationStage(@"StaticDispatchPrepare", ^{ ZNPrepareStaticDispatchRuntimeDeferred(); });

        // Static Dispatch historically waits 350 ms before refresh. Keep that
        // stage behavior. This continuation is queued later on the same main
        // queue, so the refresh must finish before the menu is revealed.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self zn_finishActivation];
        });
    } @catch (NSException *exception) {
        [self zn_markFailed:exception];
    }
}

- (void)zn_activate:(id)sender {
    (void)sender;
    int expected = ZNDeferredStateCold;
    if (!gZNDeferredState.compare_exchange_strong(expected,
                                                   ZNDeferredStateLoading,
                                                   std::memory_order_acq_rel)) {
        return;
    }

    self.button.enabled = NO;
    self.button.alpha = 0.78;
    [self.button setTitle:@"…" forState:UIControlStateNormal];

    // One UI beat makes the loading state visible before the original startup
    // chain begins. The menu appears only after all deferred stages complete.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self zn_beginActivation];
    });
}

@end

// The only v0.5.7 load-time constructor. It owns the cold launcher only and
// intentionally does not touch DeveloperGate, PatchManager, Resolver, Static
// Dispatch, Builder, Diagnostics, Probe, Feature UI, or the menu controller.
__attribute__((constructor(200))) static void ZNDeferredColdLauncherBootstrap(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ZNDeferredLauncher sharedLauncher] installIfPossible];
    });
}
