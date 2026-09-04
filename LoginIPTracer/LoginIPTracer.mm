#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <sys/socket.h>
#import <unistd.h>
#import <errno.h>
#import <mach-o/dyld.h>

static NSString *LITLogPath(void) {
    NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    return [documents stringByAppendingPathComponent:@"LoginIPTrace.log"];
}

static void LITLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSLog(@"[LOGINTRACE] %@", message);

    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.zonoe.loginiptracer.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(q, ^{
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = LITLogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } @catch (__unused NSException *e) {}
    });
}

static NSString *LITEndpoint(const struct sockaddr *addr, socklen_t len) {
    if (!addr) return @"<null>";
    char host[NI_MAXHOST] = {0};
    char serv[NI_MAXSERV] = {0};
    int rc = getnameinfo(addr, len, host, sizeof(host), serv, sizeof(serv), NI_NUMERICHOST | NI_NUMERICSERV);
    if (rc == 0) {
        if (addr->sa_family == AF_INET6) {
            return [NSString stringWithFormat:@"[%s]:%s", host, serv];
        }
        return [NSString stringWithFormat:@"%s:%s", host, serv];
    }
    return [NSString stringWithFormat:@"family=%d", addr->sa_family];
}

typedef int (*connect_fn)(int, const struct sockaddr *, socklen_t);
typedef int (*getaddrinfo_fn)(const char *, const char *, const struct addrinfo *, struct addrinfo **);

static connect_fn lit_real_connect(void) {
    static connect_fn fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (connect_fn)dlsym(RTLD_NEXT, "connect");
    });
    return fn;
}

static getaddrinfo_fn lit_real_getaddrinfo(void) {
    static getaddrinfo_fn fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (getaddrinfo_fn)dlsym(RTLD_NEXT, "getaddrinfo");
    });
    return fn;
}

static int lit_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    connect_fn realFn = lit_real_connect();
    if (!realFn) {
        errno = ENOSYS;
        return -1;
    }
    NSString *endpoint = LITEndpoint(addr, len);
    int rc = realFn(fd, addr, len);
    int savedErrno = errno;
    LITLog(@"CONNECT fd=%d -> %@ rc=%d errno=%d", fd, endpoint, rc, savedErrno);
    errno = savedErrno;
    return rc;
}

static int lit_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    getaddrinfo_fn realFn = lit_real_getaddrinfo();
    if (!realFn) return EAI_SYSTEM;
    NSString *host = node ? [NSString stringWithUTF8String:node] : @"<null>";
    NSString *svc = service ? [NSString stringWithUTF8String:service] : @"<null>";
    LITLog(@"DNS query host=%@ service=%@", host, svc);
    int rc = realFn(node, service, hints, res);
    if (rc == 0 && res && *res) {
        NSUInteger index = 0;
        for (const struct addrinfo *ai = *res; ai && index < 12; ai = ai->ai_next, index++) {
            NSString *endpoint = LITEndpoint(ai->ai_addr, (socklen_t)ai->ai_addrlen);
            LITLog(@"DNS result host=%@ -> %@ socktype=%d protocol=%d", host, endpoint, ai->ai_socktype, ai->ai_protocol);
        }
    } else {
        LITLog(@"DNS result host=%@ rc=%d", host, rc);
    }
    return rc;
}

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { const void *replacement; const void *replacee; } \
_interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
    (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee \
};

DYLD_INTERPOSE(lit_connect, connect)
DYLD_INTERPOSE(lit_getaddrinfo, getaddrinfo)

@interface NSURLSession (LoginIPTracer)
- (NSURLSessionDataTask *)lit_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)lit_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation NSURLSession (LoginIPTracer)
- (NSURLSessionDataTask *)lit_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    LITLog(@"HTTP %@ %@", request.HTTPMethod ?: @"GET", request.URL.absoluteString ?: @"<nil>");
    return [self lit_dataTaskWithRequest:request completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)lit_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    LITLog(@"HTTP GET %@", url.absoluteString ?: @"<nil>");
    return [self lit_dataTaskWithURL:url completionHandler:completionHandler];
}
@end

@interface NSURLSessionTask (LoginIPTracer)
- (void)lit_resume;
@end

@implementation NSURLSessionTask (LoginIPTracer)
- (void)lit_resume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    if (request.URL) {
        LITLog(@"HTTP RESUME %@ %@", request.HTTPMethod ?: @"GET", request.URL.absoluteString);
    }
    [self lit_resume];
}
@end

static void LITSwizzle(Class cls, SEL original, SEL replacement) {
    Method m1 = class_getInstanceMethod(cls, original);
    Method m2 = class_getInstanceMethod(cls, replacement);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

static void LITInstallObjCHooks(void) {
    LITSwizzle([NSURLSession class], @selector(dataTaskWithRequest:completionHandler:), @selector(lit_dataTaskWithRequest:completionHandler:));
    LITSwizzle([NSURLSession class], @selector(dataTaskWithURL:completionHandler:), @selector(lit_dataTaskWithURL:completionHandler:));
    LITSwizzle([NSURLSessionTask class], @selector(resume), @selector(lit_resume));
}

__attribute__((constructor)) static void LoginIPTracerInit(void) {
    @autoreleasepool {
        NSString *bundleId = [NSBundle mainBundle].bundleIdentifier ?: @"<unknown>";
        LITLog(@"=== LoginIPTracer v1.0 loaded bundle=%@ pid=%d ===", bundleId, getpid());
        LITLog(@"log file: %@", LITLogPath());
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name) continue;
            NSString *path = [NSString stringWithUTF8String:name];
            NSString *last = path.lastPathComponent;
            if ([last containsString:@"Unity"] || [last containsString:@"Framework"] || [path hasPrefix:NSBundle.mainBundle.bundlePath]) {
                LITLog(@"IMAGE[%u] %@ slide=0x%llx", i, path, (unsigned long long)_dyld_get_image_vmaddr_slide(i));
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            LITInstallObjCHooks();
            LITLog(@"NSURLSession hooks installed");
        });
    }
}

extern "C" const char *LoginIPTracerVersion(void) {
    return "LoginIPTracer/1.0";
}
