#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// M3.1 text-interaction UIViewController hotfix.
//
// ZNRuntimeMenuControllerV040 itself is a UIViewController. Its panel is its
// root view (panel == self.view), and the menu controller is attached as a real
// child of the game's rootViewController. The floating button deliberately
// remains a direct UIWindow child and keeps its historical 0.5 s z-order
// promotion. The menu is promoted only on attach/open, never periodically.

@interface ZNRuntimeMenuControllerV040 : UIViewController
@property(nonatomic,strong) UIButton *floatButton;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,assign) CGRect lastBounds;
@property(nonatomic,assign) UIEdgeInsets lastInsets;
@property(nonatomic,assign) UIUserInterfaceStyle lastStyle;
@property(nonatomic,assign) BOOL uiReady;
@property(nonatomic,assign) ZNThemeMode themeMode;
- (UIWindow *)currentWindow;
- (UIUserInterfaceStyle)interfaceStyle;
- (void)makeUI:(UIWindow *)window;
- (void)attach:(UIWindow *)window;
- (void)tick:(NSTimer *)timer;
- (void)show;
- (void)togglePanel:(id)sender;
- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial;
- (void)applyTheme;
@end

static BOOL ZN63ContainsFirstResponder(UIView *view) {
    if (!view) return NO;
    if (view.isFirstResponder) return YES;
    for (UIView *subview in view.subviews) if (ZN63ContainsFirstResponder(subview)) return YES;
    return NO;
}

static BOOL ZN63WindowUsable(UIWindow *window) {
    if (!window || window.hidden || window.alpha <= 0.01 || !window.rootViewController) return NO;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene) {
            UISceneActivationState state = scene.activationState;
            if (state != UISceneActivationStateForegroundActive && state != UISceneActivationStateForegroundInactive) return NO;
        }
    }
    return YES;
}

static void ZN63DetachMenuController(ZNRuntimeMenuControllerV040 *menu) {
    if (!menu.parentViewController) return;
    [menu willMoveToParentViewController:nil];
    [menu.view removeFromSuperview];
    [menu removeFromParentViewController];
}

static void ZN63PromoteMenu(ZNRuntimeMenuControllerV040 *menu) {
    UIViewController *parent = menu.parentViewController;
    if (!parent || menu.view.superview != parent.view) return;
    [parent.view bringSubviewToFront:menu.view];
}

@interface ZNRuntimeMenuControllerV040 (ZNMenuAsViewControllerFix)
- (void)zn63_attach:(UIWindow *)window;
- (void)zn63_tick:(NSTimer *)timer;
- (void)zn63_show;
- (void)zn63_togglePanel:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMenuAsViewControllerFix)

- (void)zn63_attach:(UIWindow *)window {
    if (!window || !self.uiReady) return;
    UIViewController *root = window.rootViewController;
    if (!root || root == self) return;

    if (self.view != self.panel) self.view = self.panel;

    UIView *oldSuperview = self.view.superview;
    UIWindow *oldWindow = oldSuperview.window;
    CGPoint centerInWindow = self.view.center;
    BOOL canConvertCenter = oldSuperview && oldWindow == window;
    if (canConvertCenter) centerInWindow = [oldSuperview convertPoint:self.view.center toView:window];

    if (self.parentViewController != root) {
        ZN63DetachMenuController(self);
        [root addChildViewController:self];
        [root.view addSubview:self.view];
        [self didMoveToParentViewController:root];
    } else if (self.view.superview != root.view) {
        [root.view addSubview:self.view];
    }
    if (canConvertCenter) self.view.center = [window convertPoint:centerInWindow toView:root.view];

    if (self.floatButton.superview != window) {
        UIView *oldFloatSuperview = self.floatButton.superview;
        UIWindow *oldFloatWindow = oldFloatSuperview.window;
        CGPoint floatCenter = self.floatButton.center;
        BOOL canConvertFloat = oldFloatSuperview && oldFloatWindow == window;
        if (canConvertFloat) floatCenter = [oldFloatSuperview convertPoint:self.floatButton.center toView:window];
        [self.floatButton removeFromSuperview];
        [window addSubview:self.floatButton];
        if (canConvertFloat) self.floatButton.center = floatCenter;
    }

    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    [self applyTheme];
    ZN63PromoteMenu(self);
    [window bringSubviewToFront:self.floatButton];
}

- (void)zn63_tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *window = ZN63WindowUsable(self.hostWindow) ? self.hostWindow : [self currentWindow];
    if (!window) return;

    if (!self.uiReady) {
        [self makeUI:window];
        if (self.uiReady) [self attach:window];
        return;
    }

    UIViewController *root = window.rootViewController;
    BOOL textInteractionActive = ZN63ContainsFirstResponder(self.panel);
    BOOL needsAttach = self.hostWindow != window || self.floatButton.superview != window || !root ||
                       self.parentViewController != root || self.view != self.panel || self.view.superview != root.view;
    if (needsAttach && !textInteractionActive) [self attach:window];

    if (!CGRectEqualToRect(self.lastBounds, window.bounds) ||
        !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets, window.safeAreaInsets)) {
        [self layoutForWindow:window initial:NO];
    }
    if (self.themeMode == ZNThemeModeSystem && [self interfaceStyle] != self.lastStyle) [self applyTheme];

    if (self.floatButton.superview == window) [window bringSubviewToFront:self.floatButton];
}

- (void)zn63_show {
    [self zn63_show];
    if (!self.panel.hidden) ZN63PromoteMenu(self);
    if (self.floatButton.superview == self.hostWindow) [self.hostWindow bringSubviewToFront:self.floatButton];
}

- (void)zn63_togglePanel:(id)sender {
    [self zn63_togglePanel:sender];
    if (!self.panel.hidden) ZN63PromoteMenu(self);
    if (self.floatButton.superview == self.hostWindow) [self.hostWindow bringSubviewToFront:self.floatButton];
}

@end

extern "C" void ZNInstallMenuPresentationHostFixDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls || ![cls isSubclassOfClass:UIViewController.class]) return;

        Method attachOriginal = class_getInstanceMethod(cls, @selector(attach:));
        Method attachReplacement = class_getInstanceMethod(cls, @selector(zn63_attach:));
        if (attachOriginal && attachReplacement) method_exchangeImplementations(attachOriginal, attachReplacement);

        Method tickOriginal = class_getInstanceMethod(cls, @selector(tick:));
        Method tickReplacement = class_getInstanceMethod(cls, @selector(zn63_tick:));
        if (tickOriginal && tickReplacement) method_exchangeImplementations(tickOriginal, tickReplacement);

        Method showOriginal = class_getInstanceMethod(cls, @selector(show));
        Method showReplacement = class_getInstanceMethod(cls, @selector(zn63_show));
        if (showOriginal && showReplacement) method_exchangeImplementations(showOriginal, showReplacement);

        Method toggleOriginal = class_getInstanceMethod(cls, @selector(togglePanel:));
        Method toggleReplacement = class_getInstanceMethod(cls, @selector(zn63_togglePanel:));
        if (toggleOriginal && toggleReplacement) method_exchangeImplementations(toggleOriginal, toggleReplacement);
    });
}
