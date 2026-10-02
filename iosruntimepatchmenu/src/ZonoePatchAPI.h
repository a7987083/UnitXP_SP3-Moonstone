#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Stable cross-dylib C ABI. Resolve these with dlsym() from another dylib.
__attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void);
__attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void);

// Activates the same deferred bootstrap path as tapping the ZN launcher.
// Returns false only when the deferred bootstrap is already in failed state.
// Safe to call repeatedly and from a non-main thread.
__attribute__((visibility("default"))) bool ZonoePatchActivate(void);

__attribute__((visibility("default"))) void ZonoePatchStart(void);
__attribute__((visibility("default"))) void ZonoePatchShow(void);
__attribute__((visibility("default"))) void ZonoePatchHide(void);
__attribute__((visibility("default"))) bool ZonoePatchIsVisible(void);

#ifdef __cplusplus
}
#endif
