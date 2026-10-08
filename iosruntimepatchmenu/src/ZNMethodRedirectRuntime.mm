#import "ZNMethodRedirectRuntime.h"

#import "ZNRuntimeActionRuntime.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPOwningMethodResolver.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNNativeHookBackend.h"
#import "ZNPatchCore.h"

#include <atomic>

static const NSUInteger kZNMRMaxSlots=16;

typedef uintptr_t (*ZNMRFn0)(void);
typedef uintptr_t (*ZNMRFn1)(uintptr_t);
typedef uintptr_t (*ZNMRFn2)(uintptr_t,uintptr_t);
typedef uintptr_t (*ZNMRFn3)(uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNMRFn4)(uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNMRFn5)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNMRFn6)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNMRFn7)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*ZNMRFn8)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);

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
    std::atomic<uint32_t> actionID;
} ZNMRSlot;

static ZNMRSlot gZNMRSlots[kZNMRMaxSlots];

static uintptr_t ZNMRCall(uintptr_t target,const uintptr_t *a,NSUInteger count) {
    switch(count){
        case 0:return ((ZNMRFn0)target)();
        case 1:return ((ZNMRFn1)target)(a[0]);
        case 2:return ((ZNMRFn2)target)(a[0],a[1]);
        case 3:return ((ZNMRFn3)target)(a[0],a[1],a[2]);
        case 4:return ((ZNMRFn4)target)(a[0],a[1],a[2],a[3]);
        case 5:return ((ZNMRFn5)target)(a[0],a[1],a[2],a[3],a[4]);
        case 6:return ((ZNMRFn6)target)(a[0],a[1],a[2],a[3],a[4],a[5]);
        case 7:return ((ZNMRFn7)target)(a[0],a[1],a[2],a[3],a[4],a[5],a[6]);
        case 8:return ((ZNMRFn8)target)(a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7]);
        default:return 0;
    }
}

static uintptr_t ZNMRHandle(NSUInteger index,
                            uintptr_t x0,uintptr_t x1,uintptr_t x2,uintptr_t x3,
                            uintptr_t x4,uintptr_t x5,uintptr_t x6,uintptr_t x7) {
    if(index>=kZNMRMaxSlots)return 0;
    ZNMRSlot *slot=&gZNMRSlots[index];
    uintptr_t original=slot->original.load(std::memory_order_acquire);
    uintptr_t regs[8]={x0,x1,x2,x3,x4,x5,x6,x7};
    BOOL sourceInstance=slot->sourceInstance.load(std::memory_order_relaxed)!=0;
    NSUInteger argc=slot->argumentCount.load(std::memory_order_relaxed);
    NSUInteger sourceNative=(sourceInstance?1u:0u)+argc+1u;

    if(!slot->enabled.load(std::memory_order_relaxed)){
        return original?ZNMRCall(original,regs,MIN(sourceNative,(NSUInteger)8)):0;
    }

    uintptr_t target=slot->target.load(std::memory_order_acquire);
    uintptr_t targetMethodInfo=slot->targetMethodInfo.load(std::memory_order_acquire);
    if(!target||!targetMethodInfo){
        return original?ZNMRCall(original,regs,MIN(sourceNative,(NSUInteger)8)):0;
    }

    uintptr_t argv[8]={0};NSUInteger n=0;
    BOOL targetInstance=slot->targetInstance.load(std::memory_order_relaxed)!=0;
    if(targetInstance){
        uintptr_t receiver=slot->reuseSourceSelf.load(std::memory_order_relaxed)
            ? (sourceInstance?x0:0)
            : slot->targetReceiver.load(std::memory_order_acquire);
        if(!receiver)return original?ZNMRCall(original,regs,MIN(sourceNative,(NSUInteger)8)):0;
        argv[n++]=receiver;
    }

    NSUInteger sourceParamBase=sourceInstance?1u:0u;
    for(NSUInteger i=0;i<argc;i++){
        NSUInteger reg=sourceParamBase+i;
        if(reg>=8||n>=8)return original?ZNMRCall(original,regs,MIN(sourceNative,(NSUInteger)8)):0;
        argv[n++]=regs[reg];
    }
    if(n>=8)return original?ZNMRCall(original,regs,MIN(sourceNative,(NSUInteger)8)):0;
    argv[n++]=targetMethodInfo;
    slot->hits.fetch_add(1,std::memory_order_relaxed);
    return ZNMRCall(target,argv,n);
}

#define ZNMR_REPLACEMENT(N) \
static uintptr_t ZNMRReplacement##N(uintptr_t x0,uintptr_t x1,uintptr_t x2,uintptr_t x3, \
                                    uintptr_t x4,uintptr_t x5,uintptr_t x6,uintptr_t x7) { \
    return ZNMRHandle((N),x0,x1,x2,x3,x4,x5,x6,x7); \
}
ZNMR_REPLACEMENT(0)  ZNMR_REPLACEMENT(1)  ZNMR_REPLACEMENT(2)  ZNMR_REPLACEMENT(3)
ZNMR_REPLACEMENT(4)  ZNMR_REPLACEMENT(5)  ZNMR_REPLACEMENT(6)  ZNMR_REPLACEMENT(7)
ZNMR_REPLACEMENT(8)  ZNMR_REPLACEMENT(9)  ZNMR_REPLACEMENT(10) ZNMR_REPLACEMENT(11)
ZNMR_REPLACEMENT(12) ZNMR_REPLACEMENT(13) ZNMR_REPLACEMENT(14) ZNMR_REPLACEMENT(15)

static void * const gZNMRReplacements[kZNMRMaxSlots]={
    (void *)&ZNMRReplacement0,(void *)&ZNMRReplacement1,(void *)&ZNMRReplacement2,(void *)&ZNMRReplacement3,
    (void *)&ZNMRReplacement4,(void *)&ZNMRReplacement5,(void *)&ZNMRReplacement6,(void *)&ZNMRReplacement7,
    (void *)&ZNMRReplacement8,(void *)&ZNMRReplacement9,(void *)&ZNMRReplacement10,(void *)&ZNMRReplacement11,
    (void *)&ZNMRReplacement12,(void *)&ZNMRReplacement13,(void *)&ZNMRReplacement14,(void *)&ZNMRReplacement15
};

static NSString *ZNMRPreferenceKey(uint32_t actionID){
    return [NSString stringWithFormat:@"zonoe.method-redirect.enabled.v1.%u",actionID];
}

static NSString *ZNMRTrim(NSString *value){
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static NSString *ZNMRNormalizeAssembly(NSString *value){
    NSString *s=ZNMRTrim(value).lowercaseString;
    return [s hasSuffix:@".dll"]?[s substringToIndex:s.length-4]:s;
}
static BOOL ZNMRStringEqual(NSString *a,NSString *b){
    return [ZNMRTrim(a) caseInsensitiveCompare:ZNMRTrim(b)]==NSOrderedSame;
}
static BOOL ZNMRSameOwner(ZNRuntimeMethodActionRecord *record,NSDictionary *target){
    return [ZNMRNormalizeAssembly(record.assembly) isEqualToString:ZNMRNormalizeAssembly(target[@"assembly"])] &&
           ZNMRStringEqual(record.namespaceName,target[@"namespace"]) &&
           ZNMRStringEqual(record.className,target[@"class"]);
}

static NSDictionary *ZNMRResolveRVA(uint64_t rva,
                                    NSString *assembly,
                                    NSString *namespaceName,
                                    NSString *className,
                                    NSString *methodName,
                                    NSUInteger argumentCount,
                                    NSArray<NSString *> *parameterTypes,
                                    BOOL signatureAvailable,
                                    NSString **error) {
    if(!rva){if(error)*error=@"Method Redirect RVA 为空";return nil;}
    NSString *inner=nil;
    NSArray<NSDictionary<NSString *,id> *> *resolved=[[ZNIL2CPPOwningMethodResolver sharedResolver]
        resolveRVA:rva limit:32 error:&inner];
    if(!resolved.count){if(error)*error=inner?:[NSString stringWithFormat:@"Method Redirect RVA 0x%llX 无法解析",(unsigned long long)rva];return nil;}
    NSMutableArray *matches=[NSMutableArray array];
    for(NSDictionary *candidate in resolved){
        if([candidate[@"methodRVA"] unsignedLongLongValue]!=rva)continue;
        if(![ZNMRNormalizeAssembly(candidate[@"assembly"]) isEqualToString:ZNMRNormalizeAssembly(assembly)])continue;
        if(!ZNMRStringEqual(candidate[@"namespace"],namespaceName))continue;
        if(!ZNMRStringEqual(candidate[@"class"],className))continue;
        if(!ZNMRStringEqual(candidate[@"method"],methodName))continue;
        if([candidate[@"argumentCount"] unsignedIntegerValue]!=argumentCount)continue;
        if(signatureAvailable){
            NSString *signatureError=nil;
            NSArray *types=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&signatureError);
            if(!types||![types isEqualToArray:parameterTypes?:@[]])continue;
        }
        [matches addObject:candidate];
    }
    if(matches.count==1)return matches.firstObject;
    if(error)*error=matches.count
        ?[NSString stringWithFormat:@"Method Redirect RVA 0x%llX 仍有 %lu 个候选，拒绝猜测",(unsigned long long)rva,(unsigned long)matches.count]
        :[NSString stringWithFormat:@"Method Redirect RVA 0x%llX 与生成时方法身份不一致",(unsigned long long)rva];
    return nil;
}

static BOOL ZNMRGPRKind(ZNIL2CPPABIValueKind kind){
    return kind==ZNIL2CPPABIValueKindBool||
           kind==ZNIL2CPPABIValueKindSigned32||
           kind==ZNIL2CPPABIValueKindUnsigned32||
           kind==ZNIL2CPPABIValueKindSigned64||
           kind==ZNIL2CPPABIValueKindUnsigned64||
           kind==ZNIL2CPPABIValueKindPointer||
           kind==ZNIL2CPPABIValueKindObjectReference;
}
static NSString *ZNMRTypeName(NSDictionary *type){
    return [type[@"name"] isKindOfClass:NSString.class]?type[@"name"]:@"?";
}
static BOOL ZNMRCompatibleType(NSDictionary *a,NSDictionary *b){
    BOOL ar=[a[@"byRef"] boolValue],br=[b[@"byRef"] boolValue];
    if(ar!=br)return NO;
    if(ar)return [ZNMRTypeName(a) caseInsensitiveCompare:ZNMRTypeName(b)]==NSOrderedSame;
    ZNIL2CPPABIValueKind ak=(ZNIL2CPPABIValueKind)[a[@"kind"] integerValue];
    ZNIL2CPPABIValueKind bk=(ZNIL2CPPABIValueKind)[b[@"kind"] integerValue];
    if(ak!=bk||!ZNMRGPRKind(ak))return NO;
    if(ak==ZNIL2CPPABIValueKindObjectReference||ak==ZNIL2CPPABIValueKindPointer)
        return [ZNMRTypeName(a) caseInsensitiveCompare:ZNMRTypeName(b)]==NSOrderedSame;
    return YES;
}

static BOOL ZNMRValidateRuntimeABI(NSDictionary *source,NSDictionary *target,NSString **error){
    NSDictionary *sa=ZNIL2CPPDescribeMethodABI(source),*ta=ZNIL2CPPDescribeMethodABI(target);
    if(![sa[@"available"] boolValue]||![ta[@"available"] boolValue]){if(error)*error=@"Method Redirect runtime ABI metadata 不完整";return NO;}
    if([sa[@"generic"] boolValue]||[sa[@"inflated"] boolValue]||[ta[@"generic"] boolValue]||[ta[@"inflated"] boolValue]){if(error)*error=@"Method Redirect runtime 拒绝 generic/inflated";return NO;}
    NSArray *sp=[sa[@"parameters"] isKindOfClass:NSArray.class]?sa[@"parameters"]:@[];
    NSArray *tp=[ta[@"parameters"] isKindOfClass:NSArray.class]?ta[@"parameters"]:@[];
    if(sp.count!=tp.count){if(error)*error=@"Method Redirect runtime 参数数量变化";return NO;}
    for(NSUInteger i=0;i<sp.count;i++)if(!ZNMRCompatibleType(sp[i],tp[i])){if(error)*error=[NSString stringWithFormat:@"Method Redirect runtime 参数%lu ABI 不兼容",(unsigned long)i+1];return NO;}
    NSDictionary *sr=[sa[@"return"] isKindOfClass:NSDictionary.class]?sa[@"return"]:@{};
    NSDictionary *tr=[ta[@"return"] isKindOfClass:NSDictionary.class]?ta[@"return"]:@{};
    ZNIL2CPPABIValueKind sk=(ZNIL2CPPABIValueKind)[sr[@"kind"] integerValue],tk=(ZNIL2CPPABIValueKind)[tr[@"kind"] integerValue];
    BOOL ret=(sk==ZNIL2CPPABIValueKindVoid&&tk==ZNIL2CPPABIValueKindVoid)||(sk==tk&&ZNMRGPRKind(sk)&&ZNMRCompatibleType(sr,tr));
    if(!ret){if(error)*error=@"Method Redirect runtime 返回 ABI 不兼容";return NO;}
    if(![sa[@"instanceKnown"] boolValue]||![ta[@"instanceKnown"] boolValue]){if(error)*error=@"Method Redirect runtime 无法确认 instance/static";return NO;}
    NSUInteger sn=sp.count+([sa[@"instance"] boolValue]?1u:0u)+1u;
    NSUInteger tn=tp.count+([ta[@"instance"] boolValue]?1u:0u)+1u;
    if(sn>8||tn>8){if(error)*error=@"Method Redirect runtime 超过 x0~x7 参数预算";return NO;}
    return YES;
}

@interface ZNMethodRedirectRuntime ()
@property(nonatomic,copy,readwrite) NSString *lastStatus;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSNumber *> *slotByActionID;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,ZNRuntimeMethodActionRecord *> *recordByActionID;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSString *> *statusByActionID;
@end

@implementation ZNMethodRedirectRuntime
+ (instancetype)sharedRuntime{
    static ZNMethodRedirectRuntime *r;static dispatch_once_t once;
    dispatch_once(&once,^{r=[ZNMethodRedirectRuntime new];});
    return r;
}
- (instancetype)init{
    self=[super init];if(!self)return nil;
    _slotByActionID=[NSMutableDictionary dictionary];
    _recordByActionID=[NSMutableDictionary dictionary];
    _statusByActionID=[NSMutableDictionary dictionary];
    _lastStatus=@"Method Redirect idle";
    return self;
}

- (NSInteger)zn_freeSlot{
    for(NSUInteger i=0;i<kZNMRMaxSlots;i++)
        if(gZNMRSlots[i].source.load(std::memory_order_acquire)==0)return (NSInteger)i;
    return -1;
}

- (BOOL)zn_resolveTargetReceiverForRecord:(ZNRuntimeMethodActionRecord *)record
                                     slot:(ZNMRSlot *)slot
                                    error:(NSString **)error {
    if(!slot->targetInstance.load(std::memory_order_relaxed))return YES;
    if(slot->reuseSourceSelf.load(std::memory_order_relaxed))return YES;
    uintptr_t current=slot->targetReceiver.load(std::memory_order_acquire);
    if(current)return YES;
    NSDictionary *target=record.methodRedirectTarget?:@{};
    NSString *assembly=[target[@"assembly"] isKindOfClass:NSString.class]?target[@"assembly"]:@"Assembly-CSharp.dll";
    NSString *ns=[target[@"namespace"] isKindOfClass:NSString.class]?target[@"namespace"]:@"";
    NSString *cls=[target[@"class"] isKindOfClass:NSString.class]?target[@"class"]:@"";
    ZNIL2CPPInstanceResolver *resolver=[ZNIL2CPPInstanceResolver sharedResolver];
    uintptr_t receiver=[resolver znm44_selectedInstanceForAssembly:assembly namespace:ns className:cls];
    if(!receiver){
        NSString *diag=nil,*inner=nil;
        receiver=(uintptr_t)[resolver resolveUniqueInstanceForAssembly:assembly namespace:ns className:cls diagnostics:&diag error:&inner];
        if(!receiver){
            if(error)*error=[NSString stringWithFormat:@"Target instance 尚未可用：%@",inner?:diag?:@"没有唯一实例"];
            return NO;
        }
    }
    slot->targetReceiver.store(receiver,std::memory_order_release);
    return YES;
}

- (BOOL)zn_prepareRecord:(ZNRuntimeMethodActionRecord *)record error:(NSString **)error{
    if(!record||record.executionKind!=ZNRuntimeActionKindIL2CPPMethodRedirect){
        if(error)*error=@"Method Redirect record 类型错误";return NO;
    }
    NSNumber *actionKey=@(record.actionID);
    @synchronized(self){if(self.slotByActionID[actionKey])return YES;}

    NSDictionary *target=record.methodRedirectTarget?:@{};
    uint64_t targetRVA=[target[@"methodRVA"] unsignedLongLongValue];
    NSUInteger targetArgc=[target[@"argumentCount"] unsignedIntegerValue];
    NSArray *targetTypes=[target[@"parameterTypeNames"] isKindOfClass:NSArray.class]?target[@"parameterTypeNames"]:@[];
    BOOL targetSig=[target[@"signatureAvailable"] boolValue];

    NSString *inner=nil;
    NSDictionary *sourceCandidate=ZNMRResolveRVA(record.methodRVA,record.assembly,record.namespaceName,record.className,record.methodName,
                                                record.argumentCount,record.parameterTypeNames,record.signatureAvailable,&inner);
    if(!sourceCandidate){if(error)*error=inner;return NO;}
    NSDictionary *targetCandidate=ZNMRResolveRVA(targetRVA,
                                                [target[@"assembly"] isKindOfClass:NSString.class]?target[@"assembly"]:@"Assembly-CSharp.dll",
                                                [target[@"namespace"] isKindOfClass:NSString.class]?target[@"namespace"]:@"",
                                                [target[@"class"] isKindOfClass:NSString.class]?target[@"class"]:@"",
                                                [target[@"method"] isKindOfClass:NSString.class]?target[@"method"]:@"",
                                                targetArgc,targetTypes,targetSig,&inner);
    if(!targetCandidate){if(error)*error=inner;return NO;}
    if(!ZNMRValidateRuntimeABI(sourceCandidate,targetCandidate,&inner)){if(error)*error=inner;return NO;}

    NSDictionary *sa=ZNIL2CPPDescribeMethodABI(sourceCandidate),*ta=ZNIL2CPPDescribeMethodABI(targetCandidate);
    uintptr_t sourcePtr=[sa[@"methodPointer"] unsignedLongLongValue];
    uintptr_t targetPtr=[ta[@"methodPointer"] unsignedLongLongValue];
    uintptr_t targetMI=[ta[@"methodInfo"] unsignedLongLongValue];
    if(!sourcePtr||!targetPtr||!targetMI){if(error)*error=@"Method Redirect runtime pointer/MethodInfo 为空";return NO;}

    NSInteger index=[self zn_freeSlot];
    if(index<0){if(error)*error=[NSString stringWithFormat:@"Method Redirect V1 最多同时准备 %lu 个动作",(unsigned long)kZNMRMaxSlots];return NO;}
    ZNMRSlot *slot=&gZNMRSlots[(NSUInteger)index];
    BOOL sourceInstance=[sa[@"instance"] boolValue],targetInstance=[ta[@"instance"] boolValue];
    BOOL reuseSelf=sourceInstance&&targetInstance&&ZNMRSameOwner(record,target);

    uintptr_t original=0;
    if(![[ZNNativeHookBackend sharedBackend] installReplacementAtAddress:sourcePtr
                                                            replacement:gZNMRReplacements[(NSUInteger)index]
                                                               original:(void **)&original
                                                                  error:&inner]){
        if(error)*error=inner?:@"Method Redirect DobbyHook 失败";
        return NO;
    }

    slot->original.store(original,std::memory_order_relaxed);
    slot->target.store(targetPtr,std::memory_order_relaxed);
    slot->targetMethodInfo.store(targetMI,std::memory_order_relaxed);
    slot->targetReceiver.store(0,std::memory_order_relaxed);
    slot->sourceInstance.store(sourceInstance?1u:0u,std::memory_order_relaxed);
    slot->targetInstance.store(targetInstance?1u:0u,std::memory_order_relaxed);
    slot->reuseSourceSelf.store(reuseSelf?1u:0u,std::memory_order_relaxed);
    slot->argumentCount.store((uint32_t)record.argumentCount,std::memory_order_relaxed);
    slot->enabled.store(0,std::memory_order_relaxed);
    slot->hits.store(0,std::memory_order_relaxed);
    slot->actionID.store(record.actionID,std::memory_order_relaxed);
    slot->source.store(sourcePtr,std::memory_order_release);

    NSString *receiverStatus=@"static";
    if(targetInstance){
        if(reuseSelf)receiverStatus=@"source-self";
        else{
            NSString *receiverError=nil;
            if([self zn_resolveTargetReceiverForRecord:record slot:slot error:&receiverError])
                receiverStatus=[NSString stringWithFormat:@"target-instance=0x%llX",(unsigned long long)slot->targetReceiver.load()];
            else
                receiverStatus=@"target-instance=pending";
        }
    }

    @synchronized(self){
        self.slotByActionID[actionKey]=@(index);
        self.recordByActionID[actionKey]=record;
        self.statusByActionID[actionKey]=[NSString stringWithFormat:@"PREPARED · %@",receiverStatus];
    }
    self.lastStatus=[NSString stringWithFormat:@"PREPARED · %@ · %@",record.title?:record.canonicalIdentity,receiverStatus];
    [[ZNRuntimeLogger sharedLogger]log:[@"[method-redirect] " stringByAppendingString:self.lastStatus]];

    if([NSUserDefaults.standardUserDefaults boolForKey:ZNMRPreferenceKey(record.actionID)]){
        NSString *restoreError=nil;
        if(![self setEnabled:YES forRecord:record error:&restoreError]){
            @synchronized(self){self.statusByActionID[actionKey]=[NSString stringWithFormat:@"PREPARED · desired ON pending · %@",restoreError?:@"target not ready"];}
            [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[method-redirect] restore desired ON pending id=%u %@",record.actionID,restoreError?:@""]];
        }
    }
    return YES;
}

- (BOOL)reconcileRecords:(NSArray<ZNRuntimeMethodActionRecord *> *)records error:(NSString **)error{
    NSArray *items=[records isKindOfClass:NSArray.class]?records:@[];
    if(items.count>kZNMRMaxSlots){if(error)*error=[NSString stringWithFormat:@"Method Redirect V1 最多支持 %lu 个动作",(unsigned long)kZNMRMaxSlots];return NO;}
    NSString *firstError=nil;
    BOOL allOK=YES;
    for(ZNRuntimeMethodActionRecord *record in items){
        NSString *inner=nil;
        if(![self zn_prepareRecord:record error:&inner]){
            allOK=NO;if(!firstError)firstError=inner;
            @synchronized(self){self.statusByActionID[@(record.actionID)]=inner?:@"PREPARE FAILED";}
        }
    }
    self.lastStatus=[NSString stringWithFormat:@"Method Redirect：%lu records · %@",(unsigned long)items.count,allOK?@"READY":@"PARTIAL"];
    if(!allOK&&error)*error=firstError;
    return allOK;
}

- (BOOL)setEnabled:(BOOL)enabled forRecord:(ZNRuntimeMethodActionRecord *)record error:(NSString **)error{
    if(!record){if(error)*error=@"Method Redirect record 为空";return NO;}
    NSNumber *slotNumber=nil;
    @synchronized(self){slotNumber=self.slotByActionID[@(record.actionID)];}
    // Customer controls must not install hooks or perform prepare-time resolution.
    // The capability prepare adapter owns installation via reconcileRecords:.
    if(!slotNumber){
        if(error)*error=@"Method Redirect 尚未准备；客户端开关不会安装 Hook";
        return NO;
    }
    NSUInteger index=slotNumber.unsignedIntegerValue;
    if(index>=kZNMRMaxSlots){if(error)*error=@"Method Redirect slot 越界";return NO;}
    ZNMRSlot *slot=&gZNMRSlots[index];
    if(enabled){
        NSString *inner=nil;
        if(![self zn_resolveTargetReceiverForRecord:record slot:slot error:&inner]){
            slot->enabled.store(0,std::memory_order_release);
            if(error)*error=inner;
            return NO;
        }
    }
    slot->enabled.store(enabled?1u:0u,std::memory_order_release);
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:ZNMRPreferenceKey(record.actionID)];
    NSString *status=[NSString stringWithFormat:@"%@ · hits=%llu",enabled?@"ENABLED":@"DISABLED",
                      (unsigned long long)slot->hits.load(std::memory_order_relaxed)];
    @synchronized(self){self.statusByActionID[@(record.actionID)]=status;}
    self.lastStatus=[NSString stringWithFormat:@"%@：%@",record.title?:record.canonicalIdentity,status];
    return YES;
}

- (BOOL)isEnabledForRecord:(ZNRuntimeMethodActionRecord *)record{
    NSNumber *slotNumber=nil;@synchronized(self){slotNumber=self.slotByActionID[@(record.actionID)];}
    if(!slotNumber)return NO;
    NSUInteger index=slotNumber.unsignedIntegerValue;
    return index<kZNMRMaxSlots&&gZNMRSlots[index].enabled.load(std::memory_order_acquire)!=0;
}

- (NSString *)statusForRecord:(ZNRuntimeMethodActionRecord *)record{
    if(!record)return @"INVALID";
    @synchronized(self){return self.statusByActionID[@(record.actionID)]?:@"NOT PREPARED";}
}
@end
