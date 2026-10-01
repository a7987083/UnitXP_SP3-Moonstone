#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNFeaturePageModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNRangeControl.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M5.10 canonical Feature page.
// Static Offset has exactly one customer control: Switch.
// Number/Slider/Button controls below are Runtime Method / IL2CPP only.
// ZN_UI_CANONICAL_FEATURE_RENDERER
// render path has no discovery refresh

static const NSInteger kZNFRControlTagBase = 980000;
static const NSInteger kZNFRExecTagBase = 982000;
static const NSInteger kZNFRRuntimeSlotBase = 984000;
static const NSInteger kZNFRRuntimeValueBase = 986000;
static NSString * const kZNFRRuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

@interface ZNStaticPatchRecord (ZNFeaturePagePrivate)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,assign) uint32_t patchID;
@property(nonatomic,assign,getter=isEnabled) BOOL enabled;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
- (void)zn51_renderRuntime:(BOOL)compact;
@end

static NSString *ZNFRTrim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNFRStaticIdentity(NSDictionary *meta, ZNStaticPatchRecord *record) {
    uint64_t featureID = [meta[@"featureID"] unsignedLongLongValue];
    if (featureID) return [NSString stringWithFormat:@"static:%016llx", featureID];
    NSString *group = ZNFRTrim(meta[@"group"]);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame)
        return [@"static:group:" stringByAppendingString:group.lowercaseString];
    return [NSString stringWithFormat:@"static:%@:%u", record.target.lowercaseString ?: @"", record.patchID];
}

static NSDictionary *ZNFRStaticMeta(ZNStaticPatchRecord *record) {
    NSDictionary *decoded = record.entry ? ZNFeatureMetadataDecodeEntry(record.entry) : nil;
    NSString *title = ZNFRTrim(decoded[@"title"] ?: record.title);
    NSString *group = ZNFRTrim(decoded[@"group"] ?: record.group);
    if (!title.length || [title hasPrefix:@"Patch #"]) title = [NSString stringWithFormat:@"功能 #%u", record.patchID];
    if (!group.length) group = @"Imported";
    return @{
        @"featureID": decoded[@"featureID"] ?: @0,
        @"title": title ?: @"功能",
        @"group": group,
        @"explicitGroup": @([decoded[@"explicitGroup"] boolValue] || [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame),
        @"description": ZNFRTrim(decoded[@"description"]),
        @"controlType": @(ZNFeatureControlTypeSwitch),
        @"valueType": @(ZNValueTypeAuto)
    };
}

static NSArray<ZNFeaturePageItem *> *ZNFRBuildStaticItems(void) {
    NSArray<ZNStaticPatchRecord *> *records = [ZNStaticDispatchRuntime sharedRuntime].records ?: @[];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNStaticPatchRecord *> *> *members = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *metas = [NSMutableDictionary dictionary];
    for (ZNStaticPatchRecord *record in records) {
        NSDictionary *meta = ZNFRStaticMeta(record);
        NSString *key = ZNFRStaticIdentity(meta, record);
        if (!members[key]) { members[key] = [NSMutableArray array]; metas[key] = meta; [order addObject:key]; }
        [members[key] addObject:record];
    }
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        NSDictionary *meta = metas[key] ?: @{};
        NSString *group = ZNFRTrim(meta[@"group"]), *title = ZNFRTrim(meta[@"title"]);
        BOOL explicitGroup = [meta[@"explicitGroup"] boolValue];
        ZNFeaturePageItem *item = [ZNFeaturePageItem new];
        item.identifier = key;
        item.title = explicitGroup && group.length ? group : (title.length ? title : @"功能");
        item.descriptionText = ZNFRTrim(meta[@"description"]);
        item.source = ZNFeaturePageSourceStaticOffset;
        item.controlType = ZNFeatureControlTypeSwitch;
        item.valueType = ZNValueTypeAuto;
        item.minimumValue = 0.0;
        item.maximumValue = 0.0;
        item.step = 1.0;
        item.currentValueText = @"";
        item.backingRecord = @{
            @"records": [members[key] copy] ?: @[],
            @"featureID": meta[@"featureID"] ?: @0,
            @"key": key
        };
        [items addObject:item];
    }
    return items;
}

static ZNFeatureControlType ZNFRRuntimePrimaryType(ZNRuntimeMethodActionRecord *record) {
    if (record.argumentCount == 0 || record.argumentControlConfigs.count != record.argumentCount) return ZNFeatureControlTypeButton;
    for (NSDictionary *cfg in record.argumentControlConfigs) {
        if (![cfg[@"enabled"] boolValue]) continue;
        switch (ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"])) {
            case ZNRuntimeArgumentControlTypeSwitch: return ZNFeatureControlTypeSwitch;
            case ZNRuntimeArgumentControlTypeSlider: return ZNFeatureControlTypeSlider;
            case ZNRuntimeArgumentControlTypeButton: return ZNFeatureControlTypeButton;
            case ZNRuntimeArgumentControlTypeNumber: return ZNFeatureControlTypeNumber;
            default: break;
        }
    }
    return ZNFeatureControlTypeButton;
}

static NSArray<ZNFeaturePageItem *> *ZNFRBuildRuntimeItems(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (ZNRuntimeMethodActionRecord *record in [ZNRuntimeActionRuntime sharedRuntime].records ?: @[]) {
        ZNFeaturePageItem *item = [ZNFeaturePageItem new];
        item.identifier = [NSString stringWithFormat:@"runtime:%u:%@", record.actionID, record.canonicalIdentity ?: @""];
        item.title = record.title.length ? record.title : record.methodName;
        item.descriptionText = ZNFRTrim(record.descriptionText);
        item.source = ZNFeaturePageSourceRuntimeIL2CPP;
        item.controlType = ZNFRRuntimePrimaryType(record);
        item.valueType = ZNValueTypeAuto;
        item.minimumValue = 0.0; item.maximumValue = 10.0; item.step = 1.0;
        item.currentValueText = record.argumentValues.count ? record.argumentValues.firstObject : @"";
        item.backingRecord = record;
        [items addObject:item];
    }
    return items;
}

static void ZNFRPublishInitialSnapshot(void) {
    [[ZNRuntimeActionRuntime sharedRuntime] refresh];
    [[ZNFeaturePageModel sharedModel] publishStaticItems:ZNFRBuildStaticItems()];
    [[ZNFeaturePageModel sharedModel] publishRuntimeItems:ZNFRBuildRuntimeItems()];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-page] snapshot published generation=%lu items=%lu staticOffset=SwitchOnly",
        (unsigned long)[ZNFeaturePageModel sharedModel].generation,
        (unsigned long)[ZNFeaturePageModel sharedModel].items.count]];
}

static BOOL ZNFRStaticAllEnabled(NSArray<ZNStaticPatchRecord *> *records) {
    if (!records.count) return NO;
    for (ZNStaticPatchRecord *record in records) if (!record.enabled) return NO;
    return YES;
}

static NSString *ZNFRRuntimeRecordKey(ZNRuntimeMethodActionRecord *record) {
    return [NSString stringWithFormat:@"%u|%@", record.actionID, record.canonicalIdentity ?: @""];
}
static NSArray<NSString *> *ZNFRRuntimeStoredValues(ZNRuntimeMethodActionRecord *record) {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults objectForKey:kZNFRRuntimeValuesKey];
    NSArray *values = [root isKindOfClass:NSDictionary.class] ? root[ZNFRRuntimeRecordKey(record)] : nil;
    return [values isKindOfClass:NSArray.class] && values.count == record.argumentCount ? values : nil;
}
static void ZNFRRuntimeStoreValues(ZNRuntimeMethodActionRecord *record, NSArray<NSString *> *values) {
    NSDictionary *old = [NSUserDefaults.standardUserDefaults objectForKey:kZNFRRuntimeValuesKey];
    NSMutableDictionary *root = [old isKindOfClass:NSDictionary.class] ? [old mutableCopy] : [NSMutableDictionary dictionary];
    root[ZNFRRuntimeRecordKey(record)] = values ?: @[];
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNFRRuntimeValuesKey];
}
static double ZNFRQuantize(double value, NSDictionary *cfg, double lo, double hi) {
    double step = [cfg[@"step"] doubleValue]; if (!isfinite(step) || step <= 0) step = 1;
    value = MAX(lo, MIN(hi, value));
    return MAX(lo, MIN(hi, lo + round((value - lo) / step) * step));
}

@interface ZNRuntimeMenuControllerV040 (ZNCanonicalFeaturePage)
- (void)znfr_renderFull;
- (void)znfr_renderCompact;
- (void)znfr_legacyRuntimeNoop:(BOOL)compact;
- (void)znfr_staticToggle:(UISwitch *)sender;
- (void)znfr_runtimeExecute:(UIButton *)sender;
- (void)znfr_runtimeSwitch:(UISwitch *)sender;
- (void)znfr_runtimeSliderChanged:(ZNRangeControl *)slider;
- (void)znfr_runtimeSliderCommit:(ZNRangeControl *)slider;
- (void)znfr_runtimeNumberReturn:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNCanonicalFeaturePage)

- (void)znfr_render:(BOOL)compact {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSArray<ZNFeaturePageItem *> *items = [ZNFeaturePageModel sharedModel].items ?: @[];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = compact ? 7.0 : 9.0;
    if (!items.count) {
        UIView *card = [self cardAtY:y height:(compact ? 40 : 46) width:width compact:compact];
        UILabel *label = [self label:@"暂无功能" size:(compact ? 10.7 : 11.0) weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(compact ? 9 : 13, compact ? 10 : 13, card.bounds.size.width - (compact ? 18 : 26), 20);
        [card addSubview:label]; [self.contentView addSubview:card];
        [self zn40_updateContentHeight:y + (compact ? 46 : 54)];
        return;
    }

    for (NSUInteger index = 0; index < items.count; index++) {
        ZNFeaturePageItem *item = items[index];
        if (item.source == ZNFeaturePageSourceRuntimeIL2CPP) {
            ZNRuntimeMethodActionRecord *record = [item.backingRecord isKindOfClass:ZNRuntimeMethodActionRecord.class] ? item.backingRecord : nil;
            if (!record) continue;
            NSArray *configs = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs : @[];
            NSUInteger exposed = 0; for (NSDictionary *cfg in configs) if ([cfg[@"enabled"] boolValue]) exposed++;
            BOOL hasDescription = ZNFRTrim(item.descriptionText).length > 0;
            CGFloat rowH = compact ? 31.0 : 36.0;
            CGFloat baseH = hasDescription ? (compact ? 42.0 : 46.0) : (compact ? 28.0 : 32.0);
            CGFloat h = baseH + exposed * rowH;
            if (!exposed) h = hasDescription ? (compact ? 46.0 : 52.0) : (compact ? 40.0 : 46.0);
            UIView *card = [self cardAtY:y height:h width:width compact:compact];
            UILabel *name = [self label:item.title size:(compact ? 10.4 : 11.3) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            name.frame = CGRectMake(compact ? 9 : 13, 5, card.bounds.size.width - 94, 20); name.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:name];
            if (hasDescription) {
                UILabel *description = [self label:item.descriptionText size:(compact ? 7.8 : 8.4) weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
                description.frame = CGRectMake(compact ? 9 : 13, 24, card.bounds.size.width - 94, 16); description.numberOfLines = 1; description.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:description];
            }
            if (!exposed) {
                UIButton *button = [self zn40_button:@"执行" selector:@selector(znfr_runtimeExecute:) frame:CGRectMake(card.bounds.size.width - 70, (h - 29) * 0.5, 58, 29)];
                button.tag = kZNFRExecTagBase + (NSInteger)index; [card addSubview:button];
            }
            NSArray *stored = ZNFRRuntimeStoredValues(record);
            CGFloat rowY = baseH;
            for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
                NSDictionary *cfg = configs.count ? configs[arg] : nil;
                if (![cfg[@"enabled"] boolValue]) continue;
                NSInteger slot = (NSInteger)(index * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
                NSString *fallback = stored.count == record.argumentCount ? stored[arg] : (arg < record.argumentValues.count ? record.argumentValues[arg] : @"");
                ZNRuntimeArgumentControlType type = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
                CGFloat left = compact ? 9 : 13, avail = card.bounds.size.width - left - 12;
                if (type == ZNRuntimeArgumentControlTypeSwitch) {
                    UISwitch *control = [UISwitch new]; control.on = fallback.boolValue || [fallback.lowercaseString isEqualToString:@"true"];
                    control.tag = kZNFRRuntimeSlotBase + slot; [control addTarget:self action:@selector(znfr_runtimeSwitch:) forControlEvents:UIControlEventValueChanged];
                    control.center = CGPointMake(card.bounds.size.width - 38, rowY + rowH * 0.5); [card addSubview:control];
                } else if (type == ZNRuntimeArgumentControlTypeSlider) {
                    double lo = [cfg[@"min"] doubleValue], hi = [cfg[@"max"] doubleValue];
                    if (!isfinite(lo)) lo = 0; if (!isfinite(hi) || hi <= lo) hi = lo + 10;
                    CGFloat valueW = 42, gap = 5, sliderW = MAX(60.0, avail - valueW - gap);
                    ZNRangeControl *control = [[ZNRangeControl alloc] initWithFrame:CGRectMake(left, rowY + 2, sliderW, rowH - 4)];
                    control.minimumValue = lo; control.maximumValue = hi; control.value = ZNFRQuantize(fallback.doubleValue, cfg, lo, hi); control.tag = kZNFRRuntimeSlotBase + slot;
                    [control addTarget:self action:@selector(znfr_runtimeSliderChanged:) forControlEvents:UIControlEventValueChanged];
                    [control addTarget:self action:@selector(znfr_runtimeSliderCommit:) forControlEvents:UIControlEventPrimaryActionTriggered]; [card addSubview:control];
                    UILabel *value = [self label:[NSString stringWithFormat:@"%.6g", control.value] size:8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
                    value.textAlignment = NSTextAlignmentRight; value.frame = CGRectMake(CGRectGetMaxX(control.frame) + gap, rowY, valueW, rowH); value.tag = kZNFRRuntimeValueBase + slot; [card addSubview:value];
                } else if (type == ZNRuntimeArgumentControlTypeButton) {
                    UIButton *button = [self zn40_button:@"触发" selector:@selector(znfr_runtimeExecute:) frame:CGRectMake(card.bounds.size.width - 70, rowY + 3, 58, rowH - 6)];
                    button.tag = kZNFRExecTagBase + (NSInteger)index; [card addSubview:button];
                } else {
                    CGFloat execW = 58, gap = 5;
                    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(left, rowY + 3, MAX(55.0, avail - execW - gap), rowH - 6)];
                    field.text = fallback; field.keyboardType = UIKeyboardTypeNumbersAndPunctuation; field.returnKeyType = UIReturnKeyDone;
                    field.textColor = self.theme.primaryTextColor; field.backgroundColor = self.theme.controlColor; field.layer.cornerRadius = 7; field.layer.borderWidth = 1; field.layer.borderColor = self.theme.borderColor.CGColor;
                    field.tag = kZNFRRuntimeSlotBase + slot; [field addTarget:self action:@selector(znfr_runtimeNumberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit]; [card addSubview:field];
                    UIButton *button = [self zn40_button:@"执行" selector:@selector(znfr_runtimeExecute:) frame:CGRectMake(CGRectGetMaxX(field.frame) + gap, rowY + 3, execW, rowH - 6)];
                    button.tag = kZNFRExecTagBase + (NSInteger)index; [card addSubview:button];
                }
                rowY += rowH;
            }
            [self.contentView addSubview:card]; y += h + (compact ? 7 : 9);
            continue;
        }

        NSDictionary *back = [item.backingRecord isKindOfClass:NSDictionary.class] ? item.backingRecord : @{};
        NSArray<ZNStaticPatchRecord *> *records = back[@"records"] ?: @[];
        BOOL hasDescription = ZNFRTrim(item.descriptionText).length > 0;
        CGFloat h = hasDescription ? (compact ? 52 : 58) : (compact ? 40 : 46);
        UIView *card = [self cardAtY:y height:h width:width compact:compact];
        UILabel *name = [self label:item.title size:(compact ? 10.7 : 11.4) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(compact ? 9 : 13, hasDescription ? (compact ? 5 : 7) : (compact ? 10 : 13), card.bounds.size.width - 96, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:name];
        if (hasDescription) {
            UILabel *description = [self label:item.descriptionText size:(compact ? 7.8 : 8.4) weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            description.frame = CGRectMake(compact ? 9 : 13, compact ? 25 : 28, card.bounds.size.width - 96, 16); description.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:description];
        }
        UISwitch *control = [UISwitch new]; control.on = ZNFRStaticAllEnabled(records); control.tag = kZNFRControlTagBase + (NSInteger)index;
        [control addTarget:self action:@selector(znfr_staticToggle:) forControlEvents:UIControlEventValueChanged]; control.center = CGPointMake(card.bounds.size.width - 38, h * 0.5); [card addSubview:control];
        [self.contentView addSubview:card]; y += h + (compact ? 6 : 7);
    }
    [self zn40_updateContentHeight:y];
}

- (void)znfr_renderFull { [self znfr_render:NO]; }
- (void)znfr_renderCompact { [self znfr_render:YES]; }
- (void)znfr_legacyRuntimeNoop:(BOOL)compact { (void)compact; }

- (ZNFeaturePageItem *)znfr_itemForTag:(NSInteger)tag base:(NSInteger)base {
    NSInteger index = tag - base; NSArray<ZNFeaturePageItem *> *items = [ZNFeaturePageModel sharedModel].items;
    return index >= 0 && (NSUInteger)index < items.count ? items[(NSUInteger)index] : nil;
}

- (void)znfr_staticToggle:(UISwitch *)sender {
    ZNFeaturePageItem *item = [self znfr_itemForTag:sender.tag base:kZNFRControlTagBase];
    NSDictionary *back = [item.backingRecord isKindOfClass:NSDictionary.class] ? item.backingRecord : @{};
    NSArray<ZNStaticPatchRecord *> *records = back[@"records"] ?: @[];
    BOOL desired = sender.on; NSMutableArray *changed = [NSMutableArray array];
    for (ZNStaticPatchRecord *record in records) {
        if (record.enabled == desired) continue;
        NSString *error = nil;
        if (![[ZNStaticDispatchRuntime sharedRuntime] setEnabled:desired forRecord:record error:&error]) {
            for (ZNStaticPatchRecord *rollback in changed) [[ZNStaticDispatchRuntime sharedRuntime] setEnabled:!desired forRecord:rollback error:NULL];
            sender.on = !desired;
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-page] static toggle rollback %@", error ?: @"unknown"]];
            return;
        }
        [changed addObject:record];
    }
    uint64_t featureID = [back[@"featureID"] unsignedLongLongValue];
    if (featureID) [NSUserDefaults.standardUserDefaults setBool:desired forKey:[NSString stringWithFormat:@"zn.f.%016llx.enabled", featureID]];
}

- (NSMutableArray<NSString *> *)znfr_runtimeValuesForIndex:(NSUInteger)index record:(ZNRuntimeMethodActionRecord *)record {
    NSArray *stored = ZNFRRuntimeStoredValues(record);
    NSMutableArray *values = [NSMutableArray arrayWithArray:(stored ?: record.argumentValues ?: @[])];
    while (values.count < record.argumentCount) [values addObject:@""];
    for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
        NSDictionary *cfg = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs[arg] : nil;
        if (![cfg[@"enabled"] boolValue]) continue;
        NSInteger slot = (NSInteger)(index * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
        UIView *view = [self.contentView viewWithTag:kZNFRRuntimeSlotBase + slot];
        ZNRuntimeArgumentControlType type = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
        if (type == ZNRuntimeArgumentControlTypeSwitch && [view isKindOfClass:UISwitch.class]) values[arg] = ((UISwitch *)view).on ? @"true" : @"false";
        else if (type == ZNRuntimeArgumentControlTypeSlider && [view isKindOfClass:ZNRangeControl.class]) {
            ZNRangeControl *slider = (ZNRangeControl *)view;
            values[arg] = [NSString stringWithFormat:@"%.17g", ZNFRQuantize(slider.value, cfg, slider.minimumValue, slider.maximumValue)];
        } else if (type == ZNRuntimeArgumentControlTypeNumber && [view isKindOfClass:UITextField.class]) values[arg] = ((UITextField *)view).text ?: @"";
    }
    return values;
}

- (void)znfr_runtimeExecute:(UIButton *)sender {
    NSInteger index = sender.tag - kZNFRExecTagBase; NSArray<ZNFeaturePageItem *> *items = [ZNFeaturePageModel sharedModel].items;
    if (index < 0 || (NSUInteger)index >= items.count) return;
    ZNRuntimeMethodActionRecord *record = [items[(NSUInteger)index].backingRecord isKindOfClass:ZNRuntimeMethodActionRecord.class] ? items[(NSUInteger)index].backingRecord : nil;
    if (!record) return;
    NSMutableArray *values = [self znfr_runtimeValuesForIndex:(NSUInteger)index record:record]; ZNFRRuntimeStoreValues(record, values);
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.actionID = record.actionID; action.title = record.title; action.descriptionText = record.descriptionText; action.group = record.group;
    action.assembly = record.assembly; action.namespaceName = record.namespaceName; action.className = record.className; action.methodName = record.methodName;
    action.argumentCount = record.argumentCount; action.argumentValues = values; action.parameterTypeNames = record.parameterTypeNames;
    action.signatureAvailable = record.signatureAvailable; action.argumentControlConfigs = record.argumentControlConfigs; action.immediateChain = record.immediateChain;
    NSString *error = nil; NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    if (!result) [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-page] runtime execute failed %@", error ?: @"unknown"]];
}

- (void)znfr_runtimeSwitch:(UISwitch *)sender {
    NSInteger slot = sender.tag - kZNFRRuntimeSlotBase; if (slot < 0) return;
    UIButton *button = [UIButton new]; button.tag = kZNFRExecTagBase + (NSInteger)((NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS); [self znfr_runtimeExecute:button];
}
- (void)znfr_runtimeSliderChanged:(ZNRangeControl *)slider {
    NSInteger slot = slider.tag - kZNFRRuntimeSlotBase; if (slot < 0) return;
    NSUInteger index = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS, arg = (NSUInteger)slot % ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    NSArray<ZNFeaturePageItem *> *items = [ZNFeaturePageModel sharedModel].items; if (index >= items.count) return;
    ZNRuntimeMethodActionRecord *record = [items[index].backingRecord isKindOfClass:ZNRuntimeMethodActionRecord.class] ? items[index].backingRecord : nil;
    if (!record || record.argumentControlConfigs.count != record.argumentCount || arg >= record.argumentCount) return;
    NSDictionary *cfg = record.argumentControlConfigs[arg]; slider.value = ZNFRQuantize(slider.value, cfg, slider.minimumValue, slider.maximumValue);
    UIView *value = [self.contentView viewWithTag:kZNFRRuntimeValueBase + slot]; if ([value isKindOfClass:UILabel.class]) ((UILabel *)value).text = [NSString stringWithFormat:@"%.6g", slider.value];
}
- (void)znfr_runtimeSliderCommit:(ZNRangeControl *)slider {
    [self znfr_runtimeSliderChanged:slider]; NSInteger slot = slider.tag - kZNFRRuntimeSlotBase; if (slot < 0) return;
    UIButton *button = [UIButton new]; button.tag = kZNFRExecTagBase + (NSInteger)((NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS); [self znfr_runtimeExecute:button];
}
- (void)znfr_runtimeNumberReturn:(UITextField *)field { [field resignFirstResponder]; }

@end

extern "C" void ZNInstallCanonicalFeaturePageDeferred(void) {
    static BOOL snapshotReady = NO;
    if (!snapshotReady) { snapshotReady = YES; ZNFRPublishInitialSnapshot(); }
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040"); if (!cls) return;
    Method full = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsFull));
    Method compact = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsCompact));
    Method unifiedFull = class_getInstanceMethod(cls, @selector(znfr_renderFull));
    Method unifiedCompact = class_getInstanceMethod(cls, @selector(znfr_renderCompact));
    Method legacyRuntime = class_getInstanceMethod(cls, @selector(zn51_renderRuntime:));
    Method runtimeNoop = class_getInstanceMethod(cls, @selector(znfr_legacyRuntimeNoop:));
    if (full && unifiedFull) method_setImplementation(full, method_getImplementation(unifiedFull));
    if (compact && unifiedCompact) method_setImplementation(compact, method_getImplementation(unifiedCompact));
    if (legacyRuntime && runtimeNoop) method_setImplementation(legacyRuntime, method_getImplementation(runtimeNoop));
    [[ZNRuntimeLogger sharedLogger] log:@"[feature-page] canonical renderer bound: Runtime Method keeps typed controls; Static Offset is Switch-only"];
}
