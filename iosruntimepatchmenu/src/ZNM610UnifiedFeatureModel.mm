#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNIL2CPPOwningMethodResolver.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNRuntimeActionModel.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M6.4 unified authoring backend.
// Offset is only an address source for resolving an exact IL2CPP method.
// New authoring converges to Runtime Action controls; no direct Static numeric
// or Raw Patch fallback is allowed. Legacy embedded Static remains compatible.

static NSString * const kZNM640SliderPrefix  = @"zonoe.m5.8.5.static-slider-max.v1";
static NSString * const kZNM640ControlPrefix = @"zonoe.m6.4.offset-control.v1";
static NSString * const kZNM640ValuePrefix   = @"zonoe.m6.4.offset-fixed-value.v1";

static NSString *ZNM640Trim(NSString *v){return [v?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *ZNM640FeatureName(ZNBinaryPatchRow *row){NSString *g=ZNM640Trim(row.group);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return g;NSString *t=ZNM640Trim(row.title);return t.length?t:@"功能";}
static NSString *ZNM640FeatureDescription(ZNBinaryPatchRow *row){NSString *g=ZNM640Trim(row.group),*t=ZNM640Trim(row.title);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return t;return @"";}
static NSString *ZNM640Key(NSString *prefix,NSString *name){return [NSString stringWithFormat:@"%@.%@",prefix,ZNM640Trim(name).lowercaseString];}

static BOOL ZNM640ParseRVA(NSString *text,uint64_t *out){NSString *s=ZNM640Trim(text).lowercaseString;if(!s.length)return NO;const char *c=s.UTF8String;char *end=NULL;errno=0;unsigned long long v=strtoull(c,&end,0);if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}if(errno||end==c||(end&&*end))return NO;if(out)*out=(uint64_t)v;return YES;}

static ZNRuntimeArgumentControlType ZNM640OffsetControl(ZNBinaryPatchRow *row){NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:ZNM640Key(kZNM640ControlPrefix,ZNM640FeatureName(row))];if(saved.length)return ZNRuntimeArgumentControlTypeFromKey(saved);switch(row.featureControlType){case ZNFeatureControlTypeSlider:return ZNRuntimeArgumentControlTypeSlider;case ZNFeatureControlTypeSwitch:return ZNRuntimeArgumentControlTypeSwitch;case ZNFeatureControlTypeButton:return ZNRuntimeArgumentControlTypeButton;default:return ZNRuntimeArgumentControlTypeNumber;}}

static BOOL ZNM640IsAuthoredOffsetFeature(ZNBinaryPatchRow *row){if(!row.offsetText.length)return NO;NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:ZNM640Key(kZNM640ControlPrefix,ZNM640FeatureName(row))];if(saved.length)return YES;return row.featureControlType==ZNFeatureControlTypeNumber||row.featureControlType==ZNFeatureControlTypeSlider;}

static NSString *ZNM640CandidateIdentity(NSDictionary *c){return [NSString stringWithFormat:@"%@|%@|%@|%@|%ld",[c[@"assembly"] isKindOfClass:NSString.class]?[c[@"assembly"] lowercaseString]:@"",[c[@"namespace"] isKindOfClass:NSString.class]?c[@"namespace"]:@"",[c[@"class"] isKindOfClass:NSString.class]?c[@"class"]:@"",[c[@"method"] isKindOfClass:NSString.class]?c[@"method"]:@"",(long)[c[@"argumentCount"] integerValue]];}

static NSDictionary *ZNM640UniqueExactCandidate(uint64_t rva,NSString **reason){NSString *resolveError=nil;NSArray *resolved=[[ZNIL2CPPOwningMethodResolver sharedResolver]resolveRVA:rva limit:16 error:&resolveError];NSMutableDictionary *unique=[NSMutableDictionary dictionary];for(NSDictionary *c in resolved?:@[]){if([c[@"methodRVA"]unsignedLongLongValue]!=rva)continue;if([c[@"intraMethodOffset"]unsignedLongLongValue]!=0)continue;NSString *identity=ZNM640CandidateIdentity(c);if(identity.length&&!unique[identity])unique[identity]=c;}if(unique.count!=1){if(reason)*reason=unique.count>1?[NSString stringWithFormat:@"Offset 0x%llX 对应 %lu 个 exact 方法，拒绝猜测",rva,(unsigned long)unique.count]:[NSString stringWithFormat:@"Offset 0x%llX 不是唯一 exact IL2CPP 方法入口（%@）",rva,resolveError?:@"no candidate"];return nil;}return unique.allValues.firstObject;}

static BOOL ZNM640SupportedNumericType(ZNValueType t){switch(t){case ZNValueTypeI32:case ZNValueTypeU32:case ZNValueTypeI64:case ZNValueTypeU64:case ZNValueTypeF32:case ZNValueTypeF64:return YES;default:return NO;}}
static BOOL ZNM640LooksBool(NSString *type){NSString *s=type.lowercaseString;return [s containsString:@"boolean"]||[s isEqualToString:@"bool"]||[s hasSuffix:@".bool"];}

static BOOL ZNM640PromoteRow(ZNBinaryPatchRow *row,ZNRuntimeActionStore *store,NSString **reason){
    uint64_t rva=0;if(!ZNM640ParseRVA(row.offsetText,&rva)){if(reason)*reason=@"Offset 格式无法解析";return NO;}
    NSString *target=ZNM640Trim(row.explicitTarget?row.target:@"");
    if(target.length&&[target rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location==NSNotFound){if(reason)*reason=[NSString stringWithFormat:@"目标二进制 %@ 不是 UnityFramework，不能按 IL2CPP exact method 解析",target];return NO;}
    NSDictionary *candidate=ZNM640UniqueExactCandidate(rva,reason);if(!candidate)return NO;
    if([candidate[@"argumentCount"]integerValue]!=1){if(reason)*reason=@"当前统一控件要求 exact method 为单参数方法";return NO;}

    NSString *sigError=nil;NSArray<NSString *> *types=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&sigError);if(types.count!=1){if(reason)*reason=[NSString stringWithFormat:@"参数签名不可用：%@",sigError?:@"unknown"];return NO;}
    ZNRuntimeArgumentControlType control=ZNM640OffsetControl(row);
    ZNValueType authored=row.featureValueType,managed=ZNValueTypeForManagedTypeName(types.firstObject),effective=authored==ZNValueTypeAuto?managed:authored;
    if(control==ZNRuntimeArgumentControlTypeSwitch){if(!ZNM640LooksBool(types.firstObject)&&!ZNM640SupportedNumericType(effective)){if(reason)*reason=[NSString stringWithFormat:@"Switch 参数类型 %@ 不受支持",types.firstObject?:@"?"];return NO;}}
    else if(!ZNM640SupportedNumericType(effective)){if(reason)*reason=[NSString stringWithFormat:@"参数 %@ 不是受支持数值类型",types.firstObject?:@"?"];return NO;}

    NSString *feature=ZNM640FeatureName(row),*description=ZNM640FeatureDescription(row),*argument=@"0";
    if(control==ZNRuntimeArgumentControlTypeSlider){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM640Key(kZNM640SliderPrefix,feature)];double max=[stored isKindOfClass:NSNumber.class]?[stored doubleValue]:0.0;if(!isfinite(max)||max<=0){if(reason)*reason=@"Slider Max 无效";return NO;}argument=[NSString stringWithFormat:@"%.15g",max];}
    else if(control==ZNRuntimeArgumentControlTypeFixed||control==ZNRuntimeArgumentControlTypeButton){argument=[NSUserDefaults.standardUserDefaults stringForKey:ZNM640Key(kZNM640ValuePrefix,feature)]?:@"";if(!ZNM640Trim(argument).length){if(reason)*reason=[NSString stringWithFormat:@"%@ Value 不能为空",ZNRuntimeArgumentControlTypeName(control)];return NO;}}

    NSMutableDictionary *runtimeCandidate=[candidate mutableCopy];runtimeCandidate[@"parameterTypeNames"]=types;runtimeCandidate[@"signatureAvailable"]=@YES;
    NSUInteger before=[store actionsSnapshot].count;NSString *addError=nil;ZNRuntimeMethodAction *created=[store addMethodCandidate:runtimeCandidate title:feature argumentValues:@[argument] error:&addError];if(!created){if(reason)*reason=addError?:@"Runtime Action 创建失败";return NO;}NSUInteger index=[store actionsSnapshot].count-1;
    if(description.length&&![store updateGroup:description atIndex:index error:&addError]){[store removeActionAtIndex:index];if(reason)*reason=addError?:@"保存功能说明失败";return NO;}

    NSMutableDictionary *cfg=[created.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@(control!=ZNRuntimeArgumentControlTypeFixed);cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(control);cfg[@"valueType"]=ZNValueTypeKey(authored);
    if(control==ZNRuntimeArgumentControlTypeSlider){NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:argument locale:@{NSLocaleDecimalSeparator:@"."}];cfg[@"min"]=@0;cfg[@"max"]=n;cfg[@"step"]=@1;cfg[@"default"]=n;}
    NSString *cfgError=nil;if(![store updateArgumentControlConfigs:@[[cfg copy]] atIndex:index error:&cfgError]){[store removeActionAtIndex:index];if(reason)*reason=cfgError?:@"Runtime 控件配置失败";return NO;}
    if([store actionsSnapshot].count!=before+1){[store removeActionAtIndex:index];if(reason)*reason=@"Runtime Action 数量异常";return NO;}
    if(reason)*reason=[NSString stringWithFormat:@"Offset 0x%llX → %@::%@(%@) → Runtime %@",rva,created.className?:@"",created.methodName?:@"",types.firstObject?:@"?",ZNRuntimeArgumentControlTypeName(control)];return YES;
}

@interface ZNStaticBinaryBuilder (ZNM640UnifiedFeatureModel)
+ (BOOL)znm640_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end

@implementation ZNStaticBinaryBuilder (ZNM640UnifiedFeatureModel)
+ (BOOL)znm640_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    ZNRuntimeActionStore *store=[ZNRuntimeActionStore sharedStore];NSUInteger initial=[store actionsSnapshot].count;NSArray *original=[workspace.rows copy];NSMutableArray *promoted=[NSMutableArray array];NSMutableArray *details=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in original){if(!ZNM640IsAuthoredOffsetFeature(row))continue;NSString *reason=nil;if(!ZNM640PromoteRow(row,store,&reason)){row.statusText=[NSString stringWithFormat:@"❌ %@",reason?:@"无法转换 Runtime backend"];if(error)*error=[NSString stringWithFormat:@"%@：%@。M6.4 不提供普通 Offset/Raw Static fallback。",ZNM640FeatureName(row),reason?:@"无法解析"];while([store actionsSnapshot].count>initial)[store removeActionAtIndex:[store actionsSnapshot].count-1];return NO;}[promoted addObject:row];if(reason.length)[details addObject:reason];}
    for(ZNBinaryPatchRow *row in promoted)[workspace.rows removeObjectIdenticalTo:row];[workspace ensureDefaultRows];
    BOOL ok=[self znm640_buildWorkspace:workspace outputs:outputs report:report error:error];
    if(!ok){while([store actionsSnapshot].count>initial)[store removeActionAtIndex:[store actionsSnapshot].count-1];[workspace.rows removeAllObjects];[workspace.rows addObjectsFromArray:original];[workspace updateDefaultTarget:workspace.defaultTarget];return NO;}
    if(promoted.count){[workspace updateDefaultTarget:workspace.defaultTarget];NSString *summary=[NSString stringWithFormat:@"M6.4：%lu 个 Offset 功能已转换到 Runtime backend",(unsigned long)promoted.count];if(report){NSString *base=*report?:@"",*detail=[details componentsJoinedByString:@"\n"];*report=base.length?[base stringByAppendingFormat:@"\n%@%@",summary,detail.length?[NSString stringWithFormat:@"\n%@",detail]:@""]:summary;}workspace.lastStatus=summary;}
    return YES;
}
@end

extern "C" void ZNInstallM610UnifiedFeatureModelDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");Method a=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:));Method b=class_getClassMethod(builder,@selector(znm640_buildWorkspace:outputs:report:error:));if(a&&b)method_exchangeImplementations(a,b);[[ZNRuntimeLogger sharedLogger]log:@"[m6.4-model] Offset exact-method authoring supports Fixed/Number/Slider/Switch/Button; no direct Static fallback"];});}
