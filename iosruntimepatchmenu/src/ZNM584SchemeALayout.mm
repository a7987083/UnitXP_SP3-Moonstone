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

// M5.8.4 Scheme A
// Visual-only refactor over the existing single Runtime surface.
// It does not create a second menu/controller/card hierarchy. The existing
// zn51_renderRuntime: implementation is replaced in-place after M5.8.3 installs.

static const NSInteger kZNM584CardTag   = 895000;
static const NSInteger kZNM584ExecTag   = 896000;
static const NSInteger kZNM584FieldTag  = 897000;
static const NSInteger kZNM584SwitchTag = 898000;
static const NSInteger kZNM584SliderTag = 899000;
static const NSInteger kZNM584ButtonTag = 900000;
static const NSInteger kZNM584ValueTag  = 901000;
static NSString * const kZNM584RuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

static const CGFloat kZNM584HeaderH = 52.0;
static const CGFloat kZNM584FooterH = 22.0;
static const CGFloat kZNM584SidebarPhoneW = 78.0;
static const CGFloat kZNM584SidebarWideW = 86.0;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIView *headerView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIView *readyDot;
@property(nonatomic,strong) UILabel *readyLabel;
@property(nonatomic,strong) UIButton *themeButton;
@property(nonatomic,strong) UIButton *modeButton;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UIView *sidebarView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIView *footerView;
@property(nonatomic,strong) UILabel *footerLabel;
@property(nonatomic,strong) NSMutableArray<UIButton *> *sidebarButtons;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,assign) BOOL compactMode;
@property(nonatomic,strong) ZNTheme *theme;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (void)renderPage;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn51_renderRuntime:(BOOL)compact;
- (void)znm58_numberChanged:(UITextField *)field;
- (void)znm58_numberReturn:(UITextField *)field;
- (void)znm58_switchChanged:(UISwitch *)control;
- (void)znm58_sliderChanged:(ZNRangeControl *)control;
- (void)znm58_sliderCommitted:(ZNRangeControl *)control;
- (void)znm58_execute:(UIButton *)sender;
@end

static NSString *ZNM584ShortType(NSString *type) {
    NSArray<NSString *> *parts = [(type ?: @"") componentsSeparatedByString:@"."];
    NSString *last = [parts.lastObject isKindOfClass:NSString.class] ? parts.lastObject : @"";
    return last.length ? last : (type.length ? type : @"?");
}

static NSString *ZNM584RecordKey(ZNRuntimeMethodActionRecord *record) {
    NSString *identity = record.canonicalIdentity.length
        ? record.canonicalIdentity
        : [NSString stringWithFormat:@"%@::%@/%lu", record.className ?: @"", record.methodName ?: @"", (unsigned long)record.argumentCount];
    return [NSString stringWithFormat:@"%u|%@", record.actionID, identity ?: @""];
}

static NSArray<NSString *> *ZNM584StoredValues(ZNRuntimeMethodActionRecord *record) {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults objectForKey:kZNM584RuntimeValuesKey];
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSArray *values = root[ZNM584RecordKey(record)];
    if (![values isKindOfClass:NSArray.class] || values.count != record.argumentCount) return nil;
    for (id value in values) if (![value isKindOfClass:NSString.class]) return nil;
    return values;
}

static double ZNM584Quantize(double value, NSDictionary *cfg, double fallbackMin, double fallbackMax) {
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

static NSString *ZNM584ValueText(double value, NSDictionary *cfg) {
    double step = [cfg[@"step"] doubleValue];
    if (!isfinite(step) || step <= 0.0) step = 1.0;
    if (fabs(step - round(step)) < 1e-9 && fabs(value - round(value)) < 1e-9) {
        return [NSString stringWithFormat:@"%.0f", value];
    }
    return [NSString stringWithFormat:@"%.6g", value];
}

static NSString *ZNM584DefaultValue(ZNRuntimeMethodActionRecord *record,
                                    NSArray<NSString *> *stored,
                                    NSUInteger arg) {
    if (stored.count == record.argumentCount && arg < stored.count) return stored[arg] ?: @"";
    if (arg < record.argumentValues.count) return record.argumentValues[arg] ?: @"";
    return @"";
}

static NSString *ZNM584FixedSummary(ZNRuntimeMethodActionRecord *record, NSArray<NSString *> *stored) {
    if (record.argumentCount == 0) return @"无参数";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
        NSString *type = arg < record.parameterTypeNames.count ? ZNM584ShortType(record.parameterTypeNames[arg]) : @"?";
        NSString *value = ZNM584DefaultValue(record, stored, arg);
        if (record.argumentCount == 1) {
            return value.length
                ? [NSString stringWithFormat:@"参数 1 · %@ · %@", type, value]
                : [NSString stringWithFormat:@"参数 1 · %@", type];
        }
        [parts addObject:value.length
            ? [NSString stringWithFormat:@"%lu:%@=%@", (unsigned long)arg + 1, type, value]
            : [NSString stringWithFormat:@"%lu:%@", (unsigned long)arg + 1, type]];
    }
    return [parts componentsJoinedByString:@"   "];
}

@interface ZNRuntimeMenuControllerV040 (ZNM584SchemeALayout)
- (void)znm584_layoutPanel;
- (void)znm584_layoutSidebar;
- (void)znm584_renderRuntime:(BOOL)compact;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM584SchemeALayout)

- (void)znm584_layoutSidebar {
    CGFloat width = CGRectGetWidth(self.sidebarView.bounds);
    CGFloat y = 9.0;
    CGFloat itemH = 43.0;
    CGFloat gap = 4.0;
    for (UIButton *button in self.sidebarButtons) {
        button.frame = CGRectMake(6.0, y, MAX(0.0, width - 12.0), itemH);
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 5);
        button.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
        button.titleEdgeInsets = UIEdgeInsetsZero;
        button.titleLabel.font = [self menuFont:10.3 weight:UIFontWeightSemibold];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.82;
        y += itemH + gap;
    }
}

- (void)znm584_layoutPanel {
    CGFloat w = CGRectGetWidth(self.panel.bounds);
    CGFloat h = CGRectGetHeight(self.panel.bounds);

    if (self.compactMode) {
        // Preserve the existing compact-mode geometry; Scheme A targets the
        // normal customer menu and does not create another compact hierarchy.
        CGFloat headerH = 48.0;
        self.headerView.frame = CGRectMake(0, 0, w, headerH);
        self.titleLabel.text = @"ZN";
        self.titleLabel.frame = CGRectMake(12, 7, 42, 20);
        self.subtitleLabel.hidden = NO;
        self.subtitleLabel.text = @"Compact";
        self.subtitleLabel.frame = CGRectMake(12, 25, 60, 15);
        self.readyDot.hidden = YES;
        self.readyLabel.hidden = YES;
        self.themeButton.hidden = YES;
        self.modeButton.hidden = NO;
        self.closeButton.hidden = NO;
        self.closeButton.frame = CGRectMake(w - 40, 7, 32, 32);
        self.modeButton.frame = CGRectMake(w - 78, 7, 32, 32);
        [self.modeButton setTitle:@"□" forState:UIControlStateNormal];
        self.sidebarView.hidden = YES;
        self.footerView.hidden = YES;
        self.contentScroll.frame = CGRectMake(0, headerH, w, MAX(0.0, h - headerH));
    } else {
        self.headerView.frame = CGRectMake(0, 0, w, kZNM584HeaderH);
        self.titleLabel.text = @"ZONOE PATCH";
        self.subtitleLabel.hidden = YES;
        self.titleLabel.frame = CGRectMake(14, 0, MAX(118.0, w - 252.0), kZNM584HeaderH);
        self.titleLabel.font = [self menuFont:16.0 weight:UIFontWeightHeavy];

        CGFloat buttonSize = 34.0;
        CGFloat buttonGap = 6.0;
        CGFloat right = 8.0;
        self.closeButton.hidden = NO;
        self.modeButton.hidden = NO;
        self.themeButton.hidden = NO;
        self.closeButton.frame = CGRectMake(w - right - buttonSize, 9, buttonSize, buttonSize);
        self.modeButton.frame = CGRectMake(CGRectGetMinX(self.closeButton.frame) - buttonGap - buttonSize, 9, buttonSize, buttonSize);
        self.themeButton.frame = CGRectMake(CGRectGetMinX(self.modeButton.frame) - buttonGap - buttonSize, 9, buttonSize, buttonSize);
        [self.modeButton setTitle:@"—" forState:UIControlStateNormal];
        self.modeButton.titleLabel.font = [self menuFont:15.0 weight:UIFontWeightSemibold];

        CGFloat readyRight = CGRectGetMinX(self.themeButton.frame) - 8.0;
        self.readyLabel.hidden = NO;
        self.readyDot.hidden = NO;
        self.readyLabel.frame = CGRectMake(readyRight - 48.0, 14, 42.0, 24.0);
        self.readyDot.frame = CGRectMake(CGRectGetMinX(self.readyLabel.frame) - 12.0, 22.0, 8.0, 8.0);

        CGFloat sidebarW = w < 430.0 ? kZNM584SidebarPhoneW : kZNM584SidebarWideW;
        CGFloat bodyH = MAX(0.0, h - kZNM584HeaderH - kZNM584FooterH);
        self.sidebarView.hidden = NO;
        self.footerView.hidden = NO;
        self.sidebarView.frame = CGRectMake(0, kZNM584HeaderH, sidebarW, bodyH);
        self.contentScroll.frame = CGRectMake(sidebarW, kZNM584HeaderH, MAX(0.0, w - sidebarW), bodyH);
        self.footerView.frame = CGRectMake(0, h - kZNM584FooterH, w, kZNM584FooterH);
        self.footerLabel.frame = CGRectMake(10, 0, w - 20, kZNM584FooterH);
        self.footerLabel.alpha = 0.82;
        self.footerLabel.font = [self menuFont:8.0 weight:UIFontWeightRegular];
        [self znm584_layoutSidebar];
    }

    self.contentView.frame = CGRectMake(0,
                                        0,
                                        CGRectGetWidth(self.contentScroll.bounds),
                                        MAX(CGRectGetHeight(self.contentScroll.bounds), self.contentView.frame.size.height));
    [self renderPage];
}

- (void)znm584_removeRuntimeCards {
    for (UIView *view in [self.contentView.subviews copy]) {
        BOOL oldM49 = view.tag >= 786000 && view.tag < 786512;
        BOOL oldM51 = view.tag >= 795000 && view.tag < 795512;
        BOOL runtime = view.tag >= kZNM584CardTag && view.tag < kZNM584CardTag + 512;
        BOOL schemeSection = view.tag == 902100 || view.tag == 902101;
        if (oldM49 || oldM51 || runtime || schemeSection) [view removeFromSuperview];
    }
}

- (void)znm584_removeStaticEmptyStateIfRuntimeExists:(NSArray *)records {
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

- (void)znm584_addSectionHeaderAtY:(CGFloat *)y width:(CGFloat)width compact:(BOOL)compact {
    if (compact) return;
    UILabel *title = [self label:@"功能" size:12.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.tag = 902100;
    title.frame = CGRectMake(12, *y, MAX(0.0, width - 24.0), 24.0);
    [self.contentView addSubview:title];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, *y + 27.0, MAX(0.0, width - 24.0), 0.5)];
    line.tag = 902101;
    line.backgroundColor = [self.theme.borderColor colorWithAlphaComponent:0.72];
    [self.contentView addSubview:line];
    *y += 37.0;
}

- (void)znm584_renderRuntime:(BOOL)compact {
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    [self znm584_removeRuntimeCards];

    NSArray<ZNRuntimeMethodActionRecord *> *records = runtime.records ?: @[];
    [self znm584_removeStaticEmptyStateIfRuntimeExists:records];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = compact ? 7.0 : 9.0;
    [self znm584_addSectionHeaderAtY:&y width:width compact:compact];

    for (NSUInteger i = 0; i < records.count; i++) {
        ZNRuntimeMethodActionRecord *record = records[i];
        NSArray<NSDictionary *> *configs = record.argumentControlConfigs.count == record.argumentCount
            ? record.argumentControlConfigs
            : @[];
        NSArray<NSString *> *storedValues = ZNM584StoredValues(record);

        NSUInteger exposed = 0;
        NSUInteger numberControls = 0;
        for (NSDictionary *cfg in configs) {
            if (![cfg[@"enabled"] boolValue]) continue;
            exposed++;
            if (ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]) == ZNRuntimeArgumentControlTypeNumber) numberControls++;
        }

        BOOL fixedOnly = (record.argumentCount > 0 && exposed == 0);
        BOOL zeroArgument = (record.argumentCount == 0);
        BOOL singleNumberRow = (exposed == 1 && numberControls == 1);
        BOOL headerExecute = fixedOnly || zeroArgument || (numberControls > 0 && !singleNumberRow);

        CGFloat baseH = compact ? 42.0 : 52.0;
        CGFloat rowH = compact ? 31.0 : 39.0;
        CGFloat height = baseH + exposed * rowH;
        if (fixedOnly || zeroArgument) height = compact ? 46.0 : 62.0;

        UIView *card = [self cardAtY:y height:height width:width compact:compact];
        card.tag = kZNM584CardTag + (NSInteger)i;
        card.layer.cornerRadius = compact ? 9.0 : 12.0;

        CGFloat left = compact ? 10.0 : 14.0;
        CGFloat top = compact ? 6.0 : 8.0;
        CGFloat executeW = compact ? 56.0 : 66.0;
        CGFloat rightReserve = headerExecute ? executeW + 20.0 : 14.0;

        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:(compact ? 10.4 : 11.5)
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(left, top, MAX(80.0, card.bounds.size.width - left - rightReserve), 20.0);
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:name];

        NSString *summary = nil;
        if (fixedOnly || zeroArgument) {
            summary = ZNM584FixedSummary(record, storedValues);
        } else if (record.argumentCount == 1) {
            NSString *type = record.parameterTypeNames.count ? ZNM584ShortType(record.parameterTypeNames.firstObject) : @"?";
            summary = [NSString stringWithFormat:@"参数 1 · %@", type];
        } else {
            summary = [NSString stringWithFormat:@"%lu 个参数", (unsigned long)record.argumentCount];
        }
        UILabel *subtitle = [self label:summary ?: @"" size:(compact ? 7.7 : 8.5) weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        subtitle.frame = CGRectMake(left, top + 22.0, MAX(80.0, card.bounds.size.width - left - rightReserve), 17.0);
        subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:subtitle];

        if (headerExecute) {
            UIButton *execute = [UIButton buttonWithType:UIButtonTypeSystem];
            execute.frame = CGRectMake(card.bounds.size.width - executeW - 12.0, compact ? 8.0 : 13.0, executeW, compact ? 29.0 : 34.0);
            execute.tag = kZNM584ExecTag + (NSInteger)i;
            [execute setTitle:@"执行" forState:UIControlStateNormal];
            [execute setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
            execute.titleLabel.font = [self menuFont:(compact ? 9.0 : 10.0) weight:UIFontWeightSemibold];
            execute.backgroundColor = self.theme.controlColor;
            execute.layer.cornerRadius = 9.0;
            execute.layer.borderWidth = 1.0;
            execute.layer.borderColor = self.theme.borderColor.CGColor;
            [execute addTarget:self action:@selector(znm58_execute:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:execute];
        }

        CGFloat rowY = baseH;
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            NSDictionary *cfg = configs.count ? configs[arg] : nil;
            if (![cfg[@"enabled"] boolValue]) continue;

            NSString *defaultValue = ZNM584DefaultValue(record, storedValues, arg);
            NSString *typeName = arg < record.parameterTypeNames.count ? ZNM584ShortType(record.parameterTypeNames[arg]) : @"?";
            ZNRuntimeArgumentControlType controlType = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
            NSInteger slot = (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);

            CGFloat labelW = compact ? 68.0 : 78.0;
            UILabel *argLabel = [self label:[NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, typeName]
                                          size:(compact ? 7.4 : 8.0)
                                        weight:UIFontWeightMedium
                                         color:self.theme.secondaryTextColor];
            argLabel.frame = CGRectMake(left, rowY + 3.0, labelW, rowH - 7.0);
            argLabel.adjustsFontSizeToFitWidth = YES;
            argLabel.minimumScaleFactor = 0.72;
            [card addSubview:argLabel];

            CGFloat controlX = left + labelW + 5.0;
            CGFloat right = 12.0;
            CGFloat available = MAX(60.0, card.bounds.size.width - controlX - right);

            if (controlType == ZNRuntimeArgumentControlTypeSlider) {
                double min = [cfg[@"min"] doubleValue];
                double max = [cfg[@"max"] doubleValue];
                if (!isfinite(min)) min = 0.0;
                if (!isfinite(max) || max <= min) max = min + 10.0;

                CGFloat valueW = compact ? 42.0 : 50.0;
                CGFloat gap = 7.0;
                CGFloat sliderW = MAX(62.0, available - valueW - gap);
                ZNRangeControl *control = [[ZNRangeControl alloc] initWithFrame:CGRectMake(controlX, rowY + 2.0, sliderW, rowH - 5.0)];
                control.minimumValue = min;
                control.maximumValue = max;
                control.value = ZNM584Quantize(defaultValue.doubleValue, cfg, min, max);
                control.minimumTrackTintColor = self.theme.accentColor;
                control.maximumTrackTintColor = [self.theme.trackColor colorWithAlphaComponent:.78];
                control.thumbTintColor = self.theme.primaryTextColor;
                control.tag = kZNM584SliderTag + slot;
                [control addTarget:self action:@selector(znm58_sliderChanged:) forControlEvents:UIControlEventValueChanged];
                [control addTarget:self action:@selector(znm58_sliderCommitted:) forControlEvents:UIControlEventPrimaryActionTriggered];
                [card addSubview:control];

                UILabel *value = [self label:ZNM584ValueText(control.value, cfg)
                                           size:(compact ? 8.0 : 8.8)
                                         weight:UIFontWeightSemibold
                                          color:self.theme.primaryTextColor];
                value.textAlignment = NSTextAlignmentCenter;
                value.font = [UIFont monospacedDigitSystemFontOfSize:(compact ? 8.0 : 8.8) weight:UIFontWeightSemibold];
                value.backgroundColor = self.theme.controlColor;
                value.layer.cornerRadius = 7.0;
                value.layer.masksToBounds = YES;
                value.layer.borderWidth = 1.0;
                value.layer.borderColor = self.theme.borderColor.CGColor;
                value.frame = CGRectMake(CGRectGetMaxX(control.frame) + gap, rowY + 5.0, valueW, rowH - 11.0);
                value.tag = kZNM584ValueTag + slot;
                [card addSubview:value];
            } else if (controlType == ZNRuntimeArgumentControlTypeSwitch) {
                UISwitch *control = [[UISwitch alloc] initWithFrame:CGRectZero];
                control.on = defaultValue.boolValue || [defaultValue.lowercaseString isEqualToString:@"true"];
                control.onTintColor = self.theme.accentColor;
                control.tintColor = self.theme.trackColor;
                control.tag = kZNM584SwitchTag + slot;
                [control addTarget:self action:@selector(znm58_switchChanged:) forControlEvents:UIControlEventValueChanged];
                control.center = CGPointMake(card.bounds.size.width - right - control.bounds.size.width * 0.5, rowY + rowH * 0.5);
                [card addSubview:control];
            } else if (controlType == ZNRuntimeArgumentControlTypeButton) {
                UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
                button.frame = CGRectMake(card.bounds.size.width - 70.0, rowY + 4.0, 58.0, rowH - 8.0);
                button.tag = kZNM584ExecTag + (NSInteger)i;
                [button setTitle:@"触发" forState:UIControlStateNormal];
                [button setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
                button.titleLabel.font = [self menuFont:9.3 weight:UIFontWeightSemibold];
                button.backgroundColor = self.theme.controlColor;
                button.layer.cornerRadius = 8.0;
                button.layer.borderWidth = 1.0;
                button.layer.borderColor = self.theme.borderColor.CGColor;
                [button addTarget:self action:@selector(znm58_execute:) forControlEvents:UIControlEventTouchUpInside];
                [card addSubview:button];
            } else {
                CGFloat executeRowW = singleNumberRow ? (compact ? 56.0 : 66.0) : 0.0;
                CGFloat rowGap = singleNumberRow ? 7.0 : 0.0;
                CGFloat fieldW = MAX(62.0, available - executeRowW - rowGap);
                UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(controlX, rowY + 4.0, fieldW, rowH - 8.0)];
                field.text = defaultValue;
                field.placeholder = @"数值";
                field.textColor = self.theme.primaryTextColor;
                field.backgroundColor = self.theme.controlColor;
                field.layer.cornerRadius = 8.0;
                field.layer.borderWidth = 1.0;
                field.layer.borderColor = self.theme.borderColor.CGColor;
                field.font = [UIFont monospacedDigitSystemFontOfSize:(compact ? 8.8 : 9.5) weight:UIFontWeightMedium];
                field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                field.returnKeyType = UIReturnKeyDone;
                field.tag = kZNM584FieldTag + slot;
                UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
                field.leftView = pad;
                field.leftViewMode = UITextFieldViewModeAlways;
                [field addTarget:self action:@selector(znm58_numberChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm58_numberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];

                if (singleNumberRow) {
                    UIButton *execute = [UIButton buttonWithType:UIButtonTypeSystem];
                    execute.frame = CGRectMake(CGRectGetMaxX(field.frame) + rowGap, rowY + 4.0, executeRowW, rowH - 8.0);
                    execute.tag = kZNM584ExecTag + (NSInteger)i;
                    [execute setTitle:@"执行" forState:UIControlStateNormal];
                    [execute setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
                    execute.titleLabel.font = [self menuFont:(compact ? 9.0 : 9.8) weight:UIFontWeightSemibold];
                    execute.backgroundColor = self.theme.controlColor;
                    execute.layer.cornerRadius = 8.0;
                    execute.layer.borderWidth = 1.0;
                    execute.layer.borderColor = self.theme.borderColor.CGColor;
                    [execute addTarget:self action:@selector(znm58_execute:) forControlEvents:UIControlEventTouchUpInside];
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

extern "C" void ZNInstallM584SchemeALayoutDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method layoutPanel = class_getInstanceMethod(cls, @selector(layoutPanel));
        Method schemePanel = class_getInstanceMethod(cls, @selector(znm584_layoutPanel));
        if (layoutPanel && schemePanel) method_setImplementation(layoutPanel, method_getImplementation(schemePanel));

        Method layoutSidebar = class_getInstanceMethod(cls, @selector(layoutSidebar));
        Method schemeSidebar = class_getInstanceMethod(cls, @selector(znm584_layoutSidebar));
        if (layoutSidebar && schemeSidebar) method_setImplementation(layoutSidebar, method_getImplementation(schemeSidebar));

        Method runtime = class_getInstanceMethod(cls, @selector(zn51_renderRuntime:));
        Method schemeRuntime = class_getInstanceMethod(cls, @selector(znm584_renderRuntime:));
        if (runtime && schemeRuntime) method_setImplementation(runtime, method_getImplementation(schemeRuntime));

        [[ZNRuntimeLogger sharedLogger] log:@"[m5.8.4-layout] Scheme A installed in-place: narrow sidebar + compact header + aligned action cards; single runtime renderer preserved"];
    });
}
