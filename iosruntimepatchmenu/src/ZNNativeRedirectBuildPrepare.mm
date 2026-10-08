#import "ZNNativeRedirectBuildPrepare.h"

#import "ZNNativeRedirectAction.h"
#import "ZNNativeRedirectRuntime.h"
#import "ZNBuildManifest.h"
#import "ZNBuildCapabilityRegistry.h"
#import "ZNBuildItem.h"
#import "ZNIL2CPPResolver.h"

/// M6.13.10 Method Redirect build provider.
///
/// Important: the retired Native Branch Redirect implementation intentionally
/// does NOT materialize Method Redirect as a Static Patch/B instruction.
/// Until the prepared method-bridge descriptor is emitted, generation fails
/// closed instead of silently producing offset-equivalent behavior.
void ZNInstallNativeRedirectBuildProvider(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        ZNRegisterBuildCapabilityProvider(@"native-redirect",^BOOL{
            return [ZNNativeRedirectStore sharedStore].actionsSnapshot.count>0;
        });

        ZNRegisterBuildItemProvider(@"native-redirect",
            ^NSArray<ZNBuildItem *> *(ZNBinaryPatchWorkspace *workspace){
                (void)workspace;
                NSMutableArray *items=[NSMutableArray array];
                [[ZNNativeRedirectStore sharedStore].actionsSnapshot enumerateObjectsUsingBlock:
                    ^(ZNNativeRedirectAction *a,NSUInteger idx,BOOL *stop){
                        (void)stop;
                        [items addObject:[ZNBuildItem itemWithProvider:@"native-redirect"
                                                                  kind:@"method-redirect"
                                                            identifier:a.canonicalIdentity
                                                                domain:ZNBuildItemDomainRuntime
                                                              metadata:@{@"index":@(idx),@"title":a.title?:@""}]];
                    }];
                return items;
            },
            ^BOOL(ZNBuildManifest *manifest,ZNBinaryPatchWorkspace *workspace,NSString **error){
                (void)manifest;(void)workspace;
                ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
                [resolver refresh];
                if(!resolver.isAvailable){
                    if(error)*error=@"Method Redirect 生成前 IL2CPP Runtime 必须 Ready";
                    return NO;
                }
                for(ZNNativeRedirectAction *a in [ZNNativeRedirectStore sharedStore].actionsSnapshot){
                    NSDictionary *source=[resolver resolveMethodAssembly:a.sourceAssembly
                                                               namespace:a.sourceNamespace?:@""
                                                               className:a.sourceClass
                                                                  method:a.sourceMethod
                                                           argumentCount:(NSInteger)a.sourceArgumentCount];
                    NSDictionary *target=[resolver resolveMethodAssembly:a.targetAssembly
                                                               namespace:a.targetNamespace?:@""
                                                               className:a.targetClass
                                                                  method:a.targetMethod
                                                           argumentCount:(NSInteger)a.targetArgumentCount];
                    NSString *why=nil;
                    if(![[ZNNativeRedirectRuntime sharedRuntime] supportsSourceCandidate:source?:@{}
                                                                        targetCandidate:target?:@{}
                                                                                 reason:&why]){
                        if(error)*error=[NSString stringWithFormat:@"%@：%@",a.canonicalIdentity,why?:@"ABI incompatible"];
                        return NO;
                    }
                }
                return YES;
            },
            ^BOOL(ZNBuildManifest *manifest,NSArray<NSString *> *outputs,BOOL runtimeOnlyBase,NSString **report,NSString **error){
                (void)manifest;(void)outputs;(void)runtimeOnlyBase;(void)report;
                if(error)*error=@"Method Redirect M6.13.10：Prepared Bridge descriptor 尚未接入；已禁止回退成 B/BL Static Patch";
                return NO;
            });
    });
}

__attribute__((constructor)) static void ZNRDInstallProviderCtor(void) {
    ZNInstallNativeRedirectBuildProvider();
}
