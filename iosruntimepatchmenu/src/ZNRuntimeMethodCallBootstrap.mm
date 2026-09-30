#import <Foundation/Foundation.h>
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void);
extern "C" void ZNInstallMethodFinderM42UIDeferred(void);

extern "C" void ZNInstallRuntimeMethodCallDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Runtime backend + Finder stay active. Builder authoring UI is rendered
        // exclusively by M5.9.2's canonical unified Other-page renderer.
        ZNInstallRuntimeMethodCallFinderUIDeferred();
        ZNInstallMethodFinderM42UIDeferred();
        [[ZNRuntimeActionRuntime sharedRuntime] refresh];
        [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] backend/finder installed; Builder UI delegated to canonical M5.9.2 unified renderer"];
    });
}
