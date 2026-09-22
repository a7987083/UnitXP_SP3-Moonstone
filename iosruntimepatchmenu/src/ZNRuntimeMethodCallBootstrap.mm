#import <Foundation/Foundation.h>
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallBuilderUIDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallFeatureUIDeferred(void);

extern "C" void ZNInstallRuntimeMethodCallDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZNInstallRuntimeMethodCallFinderUIDeferred();
        ZNInstallRuntimeMethodCallBuilderUIDeferred();
        ZNInstallRuntimeMethodCallFeatureUIDeferred();
        [[ZNRuntimeActionRuntime sharedRuntime] refresh];
        [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] M4.1 installed: embedded action table + zero-arg static invoke"];
    });
}
