#import "ZNBuildCapabilityRegistry.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNNativeHookAction.h"

@interface ZNBuildCapabilityRegistry ()
@property(nonatomic,strong) NSMutableDictionary<NSString *, ZNBuildCapabilityProbe> *providers;
@property(nonatomic,strong) NSMutableDictionary<NSString *, NSNumber *> *providerKinds;
@property(nonatomic,assign) BOOL builtinsInstalled;
@end

@implementation ZNBuildCapabilityRegistry

+ (instancetype)sharedRegistry {
    static ZNBuildCapabilityRegistry *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry=[ZNBuildCapabilityRegistry new]; });
    [registry installBuiltinsIfNeeded];
    return registry;
}

- (instancetype)init {
    self=[super init];
    if(!self)return nil;
    _providers=[NSMutableDictionary dictionary];
    _providerKinds=[NSMutableDictionary dictionary];
    return self;
}

- (void)installBuiltinsIfNeeded {
    @synchronized(self) {
        if(self.builtinsInstalled)return;
        self.builtinsInstalled=YES;

        // Built-ins are registered exactly like future capabilities. UI never
        // needs to know which concrete stores exist.
        self.providers[@"static-patch"] = [^BOOL{
            return [ZNBinaryPatchWorkspace sharedWorkspace].filledCount > 0;
        } copy];
        self.providerKinds[@"static-patch"] = @(ZNBuildCapabilityKindStaticPatch);

        self.providers[@"runtime-method-call"] = [^BOOL{
            return [ZNRuntimeActionStore sharedStore].actionsSnapshot.count > 0;
        } copy];
        self.providerKinds[@"runtime-method-call"] = @(ZNBuildCapabilityKindRuntimeOwnedData);

        self.providers[@"native-hook"] = [^BOOL{
            return [ZNNativeHookStore sharedStore].actionsSnapshot.count > 0;
        } copy];
        self.providerKinds[@"native-hook"] = @(ZNBuildCapabilityKindRuntimeOwnedData);
    }
}

- (void)registerProviderIdentifier:(NSString *)identifier
                              kind:(ZNBuildCapabilityKind)kind
               hasBuildableContent:(ZNBuildCapabilityProbe)probe {
    NSString *key=[identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!key.length||!probe)return;
    @synchronized(self){
        self.providers[key]=[probe copy];
        self.providerKinds[key]=@(kind);
    }
}

- (void)registerProviderIdentifier:(NSString *)identifier
               hasBuildableContent:(ZNBuildCapabilityProbe)probe {
    [self registerProviderIdentifier:identifier
                                kind:ZNBuildCapabilityKindRuntimeOwnedData
                 hasBuildableContent:probe];
}

- (void)unregisterProviderIdentifier:(NSString *)identifier {
    if(!identifier.length)return;
    @synchronized(self){
        [self.providers removeObjectForKey:identifier];
        [self.providerKinds removeObjectForKey:identifier];
    }
}

- (NSArray<NSString *> *)activeProviderIdentifiers {
    NSMutableArray<NSString *> *active=[NSMutableArray array];
    NSDictionary<NSString *,ZNBuildCapabilityProbe> *snapshot=nil;
    @synchronized(self){ snapshot=[self.providers copy]; }
    NSArray<NSString *> *keys=[[snapshot allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for(NSString *key in keys){
        ZNBuildCapabilityProbe probe=snapshot[key];
        BOOL ready=NO;
        @try { ready=probe ? probe() : NO; }
        @catch(__unused NSException *exception) { ready=NO; }
        if(ready)[active addObject:key];
    }
    return [active copy];
}

- (BOOL)hasBuildableContent {
    return self.activeProviderIdentifiers.count > 0;
}

- (NSArray<NSString *> *)activeProviderIdentifiersOfKind:(ZNBuildCapabilityKind)kind {
    NSArray<NSString *> *active=self.activeProviderIdentifiers;
    NSMutableArray<NSString *> *filtered=[NSMutableArray array];
    @synchronized(self) {
        for(NSString *identifier in active) {
            NSNumber *stored=self.providerKinds[identifier];
            if(stored && stored.unsignedIntegerValue==kind) [filtered addObject:identifier];
        }
    }
    return [filtered copy];
}

- (BOOL)hasBuildableContentOfKind:(ZNBuildCapabilityKind)kind {
    return [self activeProviderIdentifiersOfKind:kind].count > 0;
}

@end

@implementation ZNBinaryBuildCoordinator

+ (instancetype)sharedCoordinator {
    static ZNBinaryBuildCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ coordinator=[ZNBinaryBuildCoordinator new]; });
    return coordinator;
}

- (NSArray<NSString *> *)activeProviderIdentifiers {
    return [ZNBuildCapabilityRegistry sharedRegistry].activeProviderIdentifiers;
}

- (BOOL)canBuild {
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(workspace.isBuilding)return NO;
    if(workspace.hasAnyApplied)return NO;
    return [ZNBuildCapabilityRegistry sharedRegistry].hasBuildableContent;
}

- (NSString *)blockedReason {
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(workspace.isBuilding)return @"正在生成二进制";
    if(workspace.hasAnyApplied)return @"生成前必须先恢复 Runtime Patch";
    if(![ZNBuildCapabilityRegistry sharedRegistry].hasBuildableContent)return @"没有可生成内容";
    return @"";
}

@end

void ZNRegisterBuildCapabilityProvider(NSString *identifier, ZNBuildCapabilityProbe probe) {
    [[ZNBuildCapabilityRegistry sharedRegistry] registerProviderIdentifier:identifier
                                                                      kind:ZNBuildCapabilityKindRuntimeOwnedData
                                                       hasBuildableContent:probe];
}

void ZNRegisterBuildCapabilityProviderWithKind(NSString *identifier,
                                               ZNBuildCapabilityKind kind,
                                               ZNBuildCapabilityProbe probe) {
    [[ZNBuildCapabilityRegistry sharedRegistry] registerProviderIdentifier:identifier
                                                                      kind:kind
                                                       hasBuildableContent:probe];
}

void ZNUnregisterBuildCapabilityProvider(NSString *identifier) {
    [[ZNBuildCapabilityRegistry sharedRegistry] unregisterProviderIdentifier:identifier];
}
