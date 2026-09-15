#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#import "Lua53Analyzer.h"

#define JCG2_VERSION @"JSONCapture Generic Full Sweep v0.4.2-g2"
#define JCG2_PROFILE @"Unity2019.4/IL2CPP/ToLua/Lua5.3/full-disk+runtime"
#define JCG2_LOADED_WATCH_SECONDS 0.50
#define JCG2_DISK_WATCH_SECONDS 1.00
#define JCG2_MAX_BUFFER (512ULL * 1024ULL * 1024ULL)
#define JCG2_MAX_ARRAY_ITEMS 2000000ULL
#define JCG2_ENCM_XOR_KEY 0x4D

typedef struct { void *klass; void *monitor; int32_t length; uint16_t chars[0]; } JCG2Il2CppString;
typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; void *vector[0]; } JCG2PtrArray;
typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; uint8_t vector[0]; } JCG2ByteArray;

typedef void *(*JCG2DomainGetFn)(void);
typedef const void **(*JCG2DomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JCG2AssemblyGetImageFn)(const void *assembly);
typedef void *(*JCG2ClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JCG2ClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);
typedef const void *(*JCG2ClassGetTypeFn)(void *klass);
typedef void *(*JCG2TypeGetObjectFn)(const void *type);
typedef void *(*JCG2StringNewFn)(const char *str);

typedef void *(*JCG2ResourcesFindAllFn)(void *typeObj, const void *method);
typedef void *(*JCG2AssetBundleGetAllNamesFn)(void *self, const void *method);
typedef void *(*JCG2AssetBundleLoadAssetFn)(void *self, void *name, void *typeObj, const void *method);
typedef void *(*JCG2AssetBundleLoadFromFileFn)(void *managedPath, const void *method);
typedef void (*JCG2AssetBundleUnloadFn)(void *self, BOOL unloadAllLoadedObjects, const void *method);
typedef void *(*JCG2TextAssetGetBytesFn)(void *self, const void *method);

typedef int (*JCG2ToluaLoadBufferFn)(void *L, const char *buffer, int size, const char *name);
typedef int (*JCG2LuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);
typedef int (*JCG2LuaGetTopFn)(void *L);
typedef void (*JCG2LuaSetTopFn)(void *L, int idx);
typedef void *(*JCG2LuaLNewStateFn)(void);
typedef void *(*JCG2LuaNewStateFn)(void *allocFn, void *ud);

typedef void (*JCG2MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JCG2DobbyHookFn)(void *address, void *replace, void **origin);

static JCG2ToluaLoadBufferFn gOrigToluaLoadBuffer;
static JCG2LuaLLoadBufferXFn gOrigLuaLLoadBufferX;
static JCG2LuaLLoadBufferXFn gEntryLuaLLoadBufferX;
static JCG2LuaGetTopFn gLuaGetTop;
static JCG2LuaSetTopFn gLuaSetTop;
static JCG2LuaLNewStateFn gOrigLuaLNewState;
static JCG2LuaNewStateFn gOrigLuaNewState;

static JCG2ResourcesFindAllFn gFindAllBundles;
static const void *gFindAllBundlesMethod;
static JCG2AssetBundleGetAllNamesFn gGetAllAssetNames;
static const void *gGetAllAssetNamesMethod;
static JCG2AssetBundleLoadAssetFn gLoadAsset;
static const void *gLoadAssetMethod;
static JCG2AssetBundleLoadFromFileFn gLoadFromFile;
static const void *gLoadFromFileMethod;
static JCG2AssetBundleUnloadFn gUnload;
static const void *gUnloadMethod;
static JCG2TextAssetGetBytesFn gTextAssetGetBytes;
static const void *gTextAssetGetBytesMethod;
static void *gAssetBundleTypeObject;
static void *gTextAssetTypeObject;
static JCG2StringNewFn gStringNew;

static NSString *gRootPath;
static NSString *gLogPath;
static dispatch_queue_t gIOQueue;
static dispatch_queue_t gDiskQueue;
static NSMutableSet *gAttemptedAssets;
static NSMutableSet *gKnownLoadedBundles;
static NSMutableSet *gLoaderSeenHashes;
static NSMutableDictionary *gDiskSeenVersions;
static NSMutableSet *gDiskPendingPaths;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gStateLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gDiskLock = PTHREAD_MUTEX_INITIALIZER;
static void *gLuaState;
static NSString *gLuaStateSource;
static BOOL gUnityReady = NO;
static BOOL gNativeHooksReady = NO;
static BOOL gRunning = YES;
static BOOL gDiskWorkerActive = NO;

static unsigned long long gLoadedWatchTick = 0;
static unsigned long long gDiskWatchTick = 0;
static unsigned long long gBundlesDiscovered = 0;
static unsigned long long gBundlesSwept = 0;
static unsigned long long gDiskFilesSeen = 0;
static unsigned long long gDiskBundleCandidates = 0;
static unsigned long long gDiskBundlesLoaded = 0;
static unsigned long long gDiskBundlesFailed = 0;
static unsigned long long gNamesAttempted = 0;
static unsigned long long gTextAssets = 0;
static unsigned long long gLuaCandidates = 0;
static unsigned long long gJsonCandidates = 0;
static unsigned long long gUnknownTextAssets = 0;
static unsigned long long gDecodedENCM = 0;
static unsigned long long gWrappedLua = 0;
static unsigned long long gCompiledOK = 0;
static unsigned long long gCompileError = 0;
static unsigned long long gCompileSkippedNoState = 0;
static unsigned long long gNonTextAssets = 0;
static unsigned long long gLoaderCaptured = 0;

#pragma mark - Basic helpers

static NSString *JCG2Now(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JCG2Documents(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JCG2EnsureDir(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

static void JCG2SetupPaths(void) {
    if (gRootPath.length) return;
    NSString *base = [[JCG2Documents() stringByAppendingPathComponent:@"JSONCapture"] stringByAppendingPathComponent:@"FullSweep"];
    gRootPath = [[base stringByStandardizingPath] retain];
    gLogPath = [[gRootPath stringByAppendingPathComponent:@"FullSweep.log"] retain];
    JCG2EnsureDir(gRootPath);
    for (NSString *dir in @[@"raw_textasset", @"decoded_lua", @"json", @"lua_loader", @"lua53_analysis"]) {
        JCG2EnsureDir([gRootPath stringByAppendingPathComponent:dir]);
    }
}

static void JCG2Log(NSString *text) {
    if (!text.length) return;
    JCG2SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", JCG2Now(), text];
    pthread_mutex_lock(&gLogLock);
    FILE *f = fopen(gLogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f); fflush(f); fclose(f);
    }
    pthread_mutex_unlock(&gLogLock);
}

static NSString *JCG2SafeName(NSString *text) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, 160)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@+"];
    for (NSUInteger i = 0; i < text.length && out.length < 160; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c]; else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

static NSString *JCG2SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JCG2HexPrefix(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = data.bytes; NSUInteger n = MIN((NSUInteger)24, data.length);
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

static NSString *JCG2Escape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithString:s];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static NSString *JCG2StringFromManaged(void *ptr) {
    if (!ptr) return nil;
    JCG2Il2CppString *s = (JCG2Il2CppString *)ptr;
    if (s->length <= 0 || s->length > (4 * 1024 * 1024)) return nil;
    @try { return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)s->length] autorelease]; }
    @catch (__unused NSException *e) { return nil; }
}

static NSData *JCG2DataFromByteArray(void *ptr) {
    if (!ptr) return nil;
    JCG2ByteArray *a = (JCG2ByteArray *)ptr;
    if (!a->max_length || a->max_length > JCG2_MAX_BUFFER) return nil;
    @try { return [NSData dataWithBytes:a->vector length:(NSUInteger)a->max_length]; }
    @catch (__unused NSException *e) { return nil; }
}

#pragma mark - Data classification

static BOOL JCG2HasLua53Signature(NSData *data) {
    if (data.length < 6) return NO;
    const uint8_t *p = data.bytes;
    return p[0] == 0x1b && p[1] == 'L' && p[2] == 'u' && p[3] == 'a' && p[4] == 0x53;
}

static BOOL JCG2LooksText(NSData *data) {
    if (!data.length) return NO;
    NSUInteger n = MIN((NSUInteger)32768, data.length); const uint8_t *p = data.bytes; NSUInteger bad = 0;
    for (NSUInteger i = 0; i < n; i++) { uint8_t c = p[i]; if (c == 0) return NO; if (c < 0x09 || (c > 0x0d && c < 0x20)) bad++; }
    if (bad * 50 > n) return NO;
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, n)] encoding:NSUTF8StringEncoding] autorelease];
    return s != nil;
}

static BOOL JCG2LooksJSON(NSData *data) {
    if (!data.length || !JCG2LooksText(data)) return NO;
    NSError *err = nil; id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
    return obj != nil && err == nil;
}

static BOOL JCG2LooksLuaSource(NSData *data, NSString *assetName) {
    if (!JCG2LooksText(data)) return NO;
    NSString *lowerName = assetName.lowercaseString ?: @"";
    if ([lowerName hasSuffix:@".lua"] || [lowerName containsString:@"/lua/"] || [lowerName containsString:@"\\lua\\"]) return YES;
    NSUInteger n = MIN((NSUInteger)32768, data.length);
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, n)] encoding:NSUTF8StringEncoding] autorelease];
    NSString *lower = s.lowercaseString; if (!lower.length) return NO;
    NSArray *tokens = @[@"function ", @"local ", @"require(", @"require ", @"return ", @" end", @" then", @"tab_", @"setmetatable", @"pairs(", @"ipairs("];
    NSUInteger score = 0; for (NSString *token in tokens) if ([lower containsString:token]) score++;
    return score >= 2 || ([lower containsString:@"tab_"] && [lower containsString:@"="]);
}

static NSData *JCG2DecodeLuaCandidate(NSData *raw, NSString *assetName, NSString **kindOut) {
    if (kindOut) *kindOut = @"none";
    if (!raw.length || raw.length > JCG2_MAX_BUFFER) return nil;
    if (JCG2HasLua53Signature(raw)) { if (kindOut) *kindOut = @"plain-luac53"; return raw; }
    const uint8_t *src = raw.bytes;
    if (raw.length > 4 && memcmp(src, "ENCM", 4) == 0) {
        NSUInteger outLen = raw.length - 4; NSMutableData *out = [NSMutableData dataWithLength:outLen]; uint8_t *dst = out.mutableBytes;
        for (NSUInteger i = 0; i < outLen; i++) dst[i] = src[i + 4] ^ JCG2_ENCM_XOR_KEY;
        if (JCG2HasLua53Signature(out) || JCG2LooksLuaSource(out, assetName)) { if (kindOut) *kindOut = @"encm-xor4d"; return out; }
        if (kindOut) *kindOut = @"encm-unknown"; return nil;
    }
    NSInteger off = JC4FindLua53SignatureOffset(raw);
    if (off > 0 && off <= 4096 && (NSUInteger)off < raw.length) {
        if (kindOut) *kindOut = [NSString stringWithFormat:@"wrapped-luac53+%ld", (long)off];
        return [raw subdataWithRange:NSMakeRange((NSUInteger)off, raw.length - (NSUInteger)off)];
    }
    if (JCG2LooksLuaSource(raw, assetName)) { if (kindOut) *kindOut = @"plain-lua-text"; return raw; }
    return nil;
}

#pragma mark - Lua state and loader capture

static void JCG2RememberLuaState(void *L, NSString *source) {
    if (!L) return;
    pthread_mutex_lock(&gStateLock); BOOL changed = (L != gLuaState); gLuaState = L;
    if (changed) { [gLuaStateSource release]; gLuaStateSource = [(source.length ? source : @"unknown") copy]; }
    pthread_mutex_unlock(&gStateLock);
    if (changed) JCG2Log([NSString stringWithFormat:@"LUA-STATE source=%@ native=%p", source ?: @"unknown", L]);
}

static void *JCG2CurrentLuaState(NSString **sourceOut) {
    pthread_mutex_lock(&gStateLock); void *L = gLuaState;
    if (sourceOut) { NSString *src = gLuaStateSource ?: @"none"; *sourceOut = [[src copy] autorelease]; }
    pthread_mutex_unlock(&gStateLock); return L;
}

static void JCG2CaptureLoader(NSData *data, NSString *source, NSString *chunkName) {
    if (!data.length || data.length > JCG2_MAX_BUFFER || !gIOQueue) return;
    NSData *snapshot = [NSData dataWithData:data]; NSString *src = [(source ?: @"loader") copy]; NSString *chunk = [(chunkName ?: @"unnamed") copy];
    dispatch_async(gIOQueue, ^{ @autoreleasepool {
        NSString *hash = JCG2SHA256(snapshot);
        if (!hash.length || [gLoaderSeenHashes containsObject:hash]) { [src release]; [chunk release]; return; }
        [gLoaderSeenHashes addObject:hash]; gLoaderCaptured++;
        NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
        NSString *ext = JCG2HasLua53Signature(snapshot) ? @"luac" : (JCG2LooksText(snapshot) ? @"lua" : @"bin");
        NSString *name = [NSString stringWithFormat:@"%06llu_%@_%@_%@.%@", gLoaderCaptured, JCG2SafeName(src), JCG2SafeName(chunk), shortHash, ext];
        NSString *path = [[gRootPath stringByAppendingPathComponent:@"lua_loader"] stringByAppendingPathComponent:name];
        [snapshot writeToFile:path atomically:YES]; NSInteger off = JC4FindLua53SignatureOffset(snapshot);
        if (off != NSNotFound) JC4AnalyzeLua53Data(snapshot, src, chunk, gRootPath);
        JCG2Log([NSString stringWithFormat:@"LOADER-CAPTURE source=%@ chunk=%@ bytes=%lu sha=%@", src, chunk, (unsigned long)snapshot.length, hash]);
        [src release]; [chunk release];
    }});
}

#pragma mark - Dynamic symbols / hooks

static void *JCG2ResolveExport(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name); if (p) return p;
    const char *paths[] = {"@rpath/UnityFramework.framework/UnityFramework", "UnityFramework.framework/UnityFramework"};
    for (size_t i = 0; i < sizeof(paths)/sizeof(paths[0]); i++) { void *h = dlopen(paths[i], RTLD_LAZY | RTLD_GLOBAL); if (!h) continue; p = dlsym(h, name); if (p) return p; }
    return NULL;
}

static void *JCG2ResolveHookSymbol(const char *symbol) {
    void *p = dlsym(RTLD_DEFAULT, symbol); if (p) return p;
    const char *libs[] = {"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", "/usr/lib/libsubstrate.dylib", "/var/jb/usr/lib/libsubstrate.dylib", "/usr/lib/libhooker.dylib", "/var/jb/usr/lib/libhooker.dylib", "/usr/lib/libellekit.dylib", "/var/jb/usr/lib/libellekit.dylib"};
    for (size_t i = 0; i < sizeof(libs)/sizeof(libs[0]); i++) { void *h = dlopen(libs[i], RTLD_LAZY | RTLD_GLOBAL); if (!h) continue; p = dlsym(h, symbol); if (p) return p; }
    return NULL;
}

static BOOL JCG2Hook(void *address, void *replacement, void **original, NSString **apiOut) {
    if (!address) return NO;
    JCG2MSHookFunctionFn ms = (JCG2MSHookFunctionFn)JCG2ResolveHookSymbol("MSHookFunction");
    if (ms) { ms(address, replacement, original); if (original && *original) { if (apiOut) *apiOut = @"MSHookFunction"; return YES; } }
    JCG2DobbyHookFn dobby = (JCG2DobbyHookFn)JCG2ResolveHookSymbol("DobbyHook");
    if (dobby) { int rc = dobby(address, replacement, original); if (rc == 0 && original && *original) { if (apiOut) *apiOut = @"DobbyHook"; return YES; } }
    return NO;
}

static int JCG2HookToluaLoadBuffer(void *L, const char *buffer, int size, const char *name) {
    JCG2RememberLuaState(L, @"tolua_loadbuffer");
    if (buffer && size > 0 && (uint64_t)size <= JCG2_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:(NSUInteger)size]; NSString *chunk = name ? [NSString stringWithUTF8String:name] : @"unnamed";
        JCG2CaptureLoader(d, @"tolua_loadbuffer", chunk);
    }
    return gOrigToluaLoadBuffer ? gOrigToluaLoadBuffer(L, buffer, size, name) : -1;
}

static int JCG2HookLuaLLoadBufferX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {
    JCG2RememberLuaState(L, @"luaL_loadbufferx");
    if (buffer && size > 0 && size <= JCG2_MAX_BUFFER) {
        NSData *d = [NSData dataWithBytes:buffer length:size]; NSString *chunk = name ? [NSString stringWithUTF8String:name] : @"unnamed";
        JCG2CaptureLoader(d, @"luaL_loadbufferx", chunk);
    }
    return gOrigLuaLLoadBufferX ? gOrigLuaLLoadBufferX(L, buffer, size, name, mode) : -1;
}

static void *JCG2HookLuaLNewState(void) { void *L = gOrigLuaLNewState ? gOrigLuaLNewState() : NULL; JCG2RememberLuaState(L, @"luaL_newstate"); return L; }
static void *JCG2HookLuaNewState(void *allocFn, void *ud) { void *L = gOrigLuaNewState ? gOrigLuaNewState(allocFn, ud) : NULL; JCG2RememberLuaState(L, @"lua_newstate"); return L; }

static BOOL JCG2InstallNativeHooks(void) {
    if (gNativeHooksReady) return YES;
    void *pTolua = JCG2ResolveExport("tolua_loadbuffer"); void *pLuaLX = JCG2ResolveExport("luaL_loadbufferx");
    void *pLNew = JCG2ResolveExport("luaL_newstate"); void *pNew = JCG2ResolveExport("lua_newstate");
    gLuaGetTop = (JCG2LuaGetTopFn)JCG2ResolveExport("lua_gettop"); gLuaSetTop = (JCG2LuaSetTopFn)JCG2ResolveExport("lua_settop");
    gEntryLuaLLoadBufferX = (JCG2LuaLLoadBufferXFn)pLuaLX;
    if (!pLuaLX || !gLuaGetTop || !gLuaSetTop) return NO;
    NSString *apiTol=nil,*apiLX=nil,*apiLNew=nil,*apiNew=nil;
    BOOL okTol = pTolua ? JCG2Hook(pTolua,(void *)JCG2HookToluaLoadBuffer,(void **)&gOrigToluaLoadBuffer,&apiTol) : NO;
    BOOL okLX = JCG2Hook(pLuaLX,(void *)JCG2HookLuaLLoadBufferX,(void **)&gOrigLuaLLoadBufferX,&apiLX);
    BOOL okLNew = pLNew ? JCG2Hook(pLNew,(void *)JCG2HookLuaLNewState,(void **)&gOrigLuaLNewState,&apiLNew) : NO;
    BOOL okNew = pNew ? JCG2Hook(pNew,(void *)JCG2HookLuaNewState,(void **)&gOrigLuaNewState,&apiNew) : NO;
    gNativeHooksReady = okTol || okLX;
    JCG2Log([NSString stringWithFormat:@"NATIVE-HOOK tolua=%d(%@) luaL_loadbufferx=%d(%@) luaL_newstate=%d(%@) lua_newstate=%d(%@)", okTol,apiTol?:@"none",okLX,apiLX?:@"none",okLNew,apiLNew?:@"none",okNew,apiNew?:@"none"]);
    return gNativeHooksReady;
}

#pragma mark - Unity metadata

static void *JCG2MethodPointer(const void *methodInfo) {
    if (!methodInfo) return NULL;
    @try { void *p = *(void * const *)methodInfo; if (!p) return NULL; Dl_info info; memset(&info,0,sizeof(info)); if (dladdr(p,&info)==0) return NULL; return p; }
    @catch (__unused NSException *e) { return NULL; }
}

static void *JCG2FindClass(JCG2DomainGetAssembliesFn assembliesFn, JCG2AssemblyGetImageFn imageFn, JCG2ClassFromNameFn classFn, void *domain, const char *namespaze, const char *name) {
    size_t count = 0; const void **assemblies = assembliesFn(domain,&count); if (!assemblies || !count) return NULL;
    for (size_t i=0;i<count;i++) { void *image = imageFn(assemblies[i]); if (!image) continue; void *klass = classFn(image,namespaze,name); if (klass) return klass; }
    return NULL;
}

static BOOL JCG2ResolveUnity(void) {
    if (gUnityReady) return YES;
    JCG2DomainGetFn domainGet=(JCG2DomainGetFn)JCG2ResolveExport("il2cpp_domain_get");
    JCG2DomainGetAssembliesFn assembliesFn=(JCG2DomainGetAssembliesFn)JCG2ResolveExport("il2cpp_domain_get_assemblies");
    JCG2AssemblyGetImageFn imageFn=(JCG2AssemblyGetImageFn)JCG2ResolveExport("il2cpp_assembly_get_image");
    JCG2ClassFromNameFn classFn=(JCG2ClassFromNameFn)JCG2ResolveExport("il2cpp_class_from_name");
    JCG2ClassGetMethodFromNameFn methodFn=(JCG2ClassGetMethodFromNameFn)JCG2ResolveExport("il2cpp_class_get_method_from_name");
    JCG2ClassGetTypeFn classGetType=(JCG2ClassGetTypeFn)JCG2ResolveExport("il2cpp_class_get_type");
    JCG2TypeGetObjectFn typeGetObject=(JCG2TypeGetObjectFn)JCG2ResolveExport("il2cpp_type_get_object");
    gStringNew=(JCG2StringNewFn)JCG2ResolveExport("il2cpp_string_new");
    if (!domainGet||!assembliesFn||!imageFn||!classFn||!methodFn||!classGetType||!typeGetObject||!gStringNew) return NO;
    void *domain=domainGet(); if (!domain) return NO;
    void *resourcesClass=JCG2FindClass(assembliesFn,imageFn,classFn,domain,"UnityEngine","Resources");
    void *bundleClass=JCG2FindClass(assembliesFn,imageFn,classFn,domain,"UnityEngine","AssetBundle");
    void *textAssetClass=JCG2FindClass(assembliesFn,imageFn,classFn,domain,"UnityEngine","TextAsset");
    if (!resourcesClass||!bundleClass||!textAssetClass) return NO;
    gFindAllBundlesMethod=methodFn(resourcesClass,"FindObjectsOfTypeAll",1);
    gGetAllAssetNamesMethod=methodFn(bundleClass,"GetAllAssetNames",0);
    gLoadAssetMethod=methodFn(bundleClass,"LoadAsset",2);
    gLoadFromFileMethod=methodFn(bundleClass,"LoadFromFile",1);
    gUnloadMethod=methodFn(bundleClass,"Unload",1);
    gTextAssetGetBytesMethod=methodFn(textAssetClass,"get_bytes",0);
    gFindAllBundles=(JCG2ResourcesFindAllFn)JCG2MethodPointer(gFindAllBundlesMethod);
    gGetAllAssetNames=(JCG2AssetBundleGetAllNamesFn)JCG2MethodPointer(gGetAllAssetNamesMethod);
    gLoadAsset=(JCG2AssetBundleLoadAssetFn)JCG2MethodPointer(gLoadAssetMethod);
    gLoadFromFile=(JCG2AssetBundleLoadFromFileFn)JCG2MethodPointer(gLoadFromFileMethod);
    gUnload=(JCG2AssetBundleUnloadFn)JCG2MethodPointer(gUnloadMethod);
    gTextAssetGetBytes=(JCG2TextAssetGetBytesFn)JCG2MethodPointer(gTextAssetGetBytesMethod);
    const void *bundleType=classGetType(bundleClass); const void *textType=classGetType(textAssetClass);
    gAssetBundleTypeObject=bundleType?typeGetObject(bundleType):NULL; gTextAssetTypeObject=textType?typeGetObject(textType):NULL;
    gUnityReady=gFindAllBundles&&gGetAllAssetNames&&gLoadAsset&&gTextAssetGetBytes&&gAssetBundleTypeObject&&gTextAssetTypeObject;
    if (gUnityReady) JCG2Log([NSString stringWithFormat:@"UNITY-READY FindAll=%p GetNames=%p LoadAsset=%p LoadFromFile=%p Unload=%p TextBytes=%p",gFindAllBundles,gGetAllAssetNames,gLoadAsset,gLoadFromFile,gUnload,gTextAssetGetBytes]);
    return gUnityReady;
}

#pragma mark - Output / compile

static void JCG2AppendManifest(NSString *jsonLine) {
    if (!jsonLine.length) return; NSString *path=[gRootPath stringByAppendingPathComponent:@"manifest.jsonl"];
    pthread_mutex_lock(&gLogLock); FILE *f=fopen(path.fileSystemRepresentation,"a"); if(f){NSData*d=[[jsonLine stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]; fwrite(d.bytes,1,d.length,f); fclose(f);} pthread_mutex_unlock(&gLogLock);
}

static NSString *JCG2WriteData(NSData *data, NSString *dir, NSString *assetName, NSString *hash, NSString *ext) {
    NSString *shortHash=hash.length>12?[hash substringToIndex:12]:hash; NSString *file=[NSString stringWithFormat:@"%@_%@.%@",JCG2SafeName(assetName),shortHash,ext];
    NSString *path=[[gRootPath stringByAppendingPathComponent:dir] stringByAppendingPathComponent:file]; if(![[NSFileManager defaultManager] fileExistsAtPath:path]) [data writeToFile:path atomically:YES]; return file;
}

static int JCG2CompileOnly(NSData *decoded, NSString *assetName) {
    if (!decoded.length) return -1001; NSString *src=nil; void *L=JCG2CurrentLuaState(&src); if(!L||!gLuaGetTop||!gLuaSetTop){gCompileSkippedNoState++;return -1000;}
    JCG2LuaLLoadBufferXFn fn=gOrigLuaLLoadBufferX?:gEntryLuaLLoadBufferX; if(!fn)return -1002;
    NSString *leaf=assetName.lastPathComponent.length?assetName.lastPathComponent:assetName; NSString *chunk=[NSString stringWithFormat:@"@full_sweep/%@",leaf?:@"unknown.lua"];
    JCG2CaptureLoader(decoded,@"full-sweep",chunk); int oldTop=gLuaGetTop(L); int rc=fn(L,(const char *)decoded.bytes,decoded.length,chunk.UTF8String,"bt"); gLuaSetTop(L,oldTop); return rc;
}

static void JCG2WriteStatus(void) {
    NSString *stateSource=nil; void *L=JCG2CurrentLuaState(&stateSource); NSString *path=[gRootPath stringByAppendingPathComponent:@"FullSweep.status.json"];
    NSString *json=[NSString stringWithFormat:@"{\n  \"version\": \"%@\",\n  \"profile\": \"%@\",\n  \"running\": %@,\n  \"artificial_batch_limits\": false,\n  \"loaded_watch_seconds\": %.2f,\n  \"disk_watch_seconds\": %.2f,\n  \"loaded_watch_tick\": %llu,\n  \"disk_watch_tick\": %llu,\n  \"bundles_discovered\": %llu,\n  \"bundles_swept\": %llu,\n  \"disk_files_seen\": %llu,\n  \"disk_bundle_candidates\": %llu,\n  \"disk_bundles_loaded\": %llu,\n  \"disk_bundles_failed\": %llu,\n  \"names_attempted\": %llu,\n  \"textassets\": %llu,\n  \"non_textassets\": %llu,\n  \"lua_candidates\": %llu,\n  \"json_candidates\": %llu,\n  \"unknown_textassets\": %llu,\n  \"decoded_encm\": %llu,\n  \"wrapped_lua\": %llu,\n  \"compiled_ok\": %llu,\n  \"compile_error\": %llu,\n  \"compile_skipped_no_state\": %llu,\n  \"loader_captured\": %llu,\n  \"lua_state\": \"%p\",\n  \"lua_state_source\": \"%@\",\n  \"updated_at\": \"%@\"\n}\n",
        JCG2Escape(JCG2_VERSION),JCG2Escape(JCG2_PROFILE),gRunning?@"true":@"false",JCG2_LOADED_WATCH_SECONDS,JCG2_DISK_WATCH_SECONDS,gLoadedWatchTick,gDiskWatchTick,gBundlesDiscovered,gBundlesSwept,gDiskFilesSeen,gDiskBundleCandidates,gDiskBundlesLoaded,gDiskBundlesFailed,gNamesAttempted,gTextAssets,gNonTextAssets,gLuaCandidates,gJsonCandidates,gUnknownTextAssets,gDecodedENCM,gWrappedLua,gCompiledOK,gCompileError,gCompileSkippedNoState,gLoaderCaptured,L,JCG2Escape(stateSource?:@"none"),JCG2Escape(JCG2Now())];
    [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Bundle processing (no count/batch limits)

static NSUInteger JCG2SweepBundle(void *bundle, NSString *origin) {
    if (!bundle||!gGetAllAssetNames||!gLoadAsset||!gTextAssetGetBytes) return 0;
    void *namesObj=gGetAllAssetNames(bundle,gGetAllAssetNamesMethod); JCG2PtrArray *names=(JCG2PtrArray *)namesObj;
    if(!names||names->max_length>JCG2_MAX_ARRAY_ITEMS)return 0;
    NSUInteger processed=0; gBundlesSwept++;
    for(NSUInteger ni=0;ni<(NSUInteger)names->max_length;ni++){@autoreleasepool{
        NSString *assetName=JCG2StringFromManaged(names->vector[ni]); if(!assetName.length)continue;
        NSString *key=[NSString stringWithFormat:@"%p|%@",bundle,assetName.lowercaseString]; if([gAttemptedAssets containsObject:key])continue; [gAttemptedAssets addObject:key]; gNamesAttempted++;
        void *managedName=gStringNew(assetName.UTF8String); void *asset=managedName?gLoadAsset(bundle,managedName,gTextAssetTypeObject,gLoadAssetMethod):NULL;
        if(!asset){gNonTextAssets++;continue;} void *bytesObj=gTextAssetGetBytes(asset,gTextAssetGetBytesMethod); NSData *raw=JCG2DataFromByteArray(bytesObj); if(!raw.length){gNonTextAssets++;continue;}
        processed++; gTextAssets++; NSString *hash=JCG2SHA256(raw); NSString *rawFile=JCG2WriteData(raw,@"raw_textasset",assetName,hash,@"bin"); NSString *jsonFile=@""; NSString *decodedFile=@""; NSString *className=@"unknown"; NSString *decodeKind=@"none"; int compileRC=-9999;
        if(JCG2LooksJSON(raw)){gJsonCandidates++;className=@"json";jsonFile=JCG2WriteData(raw,@"json",assetName,hash,@"json");}
        NSString *luaKind=nil; NSData *decoded=JCG2DecodeLuaCandidate(raw,assetName,&luaKind);
        if(decoded.length){gLuaCandidates++;decodeKind=luaKind?:@"lua";className=[className isEqualToString:@"json"]?@"json+lua":@"lua";if([decodeKind isEqualToString:@"encm-xor4d"])gDecodedENCM++;if([decodeKind hasPrefix:@"wrapped-luac53+"])gWrappedLua++;NSString *dh=JCG2SHA256(decoded);decodedFile=JCG2WriteData(decoded,@"decoded_lua",assetName,dh,JCG2HasLua53Signature(decoded)?@"luac":@"lua");compileRC=JCG2CompileOnly(decoded,assetName);if(compileRC==0)gCompiledOK++;else if(compileRC!=-1000)gCompileError++;}
        else if(![className isEqualToString:@"json"]){gUnknownTextAssets++;className=JCG2LooksText(raw)?@"text":@"binary-textasset";decodeKind=luaKind?:@"none";}
        NSString *manifest=[NSString stringWithFormat:@"{\"time\":\"%@\",\"origin\":\"%@\",\"bundle\":\"%p\",\"asset\":\"%@\",\"bytes\":%lu,\"sha256\":\"%@\",\"class\":\"%@\",\"decode\":\"%@\",\"compile_rc\":%d,\"head24\":\"%@\",\"raw_file\":\"%@\",\"decoded_file\":\"%@\",\"json_file\":\"%@\"}",JCG2Escape(JCG2Now()),JCG2Escape(origin?:@"runtime"),bundle,JCG2Escape(assetName),(unsigned long)raw.length,hash,className,decodeKind,compileRC,JCG2HexPrefix(raw),JCG2Escape(rawFile),JCG2Escape(decodedFile),JCG2Escape(jsonFile)];
        JCG2AppendManifest(manifest);
    }}
    JCG2Log([NSString stringWithFormat:@"BUNDLE-SWEEP origin=%@ bundle=%p names=%lu textassets=%lu",origin?:@"runtime",bundle,(unsigned long)names->max_length,(unsigned long)processed]);
    return processed;
}

static void JCG2SweepNewLoadedBundles(void) {
    if(!JCG2ResolveUnity())return; void *arrayObj=gFindAllBundles(gAssetBundleTypeObject,gFindAllBundlesMethod); JCG2PtrArray *bundles=(JCG2PtrArray *)arrayObj; if(!bundles||bundles->max_length>JCG2_MAX_ARRAY_ITEMS)return;
    NSMutableSet *current=[NSMutableSet setWithCapacity:(NSUInteger)bundles->max_length]; NSUInteger fresh=0;
    for(NSUInteger i=0;i<(NSUInteger)bundles->max_length;i++){@autoreleasepool{void *bundle=bundles->vector[i];if(!bundle)continue;NSString *pk=[NSString stringWithFormat:@"%p",bundle];[current addObject:pk];if(![gKnownLoadedBundles containsObject:pk]){[gKnownLoadedBundles addObject:pk];gBundlesDiscovered++;fresh++;JCG2SweepBundle(bundle,@"runtime-loaded");}}}
    [gKnownLoadedBundles intersectSet:current];
    if(fresh)JCG2Log([NSString stringWithFormat:@"LOADED-DISCOVERY current=%lu new=%lu",(unsigned long)bundles->max_length,(unsigned long)fresh]);
    JCG2WriteStatus();
}

#pragma mark - Disk Bundle discovery / processing

static BOOL JCG2PathShouldSkip(NSString *path) {
    if(!path.length)return YES; NSString *std=path.stringByStandardizingPath;
    if(gRootPath.length&&[std hasPrefix:gRootPath])return YES;
    if([std containsString:@"/Frameworks/"]||[std hasSuffix:@"/UnityFramework"]||[std containsString:@"/_CodeSignature/"])return YES;
    return NO;
}

static BOOL JCG2FileHasUnityMagic(NSString *path) {
    if(JCG2PathShouldSkip(path))return NO; NSFileHandle *h=[NSFileHandle fileHandleForReadingAtPath:path]; if(!h)return NO; NSData *d=nil;
    @try{d=[h readDataOfLength:16];[h closeFile];}@catch(__unused NSException *e){@try{[h closeFile];}@catch(__unused NSException *x){}return NO;}
    if(d.length<7)return NO; const uint8_t *p=d.bytes;
    return (d.length>=7&&memcmp(p,"UnityFS",7)==0)||(d.length>=8&&memcmp(p,"UnityRaw",8)==0)||(d.length>=8&&memcmp(p,"UnityWeb",8)==0);
}

static NSArray *JCG2DiskRoots(void) {
    NSMutableArray *roots=[NSMutableArray array]; NSFileManager *fm=[NSFileManager defaultManager];
    NSString *docs=JCG2Documents(); if(docs.length)[roots addObject:docs];
    NSArray *libs=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES); if(libs.count)[roots addObject:libs[0]];
    NSString *app=[NSBundle mainBundle].bundlePath; if(app.length)[roots addObject:app];
    NSMutableArray *unique=[NSMutableArray array]; for(NSString *p in roots)if([fm fileExistsAtPath:p]&&![unique containsObject:p])[unique addObject:p]; return unique;
}

static NSString *JCG2FileVersion(NSString *path, NSDictionary *attrs) {
    NSNumber *size=attrs[NSFileSize]?:@0; NSDate *date=attrs[NSFileModificationDate]?:[NSDate dateWithTimeIntervalSince1970:0]; return [NSString stringWithFormat:@"%@:%0.f",size,date.timeIntervalSince1970];
}

static void JCG2ProcessDiskBundleOnMain(NSString *path, NSString *version) {
    if(!path.length||!gLoadFromFile)return; void *managed=gStringNew(path.UTF8String); void *bundle=managed?gLoadFromFile(managed,gLoadFromFileMethod):NULL;
    if(!bundle){gDiskBundlesFailed++;JCG2Log([NSString stringWithFormat:@"DISK-BUNDLE-LOAD-FAIL path=%@ version=%@",path,version]);JCG2WriteStatus();return;}
    gDiskBundlesLoaded++; JCG2Log([NSString stringWithFormat:@"DISK-BUNDLE-LOAD-OK path=%@ bundle=%p",path,bundle]); JCG2SweepBundle(bundle,[NSString stringWithFormat:@"disk:%@",path]);
    if(gUnload){@try{gUnload(bundle,YES,gUnloadMethod);}@catch(__unused NSException *e){JCG2Log([NSString stringWithFormat:@"DISK-BUNDLE-UNLOAD-EXCEPTION path=%@",path]);}}
    JCG2WriteStatus();
}

static void JCG2ScanDiskOnce(void) {
    if(gDiskWorkerActive)return; gDiskWorkerActive=YES;
    dispatch_async(gDiskQueue,^{@autoreleasepool{
        NSFileManager *fm=[NSFileManager defaultManager]; unsigned long long filesSeenThisPass=0,candidatesThisPass=0;
        for(NSString *root in JCG2DiskRoots()){@autoreleasepool{
            NSDirectoryEnumerator *en=[fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLFileSizeKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url,NSError *error){JCG2Log([NSString stringWithFormat:@"DISK-ENUM-ERR %@ %@",url.path,error]);return YES;}];
            for(NSURL *url in en){@autoreleasepool{NSNumber *isFile=nil;[url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];if(!isFile.boolValue)continue;NSString *path=url.path;if(JCG2PathShouldSkip(path))continue;filesSeenThisPass++;
                NSDictionary *attrs=[fm attributesOfItemAtPath:path error:nil];NSString *ver=JCG2FileVersion(path,attrs);BOOL changed=NO;
                pthread_mutex_lock(&gDiskLock);NSString *old=gDiskSeenVersions[path];if(!old||![old isEqualToString:ver]){gDiskSeenVersions[path]=ver;changed=YES;}pthread_mutex_unlock(&gDiskLock);
                if(!changed)continue;if(!JCG2FileHasUnityMagic(path))continue;candidatesThisPass++;
                NSString *pathCopy=[path copy];NSString *verCopy=[ver copy];dispatch_async(dispatch_get_main_queue(),^{JCG2ProcessDiskBundleOnMain(pathCopy,verCopy);[pathCopy release];[verCopy release];});
            }}
        }}
        gDiskFilesSeen+=filesSeenThisPass;gDiskBundleCandidates+=candidatesThisPass;gDiskWatchTick++;JCG2Log([NSString stringWithFormat:@"DISK-SCAN tick=%llu files=%llu candidates=%llu",gDiskWatchTick,filesSeenThisPass,candidatesThisPass]);dispatch_async(dispatch_get_main_queue(),^{JCG2WriteStatus();});gDiskWorkerActive=NO;
    }});
}

#pragma mark - Watch loops

static void JCG2ScheduleLoadedWatch(void);
static void JCG2LoadedWatch(void){if(!gRunning)return;@autoreleasepool{gLoadedWatchTick++;JCG2InstallNativeHooks();JCG2SweepNewLoadedBundles();}JCG2ScheduleLoadedWatch();}
static void JCG2ScheduleLoadedWatch(void){if(!gRunning)return;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(JCG2_LOADED_WATCH_SECONDS*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG2LoadedWatch();});}

static void JCG2ScheduleDiskWatch(void);
static void JCG2DiskWatch(void){if(!gRunning)return;JCG2ScanDiskOnce();JCG2ScheduleDiskWatch();}
static void JCG2ScheduleDiskWatch(void){if(!gRunning)return;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(JCG2_DISK_WATCH_SECONDS*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG2DiskWatch();});}

static void JCG2PollNative(NSUInteger attempt){dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{if(JCG2InstallNativeHooks())return;if(attempt<240){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{JCG2PollNative(attempt+1);});}else JCG2Log(@"NATIVE-HOOK timeout; inventory still runs, Lua compile waits for APIs");});}

__attribute__((constructor)) static void JCG2Entry(void){@autoreleasepool{
    JCG2SetupPaths();gIOQueue=dispatch_queue_create("com.openai.jsoncapture.fullsweep.io",DISPATCH_QUEUE_SERIAL);gDiskQueue=dispatch_queue_create("com.openai.jsoncapture.fullsweep.disk",DISPATCH_QUEUE_SERIAL);
    gAttemptedAssets=[[NSMutableSet alloc]init];gKnownLoadedBundles=[[NSMutableSet alloc]init];gLoaderSeenHashes=[[NSMutableSet alloc]init];gDiskSeenVersions=[[NSMutableDictionary alloc]init];gDiskPendingPaths=[[NSMutableSet alloc]init];
    JCG2Log([NSString stringWithFormat:@"%@ loaded profile=%@; NO 5s/100/10 limits; full current bundles + disk UnityFS + new runtime/downloaded bundles; compile-only/no-execute",JCG2_VERSION,JCG2_PROFILE]);
    JCG2PollNative(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG2LoadedWatch();});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG2DiskWatch();});
}}
