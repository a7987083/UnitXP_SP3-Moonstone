#import "ZNNativeHookRuntime.h"

#import "ZNNativeHookAction.h"
#import "ZNNativeHookBackend.h"
#import "ZNNativeHookTemplate.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPResolver.h"
#import "ZNIL2CPPRuntimeCommon.h"
#import "ZNPatchCore.h"

#import <atomic>
#import <limits.h>

const void * const ZNNativeHookCandidateAssociationKey = &ZNNativeHookCandidateAssociationKey;

static const uint32_t kZNNativeMethodAttributeStatic = 0x0010u;
static const NSUInteger kZNNativeMaxSlots = 32;

typedef uint32_t (*ZNNativeMethodGetFlagsFn)(const void *, uint32_t *);

typedef struct {
    std::atomic<uintptr_t> target;
    std::atomic<int32_t> multiplier;
    std::atomic<uint64_t> hits;
    std::atomic<int32_t> lastBefore;
    std::atomic<int32_t> lastAfter;
    std::atomic<uint32_t> registerIndex;
    std::atomic<uint32_t> actionID;
} ZNNativeSlot;

static ZNNativeSlot gZNNativeSlots[kZNNativeMaxSlots];

static ZNNativeSlot *ZNNativeSlotForTarget(uintptr_t target) {
    if(!target)return NULL;
    for(NSUInteger i=0;i<kZNNativeMaxSlots;i++)
        if(gZNNativeSlots[i].target.load(std::memory_order_acquire)==target)return &gZNNativeSlots[i];
    return NULL;
}

static ZNNativeSlot *ZNNativeFreeSlot(void) {
    for(NSUInteger i=0;i<kZNNativeMaxSlots;i++)
        if(gZNNativeSlots[i].target.load(std::memory_order_acquire)==0)return &gZNNativeSlots[i];
    return NULL;
}

static void ZNNativeArgScaleInt32Callback(void *address, ZNM47DobbyRegisterContextPrefix *context) {
    if(!address||!context)return;
    uintptr_t target=(uintptr_t)address;
    ZNNativeSlot *slot=ZNNativeSlotForTarget(target);
    if(!slot)return;
    uint32_t reg=slot->registerIndex.load(std::memory_order_relaxed);
    if(reg>=8)return;
    uint64_t raw=context->general.x[reg];
    int32_t before=(int32_t)(uint32_t)raw;
    int32_t multiplier=slot->multiplier.load(std::memory_order_relaxed);
    int32_t after=ZNNativeHookScaleInt32(before,multiplier);
    context->general.x[reg]=(uint64_t)(uint32_t)after;
    slot->lastBefore.store(before,std::memory_order_relaxed);
    slot->lastAfter.store(after,std::memory_order_relaxed);
    slot->hits.fetch_add(1,std::memory_order_relaxed);
}

static NSString *ZNNativeString(id value) {
    return [value isKindOfClass:NSString.class]?value:@"";
}

static NSDictionary *ZNNativeResolveDescriptor(NSString *assembly,
                                                NSString *namespaceName,
                                                NSString *className,
                                                NSString *methodName,
                                                NSUInteger argumentCount,
                                                NSDictionary *candidate,
                                                NSString **error) {
    uintptr_t methodInfo=[candidate[@"methodInfo"] unsignedLongLongValue];
    uintptr_t pointer=[candidate[@"methodPointer"] unsignedLongLongValue];

    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if((!methodInfo||!pointer)&&resolver.isAvailable){
        NSDictionary *resolved=[resolver resolveMethodAssembly:assembly
                                                     namespace:namespaceName?:@""
                                                     className:className
                                                        method:methodName
                                                 argumentCount:(NSInteger)argumentCount];
        if(!methodInfo)methodInfo=[resolved[@"methodInfo"] unsignedLongLongValue];
        if(!pointer)pointer=[resolved[@"methodPointer"] unsignedLongLongValue];
    }
    if(!methodInfo||!pointer){
        if(error)*error=[NSString stringWithFormat:@"Native Hook resolve 失败：%@.%@::%@/%lu",
                         namespaceName?:@"",className?:@"",methodName?:@"",(unsigned long)argumentCount];
        return nil;
    }

    ZNNativeMethodGetFlagsFn getFlags=(ZNNativeMethodGetFlagsFn)ZNIL2CPPResolveSymbol(resolver.unityPath,"il2cpp_method_get_flags");
    if(!getFlags){
        if(error)*error=@"Native Hook 无法读取 il2cpp_method_get_flags";
        return nil;
    }
    uint32_t implFlags=0;
    uint32_t flags=getFlags((const void *)methodInfo,&implFlags);
    BOOL isStatic=(flags&kZNNativeMethodAttributeStatic)!=0;
    return @{@"methodInfo":@(methodInfo),@"methodPointer":@(pointer),@"static":@(isStatic),@"methodFlags":@(flags)};
}

@implementation ZNNativeHookRuntime

+ (instancetype)sharedRuntime {
    static ZNNativeHookRuntime *runtime;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ runtime=[ZNNativeHookRuntime new]; });
    return runtime;
}

- (NSArray<NSNumber *> *)supportedInt32ArgumentIndicesForCandidate:(NSDictionary<NSString *,id> *)candidate
                                                            reason:(NSString **)reason {
    NSDictionary *abi=ZNIL2CPPDescribeMethodABI(candidate);
    NSArray *params=[abi[@"parameters"] isKindOfClass:NSArray.class]?abi[@"parameters"]:@[];
    NSUInteger argc=[candidate[@"argumentCount"] unsignedIntegerValue];
    if(![abi[@"available"] boolValue]||params.count!=argc){
        if(reason)*reason=ZNNativeString(abi[@"reason"]).length?ZNNativeString(abi[@"reason"]):@"参数 ABI 不完整";
        return @[];
    }
    NSMutableArray *indices=[NSMutableArray array];
    for(NSUInteger i=0;i<params.count;i++){
        NSDictionary *p=params[i];
        if((ZNIL2CPPABIValueKind)[p[@"kind"] integerValue]==ZNIL2CPPABIValueKindSigned32)[indices addObject:@(i)];
    }
    if(!indices.count&&reason)*reason=@"当前 V1 只支持 int32/signed32 参数倍率";
    return indices;
}

- (BOOL)installResolvedTarget:(uintptr_t)target
                    isStatic:(BOOL)isStatic
               argumentIndex:(NSUInteger)argumentIndex
               argumentCount:(NSUInteger)argumentCount
                  multiplier:(NSInteger)multiplier
                    actionID:(uint32_t)actionID
                       error:(NSString **)error {
    if(multiplier<1||multiplier>1000){if(error)*error=@"测试倍率必须在 1~1000";return NO;}
    uint32_t reg=0;
    if(!ZNNativeHookArgRegisterIndex(isStatic,argumentIndex,argumentCount,&reg)){
        if(error)*error=@"ArgScaleInt32 V1 仅支持映射到 ARM64 x0~x7 的参数";
        return NO;
    }

    ZNNativeSlot *existing=ZNNativeSlotForTarget(target);
    if(existing){
        if(existing->registerIndex.load(std::memory_order_relaxed)!=reg){
            if(error)*error=@"同一 target 已安装不同参数位置的测试 Hook，请先恢复原方法";
            return NO;
        }
        existing->multiplier.store((int32_t)multiplier,std::memory_order_release);
        if(actionID)existing->actionID.store(actionID,std::memory_order_release);
        return YES;
    }

    ZNNativeSlot *slot=ZNNativeFreeSlot();
    if(!slot){if(error)*error=@"Native Hook slot 已满";return NO;}
    slot->multiplier.store((int32_t)multiplier,std::memory_order_relaxed);
    slot->hits.store(0,std::memory_order_relaxed);
    slot->lastBefore.store(0,std::memory_order_relaxed);
    slot->lastAfter.store(0,std::memory_order_relaxed);
    slot->registerIndex.store(reg,std::memory_order_relaxed);
    slot->actionID.store(actionID,std::memory_order_relaxed);
    slot->target.store(target,std::memory_order_release);

    NSString *hookError=nil;
    if(![[ZNNativeHookBackend sharedBackend] installInstrumentAtAddress:target callback:ZNNativeArgScaleInt32Callback error:&hookError]){
        slot->target.store(0,std::memory_order_release);
        if(error)*error=hookError?:@"Dobby instrument 安装失败";
        return NO;
    }
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[native-hook] installed target=0x%llX reg=x%u multiplier=%ld action=%u",
                                           (unsigned long long)target,reg,(long)multiplier,actionID]];
    return YES;
}

- (BOOL)installTemporaryArgScaleInt32ForCandidate:(NSDictionary<NSString *,id> *)candidate
                                     argumentIndex:(NSUInteger)argumentIndex
                                        multiplier:(NSInteger)multiplier
                                             error:(NSString **)error {
    NSArray *supported=[self supportedInt32ArgumentIndicesForCandidate:candidate reason:error];
    if(![supported containsObject:@(argumentIndex)])return NO;
    NSString *assembly=ZNNativeString(candidate[@"assembly"]);if(!assembly.length)assembly=@"Assembly-CSharp.dll";
    NSString *ns=ZNNativeString(candidate[@"namespace"]);
    NSString *cls=ZNNativeString(candidate[@"class"]);
    NSString *method=ZNNativeString(candidate[@"method"]);
    NSUInteger argc=[candidate[@"argumentCount"] unsignedIntegerValue];
    NSDictionary *resolved=ZNNativeResolveDescriptor(assembly,ns,cls,method,argc,candidate,error);
    if(!resolved)return NO;
    return [self installResolvedTarget:[resolved[@"methodPointer"] unsignedLongLongValue]
                              isStatic:[resolved[@"static"] boolValue]
                         argumentIndex:argumentIndex
                         argumentCount:argc
                            multiplier:multiplier
                              actionID:0
                                 error:error];
}

- (BOOL)removeTemporaryHookForCandidate:(NSDictionary<NSString *,id> *)candidate error:(NSString **)error {
    NSString *assembly=ZNNativeString(candidate[@"assembly"]);if(!assembly.length)assembly=@"Assembly-CSharp.dll";
    NSString *ns=ZNNativeString(candidate[@"namespace"]);
    NSString *cls=ZNNativeString(candidate[@"class"]);
    NSString *method=ZNNativeString(candidate[@"method"]);
    NSUInteger argc=[candidate[@"argumentCount"] unsignedIntegerValue];
    NSDictionary *resolved=ZNNativeResolveDescriptor(assembly,ns,cls,method,argc,candidate,error);
    if(!resolved)return NO;
    uintptr_t target=[resolved[@"methodPointer"] unsignedLongLongValue];
    ZNNativeSlot *slot=ZNNativeSlotForTarget(target);
    if(!slot)return YES;
    NSString *destroyError=nil;
    if(![[ZNNativeHookBackend sharedBackend] destroyHookAtAddress:target error:&destroyError]){
        if(error)*error=destroyError;return NO;
    }
    slot->target.store(0,std::memory_order_release);
    slot->actionID.store(0,std::memory_order_relaxed);
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[native-hook] restored target=0x%llX",(unsigned long long)target]];
    return YES;
}

- (NSString *)diagnosticsForCandidate:(NSDictionary<NSString *,id> *)candidate {
    uintptr_t target=[candidate[@"methodPointer"] unsignedLongLongValue];
    ZNNativeSlot *slot=ZNNativeSlotForTarget(target);
    if(!slot)return @"Hook 状态：未安装";
    return [NSString stringWithFormat:@"Hook 状态：已安装\nTarget：0x%llX\nHits：%llu\n最近参数：%d → %d\n倍率：x%d",
            (unsigned long long)target,
            (unsigned long long)slot->hits.load(std::memory_order_relaxed),
            slot->lastBefore.load(std::memory_order_relaxed),
            slot->lastAfter.load(std::memory_order_relaxed),
            slot->multiplier.load(std::memory_order_relaxed)];
}

- (BOOL)installAction:(ZNNativeHookAction *)action value:(NSInteger)value error:(NSString **)error {
    if(!action||action.templateKind!=ZNNativeHookTemplateArgScaleInt32){if(error)*error=@"Native Hook Action 模板不受支持";return NO;}
    NSDictionary *candidate=@{@"assembly":action.assembly?:@"Assembly-CSharp.dll",@"namespace":action.namespaceName?:@"",
                              @"class":action.className?:@"",@"method":action.methodName?:@"",@"argumentCount":@(action.argumentCount)};
    NSDictionary *resolved=ZNNativeResolveDescriptor(action.assembly,action.namespaceName,action.className,action.methodName,action.argumentCount,candidate,error);
    if(!resolved)return NO;
    return [self installResolvedTarget:[resolved[@"methodPointer"] unsignedLongLongValue]
                              isStatic:[resolved[@"static"] boolValue]
                         argumentIndex:action.argumentIndex
                         argumentCount:action.argumentCount
                            multiplier:value
                              actionID:action.actionID
                                 error:error];
}

- (BOOL)setValue:(NSInteger)value forAction:(ZNNativeHookAction *)action error:(NSString **)error {
    if(!action){if(error)*error=@"Native Hook Action 为空";return NO;}
    NSDictionary *candidate=@{@"assembly":action.assembly?:@"Assembly-CSharp.dll",@"namespace":action.namespaceName?:@"",
                              @"class":action.className?:@"",@"method":action.methodName?:@"",@"argumentCount":@(action.argumentCount)};
    NSDictionary *resolved=ZNNativeResolveDescriptor(action.assembly,action.namespaceName,action.className,action.methodName,action.argumentCount,candidate,error);
    if(!resolved)return NO;
    ZNNativeSlot *slot=ZNNativeSlotForTarget([resolved[@"methodPointer"] unsignedLongLongValue]);
    if(!slot)return [self installAction:action value:value error:error];
    slot->multiplier.store((int32_t)value,std::memory_order_release);
    return YES;
}

- (BOOL)removeAction:(ZNNativeHookAction *)action error:(NSString **)error {
    if(!action)return YES;
    NSDictionary *candidate=@{@"assembly":action.assembly?:@"Assembly-CSharp.dll",@"namespace":action.namespaceName?:@"",
                              @"class":action.className?:@"",@"method":action.methodName?:@"",@"argumentCount":@(action.argumentCount)};
    NSDictionary *resolved=ZNNativeResolveDescriptor(action.assembly,action.namespaceName,action.className,action.methodName,action.argumentCount,candidate,error);
    if(!resolved)return NO;
    uintptr_t target=[resolved[@"methodPointer"] unsignedLongLongValue];
    ZNNativeSlot *slot=ZNNativeSlotForTarget(target);
    if(!slot)return YES;
    if(![[ZNNativeHookBackend sharedBackend] destroyHookAtAddress:target error:error])return NO;
    slot->target.store(0,std::memory_order_release);
    return YES;
}

@end
