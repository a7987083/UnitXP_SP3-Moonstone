#import "SJDiagnostics.h"
#import "SJStateCoordinator.h"

@implementation SJDiagnostics

+ (void)appendModule:(NSString *)module message:(NSString *)message code:(NSInteger)code {
    if (module.length == 0 || message.length == 0) return;
    NSDictionary *entry = @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"module": [module copy],
        @"message": [message copy],
        @"code": @(code),
    };
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) {
        [state.diagnostics addObject:entry];
        if (state.diagnostics.count > 128) {
            [state.diagnostics removeObjectsInRange:NSMakeRange(0, state.diagnostics.count - 128)];
        }
    }
}

+ (NSArray<NSDictionary<NSString *, id> *> *)snapshot {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) { return [[NSArray alloc] initWithArray:state.diagnostics copyItems:YES]; }
}

+ (void)reset {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) { [state.diagnostics removeAllObjects]; }
}

@end
