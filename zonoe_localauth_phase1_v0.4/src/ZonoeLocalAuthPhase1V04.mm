#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <atomic>

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static std::atomic_bool gAuthWindow(false);
static NSMutableDictionary<NSString *, NSValue *> *gOrig;
static IMP gOrigChannelLogin = NULL;
static IMP gOrigChannelLoginCallback = NULL;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase1_v0.4.log"];
}

static void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    os_unfair_lock_lock(&gLock);
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    if (!h) {
        [[NSFileManager defaultManager] createFileAtPath:LogPath() contents:nil attributes:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    }
    [h seekToEndOfFile];
    [h writeData:data];
    [h closeFile];
    os_unfair_lock_unlock(&gLock);
}

static NSString *KeyFor(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%s::%s", class_getName(cls), sel_getName(sel)];
}

static void StoreOrig(Class cls, SEL sel, IMP imp) {
    if (!imp) return;
    os_unfair_lock_lock(&gLock);
    if (!gOrig) gOrig = [NSMutableDictionary dictionary];
    gOrig[KeyFor(cls, sel)] = [NSValue value:&imp withObjCType:@encode(IMP)];
    os_unfair_lock_unlock(&gLock);
}

static IMP OrigFor(id self, SEL sel) {
    Class cls = object_getClass(self);
    while (cls) {
        os_unfair_lock_lock(&gLock);
        NSValue *v = gOrig[KeyFor(cls, sel)];
        os_unfair_lock_unlock(&gLock);
        if (v) {
            IMP imp = NULL;
            [v getValue:&imp size:sizeof(imp)];
            return imp;
        }
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

static BOOL ClassIsSubclassOf(Class cls, Class base) {
    if (!cls || !base) return NO;
    for (Class c = cls; c; c = class_getSuperclass(c)) if (c == base) return YES;
    return NO;
}

static Method DeclaredMethod(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method found = NULL;
    for (unsigned int i = 0; i < count; ++i) {
        if (method_getName(methods[i]) == sel) { found = methods[i]; break; }
    }
    free(methods);
    return found;
}

static BOOL HookMethodOnClass(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel) return NO;
    NSString *key = KeyFor(cls, sel);
    os_unfair_lock_lock(&gLock);
    BOOL already = (gOrig[key] != nil);
    os_unfair_lock_unlock(&gLock);
    if (already) return NO;

    Method inherited = class_getInstanceMethod(cls, sel);
    if (!inherited) return NO;
    IMP old = method_getImplementation(inherited);
    const char *types = method_getTypeEncoding(inherited);
    Method declared = DeclaredMethod(cls, sel);
    if (declared) {
        old = method_getImplementation(declared);
        StoreOrig(cls, sel, old);
        method_setImplementation(declared, replacement);
    } else {
        StoreOrig(cls, sel, old);
        class_addMethod(cls, sel, replacement, types);
    }
    ZLog(@"[HOOK] class=%s sel=%s old=%p new=%p", class_getName(cls), sel_getName(sel), old, replacement);
    return YES;
}

static NSString *SafeURLSummary(NSURL *url) {
    if (!url) return @"<nil>";
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSURLQueryItem *item in c.queryItems ?: @[]) {
        if (item.name.length && ![keys containsObject:item.name]) [keys addObject:item.name];
    }
    [keys sortUsingSelector:@selector(compare:)];
    NSString *base = [NSString stringWithFormat:@"%@://%@%@", c.scheme ?: @"", c.host ?: @"", c.percentEncodedPath.length ? c.percentEncodedPath : @"/"];
    return keys.count ? [NSString stringWithFormat:@"%@ ?keys=%@", base, [keys componentsJoinedByString:@","]] : base;
}

static NSString *CallerSummary(void) {
    NSArray<NSNumber *> *frames = [NSThread callStackReturnAddresses];
    NSString *fallback = nil;
    for (NSUInteger i = 1; i < frames.count && i < 32; ++i) {
        uintptr_t addr = (uintptr_t)frames[i].unsignedLongLongValue;
        Dl_info info = {};
        if (!dladdr((void *)addr, &info) || !info.dli_fname || !info.dli_fbase) continue;
        NSString *image = [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent];
        uintptr_t rva = addr - (uintptr_t)info.dli_fbase;
        NSString *entry = [NSString stringWithFormat:@"%@+0x%llx", image ?: @"?", (unsigned long long)rva];
        if (!fallback) fallback = entry;
        if ([image rangeOfString:@"Pandora" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [image rangeOfString:@"Quick" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [image rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) return entry;
    }
    return fallback ?: @"<unknown>";
}

static void LogRequest(NSString *source, NSURLRequest *r) {
    if (!gAuthWindow.load()) return;
    ZLog(@"[HTTP] source=%@ class=%@ method=%@ url=%@ bodyLen=%lu contentType=%@ caller=%@",
         source,
         NSStringFromClass([r class]),
         r.HTTPMethod ?: @"<nil>",
         SafeURLSummary(r.URL),
         (unsigned long)r.HTTPBody.length,
         [r valueForHTTPHeaderField:@"Content-Type"] ?: @"<nil>",
         CallerSummary());
}

static id ProbeDataTaskReqCompletion(id self, SEL _cmd, NSURLRequest *r, id completion) {
    LogRequest(@"NSURLSession request+completion", r);
    IMP orig = OrigFor(self, _cmd);
    return orig ? ((id(*)(id,SEL,id,id))orig)(self,_cmd,r,completion) : nil;
}
static id ProbeDataTaskURLCompletion(id self, SEL _cmd, NSURL *url, id completion) {
    if (gAuthWindow.load()) ZLog(@"[HTTP] source=NSURLSession URL+completion class=%@ url=%@ caller=%@", NSStringFromClass([self class]), SafeURLSummary(url), CallerSummary());
    IMP orig = OrigFor(self, _cmd);
    return orig ? ((id(*)(id,SEL,id,id))orig)(self,_cmd,url,completion) : nil;
}
static id ProbeDataTaskReq(id self, SEL _cmd, NSURLRequest *r) {
    LogRequest(@"NSURLSession request(delegate)", r);
    IMP orig = OrigFor(self, _cmd);
    return orig ? ((id(*)(id,SEL,id))orig)(self,_cmd,r) : nil;
}
static id ProbeDataTaskURL(id self, SEL _cmd, NSURL *url) {
    if (gAuthWindow.load()) ZLog(@"[HTTP] source=NSURLSession URL(delegate) class=%@ url=%@ caller=%@", NSStringFromClass([self class]), SafeURLSummary(url), CallerSummary());
    IMP orig = OrigFor(self, _cmd);
    return orig ? ((id(*)(id,SEL,id))orig)(self,_cmd,url) : nil;
}
static id ProbeUploadData(id self, SEL _cmd, NSURLRequest *r, NSData *body, id completion) {
    if (gAuthWindow.load()) ZLog(@"[HTTP] source=NSURLSession uploadData class=%@ method=%@ url=%@ bodyLen=%lu caller=%@", NSStringFromClass([self class]), r.HTTPMethod ?: @"<nil>", SafeURLSummary(r.URL), (unsigned long)body.length, CallerSummary());
    IMP orig = OrigFor(self, _cmd);
    return orig ? ((id(*)(id,SEL,id,id,id))orig)(self,_cmd,r,body,completion) : nil;
}
static id ProbeUploadFile(id self, SEL _cmd, NSURLRequest *r, NSURL *fileURL, id completion) {
    if (gAuthWindow.load()) ZLog(@"[HTTP] source=NSURLSession uploadFile class=%@ method=%@ url=%@ caller=%@", NSStringFromClass([self class]), r.HTTPMethod ?: @"<nil>", SafeURLSummary(r.URL), CallerSummary());
    IMP orig = OrigFor(self, _cmd);
    return orig ? ((id(*)(id,SEL,id,id,id))orig)(self,_cmd,r,fileURL,completion) : nil;
}

static void InstallNSURLSessionHooks(void) {
    Class base = NSURLSession.class;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    int hookedClasses = 0;
    for (int i = 0; i < count; ++i) {
        Class cls = classes[i];
        if (!ClassIsSubclassOf(cls, base)) continue;
        BOOL changed = NO;
        changed |= HookMethodOnClass(cls, @selector(dataTaskWithRequest:completionHandler:), (IMP)ProbeDataTaskReqCompletion);
        changed |= HookMethodOnClass(cls, @selector(dataTaskWithURL:completionHandler:), (IMP)ProbeDataTaskURLCompletion);
        changed |= HookMethodOnClass(cls, @selector(dataTaskWithRequest:), (IMP)ProbeDataTaskReq);
        changed |= HookMethodOnClass(cls, @selector(dataTaskWithURL:), (IMP)ProbeDataTaskURL);
        changed |= HookMethodOnClass(cls, @selector(uploadTaskWithRequest:fromData:completionHandler:), (IMP)ProbeUploadData);
        changed |= HookMethodOnClass(cls, @selector(uploadTaskWithRequest:fromFile:completionHandler:), (IMP)ProbeUploadFile);
        if (changed) hookedClasses++;
    }
    free(classes);
    ZLog(@"[SCAN] NSURLSession subclass hook pass complete changedClasses=%d", hookedClasses);
}

static BOOL SelectorInteresting(const char *name) {
    if (!name) return NO;
    NSString *s = [[NSString stringWithUTF8String:name] lowercaseString];
    NSArray<NSString *> *keys = @[@"login", @"auth", @"account", @"user", @"register", @"password", @"http", @"request", @"session", @"token", @"network"];
    for (NSString *k in keys) if ([s containsString:k]) return YES;
    return NO;
}

static void DumpPandoraSelectors(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uint32_t imageCount = _dyld_image_count();
        int total = 0;
        for (uint32_t i = 0; i < imageCount; ++i) {
            const char *path = _dyld_get_image_name(i);
            if (!path) continue;
            NSString *img = [[NSString stringWithUTF8String:path] lastPathComponent];
            if ([img rangeOfString:@"Pandora" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                [img rangeOfString:@"Quick" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;

            unsigned int classCount = 0;
            const char **names = objc_copyClassNamesForImage(path, &classCount);
            ZLog(@"[OBJC] image=%@ classCount=%u", img, classCount);
            for (unsigned int c = 0; c < classCount; ++c) {
                Class cls = objc_getClass(names[c]);
                if (!cls) continue;
                unsigned int mc = 0;
                Method *methods = class_copyMethodList(cls, &mc);
                for (unsigned int m = 0; m < mc; ++m) {
                    const char *sel = sel_getName(method_getName(methods[m]));
                    if (SelectorInteresting(sel)) {
                        ZLog(@"[OBJC] %@ -[%s %s] imp=%p", img, class_getName(cls), sel, method_getImplementation(methods[m]));
                        if (++total >= 400) break;
                    }
                }
                free(methods);
                if (total >= 400) break;

                Class meta = object_getClass(cls);
                methods = class_copyMethodList(meta, &mc);
                for (unsigned int m = 0; m < mc; ++m) {
                    const char *sel = sel_getName(method_getName(methods[m]));
                    if (SelectorInteresting(sel)) {
                        ZLog(@"[OBJC] %@ +[%s %s] imp=%p", img, class_getName(cls), sel, method_getImplementation(methods[m]));
                        if (++total >= 400) break;
                    }
                }
                free(methods);
                if (total >= 400) break;
            }
            free(names);
            if (total >= 400) break;
        }
        ZLog(@"[OBJC] selector inventory complete interesting=%d", total);
    });
}

static NSInteger ChannelLoginProbe(id self, SEL _cmd) {
    gAuthWindow.store(true);
    ZLog(@"[AUTH] SMPCQuickChannel login entered; capture window OPEN");
    InstallNSURLSessionHooks();
    DumpPandoraSelectors();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ InstallNSURLSessionHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ InstallNSURLSessionHooks(); });
    return gOrigChannelLogin ? ((NSInteger(*)(id,SEL))gOrigChannelLogin)(self,_cmd) : -1;
}

static void ChannelLoginCallbackProbe(id self, SEL _cmd, NSNotification *n) {
    NSDictionary *u = [n.userInfo isKindOfClass:NSDictionary.class] ? n.userInfo : nil;
    ZLog(@"[AUTH] loginCallBack received error=%@ userPresent=%d", u[@"error"] ?: @"<nil>", u[@"username"] != nil);
    if (gOrigChannelLoginCallback) ((void(*)(id,SEL,id))gOrigChannelLoginCallback)(self,_cmd,n);
    gAuthWindow.store(false);
    ZLog(@"[AUTH] callback completed; capture window CLOSED");
}

static BOOL ReplaceInstance(Class cls, SEL sel, IMP replacement, IMP *orig, NSString *label) {
    if (!cls) { ZLog(@"[INSTALL] missing class %@", label); return NO; }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { ZLog(@"[INSTALL] missing method %@", label); return NO; }
    IMP old = method_getImplementation(m);
    if (orig) *orig = old;
    method_setImplementation(m, replacement);
    ZLog(@"[INSTALL] replaced %@ old=%p new=%p", label, old, replacement);
    return YES;
}

static void LogImages(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *p = _dyld_get_image_name(i);
        if (!p) continue;
        NSString *s = [NSString stringWithUTF8String:p];
        if ([s rangeOfString:@"Pandora" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [s rangeOfString:@"Quick" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [s rangeOfString:@"UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            ZLog(@"[IMAGE] %@ slide=0x%llx", s.lastPathComponent, (unsigned long long)_dyld_get_image_vmaddr_slide(i));
        }
    }
}

static void Install(void) {
    @autoreleasepool {
        os_unfair_lock_lock(&gLock);
        if (!gOrig) gOrig = [NSMutableDictionary dictionary];
        os_unfair_lock_unlock(&gLock);
        ZLog(@"=== ZonoeLocalAuth Phase1 v0.4 Deep Auth Route Probe start ===");
        ZLog(@"[NOTE] diagnostic only; no request redirection and no credential/body/token values are logged");
        LogImages();
        InstallNSURLSessionHooks();
        for (int i = 0; i < 160; ++i) {
            if (objc_getClass("SMPCQuickChannel")) break;
            [NSThread sleepForTimeInterval:0.25];
        }
        ReplaceInstance(objc_getClass("SMPCQuickChannel"), @selector(login), (IMP)ChannelLoginProbe, &gOrigChannelLogin, @"SMPCQuickChannel login");
        ReplaceInstance(objc_getClass("SMPCQuickChannel"), @selector(loginCallBack:), (IMP)ChannelLoginCallbackProbe, &gOrigChannelLoginCallback, @"SMPCQuickChannel loginCallBack:");
        ZLog(@"[READY] deep auth route probe installed");
    }
}

__attribute__((constructor)) static void Entry(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ Install(); });
}
