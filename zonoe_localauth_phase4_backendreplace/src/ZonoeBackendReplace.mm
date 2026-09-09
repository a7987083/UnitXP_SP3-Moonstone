#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>

static NSString * const kLocalBase = @"http://43.242.203.214";
static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;

typedef void (*KCNetworkIMP)(id, SEL, NSString *, NSString *, BOOL);
static KCNetworkIMP gOrigKCNetwork = NULL;
static BOOL gInstalled = NO;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase4_BackendReplace.log"];
}

static void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body ?: @""];
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

static NSString *MappedPath(NSString *domain) {
    if (![domain isKindOfClass:NSString.class] || domain.length == 0) return nil;
    NSString *lower = domain.lowercaseString;
    if ([lower containsString:@"/api/common/login"]) return @"/auth/login?compat=pandora";
    if ([lower containsString:@"/api/common/register"]) return @"/auth/register?compat=pandora";

    /* The supplied SDK binary exposes a web based forget-password flow rather than
       a confirmed /Api/Common password-change route. Keep a narrow compatibility
       fallback for password/reset routes and log only the route, never the body. */
    if ([lower containsString:@"forgetpwd"] ||
        [lower containsString:@"change_password"] ||
        [lower containsString:@"changepassword"] ||
        [lower containsString:@"resetpassword"] ||
        [lower containsString:@"reset_password"]) {
        return @"/auth/change_password?compat=pandora";
    }
    return nil;
}

static void SendToLocalBackend(id manager, NSString *domain, NSString *body, BOOL load) {
    NSString *path = MappedPath(domain);
    if (!path) return;

    NSString *urlString = [kLocalBase stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        ZLog(@"[P4] invalid local URL route=%@", path);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:15.0];
    req.HTTPMethod = @"POST";
    if ([body isKindOfClass:NSString.class] && body.length > 0) {
        req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    }
    [req setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    ZLog(@"[P4] route %@ -> %@ load=%d bodyBytes=%lu",
         domain ?: @"<nil>", path, load,
         (unsigned long)(req.HTTPBody.length));

    /* Use the original KCNetworkManager instance as NSURLConnection delegate so
       its existing response parsing / UI callbacks remain intact. */
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:req delegate:manager startImmediately:YES];
    (void)conn;
}

static void ZonoeKCNetworkHandle(id self, SEL _cmd, NSString *domain, NSString *body, BOOL load) {
    NSString *mapped = MappedPath(domain);
    if (!mapped) {
        if (gOrigKCNetwork) gOrigKCNetwork(self, _cmd, domain, body, load);
        return;
    }
    SendToLocalBackend(self, domain, body, load);
}

static void TryInstall(void) {
    @synchronized(NSClassFromString(@"NSObject")) {
        if (gInstalled) return;
        Class cls = NSClassFromString(@"KCNetworkManager");
        if (!cls) return;

        SEL sel = NSSelectorFromString(@"KCNetworkHandleWithDomain:andBodyStr:andLoad:");
        Method method = class_getInstanceMethod(cls, sel);
        if (!method) {
            ZLog(@"[P4] KCNetworkManager found but selector missing");
            return;
        }

        IMP current = method_getImplementation(method);
        if (current == (IMP)ZonoeKCNetworkHandle) {
            gInstalled = YES;
            return;
        }

        gOrigKCNetwork = (KCNetworkIMP)current;
        method_setImplementation(method, (IMP)ZonoeKCNetworkHandle);
        gInstalled = YES;
        ZLog(@"[P4] installed KCNetworkManager backend replacement");
    }
}

static void ImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)mh; (void)slide;
    TryInstall();
}

__attribute__((constructor)) static void ZonoeBackendReplaceEntry(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase4 BackendReplace loaded ===");
        ZLog(@"[P4] UI unchanged; only selected SDK backend routes are redirected");
        ZLog(@"[P4] request bodies/credentials are never logged or parsed by the bridge");
        _dyld_register_func_for_add_image(ImageAdded);
        TryInstall();
    }
}
