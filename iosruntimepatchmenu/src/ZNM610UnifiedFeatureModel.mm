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

// M6.1 — Unified Feature Model, phase 1.
//
// Authoring remains on the existing single Builder surface. Before generation,
// an Offset Number/Slider feature targeting an exact, unambiguous one-argument
// IL2CPP method is promoted to the proven Runtime Method backend. The source
// Offset row is removed only after promotion succeeds. If resolution is not
// exact/unambiguous/typed, the row is left untouched and continues through the
// safe Static/Offset backend from M6.0.
//
// This intentionally does NOT create another UI/controller hierarchy.

static NSString * const kZNM610SliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *ZNM610Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM610FeatureName(ZNBinaryPatchRow *row) {
    NSString *group=ZNM610Trim(row.group);
    if(group.length && [group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return group;
    NSString *title=ZNM610Trim(row.title);
    return title.length?title:@"功能";
}

static NSString *ZNM610SliderKey(NSString *featureName) {
    return [NSString stringWithFormat:@"%@.%@",kZNM610SliderMaxPrefix,ZNM610Trim(featureName).lowercaseString];
}

static BOOL ZNM610ParseRVA(NSString *text,uint64_t *out) {
    NSString *s=ZNM610Trim(text).lowercaseString;
    if(!s.length)return NO;
    const char *c=s.UTF8String;char *end=NULL;errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}
    if(errno||end==c||(end&&*end))return NO;
    if(out)*out=(uint64_t)v;
    return YES;
}

static BOOL ZNM610IsConvertibleControl(ZNBinaryPatchRow *row) {
    if(!row.offsetText.length)return NO;
    ZNFeatureControlType type=row.featureControlType;
    return type==ZNFeatureControlTypeNumber||type==ZNFeatureControlTypeSlider;
}

static NSString *ZNM610CandidateIdentity(NSDictionary *candidate) {
    NSString *assembly=[candidate[@"assembly"] isKindOfClass:NSString.class]?candidate[@"assembly"]:@"";
    NSString *ns=[candidate[@"namespace"] isKindOfClass:NSString.class]?candidate[@"namespace"]:@"";
    NSString *cls=[candidate[@"class"] isKindOfClass:NSString.class]?candidate[@"class"]:@"";
    NSString *method=[candidate[@"method"] isKindOfClass:NSString.class]?candidate[@"method"]:@"";
    NSInteger argc=[candidate[@"argumentCount"] integerValue];
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%ld",assembly.lowercaseString,ns,cls,method,(long)argc];
}

static NSDictionary *ZNM610UniqueExactCandidate(uint64_t rva,NSString **reason) {
    NSString *resolveError=nil;
    NSArray<NSDictionary<NSString *,id> *> *resolved=[[ZNIL2CPPOwningMethodResolver sharedResolver] resolveRVA:rva limit:16 error:&resolveError];
    NSMutableDictionary<NSString *,NSDictionary *> *unique=[NSMutableDictionary dictionary];
    for(NSDictionary *candidate in resolved?:@[]) {
        if([candidate[@"methodRVA"] unsignedLongLongValue]!=rva)continue;
        if([candidate[@"intraMethodOffset"] unsignedLongLongValue]!=0)continue;
        NSString *identity=ZNM610CandidateIdentity(candidate);
        if(identity.length&&!unique[identity])unique[identity]=candidate;
    }
    if(unique.count!=1) {
        if(reason) {
            if(unique.count>1)*reason=[NSString stringWithFormat:@"exact RVA 对应 %lu 个方法身份，保留 Offset backend",(unsigned long)unique.count];
            else *reason=[NSString stringWithFormat:@"未解析到 exact IL2CPP method，保留 Offset backend（%@）",resolveError?:@"no candidate"];
        }
        return nil;
    }
    return unique.allValues.firstObject;
}

static BOOL ZNM610SupportedNumericType(ZNValueType type) {
    switch(type) {
        case ZNValueTypeI32:case ZNValueTypeU32:case ZNValueTypeI64:case ZNValueTypeU64:case ZNValueTypeF32:case ZNValueTypeF64:return YES;
        default:return NO;
    }
}

static NSString *ZNM610DefaultTextForType(ZNValueType type) {
    return (type==ZNValueTypeF32||type==ZNValueTypeF64)?@"0":@"0";
}

static BOOL ZNM610PromoteRow(ZNBinaryPatchRow *row,
                             ZNRuntimeActionStore *store,
                             NSUInteger *createdIndex,
                             NSString **reason) {
    uint64_t rva=0;
    if(!ZNM610ParseRVA(row.offsetText,&rva)) { if(reason)*reason=@"Offset 格式无法解析"; return NO; }
    NSString *target=ZNM610Trim(row.explicitTarget?row.target:@"");
    if(target.length && [target rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location==NSNotFound) {
        if(reason)*reason=@"非 UnityFramework Offset，保留 Static backend";
        return NO;
    }

    NSDictionary *candidate=ZNM610UniqueExactCandidate(rva,reason);
    if(!candidate)return NO;
    NSInteger argc=[candidate[@"argumentCount"] integerValue];
    if(argc!=1) { if(reason)*reason=[NSString stringWithFormat:@"exact method argc=%ld，不自动映射单控件",(long)argc]; return NO; }

    NSString *sigError=nil;
    NSArray<NSString *> *types=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&sigError);
    if(types.count!=1) { if(reason)*reason=[NSString stringWithFormat:@"完整参数签名不可用，保留 Offset backend（%@）",sigError?:@"unknown"] ; return NO; }

    ZNValueType authored=row.featureValueType;
    ZNValueType managed=ZNValueTypeForManagedTypeName(types.firstObject);
    ZNValueType effective=authored==ZNValueTypeAuto?managed:authored;
    if(!ZNM610SupportedNumericType(effective)) {
        if(reason)*reason=[NSString stringWithFormat:@"参数 %@ 不是受支持数值类型",types.firstObject?:@"?"];
        return NO;
    }

    NSString *feature=ZNM610FeatureName(row);
    NSString *argument=ZNM610DefaultTextForType(effective);
    if(row.featureControlType==ZNFeatureControlTypeSlider) {
        id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM610SliderKey(feature)];
        double max=[stored isKindOfClass:NSNumber.class]?[stored doubleValue]:0.0;
        if(!isfinite(max)||max<=0.0) { if(reason)*reason=@"Slider Max 无效"; return NO; }
        argument=[NSString stringWithFormat:@"%.15g",max];
    }

    NSMutableDictionary *runtimeCandidate=[candidate mutableCopy];
    runtimeCandidate[@"parameterTypeNames"]=types;
    runtimeCandidate[@"signatureAvailable"]=@YES;

    NSUInteger before=[store actionsSnapshot].count;
    NSString *addError=nil;
    ZNRuntimeMethodAction *created=[store addMethodCandidate:runtimeCandidate title:feature argumentValues:@[argument] error:&addError];
    if(!created) { if(reason)*reason=addError?:@"Runtime Action 创建失败"; return NO; }
    NSUInteger index=[store actionsSnapshot].count-1;

    NSMutableDictionary *cfg=[created.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];
    cfg[@"enabled"]=@YES;
    cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(row.featureControlType==ZNFeatureControlTypeSlider?ZNRuntimeArgumentControlTypeSlider:ZNRuntimeArgumentControlTypeNumber);
    cfg[@"valueType"]=ZNValueTypeKey(authored);
    if(row.featureControlType==ZNFeatureControlTypeSlider) {
        NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:argument locale:@{NSLocaleDecimalSeparator:@"."}];
        cfg[@"min"]=@0;cfg[@"max"]=n;cfg[@"step"]=@1;cfg[@"default"]=n;
    }
    NSString *cfgError=nil;
    if(![store updateArgumentControlConfigs:@[[cfg copy]] atIndex:index error:&cfgError]) {
        [store removeActionAtIndex:index];
        if(reason)*reason=cfgError?:@"Runtime 控件配置失败";
        return NO;
    }

    if(createdIndex)*createdIndex=index;
    if(reason)*reason=[NSString stringWithFormat:@"%@::%@(%@) · Offset 0x%llX → Runtime %@",
                       created.className?:@"",created.methodName?:@"",types.firstObject?:@"?",rva,
                       row.featureControlType==ZNFeatureControlTypeSlider?@"Slider":@"Number"];
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.1-model] promoted %@",*reason?:@""]];
    return [store actionsSnapshot].count==before+1;
}

@interface ZNStaticBinaryBuilder (ZNM610UnifiedFeatureModel)
+ (BOOL)znm610_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
                      outputs:(NSArray<NSString *> **)outputs
                       report:(NSString **)report
                        error:(NSString **)error;
@end

@implementation ZNStaticBinaryBuilder (ZNM610UnifiedFeatureModel)
+ (BOOL)znm610_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
                      outputs:(NSArray<NSString *> **)outputs
                       report:(NSString **)report
                        error:(NSString **)error {
    ZNRuntimeActionStore *store=[ZNRuntimeActionStore sharedStore];
    NSUInteger initialActionCount=[store actionsSnapshot].count;
    NSArray<ZNBinaryPatchRow *> *originalRows=[workspace.rows copy];
    NSMutableArray<ZNBinaryPatchRow *> *promoted=[NSMutableArray array];
    NSMutableArray<NSString *> *promotionReports=[NSMutableArray array];

    for(ZNBinaryPatchRow *row in originalRows) {
        if(!ZNM610IsConvertibleControl(row))continue;
        NSString *reason=nil;NSUInteger createdIndex=NSNotFound;
        if(ZNM610PromoteRow(row,store,&createdIndex,&reason)) {
            [promoted addObject:row];
            if(reason.length)[promotionReports addObject:reason];
        } else {
            row.statusText=reason.length?[NSString stringWithFormat:@"Offset backend · %@",reason]:@"Offset backend";
            [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.1-model] keep static %@ offset=%@ reason=%@",ZNM610FeatureName(row),row.offsetText?:@"",reason?:@"unknown"]];
        }
    }

    for(ZNBinaryPatchRow *row in promoted)[workspace.rows removeObjectIdenticalTo:row];
    [workspace ensureDefaultRows];

    BOOL ok=[self znm610_buildWorkspace:workspace outputs:outputs report:report error:error];
    if(!ok) {
        NSArray *current=[store actionsSnapshot];
        while(current.count>initialActionCount) {
            [store removeActionAtIndex:current.count-1];
            current=[store actionsSnapshot];
        }
        [workspace.rows removeAllObjects];
        [workspace.rows addObjectsFromArray:originalRows];
        [workspace updateDefaultTarget:workspace.defaultTarget];
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.1-model] build failed; promoted actions/rows rolled back"];
        return NO;
    }

    if(promoted.count) {
        // Trigger M5.9.2's existing persistence swizzle without introducing a
        // second persistence registry. Successfully promoted Offset rows are
        // now Runtime authoring records and are removed from Static authoring.
        [workspace updateDefaultTarget:workspace.defaultTarget];
        NSString *summary=[NSString stringWithFormat:@"M6.1：已将 %lu 个 exact Offset 功能统一到 Runtime backend",(unsigned long)promoted.count];
        NSString *details=[promotionReports componentsJoinedByString:@"\n"];
        if(report) {
            NSString *base=*report?:@"";
            *report=base.length?[base stringByAppendingFormat:@"\n%@%@",summary,details.length?[NSString stringWithFormat:@"\n%@",details]:@""]:[summary stringByAppendingFormat:@"%@",details.length?[NSString stringWithFormat:@"\n%@",details]:@""];
        }
        workspace.lastStatus=summary;
    }
    return YES;
}
@end

extern "C" void ZNInstallM610UnifiedFeatureModelDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");
        Method a=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:));
        Method b=class_getClassMethod(builder,@selector(znm610_buildWorkspace:outputs:report:error:));
        if(a&&b)method_exchangeImplementations(a,b);
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.1] Unified Feature Model installed: exact one-arg Offset Number/Slider -> Runtime backend; fallback Static preserved; single UI hierarchy"];
    });
}
