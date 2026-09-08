#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/lock.h>

static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;
static IMP gOrigNetworkHandle = NULL;
static NSString * const kTestURL = @"http://43.242.203.214/auth/login";

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase2_T2.log"];
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
    return [domain isKindOfClass:NSString.class] && [(NSString *)domain isEqualToString:@"/Api/Common/Login"];
}

static void DeliverSDKFailure(id manager, NSString *message) {
    id strongManager = manager;
    __block NSInteger retries = 0;
    __block void (^tryDeliver)(void) = nil;

    tryDeliver = [^{
        id blockObj = nil;
        @try {
            blockObj = [strongManager valueForKey:@"connectionCallBcak"];
        } @catch (NSException *e) {
            ZLog(@"[T2] callback read exception=%@", e.name);
        }

        if (blockObj) {
            NSDictionary *reply = @{
                @"result": @NO,
                @"msg": message.length ? message : @"ZONOE_T2_EMPTY_MESSAGE"
            };
            ZLog(@"[T2] delivering server-mapped SDK failure msg=%@", reply[@"msg"]);
            void (^callback)(id) = blockObj;
            callback(reply);
            tryDeliver = nil;
            return;
        }

        retries++;
        if (retries >= 40) {
            ZLog(@"[T2] callback not installed after retries; giving up");
            tryDeliver = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), tryDeliver);
    } copy];

    dispatch_async(dispatch_get_main_queue(), tryDeliver);
}

static void StartServerRouteTest(id manager) {
    id strongManager = manager;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kTestURL]
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:8.0];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    // T2 is only a route test. Do not forward the SDK username/password body over plain HTTP.
    req.HTTPBody = [@"probe=zonoe_t2" dataUsingEncoding:NSUTF8StringEncoding];

    ZLog(@"[T2] POST route test -> %@ (credential body suppressed)", kTestURL);
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            ZLog(@"[T2] server request failed domain=%@ code=%ld", error.domain, (long)error.code);
            DeliverSDKFailure(strongManager, @"ZONOE_T2_NETWORK_ERROR");
            return;
        }

        NSInteger status = 0;
        if ([response isKindOfClass:NSHTTPURLResponse.class]) {
            status = ((NSHTTPURLResponse *)response).statusCode;
        }
        ZLog(@"[T2] server response status=%ld bytes=%lu", (long)status, (unsigned long)data.length);

        NSString *message = nil;
        if (data.length) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([json isKindOfClass:NSDictionary.class]) {
                id m = [(NSDictionary *)json objectForKey:@"message"];
                if ([m isKindOfClass:NSString.class]) message = m;
            }
        }
        if (!message.length) message = @"ZONOE_T2_BAD_SERVER_RESPONSE";
        DeliverSDKFailure(strongManager, message);
    }];
}

static void NetworkHandleBridge(id self, SEL _cmd, id domain, id body, BOOL load) {
    if (IsLoginDomain(domain)) {
        NSUInteger bodyLen = [body respondsToSelector:@selector(length)] ? (NSUInteger)[body length] : 0;
        ZLog(@"[T2] intercepted login domain=%@ originalBodyLen=%lu load=%d; original SDK account request suppressed",
             domain, (unsigned long)bodyLen, load);
        StartServerRouteTest(self);
        return;
    }

    if (gOrigNetworkHandle) {
        ((void(*)(id,SEL,id,id,BOOL))gOrigNetworkHandle)(self, _cmd, domain, body, load);
    }
}

static void Install(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase2 T2 Server Route Test start ===");
        ZLog(@"[NOTE] only /Api/Common/Login is intercepted; credentials/body/token values are not logged or forwarded in T2");

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
        method_setImplementation(m, (IMP)NetworkHandleBridge);
        ZLog(@"[INSTALL] replaced KCNetworkManager route old=%p new=%p", gOrigNetworkHandle, (IMP)NetworkHandleBridge);
        ZLog(@"[READY] T2 server route test installed");
    }
}

__attribute__((constructor)) static void Entry(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ Install(); });
}
