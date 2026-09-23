#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM47BuilderTitleTagBase = 672000;
static const NSInteger kZNM47BuilderArgTagBase = 690000;
static const void *kZNM47BuilderActionIndexKey = &kZNM47BuilderActionIndexKey;
static const void *kZNM47BuilderArgumentIndexKey = &kZNM47BuilderArgumentIndexKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (void)zn50b_renderOther;
- (void)zn40_updateContentHeight:(CGFloat)y;
@end

static CGFloat ZNM47BuilderBottom(UIView *root) {
    CGFloat y = 0;
    for (UIView *view in root.subviews) y = MAX(y, CGRectGetMaxY(view.frame));
    return y;
}

static UITextField *ZNM47BuilderField(CGRect frame, ZNTheme *theme) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.tintColor = theme.accentColor;
    field.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.layer.cornerRadius = 6.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

static UITextField *ZNM47FindTitleField(UIView *root, NSUInteger index) {
    NSInteger tag = kZNM47BuilderTitleTagBase + (NSInteger)index;
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UITextField.class] && view.tag == tag) return (UITextField *)view;
        UITextField *nested = ZNM47FindTitleField(view, index);
        if (nested) return nested;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNM47BuilderArgsUI)
- (void)znm47b_renderOther;
- (void)znm47b_argumentEnded:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM47BuilderArgsUI)

- (void)znm47b_renderOther {
    [self znm47b_renderOther];

    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodAction *action = actions[i];
        if (action.argumentCount < 2 || action.argumentCount > ZN_RUNTIME_ACTION_MAX_ARGUMENTS) continue;

        UITextField *titleField = ZNM47FindTitleField(self.contentView, i);
        UIView *card = titleField.superview;
        if (!card || card.superview != self.contentView) continue;

        CGFloat oldBottom = CGRectGetMaxY(card.frame);
        CGFloat oldHeight = CGRectGetHeight(card.frame);
        CGFloat rowY = 68.0;
        CGFloat rowStep = 34.0;

        for (NSUInteger arg = 0; arg < action.argumentCount; arg++) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(13, rowY + arg * rowStep, 48, 28)];
            NSString *type = (action.parameterTypeNames.count == action.argumentCount) ? action.parameterTypeNames[arg] : @"?";
            NSArray<NSString *> *parts = [type componentsSeparatedByString:@"."];
            NSString *last = parts.lastObject;
            NSString *shortType = last.length ? last : type;
            label.text = [NSString stringWithFormat:@"参数%lu", (unsigned long)arg + 1];
            label.textColor = self.theme.secondaryTextColor;
            label.font = [UIFont systemFontOfSize:8.2 weight:UIFontWeightSemibold];
            [card addSubview:label];

            UITextField *field = ZNM47BuilderField(CGRectMake(60, rowY + arg * rowStep, card.bounds.size.width - 73, 28), self.theme);
            field.tag = kZNM47BuilderArgTagBase + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            field.text = action.argumentValues.count == action.argumentCount ? action.argumentValues[arg] : @"";
            field.placeholder = [NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, shortType ?: @"?"];
            objc_setAssociatedObject(field, kZNM47BuilderActionIndexKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(field, kZNM47BuilderArgumentIndexKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [field addTarget:self action:@selector(znm47b_argumentEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:field];
        }

        CGFloat desired = rowY + action.argumentCount * rowStep + 5.0;
        CGFloat delta = MAX(0.0, desired - oldHeight);
        if (delta > 0.5) {
            CGRect frame = card.frame; frame.size.height = desired; card.frame = frame;
            for (UIView *sibling in self.contentView.subviews) {
                if (sibling == card) continue;
                if (CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
                CGRect sf = sibling.frame; sf.origin.y += delta; sibling.frame = sf;
            }
        }
    }
    [self zn40_updateContentHeight:ZNM47BuilderBottom(self.contentView) + 8.0];
}

- (void)znm47b_argumentEnded:(UITextField *)field {
    NSNumber *actionIndexNumber = objc_getAssociatedObject(field, kZNM47BuilderActionIndexKey);
    NSNumber *argumentIndexNumber = objc_getAssociatedObject(field, kZNM47BuilderArgumentIndexKey);
    if (!actionIndexNumber || !argumentIndexNumber) return;
    NSUInteger actionIndex = actionIndexNumber.unsignedIntegerValue;
    NSUInteger argumentIndex = argumentIndexNumber.unsignedIntegerValue;
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (actionIndex >= actions.count) return;
    ZNRuntimeMethodAction *action = actions[actionIndex];
    if (argumentIndex >= action.argumentCount) return;

    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:action.argumentCount];
    for (NSUInteger i = 0; i < action.argumentCount; i++) {
        NSString *value = (action.argumentValues.count == action.argumentCount) ? action.argumentValues[i] : @"";
        [values addObject:value ?: @""];
    }
    values[argumentIndex] = field.text ?: @"";
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateArgumentValues:values atIndex:actionIndex error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.7-builder-args] update failed index=%lu arg=%lu error=%@",
                                             (unsigned long)actionIndex, (unsigned long)argumentIndex, error ?: @"unknown"]];
    }
    [field resignFirstResponder];
}

@end

static void ZNM47BuilderSwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM47BuilderArgsUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47BuilderSwap(cls, @selector(zn50b_renderOther), @selector(znm47b_renderOther));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.7-builder-args] /2-/8 Builder parameter editor installed"];
    });
}
