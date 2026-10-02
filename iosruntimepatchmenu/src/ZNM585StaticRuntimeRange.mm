#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNFeatureSnapshotProvider.h"
#import "ZNRangeControl.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM585SliderTagBase = 471000;

@interface ZNStaticPatchRecord (ZNM585RangePrivate)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,assign) uint32_t patchID;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn65fc_decorateCompact:(BOOL)compact;
- (void)zn65fc_sliderCommitted:(ZNRangeControl *)slider;
@end

static NSString *ZNM585RTrim(NSString *value) { return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

static NSDictionary *ZNM585RDisplay(ZNStaticPatchRecord *record) {
    NSDictionary *embedded=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;
    if(embedded)return embedded;
    NSString *title=ZNM585RTrim(record.title),*group=ZNM585RTrim(record.group);
    if(!title.length||[title hasPrefix:@"Patch #"])title=[NSString stringWithFormat:@"功能 #%u",record.patchID];
    if(!group.length)group=@"Imported";
    return @{@"featureID":@0,@"title":title,@"group":group,@"explicitGroup":@([group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame),@"controlType":@(ZNFeatureControlTypeSwitch),@"valueType":@(ZNValueTypeAuto),@"sliderMax":@0};
}

static NSArray<NSDictionary *> *ZNM585RFeatures(void) {
    return [[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
}

static NSString *ZNM585RPreferenceKey(NSDictionary *feature,NSString *suffix){
    uint64_t featureID=[feature[@"featureID"] unsignedLongLongValue];
    NSString *identity=featureID?[NSString stringWithFormat:@"%016llx",featureID]:[feature[@"key"] description];
    return [NSString stringWithFormat:@"zn.fc.%@.%@",identity?:@"feature",suffix?:@"value"];
}

static NSDictionary *ZNM585REventInfo(NSDictionary *feature,NSNumber *value,NSString *valueText){
    NSMutableDictionary *info=[@{@"featureID":feature[@"featureID"]?:@0,@"title":feature[@"title"]?:@"功能",@"controlType":feature[@"controlType"]?:@(ZNFeatureControlTypeSwitch),@"valueType":feature[@"valueType"]?:@(ZNValueTypeAuto),@"key":feature[@"key"]?:@""} mutableCopy];
    if(value)info[@"value"]=value;if(valueText.length)info[@"valueText"]=valueText;return info;
}

@interface ZNRuntimeMenuControllerV040 (ZNM585StaticRuntimeRange)
- (void)znm585_rangeDecorateCompact:(BOOL)compact;
- (void)znm585_rangeSliderCommitted:(ZNRangeControl *)slider;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM585StaticRuntimeRange)
- (void)znm585_rangeDecorateCompact:(BOOL)compact {
    [self znm585_rangeDecorateCompact:compact];
    NSArray *features=ZNM585RFeatures();
    for(NSUInteger i=0;i<features.count;i++){
        NSDictionary *feature=features[i];
        if((ZNFeatureControlType)[feature[@"controlType"] unsignedIntValue]!=ZNFeatureControlTypeSlider)continue;
        ZNRangeControl *slider=(ZNRangeControl *)[self.contentView viewWithTag:kZNM585SliderTagBase+(NSInteger)i];
        if(![slider isKindOfClass:ZNRangeControl.class])continue;
        double max=[feature[@"sliderMax"] doubleValue];
        if(!isfinite(max)||max<=0.0)max=10.0;
        slider.minimumValue=0.0;
        slider.maximumValue=max;
        double stored=[NSUserDefaults.standardUserDefaults doubleForKey:ZNM585RPreferenceKey(feature,@"value")];
        if(!isfinite(stored))stored=0.0;
        slider.value=MAX(0.0,MIN(max,round(stored)));
        slider.accessibilityLabel=[NSString stringWithFormat:@"%@ 滑块 %@ 0-%.0f step 1",feature[@"title"]?:@"功能",ZNValueTypeName((ZNValueType)[feature[@"valueType"] integerValue]),max];
    }
}

- (void)znm585_rangeSliderCommitted:(ZNRangeControl *)slider {
    NSInteger index=slider.tag-kZNM585SliderTagBase;
    NSArray *features=ZNM585RFeatures();
    if(index<0||(NSUInteger)index>=features.count)return;
    NSDictionary *feature=features[(NSUInteger)index];
    double max=[feature[@"sliderMax"] doubleValue];
    if(!isfinite(max)||max<=0.0)max=10.0;
    double value=MAX(0.0,MIN(max,round(slider.value)));
    slider.value=value;
    NSString *text=[NSString stringWithFormat:@"%.0f",value];
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZNM585RPreferenceKey(feature,@"value")];
    [NSUserDefaults.standardUserDefaults setObject:text forKey:ZNM585RPreferenceKey(feature,@"valueText")];
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification object:self userInfo:ZNM585REventInfo(feature,@(value),text)];
}
@end

extern "C" void ZNInstallM585StaticRuntimeRangeDeferred(void){
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;
        Method d1=class_getInstanceMethod(cls,@selector(zn65fc_decorateCompact:));
        Method d2=class_getInstanceMethod(cls,@selector(znm585_rangeDecorateCompact:));
        if(d1&&d2)method_exchangeImplementations(d1,d2);
        Method c1=class_getInstanceMethod(cls,@selector(zn65fc_sliderCommitted:));
        Method c2=class_getInstanceMethod(cls,@selector(znm585_rangeSliderCommitted:));
        if(c1&&c2)method_exchangeImplementations(c1,c2);
        [[ZNRuntimeLogger sharedLogger]log:@"[m5.8.5] Static Slider runtime uses embedded authored max (min=0 step=1)"];
    });
}
