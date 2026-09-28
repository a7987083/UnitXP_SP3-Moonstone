#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRangeControl.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM58CardTag   = 895000;
static const NSInteger kZNM58ExecTag   = 896000;
static const NSInteger kZNM58FieldTag  = 897000;
static const NSInteger kZNM58SwitchTag = 898000;
static const NSInteger kZNM58SliderTag = 899000;
static const NSInteger kZNM58ButtonTag = 900000;
static const NSInteger kZNM58ValueTag  = 901000;
static NSString * const kZNM582RuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn51_renderRuntime:(BOOL)compact;
@end

static CGFloat ZNM58MaxY(UIView *root) {
    CGFloat y = 0;
    for (UIView *v in root.subviews) y = MAX(y, CGRectGetMaxY(v.frame));
    return y;
}

static UIViewController *ZNM58Top(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

static NSString *ZNM58ShortType(NSString *type) {
    NSArray<NSString *> *parts = [(type ?: @"") componentsSeparatedByString:@"."];
    NSString *last = [parts.lastObject isKindOfClass:NSString.class] ? parts.lastObject : @"";
    return last.length ? last : (type ?: @"?");
}

static double ZNM58Quantize(double value, NSDictionary *cfg, double fallbackMin, double fallbackMax) {
    double min = [cfg[@"min"] doubleValue];
    double max = [cfg[@"max"] doubleValue];
    double step = [cfg[@"step"] doubleValue];
    if (!isfinite(min)) min = fallbackMin;
    if (!isfinite(max) || max <= min) max = fallbackMax > min ? fallbackMax : min + 100.0;
    if (!isfinite(step) || step <= 0.0) step = 1.0;
    value = MAX(min, MIN(max, value));
    double q = min + round((value - min) / step) * step;
    return MAX(min, MIN(max, q));
}

static NSString *ZNM582ValueText(double value, NSDictionary *cfg) {
    double step = [cfg[@"step"] doubleValue];
    if (!isfinite(step) || step <= 0.0) step = 1.0;
    if (fabs(step - round(step)) < 1e-9 && fabs(value - round(value)) < 1e-9) {
        return [NSString stringWithFormat:@"%.0f", value];
    }
    return [NSString stringWithFormat:@"%.6g", value];
}

static NSString *ZNM582RecordKey(ZNRuntimeMethodActionRecord *record) {
    NSString *identity = record.canonicalIdentity.length ? record.canonicalIdentity : [NSString stringWithFormat:@"%@::%@/%lu", record.className ?: @"", record.methodName ?: @"", (unsigned long)record.argumentCount];
    return [NSString stringWithFormat:@"%u|%@", record.actionID, identity ?: @""];
}

static NSArray<NSString *> *ZNM582StoredValues(ZNRuntimeMethodActionRecord *record) {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults objectForKey:kZNM582RuntimeValuesKey];
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSArray *values = root[ZNM582RecordKey(record)];
    if (![values isKindOfClass:NSArray.class] || values.count != record.argumentCount) return nil;
    for (id value in values) if (![value isKindOfClass:NSString.class]) return nil;
    return values;
}

static void ZNM582StoreValues(ZNRuntimeMethodActionRecord *record, NSArray<NSString *> *values) {
    if (!record || values.count != record.argumentCount) return;
    NSDictionary *current = [NSUserDefaults.standardUserDefaults objectForKey:kZNM582RuntimeValuesKey];
    NSMutableDictionary *root = [current isKindOfClass:NSDictionary.class] ? [current mutableCopy] : [NSMutableDictionary dictionary];
    root[ZNM582RecordKey(record)] = [values copy];
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNM582RuntimeValuesKey];
}

static NSUInteger ZNM582ControlScore(ZNRuntimeMethodActionRecord *record) {
    NSUInteger enabled = 0;
    for (NSDictionary *cfg in record.argumentControlConfigs ?: @[]) if ([cfg[@"enabled"] boolValue]) enabled++;
    return enabled * 100 + record.argumentControlConfigs.count * 10 + record.argumentCount;
}

static NSArray<NSNumber *> *ZNM582DisplayRecordIndexes(NSArray<ZNRuntimeMethodActionRecord *> *records) {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *chosen = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *scores = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < records.count; i++) {
        ZNRuntimeMethodActionRecord *record = records[i];
        NSString *title = (record.title.length ? record.title : record.methodName).lowercaseString ?: @"";
        NSString *identity = record.canonicalIdentity ?: @"";
        NSString *key = [NSString stringWithFormat:@"%@|%@", title, identity];
        NSUInteger score = ZNM582ControlScore(record);
        NSNumber *old = chosen[key];
        if (!old) {
            [order addObject:key];
            chosen[key] = @(i);
            scores[key] = @(score);
        } else if (score > [scores[key] unsignedIntegerValue]) {
            chosen[key] = @(i);
            scores[key] = @(score);
        }
    }
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) [indexes addObject:chosen[key]];
    return indexes;
}

@interface ZNRuntimeMenuControllerV040 (ZNM58UnifiedControlRuntime)
- (void)znm58_renderRuntime:(BOOL)compact;
- (void)znm58_numberChanged:(UITextField *)field;
- (void)znm58_numberReturn:(UITextField *)field;
- (void)znm58_switchChanged:(UISwitch *)control;
- (void)znm58_sliderChanged:(ZNRangeControl *)control;
- (void)znm58_sliderCommitted:(ZNRangeControl *)control;
- (void)znm58_execute:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM58UnifiedControlRuntime)

- (void)znm58_removeCards {
    for (UIView *view in [self.contentView.subviews copy]) {
        BOOL oldM49 = view.tag >= 786000 && view.tag < 786512;
        BOOL oldM51 = view.tag >= 795000 && view.tag < 795512;
        BOOL m58 = view.tag >= kZNM58CardTag && view.tag < kZNM58CardTag + 512;
        if (oldM49 || oldM51 || m58) [view removeFromSuperview];
    }
}

- (void)znm581_removeStaticEmptyStateIfRuntimeExists:(NSArray *)records {
    if (!records.count) return;
    for (UIView *view in [self.contentView.subviews copy]) {
        __block BOOL emptyState = NO;
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:view];
        while (stack.count && !emptyState) {
            UIView *node = stack.lastObject;
            [stack removeLastObject];
            if ([node isKindOfClass:UILabel.class] && [((UILabel *)node).text isEqualToString:@"暂无功能"]) {
                emptyState = YES;
                break;
            }
            [stack addObjectsFromArray:node.subviews ?: @[]];
        }
        if (emptyState) [view removeFromSuperview];
    }
}

- (void)znm58_renderRuntime:(BOOL)compact {
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    [self znm58_removeCards];

    NSArray<ZNRuntimeMethodActionRecord *> *records = runtime.records ?: @[];
    [self znm581_removeStaticEmptyStateIfRuntimeExists:records];
    NSArray<NSNumber *> *displayIndexes = ZNM582DisplayRecordIndexes(records);
    if (displayIndexes.count != records.count) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.8.2-control] collapsed duplicate cards %lu -> %lu", (unsigned long)records.count, (unsigned long)displayIndexes.count]];
    }

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNM58MaxY(self.contentView) + (compact ? 6.0 : 8.0);

    for (NSNumber *indexNumber in displayIndexes) {
        NSUInteger i = indexNumber.unsignedIntegerValue;
        if (i >= records.count) continue;
        ZNRuntimeMethodActionRecord *record = records[i];
        NSArray<NSDictionary *> *configs = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs : @[];
        NSArray<NSString *> *storedValues = ZNM582StoredValues(record);
        NSUInteger exposed = 0;
        BOOL needsManualExecute = (record.argumentCount == 0);
        for (NSDictionary *cfg in configs) {
            if (![cfg[@"enabled"] boolValue]) continue;
            exposed++;
            if (ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]) == ZNRuntimeArgumentControlTypeNumber) needsManualExecute = YES;
        }
        if (exposed == 0) needsManualExecute = YES;

        CGFloat rowH = 34.0, baseH = compact ? 42.0 : 48.0;
        CGFloat height = baseH + exposed * rowH;
        UIView *card = [self cardAtY:y height:height width:width compact:compact];
        card.tag = kZNM58CardTag + (NSInteger)i;

        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:(compact ? 10.5 : 11.2)
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(compact ? 9 : 13, 8, card.bounds.size.width - (needsManualExecute ? 92 : 26), 24);
        [card addSubview:name];

        if (needsManualExecute) {
            UIButton *execute = [self zn40_button:@"执行" selector:@selector(znm58_execute:) frame:CGRectMake(card.bounds.size.width - 76, 7, 64, 29)];
            execute.tag = kZNM58ExecTag + (NSInteger)i;
            [card addSubview:execute];
        }

        CGFloat rowY = baseH;
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            NSDictionary *cfg = configs.count ? configs[arg] : nil;
            if (![cfg[@"enabled"] boolValue]) continue;

            NSString *typeName = arg < record.parameterTypeNames.count ? record.parameterTypeNames[arg] : @"?";
            UILabel *label = [self label:[NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, ZNM58ShortType(typeName)]
                                      size:8.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
            label.frame = CGRectMake(13, rowY, 82, 28);
            [card addSubview:label];

            NSInteger slot = (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            NSString *defaultValue = (storedValues.count == record.argumentCount) ? storedValues[arg] : (arg < record.argumentValues.count ? record.argumentValues[arg] : @"");
            ZNRuntimeArgumentControlType controlType = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);

            if (controlType == ZNRuntimeArgumentControlTypeSwitch) {
                UISwitch *control = [[UISwitch alloc] initWithFrame:CGRectZero];
                control.on = defaultValue.boolValue || [defaultValue.lowercaseString isEqualToString:@"true"];
                control.tag = kZNM58SwitchTag + slot;
                [control addTarget:self action:@selector(znm58_switchChanged:) forControlEvents:UIControlEventValueChanged];
                control.center = CGPointMake(card.bounds.size.width - 38, rowY + 14);
                [card addSubview:control];
            } else if (controlType == ZNRuntimeArgumentControlTypeSlider) {
                double min = [cfg[@"min"] doubleValue];
                double max = [cfg[@"max"] doubleValue];
                if (!isfinite(min)) min = 1.0;
                if (!isfinite(max) || max <= min) max = min + 9.0;
                CGFloat valueW = 46.0;
                CGFloat sliderW = MAX(70.0, card.bounds.size.width - 109.0 - valueW - 5.0);
                ZNRangeControl *control = [[ZNRangeControl alloc] initWithFrame:CGRectMake(96, rowY, sliderW, 28)];
                control.minimumValue = min;
                control.maximumValue = max;
                control.value = ZNM58Quantize(defaultValue.doubleValue, cfg, min, max);
                control.minimumTrackTintColor = self.theme.accentColor;
                control.maximumTrackTintColor = [self.theme.trackColor colorWithAlphaComponent:.75];
                control.thumbTintColor = self.theme.primaryTextColor;
                control.tag = kZNM58SliderTag + slot;
                [control addTarget:self action:@selector(znm58_sliderChanged:) forControlEvents:UIControlEventValueChanged];
                [control addTarget:self action:@selector(znm58_sliderCommitted:) forControlEvents:UIControlEventPrimaryActionTriggered];
                [card addSubview:control];

                UILabel *valueLabel = [self label:ZNM582ValueText(control.value, cfg) size:8.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
                valueLabel.textAlignment = NSTextAlignmentRight;
                valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:8.4 weight:UIFontWeightSemibold];
                valueLabel.frame = CGRectMake(CGRectGetMaxX(control.frame) + 4.0, rowY, valueW, 28);
                valueLabel.tag = kZNM58ValueTag + slot;
                [card addSubview:valueLabel];
            } else if (controlType == ZNRuntimeArgumentControlTypeButton) {
                UIButton *button = [self zn40_button:@"触发" selector:@selector(znm58_execute:) frame:CGRectMake(card.bounds.size.width - 70, rowY, 58, 28)];
                button.tag = kZNM58ExecTag + (NSInteger)i;
                [card addSubview:button];
            } else {
                UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(96, rowY, card.bounds.size.width - 109, 28)];
                field.text = defaultValue;
                field.placeholder = defaultValue;
                field.textColor = self.theme.primaryTextColor;
                field.backgroundColor = self.theme.controlColor;
                field.layer.cornerRadius = 6;
                field.layer.borderWidth = 1;
                field.layer.borderColor = self.theme.borderColor.CGColor;
                field.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium];
                field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                field.returnKeyType = UIReturnKeyDone;
                field.tag = kZNM58FieldTag + slot;
                [field addTarget:self action:@selector(znm58_numberChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm58_numberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];
            }
            rowY += rowH;
        }

        [self.contentView addSubview:card];
        y += height + (compact ? 6.0 : 8.0);
    }
    [self zn40_updateContentHeight:y];
}

- (void)znm58_numberChanged:(UITextField *)field { (void)field; }
- (void)znm58_numberReturn:(UITextField *)field { [field resignFirstResponder]; }

- (void)znm58_switchChanged:(UISwitch *)control {
    NSInteger slot = control.tag - kZNM58SwitchTag;
    if (slot < 0) return;
    NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    UIButton *proxy = [UIButton buttonWithType:UIButtonTypeCustom];
    proxy.tag = kZNM58ExecTag + (NSInteger)recordIndex;
    [self znm58_execute:proxy];
}

- (void)znm58_sliderChanged:(ZNRangeControl *)control {
    NSInteger slot = control.tag - kZNM58SliderTag;
    if (slot < 0) return;
    NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    NSUInteger arg = (NSUInteger)slot % ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    if (recordIndex >= runtime.records.count) return;
    ZNRuntimeMethodActionRecord *record = runtime.records[recordIndex];
    NSDictionary *cfg = record.argumentControlConfigs.count == record.argumentCount && arg < record.argumentCount ? record.argumentControlConfigs[arg] : @{};
    control.value = ZNM58Quantize(control.value, cfg, control.minimumValue, control.maximumValue);
    UIView *view = [self.contentView viewWithTag:kZNM58ValueTag + slot];
    if ([view isKindOfClass:UILabel.class]) ((UILabel *)view).text = ZNM582ValueText(control.value, cfg);
}

- (void)znm58_sliderCommitted:(ZNRangeControl *)control {
    NSInteger slot = control.tag - kZNM58SliderTag;
    if (slot < 0) return;
    [self znm58_sliderChanged:control];
    NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    UIButton *proxy = [UIButton buttonWithType:UIButtonTypeCustom];
    proxy.tag = kZNM58ExecTag + (NSInteger)recordIndex;
    [self znm58_execute:proxy];
}

- (NSString *)znm58_valueForRecord:(NSUInteger)recordIndex arg:(NSUInteger)arg cfg:(NSDictionary *)cfg fallback:(NSString *)fallback {
    NSInteger slot = (NSInteger)(recordIndex * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
    ZNRuntimeArgumentControlType type = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
    if (type == ZNRuntimeArgumentControlTypeSwitch) {
        UIView *v = [self.contentView viewWithTag:kZNM58SwitchTag + slot];
        if ([v isKindOfClass:UISwitch.class]) return ((UISwitch *)v).on ? @"true" : @"false";
    } else if (type == ZNRuntimeArgumentControlTypeSlider) {
        UIView *v = [self.contentView viewWithTag:kZNM58SliderTag + slot];
        if ([v isKindOfClass:ZNRangeControl.class]) {
            ZNRangeControl *s = (ZNRangeControl *)v;
            double q = ZNM58Quantize(s.value, cfg, s.minimumValue, s.maximumValue);
            return [NSString stringWithFormat:@"%.17g", q];
        }
    } else if (type == ZNRuntimeArgumentControlTypeNumber) {
        UIView *v = [self.contentView viewWithTag:kZNM58FieldTag + slot];
        if ([v isKindOfClass:UITextField.class]) return ((UITextField *)v).text ?: fallback ?: @"";
    }
    return fallback ?: @"";
}

- (void)znm58_execute:(UIButton *)sender {
    NSInteger index = sender.tag - kZNM58ExecTag;
    if (index < 0) return;

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) return;
    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    NSArray<NSString *> *storedValues = ZNM582StoredValues(record);

    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithArray:(storedValues.count == record.argumentCount ? storedValues : (record.argumentValues ?: @[]))];
    while (values.count < record.argumentCount) [values addObject:@""];
    if (record.argumentControlConfigs.count == record.argumentCount) {
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            NSDictionary *cfg = record.argumentControlConfigs[arg];
            if (![cfg[@"enabled"] boolValue]) continue;
            NSString *fallback = arg < values.count ? values[arg] : @"";
            values[arg] = [self znm58_valueForRecord:(NSUInteger)index arg:arg cfg:cfg fallback:fallback];
        }
    }

    ZNM582StoreValues(record, values);

    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.actionID = record.actionID;
    action.title = record.title;
    action.group = record.group;
    action.assembly = record.assembly;
    action.namespaceName = record.namespaceName;
    action.className = record.className;
    action.methodName = record.methodName;
    action.argumentCount = record.argumentCount;
    action.argumentValues = values;
    action.parameterTypeNames = record.parameterTypeNames;
    action.signatureAvailable = record.signatureAvailable;
    action.argumentControlConfigs = record.argumentControlConfigs;
    action.immediateChain = record.immediateChain;

    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    if (result) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.8.2-control] %@ SUCCESS persisted=%@", action.canonicalIdentity ?: @"?", values ?: @[]]];
        return;
    }

    UIViewController *top = ZNM58Top(self.hostWindow);
    if (!top) return;
    UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"执行失败" message:(error.length ? error : @"执行失败") preferredStyle:UIAlertControllerStyleAlert];
    [failed addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:failed animated:YES completion:nil];
}
@end

extern "C" void ZNInstallM58UnifiedControlRuntimeDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method current = class_getInstanceMethod(cls, @selector(zn51_renderRuntime:));
        Method unified = class_getInstanceMethod(cls, @selector(znm58_renderRuntime:));
        if (current && unified) method_setImplementation(current, method_getImplementation(unified));
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.8.2-control] single runtime renderer + duplicate collapse + live slider value + runtime value persistence installed"];
    });
}
