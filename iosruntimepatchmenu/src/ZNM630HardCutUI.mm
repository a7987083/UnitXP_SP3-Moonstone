#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureSnapshotProvider.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNNativeHookRuntime.h"
#import "ZNNativeHookAction.h"
#import "ZNRangeControl.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM630HardCutSwitchTagBase = 963000;
static const NSInteger kZNM630HardCutButtonTagBase = 964000;
static const NSInteger kZNM630HardCutNumberFieldTagBase = 965000;
static const NSInteger kZNM630HardCutNumberExecuteTagBase = 966000;
static const NSInteger kZNM630HardCutSliderTagBase = 967000;
static const NSInteger kZNM630HardCutSliderValueTagBase = 968000;
static const NSInteger kZNM640NativeHookSliderTagBase = 973000;
static const NSInteger kZNM640NativeHookValueTagBase = 974000;
static const NSInteger kZNM650NativeHookSwitchTagBase = 975000;
static NSString * const kZNM640NativeHookValuePrefix = @"zonoe.native-hook.runtime-value.v1";

// Keep the proven M5.8 backend tag ABI, but only for execution/value lookup.
// The old M5.8 renderer remains bypassed.
static const NSInteger kZNM630RuntimeExecTag   = 896000;
static const NSInteger kZNM630RuntimeFieldTag  = 897000;
static const NSInteger kZNM630RuntimeSwitchTag = 898000;
static const NSInteger kZNM630RuntimeSliderTag = 899000;
static const NSInteger kZNM630RuntimeValueTag  = 901000;
static NSString * const kZNM630RuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

@interface ZNStaticPatchRecord (ZNM630HardCutRecord)
@property(nonatomic,assign,getter=isEnabled) BOOL enabled;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,assign) BOOL compactMode;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)znm58_execute:(UIButton *)sender;
- (void)znm58_numberChanged:(UITextField *)field;
- (void)znm58_numberReturn:(UITextField *)field;
- (void)znm58_switchChanged:(UISwitch *)control;
- (void)znm58_sliderChanged:(ZNRangeControl *)control;
- (void)znm58_sliderCommitted:(ZNRangeControl *)control;
@end

static BOOL ZNM630AllEnabled(NSArray<ZNStaticPatchRecord *> *records) {
    if (!records.count) return NO;
    for (ZNStaticPatchRecord *record in records) if (!record.enabled) return NO;
    return YES;
}

static BOOL ZNM630SetFeatureEnabled(NSArray<ZNStaticPatchRecord *> *records, BOOL enabled, NSString **error) {
    if (!records.count) {
        if (error) *error=@"Feature 没有 Patch";
        return NO;
    }
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];
    NSMutableArray<ZNStaticPatchRecord *> *changed=[NSMutableArray array];
    NSMutableArray<NSNumber *> *previous=[NSMutableArray array];

    for (ZNStaticPatchRecord *record in records) {
        if (record.enabled==enabled) continue;
        BOOL old=record.enabled;
        NSString *local=nil;
        if (![runtime setEnabled:enabled forRecord:record error:&local]) {
            for (NSInteger i=(NSInteger)changed.count-1;i>=0;i--) {
                NSString *ignored=nil;
                [runtime setEnabled:[previous[(NSUInteger)i] boolValue]
                          forRecord:changed[(NSUInteger)i]
                              error:&ignored];
            }
            if (error) *error=local?:@"切换失败";
            return NO;
        }
        [changed addObject:record];
        [previous addObject:@(old)];
    }
    return YES;
}

static NSDictionary *ZNM630EventInfo(NSDictionary *feature) {
    return @{
        @"featureID": feature[@"featureID"]?:@0,
        @"title": feature[@"title"]?:@"功能",
        @"controlType": feature[@"controlType"]?:@(ZNFeatureControlTypeSwitch),
        @"valueType": feature[@"valueType"]?:@0,
        @"key": feature[@"key"]?:@""
    };
}

static NSString *ZNM630PreferenceKey(NSDictionary *feature, NSString *suffix) {
    uint64_t featureID=[feature[@"featureID"] unsignedLongLongValue];
    NSString *identity=featureID?[NSString stringWithFormat:@"%016llx",featureID]:[feature[@"key"] description];
    return [NSString stringWithFormat:@"zn.fc.%@.%@",identity?:@"feature",suffix?:@"value"];
}

static NSString *ZNM630StoredText(NSDictionary *feature, NSString *fallback) {
    id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM630PreferenceKey(feature,@"valueText")];
    return [stored isKindOfClass:NSString.class]&&[(NSString *)stored length]?(NSString *)stored:(fallback?:@"0");
}

static double ZNM630StoredValue(NSDictionary *feature, double fallback) {
    id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM630PreferenceKey(feature,@"value")];
    return [stored isKindOfClass:NSNumber.class]?[stored doubleValue]:fallback;
}

static void ZNM630PersistValue(NSDictionary *feature, double value, NSString *text) {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZNM630PreferenceKey(feature,@"value")];
    if (text.length) [NSUserDefaults.standardUserDefaults setObject:text forKey:ZNM630PreferenceKey(feature,@"valueText")];
}

static NSDictionary *ZNM630ValueEventInfo(NSDictionary *feature, double value, NSString *text) {
    NSMutableDictionary *info=[ZNM630EventInfo(feature) mutableCopy];
    info[@"value"]=@(value);
    if (text.length) info[@"valueText"]=text;
    return info;
}

static NSString *ZNM630RuntimeRecordKey(ZNRuntimeMethodActionRecord *record) {
    NSString *identity=record.canonicalIdentity.length?record.canonicalIdentity:
        [NSString stringWithFormat:@"%@::%@/%lu",record.className?:@"",record.methodName?:@"",(unsigned long)record.argumentCount];
    return [NSString stringWithFormat:@"%u|%@",record.actionID,identity?:@""];
}

static NSArray<NSString *> *ZNM630RuntimeStoredValues(ZNRuntimeMethodActionRecord *record) {
    NSDictionary *root=[NSUserDefaults.standardUserDefaults objectForKey:kZNM630RuntimeValuesKey];
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSArray *values=root[ZNM630RuntimeRecordKey(record)];
    if (![values isKindOfClass:NSArray.class]||values.count!=record.argumentCount) return nil;
    for (id value in values) if (![value isKindOfClass:NSString.class]) return nil;
    return values;
}

static double ZNM630RuntimeQuantize(double value, NSDictionary *cfg, double fallbackMin, double fallbackMax) {
    double min=[cfg[@"min"] doubleValue],max=[cfg[@"max"] doubleValue],step=[cfg[@"step"] doubleValue];
    if (!isfinite(min)) min=fallbackMin;
    if (!isfinite(max)||max<=min) max=fallbackMax>min?fallbackMax:min+100.0;
    if (!isfinite(step)||step<=0.0) step=1.0;
    value=MAX(min,MIN(max,value));
    double q=min+round((value-min)/step)*step;
    return MAX(min,MIN(max,q));
}

static NSString *ZNM630RuntimeValueText(double value, NSDictionary *cfg) {
    double step=[cfg[@"step"] doubleValue];
    if (!isfinite(step)||step<=0.0) step=1.0;
    if (fabs(step-round(step))<1e-9&&fabs(value-round(value))<1e-9)
        return [NSString stringWithFormat:@"%.0f",value];
    return [NSString stringWithFormat:@"%.6g",value];
}

static NSString *ZNM630RuntimeShortType(NSString *type) {
    NSString *last=[(type?:@"") componentsSeparatedByString:@"."].lastObject;
    return last.length?last:(type?:@"?");
}

@interface ZNRuntimeMenuControllerV040 (ZNM630HardCutUI)
- (void)znm630_hardCutRenderFullPage;
- (void)znm630_hardCutRenderCompactPage;
- (void)znm630_hardCutRenderFeatures:(BOOL)compact;
- (void)znm630_hardCutSwitchChanged:(UISwitch *)sender;
- (void)znm630_hardCutButtonTapped:(UIButton *)sender;
- (void)znm630_hardCutNumberChanged:(UITextField *)sender;
- (void)znm630_hardCutNumberReturn:(UITextField *)sender;
- (void)znm630_hardCutNumberExecute:(UIButton *)sender;
- (void)znm630_hardCutSliderChanged:(UISlider *)sender;
- (void)znm630_hardCutSliderCommitted:(UISlider *)sender;
- (CGFloat)znm630_hardCutRenderRuntimeAtY:(CGFloat)y width:(CGFloat)width compact:(BOOL)compact;
- (void)znm640_nativeHookSliderChanged:(UISlider *)sender;
- (void)znm640_nativeHookSliderCommitted:(UISlider *)sender;
- (void)znm650_nativeHookSwitchChanged:(UISwitch *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM630HardCutUI)

- (CGFloat)znm630_hardCutRenderRuntimeAtY:(CGFloat)y width:(CGFloat)width compact:(BOOL)compact {
    ZNRuntimeActionRuntime *runtime=[ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *records=runtime.records?:@[];

    ZNNativeHookRuntime *hookRuntime=[ZNNativeHookRuntime sharedRuntime];
    [hookRuntime refreshGeneratedActions];
    NSArray<ZNNativeHookAction *> *hooks=hookRuntime.generatedActions?:@[];
    if (!records.count && !hooks.count) return y;

    for (NSUInteger hidx=0;hidx<hooks.count;hidx++) {
        ZNNativeHookAction *hook=hooks[hidx];
        CGFloat height=compact?56.0:(hook.featureDescription.length?76.0:64.0);
        UIView *card=[self cardAtY:y height:height width:width compact:compact];

        UILabel *name=[self label:(hook.title.length?hook.title:hook.methodName)
                              size:(compact?10.5:11.2)
                            weight:UIFontWeightSemibold
                             color:self.theme.primaryTextColor];
        name.frame=CGRectMake(compact?9.0:13.0,compact?5.0:6.0,CGRectGetWidth(card.bounds)-(compact?18.0:26.0),22.0);
        name.lineBreakMode=NSLineBreakByTruncatingTail;
        [card addSubview:name];

        CGFloat sliderY=compact?27.0:(hook.featureDescription.length?43.0:31.0);
        if(!compact&&hook.featureDescription.length){
            UILabel *detail=[self label:hook.featureDescription size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            detail.frame=CGRectMake(13.0,26.0,CGRectGetWidth(card.bounds)-26.0,16.0);
            detail.lineBreakMode=NSLineBreakByTruncatingTail;
            [card addSubview:detail];
        }

        NSString *key=[NSString stringWithFormat:@"%@.%u",kZNM640NativeHookValuePrefix,hook.actionID];
        id stored=[NSUserDefaults.standardUserDefaults objectForKey:key];
        NSInteger value=stored?[stored integerValue]:hook.defaultValue;
        value=MIN(MAX(value,hook.minValue),hook.maxValue);

        if(hook.templateKind==ZNNativeHookTemplateManagedCallbackShortCircuit||
           hook.templateKind==ZNNativeHookTemplateReturnBoolOverride){
            UISwitch *toggle=[UISwitch new];
            toggle.on=value!=0;
            toggle.tag=kZNM650NativeHookSwitchTagBase+(NSInteger)hidx;
            toggle.transform=compact?CGAffineTransformMakeScale(.76,.76):CGAffineTransformMakeScale(.84,.84);
            toggle.center=CGPointMake(CGRectGetWidth(card.bounds)-38.0,sliderY+14.0);
            toggle.onTintColor=self.theme.accentColor;
            [toggle addTarget:self action:@selector(znm650_nativeHookSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:toggle];
            if(toggle.isOn){
                NSString *installError=nil;
                [hookRuntime setValue:1 forAction:hook error:&installError];
                if(installError.length)[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[native-hook-runtime] auto-install %@ failed: %@",hook.title,installError]];
            }
        }else{
            CGFloat valueW=46.0;
            CGFloat sliderW=MAX(70.0,CGRectGetWidth(card.bounds)-26.0-valueW-5.0);
            UISlider *slider=[[UISlider alloc]initWithFrame:CGRectMake(13.0,sliderY,sliderW,28.0)];
            slider.minimumValue=(float)hook.minValue;
            slider.maximumValue=(float)hook.maxValue;
            slider.value=(float)value;
            slider.continuous=YES;
            slider.minimumTrackTintColor=self.theme.accentColor;
            slider.maximumTrackTintColor=[self.theme.borderColor colorWithAlphaComponent:.65];
            slider.thumbTintColor=self.theme.primaryTextColor;
            slider.tag=kZNM640NativeHookSliderTagBase+(NSInteger)hidx;
            [slider addTarget:self action:@selector(znm640_nativeHookSliderChanged:) forControlEvents:UIControlEventValueChanged];
            [slider addTarget:self action:@selector(znm640_nativeHookSliderCommitted:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
            [card addSubview:slider];

            UILabel *valueLabel=[self label:[NSString stringWithFormat:@"×%ld",(long)value]
                                       size:8.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            valueLabel.textAlignment=NSTextAlignmentRight;
            valueLabel.font=[UIFont monospacedDigitSystemFontOfSize:8.4 weight:UIFontWeightSemibold];
            valueLabel.frame=CGRectMake(CGRectGetMaxX(slider.frame)+4.0,sliderY,valueW,28.0);
            valueLabel.tag=kZNM640NativeHookValueTagBase+(NSInteger)hidx;
            [card addSubview:valueLabel];

            if(value!=1){
                NSString *installError=nil;
                [hookRuntime setValue:value forAction:hook error:&installError];
                if(installError.length)[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[native-hook-runtime] auto-install %@ failed: %@",hook.title,installError]];
            }
        }

        [self.contentView addSubview:card];
        y+=height+(compact?6.0:8.0);
    }

    for (NSUInteger i=0;i<records.count;i++) {
        ZNRuntimeMethodActionRecord *record=records[i];
        NSArray<NSDictionary *> *configs=(record.argumentControlConfigs.count==record.argumentCount)?record.argumentControlConfigs:@[];
        NSArray<NSString *> *stored=ZNM630RuntimeStoredValues(record);

        NSUInteger exposed=0;
        BOOL needsManualExecute=NO;
        for (NSUInteger arg=0;arg<record.argumentCount;arg++) {
            NSDictionary *cfg=configs.count?configs[arg]:nil;
            if (![cfg[@"enabled"] boolValue]) continue;
            exposed++;
            ZNRuntimeArgumentControlType type=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
            if (type==ZNRuntimeArgumentControlTypeNumber) needsManualExecute=YES;
        }
        if (exposed==0) needsManualExecute=YES;

        NSString *runtimeDescription=record.featureDescription?:@"";
        CGFloat rowH=34.0,baseH=compact?42.0:(runtimeDescription.length?60.0:48.0);
        CGFloat height=baseH+exposed*rowH;
        UIView *card=[self cardAtY:y height:height width:width compact:compact];

        UILabel *name=[self label:(record.title.length?record.title:record.methodName)
                              size:(compact?10.5:11.2)
                            weight:UIFontWeightSemibold
                             color:self.theme.primaryTextColor];
        name.frame=CGRectMake(compact?9.0:13.0,runtimeDescription.length&&!compact?5.0:8.0,
                              CGRectGetWidth(card.bounds)-(needsManualExecute?92.0:26.0),24.0);
        name.lineBreakMode=NSLineBreakByTruncatingTail;
        [card addSubview:name];
        if (!compact && runtimeDescription.length) {
            UILabel *detail=[self label:runtimeDescription size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            detail.frame=CGRectMake(13.0,29.0,MAX(40.0,CGRectGetWidth(card.bounds)-(needsManualExecute?100.0:26.0)),22.0);
            detail.numberOfLines=1;
            detail.lineBreakMode=NSLineBreakByTruncatingTail;
            [card addSubview:detail];
        }

        if (needsManualExecute) {
            UIButton *execute=[UIButton buttonWithType:UIButtonTypeSystem];
            execute.tag=kZNM630RuntimeExecTag+(NSInteger)i;
            execute.frame=CGRectMake(CGRectGetWidth(card.bounds)-76.0,7.0,64.0,29.0);
            [execute setTitle:@"执行" forState:UIControlStateNormal];
            [execute setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
            execute.backgroundColor=self.theme.controlColor;
            execute.layer.cornerRadius=7.0;
            execute.layer.borderWidth=1.0;
            execute.layer.borderColor=self.theme.borderColor.CGColor;
            [execute addTarget:self action:@selector(znm58_execute:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:execute];
        }

        CGFloat rowY=baseH;
        for (NSUInteger arg=0;arg<record.argumentCount;arg++) {
            NSDictionary *cfg=configs.count?configs[arg]:nil;
            if (![cfg[@"enabled"] boolValue]) continue;

            NSInteger slot=(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);
            NSString *fallback=arg<record.argumentValues.count?record.argumentValues[arg]:@"";
            NSString *defaultValue=(stored.count==record.argumentCount)?stored[arg]:fallback;
            ZNRuntimeArgumentControlType type=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);

            if (type==ZNRuntimeArgumentControlTypeSwitch) {
                UISwitch *control=[UISwitch new];
                control.on=defaultValue.boolValue||[defaultValue.lowercaseString isEqualToString:@"true"];
                control.tag=kZNM630RuntimeSwitchTag+slot;
                control.transform=compact?CGAffineTransformMakeScale(.76,.76):CGAffineTransformMakeScale(.82,.82);
                control.center=CGPointMake(CGRectGetWidth(card.bounds)-36.0,rowY+14.0);
                control.onTintColor=self.theme.accentColor;
                [control addTarget:self action:@selector(znm58_switchChanged:) forControlEvents:UIControlEventValueChanged];
                [card addSubview:control];
            } else if (type==ZNRuntimeArgumentControlTypeSlider) {
                double min=[cfg[@"min"] doubleValue],max=[cfg[@"max"] doubleValue];
                if (!isfinite(min)) min=0.0;
                if (!isfinite(max)||max<=min) max=min+1.0;
                CGFloat valueW=46.0;
                CGFloat sliderW=MAX(70.0,CGRectGetWidth(card.bounds)-26.0-valueW-5.0);
                ZNRangeControl *control=[[ZNRangeControl alloc] initWithFrame:CGRectMake(13.0,rowY,sliderW,28.0)];
                control.minimumValue=min;
                control.maximumValue=max;
                control.value=ZNM630RuntimeQuantize(defaultValue.doubleValue,cfg,min,max);
                control.minimumTrackTintColor=self.theme.accentColor;
                control.maximumTrackTintColor=[self.theme.borderColor colorWithAlphaComponent:.65];
                control.thumbTintColor=self.theme.primaryTextColor;
                control.tag=kZNM630RuntimeSliderTag+slot;
                [control addTarget:self action:@selector(znm58_sliderChanged:) forControlEvents:UIControlEventValueChanged];
                [control addTarget:self action:@selector(znm58_sliderCommitted:) forControlEvents:UIControlEventPrimaryActionTriggered];
                [card addSubview:control];

                UILabel *valueLabel=[self label:ZNM630RuntimeValueText(control.value,cfg)
                                           size:8.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
                valueLabel.textAlignment=NSTextAlignmentRight;
                valueLabel.font=[UIFont monospacedDigitSystemFontOfSize:8.4 weight:UIFontWeightSemibold];
                valueLabel.frame=CGRectMake(CGRectGetMaxX(control.frame)+4.0,rowY,valueW,28.0);
                valueLabel.tag=kZNM630RuntimeValueTag+slot;
                [card addSubview:valueLabel];
            } else if (type==ZNRuntimeArgumentControlTypeButton) {
                UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
                button.tag=kZNM630RuntimeExecTag+(NSInteger)i;
                button.frame=CGRectMake(CGRectGetWidth(card.bounds)-70.0,rowY,58.0,28.0);
                [button setTitle:@"触发" forState:UIControlStateNormal];
                [button setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
                button.backgroundColor=self.theme.controlColor;
                button.layer.cornerRadius=7.0;
                button.layer.borderWidth=1.0;
                button.layer.borderColor=self.theme.borderColor.CGColor;
                [button addTarget:self action:@selector(znm58_execute:) forControlEvents:UIControlEventTouchUpInside];
                [card addSubview:button];
            } else {
                UITextField *field=[[UITextField alloc] initWithFrame:CGRectMake(13.0,rowY,CGRectGetWidth(card.bounds)-26.0,28.0)];
                field.text=defaultValue;
                field.placeholder=defaultValue;
                field.textColor=self.theme.primaryTextColor;
                field.backgroundColor=self.theme.controlColor;
                field.layer.cornerRadius=6.0;
                field.layer.borderWidth=1.0;
                field.layer.borderColor=self.theme.borderColor.CGColor;
                field.font=[UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium];
                field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;
                field.returnKeyType=UIReturnKeyDone;
                field.tag=kZNM630RuntimeFieldTag+slot;
                [field addTarget:self action:@selector(znm58_numberChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm58_numberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];
            }
            rowY+=rowH;
        }

        [self.contentView addSubview:card];
        y+=height+(compact?6.0:8.0);
    }
    return y;
}

- (void)znm630_hardCutRenderFeatures:(BOOL)compact {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    CGFloat width=CGRectGetWidth(self.contentView.bounds);
    CGFloat y=compact?7.0:9.0;

    if (!features.count) {
        CGFloat runtimeStart=y;
        y=[self znm630_hardCutRenderRuntimeAtY:y width:width compact:compact];
        if (y==runtimeStart) {
            UIView *card=[self cardAtY:y height:(compact?40.0:46.0) width:width compact:compact];
            UILabel *label=[self label:@"暂无功能" size:(compact?10.7:11.0) weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
            label.frame=CGRectMake(12,10,MAX(0.0,CGRectGetWidth(card.bounds)-24),22);
            [card addSubview:label];
            [self.contentView addSubview:card];
            y=CGRectGetMaxY(card.frame)+8.0;
        }
        [self zn40_updateContentHeight:y+4.0];
        self.contentScroll.delaysContentTouches=NO;
        self.contentScroll.canCancelContentTouches=YES;
        return;
    }

    for (NSUInteger i=0;i<features.count;i++) {
        NSDictionary *feature=features[i];
        NSString *title=[feature[@"title"] isKindOfClass:NSString.class]?feature[@"title"]:@"功能";
        NSString *description=[feature[@"description"] isKindOfClass:NSString.class]?feature[@"description"]:@"";
        ZNFeatureControlType type=(ZNFeatureControlType)[feature[@"controlType"] unsignedIntValue];

        CGFloat h=compact?42.0:(description.length?60.0:48.0);
        UIView *card=[self cardAtY:y height:h width:width compact:compact];

        CGFloat textWidth=MAX(40.0,CGRectGetWidth(card.bounds)-(compact?88:108));
        UILabel *name=[self label:title size:(compact?10.8:11.5) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame=compact
            ? CGRectMake(10,0,textWidth,h)
            : CGRectMake(13,description.length?6.0:0,textWidth,description.length?24.0:h);
        name.lineBreakMode=NSLineBreakByTruncatingTail;
        [card addSubview:name];

        if(!compact&&description.length){
            UILabel *detail=[self label:description size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            detail.frame=CGRectMake(13,29.0,textWidth,22.0);
            detail.numberOfLines=1;
            detail.lineBreakMode=NSLineBreakByTruncatingTail;
            [card addSubview:detail];
        }

        if (type==ZNFeatureControlTypeSwitch) {
            UISwitch *toggle=[UISwitch new];
            toggle.tag=kZNM630HardCutSwitchTagBase+(NSInteger)i;
            toggle.on=ZNM630AllEnabled(feature[@"records"]);
            toggle.transform=compact?CGAffineTransformMakeScale(0.78,0.78):CGAffineTransformMakeScale(0.86,0.86);
            CGSize s=toggle.bounds.size;
            toggle.center=CGPointMake(CGRectGetWidth(card.bounds)-(compact?31.0:36.0),h*0.5);
            toggle.bounds=CGRectMake(0,0,s.width,s.height);
            toggle.onTintColor=self.theme.accentColor;
            [toggle addTarget:self action:@selector(znm630_hardCutSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:toggle];
        } else if (type==ZNFeatureControlTypeButton) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            button.tag=kZNM630HardCutButtonTagBase+(NSInteger)i;
            button.frame=CGRectMake(CGRectGetWidth(card.bounds)-(compact?72:86),(h-(compact?28:32))*0.5,compact?62:72,compact?28:32);
            [button setTitle:@"执行" forState:UIControlStateNormal];
            [button setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
            button.backgroundColor=self.theme.controlColor;
            button.layer.cornerRadius=7;
            button.layer.borderWidth=1;
            button.layer.borderColor=self.theme.borderColor.CGColor;
            [button addTarget:self action:@selector(znm630_hardCutButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:button];
        } else if (type==ZNFeatureControlTypeNumber) {
            CGFloat executeW=compact?44.0:50.0;
            CGFloat gap=4.0;
            CGFloat totalW=compact?118.0:138.0;
            CGFloat x=CGRectGetWidth(card.bounds)-totalW-(compact?7.0:10.0);

            UITextField *field=[[UITextField alloc] initWithFrame:CGRectMake(x,compact?7.0:8.0,totalW-executeW-gap,compact?28.0:32.0)];
            field.frame=CGRectMake(field.frame.origin.x,(h-field.frame.size.height)*0.5,field.frame.size.width,field.frame.size.height);
            field.tag=kZNM630HardCutNumberFieldTagBase+(NSInteger)i;
            field.text=ZNM630StoredText(feature,@"0");
            field.textAlignment=NSTextAlignmentCenter;
            field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;
            field.returnKeyType=UIReturnKeyDone;
            field.textColor=self.theme.primaryTextColor;
            field.backgroundColor=[self.theme.controlColor colorWithAlphaComponent:.82];
            field.font=[UIFont systemFontOfSize:(compact?9.0:9.6) weight:UIFontWeightSemibold];
            field.layer.cornerRadius=7.0;
            field.layer.borderWidth=1.0;
            field.layer.borderColor=self.theme.borderColor.CGColor;
            [field addTarget:self action:@selector(znm630_hardCutNumberChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
            [field addTarget:self action:@selector(znm630_hardCutNumberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];
            [card addSubview:field];

            UIButton *execute=[UIButton buttonWithType:UIButtonTypeSystem];
            execute.tag=kZNM630HardCutNumberExecuteTagBase+(NSInteger)i;
            execute.frame=CGRectMake(CGRectGetMaxX(field.frame)+gap,field.frame.origin.y,executeW,field.frame.size.height);
            [execute setTitle:@"执行" forState:UIControlStateNormal];
            [execute setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
            execute.backgroundColor=self.theme.controlColor;
            execute.layer.cornerRadius=7.0;
            execute.layer.borderWidth=1.0;
            execute.layer.borderColor=self.theme.borderColor.CGColor;
            [execute addTarget:self action:@selector(znm630_hardCutNumberExecute:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:execute];
        } else if (type==ZNFeatureControlTypeSlider) {
            double max=[feature[@"sliderMax"] doubleValue];
            if (!isfinite(max)||max<=0.0) max=10.0;
            double stored=ZNM630StoredValue(feature,0.0);
            if (!isfinite(stored)) stored=0.0;
            double value=MAX(0.0,MIN(max,round(stored)));

            CGFloat valueW=compact?38.0:44.0;
            CGFloat left=compact?72.0:92.0;
            CGFloat right=valueW+(compact?8.0:10.0);
            UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(left,(h-(compact?28.0:32.0))*0.5,MAX(40.0,CGRectGetWidth(card.bounds)-left-right),compact?28.0:32.0)];
            slider.tag=kZNM630HardCutSliderTagBase+(NSInteger)i;
            slider.minimumValue=0.0f;
            slider.maximumValue=(float)max;
            slider.value=(float)value;
            slider.minimumTrackTintColor=self.theme.accentColor;
            slider.maximumTrackTintColor=[self.theme.borderColor colorWithAlphaComponent:.55];
            slider.continuous=YES;
            [slider addTarget:self action:@selector(znm630_hardCutSliderChanged:) forControlEvents:UIControlEventValueChanged];
            [slider addTarget:self action:@selector(znm630_hardCutSliderCommitted:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
            [card addSubview:slider];

            UILabel *valueLabel=[self label:[NSString stringWithFormat:@"%.0f",value]
                                      size:(compact?9.0:9.5)
                                    weight:UIFontWeightSemibold
                                     color:self.theme.secondaryTextColor];
            valueLabel.tag=kZNM630HardCutSliderValueTagBase+(NSInteger)i;
            valueLabel.textAlignment=NSTextAlignmentCenter;
            valueLabel.frame=CGRectMake(CGRectGetWidth(card.bounds)-right+2.0,0,valueW,h);
            [card addSubview:valueLabel];
        }

        [self.contentView addSubview:card];
        y+=h+(compact?6.0:7.0);
    }

    y=[self znm630_hardCutRenderRuntimeAtY:y width:width compact:compact];
    [self zn40_updateContentHeight:y+4.0];
    self.contentScroll.delaysContentTouches=NO;
    self.contentScroll.canCancelContentTouches=YES;
}

- (void)znm630_hardCutRenderFullPage {
    NSString *category=(self.selectedCategory>=0&&self.selectedCategory<(NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory] : @"";
    if ([category isEqualToString:@"功能"]) {
        [self znm630_hardCutRenderFeatures:NO];
        return;
    }

    // Hard-Cut is intentionally scoped to the public Feature surface first.
    // Other authoring/debug pages continue through the preserved legacy chain.
    Method m=class_getInstanceMethod([self class],@selector(znm630_hardCutRenderFullPage));
    IMP current=m?method_getImplementation(m):NULL;
    (void)current;
}

- (void)znm630_hardCutRenderCompactPage {
    [self znm630_hardCutRenderFeatures:YES];
}

- (void)znm640_nativeHookSliderChanged:(UISlider *)sender {
    NSInteger index=sender.tag-kZNM640NativeHookSliderTagBase;
    if(index<0)return;
    [[ZNNativeHookRuntime sharedRuntime] refreshGeneratedActions];
    NSArray<ZNNativeHookAction *> *hooks=[ZNNativeHookRuntime sharedRuntime].generatedActions?:@[];
    if((NSUInteger)index>=hooks.count)return;
    ZNNativeHookAction *hook=hooks[(NSUInteger)index];
    NSInteger value=(NSInteger)llround(sender.value);
    value=MIN(MAX(value,hook.minValue),hook.maxValue);
    sender.value=(float)value;
    UILabel *label=[self.contentView viewWithTag:kZNM640NativeHookValueTagBase+index];
    if([label isKindOfClass:UILabel.class])label.text=[NSString stringWithFormat:@"×%ld",(long)value];
}

- (void)znm640_nativeHookSliderCommitted:(UISlider *)sender {
    NSInteger index=sender.tag-kZNM640NativeHookSliderTagBase;
    if(index<0)return;
    [[ZNNativeHookRuntime sharedRuntime] refreshGeneratedActions];
    NSArray<ZNNativeHookAction *> *hooks=[ZNNativeHookRuntime sharedRuntime].generatedActions?:@[];
    if((NSUInteger)index>=hooks.count)return;
    ZNNativeHookAction *hook=hooks[(NSUInteger)index];
    NSInteger value=(NSInteger)llround(sender.value);
    value=MIN(MAX(value,hook.minValue),hook.maxValue);
    NSString *key=[NSString stringWithFormat:@"%@.%u",kZNM640NativeHookValuePrefix,hook.actionID];
    [NSUserDefaults.standardUserDefaults setInteger:value forKey:key];

    NSString *error=nil;
    // M6.4 contract: keep the hook installed even at multiplier=1.
    // setValue installs on first use, then only updates the atomic multiplier.
    BOOL ok=[[ZNNativeHookRuntime sharedRuntime] setValue:value forAction:hook error:&error];
    if(!ok&&error.length)[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[native-hook-runtime] slider commit %@ failed: %@",hook.title,error]];
    [self znm640_nativeHookSliderChanged:sender];
}

- (void)znm650_nativeHookSwitchChanged:(UISwitch *)sender {
    NSInteger index=sender.tag-kZNM650NativeHookSwitchTagBase;
    if(index<0)return;
    [[ZNNativeHookRuntime sharedRuntime] refreshGeneratedActions];
    NSArray<ZNNativeHookAction *> *hooks=[ZNNativeHookRuntime sharedRuntime].generatedActions?:@[];
    if((NSUInteger)index>=hooks.count)return;
    ZNNativeHookAction *hook=hooks[(NSUInteger)index];
    if(hook.templateKind!=ZNNativeHookTemplateManagedCallbackShortCircuit&&
       hook.templateKind!=ZNNativeHookTemplateReturnBoolOverride)return;

    NSString *key=[NSString stringWithFormat:@"%@.%u",kZNM640NativeHookValuePrefix,hook.actionID];
    [NSUserDefaults.standardUserDefaults setInteger:(sender.isOn?1:0) forKey:key];
    NSString *error=nil;
    BOOL ok=[[ZNNativeHookRuntime sharedRuntime] setValue:(sender.isOn?1:0) forAction:hook error:&error];
    if(!ok){
        sender.on=!sender.isOn;
        [NSUserDefaults.standardUserDefaults setInteger:(sender.isOn?1:0) forKey:key];
        if(error.length)[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[native-hook-switch] %@ failed: %@",hook.title,error]];
    }
}

- (void)znm630_hardCutSwitchChanged:(UISwitch *)sender {
    NSInteger index=sender.tag-kZNM630HardCutSwitchTagBase;
    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    if (index<0||(NSUInteger)index>=features.count) return;

    NSDictionary *feature=features[(NSUInteger)index];
    NSArray<ZNStaticPatchRecord *> *records=feature[@"records"];
    NSString *error=nil;
    BOOL ok=ZNM630SetFeatureEnabled(records,sender.isOn,&error);
    sender.on=ZNM630AllEnabled(records);

    [[ZNRuntimeLogger sharedLogger] log:
        [NSString stringWithFormat:@"[m6.3-hardcut] switch %@ %@ %@",
         feature[@"title"]?:@"功能",sender.isOn?@"ON":@"OFF",
         ok?@"OK":(error?:@"FAILED")]];
}

- (void)znm630_hardCutButtonTapped:(UIButton *)sender {
    NSInteger index=sender.tag-kZNM630HardCutButtonTagBase;
    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    if (index<0||(NSUInteger)index>=features.count) return;
    NSDictionary *feature=features[(NSUInteger)index];
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureActionRequestedNotification
                                                      object:self
                                                    userInfo:ZNM630EventInfo(feature)];
}

- (void)znm630_hardCutNumberChanged:(UITextField *)sender {
    NSInteger index=sender.tag-kZNM630HardCutNumberFieldTagBase;
    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    if (index<0||(NSUInteger)index>=features.count) return;
    NSDictionary *feature=features[(NSUInteger)index];
    NSString *text=[sender.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) text=@"0";
    NSDecimalNumber *number=[NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator:@"."}];
    if (![number isEqualToNumber:NSDecimalNumber.notANumber])
        ZNM630PersistValue(feature,number.doubleValue,text);
}

- (void)znm630_hardCutNumberReturn:(UITextField *)sender {
    [self znm630_hardCutNumberChanged:sender];
    [sender resignFirstResponder];
}

- (void)znm630_hardCutNumberExecute:(UIButton *)sender {
    NSInteger index=sender.tag-kZNM630HardCutNumberExecuteTagBase;
    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    if (index<0||(NSUInteger)index>=features.count) return;
    NSDictionary *feature=features[(NSUInteger)index];
    NSString *text=ZNM630StoredText(feature,@"0");
    NSDecimalNumber *number=[NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator:@"."}];
    if ([number isEqualToNumber:NSDecimalNumber.notANumber]) return;
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureNumberValueDidChangeNotification
                                                      object:self
                                                    userInfo:ZNM630ValueEventInfo(feature,number.doubleValue,text)];
}

- (void)znm630_hardCutSliderChanged:(UISlider *)sender {
    NSInteger index=sender.tag-kZNM630HardCutSliderTagBase;
    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    if (index<0||(NSUInteger)index>=features.count) return;
    NSDictionary *feature=features[(NSUInteger)index];
    double max=[feature[@"sliderMax"] doubleValue];
    if (!isfinite(max)||max<=0.0) max=10.0;
    double value=MAX(0.0,MIN(max,round(sender.value)));
    UILabel *label=[self.contentView viewWithTag:kZNM630HardCutSliderValueTagBase+index];
    if ([label isKindOfClass:UILabel.class]) label.text=[NSString stringWithFormat:@"%.0f",value];
}

- (void)znm630_hardCutSliderCommitted:(UISlider *)sender {
    NSInteger index=sender.tag-kZNM630HardCutSliderTagBase;
    NSArray<NSDictionary *> *features=[[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
    if (index<0||(NSUInteger)index>=features.count) return;
    NSDictionary *feature=features[(NSUInteger)index];
    double max=[feature[@"sliderMax"] doubleValue];
    if (!isfinite(max)||max<=0.0) max=10.0;
    double value=MAX(0.0,MIN(max,round(sender.value)));
    sender.value=(float)value;
    NSString *text=[NSString stringWithFormat:@"%.0f",value];
    ZNM630PersistValue(feature,value,text);
    UILabel *label=[self.contentView viewWithTag:kZNM630HardCutSliderValueTagBase+index];
    if ([label isKindOfClass:UILabel.class]) label.text=text;
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification
                                                      object:self
                                                    userInfo:ZNM630ValueEventInfo(feature,value,text)];
}

@end

static IMP gZNM630PreviousFullPageIMP=NULL;

static void ZNM630HardCutFullPage(id self, SEL _cmd) {
    ZNRuntimeMenuControllerV040 *controller=(ZNRuntimeMenuControllerV040 *)self;
    NSString *category=(controller.selectedCategory>=0&&controller.selectedCategory<(NSInteger)controller.categories.count)
        ? controller.categories[(NSUInteger)controller.selectedCategory] : @"";
    if ([category isEqualToString:@"功能"]) {
        [controller znm630_hardCutRenderFeatures:NO];
        return;
    }
    if (gZNM630PreviousFullPageIMP) ((void(*)(id,SEL))gZNM630PreviousFullPageIMP)(self,_cmd);
}

extern "C" void ZNInstallM630HardCutUIDeferred(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method full=class_getInstanceMethod(cls,@selector(renderFullPage));
        if (full) {
            gZNM630PreviousFullPageIMP=method_getImplementation(full);
            method_setImplementation(full,(IMP)ZNM630HardCutFullPage);
        }

        Method compact=class_getInstanceMethod(cls,@selector(renderCompactPage));
        Method hardCompact=class_getInstanceMethod(cls,@selector(znm630_hardCutRenderCompactPage));
        if (compact&&hardCompact)
            method_setImplementation(compact,method_getImplementation(hardCompact));

        [[ZNRuntimeLogger sharedLogger] log:
            @"[m6.3-hardcut] Feature UI hard-cut active: legacy feature decorators bypassed; native controls only"];
    });
}
