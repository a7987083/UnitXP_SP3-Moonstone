#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// v0.5.6.2 sealed build: activation tracing is compiled out.
// Keep the timing helper because Static Dispatch diagnostics use it, but make
// all trace/log calls and log-path references disappear at preprocessing time.
#define ZNActivationTraceLog(...) do { } while (0)
#define ZNActivationTraceLogPath() @""

static inline double ZNActivationTraceNow(void) {
    return CFAbsoluteTimeGetCurrent();
}

NS_ASSUME_NONNULL_END
