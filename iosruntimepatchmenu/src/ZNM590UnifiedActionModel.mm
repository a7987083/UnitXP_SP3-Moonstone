#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNFeatureSnapshotProvider.h"
#import "ZNRangeControl.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M5.9.0 — Unified Action Model bridge.
// Important: this file does NOT create another menu/controller hierarchy.
// It only rewires existing Builder fields and existing Static controls in-place.
// Runtime Action remains the semantic source of truth:
//   Slider -> authored max required, min=0, step=1
//   Number -> no authored value required
//   persisted Number/Slider values are restored into the Static Value Cell.

static const NSInteger kZNM590EnabledFieldTagBase = 442000;
static const NSInteger kZNM590TypeTagBase = 466000;
static const NSInteger kZNM590DeleteFeatureTagBase = 467000;
static const NSInteger kZNM590OldSliderMaxTagBase = 931000;
static const NSInteger kZNM590SliderTagBase = 471000;
static NSString * const kZNM590StaticSliderMaxDefaults = @"zonoe.m5.8.5.static-slider-max.v1";

@interface ZNStaticPatchRecord (ZNM590Private)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,assign) uint32_t patchID;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn64fb_renderOther;
- (void)zn65fc_decorateCompact:(BOOL)compact;
@end

static NSString *ZNM590Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM590FeatureNameForRow(ZNBinaryPatchRow *row) {
    NSString *group=ZNM590Trim(row.group);
    if(group.length && [group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return group;
    NSString *title=ZNM590Trim(row.title);
    return title.length?title:@"功能";
}

static NSString *ZNM590SliderDefaultsKey(NSString *featureName) {
    return [NSString stringWithFormat:@"%@.%@",kZNM590StaticSliderMaxDefaults,ZNM590Trim(featureName).lowercaseString];
}

static double ZNM590StoredSliderMax(NSString *featureName) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:ZNM590SliderDefaultsKey(featureName)];
    return [value isKindOfClass:NSNumber.class]?[value doubleValue]:0.0;
}

static void ZNM590StoreSliderMax(NSString *featureName,double value) {
    NSString *key=ZNM590SliderDefaultsKey(featureName);
    if(isfinite(value)&&value>0.0) [NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

static NSArray<NSDictionary *> *ZNM590BuilderFeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    NSMutableArray *order=[NSMutableArray array];
    NSMutableDictionary *names=[NSMutableDictionary dictionary];
    NSMutableDictionary *rows=[NSMutableDictionary dictionary];
    for(ZNBinaryPatchRow *row in workspace.rows){
        if(!row.offsetText.length&&!row.enabledText.length&&!ZNM590Trim(row.group).length&&!ZNM590Trim(row.title).length)continue;
        NSString *name=ZNM590FeatureNameForRow(row),*key=name.lowercaseString;
        if(!rows[key]){rows[key]=[NSMutableArray array];names[key]=name;[order addObject:key];}
        [rows[key] addObject:row];
    }
    NSMutableArray *out=[NSMutableArray array];
    for(NSString *key in order)[out addObject:@{@"name":names[key]?:@"功能",@"rows":[rows[key] copy]?:@[]}];
    return out;
}

static BOOL ZNM590PlainPositiveDecimal(NSString *text,double *valueOut) {
    NSString *s=ZNM590Trim(text);
    if(!s.length||s.length>5)return NO;
    NSCharacterSet *bad=[[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if([s rangeOfCharacterFromSet:bad].location!=NSNotFound)return NO;
    double v=s.doubleValue;
    if(!isfinite(v)||v<=0.0||v>16383.0)return NO;
    if(valueOut)*valueOut=v;
    return YES;
}

static UILabel *ZNM590LeftLabelForField(UITextField *field) {
    UIView *card=field.superview;
    if(!card)return nil;
    UILabel *best=nil;
    CGFloat fieldY=CGRectGetMidY(field.frame);
    for(UIView *view in card.subviews){
        if(![view isKindOfClass:UILabel.class])continue;
        UILabel *label=(UILabel *)view;
        if(fabs(CGRectGetMidY(label.frame)-fieldY)>18.0)continue;
        if(CGRectGetMaxX(label.frame)>CGRectGetMinX(field.frame)+4.0)continue;
        if(!best||CGRectGetMinX(label.frame)>CGRectGetMinX(best.frame))best=label;
    }
    return best;
}

@interface ZNBinaryPatchWorkspace (ZNM590UnifiedValidation)
- (BOOL)znm590_validateAll:(NSString **)error;
@end

@implementation ZNBinaryPatchWorkspace (ZNM590UnifiedValidation)
- (BOOL)znm590_validateAll:(NSString **)error {
    for(ZNBinaryPatchRow *row in self.rows){
        if(!row.offsetText.length)continue;
        ZNFeatureControlType type=row.featureControlType;
        if(type!=ZNFeatureControlTypeNumber&&type!=ZNFeatureControlTypeSlider)continue;
        NSString *name=ZNM590FeatureNameForRow(row);
        if(type==ZNFeatureControlTypeSlider){
            double max=ZNM590StoredSliderMax(name);
            if(!isfinite(max)||max<=0.0){
                if(error)*error=[NSString stringWithFormat:@"%@：滑块必须填写最大值（例如 31）",name];
                return NO;
            }
        }
        // Number/Slider carry no Patch/test value. Validation prepares only Offset + ValueType;
        // Slider additionally requires authored Max.
        row.enabledText=@"";
        row.validated=NO;
        row.validator=nil;
        row.originalHex=@"";
    }
    return [self znm590_validateAll:error];
}
@end

@interface ZNRuntimeMenuControllerV040 (ZNM590BuilderAdapter)
- (void)znm590_renderOther;
- (void)znm590_sliderMaxChanged:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM590BuilderAdapter)
- (void)znm590_renderOther {
    [self znm590_renderOther];
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    // M6.3: keep M5.8.5's dedicated Slider Max field visible.
    // The generic Enabled/Patch field is not used for Slider authoring.

    for(NSUInteger globalIndex=0;globalIndex<workspace.rows.count;globalIndex++){
        ZNBinaryPatchRow *row=workspace.rows[globalIndex];
        ZNFeatureControlType type=row.featureControlType;
        if(type!=ZNFeatureControlTypeNumber&&type!=ZNFeatureControlTypeSlider)continue;
        UITextField *field=(UITextField *)[self.contentView viewWithTag:kZNM590EnabledFieldTagBase+(NSInteger)globalIndex];
        if(![field isKindOfClass:UITextField.class])continue;
        UILabel *label=ZNM590LeftLabelForField(field);
        [field removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

        NSString *name=ZNM590FeatureNameForRow(row);
        if(type==ZNFeatureControlTypeSlider){
            // Max is edited by the dedicated visible field installed by M5.8.5.
            // Hide the generic Patch/Enabled input so there is one unambiguous Slider value.
            field.hidden=YES;
            if(label)label.hidden=YES;
        }else{
            // Number has no authoring/test value in M6.3. ValueType is selected
            // explicitly on the patch card; the actual number is entered only
            // from the generated runtime menu.
            if(label)label.text=@"数值";
            field.text=@"生成后在菜单中输入";
            field.placeholder=@"";
            field.enabled=NO;
            field.userInteractionEnabled=NO;
            field.accessibilityLabel=[NSString stringWithFormat:@"%@ Number 生成后输入",name];
        }
    }
}

- (void)znm590_sliderMaxChanged:(UITextField *)field {
    NSInteger globalIndex=field.tag-kZNM590EnabledFieldTagBase;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(globalIndex<0||(NSUInteger)globalIndex>=workspace.rows.count)return;
    ZNBinaryPatchRow *row=workspace.rows[(NSUInteger)globalIndex];
    if(row.featureControlType!=ZNFeatureControlTypeSlider)return;
    NSString *name=ZNM590FeatureNameForRow(row);
    NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:ZNM590Trim(field.text) locale:@{NSLocaleDecimalSeparator:@"."}];
    double value=(![n isEqualToNumber:NSDecimalNumber.notANumber])?n.doubleValue:0.0;
    if(!isfinite(value)||value<=0.0)value=0.0;
    if(value>16383.0)value=16383.0;
    ZNM590StoreSliderMax(name,value);
    row.validated=NO;
    row.validator=nil;
    row.originalHex=@"";
}
@end

static NSString *ZNM590RuntimePreferenceKey(NSDictionary *feature,NSString *suffix){
    uint64_t featureID=[feature[@"featureID"] unsignedLongLongValue];
    NSString *identity=featureID?[NSString stringWithFormat:@"%016llx",featureID]:[feature[@"key"] description];
    return [NSString stringWithFormat:@"zn.fc.%@.%@",identity?:@"feature",suffix?:@"value"];
}

static NSDictionary *ZNM590Display(ZNStaticPatchRecord *record){
    NSDictionary *embedded=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;
    if(embedded)return embedded;
    NSString *title=ZNM590Trim(record.title),*group=ZNM590Trim(record.group);
    if(!title.length||[title hasPrefix:@"Patch #"])title=[NSString stringWithFormat:@"功能 #%u",record.patchID];
    if(!group.length)group=@"Imported";
    return @{@"featureID":@0,@"title":title,@"group":group,@"explicitGroup":@([group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame),@"controlType":@(ZNFeatureControlTypeSwitch),@"valueType":@(ZNValueTypeAuto),@"sliderMax":@0};
}

static NSArray<NSDictionary *> *ZNM590RuntimeFeatures(void){
    return [[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
}

static NSDictionary *ZNM590EventInfo(NSDictionary *feature,NSNumber *value,NSString *valueText){
    NSMutableDictionary *info=[@{@"featureID":feature[@"featureID"]?:@0,@"title":feature[@"title"]?:@"功能",@"controlType":feature[@"controlType"]?:@(ZNFeatureControlTypeSwitch),@"valueType":feature[@"valueType"]?:@(ZNValueTypeAuto),@"key":feature[@"key"]?:@""} mutableCopy];
    if(value)info[@"value"]=value;
    if(valueText.length)info[@"valueText"]=valueText;
    return info;
}

static NSMutableSet<NSString *> *ZNM590RestoredTypedValueKeys(void){
    static NSMutableSet *set;static dispatch_once_t once;dispatch_once(&once,^{set=[NSMutableSet set];});return set;
}

extern "C" void ZNM630RestorePersistedTypedValues(UIView *contentView){
    NSArray *features=ZNM590RuntimeFeatures();
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSMutableSet *restored=ZNM590RestoredTypedValueKeys();
    for(NSUInteger i=0;i<features.count;i++){
        NSDictionary *feature=features[i];
        ZNFeatureControlType type=(ZNFeatureControlType)[feature[@"controlType"] unsignedIntValue];
        if(type!=ZNFeatureControlTypeNumber&&type!=ZNFeatureControlTypeSlider)continue;
        NSString *valueTextKey=ZNM590RuntimePreferenceKey(feature,@"valueText");
        NSString *valueKey=ZNM590RuntimePreferenceKey(feature,@"value");
        id storedText=[defaults objectForKey:valueTextKey];
        id storedValue=[defaults objectForKey:valueKey];
        if(![storedText isKindOfClass:NSString.class]&&![storedValue isKindOfClass:NSNumber.class])continue;
        NSString *restoreKey=[NSString stringWithFormat:@"%@|%ld",feature[@"key"]?:@"feature",(long)type];
        if([restored containsObject:restoreKey])continue;
        [restored addObject:restoreKey];
        NSString *text=[storedText isKindOfClass:NSString.class]?(NSString *)storedText:[(NSNumber *)storedValue stringValue];
        NSNumber *number=[storedValue isKindOfClass:NSNumber.class]?(NSNumber *)storedValue:@(text.doubleValue);

        if(type==ZNFeatureControlTypeSlider){
            double max=[feature[@"sliderMax"] doubleValue];
            if(isfinite(max)&&max>0.0){
                double v=MAX(0.0,MIN(max,round(number.doubleValue)));
                number=@(v);text=[NSString stringWithFormat:@"%.0f",v];
                ZNRangeControl *slider=(ZNRangeControl *)[contentView viewWithTag:kZNM590SliderTagBase+(NSInteger)i];
                if([slider isKindOfClass:ZNRangeControl.class])slider.value=v;
            }
        }

        NSDictionary *info=ZNM590EventInfo(feature,number,text);
        dispatch_async(dispatch_get_main_queue(),^{
            NSNotificationName name=(type==ZNFeatureControlTypeSlider)?ZNFeatureSliderValueDidChangeNotification:ZNFeatureNumberValueDidChangeNotification;
            [NSNotificationCenter.defaultCenter postNotificationName:name object:nil userInfo:info];
            [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.9.0-persist] restored Static %@ value=%@ key=%@",type==ZNFeatureControlTypeSlider?@"Slider":@"Number",text,restoreKey]];
        });
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNM590StaticPersistence)
- (void)znm590_decorateCompact:(BOOL)compact;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM590StaticPersistence)
- (void)znm590_decorateCompact:(BOOL)compact {
    [self znm590_decorateCompact:compact];
    ZNM630RestorePersistedTypedValues(self.contentView);
}
@end

extern "C" void ZNInstallM590UnifiedActionModelDeferred(void){
    static dispatch_once_t once;dispatch_once(&once,^{
        Class workspace=NSClassFromString(@"ZNBinaryPatchWorkspace");
        Method v1=class_getInstanceMethod(workspace,@selector(validateAll:));
        Method v2=class_getInstanceMethod(workspace,@selector(znm590_validateAll:));
        if(v1&&v2)method_exchangeImplementations(v1,v2);

        Class controller=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        Method r1=class_getInstanceMethod(controller,@selector(zn64fb_renderOther));
        Method r2=class_getInstanceMethod(controller,@selector(znm590_renderOther));
        if(r1&&r2)method_exchangeImplementations(r1,r2);
        // M6.3: typed-value persistence restore is called directly from
        // ZNFeatureRuntimeControlsV2. Do not add another decorator swizzle.
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.3-ui] M5.9.0 builder semantics retained; typed restore consolidated into runtime controls"];
    });
}
