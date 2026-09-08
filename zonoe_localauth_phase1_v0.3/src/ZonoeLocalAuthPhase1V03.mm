#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <atomic>

static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;
static std::atomic_bool gAuthWindow(false);
static IMP gOrigChannelLogin = NULL;
static IMP gOrigChannelLoginCallback = NULL;
static IMP gOrigSessionDataTaskRequest = NULL;
static IMP gOrigSessionDataTaskURL = NULL;
static IMP gOrigSessionUploadTask = NULL;
static IMP gOrigConnectionInit = NULL;
static IMP gOrigConnectionSendAsync = NULL;
static IMP gOrigConnectionSendSync = NULL;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase1_v0.3.log"];
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

static NSString *SafeURLSummary(NSURL *url) {
    if (!url) return @"<nil>";
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *scheme = c.scheme ?: @"";
    NSString *host = c.host ?: @"";
    NSString *path = c.percentEncodedPath.length ? c.percentEncodedPath : @"/";

    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSURLQueryItem *item in c.queryItems ?: @[]) {
        if (item.name.length && ![keys containsObject:item.name]) [keys addObject:item.name];
    }
    [keys sortUsingSelector:@selector(compare:)];

    if (keys.count) {
        return [NSString stringWithFormat:@"%@://%@%@ ?keys=%@", scheme, host, path, [keys componentsJoinedByString:@","]];
    }
    return [NSString stringWithFormat:@"%@://%@%@", scheme, host, path];
}

static NSString *CallerSummary(void) {
    NSArray<NSNumber *> *frames = [NSThread callStackReturnAddresses];
    NSString *fallback = nil;
    for (NSUInteger i = 1; i < frames.count && i < 24; ++i) {
        uintptr_t addr = (uintptr_t)frames[i].unsignedLongLongValue;
        Dl_info info = {};
        if (!dladdr((void *)addr, &info) || !info.dli_fname || !info.dli_fbase) continue;

        NSString *image = [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent];
        if (!image.length) continue;
        uintptr_t rva = addr - (uintptr_t)info.dli_fbase;
        NSString *entry = [NSString stringWithFormat:@"%@+0x%llx", image, (unsigned long long)rva];

        if (!fallback) fallback = entry;
        if ([image rangeOfString:@"Pandora" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [image rangeOfString:@"QuickSDK" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [image rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return entry;
        }
    }
    return fallback ?: @"<unknown>";
}

static void LogRequest(NSString *source, NSURLRequest *request) {
    if (!gAuthWindow.load()) return;
    NSString *method = request.HTTPMethod ?: @"<nil>";
    NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"] ?: @"<nil>";
    NSUInteger bodyLen = request.HTTPBody.length;
    ZLog(@"[HTTP] source=%@ method=%@ url=%@ bodyLen=%lu contentType=%@ caller=%@",
         source,
         method,
         SafeURLSummary(request.URL),
         (unsigned long)bodyLen,
         contentType,
         CallerSummary());
}

static NSInteger ChannelLoginProbe(id self, SEL _cmd) {
    gAuthWindow.store(true);
    ZLog(@"[AUTH] SMPCQuickChannel login entered; SDK UI/network capture window OPEN");
    if (gOrigChannelLogin) return ((NSInteger(*)(id,SEL))gOrigChannelLogin)(self, _cmd);
    return -1;
}

static void ChannelLoginCallbackProbe(id self, SEL _cmd, NSNotification *notification) {
    NSDictionary *u = [notification.userInfo isKindOfClass:NSDictionary.class] ? notification.userInfo : nil;
    id error = u[@"error"];
    id username = u[@"username"];
    ZLog(@"[AUTH] SMPCQuickChannel loginCallBack received error=%@ userPresent=%d",
         error ?: @"<nil>", username != nil);
    if (gOrigChannelLoginCallback) ((void(*)(id,SEL,id))gOrigChannelLoginCallback)(self, _cmd, notification);
    gAuthWindow.store(false);
    ZLog(@"[AUTH] login callback completed; capture window CLOSED");
}

static id SessionDataTaskRequestProbe(id self, SEL _cmd, NSURLRequest *request, id completion) {
    LogRequest(@"NSURLSession dataTaskWithRequest", request);
    return gOrigSessionDataTaskRequest ? ((id(*)(id,SEL,id,id))gOrigSessionDataTaskRequest)(self, _cmd, request, completion) : nil;
}

static id SessionDataTaskURLProbe(id self, SEL _cmd, NSURL *url, id completion) {
    if (gAuthWindow.load()) {
        ZLog(@"[HTTP] source=NSURLSession dataTaskWithURL method=<implicit> url=%@ bodyLen=0 caller=%@",
             SafeURLSummary(url), CallerSummary());
    }
    return gOrigSessionDataTaskURL ? ((id(*)(id,SEL,id,id))gOrigSessionDataTaskURL)(self, _cmd, url, completion) : nil;
}

static id SessionUploadTaskProbe(id self, SEL _cmd, NSURLRequest *request, NSData *body, id completion) {
    if (gAuthWindow.load()) {
        NSString *method = request.HTTPMethod ?: @"<nil>";
        NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"] ?: @"<nil>";
        ZLog(@"[HTTP] source=NSURLSession uploadTask method=%@ url=%@ bodyLen=%lu contentType=%@ caller=%@",
             method, SafeURLSummary(request.URL), (unsigned long)body.length, contentType, CallerSummary());
    }
    return gOrigSessionUploadTask ? ((id(*)(id,SEL,id,id,id))gOrigSessionUploadTask)(self, _cmd, request, body, completion) : nil;
}

static id ConnectionInitProbe(id self, SEL _cmd, NSURLRequest *request, id delegate, BOOL startImmediately) {
    LogRequest(@"NSURLConnection initWithRequest", request);
    return gOrigConnectionInit ? ((id(*)(id,SEL,id,id,BOOL))gOrigConnectionInit)(self, _cmd, request, delegate, startImmediately) : nil;
}

static void ConnectionSendAsyncProbe(id self, SEL _cmd, NSURLRequest *request, NSOperationQueue *queue, id completion) {
    LogRequest(@"NSURLConnection sendAsync", request);
    if (gOrigConnectionSendAsync) ((void(*)(id,SEL,id,id,id))gOrigConnectionSendAsync)(self, _cmd, request, queue, completion);
}

static NSData *ConnectionSendSyncProbe(id self, SEL _cmd, NSURLRequest *request, NSURLResponse **response, NSError **error) {
    LogRequest(@"NSURLConnection sendSync", request);
    return gOrigConnectionSendSync ? ((NSData *(*)(id,SEL,id,NSURLResponse **,NSError **))gOrigConnectionSendSync)(self, _cmd, request, response, error) : nil;
}

static BOOL ReplaceInstanceMethod(Class cls, const char *selectorName, IMP replacement, IMP *original, NSString *label) {
    if (!cls) {
        ZLog(@"[INSTALL] missing class for %@", label);
        return NO;
    }
    Method m = class_getInstanceMethod(cls, sel_registerName(selectorName));
    if (!m) {
        ZLog(@"[INSTALL] missing instance method %@", label);
        return NO;
    }
    IMP old = method_getImplementation(m);
    if (original) *original = old;
    method_setImplementation(m, replacement);
    ZLog(@"[INSTALL] replaced %@ old=%p new=%p", label, old, replacement);
    return YES;
}

static BOOL ReplaceClassMethod(Class cls, const char *selectorName, IMP replacement, IMP *original, NSString *label) {
    if (!cls) {
        ZLog(@"[INSTALL] missing class for %@", label);
        return NO;
    }
    Method m = class_getClassMethod(cls, sel_registerName(selectorName));
    if (!m) {
        ZLog(@"[INSTALL] missing class method %@", label);
        return NO;
    }
    IMP old = method_getImplementation(m);
    if (original) *original = old;
    method_setImplementation(m, replacement);
    ZLog(@"[INSTALL] replaced %@ old=%p new=%p", label, old, replacement);
    return YES;
}

static void LogRelevantImages(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *s = [NSString stringWithUTF8String:name];
        if ([s rangeOfString:@"Pandora" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [s rangeOfString:@"QuickSDK" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [s rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            ZLog(@"[IMAGE] %@ slide=0x%llx", s.lastPathComponent, (unsigned long long)_dyld_get_image_vmaddr_slide(i));
        }
    }
}

static void Install(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase1 v0.3 Auth Route Probe start ===");
        ZLog(@"[NOTE] diagnostic only: SDK UI and requests are not modified; request bodies and credential values are never logged");
        LogRelevantImages();

        ReplaceInstanceMethod(NSURLSession.class,
                              "dataTaskWithRequest:completionHandler:",
                              (IMP)SessionDataTaskRequestProbe,
                              &gOrigSessionDataTaskRequest,
                              @"NSURLSession dataTaskWithRequest:completionHandler:");
        ReplaceInstanceMethod(NSURLSession.class,
                              "dataTaskWithURL:completionHandler:",
                              (IMP)SessionDataTaskURLProbe,
                              &gOrigSessionDataTaskURL,
                              @"NSURLSession dataTaskWithURL:completionHandler:");
        ReplaceInstanceMethod(NSURLSession.class,
                              "uploadTaskWithRequest:fromData:completionHandler:",
                              (IMP)SessionUploadTaskProbe,
                              &gOrigSessionUploadTask,
                              @"NSURLSession uploadTaskWithRequest:fromData:completionHandler:");

        ReplaceInstanceMethod(NSURLConnection.class,
                              "initWithRequest:delegate:startImmediately:",
                              (IMP)ConnectionInitProbe,
                              &gOrigConnectionInit,
                              @"NSURLConnection initWithRequest:delegate:startImmediately:");
        ReplaceClassMethod(NSURLConnection.class,
                           "sendAsynchronousRequest:queue:completionHandler:",
                           (IMP)ConnectionSendAsyncProbe,
                           &gOrigConnectionSendAsync,
                           @"NSURLConnection sendAsynchronousRequest:queue:completionHandler:");
        ReplaceClassMethod(NSURLConnection.class,
                           "sendSynchronousRequest:returningResponse:error:",
                           (IMP)ConnectionSendSyncProbe,
                           &gOrigConnectionSendSync,
                           @"NSURLConnection sendSynchronousRequest:returningResponse:error:");

        for (int i = 0; i < 160; ++i) {
            if (objc_getClass("SMPCQuickChannel")) break;
            [NSThread sleepForTimeInterval:0.25];
        }
        ReplaceInstanceMethod(objc_getClass("SMPCQuickChannel"),
                              "login",
                              (IMP)ChannelLoginProbe,
                              &gOrigChannelLogin,
                              @"SMPCQuickChannel login");
        ReplaceInstanceMethod(objc_getClass("SMPCQuickChannel"),
                              "loginCallBack:",
                              (IMP)ChannelLoginCallbackProbe,
                              &gOrigChannelLoginCallback,
                              @"SMPCQuickChannel loginCallBack:");

        ZLog(@"[READY] auth route probe installed");
    }
}

__attribute__((constructor)) static void Entry(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        Install();
    });
}
