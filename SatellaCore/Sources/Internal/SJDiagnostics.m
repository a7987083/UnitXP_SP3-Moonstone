#import "SJDiagnostics.h"

@implementation SJDiagnostics

static NSMutableArray<NSDictionary<NSString *, id> *> *SJEntries(void) {
    static NSMutableArray<NSDictionary<NSString *, id> *> *entries;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        entries = [NSMutableArray array];
    });
    return entries;
}

+ (void)appendModule:(NSString *)module message:(NSString *)message code:(NSInteger)code {
    if (module.length == 0 || message.length == 0) {
        return;
    }
    NSDictionary *entry = @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"module": module,
        @"message": message,
        @"code": @(code),
    };
    @synchronized (SJEntries()) {
        [SJEntries() addObject:entry];
        if (SJEntries().count > 128) {
            [SJEntries() removeObjectsInRange:NSMakeRange(0, SJEntries().count - 128)];
        }
    }
}

+ (NSArray<NSDictionary<NSString *, id> *> *)snapshot {
    @synchronized (SJEntries()) {
        return [SJEntries() copy];
    }
}

+ (void)reset {
    @synchronized (SJEntries()) {
        [SJEntries() removeAllObjects];
    }
}

@end
