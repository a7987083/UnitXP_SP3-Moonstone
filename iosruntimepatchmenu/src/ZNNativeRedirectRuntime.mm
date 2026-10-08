#import "ZNNativeRedirectRuntime.h"

#import "ZNNativeHookBackend.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPResolver.h"
#import "ZNPatchCore.h"

#include <atomic>

static const NSUInteger kZNRDMaxSlots=8;

typedef uintptr_t (*ZNRDFn0)(void);
typedef uintptr_t (*ZNRDFn1)(uintptr_t);
typedef uintptr_t (*ZNRDFn2)(uintptr_t,uintptr_t);
typedef uintptr_t (*ZNRDFn3)(uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNRDFn4)(uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNRDFn5)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNRDFn6)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNRDFn7)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNRDFn8)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);

typedef struct {
    std::atomic<uintptr_t> source;
    std::atomic<uintptr_t> original;
    std::atomic<uintptr_t> target;
    std::atomic<uintptr_t> targetMethodInfo;
    std::atomic<uintptr_t> targetReceiver;
    std::atomic<uint32_t> sourceInstance;
    std::atomic<uint32_t> targetInstance;
    std::atomic<uint32_t> reuseSourceSelf;
    std::atomic<uint32_t> argumentCount;
    std::atomic<uint32_t> enabled;
    std::atomic<uint64_t> hits;
} ZNRDSlot;

static ZNRDSlot gZNRDSlots[kZNRDMaxSlots];

static uintptr_t ZNRDCall(uintptr_t target,const uintptr_t *a,NSUInteger count) {
    switch(count){
        case 0:return ((ZNRDFn0)target)();
        case 1:return ((ZNRDFn1)target)(a[0]);
        case 2:return ((ZNRDFn2)target)(a[0],a[1]);
        case 3:return ((ZNRDFn3)target)(a[0],a[1],a[2]);
        case 4:return ((ZNRDFn4)target)(a[0],a[1],a[2],a[3]);
        case 5:return ((ZNRDFn5)target)(a[0],a[1],a[2],a[3],a[4]);
        case 6:return ((ZNRDFn6)target)(a[0],a[1],a[2],a[3],a[4],a[5]);
        case 7:return ((ZNRDFn7)target)(a[0],a[1],a[2],a[3],a[4],a[5],a[6]);
        case 8:return ((ZNRDFn8)target)(a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7]);
        default:return 0;
    }
}

static uintptr_t ZNRDHandle(NSUInteger index,
                            uintptr_t x0,uintptr_t x1,uintptr_t x2,uintptr_t x3,
                            uintptr_t x4,uintptr_t x5,uintptr_t x6,uintptr_t x7) {
    if(index>=kZNRDMaxSlots)return 0;
    ZNRDSlot *slot=&gZNRDSlots[index];
    uintptr_t original=slot->original.load(std::memory_order_acquire);
    if(!slot->enabled.load(std::memory_order_relaxed)){
        if(!original)return 0;
        uintptr_t regs[8]={x0,x1,x2,x3,x4,x5,x6,x7};
        NSUInteger sourceNative=(slot->sourceInstance.load(std::memory_order_relaxed)?1u:0u)+
                                slot->argumentCount.load(std::memory_order_relaxed)+1u;
        return ZNRDCall(original,regs,MIN(sourceNative,(NSUInteger)8));
    }

    uintptr_t target=slot->target.load(std::memory_order_acquire);
    uintptr_t targetMethodInfo=slot->targetMethodInfo.load(std::memory_order_acquire);
    if(!target||!targetMethodInfo)return 0;

    uintptr_t regs[8]={x0,x1,x2,x3,x4,x5,x6,x7};
    uintptr_t argv[8]={0};
    NSUInteger n=0;
    BOOL sourceInstance=slot->sourceInstance.load(std::memory_order_relaxed)!=0;
    BOOL targetInstance=slot->targetInstance.load(std::memory_order_relaxed)!=0;
    NSUInteger argc=slot->argumentCount.load(std::memory_order_relaxed);

    if(targetInstance){
        uintptr_t receiver=slot->reuseSourceSelf.load(std::memory_order_relaxed)
            ? (sourceInstance?x0:0)
            : slot->targetReceiver.load(std::memory_order_acquire);
        if(!receiver)return 0;
        argv[n++]=receiver;
    }

    NSUInteger sourceParamBase=sourceInstance?1u:0u;
    for(NSUInteger i=0;i<argc;i++){
        NSUInteger reg=sourceParamBase+i;
        if(reg>=8||n>=8)return 0;
        argv[n++]=regs[reg];
    }
    if(n>=8)return 0;
    argv[n++]=targetMethodInfo;
    slot->hits.fetch_add(1,std::memory_order_relaxed);
    return ZNRDCall(target,argv,n);
}

#define ZNRD_REPLACEMENT(N) static uintptr_t ZNRDReplacement##N(uintptr_t x0,uintptr_t x1,uintptr_t x2,uintptr_t x3,                                     uintptr_t x4,uintptr_t x5,uintptr_t x6,uintptr_t x7) {     return ZNRDHandle((N),x0,x1,x2,x3,x4,x5,x6,x7); }
ZNRD_REPLACEMENT(0) ZNRD_REPLACEMENT(1) ZNRD_REPLACEMENT(2) ZNRD_REPLACEMENT(3)
ZNRD_REPLACEMENT(4) ZNRD_REPLACEMENT(5) ZNRD_REPLACEMENT(6) ZNRD_REPLACEMENT(7)

static void * const gZNRDReplacements[kZNRDMaxSlots]={
    (void *)&ZNRDReplacement0,(void *)&ZNRDReplacement1,(void *)&ZNRDReplacement2,(void *)&ZNRDReplacement3,
    (void *)&ZNRDReplacement4,(void *)&ZNRDReplacement5,(void *)&ZNRDReplacement6,(void *)&ZNRDReplacement7
};

static NSString *ZNRDString(id value) {
    return [value isKindOfClass:NSString.class]?value:@"";
}
static NSString *ZNRDIdentityForCandidate(NSDictionary *candidate) {
    NSString *assembly=ZNRDString(candidate[@"assembly"]);
    NSString *ns=ZNRDString(candidate[@"namespace"]);
    NSString *cls=ZNRDString(candidate[@"class"]);
    NSString *method=ZNRDString(candidate[@"method"]);
    NSUInteger argc=[candidate[@"argumentCount"] unsignedIntegerValue];
    NSString *owner=ns.length?[NSString stringWithFormat:@"%@.%@",ns,cls]:cls;
    return [NSString stringWithFormat:@"%@!%@::%@/%lu",assembly,owner,method,(unsigned long)argc];
}
static BOOL ZNRDSameOwner(NSDictionary *source,NSDictionary *target) {
    return [ZNRDString(source[@"assembly"]) caseInsensitiveCompare:ZNRDString(target[@"assembly"])]==NSOrderedSame &&
           [ZNRDString(source[@"namespace"]) isEqualToString:ZNRDString(target[@"namespace"])] &&
           [ZNRDString(source[@"class"]) isEqualToString:ZNRDString(target[@"class"])];
}
static BOOL ZNRDGPRKind(ZNIL2CPPABIValueKind kind) {
    return kind==ZNIL2CPPABIValueKindBool||
           kind==ZNIL2CPPABIValueKindSigned32||
           kind==ZNIL2CPPABIValueKindUnsigned32||
           kind==ZNIL2CPPABIValueKindSigned64||
           kind==ZNIL2CPPABIValueKindUnsigned64||
           kind==ZNIL2CPPABIValueKindPointer||
           kind==ZNIL2CPPABIValueKindObjectReference;
}
static NSString *ZNRDNormalizedTypeName(NSDictionary *type) {
    return [ZNRDString(type[@"name"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static BOOL ZNRDCompatibleType(NSDictionary *a,NSDictionary *b) {
    BOOL aByRef=[a[@"byRef"] boolValue],bByRef=[b[@"byRef"] boolValue];
    if(aByRef!=bByRef)return NO;
    if(aByRef){
        return [ZNRDNormalizedTypeName(a) caseInsensitiveCompare:ZNRDNormalizedTypeName(b)]==NSOrderedSame;
    }
    ZNIL2CPPABIValueKind ak=(ZNIL2CPPABIValueKind)[a[@"kind"] integerValue];
    ZNIL2CPPABIValueKind bk=(ZNIL2CPPABIValueKind)[b[@"kind"] integerValue];
    if(ak!=bk||!ZNRDGPRKind(ak))return NO;
    if(ak==ZNIL2CPPABIValueKindObjectReference||ak==ZNIL2CPPABIValueKindPointer)
        return [ZNRDNormalizedTypeName(a) caseInsensitiveCompare:ZNRDNormalizedTypeName(b)]==NSOrderedSame;
    return YES;
}
static NSDictionary *ZNRDResolveActionSide(ZNNativeRedirectAction *a,BOOL target,NSString **error) {
    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if(!resolver.isAvailable){if(error)*error=resolver.lastError?:@"IL2CPP Resolver unavailable";return nil;}
    NSString *assembly=target?a.targetAssembly:a.sourceAssembly;
    NSString *ns=target?a.targetNamespace:a.sourceNamespace;
    NSString *cls=target?a.targetClass:a.sourceClass;
    NSString *method=target?a.targetMethod:a.sourceMethod;
    NSUInteger argc=target?a.targetArgumentCount:a.sourceArgumentCount;
    NSDictionary *resolved=[resolver resolveMethodAssembly:assembly namespace:ns?:@"" className:cls method:method argumentCount:(NSInteger)argc];
    if(![resolved[@"methodInfo"] unsignedLongLongValue]||![resolved[@"methodPointer"] unsignedLongLongValue]){
        if(error)*error=[NSString stringWithFormat:@"Method Redirect 无法解析 %@",target?a.targetIdentity:a.sourceIdentity];
        return nil;
    }
    return resolved;
}
static ZNNativeRedirectAction *ZNRDTransientAction(NSDictionary *source,NSDictionary *target) {
    NSDictionary *sa=ZNIL2CPPDescribeMethodABI(source),*ta=ZNIL2CPPDescribeMethodABI(target);
    ZNNativeRedirectAction *a=[ZNNativeRedirectAction new];
    a.sourceAssembly=ZNRDString(source[@"assembly"]);a.sourceNamespace=ZNRDString(source[@"namespace"]);
    a.sourceClass=ZNRDString(source[@"class"]);a.sourceMethod=ZNRDString(source[@"method"]);
    a.sourceArgumentCount=[source[@"argumentCount"] unsignedIntegerValue];
    a.sourceMethodRVA=[source[@"methodRVA"] unsignedLongLongValue]?:[source[@"rva"] unsignedLongLongValue];
    a.sourceInstance=[sa[@"instance"] boolValue];
    NSMutableArray *sp=[NSMutableArray array];for(NSDictionary *p in sa[@"parameters"]?:@[])[sp addObject:ZNRDNormalizedTypeName(p)];a.sourceParameterTypes=sp;
    a.sourceReturnType=ZNRDNormalizedTypeName(sa[@"return"]?:@{});
    a.targetAssembly=ZNRDString(target[@"assembly"]);a.targetNamespace=ZNRDString(target[@"namespace"]);
    a.targetClass=ZNRDString(target[@"class"]);a.targetMethod=ZNRDString(target[@"method"]);
    a.targetArgumentCount=[target[@"argumentCount"] unsignedIntegerValue];
    a.targetMethodRVA=[target[@"methodRVA"] unsignedLongLongValue]?:[target[@"rva"] unsignedLongLongValue];
    a.targetInstance=[ta[@"instance"] boolValue];
    NSMutableArray *tp=[NSMutableArray array];for(NSDictionary *p in ta[@"parameters"]?:@[])[tp addObject:ZNRDNormalizedTypeName(p)];a.targetParameterTypes=tp;
    a.targetReturnType=ZNRDNormalizedTypeName(ta[@"return"]?:@{});
    a.title=[NSString stringWithFormat:@"%@ → %@",a.sourceMethod,a.targetMethod];
    return a;
}

@interface ZNNativeRedirectRuntime ()
@property(nonatomic,copy,readwrite) NSString *lastStatus;
@property(nonatomic,strong) NSMutableDictionary<NSString *,ZNNativeRedirectAction *> *installedBySource;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *slotBySource;
@end

@implementation ZNNativeRedirectRuntime
+ (instancetype)sharedRuntime {
    static ZNNativeRedirectRuntime *r;static dispatch_once_t once;
    dispatch_once(&once,^{r=[ZNNativeRedirectRuntime new];r.installedBySource=[NSMutableDictionary dictionary];
        r.slotBySource=[NSMutableDictionary dictionary];r.lastStatus=@"Method Redirect idle";});
    return r;
}

- (BOOL)supportsSourceCandidate:(NSDictionary<NSString *,id> *)source
                targetCandidate:(NSDictionary<NSString *,id> *)target
                         reason:(NSString **)reason {
    NSDictionary *sa=ZNIL2CPPDescribeMethodABI(source),*ta=ZNIL2CPPDescribeMethodABI(target);
    if(![sa[@"available"] boolValue]||![ta[@"available"] boolValue]){
        if(reason)*reason=@"Source/Target ABI metadata 不完整";return NO;
    }
    if([sa[@"generic"] boolValue]||[sa[@"inflated"] boolValue]||[ta[@"generic"] boolValue]||[ta[@"inflated"] boolValue]){
        if(reason)*reason=@"Method Redirect V1 不支持 generic/inflated 方法";return NO;
    }
    if(![sa[@"instanceKnown"] boolValue]||![ta[@"instanceKnown"] boolValue]){
        if(reason)*reason=@"无法确认 Source/Target static/instance";return NO;
    }
    uintptr_t sourcePtr=[sa[@"methodPointer"] unsignedLongLongValue],targetPtr=[ta[@"methodPointer"] unsignedLongLongValue];
    uintptr_t targetMI=[ta[@"methodInfo"] unsignedLongLongValue];
    if(!sourcePtr||!targetPtr||!targetMI){if(reason)*reason=@"Source/Target methodPointer/MethodInfo 不完整";return NO;}

    NSArray *sp=[sa[@"parameters"] isKindOfClass:NSArray.class]?sa[@"parameters"]:@[];
    NSArray *tp=[ta[@"parameters"] isKindOfClass:NSArray.class]?ta[@"parameters"]:@[];
    if(sp.count!=tp.count){if(reason)*reason=@"Source/Target 参数数量不同；V1 不做参数映射";return NO;}
    for(NSUInteger i=0;i<sp.count;i++){
        if(!ZNRDCompatibleType(sp[i],tp[i])){
            if(reason)*reason=[NSString stringWithFormat:@"参数%lu ABI 不兼容：%@ → %@",
                               (unsigned long)i+1,ZNRDNormalizedTypeName(sp[i]),ZNRDNormalizedTypeName(tp[i])];
            return NO;
        }
    }
    NSDictionary *sr=[sa[@"return"] isKindOfClass:NSDictionary.class]?sa[@"return"]:@{};
    NSDictionary *tr=[ta[@"return"] isKindOfClass:NSDictionary.class]?ta[@"return"]:@{};
    ZNIL2CPPABIValueKind srk=(ZNIL2CPPABIValueKind)[sr[@"kind"] integerValue];
    ZNIL2CPPABIValueKind trk=(ZNIL2CPPABIValueKind)[tr[@"kind"] integerValue];
    BOOL returnsOK=(srk==ZNIL2CPPABIValueKindVoid&&trk==ZNIL2CPPABIValueKindVoid)||
                   (srk==trk&&ZNRDGPRKind(srk)&&ZNRDCompatibleType(sr,tr));
    if(!returnsOK){
        if(reason)*reason=[NSString stringWithFormat:@"返回 ABI 不兼容：%@ → %@",
                           ZNRDNormalizedTypeName(sr),ZNRDNormalizedTypeName(tr)];
        return NO;
    }
    NSUInteger sourceNative=sp.count+([sa[@"instance"] boolValue]?1u:0u)+1u;
    NSUInteger targetNative=tp.count+([ta[@"instance"] boolValue]?1u:0u)+1u;
    if(sourceNative>8||targetNative>8){
        if(reason)*reason=@"Method Redirect V1 超过 ARM64 x0~x7 GPR 预算";return NO;
    }
    if(reason)*reason=@"ABI compatible";
    return YES;
}

- (NSInteger)freeSlot {
    for(NSUInteger i=0;i<kZNRDMaxSlots;i++)
        if(gZNRDSlots[i].source.load(std::memory_order_acquire)==0)return (NSInteger)i;
    return -1;
}

- (BOOL)installSourceCandidate:(NSDictionary<NSString *,id> *)source
                targetCandidate:(NSDictionary<NSString *,id> *)target
                           error:(NSString **)error {
    NSString *reason=nil;
    if(![self supportsSourceCandidate:source targetCandidate:target reason:&reason]){
        if(error)*error=reason;return NO;
    }
    NSString *sourceKey=ZNRDIdentityForCandidate(source);
    ZNNativeRedirectAction *existing=[self installedActionForSourceIdentity:sourceKey];
    if(existing&&! [self restoreAction:existing error:error])return NO;

    NSDictionary *sa=ZNIL2CPPDescribeMethodABI(source),*ta=ZNIL2CPPDescribeMethodABI(target);
    uintptr_t sourcePtr=[sa[@"methodPointer"] unsignedLongLongValue];
    uintptr_t targetPtr=[ta[@"methodPointer"] unsignedLongLongValue];
    uintptr_t targetMI=[ta[@"methodInfo"] unsignedLongLongValue];
    BOOL sourceInstance=[sa[@"instance"] boolValue],targetInstance=[ta[@"instance"] boolValue];
    BOOL reuseSelf=sourceInstance&&targetInstance&&ZNRDSameOwner(source,target);
    uintptr_t receiver=0;
    if(targetInstance&&!reuseSelf){
        ZNIL2CPPInstanceResolver *resolver=[ZNIL2CPPInstanceResolver sharedResolver];
        NSString *assembly=ZNRDString(target[@"assembly"]);
        NSString *ns=ZNRDString(target[@"namespace"]);
        NSString *cls=ZNRDString(target[@"class"]);
        receiver=[resolver znm44_selectedInstanceForAssembly:assembly namespace:ns className:cls];
        if(!receiver){
            NSString *diag=nil,*inner=nil;
            receiver=(uintptr_t)[resolver resolveUniqueInstanceForAssembly:assembly namespace:ns className:cls diagnostics:&diag error:&inner];
            if(!receiver){
                if(error)*error=[NSString stringWithFormat:@"Target instance 无法唯一解析：%@",inner?:diag?:@"unknown"];
                return NO;
            }
        }
    }

    NSInteger slotIndex=[self freeSlot];
    if(slotIndex<0){if(error)*error=@"Method Redirect 临时槽已满（8）";return NO;}
    ZNRDSlot *slot=&gZNRDSlots[(NSUInteger)slotIndex];
    uintptr_t original=0;
    NSString *hookError=nil;
    if(![[ZNNativeHookBackend sharedBackend] installReplacementAtAddress:sourcePtr
                                                            replacement:gZNRDReplacements[(NSUInteger)slotIndex]
                                                               original:(void **)&original
                                                                  error:&hookError]){
        if(error)*error=hookError?:@"Method Redirect DobbyHook 失败";return NO;
    }

    slot->original.store(original,std::memory_order_relaxed);
    slot->target.store(targetPtr,std::memory_order_relaxed);
    slot->targetMethodInfo.store(targetMI,std::memory_order_relaxed);
    slot->targetReceiver.store(receiver,std::memory_order_relaxed);
    slot->sourceInstance.store(sourceInstance?1u:0u,std::memory_order_relaxed);
    slot->targetInstance.store(targetInstance?1u:0u,std::memory_order_relaxed);
    slot->reuseSourceSelf.store(reuseSelf?1u:0u,std::memory_order_relaxed);
    slot->argumentCount.store((uint32_t)[source[@"argumentCount"] unsignedIntegerValue],std::memory_order_relaxed);
    slot->hits.store(0,std::memory_order_relaxed);
    slot->enabled.store(1,std::memory_order_relaxed);
    slot->source.store(sourcePtr,std::memory_order_release);

    ZNNativeRedirectAction *action=ZNRDTransientAction(source,target);
    @synchronized(self){self.installedBySource[sourceKey]=action;self.slotBySource[sourceKey]=@(slotIndex);}
    self.lastStatus=[NSString stringWithFormat:@"INSTALLED · %@ · target receiver=%@",
                     action.canonicalIdentity,targetInstance?(reuseSelf?@"source self":[NSString stringWithFormat:@"0x%llX",(unsigned long long)receiver]):@"static"];
    [[ZNRuntimeLogger sharedLogger]log:[@"[method-redirect] " stringByAppendingString:self.lastStatus]];
    return YES;
}

- (BOOL)installAction:(ZNNativeRedirectAction *)action error:(NSString **)error {
    if(!action){if(error)*error=@"Method Redirect action 为空";return NO;}
    NSString *inner=nil;
    NSDictionary *source=ZNRDResolveActionSide(action,NO,&inner);
    if(!source){if(error)*error=inner;return NO;}
    NSDictionary *target=ZNRDResolveActionSide(action,YES,&inner);
    if(!target){if(error)*error=inner;return NO;}
    return [self installSourceCandidate:source targetCandidate:target error:error];
}

- (ZNNativeRedirectAction *)installedActionForSourceCandidate:(NSDictionary<NSString *,id> *)source {
    return [self installedActionForSourceIdentity:ZNRDIdentityForCandidate(source)];
}
- (ZNNativeRedirectAction *)installedActionForSourceIdentity:(NSString *)sourceIdentity {
    @synchronized(self){return [self.installedBySource[sourceIdentity] copy];}
}

- (BOOL)restoreSourceCandidate:(NSDictionary<NSString *,id> *)source error:(NSString **)error {
    ZNNativeRedirectAction *a=[self installedActionForSourceCandidate:source];
    if(!a){self.lastStatus=@"RESTORE skipped · Source 没有 Method Redirect";return YES;}
    return [self restoreAction:a error:error];
}

- (BOOL)restoreAction:(ZNNativeRedirectAction *)action error:(NSString **)error {
    if(!action)return YES;
    NSString *key=action.sourceIdentity;
    NSNumber *slotNumber=nil;@synchronized(self){slotNumber=self.slotBySource[key];}
    if(!slotNumber){self.lastStatus=@"RESTORE skipped · Source 没有 Method Redirect";return YES;}
    NSUInteger index=slotNumber.unsignedIntegerValue;
    if(index>=kZNRDMaxSlots){if(error)*error=@"Method Redirect slot descriptor 损坏";return NO;}
    ZNRDSlot *slot=&gZNRDSlots[index];
    uintptr_t source=slot->source.load(std::memory_order_acquire);
    if(!source){if(error)*error=@"Method Redirect source slot 已失效";return NO;}
    NSString *inner=nil;
    if(![[ZNNativeHookBackend sharedBackend] destroyHookAtAddress:source error:&inner]){
        if(error)*error=inner?:@"Method Redirect DobbyDestroy 失败";return NO;
    }
    slot->enabled.store(0,std::memory_order_relaxed);
    slot->original.store(0,std::memory_order_relaxed);slot->target.store(0,std::memory_order_relaxed);
    slot->targetMethodInfo.store(0,std::memory_order_relaxed);slot->targetReceiver.store(0,std::memory_order_relaxed);
    slot->argumentCount.store(0,std::memory_order_relaxed);slot->hits.store(0,std::memory_order_relaxed);
    slot->source.store(0,std::memory_order_release);
    @synchronized(self){[self.installedBySource removeObjectForKey:key];[self.slotBySource removeObjectForKey:key];}
    self.lastStatus=[NSString stringWithFormat:@"RESTORED · %@",key];
    return YES;
}
@end
