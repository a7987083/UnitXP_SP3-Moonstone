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

// M6.3 contract:
// Offset authoring is only an address source for resolving an exact IL2CPP method.
// New Number/Slider features MUST converge to Runtime Method actions.
// Direct numeric Static/Offset execution and raw-value fallback are forbidden.
// Legacy embedded Static records remain readable by the runtime for compatibility.

static NSString * const kZNM610SliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *ZNM610Trim(NSString *value) { return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSString *ZNM610FeatureName(ZNBinaryPatchRow *row) { NSString *group=ZNM610Trim(row.group);if(group.length&&[group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return group;NSString *title=ZNM610Trim(row.title);return title.length?title:@"功能"; }
static NSString *ZNM610FeatureDescription(ZNBinaryPatchRow *row) { NSString *group=ZNM610Trim(row.group),*title=ZNM610Trim(row.title);if(group.length&&[group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return title;return @""; }
static NSString *ZNM610SliderKey(NSString *featureName) { return [NSString stringWithFormat:@"%@.%@",kZNM610SliderMaxPrefix,ZNM610Trim(featureName).lowercaseString]; }

static BOOL ZNM610ParseRVA(NSString *text,uint64_t *out) {
    NSString *s=ZNM610Trim(text).lowercaseString;if(!s.length)return NO;const char *c=s.UTF8String;char *end=NULL;errno=0;unsigned long long v=strtoull(c,&end,0);if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}if(errno||end==c||(end&&*end))return NO;if(out)*out=(uint64_t)v;return YES;
}
static BOOL ZNM610IsNumericOffsetFeature(ZNBinaryPatchRow *row) { if(!row.offsetText.length)return NO;return row.featureControlType==ZNFeatureControlTypeNumber||row.featureControlType==ZNFeatureControlTypeSlider; }
static NSString *ZNM610CandidateIdentity(NSDictionary *candidate) { return [NSString stringWithFormat:@"%@|%@|%@|%@|%ld",[candidate[@"assembly"] isKindOfClass:NSString.class]?[candidate[@"assembly"] lowercaseString]:@"",[candidate[@"namespace"] isKindOfClass:NSString.class]?candidate[@"namespace"]:@"",[candidate[@"class"] isKindOfClass:NSString.class]?candidate[@"class"]:@"",[candidate[@"method"] isKindOfClass:NSString.class]?candidate[@"method"]:@"",(long)[candidate[@"argumentCount"] integerValue]]; }

static NSDictionary *ZNM610UniqueExactCandidate(uint64_t rva,NSString **reason) {
    NSString *resolveError=nil;NSArray<NSDictionary<NSString *,id> *> *resolved=[[ZNIL2CPPOwningMethodResolver sharedResolver]resolveRVA:rva limit:16 error:&resolveError];NSMutableDictionary<NSString *,NSDictionary *> *unique=[NSMutableDictionary dictionary];
    for(NSDictionary *candidate in resolved?:@[]){if([candidate[@"methodRVA"]unsignedLongLongValue]!=rva)continue;if([candidate[@"intraMethodOffset"]unsignedLongLongValue]!=0)continue;NSString *identity=ZNM610CandidateIdentity(candidate);if(identity.length&&!unique[identity])unique[identity]=candidate;}
    if(unique.count!=1){if(reason)*reason=unique.count>1?[NSString stringWithFormat:@"Offset 0x%llX 对应 %lu 个 exact 方法，拒绝猜测",rva,(unsigned long)unique.count]:[NSString stringWithFormat:@"Offset 0x%llX 不是唯一 exact IL2CPP 方法入口（%@）",rva,resolveError?:@"no candidate"];return nil;}return unique.allValues.firstObject;
}

static BOOL ZNM610SupportedNumericType(ZNValueType type) { switch(type){case ZNValueTypeI32:case ZNValueTypeU32:case ZNValueTypeI64:case ZNValueTypeU64:case ZNValueTypeF32:case ZNValueTypeF64:return YES;default:return NO;} }

static BOOL ZNM610PromoteRow(ZNBinaryPatchRow *row,ZNRuntimeActionStore *store,NSString **reason) {
    uint64_t rva=0;if(!ZNM610ParseRVA(row.offsetText,&rva)){if(reason)*reason=@"Offset 格式无法解析";return NO;}
    NSString *target=ZNM610Trim(row.explicitTarget?row.target:@"");if(target.length&&[target rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location==NSNotFound){if(reason)*reason=@"新建数值 Offset 只支持 UnityFramework exact IL2CPP method";return NO;}
    NSDictionary *candidate=ZNM610UniqueExactCandidate(rva,reason);if(!candidate)return NO;
    if([candidate[@"argumentCount"]integerValue]!=1){if(reason)*reason=@"该 exact method 不是单参数方法，不能映射为单个 Slider/Number";return NO;}
    NSString *sigError=nil;NSArray<NSString *> *types=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&sigError);if(types.count!=1){if(reason)*reason=[NSString stringWithFormat:@"参数签名不可用：%@",sigError?:@"unknown"];return NO;}
    ZNValueType authored=row.featureValueType,managed=ZNValueTypeForManagedTypeName(types.firstObject),effective=authored==ZNValueTypeAuto?managed:authored;if(!ZNM610SupportedNumericType(effective)){if(reason)*reason=[NSString stringWithFormat:@"参数 %@ 不是受支持数值类型",types.firstObject?:@"?"];return NO;}

    NSString *feature=ZNM610FeatureName(row),*description=ZNM610FeatureDescription(row),*argument=@"0";
    if(row.featureControlType==ZNFeatureControlTypeSlider){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM610SliderKey(feature)];double max=[stored isKindOfClass:NSNumber.class]?[stored doubleValue]:0.0;if(!isfinite(max)||max<=0.0){if(reason)*reason=@"Slider Max 无效";return NO;}argument=[NSString stringWithFormat:@"%.15g",max];}

    NSMutableDictionary *runtimeCandidate=[candidate mutableCopy];runtimeCandidate[@"parameterTypeNames"]=types;runtimeCandidate[@"signatureAvailable"]=@YES;
    NSUInteger before=[store actionsSnapshot].count;NSString *addError=nil;ZNRuntimeMethodAction *created=[store addMethodCandidate:runtimeCandidate title:feature argumentValues:@[argument] error:&addError];if(!created){if(reason)*reason=addError?:@"Runtime Action 创建失败";return NO;}NSUInteger index=[store actionsSnapshot].count-1;
    if(description.length&&![store updateGroup:description atIndex:index error:&addError]){[store removeActionAtIndex:index];if(reason)*reason=addError?:@"保存功能说明失败";return NO;}

    NSMutableDictionary *cfg=[created.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@YES;cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(row.featureControlType==ZNFeatureControlTypeSlider?ZNRuntimeArgumentControlTypeSlider:ZNRuntimeArgumentControlTypeNumber);cfg[@"valueType"]=ZNValueTypeKey(authored);
    if(row.featureControlType==ZNFeatureControlTypeSlider){NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:argument locale:@{NSLocaleDecimalSeparator:@"."}];cfg[@"min"]=@0;cfg[@"max"]=n;cfg[@"step"]=@1;cfg[@"default"]=n;}
    NSString *cfgError=nil;if(![store updateArgumentControlConfigs:@[[cfg copy]] atIndex:index error:&cfgError]){[store removeActionAtIndex:index];if(reason)*reason=cfgError?:@"Runtime 控件配置失败";return NO;}
    if([store actionsSnapshot].count!=before+1){[store removeActionAtIndex:index];if(reason)*reason=@"Runtime Action 数量异常";return NO;}
    if(reason)*reason=[NSString stringWithFormat:@"Offset 0x%llX → %@::%@(%@) → Runtime %@",rva,created.className?:@"",created.methodName?:@"",types.firstObject?:@"?",row.featureControlType==ZNFeatureControlTypeSlider?@"Slider":@"Number"];return YES;
}

@interface ZNStaticBinaryBuilder (ZNM610UnifiedFeatureModel)
+ (BOOL)znm610_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end
@implementation ZNStaticBinaryBuilder (ZNM610UnifiedFeatureModel)
+ (BOOL)znm610_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    ZNRuntimeActionStore *store=[ZNRuntimeActionStore sharedStore];NSUInteger initialActionCount=[store actionsSnapshot].count;NSArray<ZNBinaryPatchRow *> *originalRows=[workspace.rows copy];NSMutableArray<ZNBinaryPatchRow *> *promoted=[NSMutableArray array];NSMutableArray<NSString *> *promotionReports=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in originalRows){if(!ZNM610IsNumericOffsetFeature(row))continue;NSString *reason=nil;if(!ZNM610PromoteRow(row,store,&reason)){row.statusText=[NSString stringWithFormat:@"❌ %@",reason?:@"无法转换到 Runtime backend"];if(error)*error=[NSString stringWithFormat:@"%@：%@。M6.3 已删除普通 Offset 直接数值/Static fallback，请使用 exact IL2CPP method。",ZNM610FeatureName(row),reason?:@"无法解析"];while([store actionsSnapshot].count>initialActionCount)[store removeActionAtIndex:[store actionsSnapshot].count-1];return NO;}[promoted addObject:row];if(reason.length)[promotionReports addObject:reason];}
    for(ZNBinaryPatchRow *row in promoted)[workspace.rows removeObjectIdenticalTo:row];[workspace ensureDefaultRows];
    BOOL ok=[self znm610_buildWorkspace:workspace outputs:outputs report:report error:error];if(!ok){while([store actionsSnapshot].count>initialActionCount)[store removeActionAtIndex:[store actionsSnapshot].count-1];[workspace.rows removeAllObjects];[workspace.rows addObjectsFromArray:originalRows];[workspace updateDefaultTarget:workspace.defaultTarget];return NO;}
    if(promoted.count){[workspace updateDefaultTarget:workspace.defaultTarget];NSString *summary=[NSString stringWithFormat:@"M6.3：%lu 个 Offset 数值功能全部转换到 Runtime backend",(unsigned long)promoted.count];NSString *details=[promotionReports componentsJoinedByString:@"\n"];if(report){NSString *base=*report?:@"";*report=base.length?[base stringByAppendingFormat:@"\n%@%@",summary,details.length?[NSString stringWithFormat:@"\n%@",details]:@""]:summary;}workspace.lastStatus=summary;}return YES;
}
@end

extern "C" void ZNInstallM610UnifiedFeatureModelDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");Method a=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:));Method b=class_getClassMethod(builder,@selector(znm610_buildWorkspace:outputs:report:error:));if(a&&b)method_exchangeImplementations(a,b);[[ZNRuntimeLogger sharedLogger]log:@"[m6.3] Offset numeric authoring is Runtime-only; direct Static numeric fallback removed; description promoted with action"];} );
}
