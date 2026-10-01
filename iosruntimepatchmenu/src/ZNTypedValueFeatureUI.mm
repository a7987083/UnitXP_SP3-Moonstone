#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>
#import "ZNTypedValueDispatchRuntime.h"
#import "ZNPatchCore.h"
#import "ZNTheme.h"

static const NSInteger kZNTVSliderTagBase = 560000;
static const NSInteger kZNTVNumberTagBase = 561000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static CGFloat ZNTVBottom(UIView *root, CGFloat fallback) {
    CGFloat y = fallback;
    for (UIView *view in root.subviews) y = MAX(y, CGRectGetMaxY(view.frame) + 6.0);
    return y;
}

static double ZNTVClampStep(double value, double minValue, double maxValue, double step) {
    value = MIN(MAX(value, minValue), maxValue);
    if (step > 0.0 && isfinite(step)) value = minValue + round((value - minValue) / step) * step;
    return MIN(MAX(value, minValue), maxValue);
}

@interface ZNRuntimeMenuControllerV040 (ZNTypedValueFeatureUI)
- (void)zn511_renderFeatureGroupsFull;
- (void)zn511_renderFeatureGroupsCompact;
- (void)zn511_sliderChanged:(UISlider *)slider;
- (void)zn511_numberChanged:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNTypedValueFeatureUI)

- (void)zn511_appendTyped:(BOOL)compact {
    ZNTypedValueDispatchRuntime *runtime = [ZNTypedValueDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNTypedValueRuntimeRecord *> *records = runtime.records;
    if (!records.count) return;

    // If Static Dispatch rendered only its empty placeholder, replace it with
    // the actual Typed Value controls instead of showing a false "暂无功能" card.
    BOOL hasStaticContent = NO;
    for (UIView *view in self.contentView.subviews) {
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:UILabel.class] && [((UILabel *)child).text isEqualToString:@"暂无功能"]) continue;
            if ([child isKindOfClass:UILabel.class]) { hasStaticContent = YES; break; }
        }
        if (hasStaticContent) break;
    }
    CGFloat y = compact ? 7.0 : 9.0;
    if (!hasStaticContent) [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    else y = ZNTVBottom(self.contentView, y);

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    for (NSUInteger i = 0; i < records.count; i++) {
        ZNTypedValueRuntimeRecord *record = records[i];
        CGFloat h = compact ? 58.0 : 66.0;
        UIView *card = [self cardAtY:y height:h width:width compact:compact];
        UILabel *name = [self label:record.title ?: @"Value Offset"
                                size:(compact ? 10.4 : 11.1)
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(compact ? 9 : 13, 5, card.bounds.size.width - (compact ? 18 : 26), 18);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        if (record.control == ZNTVStaticControlSlider) {
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(compact ? 9 : 13, 25, card.bounds.size.width - (compact ? 72 : 86), 28)];
            slider.tag = kZNTVSliderTagBase + (NSInteger)i;
            slider.minimumValue = (float)record.minValue;
            slider.maximumValue = (float)record.maxValue;
            double current = record.currentValueText.length ? record.currentValueText.doubleValue : record.defaultValue;
            slider.value = (float)ZNTVClampStep(current, record.minValue, record.maxValue, record.stepValue);
            slider.continuous = YES;
            [slider addTarget:self action:@selector(zn511_sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:slider];

            UILabel *value = [self label:[NSString stringWithFormat:@"%.4g", slider.value]
                                     size:(compact ? 9.0 : 9.5)
                                   weight:UIFontWeightMedium
                                    color:self.theme.secondaryTextColor];
            value.tag = kZNTVSliderTagBase + 10000 + (NSInteger)i;
            value.frame = CGRectMake(CGRectGetMaxX(slider.frame) + 4, 29, compact ? 48 : 56, 20);
            value.textAlignment = NSTextAlignmentRight;
            [card addSubview:value];
        } else {
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(compact ? 9 : 13, 26, card.bounds.size.width - (compact ? 18 : 26), compact ? 26 : 29)];
            field.tag = kZNTVNumberTagBase + (NSInteger)i;
            field.text = record.currentValueText.length ? record.currentValueText : [NSString stringWithFormat:@"%.12g", record.defaultValue];
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            field.returnKeyType = UIReturnKeyDone;
            field.font = [UIFont monospacedDigitSystemFontOfSize:(compact ? 10.0 : 10.5) weight:UIFontWeightMedium];
            field.textColor = self.theme.primaryTextColor;
            field.backgroundColor = self.theme.controlColor;
            field.layer.cornerRadius = 7;
            field.layer.borderWidth = 1;
            field.layer.borderColor = self.theme.borderColor.CGColor;
            UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
            field.leftView = pad; field.leftViewMode = UITextFieldViewModeAlways;
            [field addTarget:self action:@selector(zn511_numberChanged:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:field];
        }

        [self.contentView addSubview:card];
        y += h + 6.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn511_renderFeatureGroupsFull {
    [self zn511_renderFeatureGroupsFull];
    [self zn511_appendTyped:NO];
}

- (void)zn511_renderFeatureGroupsCompact {
    [self zn511_renderFeatureGroupsCompact];
    [self zn511_appendTyped:YES];
}

- (void)zn511_sliderChanged:(UISlider *)slider {
    NSInteger index = slider.tag - kZNTVSliderTagBase;
    NSArray *records = [ZNTypedValueDispatchRuntime sharedRuntime].records;
    if (index < 0 || (NSUInteger)index >= records.count) return;
    ZNTypedValueRuntimeRecord *record = records[(NSUInteger)index];
    double value = ZNTVClampStep(slider.value, record.minValue, record.maxValue, record.stepValue);
    slider.value = (float)value;
    NSString *text = [NSString stringWithFormat:@"%.12g", value];
    NSString *error = nil;
    if (![[ZNTypedValueDispatchRuntime sharedRuntime] setValueText:text forRecord:record error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-value-ui] slider write failed %@: %@", record.title, error ?: @"unknown"]];
        return;
    }
    UILabel *label = (UILabel *)[self.contentView viewWithTag:kZNTVSliderTagBase + 10000 + index];
    if ([label isKindOfClass:UILabel.class]) label.text = [NSString stringWithFormat:@"%.4g", value];
}

- (void)zn511_numberChanged:(UITextField *)field {
    NSInteger index = field.tag - kZNTVNumberTagBase;
    NSArray *records = [ZNTypedValueDispatchRuntime sharedRuntime].records;
    if (index < 0 || (NSUInteger)index >= records.count) return;
    ZNTypedValueRuntimeRecord *record = records[(NSUInteger)index];
    NSString *error = nil;
    if (![[ZNTypedValueDispatchRuntime sharedRuntime] setValueText:field.text ?: @"" forRecord:record error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-value-ui] number write failed %@: %@", record.title, error ?: @"unknown"]];
        field.text = record.currentValueText;
    }
}

@end

static void ZNTVSwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallTypedValueFeatureUIDeferred(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
    if (!cls) return;
    ZNTVSwap(cls, @selector(zn50_renderFeatureGroupsFull), @selector(zn511_renderFeatureGroupsFull));
    ZNTVSwap(cls, @selector(zn50_renderFeatureGroupsCompact), @selector(zn511_renderFeatureGroupsCompact));
    [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][m5.11] generated Typed Value Slider/Number UI installed"];
}
