#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// v0.5.8-dev Method Finder V3 M2.1
//
// M2 already provides cooperative cancellation, but its Cancel control is
// appended at the bottom of the search page. On fast devices the search can
// finish before that extra card is ever visibly presented. M2.1 keeps the
// engine unchanged and makes cancellation discoverable by turning the primary
// Search button into Cancel for the lifetime of an active M2 token.

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn60v3_renderSearchAtWidth:(CGFloat)width;
- (void)zn60v3_startSearch:(id)sender;
- (NSString *)zn61m2_activeToken;
- (void)zn61m2_startSearch:(id)sender;
- (void)zn61m2_cancelSearch:(id)sender;
@end

static UIButton *ZN62FindButtonWithTitle(UIView *root, NSString *title) {
    if (!root) return nil;
    if ([root isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)root;
        if ([button.currentTitle isEqualToString:title]) return button;
    }
    for (UIView *child in root.subviews) {
        UIButton *found = ZN62FindButtonWithTitle(child, title);
        if (found) return found;
    }
    return nil;
}

static UIView *ZN62LegacyCancelCard(UIView *contentView) {
    for (UIView *card in contentView.subviews) {
        UIButton *cancel = ZN62FindButtonWithTitle(card, @"取消");
        if (cancel) return card;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM21CancelUX)
- (void)zn62m21_renderSearchAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM21CancelUX)

- (void)zn62m21_renderSearchAtWidth:(CGFloat)width {
    // After swizzling this selector calls the complete M2 search-page renderer.
    [self zn62m21_renderSearchAtWidth:width];

    NSString *token = [self zn61m2_activeToken];
    if (!token.length) return;

    // M2's bottom-of-page Cancel card is redundant once the primary action is
    // converted in place. Remove it so there is only one clear cancellation
    // affordance and no need to scroll during a short search.
    UIView *legacyCancelCard = ZN62LegacyCancelCard(self.contentView);
    if (legacyCancelCard) [legacyCancelCard removeFromSuperview];

    UIButton *primary = ZN62FindButtonWithTitle(self.contentView, @"搜索");
    if (primary) {
        [primary setTitle:@"取消" forState:UIControlStateNormal];
        [primary removeTarget:self action:@selector(zn60v3_startSearch:) forControlEvents:UIControlEventTouchUpInside];
        [primary removeTarget:self action:@selector(zn61m2_startSearch:) forControlEvents:UIControlEventTouchUpInside];
        [primary addTarget:self action:@selector(zn61m2_cancelSearch:) forControlEvents:UIControlEventTouchUpInside];
        primary.accessibilityIdentifier = @"ZNMethodFinderPrimaryCancel";
        primary.accessibilityLabel = @"取消 IL2CPP 搜索";
    }

    CGFloat maxY = 0.0;
    for (UIView *view in self.contentView.subviews) {
        maxY = MAX(maxY, CGRectGetMaxY(view.frame));
    }
    [self zn40_updateContentHeight:maxY + 8.0];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderM21CancelUXDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method original = class_getInstanceMethod(cls, @selector(zn60v3_renderSearchAtWidth:));
        Method replacement = class_getInstanceMethod(cls, @selector(zn62m21_renderSearchAtWidth:));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
        }
    });
}
