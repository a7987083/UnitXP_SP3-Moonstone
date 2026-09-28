#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNRangeControl.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// ZN_UI_CANONICAL_FEATURE_RENDERER
// M6.3 canonical customer Feature renderer.
// This translation unit is the ONLY owner allowed to replace zn51_renderRuntime:.
// It creates final cards directly; there is no later move/hide/relabel pass.

static const NSInteger kZNM630CardTag   = 895000;
static const NSInteger kZNM630ExecTag   = 896000;
static const NSInteger kZNM630FieldTag  = 897000;
static const NSInteger kZNM630SwitchTag = 898000;
static const NSInteger kZNM630SliderTag = 899000;
static const NSInteger kZNM630ValueTag  = 901000;
static NSString * const kZNM630RuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn51_renderRuntime:(BOOL)compact;
- (void)znm58_numberChanged:(UITextField *)field;
- (void)znm58_numberReturn:(UITextField *)field;
- (void)znm58_switchChanged:(UISwitch *)control;
- (void)znm58_sliderChanged:(ZNRangeControl *)control;
- (void)znm58_sliderCommitted:(ZNRangeControl *)control;
- (void)znm58_execute:(UIButton *)sender;
@end

static NSString *ZNM630Trim(NSString *value) {
    return [(value ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM630RecordKey(ZNRuntimeMethodActionRecord *record) {
    NSString *identity = record.canonicalIdentity.length ? record.canonicalIdentity : [NSString stringWithFormat:@"%@::%@/%lu", record.className ?: @"", record.methodName ?: @"", (unsigned long)record.argumentCount];
    return [NSString stringWithFormat:@"%u|%@", record.actionID, identity ?: @""];
}

static NSArray<NSString *> *ZNM630StoredValues(ZNRuntimeMethodActionRecord *record) {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults objectForKey:kZNM630RuntimeValuesKey];
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSArray *values = root[ZNM630RecordKey(record)];
    if (![values isKindOfClass:NSArray.class] || values.count != record.argumentCount) return nil;
    return values;
}

static double ZNM630Quantize(double value, NSDictionary *cfg, double fallbackMin, double fallbackMax) {
    double min = [cfg[@"min"] doubleValue], max = [cfg[@"max"] doubleValue], step = [cfg[@"step"] doubleValue];
    if (!isfinite(min)) min = fallbackMin;
    if (!isfinite(max) || max <= min) max = fallbackMax > min ? fallbackMax : min + 1.0;
    if (!isfinite(step) || step <= 0.0) step = 1.0;
    value = MAX(min, MIN(max, value));
    double q = min + round((value - min) / step) * step;
    return MAX(min, MIN(max, q));
}

static NSString *ZNM630ValueText(double value, NSDictionary *cfg) {
    double step = [cfg[@"step"] doubleValue];
    if (!isfinite(step) || step <= 0.0) step = 1.0;
    if (fabs(step - round(step)) < 1e-9 && fabs(value - round(value)) < 1e-9) return [NSString stringWithFormat:@"%.0f", value];
    return [NSString stringWithFormat:@"%.6g", value];
}

@interface ZNRuntimeMenuControllerV040 (ZNM630SingleRenderer)
- (void)znm630_renderRuntime:(BOOL)compact;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM630SingleRenderer)

- (void)znm630_renderRuntime:(BOOL)compact {
    for (UIView *view in [self.contentView.subviews copy]) {
        if (view.tag >= kZNM630CardTag && view.tag < kZNM630CardTag + 512) [view removeFromSuperview];
    }

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *records = runtime.records ?: @[];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = compact ? 7.0 : 9.0;

    for (NSUInteger i = 0; i < records.count; i++) {
        ZNRuntimeMethodActionRecord *record = records[i];
        NSArray<NSDictionary *> *configs = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs : @[];
        NSArray<NSString *> *stored = ZNM630StoredValues(record);

        NSUInteger exposed = 0, numberCount = 0;
        for (NSDictionary *cfg in configs) {
            if (![cfg[@"enabled"] boolValue]) continue;
            exposed++;
            if (ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]) == ZNRuntimeArgumentControlTypeNumber) numberCount++;
        }
        BOOL zeroArgument = record.argumentCount == 0;
        BOOL fixedOnly = record.argumentCount > 0 && exposed == 0;
        BOOL singleNumber = exposed == 1 && numberCount == 1;
        BOOL headerExecute = zeroArgument || fixedOnly || (numberCount > 0 && !singleNumber);

        CGFloat headerH = compact ? 45.0 : 56.0;
        CGFloat rowH = compact ? 31.0 : 38.0;
        CGFloat height = headerH + exposed * rowH;
        if (zeroArgument || fixedOnly) height = compact ? 49.0 : 61.0;

        UIView *card = [self cardAtY:y height:height width:width compact:compact];
        card.tag = kZNM630CardTag + (NSInteger)i;
        CGFloat left = compact ? 10.0 : 14.0;
        CGFloat executeW = compact ? 56.0 : 66.0;
        CGFloat rightReserve = headerExecute ? executeW + 20.0 : 14.0;

        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:(compact ? 10.5 : 11.5)
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(left, compact ? 5.0 : 7.0, MAX(80.0, card.bounds.size.width - left - rightReserve), 20.0);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        NSString *description = ZNM630Trim(record.group);
        if ([description caseInsensitiveCompare:@"Runtime Methods"] == NSOrderedSame) description = @"";
        if (description.length) {
            UILabel *subtitle = [self label:description size:(compact ? 7.8 : 8.6) weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            subtitle.frame = CGRectMake(left, compact ? 24.0 : 28.0, MAX(80.0, card.bounds.size.width - left - rightReserve), 17.0);
            subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
            [card addSubview:subtitle];
        }

        if (headerExecute) {
            UIButton *execute = [self zn40_button:@"执行" selector:@selector(znm58_execute:) frame:CGRectMake(card.bounds.size.width - executeW - 12.0, compact ? 8.0 : 13.0, executeW, compact ? 29.0 : 34.0)];
            execute.tag = kZNM630ExecTag + (NSInteger)i;
            [card addSubview:execute];
        }

        CGFloat rowY = headerH;
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            NSDictionary *cfg = configs.count ? configs[arg] : nil;
            if (![cfg[@"enabled"] boolValue]) continue;
            NSInteger slot = (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            NSString *defaultValue = stored.count == record.argumentCount ? stored[arg] : (arg < record.argumentValues.count ? record.argumentValues[arg] : @"");
            ZNRuntimeArgumentControlType type = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);

            CGFloat controlX = left;
            CGFloat right = 12.0;
            CGFloat available = MAX(80.0, card.bounds.size.width - controlX - right);

            if (type == ZNRuntimeArgumentControlTypeSlider) {
                double min = [cfg[@"min"] doubleValue], max = [cfg[@"max"] doubleValue];
                if (!isfinite(min)) min = 0.0;
                if (!isfinite(max) || max <= min) max = min + 1.0;
                CGFloat valueW = compact ? 42.0 : 50.0, gap = 7.0;
                CGFloat sliderW = MAX(80.0, available - valueW - gap);
                ZNRangeControl *control = [[ZNRangeControl alloc] initWithFrame:CGRectMake(controlX, rowY + 2.0, sliderW, rowH - 5.0)];
                control.minimumValue = min; control.maximumValue = max;
                control.value = ZNM630Quantize(defaultValue.doubleValue, cfg, min, max);
                control.minimumTrackTintColor = self.theme.accentColor;
                control.maximumTrackTintColor = [self.theme.trackColor colorWithAlphaComponent:.78];
                control.thumbTintColor = self.theme.primaryTextColor;
                control.tag = kZNM630SliderTag + slot;
                [control addTarget:self action:@selector(znm58_sliderChanged:) forControlEvents:UIControlEventValueChanged];
                [control addTarget:self action:@selector(znm58_sliderCommitted:) forControlEvents:UIControlEventPrimaryActionTriggered];
                [card addSubview:control];

                UILabel *value = [self label:ZNM630ValueText(control.value, cfg) size:(compact ? 8.0 : 8.8) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
                value.textAlignment = NSTextAlignmentCenter;
                value.font = [UIFont monospacedDigitSystemFontOfSize:(compact ? 8.0 : 8.8) weight:UIFontWeightSemibold];
                value.backgroundColor = self.theme.controlColor;
                value.layer.cornerRadius = 7.0; value.layer.masksToBounds = YES;
                value.frame = CGRectMake(CGRectGetMaxX(control.frame) + gap, rowY + 5.0, valueW, rowH - 11.0);
                value.tag = kZNM630ValueTag + slot;
                [card addSubview:value];
            } else if (type == ZNRuntimeArgumentControlTypeSwitch) {
                UISwitch *control = [[UISwitch alloc] initWithFrame:CGRectZero];
                control.on = defaultValue.boolValue || [defaultValue.lowercaseString isEqualToString:@"true"];
                control.tag = kZNM630SwitchTag + slot;
                [control addTarget:self action:@selector(znm58_switchChanged:) forControlEvents:UIControlEventValueChanged];
                control.center = CGPointMake(card.bounds.size.width - right - control.bounds.size.width * .5, rowY + rowH * .5);
                [card addSubview:control];
            } else if (type == ZNRuntimeArgumentControlTypeButton) {
                UIButton *button = [self zn40_button:@"触发" selector:@selector(znm58_execute:) frame:CGRectMake(card.bounds.size.width - 70.0, rowY + 4.0, 58.0, rowH - 8.0)];
                button.tag = kZNM630ExecTag + (NSInteger)i;
                [card addSubview:button];
            } else {
                CGFloat execW = singleNumber ? (compact ? 56.0 : 66.0) : 0.0;
                CGFloat gap = singleNumber ? 7.0 : 0.0;
                CGFloat fieldW = MAX(80.0, available - execW - gap);
                UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(controlX, rowY + 4.0, fieldW, rowH - 8.0)];
                field.text = defaultValue; field.placeholder = @"数值";
                field.textColor = self.theme.primaryTextColor; field.backgroundColor = self.theme.controlColor;
                field.layer.cornerRadius = 8.0; field.layer.borderWidth = 1.0; field.layer.borderColor = self.theme.borderColor.CGColor;
                field.font = [UIFont monospacedDigitSystemFontOfSize:(compact ? 8.8 : 9.5) weight:UIFontWeightMedium];
                field.keyboardType = UIKeyboardTypeNumbersAndPunctuation; field.returnKeyType = UIReturnKeyDone;
                field.tag = kZNM630FieldTag + slot;
                [field addTarget:self action:@selector(znm58_numberChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm58_numberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];
                if (singleNumber) {
                    UIButton *execute = [self zn40_button:@"执行" selector:@selector(znm58_execute:) frame:CGRectMake(CGRectGetMaxX(field.frame) + gap, rowY + 4.0, execW, rowH - 8.0)];
                    execute.tag = kZNM630ExecTag + (NSInteger)i;
                    [card addSubview:execute];
                }
            }
            rowY += rowH;
        }

        [self.contentView addSubview:card];
        y += height + (compact ? 7.0 : 10.0);
    }

    [self zn40_updateContentHeight:y + (compact ? 3.0 : 6.0)];
}
@end

extern "C" void ZNInstallM630SingleUnifiedRendererDeferred(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method current = class_getInstanceMethod(cls, @selector(zn51_renderRuntime:));
        Method canonical = class_getInstanceMethod(cls, @selector(znm630_renderRuntime:));
        if (current && canonical) method_setImplementation(current, method_getImplementation(canonical));
        [[ZNRuntimeLogger sharedLogger] log:@"[m6.3-ui] canonical single Feature renderer installed; customer parameter labels are not created"];
    });
}
