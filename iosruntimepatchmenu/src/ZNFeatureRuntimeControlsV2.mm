#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

static const NSInteger kZN65ToggleTagBase = 450000;
static const NSInteger kZN65NumberTagBase = 469000;
static const NSInteger kZN65ActionTagBase = 470000;
static const NSInteger kZN65SliderTagBase = 471000;

@interface ZNStaticPatchRecord (ZNFeatureRuntimeControlEntry)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static NSString *ZN65Trim(NSString *value) { return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSDictionary<NSString *, id> *ZN65DisplayMetadata(ZNStaticPatchRecord *record) {
    NSDictionary *embedded = ZNFeatureMetadataDecodeEntry(record.entry); if (embedded) return embedded;
    NSString *title=ZN65Trim(record.title),*group=ZN65Trim(record.group); if(!title.length||[title hasPrefix:@"Patch #"])title=[NSString stringWithFormat:@"功能 #%u",record.patchID]; if(!group.length)group=@"Imported";
    return @{@"featureID":@0,@"title":title,@"group":group,@"explicitGroup":@([group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame),@"controlType":@(ZNFeatureControlTypeSwitch),@"valueType":@(ZNValueTypeAuto)};
}
static NSArray<NSDictionary *> *ZN65FeatureGroups(void) {
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];[runtime refresh];NSMutableArray<NSString *> *order=[NSMutableArray array];NSMutableDictionary *members=[NSMutableDictionary dictionary],*metadata=[NSMutableDictionary dictionary];
    for(ZNStaticPatchRecord *record in runtime.records){NSDictionary *display=ZN65DisplayMetadata(record);NSString *group=ZN65Trim(display[@"group"]),*title=ZN65Trim(display[@"title"]);uint64_t featureID=[display[@"featureID"] unsignedLongLongValue];BOOL explicitFeature=[display[@"explicitGroup"] boolValue]||(group.length&&[group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame);NSString *key=featureID?[NSString stringWithFormat:@"id:%016llx",featureID]:(explicitFeature?[@"group:" stringByAppendingString:group.lowercaseString]:[NSString stringWithFormat:@"patch:%@:%u",record.target.lowercaseString?:@"",record.patchID]);if(!members[key]){members[key]=[NSMutableArray array];ZNFeatureControlType ct=record.entry?ZNFeatureControlTypeFromFlags(record.entry->flags):ZNFeatureControlTypeSwitch;ZNValueType vt=record.entry?ZNFeatureValueTypeFromFlags(record.entry->flags):ZNValueTypeAuto;metadata[key]=[@{@"key":key,@"featureID":@(featureID),@"title":explicitFeature&&group.length?group:(title.length?title:@"功能"),@"controlType":@(ct),@"valueType":@(vt)} mutableCopy];[order addObject:key];}[members[key] addObject:record];}
    NSMutableArray *out=[NSMutableArray array];for(NSString *key in order){NSMutableDictionary *item=[metadata[key] mutableCopy];item[@"records"]=[members[key] copy];[out addObject:[item copy]];}return out;
}
static NSString *ZN65PreferenceKey(NSDictionary *feature,NSString *suffix){uint64_t featureID=[feature[@"featureID"] unsignedLongLongValue];NSString *identity=featureID?[NSString stringWithFormat:@"%016llx",featureID]:[feature[@"key"] description];return [NSString stringWithFormat:@"zn.fc.%@.%@",identity?:@"feature",suffix?:@"value"];}
static double ZN65StoredValue(NSDictionary *feature,double fallback){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZN65PreferenceKey(feature,@"value")];return [stored isKindOfClass:NSNumber.class]?[stored doubleValue]:fallback;}
static NSString *ZN65StoredText(NSDictionary *feature,NSString *fallback){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZN65PreferenceKey(feature,@"valueText")];return [stored isKindOfClass:NSString.class]&&[(NSString *)stored length]?(NSString *)stored:(fallback?:@"1");}
static NSDictionary *ZN65EventInfo(NSDictionary *feature,NSNumber *value,NSString *valueText){NSMutableDictionary *info=[@{@"featureID":feature[@"featureID"]?:@0,@"title":feature[@"title"]?:@"功能",@"controlType":feature[@"controlType"]?:@(ZNFeatureControlTypeSwitch),@"valueType":feature[@"valueType"]?:@(ZNValueTypeAuto),@"key":feature[@"key"]?:@""} mutableCopy];if(value)info[@"value"]=value;if(valueText.length)info[@"valueText"]=valueText;return info;}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureRuntimeControlsV2)
- (void)zn65fc_renderFull; - (void)zn65fc_renderCompact; - (void)zn65fc_numberChanged:(UITextField *)field; - (void)zn65fc_actionTapped:(UIButton *)button; - (void)zn65fc_sliderChanged:(UISlider *)slider;
@end
@implementation ZNRuntimeMenuControllerV040 (ZNFeatureRuntimeControlsV2)
- (void)zn65fc_decorateCompact:(BOOL)compact {
    NSArray *features=ZN65FeatureGroups();for(NSUInteger i=0;i<features.count;i++){NSDictionary *feature=features[i];ZNFeatureControlType type=(ZNFeatureControlType)[feature[@"controlType"] unsignedIntValue];if(type==ZNFeatureControlTypeSwitch)continue;UIView *old=[self.contentView viewWithTag:kZN65ToggleTagBase+(NSInteger)i],*card=old.superview;if(!old||!card)continue;CGRect oldFrame=old.frame;[old removeFromSuperview];ZNValueType valueType=(ZNValueType)[feature[@"valueType"] integerValue];
        if(type==ZNFeatureControlTypeNumber){CGFloat width=compact?72:78;UITextField *field=[[UITextField alloc]initWithFrame:CGRectMake(CGRectGetWidth(card.bounds)-width-(compact?9:12),oldFrame.origin.y,width,oldFrame.size.height)];field.tag=kZN65NumberTagBase+(NSInteger)i;double stored=ZN65StoredValue(feature,1);NSString *fallback=ZNValueTypeIsInteger(valueType)||valueType==ZNValueTypeAuto?[NSString stringWithFormat:@"%.0f",stored]:[NSString stringWithFormat:@"%.6g",stored];field.text=ZN65StoredText(feature,fallback);field.textAlignment=NSTextAlignmentCenter;field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;field.textColor=self.theme.primaryTextColor;field.backgroundColor=[self.theme.controlColor colorWithAlphaComponent:.82];field.font=[UIFont systemFontOfSize:(compact?9:9.6) weight:UIFontWeightSemibold];field.layer.cornerRadius=7;field.layer.borderWidth=1;field.layer.borderColor=self.theme.borderColor.CGColor;[field addTarget:self action:@selector(zn65fc_numberChanged:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];field.accessibilityLabel=[NSString stringWithFormat:@"%@ 数值 %@",feature[@"title"]?:@"功能",ZNValueTypeName(valueType)];[card addSubview:field];
        }else if(type==ZNFeatureControlTypeButton){UIButton *button=[self zn40_button:@"执行" selector:@selector(zn65fc_actionTapped:) frame:oldFrame];button.tag=kZN65ActionTagBase+(NSInteger)i;[card addSubview:button];
        }else if(type==ZNFeatureControlTypeSlider){CGFloat width=compact?88:112;UISlider *slider=[[UISlider alloc]initWithFrame:CGRectMake(CGRectGetWidth(card.bounds)-width-(compact?7:10),oldFrame.origin.y,width,oldFrame.size.height)];slider.tag=kZN65SliderTagBase+(NSInteger)i;slider.minimumValue=1;slider.maximumValue=10;slider.value=(float)MIN(10.0,MAX(1.0,round(ZN65StoredValue(feature,1))));slider.minimumTrackTintColor=self.theme.accentColor;[slider addTarget:self action:@selector(zn65fc_sliderChanged:) forControlEvents:UIControlEventValueChanged];slider.accessibilityLabel=[NSString stringWithFormat:@"%@ 滑块 %@ 1-10 step 1",feature[@"title"]?:@"功能",ZNValueTypeName(valueType)];[card addSubview:slider];}
    }
}
- (void)zn65fc_renderFull{[self zn65fc_renderFull];[self zn65fc_decorateCompact:NO];}
- (void)zn65fc_renderCompact{[self zn65fc_renderCompact];[self zn65fc_decorateCompact:YES];}
- (void)zn65fc_numberChanged:(UITextField *)field {
    NSInteger index=field.tag-kZN65NumberTagBase;NSArray *features=ZN65FeatureGroups();if(index<0||(NSUInteger)index>=features.count)return;NSDictionary *feature=features[(NSUInteger)index];ZNValueType type=(ZNValueType)[feature[@"valueType"] integerValue];if(type==ZNValueTypeAuto)type=ZNValueTypeI32;NSDictionary *range=ZNDefaultRangeForValueType(type,NO);NSString *err=nil,*canonical=ZNCanonicalValueString(field.text,type,range[@"min"],range[@"max"],range[@"step"],&err);if(!canonical){field.text=ZN65StoredText(feature,@"1");[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.5-typed] static number rejected: %@",err?:@"invalid"]];return;}[NSUserDefaults.standardUserDefaults setObject:canonical forKey:ZN65PreferenceKey(feature,@"valueText")];[NSUserDefaults.standardUserDefaults setDouble:canonical.doubleValue forKey:ZN65PreferenceKey(feature,@"value")];field.text=canonical;[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureNumberValueDidChangeNotification object:self userInfo:ZN65EventInfo(feature,@(canonical.doubleValue),canonical)];
}
- (void)zn65fc_actionTapped:(UIButton *)button {NSInteger index=button.tag-kZN65ActionTagBase;NSArray *features=ZN65FeatureGroups();if(index<0||(NSUInteger)index>=features.count)return;NSDictionary *feature=features[(NSUInteger)index];[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureActionRequestedNotification object:self userInfo:ZN65EventInfo(feature,nil,nil)];}
- (void)zn65fc_sliderChanged:(UISlider *)slider {NSInteger index=slider.tag-kZN65SliderTagBase;NSArray *features=ZN65FeatureGroups();if(index<0||(NSUInteger)index>=features.count)return;NSDictionary *feature=features[(NSUInteger)index];double value=MAX(1.0,MIN(10.0,round(slider.value)));slider.value=(float)value;NSString *text=[NSString stringWithFormat:@"%.0f",value];[NSUserDefaults.standardUserDefaults setDouble:value forKey:ZN65PreferenceKey(feature,@"value")];[NSUserDefaults.standardUserDefaults setObject:text forKey:ZN65PreferenceKey(feature,@"valueText")];[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification object:self userInfo:ZN65EventInfo(feature,@(value),text)];}
@end
extern "C" void ZNInstallFeatureRuntimeControlsV2Deferred(void){static dispatch_once_t onceToken;dispatch_once(&onceToken,^{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;Method a=class_getInstanceMethod(cls,@selector(zn50_renderFeatureGroupsFull)),b=class_getInstanceMethod(cls,@selector(zn65fc_renderFull));if(a&&b)method_exchangeImplementations(a,b);Method c=class_getInstanceMethod(cls,@selector(zn50_renderFeatureGroupsCompact)),d=class_getInstanceMethod(cls,@selector(zn65fc_renderCompact));if(c&&d)method_exchangeImplementations(c,d);});}
