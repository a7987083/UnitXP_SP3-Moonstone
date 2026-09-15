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
#define JC42_ENCM_XOR_KEY 0x4D

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
typedef void *(*JC42ClassGetParentFn)(void *klass);
typedef void *(*JC42TypeGetObjectFn)(const void *type);
typedef void *(*JC42StringNewFn)(const char *str);
typedef void *(*JC42ObjectGetClassFn)(void *obj);
typedef int (*JC42ClassIsAssignableFromFn)(void *klass, void *oklass);
typedef void *(*JC42ClassGetFieldFromNameFn)(void *klass, const char *name);
typedef void (*JC42FieldStaticGetValueFn)(void *field, void *value);
typedef void (*JC42FieldGetValueFn)(void *obj, void *field, void *value);

typedef void *(*JC42ResourcesFindAllFn)(void *typeObj, const void *method);
typedef void *(*JC42AssetBundleGetAllNamesFn)(void *self, const void *method);
typedef void *(*JC42AssetBundleLoadAssetFn)(void *self, void *name, void *typeObj, const void *method);
typedef void *(*JC42TextAssetGetBytesFn)(void *self, const void *method);

typedef int (*JC42LuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);
typedef int (*JC42LuaGetTopFn)(void *L);
typedef void (*JC42LuaSetTopFn)(void *L, int idx);

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

static JC42ClassGetFieldFromNameFn gJC42ClassGetFieldFromName;
static JC42FieldStaticGetValueFn gJC42FieldStaticGetValue;
static JC42FieldGetValueFn gJC42FieldGetValue;
static void *gJC42LuaStateClass;
static void *gJC42LuaStatePtrClass;
static void *gJC42MainStateField;
static void *gJC42NativeLField;

static NSString *gJC42RootPath;
static NSString *gJC42LogPath;
static NSMutableSet *gJC42Done;
static NSMutableDictionary *gJC42Retry;
static pthread_mutex_t gJC42LogLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gJC42UnityReady = NO;
static BOOL gJC42LuaMetadataReady = NO;
static BOOL gJC42Running = YES;
static unsigned long long gJC42Ticks = 0;
static unsigned long long gJC42Candidates = 0;
static unsigned long long gJC42Processed = 0;
static unsigned long long gJC42DecodedENCM = 0;
static unsigned long long gJC42DecodedPlain = 0;
static unsigned long long gJC42DecodeFail = 0;
static unsigned long long gJC42CompiledOK = 0;
static unsigned long long gJC42CompileError = 0;
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

static BOOL JC42HasLua53Signature(NSData *data) {
    if (data.length < 6) return NO;
    const uint8_t *p = data.bytes;
    return p[0] == 0x1b && p[1] == 'L' && p[2] == 'u' && p[3] == 'a' && p[4] == 0x53;
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

/*
 * Captured client evidence (JSONCapture(2).zip): all 265 observed TAB TextAssets
 * use ENCM wrapper. For every matched raw/VM-ready pair:
 *   decoded[i] = raw[i + 4] XOR 0x4D
 * and decoded bytes exactly equal the VM-ready Lua 5.3 chunk.
 */
static NSData *JC42DecodeTAB(NSData *raw, BOOL *wasENCM) {
    if (wasENCM) *wasENCM = NO;
    if (!raw.length || raw.length > JC42_MAX_BUFFER) return nil;

    const uint8_t *src = raw.bytes;
    if (raw.length > 4 && memcmp(src, "ENCM", 4) == 0) {
        NSUInteger outLen = raw.length - 4;
        NSMutableData *out = [NSMutableData dataWithLength:outLen];
        uint8_t *dst = out.mutableBytes;
        for (NSUInteger i = 0; i < outLen; i++) dst[i] = src[i + 4] ^ JC42_ENCM_XOR_KEY;
        if (!JC42HasLua53Signature(out) && !JC42LooksLuaText(out)) return nil;
        if (wasENCM) *wasENCM = YES;
        return out;
    }

    if (JC42HasLua53Signature(raw) || JC42LooksLuaText(raw)) return raw;
    return nil;
}

static void JC42WriteStatus(NSUInteger bundleCount, NSUInteger batchCount) {
    JC42SetupPaths();
    NSString *path = [gJC42RootPath stringByAppendingPathComponent:@"TAB_Sweep_v0.4.2.status.json"];
    NSString *luaState = gJC42LuaState ? [NSString stringWithFormat:@"%p", gJC42LuaState] : @"0x0";
    NSString *json = [NSString stringWithFormat:
        @"{\n  \"version\": \"%@\",\n  \"running\": %@,\n  \"interval_seconds\": %.1f,\n  \"batch_size\": %d,\n  \"tick\": %llu,\n  \"loaded_bundles\": %lu,\n  \"last_batch\": %lu,\n  \"candidates_seen\": %llu,\n  \"processed\": %llu,\n  \"decoded_encm\": %llu,\n  \"decoded_plain\": %llu,\n  \"decode_fail\": %llu,\n  \"compiled_ok\": %llu,\n  \"compile_error\": %llu,\n  \"load_fail\": %llu,\n  \"lua_metadata_ready\": %@,\n  \"lua_state\": \"%@\",\n  \"updated_at\": \"%@\"\n}\n",
        JC42Escape(JC42_VERSION), gJC42Running ? @"true" : @"false", JC42_INTERVAL_SECONDS, JC42_BATCH_SIZE,
        gJC42Ticks, (unsigned long)bundleCount, (unsigned long)batchCount, gJC42Candidates, gJC42Processed,
        gJC42DecodedENCM, gJC42DecodedPlain, gJC42DecodeFail, gJC42CompiledOK, gJC42CompileError, gJC42LoadFail,
        gJC42LuaMetadataReady ? @"true" : @"false", JC42Escape(luaState), JC42Escape(JC42Now())];
    [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Runtime resolution

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

/*
 * ToLua reference layout used by this game family:
 * LuaInterface.LuaState has private static mainState;
 * LuaInterface.LuaStatePtr has protected IntPtr L.
 * Resolve both through IL2CPP metadata rather than guessing object offsets.
 */
static BOOL JC42ResolveLuaMetadata(void) {
    if (gJC42LuaMetadataReady) return YES;

    JC42DomainGetFn domainGet = (JC42DomainGetFn)JC42ResolveExport("il2cpp_domain_get");
    JC42DomainGetAssembliesFn assembliesFn = (JC42DomainGetAssembliesFn)JC42ResolveExport("il2cpp_domain_get_assemblies");
    JC42AssemblyGetImageFn imageFn = (JC42AssemblyGetImageFn)JC42ResolveExport("il2cpp_assembly_get_image");
    JC42ClassFromNameFn classFn = (JC42ClassFromNameFn)JC42ResolveExport("il2cpp_class_from_name");
    JC42ClassGetParentFn parentFn = (JC42ClassGetParentFn)JC42ResolveExport("il2cpp_class_get_parent");
    gJC42ClassGetFieldFromName = (JC42ClassGetFieldFromNameFn)JC42ResolveExport("il2cpp_class_get_field_from_name");
    gJC42FieldStaticGetValue = (JC42FieldStaticGetValueFn)JC42ResolveExport("il2cpp_field_static_get_value");
    gJC42FieldGetValue = (JC42FieldGetValueFn)JC42ResolveExport("il2cpp_field_get_value");

    gJC42LuaLLoadBufferX = (JC42LuaLLoadBufferXFn)JC42ResolveExport("luaL_loadbufferx");
    gJC42LuaGetTop = (JC42LuaGetTopFn)JC42ResolveExport("lua_gettop");
    gJC42LuaSetTop = (JC42LuaSetTopFn)JC42ResolveExport("lua_settop");

    if (!domainGet || !assembliesFn || !imageFn || !classFn || !gJC42ClassGetFieldFromName ||
        !gJC42FieldStaticGetValue || !gJC42FieldGetValue || !gJC42LuaLLoadBufferX || !gJC42LuaGetTop || !gJC42LuaSetTop)
        return NO;

    void *domain = domainGet();
    if (!domain) return NO;
    const char *namespaces[] = {"LuaInterface", "LuaFramework", ""};
    for (size_t n = 0; n < sizeof(namespaces)/sizeof(namespaces[0]) && !gJC42LuaStateClass; n++)
        gJC42LuaStateClass = JC42FindClass(assembliesFn, imageFn, classFn, domain, namespaces[n], "LuaState");
    for (size_t n = 0; n < sizeof(namespaces)/sizeof(namespaces[0]) && !gJC42LuaStatePtrClass; n++)
        gJC42LuaStatePtrClass = JC42FindClass(assembliesFn, imageFn, classFn, domain, namespaces[n], "LuaStatePtr");
    if (!gJC42LuaStatePtrClass && gJC42LuaStateClass && parentFn)
        gJC42LuaStatePtrClass = parentFn(gJC42LuaStateClass);
    if (!gJC42LuaStateClass || !gJC42LuaStatePtrClass) return NO;

    gJC42MainStateField = gJC42ClassGetFieldFromName(gJC42LuaStateClass, "mainState");
    gJC42NativeLField = gJC42ClassGetFieldFromName(gJC42LuaStatePtrClass, "L");
    gJC42LuaMetadataReady = gJC42MainStateField && gJC42NativeLField;
    if (gJC42LuaMetadataReady) {
        JC42Log([NSString stringWithFormat:@"LUA-METADATA-READY LuaState=%p LuaStatePtr=%p mainState=%p L=%p luaL_loadbufferx=%p",
                 gJC42LuaStateClass, gJC42LuaStatePtrClass, gJC42MainStateField, gJC42NativeLField, gJC42LuaLLoadBufferX]);
    }
    return gJC42LuaMetadataReady;
}

static BOOL JC42RefreshLuaState(void) {
    if (!JC42ResolveLuaMetadata()) return NO;
    void *managedState = NULL;
    gJC42FieldStaticGetValue(gJC42MainStateField, &managedState);
    if (!managedState) return NO;

    void *nativeL = NULL;
    gJC42FieldGetValue(managedState, gJC42NativeLField, &nativeL);
    if (!nativeL) return NO;
    if (nativeL != gJC42LuaState) {
        gJC42LuaState = nativeL;
        JC42Log([NSString stringWithFormat:@"LUA-STATE-READY managed=%p native=%p", managedState, nativeL]);
    }
    return YES;
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

static int JC42CompileOnly(NSData *decoded, NSString *assetName) {
    if (!decoded.length || !JC42RefreshLuaState()) return -1000;
    if (!JC42HasLua53Signature(decoded) && !JC42LooksLuaText(decoded)) return -1001;

    NSString *leaf = assetName.lastPathComponent.length ? assetName.lastPathComponent : assetName;
    NSString *chunk = [NSString stringWithFormat:@"@sweep_%@", leaf ?: @"TAB_unknown.lua"];
    int oldTop = gJC42LuaGetTop(gJC42LuaState);
    int rc = gJC42LuaLLoadBufferX(gJC42LuaState, (const char *)decoded.bytes, decoded.length, chunk.UTF8String, "bt");
    gJC42LuaSetTop(gJC42LuaState, oldTop);
    return rc;
}

static NSUInteger JC42SweepBatch(void) {
    if (!JC42ResolveUnity()) {
        JC42Log(@"WAIT unity metadata not ready");
        return 0;
    }
    if (!JC42RefreshLuaState()) {
        JC42Log(@"WAIT LuaState.mainState/L not ready");
        JC42WriteStatus(0, 0);
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
            NSData *raw = JC42DataFromByteArray(bytesObj);
            if (!raw.length) {
                NSUInteger n = retry ? retry.unsignedIntegerValue + 1 : 1;
                [gJC42Retry setObject:[NSNumber numberWithUnsignedInteger:n] forKey:key];
                gJC42LoadFail++;
                JC42Log([NSString stringWithFormat:@"TAB-BYTES-FAIL retry=%lu/%d asset=%@", (unsigned long)n, JC42_MAX_RETRY, assetName]);
                continue;
            }

            BOOL wasENCM = NO;
            NSData *decoded = JC42DecodeTAB(raw, &wasENCM);
            if (!decoded.length) {
                gJC42DecodeFail++;
                [gJC42Done addObject:key];
                JC42Log([NSString stringWithFormat:@"TAB-DECODE-FAIL asset=%@ bytes=%lu head=%02x%02x%02x%02x",
                         assetName, (unsigned long)raw.length,
                         raw.length > 0 ? ((const uint8_t *)raw.bytes)[0] : 0,
                         raw.length > 1 ? ((const uint8_t *)raw.bytes)[1] : 0,
                         raw.length > 2 ? ((const uint8_t *)raw.bytes)[2] : 0,
                         raw.length > 3 ? ((const uint8_t *)raw.bytes)[3] : 0]);
                continue;
            }

            if (wasENCM) gJC42DecodedENCM++; else gJC42DecodedPlain++;
            JC42Log([NSString stringWithFormat:@"TAB-DECODE-OK mode=%@ asset=%@ raw=%lu decoded=%lu",
                     wasENCM ? @"ENCM-XOR4D" : @"plain", assetName,
                     (unsigned long)raw.length, (unsigned long)decoded.length]);

            int rc = JC42CompileOnly(decoded, assetName);
            if (rc == -1000) {
                NSUInteger n = retry ? retry.unsignedIntegerValue + 1 : 1;
                [gJC42Retry setObject:[NSNumber numberWithUnsignedInteger:n] forKey:key];
                JC42Log([NSString stringWithFormat:@"TAB-COMPILE-WAIT retry=%lu/%d asset=%@", (unsigned long)n, JC42_MAX_RETRY, assetName]);
                continue;
            }

            [gJC42Done addObject:key];
            [gJC42Retry removeObjectForKey:key];
            gJC42Processed++;
            if (rc == 0) {
                gJC42CompiledOK++;
                JC42Log([NSString stringWithFormat:@"TAB-COMPILE-OK asset=%@ decoded=%lu", assetName, (unsigned long)decoded.length]);
            } else {
                gJC42CompileError++;
                JC42Log([NSString stringWithFormat:@"TAB-COMPILE-ERR rc=%d asset=%@ decoded=%lu", rc, assetName, (unsigned long)decoded.length]);
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
        NSUInteger batch = JC42SweepBatch();
        JC42Log([NSString stringWithFormat:@"TICK #%llu batch=%lu done=%lu lua=%p unity=%d luaMeta=%d",
                 gJC42Ticks, (unsigned long)batch, (unsigned long)gJC42Done.count, gJC42LuaState,
                 gJC42UnityReady, gJC42LuaMetadataReady]);
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
        JC42Log([NSString stringWithFormat:@"%@ loaded; TAB-only batch=%d interval=%.1fs; ENCM decode + compile-only/no-execute",
                 JC42_VERSION, JC42_BATCH_SIZE, JC42_INTERVAL_SECONDS]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ JC42Tick(); });
    }
}
