#import "ZNBuiltInCapabilityAdapters.h"
#import "ZNCapabilityRegistry.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNNativeHookRuntime.h"
#import "ZNNativeHookScheduler.h"
#import "ZNNativeHookAction.h"
#import "ZNDirectNativeCallEngine.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPOwningMethodResolver.h"
#import "ZNIL2CPPMethodSignature.h"

NSString * const ZNCapabilityStaticPatchIdentifier=@"static-patch";
NSString * const ZNCapabilityRuntimeMethodIdentifier=@"runtime-method";
NSString * const ZNCapabilityNativeHookIdentifier=@"native-hook";
NSString * const ZNCapabilityDirectNativeCallIdentifier=@"direct-native-call";

@interface ZNStaticPatchCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNStaticPatchCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityStaticPatchIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{(void)c;(void)e;[[ZNStaticDispatchRuntime sharedRuntime] refresh];return YES;}
- (NSArray *)snapshotItems{return [ZNStaticDispatchRuntime sharedRuntime].records?:@[];}
- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    if(![item isKindOfClass:ZNStaticPatchRecord.class]){if(error)*error=@"Static Patch item 类型错误";return NO;}
    return [[ZNStaticDispatchRuntime sharedRuntime] setEnabled:[value boolValue] forRecord:item error:error];
}
- (BOOL)deactivateItem:(id)item error:(NSString **)error{return [self activateItem:item value:@NO error:error];}
@end

@interface ZNRuntimeMethodCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNRuntimeMethodCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityRuntimeMethodIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{(void)c;(void)e;[[ZNRuntimeActionRuntime sharedRuntime] refresh];return YES;}
- (NSArray *)snapshotItems{return [ZNRuntimeActionRuntime sharedRuntime].records?:@[];}
- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    (void)value;
    if(![item isKindOfClass:ZNRuntimeMethodActionRecord.class]){if(error)*error=@"Runtime Method item 类型错误";return NO;}
    return [[ZNRuntimeActionRuntime sharedRuntime] executeRecord:item error:error];
}
@end

@interface ZNNativeHookCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNNativeHookCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityNativeHookIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{
    (void)c;(void)e;
    ZNNativeHookRuntime *runtime=[ZNNativeHookRuntime sharedRuntime];
    [runtime refreshGeneratedActions];
    [[ZNNativeHookScheduler sharedScheduler] reconcileActions:runtime.generatedActions?:@[]];
    return YES;
}
- (NSArray *)snapshotItems{return [ZNNativeHookRuntime sharedRuntime].generatedActions?:@[];}
- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    if(![item isKindOfClass:ZNNativeHookAction.class]){if(error)*error=@"Native Hook item 类型错误";return NO;}
    NSInteger desired=[value respondsToSelector:@selector(integerValue)]?[value integerValue]:0;
    [[ZNNativeHookScheduler sharedScheduler] setDesiredValue:desired forAction:item];
    return YES;
}
@end


@interface ZNDirectNativeCallCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNDirectNativeCallCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityDirectNativeCallIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{
    (void)c;
    [[ZNRuntimeActionRuntime sharedRuntime] refresh];
    return [[ZNDirectNativeCallEngine sharedEngine] prepare:e];
}
- (NSArray *)snapshotItems{return [ZNRuntimeActionRuntime sharedRuntime].directRecords?:@[];}

static NSString *ZNDNCNormalizeAssembly(NSString *value){
    NSString *s=[[value?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [s hasSuffix:@".dll"]?[s substringToIndex:s.length-4]:s;
}
static BOOL ZNDNCStringEqual(NSString *a,NSString *b){
    return [[a?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            caseInsensitiveCompare:[b?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]==NSOrderedSame;
}
- (NSDictionary *)zn_candidateForRecord:(ZNRuntimeMethodActionRecord *)record error:(NSString **)error {
    if(record.methodRVA){
        NSString *inner=nil;
        NSArray<NSDictionary<NSString *,id> *> *resolved=[[ZNIL2CPPOwningMethodResolver sharedResolver]
            resolveRVA:record.methodRVA limit:32 error:&inner];
        if(!resolved.count){if(error)*error=inner?:[NSString stringWithFormat:@"Direct Native Call RVA 0x%llX 无法解析",(unsigned long long)record.methodRVA];return nil;}

        NSMutableArray<NSDictionary<NSString *,id> *> *matches=[NSMutableArray array];
        for(NSDictionary<NSString *,id> *candidate in resolved){
            uint64_t methodRVA=[candidate[@"methodRVA"] unsignedLongLongValue];
            if(methodRVA!=record.methodRVA)continue;
            if(![ZNDNCNormalizeAssembly(candidate[@"assembly"]) isEqualToString:ZNDNCNormalizeAssembly(record.assembly)])continue;
            if(!ZNDNCStringEqual(candidate[@"namespace"],record.namespaceName))continue;
            if(!ZNDNCStringEqual(candidate[@"class"],record.className))continue;
            if(!ZNDNCStringEqual(candidate[@"method"],record.methodName))continue;
            if([candidate[@"argumentCount"] unsignedIntegerValue]!=record.argumentCount)continue;
            if(record.signatureAvailable){
                NSString *signatureError=nil;
                NSArray<NSString *> *types=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&signatureError);
                if(!types||![types isEqualToArray:record.parameterTypeNames])continue;
            }
            [matches addObject:candidate];
        }
        if(matches.count==1){
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[direct-native-call] resolved by authored RVA 0x%llX -> %@",
              (unsigned long long)record.methodRVA,matches.firstObject[@"canonical"]?:record.canonicalIdentity]];
            return matches.firstObject;
        }
        if(error)*error=matches.count
            ? [NSString stringWithFormat:@"Direct Native Call RVA 0x%llX 仍有 %lu 个同入口候选；拒绝猜测",(unsigned long long)record.methodRVA,(unsigned long)matches.count]
            : [NSString stringWithFormat:@"Direct Native Call RVA 0x%llX 与生成时方法身份不一致；请重新制作菜单",(unsigned long long)record.methodRVA];
        return nil;
    }

    // Legacy generated records created before the authored-RVA side-table.
    NSString *owner=record.namespaceName.length
        ? [NSString stringWithFormat:@"%@.%@",record.namespaceName,record.className]
        : record.className;
    NSString *expression=[NSString stringWithFormat:@"%@!%@::%@/%lu",
                          record.assembly.length?record.assembly:@"Assembly-CSharp.dll",
                          owner?:@"",record.methodName?:@"",(unsigned long)record.argumentCount];
    NSString *inner=nil;
    NSDictionary *candidate=[[ZNIL2CPPHybridFinder sharedFinder] resolveExpression:expression error:&inner];
    if(!candidate){if(error)*error=inner?:@"Direct Native Call legacy 记录无法解析";return nil;}
    return candidate;
}

- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    NSArray *values=[value isKindOfClass:NSArray.class]?value:nil;
    NSDictionary *candidate=nil;
    if([item isKindOfClass:NSDictionary.class]){
        candidate=item;
    }else if([item isKindOfClass:ZNRuntimeMethodActionRecord.class]){
        ZNRuntimeMethodActionRecord *record=item;
        candidate=[self zn_candidateForRecord:record error:error];
        if(!candidate)return NO;
        if(!values)values=record.argumentValues?:@[];
    }else{
        if(error)*error=@"Direct Native Call item 类型错误";
        return NO;
    }
    if(!values)values=@[];
    return [[ZNDirectNativeCallEngine sharedEngine] executeCandidate:candidate argumentValues:values error:error]!=nil;
}
@end

void ZNRegisterBuiltInCapabilityAdapters(void){
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        ZNCapabilityRegistry *r=[ZNCapabilityRegistry sharedRegistry];
        [r registerAdapter:[ZNStaticPatchCapabilityAdapter new]];
        [r registerAdapter:[ZNRuntimeMethodCapabilityAdapter new]];
        [r registerAdapter:[ZNNativeHookCapabilityAdapter new]];
        [r registerAdapter:[ZNDirectNativeCallCapabilityAdapter new]];
    });
}
