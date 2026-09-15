#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#import "Lua53Analyzer.h"

#define JCG_VERSION @"JSONCapture Generic Sweep v0.4.2-g1"
#define JCG_PROFILE @"Unity2019.4/IL2CPP/ToLua/Lua5.3"
#define JCG_BATCH_TEXTASSETS 10
#define JCG_MAX_NAMES_PER_TICK 100
#define JCG_INTERVAL_SECONDS 5.0
#define JCG_MAX_BUFFER (64ULL * 1024ULL * 1024ULL)
#define JCG_MAX_ARRAY_ITEMS 250000
#define JCG_ENCM_XOR_KEY 0x4D

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} JCGIl2CppString;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    void *vector[0];
} JCGPtrArray;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    uint8_t vector[0];
} JCGByteArray;

typedef void *(*JCGDomainGetFn)(void);
typedef const void **(*JCGDomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JCGAssemblyGetImageFn)(const void *assembly);
typedef void *(*JCGClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JCGClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);
typedef const void *(*JCGClassGetTypeFn)(void *klass);
typedef void *(*JCGTypeGetObjectFn)(const void *type);
typedef void *(*JCGStringNewFn)(const char *str);

typedef void *(*JCGResourcesFindAllFn)(void *typeObj, const void *method);
typedef void *(*JCGAssetBundleGetAllNamesFn)(void *self, const void *method);
typedef void *(*JCGAssetBundleLoadAssetFn)(void *self, void *name, void *typeObj, const void *method);
typedef void *(*JCGTextAssetGetBytesFn)(void *self, const void *method);

typedef int (*JCGToluaLoadBufferFn)(void *L, const char *buffer, int size, const char *name);
typedef int (*JCGLuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);
typedef int (*JCGLuaGetTopFn)(void *L);
typedef void (*JCGLuaSetTopFn)(void *L, int idx);
typedef void *(*JCGLuaLNewStateFn)(void);
typedef void *(*JCGLuaNewStateFn)(void *allocFn, void *ud);

typedef void (*JCGMSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JCGDobbyHookFn)(void *address, void *replace, void **origin);

static JCGToluaLoadBufferFn gOrigToluaLoadBuffer;
static JCGLuaLLoadBufferXFn gOrigLuaLLoadBufferX;
static JCGLuaLLoadBufferXFn gEntryLuaLLoadBufferX;
static JCGLuaGetTopFn gLuaGetTop;
static JCGLuaSetTopFn gLuaSetTop;
static JCGLuaLNewStateFn gOrigLuaLNewState;
static JCGLuaNewStateFn gOrigLuaNewState;

static JCGResourcesFindAllFn gFindAllBundles;
static const void *gFindAllBundlesMethod;
static JCGAssetBundleGetAllNamesFn gGetAllAssetNames;
static const void *gGetAllAssetNamesMethod;
static JCGAssetBundleLoadAssetFn gLoadAsset;
static const void *gLoadAssetMethod;
static JCGTextAssetGetBytesFn gTextAssetGetBytes;
static const void *gTextAssetGetBytesMethod;
static void *gAssetBundleTypeObject;
static void *gTextAssetTypeObject;
static JCGStringNewFn gStringNew;

static NSString *gRootPath;
static NSString *gLogPath;
static dispatch_queue_t gIOQueue;
static NSMutableSet *gAttemptedAssets;
static NSMutableSet *gLoaderSeenHashes;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gStateLock = PTHREAD_MUTEX_INITIALIZER;
static void *gLuaState;
static NSString *gLuaStateSource;
static BOOL gUnityReady = NO;
static BOOL gNativeHooksReady = NO;
static BOOL gRunning = YES;

static unsigned long long gTick = 0;
static unsigned long long gBundlesSeen = 0;
static unsigned long long gNamesAttempted = 0;
static unsigned long long gTextAssets = 0;
static unsigned long long gLuaCandidates = 0;
static unsigned long long gJsonCandidates = 0;
static unsigned long long gUnknownTextAssets = 0;
static unsigned long long gDecodedENCM = 0;
static unsigned long long gWrappedLua = 0;
static unsigned long long gCompiledOK = 0;
static unsigned long long gCompileError = 0;
static unsigned long long gLoadFail = 0;
static unsigned long long gLoaderCaptured = 0;

#pragma mark - Paths / logging

static NSString *JCGNow(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JCGDocuments(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JCGEnsureDir(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void JCGSetupPaths(void) {
    if (gRootPath.length) return;
    NSString *base = [[JCGDocuments() stringByAppendingPathComponent:@"JSONCapture"] stringByAppendingPathComponent:@"Generic"];
    gRootPath = [[base stringByStandardizingPath] retain];
    gLogPath = [[gRootPath stringByAppendingPathComponent:@"GenericSweep.log"] retain];
    JCGEnsureDir(gRootPath);
    JCGEnsureDir([gRootPath stringByAppendingPathComponent:@"raw_textasset"]);
    JCGEnsureDir([gRootPath stringByAppendingPathComponent:@"json"]);
    JCGEnsureDir([gRootPath stringByAppendingPathComponent:@"lua_loader"]);
    JCGEnsureDir([gRootPath stringByAppendingPathComponent:@"lua53_analysis"]);
}

static void JCGLog(NSString *text) {
    if (!text.length) return;
    JCGSetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", JCGNow(), text];
    pthread_mutex_lock(&gLogLock);
    FILE *f = fopen(gLogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gLogLock);
}

static NSString *JCGSafeName(NSString *text) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, 140)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@"];
    for (NSUInteger i = 0; i < text.length && out.length < 140; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c];
        else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

static NSString *JCGSHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JCGHexPrefix(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = data.bytes;
    NSUInteger n = MIN((NSUInteger)24, data.length);
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

static NSString *JCGEscape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithString:s];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static NSString *JCGStringFromManaged(void *ptr) {
    if (!ptr) return nil;
    JCGIl2CppString *s = (JCGIl2CppString *)ptr;
    if (s->length <= 0 || s->length > (4 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)s->length] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSData *JCGDataFromByteArray(void *ptr) {
    if (!ptr) return nil;
    JCGByteArray *a = (JCGByteArray *)ptr;
    if (!a->max_length || a->max_length > JCG_MAX_BUFFER) return nil;
    @try {
        return [NSData dataWithBytes:a->vector length:(NSUInteger)a->max_length];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

#pragma mark - Classification

static BOOL JCGHasLua53Signature(NSData *data) {
    if (data.length < 6) return NO;
    const uint8_t *p = data.bytes;
    return p[0] == 0x1b && p[1] == 'L' && p[2] == 'u' && p[3] == 'a' && p[4] == 0x53;
}

static BOOL JCGLooksText(NSData *data) {
    if (!data.length) return NO;
    NSUInteger n = MIN((NSUInteger)32768, data.length);
    const uint8_t *p = data.bytes;
    NSUInteger bad = 0;
    for (NSUInteger i = 0; i < n; i++) {
        uint8_t c = p[i];
        if (c == 0) return NO;
        if (c < 0x09 || (c > 0x0d && c < 0x20)) bad++;
    }
    if (bad * 50 > n) return NO;
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, n)] encoding:NSUTF8StringEncoding] autorelease];
    return s != nil;
}

static BOOL JCGLooksJSON(NSData *data) {
    if (!data.length || !JCGLooksText(data)) return NO;
    const uint8_t *p = data.bytes;
    NSUInteger i = 0;
    if (data.length >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) i = 3;
    while (i < data.length && (p[i] == ' ' || p[i] == '\t' || p[i] == '\r' || p[i] == '\n')) i++;
    if (i >= data.length || (p[i] != '{' && p[i] != '[')) return NO;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
    return obj != nil && err == nil;
}

static BOOL JCGLooksLuaSource(NSData *data, NSString *assetName) {
    if (!JCGLooksText(data)) return NO;
    NSString *lowerName = assetName.lowercaseString ?: @"";
    if ([lowerName hasSuffix:@".lua"] || [lowerName containsString:@"/lua/"] || [lowerName containsString:@"\\lua\\"]) return YES;
    NSUInteger n = MIN((NSUInteger)32768, data.length);
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, n)] encoding:NSUTF8StringEncoding] autorelease];
    NSString *lower = s.lowercaseString;
    if (!lower.length) return NO;
    NSUInteger score = 0;
    NSArray *tokens = @[@"function ", @"local ", @"require(", @"require ", @"return ", @" end", @" then", @"tab_", @"setmetatable", @"pairs(", @"ipairs("];
    for (NSString *token in tokens) if ([lower containsString:token]) score++;
    return score >= 2 || ([lower containsString:@"tab_"] && [lower containsString:@"="]);
}

static NSData *JCGDecodeLuaCandidate(NSData *raw, NSString *assetName, NSString **kindOut) {
    if (kindOut) *kindOut = @"none";
    if (!raw.length || raw.length > JCG_MAX_BUFFER) return nil;

    if (JCGHasLua53Signature(raw)) {
        if (kindOut) *kindOut = @"plain-luac53";
        return raw;
    }

    const uint8_t *src = raw.bytes;
    if (raw.length > 4 && memcmp(src, "ENCM", 4) == 0) {
        NSUInteger outLen = raw.length - 4;
        NSMutableData *out = [NSMutableData dataWithLength:outLen];
        uint8_t *dst = out.mutableBytes;
        for (NSUInteger i = 0; i < outLen; i++) dst[i] = src[i + 4] ^ JCG_ENCM_XOR_KEY;
        if (JCGHasLua53Signature(out) || JCGLooksLuaSource(out, assetName)) {
            if (kindOut) *kindOut = @"encm-xor4d";
            return out;
        }
        if (kindOut) *kindOut = @"encm-unknown";
        return nil;
    }

    NSInteger off = JC4FindLua53SignatureOffset(raw);
    if (off > 0 && off <= 4096 && (NSUInteger)off < raw.length) {
        if (kindOut) *kindOut = [NSString stringWithFormat:@"wrapped-luac53+%ld", (long)off];
        return [raw subdataWithRange:NSMakeRange((NSUInteger)off, raw.length - (NSUInteger)off)];
    }

    if (JCGLooksLuaSource(raw, assetName)) {
        if (kindOut) *kindOut = @"plain-lua-text";
        return raw;
    }
    return nil;
}

#pragma mark - Loader capture / state observation

static void JCGRememberLuaState(void *L, NSString *source) {
    if (!L) return;
    pthread_mutex_lock(&gStateLock);
    BOOL changed = (L != gLuaState);
    gLuaState = L;
    if (changed) {
        [gLuaStateSource release];
        gLuaStateSource = [(source.length ? source : @"unknown") copy];
    }
    pthread_mutex_unlock(&gStateLock);
    if (changed) JCGLog([NSString stringWithFormat:@"LUA-STATE source=%@ native=%p", source ?: @"unknown", L]);
}

static void *JCGCurrentLuaState(NSString **sourceOut) {
    pthread_mutex_lock(&gStateLock);
    void *L = gLuaState;
    if (sourceOut) { NSString *src = gLuaStateSource ?: @"none"; *sourceOut = [[src copy] autorelease]; }
    pthread_mutex_unlock(&gStateLock);
    return L;
}

static void JCGCaptureLoader(NSData *data, NSString *source, NSString *chunkName) {
    if (!data.length || data.length > JCG_MAX_BUFFER || !gIOQueue) return;
    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = [(source ?: @"loader") copy];
    NSString *chunk = [(chunkName ?: @"unnamed") copy];
    dispatch_async(gIOQueue, ^{
        @autoreleasepool {
            NSString *hash = JCGSHA256(snapshot);
            if (!hash.length || [gLoaderSeenHashes containsObject:hash]) {
                [src release];
                [chunk release];
                return;
            }
            [gLoaderSeenHashes addObject:hash];
            gLoaderCaptured++;
            NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
            NSString *ext = JCGHasLua53Signature(snapshot) ? @"luac" : (JCGLooksText(snapshot) ? @"lua" : @"bin");
            NSString *name = [NSString stringWithFormat:@"%06llu_%@_%@_%@.%@", gLoaderCaptured, JCGSafeName(src), JCGSafeName(chunk), shortHash, ext];
            NSString *path = [[gRootPath stringByAppendingPathComponent:@"lua_loader"] stringByAppendingPathComponent:name];
            [snapshot writeToFile:path atomically:YES];
            NSInteger off = JC4FindLua53SignatureOffset(snapshot);
            if (off != NSNotFound) JC4AnalyzeLua53Data(snapshot, src, chunk, gRootPath);
            JCGLog([NSString stringWithFormat:@"LOADER-CAPTURE source=%@ chunk=%@ bytes=%lu sha=%@ file=%@", src, chunk, (unsigned long)snapshot.length, hash, name]);
            [src release];
            [chunk release];
        }
    });
}

#pragma mark - Hook backend

static void *JCGResolveExport(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    const char *paths[] = {"@rpath/UnityFramework.framework/UnityFramework", "UnityFramework.framework/UnityFramework"};
    for (size_t i = 0; i < sizeof(paths)/sizeof(paths[0]); i++) {
        void *h = dlopen(paths[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, name);
        if (p) return p;
    }
    return NULL;
}

static void *JCGResolveHookSymbol(const char *symbol) {
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    const char *libs[] = {
        "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/var/jb/usr/libsubstrate.dylib",
        "/usr/lib/libhooker.dylib",
        "/var/jb/usr/lib/libhooker.dylib",
        "/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libellekit.dylib"
    };
    for (size_t i = 0; i < sizeof(libs)/sizeof(libs[0]); i++) {
        void *h = dlopen(libs[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, symbol);
        if (p) return p;
    }
    return NULL;
}

static BOOL JCGHook(void *address, void *replacement, void **original, NSString **apiOut) {
    if (!address) return NO;
    JCGMSHookFunctionFn ms = (JCGMSHookFunctionFn)JCGResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (apiOut) *apiOut = @"MSHookFunction";
            return YES;
        }
    }
    JCGDobbyHookFn dobby = (JCGDobbyHookFn)JCGResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (apiOut) *apiOut = @"DobbyHook";
            return YES;
        }
    }
    return NO;
}

static int JCGHookToluaLoadBuffer(void *L, const char *buffer, int size, const char *name) {
    JCGRememberLuaState(L, @"tolua_loadbuffer");
    if (buffer && size > 0 && (uint64_t)size <= JCG_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:(NSUInteger)size];
        NSString *chunk = name ? [NSString stringWithUTF8String:name] : @"unnamed";
        JCGCaptureLoader(d, @"tolua_loadbuffer", chunk);
    }
    return gOrigToluaLoadBuffer ? gOrigToluaLoadBuffer(L, buffer, size, name) : -1;
}

static int JCGHookLuaLLoadBufferX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {
    JCGRememberLuaState(L, @"luaL_loadbufferx");
    if (buffer && size > 0 && size <= JCG_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:size];
        NSString *chunk = name ? [NSString stringWithUTF8String:name] : @"unnamed";
        JCGCaptureLoader(d, @"luaL_loadbufferx", chunk);
    }
    return gOrigLuaLLoadBufferX ? gOrigLuaLLoadBufferX(L, buffer, size, name, mode) : -1;
}

static void *JCGHookLuaLNewState(void) {
    void *L = gOrigLuaLNewState ? gOrigLuaLNewState() : NULL;
    JCGRememberLuaState(L, @"luaL_newstate");
    return L;
}

static void *JCGHookLuaNewState(void *allocFn, void *ud) {
    void *L = gOrigLuaNewState ? gOrigLuaNewState(allocFn, ud) : NULL;
    JCGRememberLuaState(L, @"lua_newstate");
    return L;
}

static BOOL JCGInstallNativeHooks(void) {
    if (gNativeHooksReady) return YES;
    void *pTolua = JCGResolveExport("tolua_loadbuffer");
    void *pLuaLX = JCGResolveExport("luaL_loadbufferx");
    void *pLNew = JCGResolveExport("luaL_newstate");
    void *pNew = JCGResolveExport("lua_newstate");
    gLuaGetTop = (JCGLuaGetTopFn)JCGResolveExport("lua_gettop");
    gLuaSetTop = (JCGLuaSetTopFn)JCGResolveExport("lua_settop");
    gEntryLuaLLoadBufferX = (JCGLuaLLoadBufferXFn)pLuaLX;
    if (!pLuaLX || !gLuaGetTop || !gLuaSetTop) return NO;

    NSString *apiTol = nil, *apiLX = nil, *apiLNew = nil, *apiNew = nil;
    BOOL okTol = pTolua ? JCGHook(pTolua, (void *)JCGHookToluaLoadBuffer, (void **)&gOrigToluaLoadBuffer, &apiTol) : NO;
    BOOL okLX = JCGHook(pLuaLX, (void *)JCGHookLuaLLoadBufferX, (void **)&gOrigLuaLLoadBufferX, &apiLX);
    BOOL okLNew = pLNew ? JCGHook(pLNew, (void *)JCGHookLuaLNewState, (void **)&gOrigLuaLNewState, &apiLNew) : NO;
    BOOL okNew = pNew ? JCGHook(pNew, (void *)JCGHookLuaNewState, (void **)&gOrigLuaNewState, &apiNew) : NO;
    gNativeHooksReady = okLX || okTol;
    JCGLog([NSString stringWithFormat:@"NATIVE-HOOK tolua=%d(%@) luaL_loadbufferx=%d(%@) luaL_newstate=%d(%@) lua_newstate=%d(%@) addr_tol=%p addr_lx=%p",
            okTol, apiTol ?: @"none", okLX, apiLX ?: @"none", okLNew, apiLNew ?: @"none", okNew, apiNew ?: @"none", pTolua, pLuaLX]);
    return gNativeHooksReady;
}

#pragma mark - Unity metadata

static void *JCGMethodPointer(const void *methodInfo) {
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

static void *JCGFindClass(JCGDomainGetAssembliesFn assembliesFn,
                          JCGAssemblyGetImageFn imageFn,
                          JCGClassFromNameFn classFn,
                          void *domain,
                          const char *namespaze,
                          const char *name) {
    size_t count = 0;
    const void **assemblies = assembliesFn(domain, &count);
    if (!assemblies || !count) return NULL;
    for (size_t i = 0; i < count; i++) {
        void *image = imageFn(assemblies[i]);
        if (!image) continue;
        void *klass = classFn(image, namespaze, name);
        if (klass) return klass;
    }
    return NULL;
}

static BOOL JCGResolveUnity(void) {
    if (gUnityReady) return YES;
    JCGDomainGetFn domainGet = (JCGDomainGetFn)JCGResolveExport("il2cpp_domain_get");
    JCGDomainGetAssembliesFn assembliesFn = (JCGDomainGetAssembliesFn)JCGResolveExport("il2cpp_domain_get_assemblies");
    JCGAssemblyGetImageFn imageFn = (JCGAssemblyGetImageFn)JCGResolveExport("il2cpp_assembly_get_image");
    JCGClassFromNameFn classFn = (JCGClassFromNameFn)JCGResolveExport("il2cpp_class_from_name");
    JCGClassGetMethodFromNameFn methodFn = (JCGClassGetMethodFromNameFn)JCGResolveExport("il2cpp_class_get_method_from_name");
    JCGClassGetTypeFn classGetType = (JCGClassGetTypeFn)JCGResolveExport("il2cpp_class_get_type");
    JCGTypeGetObjectFn typeGetObject = (JCGTypeGetObjectFn)JCGResolveExport("il2cpp_type_get_object");
    gStringNew = (JCGStringNewFn)JCGResolveExport("il2cpp_string_new");
    if (!domainGet || !assembliesFn || !imageFn || !classFn || !methodFn || !classGetType || !typeGetObject || !gStringNew) return NO;
    void *domain = domainGet();
    if (!domain) return NO;

    void *resourcesClass = JCGFindClass(assembliesFn, imageFn, classFn, domain, "UnityEngine", "Resources");
    void *bundleClass = JCGFindClass(assembliesFn, imageFn, classFn, domain, "UnityEngine", "AssetBundle");
    void *textAssetClass = JCGFindClass(assembliesFn, imageFn, classFn, domain, "UnityEngine", "TextAsset");
    if (!resourcesClass || !bundleClass || !textAssetClass) return NO;

    gFindAllBundlesMethod = methodFn(resourcesClass, "FindObjectsOfTypeAll", 1);
    gGetAllAssetNamesMethod = methodFn(bundleClass, "GetAllAssetNames", 0);
    gLoadAssetMethod = methodFn(bundleClass, "LoadAsset", 2);
    gTextAssetGetBytesMethod = methodFn(textAssetClass, "get_bytes", 0);
    gFindAllBundles = (JCGResourcesFindAllFn)JCGMethodPointer(gFindAllBundlesMethod);
    gGetAllAssetNames = (JCGAssetBundleGetAllNamesFn)JCGMethodPointer(gGetAllAssetNamesMethod);
    gLoadAsset = (JCGAssetBundleLoadAssetFn)JCGMethodPointer(gLoadAssetMethod);
    gTextAssetGetBytes = (JCGTextAssetGetBytesFn)JCGMethodPointer(gTextAssetGetBytesMethod);

    const void *bundleType = classGetType(bundleClass);
    const void *textType = classGetType(textAssetClass);
    gAssetBundleTypeObject = bundleType ? typeGetObject(bundleType) : NULL;
    gTextAssetTypeObject = textType ? typeGetObject(textType) : NULL;
    gUnityReady = gFindAllBundles && gGetAllAssetNames && gLoadAsset && gTextAssetGetBytes && gAssetBundleTypeObject && gTextAssetTypeObject;
    if (gUnityReady) {
        JCGLog([NSString stringWithFormat:@"UNITY-READY FindObjectsOfTypeAll=%p GetAllAssetNames=%p LoadAsset/2=%p TextAsset.get_bytes=%p",
                gFindAllBundles, gGetAllAssetNames, gLoadAsset, gTextAssetGetBytes]);
    }
    return gUnityReady;
}

#pragma mark - Sweep output

static void JCGAppendManifest(NSString *jsonLine) {
    if (!jsonLine.length) return;
    NSString *path = [gRootPath stringByAppendingPathComponent:@"manifest.jsonl"];
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [[jsonLine stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fclose(f);
    }
}

static NSString *JCGWriteRaw(NSData *raw, NSString *assetName, NSString *hash) {
    NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
    NSString *file = [NSString stringWithFormat:@"%@_%@.bin", JCGSafeName(assetName), shortHash];
    NSString *path = [[gRootPath stringByAppendingPathComponent:@"raw_textasset"] stringByAppendingPathComponent:file];
    [raw writeToFile:path atomically:YES];
    return file;
}

static NSString *JCGWriteJSON(NSData *raw, NSString *assetName, NSString *hash) {
    NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
    NSString *base = JCGSafeName(assetName.lastPathComponent.length ? assetName.lastPathComponent : assetName);
    if ([base.lowercaseString hasSuffix:@".json"]) base = [base substringToIndex:base.length - 5];
    NSString *file = [NSString stringWithFormat:@"%@_%@.json", base, shortHash];
    NSString *path = [[gRootPath stringByAppendingPathComponent:@"json"] stringByAppendingPathComponent:file];
    [raw writeToFile:path atomically:YES];
    return file;
}

static int JCGCompileOnly(NSData *decoded, NSString *assetName) {
    if (!decoded.length) return -1001;
    NSString *stateSource = nil;
    void *L = JCGCurrentLuaState(&stateSource);
    if (!L || !gLuaGetTop || !gLuaSetTop) return -1000;
    JCGLuaLLoadBufferXFn fn = gOrigLuaLLoadBufferX ?: gEntryLuaLLoadBufferX;
    if (!fn) return -1002;
    NSString *leaf = assetName.lastPathComponent.length ? assetName.lastPathComponent : assetName;
    NSString *chunk = [NSString stringWithFormat:@"@generic_sweep/%@", leaf ?: @"unknown.lua"];
    JCGCaptureLoader(decoded, @"generic-sweep", chunk);
    int oldTop = gLuaGetTop(L);
    int rc = fn(L, (const char *)decoded.bytes, decoded.length, chunk.UTF8String, "bt");
    gLuaSetTop(L, oldTop);
    return rc;
}

static void JCGWriteStatus(NSUInteger bundleCount, NSUInteger lastBatch, NSUInteger namesThisTick) {
    NSString *stateSource = nil;
    void *L = JCGCurrentLuaState(&stateSource);
    NSString *path = [gRootPath stringByAppendingPathComponent:@"GenericSweep.status.json"];
    NSString *json = [NSString stringWithFormat:
        @"{\n  \"version\": \"%@\",\n  \"profile\": \"%@\",\n  \"running\": %@,\n  \"interval_seconds\": %.1f,\n  \"batch_textassets\": %d,\n  \"max_names_per_tick\": %d,\n  \"tick\": %llu,\n  \"loaded_bundles\": %lu,\n  \"last_batch_textassets\": %lu,\n  \"last_names_attempted\": %lu,\n  \"names_attempted\": %llu,\n  \"textassets\": %llu,\n  \"lua_candidates\": %llu,\n  \"json_candidates\": %llu,\n  \"unknown_textassets\": %llu,\n  \"decoded_encm\": %llu,\n  \"wrapped_lua\": %llu,\n  \"compiled_ok\": %llu,\n  \"compile_error\": %llu,\n  \"load_fail\": %llu,\n  \"loader_captured\": %llu,\n  \"lua_state\": \"%p\",\n  \"lua_state_source\": \"%@\",\n  \"updated_at\": \"%@\"\n}\n",
        JCGEscape(JCG_VERSION), JCGEscape(JCG_PROFILE), gRunning ? @"true" : @"false", JCG_INTERVAL_SECONDS,
        JCG_BATCH_TEXTASSETS, JCG_MAX_NAMES_PER_TICK, gTick, (unsigned long)bundleCount, (unsigned long)lastBatch,
        (unsigned long)namesThisTick, gNamesAttempted, gTextAssets, gLuaCandidates, gJsonCandidates, gUnknownTextAssets,
        gDecodedENCM, gWrappedLua, gCompiledOK, gCompileError, gLoadFail, gLoaderCaptured, L, JCGEscape(stateSource ?: @"none"), JCGEscape(JCGNow())];
    [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Sweep loop

static NSUInteger JCGSweepBatch(NSUInteger *namesThisTickOut) {
    if (namesThisTickOut) *namesThisTickOut = 0;
    if (!JCGResolveUnity()) {
        JCGLog(@"WAIT Unity/IL2CPP metadata not ready");
        return 0;
    }

    void *arrayObj = gFindAllBundles(gAssetBundleTypeObject, gFindAllBundlesMethod);
    JCGPtrArray *bundles = (JCGPtrArray *)arrayObj;
    if (!bundles || bundles->max_length > JCG_MAX_ARRAY_ITEMS) return 0;
    NSUInteger bundleCount = (NSUInteger)bundles->max_length;
    gBundlesSeen = MAX(gBundlesSeen, bundleCount);

    NSUInteger textBatch = 0;
    NSUInteger namesThisTick = 0;
    for (NSUInteger bi = 0; bi < bundleCount && textBatch < JCG_BATCH_TEXTASSETS && namesThisTick < JCG_MAX_NAMES_PER_TICK; bi++) {
        void *bundle = bundles->vector[bi];
        if (!bundle) continue;
        void *namesObj = gGetAllAssetNames(bundle, gGetAllAssetNamesMethod);
        JCGPtrArray *names = (JCGPtrArray *)namesObj;
        if (!names || names->max_length > JCG_MAX_ARRAY_ITEMS) continue;

        for (NSUInteger ni = 0; ni < (NSUInteger)names->max_length && textBatch < JCG_BATCH_TEXTASSETS && namesThisTick < JCG_MAX_NAMES_PER_TICK; ni++) {
            NSString *assetName = JCGStringFromManaged(names->vector[ni]);
            if (!assetName.length) continue;
            NSString *key = [NSString stringWithFormat:@"%p|%@", bundle, assetName.lowercaseString];
            if ([gAttemptedAssets containsObject:key]) continue;
            [gAttemptedAssets addObject:key];
            namesThisTick++;
            gNamesAttempted++;

            void *managedName = gStringNew(assetName.UTF8String);
            void *asset = managedName ? gLoadAsset(bundle, managedName, gTextAssetTypeObject, gLoadAssetMethod) : NULL;
            if (!asset) {
                gLoadFail++;
                continue;
            }
            void *bytesObj = gTextAssetGetBytes(asset, gTextAssetGetBytesMethod);
            NSData *raw = JCGDataFromByteArray(bytesObj);
            if (!raw.length) {
                gLoadFail++;
                continue;
            }

            textBatch++;
            gTextAssets++;
            NSString *hash = JCGSHA256(raw);
            NSString *rawFile = JCGWriteRaw(raw, assetName, hash);
            NSString *jsonFile = @"";
            NSString *decodeKind = @"none";
            int compileRC = -9999;
            NSString *className = @"unknown";

            if (JCGLooksJSON(raw)) {
                gJsonCandidates++;
                className = @"json";
                jsonFile = JCGWriteJSON(raw, assetName, hash);
            }

            NSString *luaKind = nil;
            NSData *decoded = JCGDecodeLuaCandidate(raw, assetName, &luaKind);
            if (decoded.length) {
                gLuaCandidates++;
                decodeKind = luaKind ?: @"lua";
                className = [className isEqualToString:@"json"] ? @"json+lua" : @"lua";
                if ([decodeKind isEqualToString:@"encm-xor4d"]) gDecodedENCM++;
                if ([decodeKind hasPrefix:@"wrapped-luac53+"]) gWrappedLua++;
                compileRC = JCGCompileOnly(decoded, assetName);
                if (compileRC == 0) gCompiledOK++;
                else gCompileError++;
            } else if (![className isEqualToString:@"json"]) {
                gUnknownTextAssets++;
                className = JCGLooksText(raw) ? @"text" : @"binary-textasset";
                decodeKind = luaKind ?: @"none";
            }

            NSString *manifest = [NSString stringWithFormat:
                @"{\"time\":\"%@\",\"bundle\":\"%p\",\"asset\":\"%@\",\"bytes\":%lu,\"sha256\":\"%@\",\"class\":\"%@\",\"decode\":\"%@\",\"compile_rc\":%d,\"head24\":\"%@\",\"raw_file\":\"%@\",\"json_file\":\"%@\"}",
                JCGEscape(JCGNow()), bundle, JCGEscape(assetName), (unsigned long)raw.length, hash, className, decodeKind,
                compileRC, JCGHexPrefix(raw), JCGEscape(rawFile), JCGEscape(jsonFile)];
            JCGAppendManifest(manifest);
            JCGLog([NSString stringWithFormat:@"ASSET class=%@ decode=%@ rc=%d name=%@ bytes=%lu sha=%@", className, decodeKind, compileRC, assetName, (unsigned long)raw.length, hash]);
        }
    }
    if (namesThisTickOut) *namesThisTickOut = namesThisTick;
    JCGWriteStatus(bundleCount, textBatch, namesThisTick);
    return textBatch;
}

static void JCGScheduleNext(void);

static void JCGTick(void) {
    if (!gRunning) return;
    @autoreleasepool {
        gTick++;
        JCGInstallNativeHooks();
        NSUInteger namesThisTick = 0;
        NSUInteger batch = JCGSweepBatch(&namesThisTick);
        NSString *stateSource = nil;
        void *L = JCGCurrentLuaState(&stateSource);
        JCGLog([NSString stringWithFormat:@"TICK #%llu batch_text=%lu names=%lu state=%p source=%@ unity=%d native=%d",
                gTick, (unsigned long)batch, (unsigned long)namesThisTick, L, stateSource ?: @"none", gUnityReady, gNativeHooksReady]);
    }
    JCGScheduleNext();
}

static void JCGScheduleNext(void) {
    if (!gRunning) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(JCG_INTERVAL_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ JCGTick(); });
}

static void JCGPollNative(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (JCGInstallNativeHooks()) return;
        if (attempt < 240) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JCGPollNative(attempt + 1); });
        } else {
            JCGLog(@"NATIVE-HOOK timeout; sweep can inventory TextAssets but cannot compile Lua until loader APIs resolve");
        }
    });
}

__attribute__((constructor)) static void JCGEntry(void) {
    @autoreleasepool {
        JCGSetupPaths();
        gIOQueue = dispatch_queue_create("com.openai.jsoncapture.generic.io", DISPATCH_QUEUE_SERIAL);
        gAttemptedAssets = [[NSMutableSet alloc] init];
        gLoaderSeenHashes = [[NSMutableSet alloc] init];
        JCGLog([NSString stringWithFormat:@"%@ loaded profile=%@; generic/no fixed RVA; interval=%.1fs batch=%d max_names=%d; compile-only/no-execute",
                JCG_VERSION, JCG_PROFILE, JCG_INTERVAL_SECONDS, JCG_BATCH_TEXTASSETS, JCG_MAX_NAMES_PER_TICK]);
        JCGPollNative(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ JCGTick(); });
    }
}
