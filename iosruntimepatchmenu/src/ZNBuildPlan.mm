#import "ZNBuildPlan.h"

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNNativeHookAction.h"

@interface ZNBuildProviderRegistry : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSString *, ZNBuildProviderProbe> *runtimeProviders;
+ (instancetype)sharedRegistry;
- (void)registerProvider:(NSString *)identifier probe:(ZNBuildProviderProbe)probe;
- (void)unregisterProvider:(NSString *)identifier;
- (NSArray<NSString *> *)activeProviders;
@end

@implementation ZNBuildProviderRegistry

+ (instancetype)sharedRegistry {
    static ZNBuildProviderRegistry *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        registry=[ZNBuildProviderRegistry new];
        registry.runtimeProviders=[NSMutableDictionary dictionary];
        [registry registerProvider:@"runtime-method-call" probe:^BOOL{
            return [ZNRuntimeActionStore sharedStore].actionsSnapshot.count > 0;
        }];
        [registry registerProvider:@"native-hook" probe:^BOOL{
            return [ZNNativeHookStore sharedStore].actionsSnapshot.count > 0;
        }];
    });
    return registry;
}

- (void)registerProvider:(NSString *)identifier probe:(ZNBuildProviderProbe)probe {
    NSString *key=[identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!key.length||!probe)return;
    @synchronized(self){ self.runtimeProviders[key]=[probe copy]; }
}

- (void)unregisterProvider:(NSString *)identifier {
    if(!identifier.length)return;
    @synchronized(self){ [self.runtimeProviders removeObjectForKey:identifier]; }
}

- (NSArray<NSString *> *)activeProviders {
    NSDictionary<NSString *,ZNBuildProviderProbe> *snapshot=nil;
    @synchronized(self){ snapshot=[self.runtimeProviders copy]; }
    NSMutableArray<NSString *> *active=[NSMutableArray array];
    for(NSString *identifier in [[snapshot allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        ZNBuildProviderProbe probe=snapshot[identifier];
        BOOL ready=NO;
        @try { ready=probe ? probe() : NO; }
        @catch(__unused NSException *exception) { ready=NO; }
        if(ready)[active addObject:identifier];
    }
    return [active copy];
}

@end

@interface ZNBuildPlan ()
@property(nonatomic,readwrite) ZNBuildMode mode;
@property(nonatomic,readwrite) BOOL canBuild;
@property(nonatomic,copy,readwrite) NSString *blockedReason;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *activeProviders;
@property(nonatomic,readwrite) NSUInteger completeStaticRows;
@property(nonatomic,readwrite) NSUInteger partialStaticRows;
@property(nonatomic,readwrite) NSUInteger runtimeProviderCount;
@end

@implementation ZNBuildPlan

+ (instancetype)currentPlan {
    return [self planForWorkspace:[ZNBinaryPatchWorkspace sharedWorkspace] includeTransientState:YES];
}

+ (instancetype)executionPlan {
    return [self planForWorkspace:[ZNBinaryPatchWorkspace sharedWorkspace] includeTransientState:NO];
}

+ (instancetype)planForWorkspace:(ZNBinaryPatchWorkspace *)workspace includeTransientState:(BOOL)includeTransientState {
    ZNBuildPlan *plan=[ZNBuildPlan new];
    if(!workspace){
        plan.mode=ZNBuildModeInvalid;
        plan.canBuild=NO;
        plan.blockedReason=@"Build workspace 不存在";
        plan.activeProviders=@[];
        return plan;
    }

    NSUInteger complete=0,partial=0;
    for(ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        BOOL offset=row.offsetText.length>0;
        BOOL enabled=row.enabledText.length>0;
        if(offset&&enabled)complete++;
        else if(offset||enabled)partial++;
    }

    NSArray<NSString *> *runtimeProviders=[[ZNBuildProviderRegistry sharedRegistry] activeProviders];
    BOOL hasRuntime=runtimeProviders.count>0;
    BOOL hasStatic=complete>0;

    plan.completeStaticRows=complete;
    plan.partialStaticRows=partial;
    plan.runtimeProviderCount=runtimeProviders.count;

    NSMutableArray<NSString *> *providers=[runtimeProviders mutableCopy] ?: [NSMutableArray array];
    if(hasStatic)[providers insertObject:@"static-patch" atIndex:0];
    plan.activeProviders=[providers copy];

    if(includeTransientState && workspace.isBuilding){
        plan.mode=ZNBuildModeInvalid;
        plan.canBuild=NO;
        plan.blockedReason=@"正在生成二进制";
        return plan;
    }
    if(workspace.hasAnyApplied){
        plan.mode=ZNBuildModeInvalid;
        plan.canBuild=NO;
        plan.blockedReason=@"生成前必须先恢复 Runtime Patch";
        return plan;
    }

    if(hasRuntime&&!hasStatic){
        // Runtime-owned actions intentionally ignore incomplete Static drafts.
        plan.mode=ZNBuildModeRuntimeOnly;
        plan.canBuild=YES;
        plan.blockedReason=@"";
        return plan;
    }

    if(hasStatic&&partial>0){
        plan.mode=ZNBuildModeInvalid;
        plan.canBuild=NO;
        plan.blockedReason=@"存在未完整填写的 Static Patch";
        return plan;
    }

    if(hasRuntime&&hasStatic){
        plan.mode=ZNBuildModeMixed;
        plan.canBuild=YES;
        plan.blockedReason=@"";
        return plan;
    }

    if(hasStatic){
        plan.mode=ZNBuildModeStaticOnly;
        plan.canBuild=YES;
        plan.blockedReason=@"";
        return plan;
    }

    if(partial>0){
        plan.mode=ZNBuildModeInvalid;
        plan.canBuild=NO;
        plan.blockedReason=@"Static Patch 未填写完整";
        return plan;
    }

    plan.mode=ZNBuildModeEmpty;
    plan.canBuild=NO;
    plan.blockedReason=@"没有可生成内容";
    return plan;
}

@end

@implementation ZNBinaryBuildCoordinator

+ (instancetype)sharedCoordinator {
    static ZNBinaryBuildCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ coordinator=[ZNBinaryBuildCoordinator new]; });
    return coordinator;
}

- (BOOL)canBuild { return [ZNBuildPlan currentPlan].canBuild; }
- (NSString *)blockedReason { return [ZNBuildPlan currentPlan].blockedReason; }
- (NSArray<NSString *> *)activeProviderIdentifiers { return [ZNBuildPlan currentPlan].activeProviders; }

@end

void ZNRegisterBuildCapabilityProvider(NSString *identifier, ZNBuildProviderProbe probe) {
    [[ZNBuildProviderRegistry sharedRegistry] registerProvider:identifier probe:probe];
}

void ZNUnregisterBuildCapabilityProvider(NSString *identifier) {
    [[ZNBuildProviderRegistry sharedRegistry] unregisterProvider:identifier];
}
