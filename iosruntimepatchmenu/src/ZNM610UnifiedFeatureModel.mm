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

static NSString * const kZNM641SliderPrefix  = @"zonoe.m5.8.5.static-slider-max.v1";
static NSString * const kZNM641ControlPrefix = @"zonoe.m6.4.1.control.v1";
static NSString * const kZNM641BackendPrefix = @"zonoe.m6.4.1.backend.v1";
static NSString * const kZNM641ValuePrefix   = @"zonoe.m6.4.offset-fixed-value.v1";

static NSString *ZNM641Trim(NSString *v){return [v?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *ZNM641FeatureName(ZNBinaryPatchRow *row){NSString *g=ZNM641Trim(row.group);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return g;NSString *t=ZNM641Trim(row.title);return t.length?t:@"功能";}
static NSString *ZNM641FeatureDescription(ZNBinaryPatchRow *row){NSString *g=ZNM641Trim(row.group),*t=ZNM641Trim(row.title);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return t;return @"";}
static NSString *ZNM641Key(NSString *prefix,NSString *name){return [NSString stringWithFormat:@"%@.%@",prefix,ZNM641Trim(name).lowercaseString];}
static BOOL ZNM641ParseRVA(NSString *text,uint64_t *out){NSString *s=ZNM641Trim(text).lowercaseString;if(!s.length)return NO;const char *c=s.UTF8String;char *end=NULL;errno=0;unsigned long long v=strtoull(c,&end,0);if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}if(errno||end==c||(end&&*end))return NO;if(out)*out=(uint64_t)v;return YES;}
static BOOL ZNM641RuntimeBackend(ZNBinaryPatchRow *row){NSString *name=ZNM641FeatureName(row);NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:ZNM641Key(kZNM641BackendPrefix,name)];if([saved isEqualToString:@"static"])return NO;if([saved isEqualToString:@"runtime"])return YES;return !row.enabledText.length;}
static ZNRuntimeArgumentControlType ZNM641RuntimeControl(ZNBinaryPatchRow *row){NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:ZNM641Key(kZNM641ControlPrefix,ZNM641FeatureName(row))];if(saved.length)return ZNRuntimeArgumentControlTypeFromKey(saved);switch(row.featureControlType){case ZNFeatureControlTypeSlider:return ZNRuntimeArgumentControlTypeSlider;case ZNFeatureControlTypeSwitch:return ZNRuntimeArgumentControlTypeSwitch;case ZNFeatureControlTypeButton:return ZNRuntimeArgumentControlTypeButton;default:return ZNRuntimeArgumentControlTypeNumber;}}
static BOOL ZNM641IsRuntimeFeature(ZNBinaryPatchRow *row){return row.offsetText.length&&ZNM641RuntimeBackend(row);}
static NSString *ZNM641CandidateIdentity(NSDictionary *c){return [NSString stringWithFormat:@"%@|%@|%@|%@|%ld",[c[@"assembly"] isKindOfClass:NSString.class]?[c[@"assembly"] lowercaseString]:@"",[c[@"namespace"] isKindOfClass:NSString.class]?c[@"namespace"]:@"",[c[@"class"] isKindOfClass:NSString.class]?c[@"class"]:@"",[c[@"method"] isKindOfClass:NSString.class]?c[@"method"]:@"",(long)[c[@"argumentCount"] integerValue]];}
static NSDictionary *ZNM641UniqueExactCandidate(uint64_t rva,NSString **reason){NSString *resolveError=nil;NSArray *resolved=[[ZNIL2CPPOwningMethodResolver sharedResolver]resolveRVA:rva limit:16 error:&resolveError];NSMutableDictionary *unique=[NSMutableDictionary dictionary];for(NSDictionary *c in resolved?:@[]){if([c[@"methodRVA"]unsignedLongLongValue]!=rva)continue;if([c[@"intraMethodOffset"]unsignedLongLongValue]!=0)continue;NSString *identity=ZNM641CandidateIdentity(c);if(identity.length&&!unique[identity])unique[identity]=c;}if(unique.count!=1){if(reason)*reason=unique.count>1?[NSString stringWithFormat:@"Offset 0x%llX 对应 %lu 个 exact 方法，拒绝猜测",rva,(unsigned long)unique.count]:[NSString stringWithFormat:@"Offset 0x%llX 不是唯一 exact IL2CPP 方法入口（%@）",rva,resolveError?:@"no candidate"];return nil;}return unique.allValues.firstObject;}
static BOOL ZNM641SupportedNumericType(ZNValueType t){switch(t){case ZNValueTypeI32:case ZNValueTypeU32:case ZNValueTypeI64:case ZNValueTypeU64:case ZNValueTypeF32:case ZNValueTypeF64:return YES;default:return NO;}}
static BOOL ZNM641LooksBool(NSString *type){NSString *s=type.lowercaseString;return [s containsString:@"boolean"]||[s isEqualToString:@"bool"]||[s hasSuffix:@".bool"];}

static BOOL ZNM641PromoteRow(ZNBinaryPatchRow *row,ZNRuntimeActionStore *store,NSString **reason){
    uint64_t rva=0;if(!ZNM641ParseRVA(row.offsetText,&rva)){if(reason)*reason=@"Offset 格式无法解析";return NO;}
    NSString *target=ZNM641Trim(row.explicitTarget?row.target:@"");if(target.length&&[target rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location==NSNotFound){if(reason)*reason=[NSString stringWithFormat:@"Runtime Method backend 当前要求 UnityFramework；目标为 %@",target];return NO;}
    NSDictionary *candidate=ZNM641UniqueExactCandidate(rva,reason);if(!candidate)return NO;
    if([candidate[@"argumentCount"]integerValue]!=1){if(reason)*reason=@"当前 Runtime 控件要求 exact method 为单参数方法";return NO;}
    NSString *sigError=nil;NSArray<NSString *> *types=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&sigError);if(types.count!=1){if(reason)*reason=[NSString stringWithFormat:@"参数签名不可用：%@",sigError?:@"unknown"];return NO;}
    ZNRuntimeArgumentControlType control=ZNM641RuntimeControl(row);ZNValueType authored=row.featureValueType,managed=ZNValueTypeForManagedTypeName(types.firstObject),effective=authored==ZNValueTypeAuto?managed:authored;
    if(control==ZNRuntimeArgumentControlTypeSwitch){if(!ZNM641LooksBool(types.firstObject)&&!ZNM641SupportedNumericType(effective)){if(reason)*reason=[NSString stringWithFormat:@"Switch 参数类型 %@ 不受支持",types.firstObject?:@"?"];return NO;}}
    else if(!ZNM641SupportedNumericType(effective)){if(reason)*reason=[NSString stringWithFormat:@"参数 %@ 不是受支持数值类型",types.firstObject?:@"?"];return NO;}
    NSString *feature=ZNM641FeatureName(row),*description=ZNM641FeatureDescription(row),*argument=@"0";
    if(control==ZNRuntimeArgumentControlTypeSlider){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM641Key(kZNM641SliderPrefix,feature)];double max=[stored isKindOfClass:NSNumber.class]?[stored doubleValue]:0.0;if(!isfinite(max)||max<=0){if(reason)*reason=@"Slider Max 无效";return NO;}argument=[NSString stringWithFormat:@"%.15g",max];}
    else if(control==ZNRuntimeArgumentControlTypeFixed||control==ZNRuntimeArgumentControlTypeButton){argument=[NSUserDefaults.standardUserDefaults stringForKey:ZNM641Key(kZNM641ValuePrefix,feature)]?:@"";if(!ZNM641Trim(argument).length){if(reason)*reason=[NSString stringWithFormat:@"%@ Value 不能为空",ZNRuntimeArgumentControlTypeName(control)];return NO;}}
    NSMutableDictionary *runtimeCandidate=[candidate mutableCopy];runtimeCandidate[@"parameterTypeNames"]=types;runtimeCandidate[@"signatureAvailable"]=@YES;
    NSUInteger before=[store actionsSnapshot].count;NSString *addError=nil;ZNRuntimeMethodAction *created=[store addMethodCandidate:runtimeCandidate title:feature argumentValues:@[argument] error:&addError];if(!created){if(reason)*reason=addError?:@"Runtime Action 创建失败";return NO;}NSUInteger index=[store actionsSnapshot].count-1;
    if(description.length&&![store updateGroup:description atIndex:index error:&addError]){[store removeActionAtIndex:index];if(reason)*reason=addError?:@"保存功能说明失败";return NO;}
    NSMutableDictionary *cfg=[created.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@(control!=ZNRuntimeArgumentControlTypeFixed);cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(control);cfg[@"valueType"]=ZNValueTypeKey(authored);if(control==ZNRuntimeArgumentControlTypeSlider){NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:argument locale:@{NSLocaleDecimalSeparator:@"."}];cfg[@"min"]=@0;cfg[@"max"]=n;cfg[@"step"]=@1;cfg[@"default"]=n;}
    NSString *cfgError=nil;if(![store updateArgumentControlConfigs:@[[cfg copy]] atIndex:index error:&cfgError]){[store removeActionAtIndex:index];if(reason)*reason=cfgError?:@"Runtime 控件配置失败";return NO;}if([store actionsSnapshot].count!=before+1){[store removeActionAtIndex:index];if(reason)*reason=@"Runtime Action 数量异常";return NO;}
    if(reason)*reason=[NSString stringWithFormat:@"Offset 0x%llX → %@::%@(%@) → Runtime %@",rva,created.className?:@"",created.methodName?:@"",types.firstObject?:@"?",ZNRuntimeArgumentControlTypeName(control)];return YES;
}

@interface ZNStaticBinaryBuilder (ZNM641UnifiedBackendModel)
+ (BOOL)znm641_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end
@implementation ZNStaticBinaryBuilder (ZNM641UnifiedBackendModel)
+ (BOOL)znm641_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    ZNRuntimeActionStore *store=[ZNRuntimeActionStore sharedStore];NSUInteger initial=[store actionsSnapshot].count;NSArray *original=[workspace.rows copy];NSMutableArray *promoted=[NSMutableArray array];NSMutableArray *details=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in original){if(!ZNM641IsRuntimeFeature(row))continue;NSString *reason=nil;if(!ZNM641PromoteRow(row,store,&reason)){row.statusText=[NSString stringWithFormat:@"❌ %@",reason?:@"无法转换 Runtime backend"];if(error)*error=[NSString stringWithFormat:@"%@：%@。如目标不是 IL2CPP，请把 Backend 切换为 Static Patch。",ZNM641FeatureName(row),reason?:@"无法解析"];while([store actionsSnapshot].count>initial)[store removeActionAtIndex:[store actionsSnapshot].count-1];return NO;}[promoted addObject:row];if(reason.length)[details addObject:reason];}
    for(ZNBinaryPatchRow *row in promoted)[workspace.rows removeObjectIdenticalTo:row];[workspace ensureDefaultRows];BOOL ok=[self znm641_buildWorkspace:workspace outputs:outputs report:report error:error];if(!ok){while([store actionsSnapshot].count>initial)[store removeActionAtIndex:[store actionsSnapshot].count-1];[workspace.rows removeAllObjects];[workspace.rows addObjectsFromArray:original];[workspace updateDefaultTarget:workspace.defaultTarget];return NO;}
    if(promoted.count){[workspace updateDefaultTarget:workspace.defaultTarget];NSString *summary=[NSString stringWithFormat:@"M6.4.1：%lu 个 Runtime Method 功能已解析；Static Patch 保持 Static backend",(unsigned long)promoted.count];if(report){NSString *base=*report?:@"",*detail=[details componentsJoinedByString:@"\n"];*report=base.length?[base stringByAppendingFormat:@"\n%@%@",summary,detail.length?[NSString stringWithFormat:@"\n%@",detail]:@""]:summary;}workspace.lastStatus=summary;}return YES;
}
@end

extern "C" void ZNInstallM640AuthoringValidationBridgeDeferred(void){[[ZNRuntimeLogger sharedLogger]log:@"[m6.4.1-validation] backend choice is explicit; Static is not routed through IL2CPP resolver"];}
extern "C" void ZNInstallM610UnifiedFeatureModelDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");Method a=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:));Method b=class_getClassMethod(builder,@selector(znm641_buildWorkspace:outputs:report:error:));if(a&&b)method_exchangeImplementations(a,b);[[ZNRuntimeLogger sharedLogger]log:@"[m6.4.1-model] Runtime Method and Static Patch are explicit peer backends"];} );}
