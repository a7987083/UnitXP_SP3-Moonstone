#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M5.8 ownership rule:
// M5.5 is AUTHORING ONLY. It decorates the Builder with Value Type / Range and
// owns the Runtime-only build-button gate. It never owns customer Runtime events.

static const NSInteger kZNM55Arg1Tag = 674000;
static const NSInteger kZNM55MultiArgTag = 690000;
static const NSInteger kZNM55CheckTag = 812000;
static const NSInteger kZNM55ControlTag = 813000;
static const NSInteger kZNM55ValueTag = 815000;
static const void *kZNM55ActionKey = &kZNM55ActionKey;
static const void *kZNM55ArgKey = &kZNM55ArgKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)renderPage;
- (void)zn50b_renderOther;
@end

static UIViewController *ZNM55Top(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

static ZNValueType ZNM55ResolvedType(ZNRuntimeMethodAction *action, NSUInteger arg, NSDictionary *cfg) {
    ZNValueType authored = ZNValueTypeFromKey([cfg[@"valueType"] isKindOfClass:NSString.class] ? cfg[@"valueType"] : @"auto");
    if (authored != ZNValueTypeAuto) return authored;
    NSString *managed = arg < action.parameterTypeNames.count ? action.parameterTypeNames[arg] : @"";
    return ZNValueTypeForManagedTypeName(managed);
}

static NSUInteger ZNM55CompleteStaticRows(void) {
    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in [ZNBinaryPatchWorkspace sharedWorkspace].rows ?: @[]) {
        if (row.offsetText.length > 0 && row.enabledText.length > 0) count++;
    }
    return count;
}

static UIButton *ZNM55FindBuildButton(UIView *root) {
    for (UIView *view in root.subviews ?: @[]) {
        if ([view isKindOfClass:UIButton.class]) {
            NSString *title = [(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"生成新二进制"] || [title isEqualToString:@"正在生成…"]) return (UIButton *)view;
        }
        UIButton *nested = ZNM55FindBuildButton(view);
        if (nested) return nested;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNM55Typed)
- (void)znm55_builderRender;
- (void)znm55_cycleValueType:(UIButton *)sender;
- (void)znm55_rangeLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM55Typed)

- (void)znm55_builderRender {
    [self znm55_builderRender];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodAction *action = actions[i];
        if (action.argumentControlConfigs.count != action.argumentCount) continue;
        for (NSUInteger arg = 0; arg < action.argumentCount; arg++) {
            NSInteger slot = (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            NSInteger fieldTag = action.argumentCount == 1 ? kZNM55Arg1Tag + (NSInteger)i : kZNM55MultiArgTag + slot;
            UIView *found = [self.contentView viewWithTag:fieldTag];
            UIButton *check = (UIButton *)[self.contentView viewWithTag:kZNM55CheckTag + slot];
            UIButton *controlButton = (UIButton *)[self.contentView viewWithTag:kZNM55ControlTag + slot];
            if (![found isKindOfClass:UITextField.class] || ![check isKindOfClass:UIButton.class] || ![controlButton isKindOfClass:UIButton.class]) continue;
            UITextField *field = (UITextField *)found;
            UIView *card = field.superview;
            if (!card) continue;
            NSDictionary *cfg = action.argumentControlConfigs[arg];
            BOOL enabled = [cfg[@"enabled"] boolValue];
            ZNValueType authored = ZNValueTypeFromKey([cfg[@"valueType"] isKindOfClass:NSString.class] ? cfg[@"valueType"] : @"auto");
            ZNValueType resolved = ZNM55ResolvedType(action, arg, cfg);

            CGFloat gap = 3.0, valueW = 43.0;
            CGRect ff = field.frame;
            if (ff.size.width > 82.0) ff.size.width -= valueW + gap;
            field.frame = ff;
            CGRect cf = check.frame; cf.origin.x = CGRectGetMaxX(ff) + gap; check.frame = cf;
            CGRect tf = controlButton.frame; tf.origin.x = CGRectGetMaxX(cf) + gap; tf.size.width = 47.0; controlButton.frame = tf;
            controlButton.titleLabel.font = [UIFont systemFontOfSize:7.0 weight:UIFontWeightSemibold];

            NSString *valueTitle = authored == ZNValueTypeAuto && resolved != ZNValueTypeAuto
                ? [NSString stringWithFormat:@"A→%@", ZNValueTypeName(resolved)]
                : ZNValueTypeName(authored);
            UIButton *valueButton = [self zn40_button:valueTitle selector:@selector(znm55_cycleValueType:) frame:CGRectMake(CGRectGetMaxX(tf) + gap, CGRectGetMinY(ff), valueW, CGRectGetHeight(ff))];
            valueButton.tag = kZNM55ValueTag + slot;
            valueButton.enabled = enabled;
            valueButton.alpha = enabled ? 1.0 : 0.45;
            valueButton.titleLabel.adjustsFontSizeToFitWidth = YES;
            valueButton.titleLabel.minimumScaleFactor = 0.52;
            valueButton.titleLabel.font = [UIFont systemFontOfSize:7.0 weight:UIFontWeightSemibold];
            objc_setAssociatedObject(valueButton, kZNM55ActionKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(valueButton, kZNM55ArgKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(znm55_rangeLongPress:)];
            longPress.minimumPressDuration = 0.55;
            [valueButton addGestureRecognizer:longPress];
            [card addSubview:valueButton];
        }
    }

    // Runtime-only build gate lives in the same Builder decorator. No extra
    // zn50b_renderOther swizzle is needed in M5.8.
    UIButton *build = ZNM55FindBuildButton(self.contentView);
    if (build) {
        ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
        NSUInteger completeStatic = ZNM55CompleteStaticRows();
        BOOL runtimeOnlyReady = actions.count > 0 && completeStatic == 0;
        BOOL staticReady = completeStatic > 0 && workspace.filledCount == completeStatic && workspace.validatedCount == completeStatic;
        build.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && (runtimeOnlyReady || staticReady);
        build.alpha = build.enabled ? 1.0 : 0.5;
        build.accessibilityHint = runtimeOnlyReady ? @"Runtime-only：无需 Static Offset Patch" : nil;
    }
}

- (void)znm55_cycleValueType:(UIButton *)sender {
    NSUInteger actionIndex = [objc_getAssociatedObject(sender, kZNM55ActionKey) unsignedIntegerValue];
    NSUInteger argIndex = [objc_getAssociatedObject(sender, kZNM55ArgKey) unsignedIntegerValue];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (actionIndex >= actions.count) return;
    ZNRuntimeMethodAction *action = actions[actionIndex];
    if (argIndex >= action.argumentCount || action.argumentControlConfigs.count != action.argumentCount) return;
    NSMutableArray *configs = [action.argumentControlConfigs mutableCopy];
    NSMutableDictionary *cfg = [configs[argIndex] mutableCopy];
    if (![cfg[@"enabled"] boolValue]) return;
    ZNValueType current = ZNValueTypeFromKey([cfg[@"valueType"] isKindOfClass:NSString.class] ? cfg[@"valueType"] : @"auto");
    ZNValueType next = current >= ZNValueTypeF64 ? ZNValueTypeAuto : (ZNValueType)(current + 1);
    ZNRuntimeArgumentControlType control = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
    NSString *managed = argIndex < action.parameterTypeNames.count ? action.parameterTypeNames[argIndex] : @"";
    ZNValueType resolved = next == ZNValueTypeAuto ? ZNValueTypeForManagedTypeName(managed) : next;
    NSDictionary *range = ZNDefaultRangeForValueType(resolved, control == ZNRuntimeArgumentControlTypeSlider);
    cfg[@"valueType"] = ZNValueTypeKey(next);
    cfg[@"default"] = range[@"default"] ?: @1;
    cfg[@"min"] = range[@"min"] ?: @0;
    cfg[@"max"] = range[@"max"] ?: @10;
    cfg[@"step"] = range[@"step"] ?: @1;
    configs[argIndex] = cfg;
    [[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:configs atIndex:actionIndex error:nil];
    [self renderPage];
}

- (void)znm55_rangeLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || ![gesture.view isKindOfClass:UIButton.class]) return;
    UIButton *button = (UIButton *)gesture.view;
    NSUInteger actionIndex = [objc_getAssociatedObject(button, kZNM55ActionKey) unsignedIntegerValue];
    NSUInteger argIndex = [objc_getAssociatedObject(button, kZNM55ArgKey) unsignedIntegerValue];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (actionIndex >= actions.count) return;
    ZNRuntimeMethodAction *action = actions[actionIndex];
    if (argIndex >= action.argumentCount || action.argumentControlConfigs.count != action.argumentCount) return;
    NSDictionary *cfg = action.argumentControlConfigs[argIndex];
    UIViewController *top = ZNM55Top(self.hostWindow); if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"数值范围" message:@"Default / Min / Max / Step\n滑块默认建议 1~10，Step=1。" preferredStyle:UIAlertControllerStyleAlert];
    NSArray *keys = @[@"default", @"min", @"max", @"step"];
    NSArray *placeholders = @[@"Default", @"Min", @"Max", @"Step"];
    for (NSUInteger i=0;i<keys.count;i++) [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=placeholders[i]; f.text=[cfg[keys[i]] description] ?: @""; f.keyboardType=UIKeyboardTypeNumbersAndPunctuation; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        __strong typeof(weakSelf) selfRef=weakSelf; if(!selfRef)return;
        NSDecimalNumber *def=[NSDecimalNumber decimalNumberWithString:alert.textFields[0].text locale:@{NSLocaleDecimalSeparator:@"."}];
        NSDecimalNumber *min=[NSDecimalNumber decimalNumberWithString:alert.textFields[1].text locale:@{NSLocaleDecimalSeparator:@"."}];
        NSDecimalNumber *max=[NSDecimalNumber decimalNumberWithString:alert.textFields[2].text locale:@{NSLocaleDecimalSeparator:@"."}];
        NSDecimalNumber *step=[NSDecimalNumber decimalNumberWithString:alert.textFields[3].text locale:@{NSLocaleDecimalSeparator:@"."}];
        if ([def isEqualToNumber:NSDecimalNumber.notANumber]||[min isEqualToNumber:NSDecimalNumber.notANumber]||[max isEqualToNumber:NSDecimalNumber.notANumber]||[step isEqualToNumber:NSDecimalNumber.notANumber]||[min compare:max]==NSOrderedDescending||[step compare:NSDecimalNumber.zero]!=NSOrderedDescending) return;
        NSMutableArray *configs=[action.argumentControlConfigs mutableCopy]; NSMutableDictionary *next=[configs[argIndex] mutableCopy];
        next[@"default"]=def; next[@"min"]=min; next[@"max"]=max; next[@"step"]=step; configs[argIndex]=next;
        [[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:configs atIndex:actionIndex error:nil]; [selfRef renderPage];
    }]];
    [top presentViewController:alert animated:YES completion:nil];
}
@end

extern "C" void ZNInstallM55TypedControlBindingDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040"); if(!cls)return;
        Method b0=class_getInstanceMethod(cls,@selector(zn50b_renderOther));
        Method b1=class_getInstanceMethod(cls,@selector(znm55_builderRender));
        if(b0&&b1)method_exchangeImplementations(b0,b1);
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.8-authoring] single Builder typed/gate decorator installed; no customer Runtime control swizzles"];
    });
}
