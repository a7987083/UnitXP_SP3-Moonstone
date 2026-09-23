#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const CGFloat kZNM461SignatureRowHeight = 16.0;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (void)renderPage;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (void)zn40_updateContentHeight:(CGFloat)y;
@end

static NSString *ZNM461LegacyName(NSDictionary *candidate) {
    NSString *method = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZNM461CollisionKey(NSDictionary *candidate) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"",
            candidate[@"namespace"] ?: @"",
            candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"",
            candidate[@"argumentCount"] ?: @(-1)];
}

static NSArray<NSDictionary *> *ZNM461VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static CGFloat ZNM461Y(UIView *view, UIView *root) {
    return CGRectGetMinY([view convertRect:view.bounds toView:root]);
}

static void ZNM461CollectButtons(UIView *view,
                                 id target,
                                 SEL selector,
                                 NSMutableArray<UIButton *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(selector)]) [out addObject:button];
        }
        ZNM461CollectButtons(child, target, selector, out);
    }
}

static UILabel *ZNM461MethodLabelInCard(UIView *card) {
    UILabel *best = nil;
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        CGFloat y = CGRectGetMinY(label.frame);
        if (y >= 4.0 && y <= 28.0) {
            if (!best || y < CGRectGetMinY(best.frame)) best = label;
        }
    }
    return best;
}

static void ZNM461MoveLowerLabels(UIView *card, CGFloat threshold, CGFloat delta) {
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        if (CGRectGetMinY(view.frame) < threshold) continue;
        CGRect frame = view.frame;
        frame.origin.y += delta;
        view.frame = frame;
    }
}

static CGFloat ZNM461Bottom(UIView *root) {
    CGFloat bottom = 0;
    for (UIView *view in root.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

@interface ZNRuntimeMenuControllerV040 (ZNM461Polish)
- (void)znm461_renderPage;
- (void)znm461_renderResultsAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM461Polish)

- (void)znm461_renderPage {
    [self znm461_renderPage];

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSUInteger runtimeCount = [ZNRuntimeActionStore sharedStore].actionsSnapshot.count;
    BOOL runtimeOnlyReady = runtimeCount > 0 && workspace.filledCount == 0;
    if (!runtimeOnlyReady) return;

    // ZNUXFixesV2 historically re-applies a Static-only filledCount gate after
    // the Builder page renders. Runtime-only generation has its own safe path,
    // so override that UI gate after the complete render chain.
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM461CollectButtons(self.contentView, self, @selector(zn44_buildBinary:), buttons);
    for (UIButton *button in buttons) {
        button.enabled = !workspace.isBuilding;
        button.alpha = button.enabled ? 1.0 : 0.5;
    }
}

- (void)znm461_renderResultsAtWidth:(CGFloat)width {
    [self znm461_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM461VisibleCandidates(self);
    if (visible.count < 2) return;

    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NSDictionary *candidate in visible) {
        NSString *key = ZNM461CollisionKey(candidate);
        counts[key] = @([counts[key] unsignedIntegerValue] + 1);
    }

    NSMutableArray<UIButton *> *testButtons = [NSMutableArray array];
    ZNM461CollectButtons(self.contentView, self, @selector(znm43_testCandidate:), testButtons);
    [testButtons sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat ay = ZNM461Y(a, self.contentView), by = ZNM461Y(b, self.contentView);
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    if (testButtons.count < visible.count) return;

    for (NSUInteger i = 0; i < visible.count && i < testButtons.count; i++) {
        NSDictionary *candidate = visible[i];
        if ([counts[ZNM461CollisionKey(candidate)] unsignedIntegerValue] <= 1) continue;

        NSString *signatureError = nil;
        NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
        if (!types || types.count != [candidate[@"argumentCount"] unsignedIntegerValue]) continue;

        UIButton *test = testButtons[i];
        UIView *card = test.superview;
        if (!card || card.superview != self.contentView) continue;

        // M4.6 V1 replaced the top title with Method(Type). M4.6.1 restores the
        // compact Method/N title and moves exact overload identity below input.
        UILabel *methodLabel = ZNM461MethodLabelInCard(card);
        if (methodLabel) methodLabel.text = ZNM461LegacyName(candidate);

        NSInteger argc = [candidate[@"argumentCount"] integerValue];
        CGFloat signatureY = argc == 1 ? 82.0 : 54.0;
        CGFloat oldBottom = CGRectGetMaxY(card.frame);

        // Existing Assembly row occupies this vertical slot. Shift it down one
        // helper row (hidden Assembly labels are moved too, keeping all-mode UI).
        ZNM461MoveLowerLabels(card, signatureY - 2.0, kZNM461SignatureRowHeight);

        CGRect cardFrame = card.frame;
        cardFrame.size.height += kZNM461SignatureRowHeight;
        card.frame = cardFrame;

        CGFloat rightEdge = MAX(80.0, CGRectGetMinX(test.frame) - 8.0);
        UILabel *signature = [[UILabel alloc] initWithFrame:CGRectMake(13.0,
                                                                      signatureY,
                                                                      MAX(40.0, rightEdge - 13.0),
                                                                      15.0)];
        signature.text = ZNIL2CPPShortSignature(candidate[@"method"] ?: @"Method", types);
        signature.textColor = self.theme.secondaryTextColor;
        signature.font = [UIFont monospacedSystemFontOfSize:7.9 weight:UIFontWeightMedium];
        signature.lineBreakMode = NSLineBreakByTruncatingMiddle;
        signature.adjustsFontSizeToFitWidth = YES;
        signature.minimumScaleFactor = 0.65;
        signature.userInteractionEnabled = NO;
        [card addSubview:signature];

        // Result cards are top-level siblings. Preserve their spacing by moving
        // everything that originally followed this card by exactly one row.
        for (UIView *sibling in self.contentView.subviews) {
            if (sibling == card) continue;
            if (CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
            CGRect frame = sibling.frame;
            frame.origin.y += kZNM461SignatureRowHeight;
            sibling.frame = frame;
        }
    }

    [self zn40_updateContentHeight:ZNM461Bottom(self.contentView) + 8.0];
}

@end

static void ZNM461Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM461PolishDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM461Swap(cls, @selector(renderPage), @selector(znm461_renderPage));
        ZNM461Swap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm461_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.6.1-polish] signature helper row + runtime-only build gate override installed"];
    });
}
