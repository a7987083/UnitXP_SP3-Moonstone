#import <Foundation/Foundation.h>
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallBuilderUIDeferred(void);
extern "C" void ZNInstallMethodFinderM42UIDeferred(void);

extern "C" void ZNInstallRuntimeMethodCallDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Finder + Builder authoring remain part of the Runtime Method backend.
        ZNInstallRuntimeMethodCallFinderUIDeferred();
        ZNInstallRuntimeMethodCallBuilderUIDeferred();

        // Historical duplicate customer Runtime UI remains disabled. The
        // canonical Feature page performs the one initial Runtime metadata scan
        // after all backend adapters are installed; render/layout never scans.
        ZNInstallMethodFinderM42UIDeferred();
        [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] backend installed; discovery owned by canonical Feature snapshot"];
    });
}
