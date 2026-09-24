#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM55Arg1Tag = 674000;
static const NSInteger kZNM55MultiArgTag = 690000;
static const NSInteger kZNM55CheckTag = 812000;
static const NSInteger kZNM55ControlTag = 813000;
static const NSInteger kZNM55ValueTag = 815000;
static const NSInteger kZNM55FieldTag = 797000;
static const NSInteger kZNM55SliderTag = 799000;
static const void *kZNM55ActionKey = &kZNM55ActionKey;
static const void *kZNM55ArgKey = &kZNM55ArgKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)renderPage;
- (void)zn50b_renderOther;
- (void)zn51_runtimeNumberChanged:(UITextField *)field;
- (void)zn51_runtimeSliderChanged:(UISlider *)slider;
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

static ZNValueType ZNM55ResolvedRecordType(ZNRuntimeMethodActionRecord *record, NSUInteger arg, NSDictionary *cfg) {
    ZNValueType authored = ZNValueTypeFromKey([cfg[@"valueType"] isKindOfClass:NSString.class] ? cfg[@"valueType"] : @"auto");
    if (authored != ZNValueTypeAuto) return authored;
    NSString *managed = arg < record.parameterTypeNames.count ? record.parameterTypeNames[arg] : @"";
    return ZNValueTypeForManagedTypeName(managed);
}

@interface ZNRuntimeMenuControllerV040 (ZNM55Typed)
- (void)znm55_builderRender;
- (void)znm55_cycleValueType:(UIButton *)sender;
- (void)znm55_rangeLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)znm55_runtimeNumberChanged:(UITextField *)field;
- (void)znm55_runtimeSliderChanged:(UISlider *)slider;
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

- (void)znm55_runtimeNumberChanged:(UITextField *)field {
    NSInteger slot = field.tag - kZNM55FieldTag;
    if (slot >= 0 && !field.isEditing) {
        NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
        NSUInteger arg = (NSUInteger)slot % ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
        ZNRuntimeActionRuntime *runtime=[ZNRuntimeActionRuntime sharedRuntime]; [runtime refresh];
        if (recordIndex < runtime.records.count) {
            ZNRuntimeMethodActionRecord *record=runtime.records[recordIndex];
            if (arg < record.argumentCount && record.argumentControlConfigs.count==record.argumentCount) {
                NSDictionary *cfg=record.argumentControlConfigs[arg]; ZNValueType type=ZNM55ResolvedRecordType(record,arg,cfg);
                if(type!=ZNValueTypeAuto){NSString *err=nil;NSString *canonical=ZNCanonicalValueString(field.text,type,cfg[@"min"],cfg[@"max"],cfg[@"step"],&err);if(canonical.length)field.text=canonical;else{field.text=[cfg[@"default"] description]?:@"1";[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.5-typed] number fallback %@",err?:@"invalid"]];}}
            }
        }
    }
    [self znm55_runtimeNumberChanged:field];
}

- (void)znm55_runtimeSliderChanged:(UISlider *)slider {
    NSInteger slot=slider.tag-kZNM55SliderTag;
    if(slot>=0){NSUInteger recordIndex=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS;NSUInteger arg=(NSUInteger)slot%ZN_RUNTIME_ACTION_MAX_ARGUMENTS;ZNRuntimeActionRuntime *runtime=[ZNRuntimeActionRuntime sharedRuntime];[runtime refresh];if(recordIndex<runtime.records.count){ZNRuntimeMethodActionRecord *record=runtime.records[recordIndex];if(arg<record.argumentCount&&record.argumentControlConfigs.count==record.argumentCount){NSDictionary *cfg=record.argumentControlConfigs[arg];double step=[cfg[@"step"] doubleValue];double min=[cfg[@"min"] doubleValue];if(step<=0||!isfinite(step))step=1.0;double q=min+round(((double)slider.value-min)/step)*step;q=MAX((double)slider.minimumValue,MIN((double)slider.maximumValue,q));slider.value=(float)q;}}}
    [self znm55_runtimeSliderChanged:slider];
}
@end

extern "C" void ZNInstallM55TypedControlBindingDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040"); if(!cls)return;
        Method b0=class_getInstanceMethod(cls,@selector(zn50b_renderOther)); Method b1=class_getInstanceMethod(cls,@selector(znm55_builderRender)); if(b0&&b1)method_exchangeImplementations(b0,b1);
        Method n0=class_getInstanceMethod(cls,@selector(zn51_runtimeNumberChanged:)); Method n1=class_getInstanceMethod(cls,@selector(znm55_runtimeNumberChanged:)); if(n0&&n1)method_exchangeImplementations(n0,n1);
        Method s0=class_getInstanceMethod(cls,@selector(zn51_runtimeSliderChanged:)); Method s1=class_getInstanceMethod(cls,@selector(znm55_runtimeSliderChanged:)); if(s0&&s1)method_exchangeImplementations(s0,s1);
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.5-typed] Value Type + range editor + integer-step slider installed"];
    });
}
