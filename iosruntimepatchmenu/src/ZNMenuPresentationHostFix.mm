#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// M3.1 text-interaction presentation hotfix.
//
// Keep the historical UIWindow attachment model and floating button behavior,
// but stop forcing the menu panel to the front every 0.5 s. Repeated panel
// z-order promotion can cover/interfere with UIKit text interaction UI such as
// Translate / Look Up / Share. While a field inside the panel is first
// responder, also avoid reattaching the whole editable hierarchy to a transient
// key window.
//
// No constructor/+load. Installed only by the existing deferred bootstrap.

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

static BOOL ZN62ContainsFirstResponder(UIView *view) {
    if (!view) return NO;
    if (view.isFirstResponder) return YES;
    for (UIView *subview in view.subviews) {
        if (ZN62ContainsFirstResponder(subview)) return YES;
    }
    return NO;
}

@interface ZNRuntimeMenuControllerV040 (ZNMenuPresentationHostFix)
- (void)zn62_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMenuPresentationHostFix)

- (void)zn62_tick:(NSTimer *)timer {
    (void)timer;

    UIWindow *candidate = [self currentWindow];
    if (!candidate) return;

    if (!self.uiReady) {
        [self makeUI:candidate];
        return;
    }

    // UITextField selection/edit-menu actions may transiently change which
    // window UIKit reports as key. Never remove/re-add the active text field
    // hierarchy while it owns first-responder state.
    BOOL textInteractionActive = ZN62ContainsFirstResponder(self.panel);
    if (!textInteractionActive &&
        (self.hostWindow != candidate || self.panel.superview != candidate || self.floatButton.superview != candidate)) {
        [self attach:candidate];
    }

    UIWindow *window = self.hostWindow ?: candidate;
    if (!window) return;

    if (!CGRectEqualToRect(self.lastBounds, window.bounds) ||
        !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets, window.safeAreaInsets)) {
        [self layoutForWindow:window initial:NO];
    }
    if (self.themeMode == ZNThemeModeSystem && [self interfaceStyle] != self.lastStyle) {
        [self applyTheme];
    }

    // Preserve the floating button's historical always-on-top behavior.
    // Deliberately do NOT call bringSubviewToFront: for self.panel here.
    // The panel is promoted by its normal open/attach flow, not every 0.5 s.
    if (self.floatButton.superview == window) {
        [window bringSubviewToFront:self.floatButton];
    }
}

@end

extern "C" void ZNInstallMenuPresentationHostFixDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method tickOriginal = class_getInstanceMethod(cls, @selector(tick:));
        Method tickReplacement = class_getInstanceMethod(cls, @selector(zn62_tick:));
        if (tickOriginal && tickReplacement) {
            method_exchangeImplementations(tickOriginal, tickReplacement);
        }
    });
}
