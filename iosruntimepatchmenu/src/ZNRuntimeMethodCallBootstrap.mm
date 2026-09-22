#import <Foundation/Foundation.h>
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallBuilderUIDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallFeatureUIDeferred(void);
extern "C" void ZNInstallMethodFinderM42UIDeferred(void);

extern "C" void ZNInstallRuntimeMethodCallDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZNInstallRuntimeMethodCallFinderUIDeferred();
        ZNInstallRuntimeMethodCallBuilderUIDeferred();
        ZNInstallRuntimeMethodCallFeatureUIDeferred();
        ZNInstallMethodFinderM42UIDeferred();
        [[ZNRuntimeActionRuntime sharedRuntime] refresh];
        [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] M4.2 installed: /0 + typed /1 static invoke, arity-filtered Method Finder UI"];
    });
}
