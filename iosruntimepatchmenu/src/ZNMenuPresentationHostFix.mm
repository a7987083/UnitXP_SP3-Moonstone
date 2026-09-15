#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// M3.1 text-interaction host-controller hotfix.
//
// Keep the floating button attached directly to the game UIWindow exactly as
// before, including the historical 0.5 s z-order promotion. Move only the menu
// panel under a real child UIViewController so UITextField edit-menu actions
// (Translate / Look Up / Share) participate in a normal controller hierarchy.
//
// The host view is pass-through outside the panel. The panel is never promoted
// periodically; it is promoted only when attached/opened. No constructor/+load.

@interface ZNRuntimeMenuControllerV040 : NSObject
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

@interface ZN62PassthroughView : UIView
@end
@implementation ZN62PassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface ZN62MenuHostController : UIViewController
@end
@implementation ZN62MenuHostController
- (void)loadView {
    ZN62PassthroughView *view = [ZN62PassthroughView new];
    view.backgroundColor = UIColor.clearColor;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = view;
}
- (BOOL)shouldAutorotate { return YES; }
@end

static const void *kZN62HostControllerKey = &kZN62HostControllerKey;

static BOOL ZN62ContainsFirstResponder(UIView *view) {
    if (!view) return NO;
    if (view.isFirstResponder) return YES;
    for (UIView *subview in view.subviews) {
        if (ZN62ContainsFirstResponder(subview)) return YES;
    }
    return NO;
}

static BOOL ZN62WindowUsable(UIWindow *window) {
    if (!window || window.hidden || window.alpha <= 0.01 || !window.rootViewController) return NO;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene) {
            UISceneActivationState state = scene.activationState;
            if (state != UISceneActivationStateForegroundActive &&
                state != UISceneActivationStateForegroundInactive) return NO;
        }
    }
    return YES;
}

static ZN62MenuHostController *ZN62HostControllerForMenu(ZNRuntimeMenuControllerV040 *menu,
                                                          UIWindow *window,
                                                          BOOL create) {
    if (!menu || !window) return nil;
    UIViewController *root = window.rootViewController;
    if (!root) return nil;

    ZN62MenuHostController *host = objc_getAssociatedObject(menu, kZN62HostControllerKey);
    if (host && host.parentViewController != root) {
        [host willMoveToParentViewController:nil];
        [host.view removeFromSuperview];
        [host removeFromParentViewController];
        host = nil;
        objc_setAssociatedObject(menu, kZN62HostControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!host && create) {
        host = [ZN62MenuHostController new];
        [root addChildViewController:host];
        host.view.frame = root.view.bounds;
        host.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root.view addSubview:host.view];
        [host didMoveToParentViewController:root];
        objc_setAssociatedObject(menu, kZN62HostControllerKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return host;
}

static void ZN62PromotePanelHost(ZNRuntimeMenuControllerV040 *menu) {
    UIWindow *window = menu.hostWindow;
    ZN62MenuHostController *host = ZN62HostControllerForMenu(menu, window, NO);
    if (!host || !host.parentViewController || !host.view.superview) return;
    [host.view.superview bringSubviewToFront:host.view];
    if (menu.panel.superview == host.view) [host.view bringSubviewToFront:menu.panel];
}

@interface ZNRuntimeMenuControllerV040 (ZNMenuPresentationHostFix)
- (void)zn62_attach:(UIWindow *)window;
- (void)zn62_tick:(NSTimer *)timer;
- (void)zn62_show;
- (void)zn62_togglePanel:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMenuPresentationHostFix)

- (void)zn62_attach:(UIWindow *)window {
    if (!window || !self.uiReady || !window.rootViewController) return;

    ZN62MenuHostController *host = ZN62HostControllerForMenu(self, window, YES);
    if (!host) return;

    UIView *oldPanelSuperview = self.panel.superview;
    UIWindow *oldPanelWindow = oldPanelSuperview.window;
    CGPoint panelCenterInWindow = self.panel.center;
    BOOL canConvertPanelCenter = oldPanelSuperview && oldPanelWindow == window;
    if (canConvertPanelCenter) {
        panelCenterInWindow = [oldPanelSuperview convertPoint:self.panel.center toView:window];
    }

    if (self.floatButton.superview != window) {
        UIView *oldFloatSuperview = self.floatButton.superview;
        UIWindow *oldFloatWindow = oldFloatSuperview.window;
        CGPoint floatCenterInWindow = self.floatButton.center;
        BOOL canConvertFloatCenter = oldFloatSuperview && oldFloatWindow == window;
        if (canConvertFloatCenter) {
            floatCenterInWindow = [oldFloatSuperview convertPoint:self.floatButton.center toView:window];
        }
        [self.floatButton removeFromSuperview];
        [window addSubview:self.floatButton];
        if (canConvertFloatCenter) self.floatButton.center = floatCenterInWindow;
    }

    if (self.panel.superview != host.view) {
        [self.panel removeFromSuperview];
        [host.view addSubview:self.panel];
        if (canConvertPanelCenter) {
            self.panel.center = [window convertPoint:panelCenterInWindow toView:host.view];
        }
    }

    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    [self applyTheme];

    ZN62PromotePanelHost(self);
    [window bringSubviewToFront:self.floatButton];
}

- (void)zn62_tick:(NSTimer *)timer {
    (void)timer;

    // Keep the established game window while it is valid. UIKit Translate can
    // create/present transient UI; it must not make the menu jump to a new key
    // window while the text field owns first-responder state.
    UIWindow *window = ZN62WindowUsable(self.hostWindow) ? self.hostWindow : [self currentWindow];
    if (!window) return;

    if (!self.uiReady) {
        [self makeUI:window];
        if (self.uiReady) [self attach:window];
        return;
    }

    ZN62MenuHostController *host = ZN62HostControllerForMenu(self, window, NO);
    BOOL textInteractionActive = ZN62ContainsFirstResponder(self.panel);
    BOOL needsAttach = self.hostWindow != window ||
                       self.floatButton.superview != window ||
                       !host || self.panel.superview != host.view;
    if (needsAttach && !textInteractionActive) {
        [self attach:window];
        host = ZN62HostControllerForMenu(self, window, NO);
    }

    if (!CGRectEqualToRect(self.lastBounds, window.bounds) ||
        !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets, window.safeAreaInsets)) {
        [self layoutForWindow:window initial:NO];
        if (host) host.view.frame = window.rootViewController.view.bounds;
    }
    if (self.themeMode == ZNThemeModeSystem && [self interfaceStyle] != self.lastStyle) {
        [self applyTheme];
    }

    // Preserve only the floating button's historical always-on-top behavior.
    // Never periodically promote the menu host/panel.
    if (self.floatButton.superview == window) {
        [window bringSubviewToFront:self.floatButton];
    }
}

- (void)zn62_show {
    [self zn62_show];
    if (!self.panel.hidden) ZN62PromotePanelHost(self);
    if (self.floatButton.superview == self.hostWindow) {
        [self.hostWindow bringSubviewToFront:self.floatButton];
    }
}

- (void)zn62_togglePanel:(id)sender {
    [self zn62_togglePanel:sender];
    if (!self.panel.hidden) ZN62PromotePanelHost(self);
    if (self.floatButton.superview == self.hostWindow) {
        [self.hostWindow bringSubviewToFront:self.floatButton];
    }
}

@end

extern "C" void ZNInstallMenuPresentationHostFixDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method attachOriginal = class_getInstanceMethod(cls, @selector(attach:));
        Method attachReplacement = class_getInstanceMethod(cls, @selector(zn62_attach:));
        if (attachOriginal && attachReplacement) {
            method_exchangeImplementations(attachOriginal, attachReplacement);
        }

        Method tickOriginal = class_getInstanceMethod(cls, @selector(tick:));
        Method tickReplacement = class_getInstanceMethod(cls, @selector(zn62_tick:));
        if (tickOriginal && tickReplacement) {
            method_exchangeImplementations(tickOriginal, tickReplacement);
        }

        Method showOriginal = class_getInstanceMethod(cls, @selector(show));
        Method showReplacement = class_getInstanceMethod(cls, @selector(zn62_show));
        if (showOriginal && showReplacement) {
            method_exchangeImplementations(showOriginal, showReplacement);
        }

        Method toggleOriginal = class_getInstanceMethod(cls, @selector(togglePanel:));
        Method toggleReplacement = class_getInstanceMethod(cls, @selector(zn62_togglePanel:));
        if (toggleOriginal && toggleReplacement) {
            method_exchangeImplementations(toggleOriginal, toggleReplacement);
        }
    });
}
