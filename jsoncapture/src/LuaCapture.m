#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#define JC3_VERSION @"JSONCapture LuaLoader v0.3"
#define JC3_MAX_BUFFER (64ULL * 1024ULL * 1024ULL)
#define JC3_POLL_MAX 240

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} JC3Il2CppString;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    uint8_t vector[0];
} JC3Il2CppArray;

typedef void *(*JC3DomainGetFn)(void);
typedef const void **(*JC3DomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JC3AssemblyGetImageFn)(const void *assembly);
typedef const char *(*JC3ImageGetNameFn)(const void *image);
typedef void *(*JC3ClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JC3ClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);

typedef int32_t (*JC3ManagedLuaLoadBufferFn)(void *self, void *buffer, int32_t size, void *name, const void *method);
typedef int (*JC3ToluaLoadBufferFn)(void *L, const char *buffer, int size, const char *name);
typedef int (*JC3LuaLLoadBufferFn)(void *L, const char *buffer, size_t size, const char *name);
typedef int (*JC3LuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);

typedef void (*JC3MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JC3DobbyHookFn)(void *address, void *replace, void **origin);

static JC3ManagedLuaLoadBufferFn gJC3OrigManagedLoadBuffer;
static JC3ToluaLoadBufferFn gJC3OrigToluaLoadBuffer;
static JC3LuaLLoadBufferFn gJC3OrigLuaLLoadBuffer;
static JC3LuaLLoadBufferXFn gJC3OrigLuaLLoadBufferX;

static NSString *gJC3RootPath;
static NSString *gJC3LogPath;
static dispatch_queue_t gJC3Queue;
static NSMutableSet *gJC3Seen;
static unsigned long long gJC3Seq = 0;
static pthread_mutex_t gJC3LogLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gJC3MetadataInstalled = NO;
static BOOL gJC3NativeAttempted = NO;

#pragma mark - Paths / helpers

static NSString *JC3Now(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JC3Documents(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JC3EnsureDir(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void JC3SetupPaths(void) {
    if (!gJC3RootPath.length) {
        gJC3RootPath = [[[JC3Documents() stringByAppendingPathComponent:@"JSONCapture"] stringByStandardizingPath] retain];
        gJC3LogPath = [[gJC3RootPath stringByAppendingPathComponent:@"LuaLoader_v0.3.log"] retain];
    }
    JC3EnsureDir(gJC3RootPath);
    JC3EnsureDir([gJC3RootPath stringByAppendingPathComponent:@"lua_loader"]);
}

static void JC3Log(NSString *text) {
    if (!text.length) return;
    JC3SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", JC3Now(), text];
    pthread_mutex_lock(&gJC3LogLock);
    FILE *f = fopen(gJC3LogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJC3LogLock);
}

static NSString *JC3SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JC3SafeName(NSString *text) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, 120)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@"];
    for (NSUInteger i = 0; i < text.length && out.length < 120; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c];
        else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

static NSString *JC3NSStringFromManaged(void *ptr) {
    if (!ptr) return nil;
    JC3Il2CppString *s = (JC3Il2CppString *)ptr;
    int32_t len = s->length;
    if (len <= 0 || len > (8 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)len] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSData *JC3DataFromManagedArray(void *ptr, int32_t requestedSize) {
    if (!ptr) return nil;
    JC3Il2CppArray *a = (JC3Il2CppArray *)ptr;
    uintptr_t maxLen = a->max_length;
    if (!maxLen || maxLen > JC3_MAX_BUFFER) return nil;
    NSUInteger len = (NSUInteger)maxLen;
    if (requestedSize > 0 && (uintptr_t)requestedSize <= maxLen) len = (NSUInteger)requestedSize;
    @try {
        return [NSData dataWithBytes:a->vector length:len];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *JC3NameFromC(const char *name) {
    if (!name) return @"unnamed";
    @try {
        NSString *s = [NSString stringWithUTF8String:name];
        if (s.length) return s;
    } @catch (__unused NSException *e) {}
    return @"unnamed";
}

static NSString *JC3HexPrefix(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = data.bytes;
    NSUInteger n = MIN((NSUInteger)32, data.length);
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

static BOOL JC3LooksJSON(NSData *data) {
    if (!data.length) return NO;
    const uint8_t *p = data.bytes;
    NSUInteger i = 0;
    if (data.length >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) i = 3;
    while (i < data.length) {
        uint8_t c = p[i++];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        return c == '{' || c == '[';
    }
    return NO;
}

static BOOL JC3LooksUTF8Text(NSData *data) {
    if (!data.length) return NO;
    NSUInteger sample = MIN((NSUInteger)16384, data.length);
    const uint8_t *p = data.bytes;
    NSUInteger bad = 0;
    for (NSUInteger i = 0; i < sample; i++) {
        uint8_t c = p[i];
        if (c == 0) return NO;
        if (c < 0x09 || (c > 0x0D && c < 0x20)) bad++;
    }
    if (bad * 50 > sample) return NO;
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, sample)]
                                         encoding:NSUTF8StringEncoding] autorelease];
    return s != nil;
}

static NSString *JC3Format(NSData *data) {
    if (JC3LooksJSON(data)) return @"json";
    const uint8_t *p = data.bytes;
    if (data.length >= 4 && p[0] == 0x1B && p[1] == 'L' && p[2] == 'u' && p[3] == 'a') return @"luac";
    if (data.length >= 2 && p[0] == 0x1F && p[1] == 0x8B) return @"gz";
    if (data.length >= 2 && p[0] == 0x78 && (p[1] == 0x01 || p[1] == 0x5E || p[1] == 0x9C || p[1] == 0xDA)) return @"zlib";
    if (data.length >= 4 && p[0] == 0x04 && p[1] == 0x22 && p[2] == 0x4D && p[3] == 0x18) return @"lz4";
    if (JC3LooksUTF8Text(data)) return @"lua";
    return @"bin";
}

static NSString *JC3Escape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithString:s];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static void JC3Capture(NSData *data, NSString *source, NSString *name) {
    if (!data.length || data.length > JC3_MAX_BUFFER || !gJC3Queue) return;
    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = source.length ? [NSString stringWithString:source] : @"lua-loader";
    NSString *chunk = name.length ? [NSString stringWithString:name] : @"unnamed";
    dispatch_async(gJC3Queue, ^{
        @autoreleasepool {
            NSString *hash = JC3SHA256(snapshot);
            if (!hash.length || [gJC3Seen containsObject:hash]) return;
            [gJC3Seen addObject:hash];
            unsigned long long idx = ++gJC3Seq;
            NSString *fmt = JC3Format(snapshot);
            NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
            NSString *base = [NSString stringWithFormat:@"%06llu_%@_%@_%@", idx, JC3SafeName(src), JC3SafeName(chunk), shortHash];
            NSString *dir = [gJC3RootPath stringByAppendingPathComponent:@"lua_loader"];
            JC3EnsureDir(dir);
            NSString *dataPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", base, fmt]];
            NSString *metaPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".meta.json"]];
            NSError *err = nil;
            if (![snapshot writeToFile:dataPath options:NSDataWritingAtomic error:&err]) {
                JC3Log([NSString stringWithFormat:@"WRITE-FAIL source=%@ chunk=%@ err=%@", src, chunk, err]);
                return;
            }
            NSString *prefix = JC3HexPrefix(snapshot);
            NSString *meta = [NSString stringWithFormat:
                @"{\n  \"version\": \"%@\",\n  \"source\": \"%@\",\n  \"chunk\": \"%@\",\n  \"bytes\": %lu,\n  \"sha256\": \"%@\",\n  \"format\": \"%@\",\n  \"head32\": \"%@\",\n  \"captured_at\": \"%@\",\n  \"file\": \"%@\"\n}\n",
                JC3Escape(JC3_VERSION), JC3Escape(src), JC3Escape(chunk), (unsigned long)snapshot.length,
                hash, fmt, prefix, JC3Escape(JC3Now()), JC3Escape(dataPath.lastPathComponent)];
            [meta writeToFile:metaPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            JC3Log([NSString stringWithFormat:@"LUA-CAPTURE #%llu source=%@ chunk=%@ bytes=%lu format=%@ sha256=%@ head=%@ file=%@",
                    idx, src, chunk, (unsigned long)snapshot.length, fmt, hash, prefix, dataPath.lastPathComponent]);
        }
    });
}

#pragma mark - Hook backend

static void *JC3ResolveHookSymbol(const char *symbol) {
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    const char *libs[] = {
        "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/var/jb/usr/lib/libsubstrate.dylib",
        "/usr/lib/libhooker.dylib",
        "/var/jb/usr/lib/libhooker.dylib",
        "/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libellekit.dylib"
    };
    for (size_t i = 0; i < sizeof(libs) / sizeof(libs[0]); i++) {
        void *h = dlopen(libs[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, symbol);
        if (p) return p;
    }
    return NULL;
}

static BOOL JC3Hook(void *address, void *replacement, void **original, NSString **apiOut) {
    if (!address) return NO;
    JC3MSHookFunctionFn ms = (JC3MSHookFunctionFn)JC3ResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (apiOut) *apiOut = @"MSHookFunction";
            return YES;
        }
    }
    JC3DobbyHookFn dobby = (JC3DobbyHookFn)JC3ResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (apiOut) *apiOut = @"DobbyHook";
            return YES;
        }
    }
    return NO;
}

static void *JC3ResolveExport(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    const char *paths[] = {"@rpath/UnityFramework.framework/UnityFramework", "UnityFramework.framework/UnityFramework"};
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        void *h = dlopen(paths[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, name);
        if (p) return p;
    }
    return NULL;
}

static void *JC3MethodPointer(const void *methodInfo) {
    if (!methodInfo) return NULL;
    @try {
        void *p = *(void * const *)methodInfo;
        if (!p) return NULL;
        Dl_info info;
        memset(&info, 0, sizeof(info));
        if (dladdr(p, &info) == 0) return NULL;
        return p;
    } @catch (__unused NSException *e) {
        return NULL;
    }
}

#pragma mark - Hook implementations

static int32_t JC3HookManagedLoadBuffer(void *self, void *buffer, int32_t size, void *name, const void *method) {
    NSData *d = JC3DataFromManagedArray(buffer, size);
    NSString *chunk = JC3NSStringFromManaged(name) ?: @"unnamed";
    if (d.length) JC3Capture(d, @"managed-LuaStatePtr.LuaLoadBuffer", chunk);
    return gJC3OrigManagedLoadBuffer ? gJC3OrigManagedLoadBuffer(self, buffer, size, name, method) : -1;
}

static int JC3HookToluaLoadBuffer(void *L, const char *buffer, int size, const char *name) {
    if (buffer && size > 0 && (uint64_t)size <= JC3_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:(NSUInteger)size];
        JC3Capture(d, @"native-tolua_loadbuffer", JC3NameFromC(name));
    }
    return gJC3OrigToluaLoadBuffer ? gJC3OrigToluaLoadBuffer(L, buffer, size, name) : -1;
}

static int JC3HookLuaLLoadBuffer(void *L, const char *buffer, size_t size, const char *name) {
    if (buffer && size > 0 && size <= JC3_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:size];
        JC3Capture(d, @"native-luaL_loadbuffer", JC3NameFromC(name));
    }
    return gJC3OrigLuaLLoadBuffer ? gJC3OrigLuaLLoadBuffer(L, buffer, size, name) : -1;
}

static int JC3HookLuaLLoadBufferX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {
    if (buffer && size > 0 && size <= JC3_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:size];
        JC3Capture(d, @"native-luaL_loadbufferx", JC3NameFromC(name));
    }
    return gJC3OrigLuaLLoadBufferX ? gJC3OrigLuaLLoadBufferX(L, buffer, size, name, mode) : -1;
}

#pragma mark - Install native symbols

static void JC3InstallNativeHooks(void) {
    if (gJC3NativeAttempted) return;
    gJC3NativeAttempted = YES;
    NSString *api = nil;
    void *pTolua = JC3ResolveExport("tolua_loadbuffer");
    void *pLuaL = JC3ResolveExport("luaL_loadbuffer");
    void *pLuaLX = JC3ResolveExport("luaL_loadbufferx");
    BOOL toluaOK = NO, luaLOK = NO, luaLXOK = NO;
    if (pTolua) toluaOK = JC3Hook(pTolua, (void *)JC3HookToluaLoadBuffer, (void **)&gJC3OrigToluaLoadBuffer, &api);
    if (pLuaL && pLuaL != pTolua) luaLOK = JC3Hook(pLuaL, (void *)JC3HookLuaLLoadBuffer, (void **)&gJC3OrigLuaLLoadBuffer, &api);
    if (pLuaLX && pLuaLX != pTolua && pLuaLX != pLuaL) luaLXOK = JC3Hook(pLuaLX, (void *)JC3HookLuaLLoadBufferX, (void **)&gJC3OrigLuaLLoadBufferX, &api);
    JC3Log([NSString stringWithFormat:@"NATIVE-LUA-HOOK api=%@ tolua_loadbuffer=%d luaL_loadbuffer=%d luaL_loadbufferx=%d addr_tol=%p addr_lual=%p addr_lualx=%p",
            api ?: @"none", toluaOK, luaLOK, luaLXOK, pTolua, pLuaL, pLuaLX]);
}

#pragma mark - Install managed LuaStatePtr hook

static BOOL JC3InstallMetadataHook(void) {
    if (gJC3MetadataInstalled) return YES;
    JC3DomainGetFn domainGet = (JC3DomainGetFn)JC3ResolveExport("il2cpp_domain_get");
    JC3DomainGetAssembliesFn domainGetAssemblies = (JC3DomainGetAssembliesFn)JC3ResolveExport("il2cpp_domain_get_assemblies");
    JC3AssemblyGetImageFn assemblyGetImage = (JC3AssemblyGetImageFn)JC3ResolveExport("il2cpp_assembly_get_image");
    JC3ImageGetNameFn imageGetName = (JC3ImageGetNameFn)JC3ResolveExport("il2cpp_image_get_name");
    JC3ClassFromNameFn classFromName = (JC3ClassFromNameFn)JC3ResolveExport("il2cpp_class_from_name");
    JC3ClassGetMethodFromNameFn classGetMethod = (JC3ClassGetMethodFromNameFn)JC3ResolveExport("il2cpp_class_get_method_from_name");
    if (!domainGet || !domainGetAssemblies || !assemblyGetImage || !classFromName || !classGetMethod) return NO;
    void *domain = domainGet();
    if (!domain) return NO;
    size_t count = 0;
    const void **assemblies = domainGetAssemblies(domain, &count);
    if (!assemblies || !count) return NO;

    const char *namespaces[] = {"LuaInterface", "LuaFramework", ""};
    const char *classes[] = {"LuaStatePtr", "LuaState"};
    void *foundClass = NULL;
    NSString *foundNS = nil, *foundClassName = nil, *foundImage = nil;
    for (size_t i = 0; i < count && !foundClass; i++) {
        void *image = assemblyGetImage(assemblies[i]);
        if (!image) continue;
        for (size_t n = 0; n < sizeof(namespaces)/sizeof(namespaces[0]) && !foundClass; n++) {
            for (size_t c = 0; c < sizeof(classes)/sizeof(classes[0]) && !foundClass; c++) {
                void *k = classFromName(image, namespaces[n], classes[c]);
                if (!k) continue;
                const void *m = classGetMethod(k, "LuaLoadBuffer", 3);
                void *p = JC3MethodPointer(m);
                if (!p) continue;
                foundClass = k;
                foundNS = [NSString stringWithUTF8String:namespaces[n]];
                foundClassName = [NSString stringWithUTF8String:classes[c]];
                if (imageGetName) {
                    const char *im = imageGetName(image);
                    if (im) foundImage = [NSString stringWithUTF8String:im];
                }
                NSString *api = nil;
                BOOL ok = JC3Hook(p, (void *)JC3HookManagedLoadBuffer, (void **)&gJC3OrigManagedLoadBuffer, &api);
                gJC3MetadataInstalled = ok;
                JC3Log([NSString stringWithFormat:@"MANAGED-LUA-HOOK installed=%d api=%@ assemblies=%lu image=%@ class=%@.%@ method=LuaLoadBuffer/3 addr=%p",
                        ok, api ?: @"none", (unsigned long)count, foundImage ?: @"?", foundNS ?: @"", foundClassName ?: @"?", p]);
            }
        }
    }
    if (!foundClass) {
        JC3Log([NSString stringWithFormat:@"MANAGED-LUA-HOOK class/method not found assemblies=%lu candidates=LuaInterface.LuaStatePtr,LuaState", (unsigned long)count]);
    }
    return gJC3MetadataInstalled;
}

static void JC3Poll(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        JC3InstallNativeHooks();
        if (gJC3MetadataInstalled) return;
        if (JC3InstallMetadataHook()) return;
        if (attempt < JC3_POLL_MAX) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JC3Poll(attempt + 1); });
        } else {
            JC3Log(@"MANAGED-LUA-HOOK timeout; native hooks (if available) remain active");
        }
    });
}

__attribute__((constructor)) static void JC3Entry(void) {
    @autoreleasepool {
        JC3SetupPaths();
        gJC3Queue = dispatch_queue_create("com.hfamap187.jsoncapture.lua.v03", DISPATCH_QUEUE_SERIAL);
        gJC3Seen = [[NSMutableSet alloc] init];
        JC3Log([NSString stringWithFormat:@"%@ loaded; capture point is Lua loader input", JC3_VERSION]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JC3Poll(0); });
    }
}
