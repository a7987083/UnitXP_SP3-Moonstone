#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#import "Lua53Analyzer.h"

#define JC41_VERSION @"JSONCapture LuaLoader v0.4.1"
#define JC41_MAX_BUFFER (64ULL * 1024ULL * 1024ULL)
#define JC41_POLL_MAX 240

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} JC41Il2CppString;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    uint8_t vector[0];
} JC41Il2CppArray;

typedef void *(*JC41DomainGetFn)(void);
typedef const void **(*JC41DomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JC41AssemblyGetImageFn)(const void *assembly);
typedef const char *(*JC41ImageGetNameFn)(const void *image);
typedef void *(*JC41ClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JC41ClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);

typedef int32_t (*JC41ManagedLuaLoadBufferFn)(void *self, void *buffer, int32_t size, void *name, const void *method);
typedef int (*JC41ToluaLoadBufferFn)(void *L, const char *buffer, int size, const char *name);
typedef int (*JC41LuaLLoadBufferFn)(void *L, const char *buffer, size_t size, const char *name);
typedef int (*JC41LuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);

typedef void (*JC41MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JC41DobbyHookFn)(void *address, void *replace, void **origin);

static JC41ManagedLuaLoadBufferFn gJC41OrigManagedLoadBuffer;
static JC41ToluaLoadBufferFn gJC41OrigToluaLoadBuffer;
static JC41LuaLLoadBufferFn gJC41OrigLuaLLoadBuffer;
static JC41LuaLLoadBufferXFn gJC41OrigLuaLLoadBufferX;

static NSString *gJC41RootPath;
static NSString *gJC41LogPath;
static dispatch_queue_t gJC41Queue;
static NSMutableSet *gJC41Seen;
static unsigned long long gJC41Seq = 0;
static pthread_mutex_t gJC41LogLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gJC41MetadataInstalled = NO;
static BOOL gJC41NativeAttempted = NO;

#pragma mark - Paths / helpers

static NSString *JC41Now(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JC41Documents(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JC41EnsureDir(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void JC41SetupPaths(void) {
    if (!gJC41RootPath.length) {
        gJC41RootPath = [[[JC41Documents() stringByAppendingPathComponent:@"JSONCapture"] stringByStandardizingPath] retain];
        gJC41LogPath = [[gJC41RootPath stringByAppendingPathComponent:@"LuaLoader_v0.4.1.log"] retain];
    }
    JC41EnsureDir(gJC41RootPath);
    JC41EnsureDir([gJC41RootPath stringByAppendingPathComponent:@"lua_loader"]);
    JC41EnsureDir([gJC41RootPath stringByAppendingPathComponent:@"lua53_analysis"]);
}

static void JC41Log(NSString *text) {
    if (!text.length) return;
    JC41SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", JC41Now(), text];
    pthread_mutex_lock(&gJC41LogLock);
    FILE *f = fopen(gJC41LogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJC41LogLock);
}

static NSString *JC41SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JC41SafeName(NSString *text) {
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

static NSString *JC41NSStringFromManaged(void *ptr) {
    if (!ptr) return nil;
    JC41Il2CppString *s = (JC41Il2CppString *)ptr;
    int32_t len = s->length;
    if (len <= 0 || len > (8 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)len] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSData *JC41DataFromManagedArray(void *ptr, int32_t requestedSize) {
    if (!ptr) return nil;
    JC41Il2CppArray *a = (JC41Il2CppArray *)ptr;
    uintptr_t maxLen = a->max_length;
    if (!maxLen || maxLen > JC41_MAX_BUFFER) return nil;
    NSUInteger len = (NSUInteger)maxLen;
    if (requestedSize > 0 && (uintptr_t)requestedSize <= maxLen) len = (NSUInteger)requestedSize;
    @try {
        return [NSData dataWithBytes:a->vector length:len];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *JC41NameFromC(const char *name) {
    if (!name) return @"unnamed";
    @try {
        NSString *s = [NSString stringWithUTF8String:name];
        return s.length ? s : @"unnamed";
    } @catch (__unused NSException *e) {
        return @"unnamed";
    }
}

static NSString *JC41HexPrefix(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = data.bytes;
    NSUInteger n = MIN((NSUInteger)32, data.length);
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

static BOOL JC41LooksJSON(NSData *data) {
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

static BOOL JC41LooksUTF8Text(NSData *data) {
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
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, sample)] encoding:NSUTF8StringEncoding] autorelease];
    return s != nil;
}

static NSString *JC41Format(NSData *data) {
    if (JC41LooksJSON(data)) return @"json";
    NSInteger off = JC4FindLua53SignatureOffset(data);
    if (off == 0) return @"luac";
    if (off != NSNotFound) return @"luacwrap";
    const uint8_t *p = data.bytes;
    if (data.length >= 2 && p[0] == 0x1F && p[1] == 0x8B) return @"gz";
    if (data.length >= 2 && p[0] == 0x78 && (p[1] == 0x01 || p[1] == 0x5E || p[1] == 0x9C || p[1] == 0xDA)) return @"zlib";
    if (data.length >= 4 && p[0] == 0x04 && p[1] == 0x22 && p[2] == 0x4D && p[3] == 0x18) return @"lz4";
    if (JC41LooksUTF8Text(data)) return @"lua";
    return @"bin";
}

static NSString *JC41Escape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithString:s];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static void JC41Capture(NSData *data, NSString *source, NSString *name) {
    if (!data.length || data.length > JC41_MAX_BUFFER || !gJC41Queue) return;
    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = source.length ? [NSString stringWithString:source] : @"lua-loader";
    NSString *chunk = name.length ? [NSString stringWithString:name] : @"unnamed";
    dispatch_async(gJC41Queue, ^{
        @autoreleasepool {
            NSString *hash = JC41SHA256(snapshot);
            if (!hash.length || [gJC41Seen containsObject:hash]) return;
            [gJC41Seen addObject:hash];

            unsigned long long idx = ++gJC41Seq;
            NSString *fmt = JC41Format(snapshot);
            NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
            NSString *base = [NSString stringWithFormat:@"%06llu_%@_%@_%@", idx, JC41SafeName(src), JC41SafeName(chunk), shortHash];
            NSString *dir = [gJC41RootPath stringByAppendingPathComponent:@"lua_loader"];
            JC41EnsureDir(dir);
            NSString *dataPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", base, fmt]];
            NSString *metaPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".meta.json"]];

            NSError *err = nil;
            if (![snapshot writeToFile:dataPath options:NSDataWritingAtomic error:&err]) {
                JC41Log([NSString stringWithFormat:@"WRITE-FAIL source=%@ chunk=%@ err=%@", src, chunk, err]);
                return;
            }

            NSString *prefix = JC41HexPrefix(snapshot);
            NSString *meta = [NSString stringWithFormat:
                @"{\n  \"version\": \"%@\",\n  \"source\": \"%@\",\n  \"chunk\": \"%@\",\n  \"bytes\": %lu,\n  \"sha256\": \"%@\",\n  \"format\": \"%@\",\n  \"head32\": \"%@\",\n  \"captured_at\": \"%@\",\n  \"file\": \"%@\"\n}\n",
                JC41Escape(JC41_VERSION), JC41Escape(src), JC41Escape(chunk), (unsigned long)snapshot.length,
                hash, fmt, prefix, JC41Escape(JC41Now()), JC41Escape(dataPath.lastPathComponent)];
            [meta writeToFile:metaPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

            JC41Log([NSString stringWithFormat:@"LUA-CAPTURE #%llu source=%@ chunk=%@ bytes=%lu format=%@ sha256=%@ head=%@ file=%@",
                     idx, src, chunk, (unsigned long)snapshot.length, fmt, hash, prefix, dataPath.lastPathComponent]);

            NSInteger luaOff = JC4FindLua53SignatureOffset(snapshot);
            if (luaOff != NSNotFound) {
                JC41Log([NSString stringWithFormat:@"LUA53-VM-DETECTED source=%@ chunk=%@ signature_offset=%ld bytes=%lu head=%@",
                         src, chunk, (long)luaOff, (unsigned long)snapshot.length, prefix]);
                JC4AnalyzeLua53Data(snapshot, src, chunk, gJC41RootPath);
            }
        }
    });
}

#pragma mark - Hook backend

static void *JC41ResolveHookSymbol(const char *symbol) {
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

static BOOL JC41Hook(void *address, void *replacement, void **original, NSString **apiOut) {
    if (!address) return NO;
    JC41MSHookFunctionFn ms = (JC41MSHookFunctionFn)JC41ResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (apiOut) *apiOut = @"MSHookFunction";
            return YES;
        }
    }
    JC41DobbyHookFn dobby = (JC41DobbyHookFn)JC41ResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (apiOut) *apiOut = @"DobbyHook";
            return YES;
        }
    }
    return NO;
}

static void *JC41ResolveExport(const char *name) {
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

static void *JC41MethodPointer(const void *methodInfo) {
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

static int32_t JC41HookManagedLoadBuffer(void *self, void *buffer, int32_t size, void *name, const void *method) {
    NSData *d = JC41DataFromManagedArray(buffer, size);
    NSString *chunk = JC41NSStringFromManaged(name) ?: @"unnamed";
    if (d.length) JC41Capture(d, @"managed-LuaStatePtr.LuaLoadBuffer", chunk);
    return gJC41OrigManagedLoadBuffer ? gJC41OrigManagedLoadBuffer(self, buffer, size, name, method) : -1;
}

static int JC41HookToluaLoadBuffer(void *L, const char *buffer, int size, const char *name) {
    if (buffer && size > 0 && (uint64_t)size <= JC41_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:(NSUInteger)size];
        JC41Capture(d, @"native-tolua_loadbuffer", JC41NameFromC(name));
    }
    return gJC41OrigToluaLoadBuffer ? gJC41OrigToluaLoadBuffer(L, buffer, size, name) : -1;
}

static int JC41HookLuaLLoadBuffer(void *L, const char *buffer, size_t size, const char *name) {
    if (buffer && size > 0 && size <= JC41_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:size];
        JC41Capture(d, @"native-luaL_loadbuffer", JC41NameFromC(name));
    }
    return gJC41OrigLuaLLoadBuffer ? gJC41OrigLuaLLoadBuffer(L, buffer, size, name) : -1;
}

static int JC41HookLuaLLoadBufferX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {
    if (buffer && size > 0 && size <= JC41_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:size];
        JC41Capture(d, @"native-luaL_loadbufferx", JC41NameFromC(name));
    }
    return gJC41OrigLuaLLoadBufferX ? gJC41OrigLuaLLoadBufferX(L, buffer, size, name, mode) : -1;
}

#pragma mark - Install native hooks

static void JC41InstallNativeHooks(void) {
    if (gJC41NativeAttempted) return;
    gJC41NativeAttempted = YES;
    NSString *api = nil;
    void *pTolua = JC41ResolveExport("tolua_loadbuffer");
    void *pLuaL = JC41ResolveExport("luaL_loadbuffer");
    void *pLuaLX = JC41ResolveExport("luaL_loadbufferx");
    BOOL toluaOK = NO, luaLOK = NO, luaLXOK = NO;
    if (pTolua) toluaOK = JC41Hook(pTolua, (void *)JC41HookToluaLoadBuffer, (void **)&gJC41OrigToluaLoadBuffer, &api);
    if (pLuaL && pLuaL != pTolua) luaLOK = JC41Hook(pLuaL, (void *)JC41HookLuaLLoadBuffer, (void **)&gJC41OrigLuaLLoadBuffer, &api);
    if (pLuaLX && pLuaLX != pTolua && pLuaLX != pLuaL) luaLXOK = JC41Hook(pLuaLX, (void *)JC41HookLuaLLoadBufferX, (void **)&gJC41OrigLuaLLoadBufferX, &api);
    JC41Log([NSString stringWithFormat:@"NATIVE-LUA-HOOK api=%@ tolua_loadbuffer=%d luaL_loadbuffer=%d luaL_loadbufferx=%d addr_tol=%p addr_lual=%p addr_lualx=%p",
             api ?: @"none", toluaOK, luaLOK, luaLXOK, pTolua, pLuaL, pLuaLX]);
}

#pragma mark - Install managed hook

static BOOL JC41InstallMetadataHook(void) {
    if (gJC41MetadataInstalled) return YES;

    JC41DomainGetFn domainGet = (JC41DomainGetFn)JC41ResolveExport("il2cpp_domain_get");
    JC41DomainGetAssembliesFn domainGetAssemblies = (JC41DomainGetAssembliesFn)JC41ResolveExport("il2cpp_domain_get_assemblies");
    JC41AssemblyGetImageFn assemblyGetImage = (JC41AssemblyGetImageFn)JC41ResolveExport("il2cpp_assembly_get_image");
    JC41ImageGetNameFn imageGetName = (JC41ImageGetNameFn)JC41ResolveExport("il2cpp_image_get_name");
    JC41ClassFromNameFn classFromName = (JC41ClassFromNameFn)JC41ResolveExport("il2cpp_class_from_name");
    JC41ClassGetMethodFromNameFn classGetMethod = (JC41ClassGetMethodFromNameFn)JC41ResolveExport("il2cpp_class_get_method_from_name");
    if (!domainGet || !domainGetAssemblies || !assemblyGetImage || !classFromName || !classGetMethod) return NO;

    void *domain = domainGet();
    if (!domain) return NO;
    size_t count = 0;
    const void **assemblies = domainGetAssemblies(domain, &count);
    if (!assemblies || !count) return NO;

    const char *namespaces[] = {"LuaInterface", "LuaFramework", ""};
    const char *classes[] = {"LuaStatePtr", "LuaState"};
    BOOL foundAny = NO;

    for (size_t i = 0; i < count && !foundAny; i++) {
        void *image = assemblyGetImage(assemblies[i]);
        if (!image) continue;
        for (size_t n = 0; n < sizeof(namespaces)/sizeof(namespaces[0]) && !foundAny; n++) {
            for (size_t c = 0; c < sizeof(classes)/sizeof(classes[0]) && !foundAny; c++) {
                void *klass = classFromName(image, namespaces[n], classes[c]);
                if (!klass) continue;
                const void *m = classGetMethod(klass, "LuaLoadBuffer", 3);
                void *p = JC41MethodPointer(m);
                if (!p) continue;

                NSString *api = nil;
                BOOL ok = JC41Hook(p, (void *)JC41HookManagedLoadBuffer, (void **)&gJC41OrigManagedLoadBuffer, &api);
                gJC41MetadataInstalled = ok;
                foundAny = YES;

                NSString *imageName = @"?";
                if (imageGetName) {
                    const char *im = imageGetName(image);
                    if (im) imageName = [NSString stringWithUTF8String:im];
                }
                JC41Log([NSString stringWithFormat:@"MANAGED-LUA-HOOK installed=%d api=%@ assemblies=%lu image=%@ class=%s.%s method=LuaLoadBuffer/3 addr=%p",
                         ok, api ?: @"none", (unsigned long)count, imageName, namespaces[n], classes[c], p]);
            }
        }
    }

    if (!foundAny) {
        JC41Log([NSString stringWithFormat:@"MANAGED-LUA-HOOK class/method not found assemblies=%lu candidates=LuaInterface.LuaStatePtr,LuaState", (unsigned long)count]);
    }
    return gJC41MetadataInstalled;
}

static void JC41Poll(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        JC41InstallNativeHooks();
        if (gJC41MetadataInstalled) return;
        if (JC41InstallMetadataHook()) return;
        if (attempt < JC41_POLL_MAX) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JC41Poll(attempt + 1); });
        } else {
            JC41Log(@"MANAGED-LUA-HOOK timeout; native hooks (if available) remain active");
        }
    });
}

__attribute__((constructor)) static void JC41Entry(void) {
    @autoreleasepool {
        JC41SetupPaths();
        gJC41Queue = dispatch_queue_create("com.hfamap187.jsoncapture.lua.v041", DISPATCH_QUEUE_SERIAL);
        gJC41Seen = [[NSMutableSet alloc] init];
        JC41Log([NSString stringWithFormat:@"%@ loaded; VM-ready Lua 5.3 analyzer enabled", JC41_VERSION]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JC41Poll(0); });
    }
}
