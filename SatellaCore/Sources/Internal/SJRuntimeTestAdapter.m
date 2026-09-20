#import "../Public/SJRuntimeTestAdapter.h"
#import "SJStateCoordinator.h"\n#import "../Public/SJConfiguration.h"

@implementation SJRuntimeTestAdapter

+ (NSString *)simulatedVisibleImageNameForOriginalImageName:(NSString *)originalImageName {
    if (originalImageName.length == 0) return @"";
    SJStateCoordinator *state = [SJStateCoordinator shared];
    BOOL enabled;
    @synchronized (state) { enabled = state.configuration.stealthPreferenceEnabled; }
    if (enabled && [originalImageName hasSuffix:@"SatellaJailed.dylib"]) {
        return @"/usr/lib/libcrane.dylib";
    }
    return [originalImageName copy];
}

@end
