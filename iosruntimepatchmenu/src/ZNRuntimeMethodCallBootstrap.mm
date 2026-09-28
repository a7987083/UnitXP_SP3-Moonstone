#import <Foundation/Foundation.h>
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void);
extern "C" void ZNInstallMethodFinderM42UIDeferred(void);

extern "C" void ZNInstallRuntimeMethodCallDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // M6.3: Finder stays available, but the historical Builder UI wrapper
        // is intentionally NOT installed. Authoring presentation must be owned
        // by the single canonical authoring surface, never appended as a layer.
        ZNInstallRuntimeMethodCallFinderUIDeferred();
        ZNInstallMethodFinderM42UIDeferred();
        [[ZNRuntimeActionRuntime sharedRuntime] refresh];
        [[ZNRuntimeLogger sharedLogger] log:@"[m6.3] Runtime backend installed; layered Runtime Builder renderer disabled"];
    });
}
