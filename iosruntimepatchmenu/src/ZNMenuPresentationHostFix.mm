#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// M3.1 text-interaction presentation hotfix.
//
// The historical menu attaches panel/floatButton directly to UIWindow and its
// 0.5 s tick follows whichever window is currently key. That is unsafe while a
// UITextField edit interaction is presenting system UI (Translate/Look Up/
// Share): the menu is outside the root view-controller responder hierarchy and
// can also be reparented while the text interaction is active.
//
// Keep the already-selected game window stable while it remains usable and put
// menu views under rootViewController.view. UIKit presentations then sit above
// the menu naturally, and UITextField's responder chain includes a controller.
// No constructor/+load; installed only by the existing deferred bootstrap.

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
- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial;
- (void)applyTheme;
@end

static BOOL ZN62WindowIsUsable(UIWindow *window) {
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

static UIView *ZN62PresentationHostView(UIWindow *window) {
    if (!window) return nil;
    UIViewController *root = window.rootViewController;
    if (!root) return window;
    UIView *view = root.view;
    return view ?: window;
}

@interface ZNRuntimeMenuControllerV040 (ZNMenuPresentationHostFix)
- (void)zn62_attach:(UIWindow *)window;
- (void)zn62_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMenuPresentationHostFix)

- (void)zn62_attach:(UIWindow *)window {
    if (!window || !self.uiReady) return;

    UIView *host = ZN62PresentationHostView(window);
    if (!host) return;

    // Do not repeatedly remove/re-add an active UITextField hierarchy. Only
    // reparent when the host actually changes.
    if (self.floatButton.superview != host) {
        [self.floatButton removeFromSuperview];
        [host addSubview:self.floatButton];
    }
    if (self.panel.superview != host) {
        [self.panel removeFromSuperview];
        [host addSubview:self.panel];
    }

    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    [self applyTheme];
    [host bringSubviewToFront:self.panel];
    [host bringSubviewToFront:self.floatButton];
}

- (void)zn62_tick:(NSTimer *)timer {
    (void)timer;

    // Once the menu is attached, keep that app/game window stable while it is
    // still alive and foreground. A transient key-window change caused by edit
    // menu / translation presentation must not move the active UITextField.
    UIWindow *window = ZN62WindowIsUsable(self.hostWindow) ? self.hostWindow : [self currentWindow];
    if (!window) return;

    if (!self.uiReady) {
        [self makeUI:window];
        if (self.uiReady) [self attach:window];
        return;
    }

    UIView *host = ZN62PresentationHostView(window);
    if (!host) return;
    if (self.hostWindow != window || self.panel.superview != host || self.floatButton.superview != host) {
        [self attach:window];
        host = ZN62PresentationHostView(window);
        if (!host) return;
    }

    if (!CGRectEqualToRect(self.lastBounds, window.bounds) ||
        !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets, window.safeAreaInsets)) {
        [self layoutForWindow:window initial:NO];
    }
    if (self.themeMode == ZNThemeModeSystem && [self interfaceStyle] != self.lastStyle) {
        [self applyTheme];
    }

    // Only reorder inside rootViewController.view. This keeps ZonoPatch above
    // game content but below UIKit-presented system controllers/sheets.
    [host bringSubviewToFront:self.panel];
    [host bringSubviewToFront:self.floatButton];
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
    });
}
