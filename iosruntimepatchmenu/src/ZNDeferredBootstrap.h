#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Cold means only the launcher exists. Loading/Ready are entered exclusively
// by the first launcher tap; feature/runtime modules must not initialize before it.
FOUNDATION_EXPORT BOOL ZNDeferredBootstrapIsActivated(void)
    __attribute__((visibility("hidden")));
FOUNDATION_EXPORT BOOL ZNDeferredBootstrapIsReady(void)
    __attribute__((visibility("hidden")));

// Programmatic entry used by the exported cross-dylib API. It preserves the
// exact deferred bootstrap path used by the launcher tap and is idempotent.
FOUNDATION_EXPORT BOOL ZNDeferredBootstrapActivate(void)
    __attribute__((visibility("hidden")));

#ifdef __cplusplus
}
#endif
