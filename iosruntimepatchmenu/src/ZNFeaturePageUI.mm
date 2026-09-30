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

// Canonical customer Feature page renderer.
// ZN_UI_CANONICAL_FEATURE_RENDERER
// Runtime IL2CPP and Static/Offset keep separate backends; they merge only here,
// through ZNFeaturePageModel. Rendering never performs discovery refreshes.

static const NSInteger kZNFRControlTagBase = 980000;
static const NSInteger kZNFRExecTagBase = 982000;
static const NSInteger kZNFRRuntimeSlotBase = 984000;
static const NSInteger kZNFRRuntimeValueBase = 986000;
static NSString * const kZNFRRuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

@interface ZNStaticPatchRecord (ZNFeaturePagePrivate)
@property(nonatomic,assign) ZN44StaticEntry *entry;
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
- (void)renderPage;
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
    NSDictionary *m = record.entry ? ZNFeatureMetadataDecodeEntry(record.entry) : nil;
    if (m) return m;
    NSString *title = ZNFRTrim(record.title);
    NSString *group = ZNFRTrim(record.group);
    if (!title.length || [title hasPrefix:@"Patch #"]) title = [NSString stringWithFormat:@"功能 #%u", record.patchID];
    if (!group.length) group = @"Imported";
    return @{@"featureID":@0,
             @"title":title ?: @"功能",
             @"group":group,
             @"explicitGroup":@([group caseInsensitiveCompare:@"Imported"] != NSOrderedSame),
             @"description":@"",
             @"controlType":@(record.entry ? ZNFeatureControlTypeFromFlags(record.entry->flags) : ZNFeatureControlTypeSwitch),
             @"valueType":@(record.entry ? ZNFeatureValueTypeFromFlags(record.entry->flags) : ZNValueTypeAuto),
             @"sliderMax":@0};
}

static NSArray<ZNFeaturePageItem *> *ZNFRBuildStaticItems(void) {
    NSArray<ZNStaticPatchRecord *> *records = [ZNStaticDispatchRuntime sharedRuntime].records ?: @[];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *members = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *metas = [NSMutableDictionary dictionary];
    for (ZNStaticPatchRecord *record in records) {
        NSDictionary *meta = ZNFRStaticMeta(record);
        NSString *key = ZNFRStaticIdentity(meta, record);
        if (!members[key]) { members[key] = [NSMutableArray array]; metas[key] = meta; [order addObject:key]; }
        [members[key] addObject:record];
    }
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        NSDictionary *m = metas[key] ?: @{};
        NSArray *rs = [members[key] copy] ?: @[];
        NSString *group = ZNFRTrim(m[@"group"]), *title = ZNFRTrim(m[@"title"]);
        BOOL explicitGroup = [m[@"explicitGroup"] boolValue] || (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame);
        ZNFeaturePageItem *item = [ZNFeaturePageItem new];
        item.identifier = key;
        item.title = explicitGroup && group.length ? group : (title.length ? title : @"功能");
        item.descriptionText = ZNFRTrim(m[@"description"]);
        item.source = ZNFeaturePageSourceStaticOffset;
        item.controlType = (ZNFeatureControlType)[m[@"controlType"] unsignedIntegerValue];
        item.valueType = (ZNValueType)[m[@"valueType"] integerValue];
        item.minimumValue = 0.0;
        double max = [m[@"sliderMax"] doubleValue];
        item.maximumValue = isfinite(max) && max > 0 ? max : 10.0;
        item.step = 1.0;
        uint64_t fid = [m[@"featureID"] unsignedLongLongValue];
        NSString *identity = fid ? [NSString stringWithFormat:@"%016llx",fid] : key;
        NSString *valueTextKey = [NSString stringWithFormat:@"zn.fc.%@.valueText",identity ?: @"feature"];
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:valueTextKey];
        item.currentValueText = [stored isKindOfClass:NSString.class] ? stored : @"1";
        item.backingRecord = @{@"records":rs,@"featureID":@(fid),@"key":key};
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
        item.identifier = [NSString stringWithFormat:@"runtime:%u:%@",record.actionID,record.canonicalIdentity ?: @""];
        item.title = record.title.length ? record.title : record.methodName;
        item.descriptionText = @"";
        item.source = ZNFeaturePageSourceRuntimeIL2CPP;
        item.controlType = ZNFRRuntimePrimaryType(record);
        item.valueType = ZNValueTypeAuto;
        item.minimumValue = 0.0;
        item.maximumValue = 10.0;
        item.step = 1.0;
        item.currentValueText = record.argumentValues.count ? record.argumentValues.firstObject : @"";
        item.backingRecord = record;
        [items addObject:item];
    }
    return items;
}

static void ZNFRPublishInitialSnapshot(void) {
    // Static Dispatch discovery is completed by the deferred bootstrap before UI
    // installation. Runtime metadata is scanned exactly once here, never in render.
    [[ZNRuntimeActionRuntime sharedRuntime] refresh];
    [[ZNFeaturePageModel sharedModel] publishStaticItems:ZNFRBuildStaticItems()];
    [[ZNFeaturePageModel sharedModel] publishRuntimeItems:ZNFRBuildRuntimeItems()];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-page] snapshot published generation=%lu items=%lu",(unsigned long)[ZNFeaturePageModel sharedModel].generation,(unsigned long)[ZNFeaturePageModel sharedModel].items.count]];
}

static BOOL ZNFRStaticAllEnabled(NSArray<ZNStaticPatchRecord *> *records) {
    if (!records.count) return NO;
    for (ZNStaticPatchRecord *r in records) if (!r.enabled) return NO;
    return YES;
}

static NSString *ZNFRStaticPreferenceIdentity(ZNFeaturePageItem *item) {
    NSDictionary *back = [item.backingRecord isKindOfClass:NSDictionary.class] ? item.backingRecord : nil;
    uint64_t fid = [back[@"featureID"] unsignedLongLongValue];
    return fid ? [NSString stringWithFormat:@"%016llx",fid] : (back[@"key"] ?: item.identifier ?: @"feature");
}

static NSDictionary *ZNFRStaticEventInfo(ZNFeaturePageItem *item, NSNumber *value, NSString *text) {
    NSDictionary *back = [item.backingRecord isKindOfClass:NSDictionary.class] ? item.backingRecord : @{};
    NSMutableDictionary *d = [@{@"featureID":back[@"featureID"] ?: @0,
                                @"title":item.title ?: @"功能",
                                @"controlType":@(item.controlType),
                                @"valueType":@(item.valueType),
                                @"key":back[@"key"] ?: item.identifier ?: @""} mutableCopy];
    if (value) d[@"value"] = value;
    if (text.length) d[@"valueText"] = text;
    return d;
}

static NSString *ZNFRRuntimeRecordKey(ZNRuntimeMethodActionRecord *record) {
    return [NSString stringWithFormat:@"%u|%@",record.actionID,record.canonicalIdentity ?: @""];
}

static NSArray<NSString *> *ZNFRRuntimeStoredValues(ZNRuntimeMethodActionRecord *record) {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults objectForKey:kZNFRRuntimeValuesKey];
    NSArray *a = [root isKindOfClass:NSDictionary.class] ? root[ZNFRRuntimeRecordKey(record)] : nil;
    return [a isKindOfClass:NSArray.class] && a.count == record.argumentCount ? a : nil;
}

static void ZNFRRuntimeStoreValues(ZNRuntimeMethodActionRecord *record, NSArray<NSString *> *values) {
    NSDictionary *old = [NSUserDefaults.standardUserDefaults objectForKey:kZNFRRuntimeValuesKey];
    NSMutableDictionary *root = [old isKindOfClass:NSDictionary.class] ? [old mutableCopy] : [NSMutableDictionary dictionary];
    root[ZNFRRuntimeRecordKey(record)] = values ?: @[];
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNFRRuntimeValuesKey];
}

static double ZNFRQuantize(double v, NSDictionary *cfg, double lo, double hi) {
    double step = [cfg[@"step"] doubleValue]; if (!isfinite(step) || step <= 0) step = 1;
    v = MAX(lo,MIN(hi,v));
    return MAX(lo,MIN(hi,lo + round((v-lo)/step)*step));
}

@interface ZNRuntimeMenuControllerV040 (ZNCanonicalFeaturePage)
- (void)znfr_renderFull;
- (void)znfr_renderCompact;
- (void)znfr_legacyRuntimeNoop:(BOOL)compact;
- (void)znfr_staticToggle:(UISwitch *)sender;
- (void)znfr_staticNumberReturn:(UITextField *)field;
- (void)znfr_staticExecute:(UIButton *)sender;
- (void)znfr_staticSlider:(ZNRangeControl *)slider;
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
        UIView *card = [self cardAtY:y height:(compact?40:46) width:width compact:compact];
        UILabel *l = [self label:@"暂无功能" size:(compact?10.7:11.0) weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        l.frame = CGRectMake(compact?9:13,compact?10:13,card.bounds.size.width-(compact?18:26),20);
        [card addSubview:l]; [self.contentView addSubview:card];
        [self zn40_updateContentHeight:y+(compact?46:54)]; return;
    }

    for (NSUInteger index=0; index<items.count; index++) {
        ZNFeaturePageItem *item = items[index];
        if (item.source == ZNFeaturePageSourceRuntimeIL2CPP) {
            ZNRuntimeMethodActionRecord *record = [item.backingRecord isKindOfClass:ZNRuntimeMethodActionRecord.class] ? item.backingRecord : nil;
            if (!record) continue;
            NSArray *cfgs = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs : @[];
            NSUInteger exposed=0; for (NSDictionary *cfg in cfgs) if ([cfg[@"enabled"] boolValue]) exposed++;
            CGFloat baseH = compact ? 42.0 : 50.0, rowH = compact ? 31.0 : 36.0;
            CGFloat h = baseH + exposed*rowH;
            if (!exposed) h = compact ? 44.0 : 54.0;
            UIView *card = [self cardAtY:y height:h width:width compact:compact];
            UILabel *name = [self label:item.title size:(compact?10.4:11.3) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            name.frame = CGRectMake(compact?9:13,7,card.bounds.size.width-94,22); name.lineBreakMode=NSLineBreakByTruncatingTail; [card addSubview:name];
            UILabel *kind = [self label:@"Runtime" size:7.7 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
            kind.frame = CGRectMake(compact?9:13,27,70,15); [card addSubview:kind];
            if (!exposed) {
                UIButton *b=[self zn40_button:@"执行" selector:@selector(znfr_runtimeExecute:) frame:CGRectMake(card.bounds.size.width-70,compact?8:10,58,29)];
                b.tag=kZNFRExecTagBase+(NSInteger)index; [card addSubview:b];
            }
            NSArray *stored=ZNFRRuntimeStoredValues(record);
            CGFloat rowY=baseH;
            for (NSUInteger arg=0; arg<record.argumentCount; arg++) {
                NSDictionary *cfg = cfgs.count ? cfgs[arg] : nil; if (![cfg[@"enabled"] boolValue]) continue;
                NSInteger slot=(NSInteger)(index*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);
                NSString *fallback=(stored.count==record.argumentCount)?stored[arg]:(arg<record.argumentValues.count?record.argumentValues[arg]:@"");
                ZNRuntimeArgumentControlType type=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
                CGFloat left=compact?9:13, labelW=compact?62:72;
                UILabel *al=[self label:[NSString stringWithFormat:@"参数%lu",(unsigned long)arg+1] size:7.8 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
                al.frame=CGRectMake(left,rowY,labelW,rowH); [card addSubview:al];
                CGFloat x=left+labelW+4, avail=card.bounds.size.width-x-12;
                if (type==ZNRuntimeArgumentControlTypeSwitch) {
                    UISwitch *sw=[UISwitch new]; sw.on=fallback.boolValue||[fallback.lowercaseString isEqualToString:@"true"]; sw.tag=kZNFRRuntimeSlotBase+slot; [sw addTarget:self action:@selector(znfr_runtimeSwitch:) forControlEvents:UIControlEventValueChanged]; sw.center=CGPointMake(card.bounds.size.width-38,rowY+rowH*0.5); [card addSubview:sw];
                } else if (type==ZNRuntimeArgumentControlTypeSlider) {
                    double lo=[cfg[@"min"] doubleValue], hi=[cfg[@"max"] doubleValue]; if(!isfinite(lo))lo=0;if(!isfinite(hi)||hi<=lo)hi=lo+10;
                    CGFloat valueW=42,gap=5,sliderW=MAX(60.0,avail-valueW-gap); ZNRangeControl *s=[[ZNRangeControl alloc]initWithFrame:CGRectMake(x,rowY+2,sliderW,rowH-4)]; s.minimumValue=lo;s.maximumValue=hi;s.value=ZNFRQuantize(fallback.doubleValue,cfg,lo,hi);s.tag=kZNFRRuntimeSlotBase+slot;[s addTarget:self action:@selector(znfr_runtimeSliderChanged:) forControlEvents:UIControlEventValueChanged];[s addTarget:self action:@selector(znfr_runtimeSliderCommit:) forControlEvents:UIControlEventPrimaryActionTriggered];[card addSubview:s]; UILabel *vl=[self label:[NSString stringWithFormat:@"%.6g",s.value] size:8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];vl.textAlignment=NSTextAlignmentRight;vl.frame=CGRectMake(CGRectGetMaxX(s.frame)+gap,rowY,valueW,rowH);vl.tag=kZNFRRuntimeValueBase+slot;[card addSubview:vl];
                } else if (type==ZNRuntimeArgumentControlTypeButton) {
                    UIButton *b=[self zn40_button:@"触发" selector:@selector(znfr_runtimeExecute:) frame:CGRectMake(card.bounds.size.width-70,rowY+3,58,rowH-6)];b.tag=kZNFRExecTagBase+(NSInteger)index;[card addSubview:b];
                } else {
                    CGFloat execW=58,gap=5; UITextField *f=[[UITextField alloc]initWithFrame:CGRectMake(x,rowY+3,MAX(55.0,avail-execW-gap),rowH-6)];f.text=fallback;f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;f.returnKeyType=UIReturnKeyDone;f.textColor=self.theme.primaryTextColor;f.backgroundColor=self.theme.controlColor;f.layer.cornerRadius=7;f.layer.borderWidth=1;f.layer.borderColor=self.theme.borderColor.CGColor;f.tag=kZNFRRuntimeSlotBase+slot;[f addTarget:self action:@selector(znfr_runtimeNumberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];[card addSubview:f];UIButton *b=[self zn40_button:@"执行" selector:@selector(znfr_runtimeExecute:) frame:CGRectMake(CGRectGetMaxX(f.frame)+gap,rowY+3,execW,rowH-6)];b.tag=kZNFRExecTagBase+(NSInteger)index;[card addSubview:b];
                }
                rowY += rowH;
            }
            [self.contentView addSubview:card]; y += h+(compact?7:9); continue;
        }

        NSDictionary *back=[item.backingRecord isKindOfClass:NSDictionary.class]?item.backingRecord:@{};
        NSArray<ZNStaticPatchRecord *> *records=back[@"records"] ?: @[];
        BOOL hasDescription = ZNFRTrim(item.descriptionText).length > 0;
        CGFloat h = hasDescription ? (compact ? 52 : 58) : (compact ? 40 : 46);
        UIView *card=[self cardAtY:y height:h width:width compact:compact];
        CGFloat textRightInset = item.controlType==ZNFeatureControlTypeNumber ? 150 : 96;
        UILabel *name=[self label:item.title size:(compact?10.7:11.4) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame=CGRectMake(compact?9:13,hasDescription?(compact?5:7):(compact?10:13),card.bounds.size.width-textRightInset,20);
        name.lineBreakMode=NSLineBreakByTruncatingTail;[card addSubview:name];
        if (hasDescription) {
            UILabel *description=[self label:item.descriptionText size:(compact?7.8:8.4) weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            description.frame=CGRectMake(compact?9:13,compact?25:28,card.bounds.size.width-textRightInset,16);
            description.lineBreakMode=NSLineBreakByTruncatingTail;
            description.numberOfLines=1;
            [card addSubview:description];
        }
        if(item.controlType==ZNFeatureControlTypeSwitch){UISwitch *sw=[UISwitch new];sw.on=ZNFRStaticAllEnabled(records);sw.tag=kZNFRControlTagBase+(NSInteger)index;[sw addTarget:self action:@selector(znfr_staticToggle:) forControlEvents:UIControlEventValueChanged];sw.center=CGPointMake(card.bounds.size.width-38,h*0.5);[card addSubview:sw];}
        else if(item.controlType==ZNFeatureControlTypeButton){UIButton*b=[self zn40_button:@"执行" selector:@selector(znfr_staticExecute:) frame:CGRectMake(card.bounds.size.width-70,(h-(compact?28:30))*0.5,58,compact?28:30)];b.tag=kZNFRExecTagBase+(NSInteger)index;[card addSubview:b];}
        else if(item.controlType==ZNFeatureControlTypeNumber){UITextField*f=[[UITextField alloc]initWithFrame:CGRectMake(card.bounds.size.width-(compact?126:142),(h-(compact?28:30))*0.5,compact?68:82,compact?28:30)];f.text=item.currentValueText;f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;f.returnKeyType=UIReturnKeyDone;f.textAlignment=NSTextAlignmentCenter;f.textColor=self.theme.primaryTextColor;f.backgroundColor=self.theme.controlColor;f.layer.cornerRadius=7;f.layer.borderWidth=1;f.layer.borderColor=self.theme.borderColor.CGColor;f.tag=kZNFRControlTagBase+(NSInteger)index;[f addTarget:self action:@selector(znfr_staticNumberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];[card addSubview:f];UIButton*b=[self zn40_button:@"执行" selector:@selector(znfr_staticExecute:) frame:CGRectMake(CGRectGetMaxX(f.frame)+4,(h-(compact?28:30))*0.5,compact?50:52,compact?28:30)];b.tag=kZNFRExecTagBase+(NSInteger)index;[card addSubview:b];}
        else {CGFloat sw=compact?92:112;ZNRangeControl*s=[[ZNRangeControl alloc]initWithFrame:CGRectMake(card.bounds.size.width-sw-10,(h-(compact?28:30))*0.5,sw,compact?28:30)];s.minimumValue=item.minimumValue;s.maximumValue=MAX(item.maximumValue,item.minimumValue+1);s.value=MAX(s.minimumValue,MIN(s.maximumValue,item.currentValueText.doubleValue));s.tag=kZNFRControlTagBase+(NSInteger)index;[s addTarget:self action:@selector(znfr_staticSlider:) forControlEvents:UIControlEventPrimaryActionTriggered];[card addSubview:s];}
        [self.contentView addSubview:card]; y += h+(compact?6:7);
    }
    [self zn40_updateContentHeight:y];
}

- (void)znfr_renderFull { [self znfr_render:NO]; }
- (void)znfr_renderCompact { [self znfr_render:YES]; }
- (void)znfr_legacyRuntimeNoop:(BOOL)compact { (void)compact; }

- (ZNFeaturePageItem *)znfr_itemForTag:(NSInteger)tag base:(NSInteger)base {NSInteger i=tag-base;NSArray<ZNFeaturePageItem *> *items=[ZNFeaturePageModel sharedModel].items;return(i>=0&&(NSUInteger)i<items.count)?items[(NSUInteger)i]:nil;}

- (void)znfr_staticToggle:(UISwitch *)sender {ZNFeaturePageItem*item=[self znfr_itemForTag:sender.tag base:kZNFRControlTagBase];NSDictionary*back=[item.backingRecord isKindOfClass:NSDictionary.class]?item.backingRecord:@{};NSArray*records=back[@"records"]?:@[];BOOL desired=sender.on;NSMutableArray*changed=[NSMutableArray array];for(ZNStaticPatchRecord*r in records){if(r.enabled==desired)continue;NSString*e=nil;if(![[ZNStaticDispatchRuntime sharedRuntime]setEnabled:desired forRecord:r error:&e]){for(ZNStaticPatchRecord*x in changed){NSString*ignore=nil;[[ZNStaticDispatchRuntime sharedRuntime]setEnabled:!desired forRecord:x error:&ignore];}sender.on=!desired;[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[feature-page] static toggle rollback %@",e?:@"unknown"]];return;}[changed addObject:r];}uint64_t fid=[back[@"featureID"]unsignedLongLongValue];if(fid)[NSUserDefaults.standardUserDefaults setBool:desired forKey:[NSString stringWithFormat:@"zn.f.%016llx.enabled",fid]];}
- (void)znfr_staticNumberReturn:(UITextField *)field {[field resignFirstResponder];}
- (void)znfr_staticExecute:(UIButton *)sender {ZNFeaturePageItem*item=[self znfr_itemForTag:sender.tag base:kZNFRExecTagBase];if(!item)return;NSString*text=item.currentValueText;if(item.controlType==ZNFeatureControlTypeNumber){UIView*v=[self.contentView viewWithTag:kZNFRControlTagBase+(sender.tag-kZNFRExecTagBase)];if([v isKindOfClass:UITextField.class])text=((UITextField*)v).text?:@"0";}NSString*identity=ZNFRStaticPreferenceIdentity(item);[NSUserDefaults.standardUserDefaults setObject:text?:@"0" forKey:[NSString stringWithFormat:@"zn.fc.%@.valueText",identity]];NSNotificationName n=item.controlType==ZNFeatureControlTypeButton?ZNFeatureActionRequestedNotification:ZNFeatureNumberValueDidChangeNotification;[NSNotificationCenter.defaultCenter postNotificationName:n object:self userInfo:ZNFRStaticEventInfo(item,item.controlType==ZNFeatureControlTypeButton?nil:@(text.doubleValue),text)];}
- (void)znfr_staticSlider:(ZNRangeControl *)slider {ZNFeaturePageItem*item=[self znfr_itemForTag:slider.tag base:kZNFRControlTagBase];if(!item)return;double v=round(slider.value);slider.value=v;NSString*text=[NSString stringWithFormat:@"%.0f",v];NSString*identity=ZNFRStaticPreferenceIdentity(item);[NSUserDefaults.standardUserDefaults setObject:text forKey:[NSString stringWithFormat:@"zn.fc.%@.valueText",identity]];[NSUserDefaults.standardUserDefaults setDouble:v forKey:[NSString stringWithFormat:@"zn.fc.%@.value",identity]];[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification object:self userInfo:ZNFRStaticEventInfo(item,@(v),text)];}

- (NSMutableArray<NSString *> *)znfr_runtimeValuesForIndex:(NSUInteger)index record:(ZNRuntimeMethodActionRecord *)record {NSArray*stored=ZNFRRuntimeStoredValues(record);NSMutableArray*values=[NSMutableArray arrayWithArray:(stored?:record.argumentValues?:@[])];while(values.count<record.argumentCount)[values addObject:@""];for(NSUInteger arg=0;arg<record.argumentCount;arg++){NSDictionary*cfg=(record.argumentControlConfigs.count==record.argumentCount)?record.argumentControlConfigs[arg]:nil;if(![cfg[@"enabled"]boolValue])continue;NSInteger slot=(NSInteger)(index*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);UIView*v=[self.contentView viewWithTag:kZNFRRuntimeSlotBase+slot];ZNRuntimeArgumentControlType type=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);if(type==ZNRuntimeArgumentControlTypeSwitch&&[v isKindOfClass:UISwitch.class])values[arg]=((UISwitch*)v).on?@"true":@"false";else if(type==ZNRuntimeArgumentControlTypeSlider&&[v isKindOfClass:ZNRangeControl.class]){ZNRangeControl*s=(ZNRangeControl*)v;values[arg]=[NSString stringWithFormat:@"%.17g",ZNFRQuantize(s.value,cfg,s.minimumValue,s.maximumValue)];}else if(type==ZNRuntimeArgumentControlTypeNumber&&[v isKindOfClass:UITextField.class])values[arg]=((UITextField*)v).text?:@"";}return values;}
- (void)znfr_runtimeExecute:(UIButton *)sender {NSInteger index=sender.tag-kZNFRExecTagBase;NSArray<ZNFeaturePageItem *> *items=[ZNFeaturePageModel sharedModel].items;if(index<0||(NSUInteger)index>=items.count)return;ZNFeaturePageItem*item=items[(NSUInteger)index];ZNRuntimeMethodActionRecord*r=[item.backingRecord isKindOfClass:ZNRuntimeMethodActionRecord.class]?item.backingRecord:nil;if(!r)return;NSMutableArray*values=[self znfr_runtimeValuesForIndex:(NSUInteger)index record:r];ZNFRRuntimeStoreValues(r,values);ZNRuntimeMethodAction*a=[ZNRuntimeMethodAction new];a.actionID=r.actionID;a.title=r.title;a.group=r.group;a.assembly=r.assembly;a.namespaceName=r.namespaceName;a.className=r.className;a.methodName=r.methodName;a.argumentCount=r.argumentCount;a.argumentValues=values;a.parameterTypeNames=r.parameterTypeNames;a.signatureAvailable=r.signatureAvailable;a.argumentControlConfigs=r.argumentControlConfigs;a.immediateChain=r.immediateChain;NSString*e=nil;NSDictionary*result=[[ZNIL2CPPInvokeEngine sharedEngine]executeAction:a error:&e];if(!result)[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[feature-page] runtime execute failed %@",e?:@"unknown"]];}
- (void)znfr_runtimeSwitch:(UISwitch *)sender {NSInteger slot=sender.tag-kZNFRRuntimeSlotBase;if(slot<0)return;NSUInteger index=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS;UIButton*b=[UIButton new];b.tag=kZNFRExecTagBase+(NSInteger)index;[self znfr_runtimeExecute:b];}
- (void)znfr_runtimeSliderChanged:(ZNRangeControl *)slider {NSInteger slot=slider.tag-kZNFRRuntimeSlotBase;if(slot<0)return;NSUInteger index=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS,arg=(NSUInteger)slot%ZN_RUNTIME_ACTION_MAX_ARGUMENTS;NSArray<ZNFeaturePageItem *> *items=[ZNFeaturePageModel sharedModel].items;if(index>=items.count)return;ZNFeaturePageItem *item=items[index];ZNRuntimeMethodActionRecord*r=[item.backingRecord isKindOfClass:ZNRuntimeMethodActionRecord.class]?item.backingRecord:nil;if(!r||r.argumentControlConfigs.count!=r.argumentCount||arg>=r.argumentCount)return;NSDictionary*cfg=r.argumentControlConfigs[arg];slider.value=ZNFRQuantize(slider.value,cfg,slider.minimumValue,slider.maximumValue);UIView*v=[self.contentView viewWithTag:kZNFRRuntimeValueBase+slot];if([v isKindOfClass:UILabel.class])((UILabel*)v).text=[NSString stringWithFormat:@"%.6g",slider.value];}
- (void)znfr_runtimeSliderCommit:(ZNRangeControl *)slider {[self znfr_runtimeSliderChanged:slider];NSInteger slot=slider.tag-kZNFRRuntimeSlotBase;if(slot<0)return;UIButton*b=[UIButton new];b.tag=kZNFRExecTagBase+(NSInteger)((NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS);[self znfr_runtimeExecute:b];}
- (void)znfr_runtimeNumberReturn:(UITextField *)field {[field resignFirstResponder];}
@end

extern "C" void ZNInstallCanonicalFeaturePageDeferred(void) {
    static BOOL snapshotReady = NO;
    if (!snapshotReady) { snapshotReady = YES; ZNFRPublishInitialSnapshot(); }
    Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040"); if(!cls)return;
    Method full=class_getInstanceMethod(cls,@selector(zn50_renderFeatureGroupsFull));
    Method compact=class_getInstanceMethod(cls,@selector(zn50_renderFeatureGroupsCompact));
    Method unifiedFull=class_getInstanceMethod(cls,@selector(znfr_renderFull));
    Method unifiedCompact=class_getInstanceMethod(cls,@selector(znfr_renderCompact));
    Method legacyRuntime=class_getInstanceMethod(cls,@selector(zn51_renderRuntime:));
    Method runtimeNoop=class_getInstanceMethod(cls,@selector(znfr_legacyRuntimeNoop:));
    if(full&&unifiedFull)method_setImplementation(full,method_getImplementation(unifiedFull));
    if(compact&&unifiedCompact)method_setImplementation(compact,method_getImplementation(unifiedCompact));
    if(legacyRuntime&&runtimeNoop)method_setImplementation(legacyRuntime,method_getImplementation(runtimeNoop));
    [[ZNRuntimeLogger sharedLogger]log:@"[feature-page] canonical renderer bound: Runtime + Static/Offset share one coordinate stream; render path has no discovery refresh"];
}