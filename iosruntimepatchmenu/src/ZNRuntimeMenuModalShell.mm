#import "ZNRuntimeMenuModalShell.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIButton *floatButton;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *footerLabel;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,assign) CGRect lastBounds;
@property(nonatomic,assign) UIEdgeInsets lastInsets;
@property(nonatomic,assign) UIUserInterfaceStyle lastStyle;
@property(nonatomic,assign) BOOL uiReady;
@property(nonatomic,assign) ZNThemeMode themeMode;
- (UIWindow *)currentWindow;
- (UIUserInterfaceStyle)interfaceStyle;
- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial;
- (void)applyTheme;
- (void)zn40_updateSubtitle;
@end

@interface ZNModalPassthroughView : UIView
@property(nonatomic,weak) UIView *panel;
@end

@implementation ZNModalPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

@interface ZNRuntimeMenuModalViewController : UIViewController
@property(nonatomic,strong) UIView *menuPanel;
@end

@implementation ZNRuntimeMenuModalViewController
- (instancetype)initWithPanel:(UIView *)panel {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _menuPanel = panel;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    return self;
}

- (void)loadView {
    ZNModalPassthroughView *root = [ZNModalPassthroughView new];
    root.backgroundColor = UIColor.clearColor;
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.panel = self.menuPanel;
    self.view = root;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.menuPanel.superview != self.view) {
        [self.menuPanel removeFromSuperview];
        [self.view addSubview:self.menuPanel];
    }
    self.menuPanel.hidden = NO;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Keep the visual tree owned by the runtime menu object, not by a dismissed
    // controller. A fresh modal shell is used on the next presentation.
    [self.menuPanel removeFromSuperview];
}
@end

static const void *kZNModalControllerKey = &kZNModalControllerKey;
static const void *kZNModalPresentingKey = &kZNModalPresentingKey;

static UIViewController *ZNModalTopController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented = vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZNModalTopController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)vc).visibleViewController;
        return top ? ZNModalTopController(top) : vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
        return selected ? ZNModalTopController(selected) : vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last = ((UISplitViewController *)vc).viewControllers.lastObject;
        return last ? ZNModalTopController(last) : vc;
    }
    return vc;
}

static BOOL ZNModalIsPresented(id owner) {
    ZNRuntimeMenuModalViewController *modal = objc_getAssociatedObject(owner, kZNModalControllerKey);
    if (!modal) return NO;
    return modal.presentingViewController != nil || modal.isBeingPresented || [objc_getAssociatedObject(owner, kZNModalPresentingKey) boolValue];
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMenuModalShell)
- (void)znmodal_makeUI:(UIWindow *)window;
- (void)znmodal_attach:(UIWindow *)window;
- (void)znmodal_tick:(NSTimer *)timer;
- (void)znmodal_show;
- (void)znmodal_hide;
- (BOOL)znmodal_isVisible;
- (void)znmodal_togglePanel:(id)sender;
- (void)znmodal_closeTapped:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMenuModalShell)

- (void)znmodal_makeUI:(UIWindow *)window {
    [self znmodal_makeUI:window];
    // The legacy builder creates the complete visual tree correctly. Only move
    // the panel out of UIWindow ownership; the floating button stays untouched.
    if (self.panel.superview == window) [self.panel removeFromSuperview];
    self.panel.hidden = YES;
}

- (void)znmodal_attach:(UIWindow *)window {
    if (!window || !self.uiReady) return;
    if (self.floatButton.superview != window) {
        [self.floatButton removeFromSuperview];
        [window addSubview:self.floatButton];
    }
    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    [self applyTheme];
    if (!ZNModalIsPresented(self) && self.panel.superview == window) [self.panel removeFromSuperview];
}

- (void)znmodal_tick:(NSTimer *)timer {
    (void)timer;
    // While the menu is presented, keep its presentation/window relationship
    // stable. System text services may temporarily change key-window state.
    BOOL menuPresented = ZNModalIsPresented(self);
    UIWindow *window = menuPresented ? self.hostWindow : [self currentWindow];
    if (!window) return;

    if (!self.uiReady) {
        [self makeUI:window];
        return;
    }

    if (!menuPresented && (self.hostWindow != window || self.floatButton.superview != window)) {
        [self attach:window];
    }

    UIWindow *layoutWindow = self.hostWindow ?: window;
    if (layoutWindow && (!CGRectEqualToRect(self.lastBounds, layoutWindow.bounds) ||
                         !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets, layoutWindow.safeAreaInsets))) {
        [self layoutForWindow:layoutWindow initial:NO];
    }
    if (self.themeMode == ZNThemeModeSystem && [self interfaceStyle] != self.lastStyle) [self applyTheme];

    [self zn40_updateSubtitle];
    if (self.uiReady && self.footerLabel) {
        self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    Current UI    iOS %@", UIDevice.currentDevice.systemVersion];
    }
    if (self.floatButton.superview == layoutWindow) [layoutWindow bringSubviewToFront:self.floatButton];
}

- (void)znmodal_show {
    if (!self.uiReady) [self tick:nil];
    if (!self.uiReady || ZNModalIsPresented(self)) return;

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    if (!window || !window.rootViewController) return;
    if (self.floatButton.superview != window) [self attach:window];

    UIViewController *presenter = ZNModalTopController(window.rootViewController);
    if (!presenter || presenter.isBeingDismissed) return;

    ZNRuntimeMenuModalViewController *modal = [[ZNRuntimeMenuModalViewController alloc] initWithPanel:self.panel];
    modal.modalPresentationStyle = UIModalPresentationOverFullScreen;
    modal.view.backgroundColor = UIColor.clearColor;
    objc_setAssociatedObject(self, kZNModalControllerKey, modal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kZNModalPresentingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    self.panel.hidden = NO;
    [presenter presentViewController:modal animated:NO completion:^{
        objc_setAssociatedObject(self, kZNModalPresentingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (self.floatButton.superview == window) [window bringSubviewToFront:self.floatButton];
        [[ZNRuntimeLogger sharedLogger] log:@"[menu-modal] presented via UIModalPresentationOverFullScreen"];
    }];
}

- (void)znmodal_hide {
    ZNRuntimeMenuModalViewController *modal = objc_getAssociatedObject(self, kZNModalControllerKey);
    if (!modal) {
        self.panel.hidden = YES;
        [self.panel removeFromSuperview];
        return;
    }

    self.panel.hidden = YES;
    UIViewController *presenter = modal.presentingViewController;
    void (^finish)(void) = ^{
        [self.panel removeFromSuperview];
        objc_setAssociatedObject(self, kZNModalControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kZNModalPresentingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.floatButton.hidden = NO;
        if (self.floatButton.superview == self.hostWindow) [self.hostWindow bringSubviewToFront:self.floatButton];
        [[ZNRuntimeLogger sharedLogger] log:@"[menu-modal] dismissed"];
    };

    if (presenter || modal.isBeingPresented) [modal dismissViewControllerAnimated:NO completion:finish];
    else finish();
}

- (BOOL)znmodal_isVisible {
    return self.uiReady && ZNModalIsPresented(self) && !self.panel.hidden;
}

- (void)znmodal_togglePanel:(id)sender {
    (void)sender;
    if ([self isVisible]) [self hide];
    else [self show];
    [self zn40_updateSubtitle];
}

- (void)znmodal_closeTapped:(id)sender {
    (void)sender;
    [self hide];
}

@end

static void ZNModalSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallRuntimeMenuModalShellDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNModalSwap(cls, @selector(makeUI:), @selector(znmodal_makeUI:));
        ZNModalSwap(cls, @selector(attach:), @selector(znmodal_attach:));
        ZNModalSwap(cls, @selector(tick:), @selector(znmodal_tick:));
        ZNModalSwap(cls, @selector(show), @selector(znmodal_show));
        ZNModalSwap(cls, @selector(hide), @selector(znmodal_hide));
        ZNModalSwap(cls, @selector(isVisible), @selector(znmodal_isVisible));
        ZNModalSwap(cls, @selector(togglePanel:), @selector(znmodal_togglePanel:));
        ZNModalSwap(cls, @selector(closeTapped:), @selector(znmodal_closeTapped:));
        [[ZNRuntimeLogger sharedLogger] log:@"[menu-modal] installed: floating button remains UIWindow overlay; menu panel uses presented UIViewController shell"];
    });
}
