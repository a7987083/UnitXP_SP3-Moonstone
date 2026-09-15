#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#define JC42_VERSION @"JSONCapture TAB Sweep v0.4.2"
#define JC42_BATCH_SIZE 10
#define JC42_INTERVAL_SECONDS 5.0
#define JC42_MAX_BUFFER (64ULL * 1024ULL * 1024ULL)
#define JC42_MAX_ARRAY_ITEMS 200000
#define JC42_MAX_RETRY 3

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} JC42Il2CppString;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    void *vector[0];
} JC42PtrArray;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    uint8_t vector[0];
} JC42ByteArray;

typedef void *(*JC42DomainGetFn)(void);
typedef const void **(*JC42DomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JC42AssemblyGetImageFn)(const void *assembly);
typedef void *(*JC42ClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JC42ClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);
typedef const void *(*JC42ClassGetTypeFn)(void *klass);
typedef void *(*JC42TypeGetObjectFn)(const void *type);
typedef void *(*JC42StringNewFn)(const char *str);
typedef void *(*JC42ObjectGetClassFn)(void *obj);
typedef int (*JC42ClassIsAssignableFromFn)(void *klass, void *oklass);

typedef void *(*JC42ResourcesFindAllFn)(void *typeObj, const void *method);
typedef void *(*JC42AssetBundleGetAllNamesFn)(void *self, const void *method);
typedef void *(*JC42AssetBundleLoadAssetFn)(void *self, void *name, void *typeObj, const void *method);
typedef void *(*JC42TextAssetGetBytesFn)(void *self, const void *method);

typedef int (*JC42LuaLoadFn)(void *L, void *reader, void *data, const char *chunkname, const char *mode);
typedef int (*JC42LuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);
typedef int (*JC42LuaGetTopFn)(void *L);
typedef void (*JC42LuaSetTopFn)(void *L, int idx);

typedef void (*JC42MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JC42DobbyHookFn)(void *address, void *replace, void **origin);

static JC42LuaLoadFn gJC42OrigLuaLoad;
static JC42LuaLLoadBufferXFn gJC42LuaLLoadBufferX;
static JC42LuaGetTopFn gJC42LuaGetTop;
static JC42LuaSetTopFn gJC42LuaSetTop;
static void *gJC42LuaState;

static JC42ResourcesFindAllFn gJC42FindAllBundles;
static const void *gJC42FindAllBundlesMethod;
static JC42AssetBundleGetAllNamesFn gJC42GetAllAssetNames;
static const void *gJC42GetAllAssetNamesMethod;
static JC42AssetBundleLoadAssetFn gJC42LoadAsset;
static const void *gJC42LoadAssetMethod;
static JC42TextAssetGetBytesFn gJC42TextAssetGetBytes;
static const void *gJC42TextAssetGetBytesMethod;
static void *gJC42AssetBundleTypeObject;
static void *gJC42TextAssetTypeObject;
static void *gJC42TextAssetClass;
static JC42StringNewFn gJC42StringNew;
static JC42ObjectGetClassFn gJC42ObjectGetClass;
static JC42ClassIsAssignableFromFn gJC42ClassIsAssignableFrom;

static NSString *gJC42RootPath;
static NSString *gJC42LogPath;
static NSMutableSet *gJC42Done;
static NSMutableDictionary *gJC42Retry;
static pthread_mutex_t gJC42LogLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gJC42LuaTapAttempted = NO;
static BOOL gJC42UnityReady = NO;
static BOOL gJC42Running = YES;
static unsigned long long gJC42Ticks = 0;
static unsigned long long gJC42Candidates = 0;
static unsigned long long gJC42Processed = 0;
static unsigned long long gJC42CompiledOK = 0;
static unsigned long long gJC42CompileError = 0;
static unsigned long long gJC42RawOnly = 0;
static unsigned long long gJC42LoadFail = 0;

#pragma mark - Helpers

static NSString *JC42Now(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JC42Documents(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JC42SetupPaths(void) {
    if (gJC42RootPath.length) return;
    gJC42RootPath = [[[JC42Documents() stringByAppendingPathComponent:@"JSONCapture"] stringByStandardizingPath] retain];
    gJC42LogPath = [[gJC42RootPath stringByAppendingPathComponent:@"TAB_Sweep_v0.4.2.log"] retain];
    [[NSFileManager defaultManager] createDirectoryAtPath:gJC42RootPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void JC42Log(NSString *text) {
    if (!text.length) return;
    JC42SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", JC42Now(), text];
    pthread_mutex_lock(&gJC42LogLock);
    FILE *f = fopen(gJC42LogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJC42LogLock);
}

static NSString *JC42Escape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithString:s];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static NSString *JC42StringFromManaged(void *ptr) {
    if (!ptr) return nil;
    JC42Il2CppString *s = (JC42Il2CppString *)ptr;
    if (s->length <= 0 || s->length > (4 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)s->length] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static BOOL JC42IsTABName(NSString *name) {
    if (!name.length) return NO;
    return [name rangeOfString:@"TAB_" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSInteger JC42Lua53Offset(NSData *data) {
    if (data.length < 6) return NSNotFound;
    const uint8_t *p = data.bytes;
    NSUInteger limit = MIN((NSUInteger)64, data.length - 5);
    for (NSUInteger i = 0; i <= limit; i++) {
        if (p[i] == 0x1b && p[i + 1] == 'L' && p[i + 2] == 'u' && p[i + 3] == 'a' && p[i + 4] == 0x53)
            return (NSInteger)i;
    }
    return NSNotFound;
}

static BOOL JC42LooksLuaText(NSData *data) {
    if (!data.length) return NO;
    NSUInteger n = MIN((NSUInteger)8192, data.length);
    const uint8_t *p = data.bytes;
    NSUInteger bad = 0;
    for (NSUInteger i = 0; i < n; i++) {
        uint8_t c = p[i];
        if (c == 0) return NO;
        if (c < 0x09 || (c > 0x0d && c < 0x20)) bad++;
    }
    if (bad * 50 > n) return NO;
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, n)]
                                         encoding:NSUTF8StringEncoding] autorelease];
    return s != nil;
}

static void JC42WriteStatus(NSUInteger bundleCount, NSUInteger batchCount) {
    JC42SetupPaths();
    NSString *path = [gJC42RootPath stringByAppendingPathComponent:@"TAB_Sweep_v0.4.2.status.json"];
    NSString *luaState = gJC42LuaState ? [NSString stringWithFormat:@"%p", gJC42LuaState] : @"0x0";
    NSString *json = [NSString stringWithFormat:
        @"{\n  \"version\": \"%@\",\n  \"running\": %@,\n  \"interval_seconds\": %.1f,\n  \"batch_size\": %d,\n  \"tick\": %llu,\n  \"loaded_bundles\": %lu,\n  \"last_batch\": %lu,\n  \"candidates_seen\": %llu,\n  \"processed\": %llu,\n  \"compiled_ok\": %llu,\n  \"compile_error\": %llu,\n  \"raw_only\": %llu,\n  \"load_fail\": %llu,\n  \"lua_state\": \"%@\",\n  \"updated_at\": \"%@\"\n}\n",
        JC42Escape(JC42_VERSION), gJC42Running ? @"true" : @"false", JC42_INTERVAL_SECONDS, JC42_BATCH_SIZE,
        gJC42Ticks, (unsigned long)bundleCount, (unsigned long)batchCount, gJC42Candidates, gJC42Processed,
        gJC42CompiledOK, gJC42CompileError, gJC42RawOnly, gJC42LoadFail, JC42Escape(luaState), JC42Escape(JC42Now())];
    [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Runtime resolution / hook backend

static void *JC42ResolveExport(const char *name) {
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

static void *JC42ResolveHookSymbol(const char *symbol) {
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

static BOOL JC42Hook(void *address, void *replacement, void **original, NSString **apiOut) {
    if (!address) return NO;
    JC42MSHookFunctionFn ms = (JC42MSHookFunctionFn)JC42ResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (apiOut) *apiOut = @"MSHookFunction";
            return YES;
        }
    }
    JC42DobbyHookFn dobby = (JC42DobbyHookFn)JC42ResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (apiOut) *apiOut = @"DobbyHook";
            return YES;
        }
    }
    return NO;
}

static void *JC42MethodPointer(const void *methodInfo) {
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

#pragma mark - Lua state tap

static int JC42HookLuaLoad(void *L, void *reader, void *data, const char *chunkname, const char *mode) {
    if (L) gJC42LuaState = L;
    return gJC42OrigLuaLoad ? gJC42OrigLuaLoad(L, reader, data, chunkname, mode) : -1;
}

static void JC42InstallLuaTap(void) {
    if (gJC42LuaTapAttempted) return;
    gJC42LuaTapAttempted = YES;

    void *pLuaLoad = JC42ResolveExport("lua_load");
    gJC42LuaLLoadBufferX = (JC42LuaLLoadBufferXFn)JC42ResolveExport("luaL_loadbufferx");
    gJC42LuaGetTop = (JC42LuaGetTopFn)JC42ResolveExport("lua_gettop");
    gJC42LuaSetTop = (JC42LuaSetTopFn)JC42ResolveExport("lua_settop");

    NSString *api = nil;
    BOOL hooked = pLuaLoad ? JC42Hook(pLuaLoad, (void *)JC42HookLuaLoad, (void **)&gJC42OrigLuaLoad, &api) : NO;
    JC42Log([NSString stringWithFormat:@"LUA-TAP hooked=%d api=%@ lua_load=%p luaL_loadbufferx=%p lua_gettop=%p lua_settop=%p",
             hooked, api ?: @"none", pLuaLoad, gJC42LuaLLoadBufferX, gJC42LuaGetTop, gJC42LuaSetTop]);
}

#pragma mark - Unity API resolution

static void *JC42FindClass(JC42DomainGetAssembliesFn assembliesFn,
                           JC42AssemblyGetImageFn imageFn,
                           JC42ClassFromNameFn classFn,
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

static BOOL JC42ResolveUnity(void) {
    if (gJC42UnityReady) return YES;

    JC42DomainGetFn domainGet = (JC42DomainGetFn)JC42ResolveExport("il2cpp_domain_get");
    JC42DomainGetAssembliesFn assembliesFn = (JC42DomainGetAssembliesFn)JC42ResolveExport("il2cpp_domain_get_assemblies");
    JC42AssemblyGetImageFn imageFn = (JC42AssemblyGetImageFn)JC42ResolveExport("il2cpp_assembly_get_image");
    JC42ClassFromNameFn classFn = (JC42ClassFromNameFn)JC42ResolveExport("il2cpp_class_from_name");
    JC42ClassGetMethodFromNameFn methodFn = (JC42ClassGetMethodFromNameFn)JC42ResolveExport("il2cpp_class_get_method_from_name");
    JC42ClassGetTypeFn classGetType = (JC42ClassGetTypeFn)JC42ResolveExport("il2cpp_class_get_type");
    JC42TypeGetObjectFn typeGetObject = (JC42TypeGetObjectFn)JC42ResolveExport("il2cpp_type_get_object");
    gJC42StringNew = (JC42StringNewFn)JC42ResolveExport("il2cpp_string_new");
    gJC42ObjectGetClass = (JC42ObjectGetClassFn)JC42ResolveExport("il2cpp_object_get_class");
    gJC42ClassIsAssignableFrom = (JC42ClassIsAssignableFromFn)JC42ResolveExport("il2cpp_class_is_assignable_from");

    if (!domainGet || !assembliesFn || !imageFn || !classFn || !methodFn || !classGetType || !typeGetObject || !gJC42StringNew)
        return NO;
    void *domain = domainGet();
    if (!domain) return NO;

    void *resourcesClass = JC42FindClass(assembliesFn, imageFn, classFn, domain, "UnityEngine", "Resources");
    void *bundleClass = JC42FindClass(assembliesFn, imageFn, classFn, domain, "UnityEngine", "AssetBundle");
    gJC42TextAssetClass = JC42FindClass(assembliesFn, imageFn, classFn, domain, "UnityEngine", "TextAsset");
    if (!resourcesClass || !bundleClass || !gJC42TextAssetClass) return NO;

    gJC42FindAllBundlesMethod = methodFn(resourcesClass, "FindObjectsOfTypeAll", 1);
    gJC42GetAllAssetNamesMethod = methodFn(bundleClass, "GetAllAssetNames", 0);
    gJC42LoadAssetMethod = methodFn(bundleClass, "LoadAsset", 2);
    gJC42TextAssetGetBytesMethod = methodFn(gJC42TextAssetClass, "get_bytes", 0);

    gJC42FindAllBundles = (JC42ResourcesFindAllFn)JC42MethodPointer(gJC42FindAllBundlesMethod);
    gJC42GetAllAssetNames = (JC42AssetBundleGetAllNamesFn)JC42MethodPointer(gJC42GetAllAssetNamesMethod);
    gJC42LoadAsset = (JC42AssetBundleLoadAssetFn)JC42MethodPointer(gJC42LoadAssetMethod);
    gJC42TextAssetGetBytes = (JC42TextAssetGetBytesFn)JC42MethodPointer(gJC42TextAssetGetBytesMethod);

    const void *bundleType = classGetType(bundleClass);
    const void *textType = classGetType(gJC42TextAssetClass);
    gJC42AssetBundleTypeObject = bundleType ? typeGetObject(bundleType) : NULL;
    gJC42TextAssetTypeObject = textType ? typeGetObject(textType) : NULL;

    gJC42UnityReady = gJC42FindAllBundles && gJC42GetAllAssetNames && gJC42LoadAsset && gJC42TextAssetGetBytes &&
                      gJC42AssetBundleTypeObject && gJC42TextAssetTypeObject;
    if (gJC42UnityReady) {
        JC42Log([NSString stringWithFormat:@"UNITY-READY FindObjectsOfTypeAll=%p GetAllAssetNames=%p LoadAsset/2=%p TextAsset.get_bytes=%p",
                 gJC42FindAllBundles, gJC42GetAllAssetNames, gJC42LoadAsset, gJC42TextAssetGetBytes]);
    }
    return gJC42UnityReady;
}

#pragma mark - Sweep

static BOOL JC42ObjectIsTextAsset(void *obj) {
    if (!obj || !gJC42TextAssetClass) return NO;
    if (!gJC42ObjectGetClass || !gJC42ClassIsAssignableFrom) return YES;
    void *klass = gJC42ObjectGetClass(obj);
    return klass ? (gJC42ClassIsAssignableFrom(gJC42TextAssetClass, klass) != 0) : NO;
}

static NSData *JC42DataFromByteArray(void *ptr) {
    if (!ptr) return nil;
    JC42ByteArray *a = (JC42ByteArray *)ptr;
    if (!a->max_length || a->max_length > JC42_MAX_BUFFER) return nil;
    @try {
        return [NSData dataWithBytes:a->vector length:(NSUInteger)a->max_length];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static int JC42CompileOnly(NSData *data, NSString *assetName) {
    if (!data.length || !gJC42LuaState || !gJC42LuaLLoadBufferX || !gJC42LuaGetTop || !gJC42LuaSetTop) return -1000;

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSInteger off = JC42Lua53Offset(data);
    if (off != NSNotFound) {
        bytes += off;
        length -= (NSUInteger)off;
    } else if (!JC42LooksLuaText(data)) {
        return -1001;
    }

    const char *name = assetName.length ? assetName.UTF8String : "@TAB_Sweep.lua";
    int oldTop = gJC42LuaGetTop(gJC42LuaState);
    int rc = gJC42LuaLLoadBufferX(gJC42LuaState, (const char *)bytes, length, name, "bt");
    gJC42LuaSetTop(gJC42LuaState, oldTop);
    return rc;
}

static NSUInteger JC42SweepBatch(void) {
    if (!JC42ResolveUnity()) {
        JC42Log(@"WAIT unity metadata not ready");
        return 0;
    }

    void *arrayObj = gJC42FindAllBundles(gJC42AssetBundleTypeObject, gJC42FindAllBundlesMethod);
    JC42PtrArray *bundles = (JC42PtrArray *)arrayObj;
    if (!bundles || bundles->max_length > JC42_MAX_ARRAY_ITEMS) {
        JC42WriteStatus(0, 0);
        return 0;
    }

    NSUInteger bundleCount = (NSUInteger)bundles->max_length;
    NSUInteger batch = 0;

    for (NSUInteger bi = 0; bi < bundleCount && batch < JC42_BATCH_SIZE; bi++) {
        void *bundle = bundles->vector[bi];
        if (!bundle) continue;

        void *namesObj = gJC42GetAllAssetNames(bundle, gJC42GetAllAssetNamesMethod);
        JC42PtrArray *names = (JC42PtrArray *)namesObj;
        if (!names || names->max_length > JC42_MAX_ARRAY_ITEMS) continue;

        for (NSUInteger ni = 0; ni < (NSUInteger)names->max_length && batch < JC42_BATCH_SIZE; ni++) {
            NSString *assetName = JC42StringFromManaged(names->vector[ni]);
            if (!JC42IsTABName(assetName)) continue;
            gJC42Candidates++;

            NSString *key = assetName.lowercaseString;
            if ([gJC42Done containsObject:key]) continue;
            NSNumber *retry = [gJC42Retry objectForKey:key];
            if (retry.unsignedIntegerValue >= JC42_MAX_RETRY) continue;

            batch++;
            void *managedName = gJC42StringNew(assetName.UTF8String);
            void *asset = managedName ? gJC42LoadAsset(bundle, managedName, gJC42TextAssetTypeObject, gJC42LoadAssetMethod) : NULL;
            if (!asset || !JC42ObjectIsTextAsset(asset)) {
                NSUInteger n = retry ? retry.unsignedIntegerValue + 1 : 1;
                [gJC42Retry setObject:[NSNumber numberWithUnsignedInteger:n] forKey:key];
                gJC42LoadFail++;
                JC42Log([NSString stringWithFormat:@"TAB-LOAD-FAIL retry=%lu/%d asset=%@", (unsigned long)n, JC42_MAX_RETRY, assetName]);
                continue;
            }

            void *bytesObj = gJC42TextAssetGetBytes(asset, gJC42TextAssetGetBytesMethod);
            NSData *data = JC42DataFromByteArray(bytesObj);
            if (!data.length) {
                NSUInteger n = retry ? retry.unsignedIntegerValue + 1 : 1;
                [gJC42Retry setObject:[NSNumber numberWithUnsignedInteger:n] forKey:key];
                gJC42LoadFail++;
                JC42Log([NSString stringWithFormat:@"TAB-BYTES-FAIL retry=%lu/%d asset=%@", (unsigned long)n, JC42_MAX_RETRY, assetName]);
                continue;
            }

            int rc = JC42CompileOnly(data, assetName);
            [gJC42Done addObject:key];
            [gJC42Retry removeObjectForKey:key];
            gJC42Processed++;
            if (rc == 0) {
                gJC42CompiledOK++;
                JC42Log([NSString stringWithFormat:@"TAB-COMPILE-OK asset=%@ bytes=%lu", assetName, (unsigned long)data.length]);
            } else if (rc == -1000 || rc == -1001) {
                gJC42RawOnly++;
                JC42Log([NSString stringWithFormat:@"TAB-RAW-ONLY rc=%d asset=%@ bytes=%lu", rc, assetName, (unsigned long)data.length]);
            } else {
                gJC42CompileError++;
                JC42Log([NSString stringWithFormat:@"TAB-COMPILE-ERR rc=%d asset=%@ bytes=%lu", rc, assetName, (unsigned long)data.length]);
            }
        }
    }

    JC42WriteStatus(bundleCount, batch);
    return batch;
}

static void JC42ScheduleNext(void);

static void JC42Tick(void) {
    if (!gJC42Running) return;
    @autoreleasepool {
        gJC42Ticks++;
        JC42InstallLuaTap();
        NSUInteger batch = JC42SweepBatch();
        JC42Log([NSString stringWithFormat:@"TICK #%llu batch=%lu done=%lu lua=%p unity=%d",
                 gJC42Ticks, (unsigned long)batch, (unsigned long)gJC42Done.count, gJC42LuaState, gJC42UnityReady]);
    }
    JC42ScheduleNext();
}

static void JC42ScheduleNext(void) {
    if (!gJC42Running) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(JC42_INTERVAL_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ JC42Tick(); });
}

__attribute__((constructor)) static void JC42Entry(void) {
    @autoreleasepool {
        JC42SetupPaths();
        gJC42Done = [[NSMutableSet alloc] init];
        gJC42Retry = [[NSMutableDictionary alloc] init];
        JC42Log([NSString stringWithFormat:@"%@ loaded; TAB-only batch=%d interval=%.1fs; compile-only/no-pcall", JC42_VERSION, JC42_BATCH_SIZE, JC42_INTERVAL_SECONDS]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ JC42Tick(); });
    }
}
