#import "ZNActivationTrace.h"
#import "ZNPatchCore.h"

static NSString *gZNActivationTracePath = nil;
static NSObject *gZNActivationTraceLock = nil;
static dispatch_once_t gZNActivationTraceOnce;

static void ZNActivationTraceEnsureReady(void) {
    dispatch_once(&gZNActivationTraceOnce, ^{
        gZNActivationTraceLock = [NSObject new];
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
        gZNActivationTracePath = [documents stringByAppendingPathComponent:@"ZonoPatch-v0.5.6.1.log"];

        NSDateFormatter *fmt = [NSDateFormatter new];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *header = [NSString stringWithFormat:
                            @"[%@] ZonoPatch v0.5.6.1 activation trace start · pid=%d\n",
                            [fmt stringFromDate:[NSDate date]],
                            NSProcessInfo.processInfo.processIdentifier];
        NSData *data = [header dataUsingEncoding:NSUTF8StringEncoding];
        [NSFileManager.defaultManager createFileAtPath:gZNActivationTracePath contents:data attributes:nil];
        NSLog(@"[ZonoPatch] [activation-trace] file=%@", gZNActivationTracePath);
    });
}

NSString *ZNActivationTraceLogPath(void) {
    ZNActivationTraceEnsureReady();
    return gZNActivationTracePath ?: @"";
}

double ZNActivationTraceNow(void) {
    return CFAbsoluteTimeGetCurrent();
}

void ZNActivationTraceLog(NSString *message) {
    if (!message.length) return;
    ZNActivationTraceEnsureReady();

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [fmt stringFromDate:[NSDate date]],
                      message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    @synchronized (gZNActivationTraceLock) {
        @try {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:gZNActivationTracePath];
            if (!handle) {
                [NSFileManager.defaultManager createFileAtPath:gZNActivationTracePath contents:nil attributes:nil];
                handle = [NSFileHandle fileHandleForWritingAtPath:gZNActivationTracePath];
            }
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle closeFile];
        } @catch (__unused NSException *exception) {
            // Diagnostics must never affect activation behavior.
        }
    }

    [[ZNRuntimeLogger sharedLogger] log:message];
}
