#import "ZNPreparedClientRuntime.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <uuid/uuid.h>
#include <string.h>

#import "ZNComplexStructCodec.h"
#import "ZNComplexStructCodecResolver.h"
#import "ZNDirectNativeCallEngine.h"
#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNPatchCore.h"

static const uint32_t kZNM614MethodAttributeStatic=0x0010u;
typedef uint32_t (*ZNM614MethodGetFlagsFn)(const void *,uint32_t *);

static NSString *ZNM614RuntimeUUIDForHeader(const struct mach_header_64 *mh) {
    if(!mh||mh->magic!=MH_MAGIC_64)return @"";
    const uint8_t *cursor=(const uint8_t *)(mh+1),*limit=cursor+mh->sizeofcmds;
    if(mh->ncmds>4096||mh->sizeofcmds>16*1024*1024)return @"";
    for(uint32_t i=0;i<mh->ncmds;i++){
        if(cursor+sizeof(struct load_command)>limit)return @"";
        const struct load_command *lc=(const struct load_command *)cursor;
        if(lc->cmdsize<sizeof(*lc)||cursor+lc->cmdsize>limit)return @"";
        if(lc->cmd==LC_UUID&&lc->cmdsize>=sizeof(struct uuid_command)){
            const struct uuid_command *uc=(const struct uuid_command *)cursor;
            uuid_t bytes={0};memcpy(bytes,uc->uuid,sizeof(bytes));
            NSUUID *uuid=[[NSUUID alloc]initWithUUIDBytes:bytes];
            return uuid.UUIDString.uppercaseString?:@"";
        }
        cursor+=lc->cmdsize;
    }
    return @"";
}

static ZNRuntimeMethodAction *ZNM614PreparedActionForChainNode(NSDictionary *node) {
    ZNRuntimeMethodAction *action=[ZNRuntimeMethodAction new];
    action.title=[node[@"title"] isKindOfClass:NSString.class]?node[@"title"]:@"Chain Node";
    action.group=@"Immediate Chain";
    action.assembly=[node[@"assembly"] isKindOfClass:NSString.class]?node[@"assembly"]:@"Assembly-CSharp.dll";
    action.namespaceName=[node[@"namespace"] isKindOfClass:NSString.class]?node[@"namespace"]:@"";
    action.className=[node[@"class"] isKindOfClass:NSString.class]?node[@"class"]:@"";
    action.methodName=[node[@"method"] isKindOfClass:NSString.class]?node[@"method"]:@"";
    action.argumentValues=[node[@"argumentValues"] isKindOfClass:NSArray.class]?node[@"argumentValues"]:@[];
    action.parameterTypeNames=[node[@"parameterTypeNames"] isKindOfClass:NSArray.class]?node[@"parameterTypeNames"]:@[];
    action.argumentCount=action.argumentValues.count;
    action.signatureAvailable=action.parameterTypeNames.count==action.argumentCount;
    action.argumentControlConfigs=@[];
    action.immediateChain=@{};
    return action;
}

static NSDictionary *ZNM614ResolvePreparedAction(ZNRuntimeMethodAction *action,NSString **error) {
    if(action.signatureAvailable&&action.parameterTypeNames.count==action.argumentCount){
        return [[ZNIL2CPPFullSignatureResolver sharedResolver]
            resolveAssembly:action.assembly
                   namespace:action.namespaceName?:@""
                   className:action.className
                      method:action.methodName
          parameterTypeNames:action.parameterTypeNames
                       error:error];
    }
    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    NSDictionary *resolved=[resolver resolveMethodAssembly:action.assembly
                                                  namespace:action.namespaceName?:@""
                                                  className:action.className
                                                     method:action.methodName
                                              argumentCount:(NSInteger)action.argumentCount];
    if(!resolved&&error)*error=resolver.lastError?:@"Prepared action resolve 失败";
    return resolved;
}

static NSDictionary *ZNM614ResolveRecord(ZNRuntimeMethodActionRecord *record,NSString **error) {
    if(record.signatureAvailable&&record.parameterTypeNames.count==record.argumentCount){
        return [[ZNIL2CPPFullSignatureResolver sharedResolver]
            resolveAssembly:record.assembly
                   namespace:record.namespaceName?:@""
                   className:record.className
                      method:record.methodName
          parameterTypeNames:record.parameterTypeNames
                       error:error];
    }
    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    NSDictionary *resolved=[resolver resolveMethodAssembly:record.assembly
                                                  namespace:record.namespaceName?:@""
                                                  className:record.className
                                                     method:record.methodName
                                              argumentCount:(NSInteger)record.argumentCount];
    if(!resolved&&error)*error=resolver.lastError?:@"Prepared Client resolve 失败";
    return resolved;
}

@interface ZNPreparedClientRuntime ()
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSDictionary *> *bindings;
@property(nonatomic,assign) BOOL started;
@property(nonatomic,assign) BOOL scheduled;
@property(nonatomic,assign) NSUInteger retryCount;
@end

static void ZNM614PreparedImageAdded(const struct mach_header *mh,intptr_t slide) {
    (void)mh;(void)slide;
    [[ZNPreparedClientRuntime sharedRuntime] requestReconcile];
}

@implementation ZNPreparedClientRuntime

+ (instancetype)sharedRuntime {
    static ZNPreparedClientRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{runtime=[ZNPreparedClientRuntime new];});
    return runtime;
}

- (instancetype)init {
    self=[super init];
    if(!self)return nil;
    _queue=dispatch_queue_create("com.zonoe.prepared-client-runtime",DISPATCH_QUEUE_SERIAL);
    _bindings=[NSMutableDictionary dictionary];
    return self;
}

- (void)start {
    @synchronized(self){if(self.started)return;self.started=YES;}
    _dyld_register_func_for_add_image(ZNM614PreparedImageAdded);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(zn_appActive:)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];
    [self requestReconcile];
    [[ZNRuntimeLogger sharedLogger]log:@"[m6.14-prepared-client] bootstrap started; generated Runtime/Direct are prepared-only"];
}

- (void)zn_appActive:(NSNotification *)note {(void)note;[self requestReconcile];}

- (void)requestReconcile {
    @synchronized(self){if(self.scheduled)return;self.scheduled=YES;}
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.queue,^{
        typeof(self) self=weakSelf;if(!self)return;
        BOOL pending=[self zn_reconcileNow];
        @synchronized(self){self.scheduled=NO;}
        if(pending&&self.retryCount<8){
            self.retryCount++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.75*NSEC_PER_SEC)),self.queue,^{
                [self requestReconcile];
            });
        }else if(!pending){
            self.retryCount=0;
        }
    });
}

- (BOOL)zn_reconcileNow {
    // Static metadata is also discovered during startup. Historical customer UI
    // refresh() calls therefore hit the O(1) discovery cache instead of scanning.
    [[ZNStaticDispatchRuntime sharedRuntime] refresh];
    ZNRuntimeActionRuntime *table=[ZNRuntimeActionRuntime sharedRuntime];
    [table refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *all=[(table.records?:@[]) arrayByAddingObjectsFromArray:table.directRecords?:@[]];
    if(!all.count)return NO;

    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if(!resolver.isAvailable)return YES;

    void *handle=NULL;
#ifdef RTLD_NOLOAD
    if(resolver.unityPath.length)handle=dlopen(resolver.unityPath.fileSystemRepresentation,RTLD_LAZY|RTLD_NOLOAD);
#else
    if(resolver.unityPath.length)handle=dlopen(resolver.unityPath.fileSystemRepresentation,RTLD_LAZY);
#endif
    ZNM614MethodGetFlagsFn getFlags=(ZNM614MethodGetFlagsFn)(handle?dlsym(handle,"il2cpp_method_get_flags"):NULL);
    if(!getFlags)getFlags=(ZNM614MethodGetFlagsFn)dlsym(RTLD_DEFAULT,"il2cpp_method_get_flags");
    if(!getFlags){if(handle)dlclose(handle);return YES;}

    BOOL pendingReceiver=NO;
    for(ZNRuntimeMethodActionRecord *record in all){
        if(!record.preparedDescriptor||!record.preparedRVA||!record.preparedUUID.length||!record.preparedStaticKnown)continue;
        NSString *inner=nil;
        NSDictionary *resolved=ZNM614ResolveRecord(record,&inner);
        uintptr_t methodInfo=[resolved[@"methodInfo"] unsignedLongLongValue];
        uintptr_t pointer=[resolved[@"methodPointer"] unsignedLongLongValue];
        if(!methodInfo||!pointer){
            [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.14-prepared-client] bind pending %@ error=%@",record.canonicalIdentity,inner?:@"resolve"]];
            continue;
        }

        Dl_info info={0};
        if(dladdr((const void *)pointer,&info)==0||!info.dli_fbase)continue;
        uintptr_t base=(uintptr_t)info.dli_fbase;
        NSString *uuid=ZNM614RuntimeUUIDForHeader((const struct mach_header_64 *)base);
        if(![uuid isEqualToString:record.preparedUUID]||pointer<base||(uint64_t)(pointer-base)!=record.preparedRVA){
            [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.14-prepared-client] descriptor mismatch %@",record.canonicalIdentity]];
            continue;
        }

        uint32_t implFlags=0;
        BOOL isStatic=(getFlags((const void *)methodInfo,&implFlags)&kZNM614MethodAttributeStatic)!=0;
        if(isStatic!=record.preparedIsStatic)continue;

        NSMutableDictionary *candidate=[resolved mutableCopy]?:[NSMutableDictionary dictionary];
        candidate[@"assembly"]=record.assembly?:@"";
        candidate[@"namespace"]=record.namespaceName?:@"";
        candidate[@"class"]=record.className?:@"";
        candidate[@"method"]=record.methodName?:@"";
        candidate[@"argumentCount"]=@(record.argumentCount);
        candidate[@"canonical"]=record.canonicalIdentity?:@"";

        if(record.executionKind==ZNRuntimeActionKindDirectNativeCall){
            NSString *why=nil;
            if(![[ZNDirectNativeCallEngine sharedEngine] supportsCandidate:candidate reason:&why]){
                [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.14-prepared-client] direct ABI rejected %@ %@",record.canonicalIdentity,why?:@""]];
                continue;
            }
            BOOL codecReady=YES;
            for(NSString *type in record.parameterTypeNames?:@[]){
                if(ZNComplexStructCodecKeyForManagedType(type).length){
                    NSString *codecError=nil;
                    if(![[ZNDirectNativeCallEngine sharedEngine] prepareManagedType:type error:&codecError]){
                        codecReady=NO;
                        [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.14-prepared-client] codec prewarm rejected %@ %@",record.canonicalIdentity,codecError?:@""]];
                        break;
                    }
                }
            }
            if(!codecReady)continue;
        }

        uintptr_t receiver=0;
        NSDictionary *existing=nil;
        @synchronized(self){existing=self.bindings[@(record.actionID)];}
        if(!isStatic){
            receiver=[existing[@"receiver"] unsignedLongLongValue];
            if(!receiver){
                ZNIL2CPPInstanceResolver *instance=[ZNIL2CPPInstanceResolver sharedResolver];
                receiver=[instance znm44_selectedInstanceForAssembly:record.assembly namespace:record.namespaceName?:@"" className:record.className];
                if(!receiver){
                    NSString *diag=nil,*instanceError=nil;
                    receiver=(uintptr_t)[instance resolveUniqueInstanceForAssembly:record.assembly
                                                                         namespace:record.namespaceName?:@""
                                                                         className:record.className
                                                                       diagnostics:&diag error:&instanceError];
                }
            }
            if(!receiver)pendingReceiver=YES;
        }

        NSMutableDictionary *chainBindings=[NSMutableDictionary dictionary];
        NSDictionary *chain=[record.immediateChain isKindOfClass:NSDictionary.class]?record.immediateChain:nil;
        NSArray *nodes=([chain[@"version"] integerValue]==2&&[chain[@"nodes"] isKindOfClass:NSArray.class])?chain[@"nodes"]:nil;
        for(NSDictionary *node in nodes?:@[]){
            if(![node[@"prepared"] boolValue] ||
               ![node[@"preparedRVA"] unsignedLongLongValue] ||
               ![node[@"preparedUUID"] isKindOfClass:NSString.class] ||
               ![(NSString *)node[@"preparedUUID"] length] ||
               ![node[@"preparedStaticKnown"] boolValue]){
                continue;
            }
            ZNRuntimeMethodAction *nodeAction=ZNM614PreparedActionForChainNode(node);
            NSString *nodeError=nil;
            NSDictionary *nodeResolved=ZNM614ResolvePreparedAction(nodeAction,&nodeError);
            uintptr_t nodeMI=[nodeResolved[@"methodInfo"] unsignedLongLongValue];
            uintptr_t nodePointer=[nodeResolved[@"methodPointer"] unsignedLongLongValue];
            if(!nodeMI||!nodePointer)continue;
            Dl_info nodeInfo={0};
            if(dladdr((const void *)nodePointer,&nodeInfo)==0||!nodeInfo.dli_fbase)continue;
            uintptr_t nodeBase=(uintptr_t)nodeInfo.dli_fbase;
            NSString *nodeUUID=ZNM614RuntimeUUIDForHeader((const struct mach_header_64 *)nodeBase);
            if(![nodeUUID isEqualToString:node[@"preparedUUID"]] ||
               nodePointer<nodeBase ||
               (uint64_t)(nodePointer-nodeBase)!=[node[@"preparedRVA"] unsignedLongLongValue])continue;
            uint32_t nodeImpl=0;
            BOOL nodeStatic=(getFlags((const void *)nodeMI,&nodeImpl)&kZNM614MethodAttributeStatic)!=0;
            if(nodeStatic!=[node[@"preparedIsStatic"] boolValue])continue;
            NSMutableDictionary *nodeCandidate=[nodeResolved mutableCopy]?:[NSMutableDictionary dictionary];
            nodeCandidate[@"assembly"]=nodeAction.assembly?:@"";
            nodeCandidate[@"namespace"]=nodeAction.namespaceName?:@"";
            nodeCandidate[@"class"]=nodeAction.className?:@"";
            nodeCandidate[@"method"]=nodeAction.methodName?:@"";
            nodeCandidate[@"argumentCount"]=@(nodeAction.argumentCount);
            nodeCandidate[@"canonical"]=nodeAction.canonicalIdentity?:@"";
            chainBindings[nodeAction.canonicalIdentity?:@""]=@{@"resolved":[nodeCandidate copy],
                                                                @"static":@(nodeStatic)};
        }

        NSDictionary *binding=@{@"resolved":[candidate copy],
                                @"receiver":@(receiver),
                                @"static":@(isStatic),
                                @"identity":record.canonicalIdentity?:@"",
                                @"chainBindings":[chainBindings copy]};
        @synchronized(self){self.bindings[@(record.actionID)]=binding;}
    }
    if(handle)dlclose(handle);
    return pendingReceiver;
}

- (BOOL)isPreparedActionID:(uint32_t)actionID {
    @synchronized(self){return self.bindings[@(actionID)]!=nil;}
}

- (ZNRuntimeMethodAction *)zn_actionFromRecord:(ZNRuntimeMethodActionRecord *)record values:(NSArray<NSString *> *)values {
    ZNRuntimeMethodAction *a=[ZNRuntimeMethodAction new];
    a.actionID=record.actionID;a.title=record.title;a.group=record.group;a.featureDescription=record.featureDescription?:@"";
    a.assembly=record.assembly;a.namespaceName=record.namespaceName;a.className=record.className;a.methodName=record.methodName;
    a.argumentCount=record.argumentCount;a.argumentValues=values?:record.argumentValues?:@[];
    a.parameterTypeNames=record.parameterTypeNames?:@[];
    // The exact overload was already resolved and verified during startup.
    // Keep signature metadata for parameter ABI display, but bypass authoring-time
    // full-signature resolver swizzles during the click path.
    a.signatureAvailable=NO;
    a.argumentControlConfigs=record.argumentControlConfigs?:@[];a.immediateChain=record.immediateChain?:@{};
    return a;
}

- (NSDictionary *)zn_contextForRecord:(ZNRuntimeMethodActionRecord *)record binding:(NSDictionary *)binding {
    return @{@"assembly":record.assembly?:@"",
             @"namespace":record.namespaceName?:@"",
             @"class":record.className?:@"",
             @"method":record.methodName?:@"",
             @"argumentCount":@(record.argumentCount),
             @"resolved":binding[@"resolved"]?:@{},
             @"receiver":binding[@"receiver"]?:@0,
             @"chainBindings":binding[@"chainBindings"]?:@{}};
}

- (BOOL)executeRuntimeRecord:(ZNRuntimeMethodActionRecord *)record values:(NSArray<NSString *> *)values error:(NSString **)error {
    NSDictionary *binding=nil;@synchronized(self){binding=self.bindings[@(record.actionID)];}
    if(!binding){if(error)*error=@"FAILED_PREPARED_NOT_READY：客户端启动绑定尚未完成";return NO;}
    BOOL isStatic=[binding[@"static"] boolValue];uintptr_t receiver=[binding[@"receiver"] unsignedLongLongValue];
    if(!isStatic&&!receiver){if(error)*error=@"FAILED_PREPARED_RECEIVER：receiver 尚未由启动期后台绑定";return NO;}
    ZNRuntimeMethodAction *action=[self zn_actionFromRecord:record values:values];
    NSDictionary *ctx=[self zn_contextForRecord:record binding:binding];
    ZNIL2CPPPreparedExecutionPush(ctx);
    NSDictionary *result=nil;NSString *inner=nil;
    @try {result=[[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action receiver:receiver error:&inner];}
    @finally {ZNIL2CPPPreparedExecutionPop();}
    if(!result){if(error)*error=inner?:@"Prepared Runtime 执行失败";return NO;}
    return YES;
}

- (BOOL)executeDirectRecord:(ZNRuntimeMethodActionRecord *)record values:(NSArray<NSString *> *)values error:(NSString **)error {
    NSDictionary *binding=nil;@synchronized(self){binding=self.bindings[@(record.actionID)];}
    if(!binding){if(error)*error=@"FAILED_PREPARED_NOT_READY：Direct Call 启动绑定尚未完成";return NO;}
    BOOL isStatic=[binding[@"static"] boolValue];uintptr_t receiver=[binding[@"receiver"] unsignedLongLongValue];
    if(!isStatic&&!receiver){if(error)*error=@"FAILED_PREPARED_RECEIVER：Direct Call receiver 尚未准备";return NO;}
    NSMutableDictionary *candidate=[binding[@"resolved"] mutableCopy]?:[NSMutableDictionary dictionary];
    candidate[@"preparedReceiver"]=@(receiver);
    NSDictionary *ctx=[self zn_contextForRecord:record binding:binding];
    ZNIL2CPPPreparedExecutionPush(ctx);
    NSDictionary *result=nil;NSString *inner=nil;
    @try {result=[[ZNDirectNativeCallEngine sharedEngine] executeCandidate:candidate argumentValues:values?:record.argumentValues?:@[] error:&inner];}
    @finally {ZNIL2CPPPreparedExecutionPop();}
    if(!result){if(error)*error=inner?:@"Prepared Direct Call 执行失败";return NO;}
    return YES;
}

@end

__attribute__((constructor(202))) static void ZNM614PreparedClientBootstrap(void) {
    @autoreleasepool {[[ZNPreparedClientRuntime sharedRuntime] start];}
}
