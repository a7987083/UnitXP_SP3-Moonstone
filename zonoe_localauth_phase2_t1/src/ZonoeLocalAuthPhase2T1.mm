#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/lock.h>

static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;
static IMP gOrigNetworkHandle = NULL;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase2_T1.log"];
}

static void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    os_unfair_lock_lock(&gLogLock);
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    if (!h) {
        [[NSFileManager defaultManager] createFileAtPath:LogPath() contents:nil attributes:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    }
    [h seekToEndOfFile];
    [h writeData:data];
    [h closeFile];
    os_unfair_lock_unlock(&gLogLock);
}

static BOOL IsLoginDomain(id domain) {
    if (![domain isKindOfClass:NSString.class]) return NO;
    return [(NSString *)domain isEqualToString:@"/Api/Common/Login"];
}

static void DeliverSyntheticFailure(id manager) {
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak id weakManager = manager;
        __block int retries = 0;
        __block void (^tryDeliver)(void) = nil;

        tryDeliver = [^{
            id strongManager = weakManager;
            if (!strongManager) {
                ZLog(@"[T1] manager released before callback delivery");
                tryDeliver = nil;
                return;
            }

            id blockObj = nil;
            @try {
                blockObj = [strongManager valueForKey:@"connectionCallBcak"];
            } @catch (NSException *e) {
                ZLog(@"[T1] failed reading connectionCallBcak exception=%@", e.name);
            }

            if (blockObj) {
                NSDictionary *reply = @{
                    @"result": @NO,
                    @"msg": @"ZONOE_LOCAL_AUTH_TEST"
                };
                ZLog(@"[T1] delivering synthetic SDK-compatible failure result=0 msg=ZONOE_LOCAL_AUTH_TEST");
                void (^callback)(id) = blockObj;
                callback(reply);
                tryDeliver = nil;
                return;
            }

            retries++;
            if (retries >= 20) {
                ZLog(@"[T1] callback not installed after retries; giving up");
                tryDeliver = nil;
                return;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), tryDeliver);
        } copy];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), tryDeliver);
    });
}

static void NetworkHandleProbe(id self, SEL _cmd, id domain, id body, BOOL load) {
    if (IsLoginDomain(domain)) {
        NSUInteger bodyLen = [body respondsToSelector:@selector(length)] ? (NSUInteger)[body length] : 0;
        ZLog(@"[T1] intercepted login domain=%@ bodyLen=%lu load=%d; original SDK account request suppressed",
             domain, (unsigned long)bodyLen, load);
        DeliverSyntheticFailure(self);
        return;
    }

    if (gOrigNetworkHandle) {
        ((void(*)(id,SEL,id,id,BOOL))gOrigNetworkHandle)(self, _cmd, domain, body, load);
    }
}

static void Install(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase2 T1 start ===");
        ZLog(@"[NOTE] only /Api/Common/Login is intercepted; no username/password/body/token values are logged");

        Class cls = Nil;
        for (int i = 0; i < 160; ++i) {
            cls = objc_getClass("KCNetworkManager");
            if (cls) break;
            [NSThread sleepForTimeInterval:0.25];
        }

        if (!cls) {
            ZLog(@"[INSTALL] KCNetworkManager not found");
            return;
        }

        SEL sel = sel_registerName("KCNetworkHandleWithDomain:andBodyStr:andLoad:");
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) {
            ZLog(@"[INSTALL] target method missing");
            return;
        }

        gOrigNetworkHandle = method_getImplementation(m);
        method_setImplementation(m, (IMP)NetworkHandleProbe);
        ZLog(@"[INSTALL] replaced KCNetworkManager KCNetworkHandleWithDomain:andBodyStr:andLoad: old=%p new=%p",
             gOrigNetworkHandle, (IMP)NetworkHandleProbe);
        ZLog(@"[READY] T1 fixed-failure route test installed");
    }
}

__attribute__((constructor)) static void Entry(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        Install();
    });
}
