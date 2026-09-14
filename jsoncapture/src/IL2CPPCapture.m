#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#import "Lua53Analyzer.h"

#define JC2_VERSION @"JSONCapture IL2CPP v0.4"
#define JC2_MAX_TEXTASSET_BYTES (64ULL * 1024ULL * 1024ULL)
#define JC2_POLL_MAX 240

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} JC2Il2CppString;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    uint8_t vector[0];
} JC2Il2CppArray;

typedef void *(*JC2DomainGetFn)(void);
typedef const void **(*JC2DomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JC2AssemblyGetImageFn)(const void *assembly);
typedef const char *(*JC2ImageGetNameFn)(const void *image);
typedef void *(*JC2ClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JC2ClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);

typedef void *(*JC2TextAssetGetterFn)(void *self, const void *method);
typedef void *(*JC2ObjectGetNameFn)(void *self, const void *method);
typedef void *(*JC2LoadAssetFn)(void *self, void *name, void *type, const void *method);

typedef void (*JC2MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JC2DobbyHookFn)(void *address, void *replace, void **origin);

static JC2TextAssetGetterFn gJC2OrigTextAssetGetText;
static JC2TextAssetGetterFn gJC2OrigTextAssetGetBytes;
static JC2ObjectGetNameFn gJC2ObjectGetName;
static const void *gJC2ObjectGetNameMethod;
static JC2LoadAssetFn gJC2OrigLoadAsset;
static JC2LoadAssetFn gJC2OrigLoadAssetAsync;

static dispatch_queue_t gJC2Queue;
static NSMutableSet *gJC2SeenHashes;
static NSString *gJC2RootPath;
static NSString *gJC2LogPath;
static unsigned long long gJC2Seq = 0;
static pthread_mutex_t gJC2LogLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gJC2Installed = NO;

#pragma mark - Paths / logging

static NSString *JC2NowText(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JC2DocumentsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JC2EnsureDirectory(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void JC2SetupPaths(void) {
    if (gJC2RootPath.length) return;
    gJC2RootPath = [[[JC2DocumentsPath() stringByAppendingPathComponent:@"JSONCapture"] stringByStandardizingPath] retain];
    gJC2LogPath = [[gJC2RootPath stringByAppendingPathComponent:@"IL2CPP_v0.4.log"] retain];
    JC2EnsureDirectory(gJC2RootPath);
    JC2EnsureDirectory([gJC2RootPath stringByAppendingPathComponent:@"textasset"]);
    JC2EnsureDirectory([gJC2RootPath stringByAppendingPathComponent:@"assetbundle"]);
    JC2EnsureDirectory([gJC2RootPath stringByAppendingPathComponent:@"lua53_analysis"]);
}

static void JC2Log(NSString *text) {
    if (!text.length) return;
    JC2SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", JC2NowText(), text];
    pthread_mutex_lock(&gJC2LogLock);
    FILE *f = fopen(gJC2LogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJC2LogLock);
}

static NSString *JC2SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JC2SafeName(NSString *text) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, 96)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."];
    for (NSUInteger i = 0; i < text.length && out.length < 96; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c];
        else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

#pragma mark - Managed object helpers

static NSString *JC2NSStringFromIl2CppString(void *ptr) {
    if (!ptr) return nil;
    JC2Il2CppString *s = (JC2Il2CppString *)ptr;
    int32_t len = s->length;
    if (len <= 0 || len > (32 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)len] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSData *JC2DataFromByteArray(void *ptr) {
    if (!ptr) return nil;
    JC2Il2CppArray *a = (JC2Il2CppArray *)ptr;
    uintptr_t len = a->max_length;
    if (!len || len > JC2_MAX_TEXTASSET_BYTES) return nil;
    @try {
        return [NSData dataWithBytes:a->vector length:(NSUInteger)len];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *JC2TextAssetName(void *self) {
    if (!self || !gJC2ObjectGetName) return @"unnamed";
    @try {
        void *s = gJC2ObjectGetName(self, gJC2ObjectGetNameMethod);
        NSString *name = JC2NSStringFromIl2CppString(s);
        return name.length ? name : @"unnamed";
    } @catch (__unused NSException *e) {
        return @"unnamed";
    }
}

#pragma mark - Classification / capture

static BOOL JC2LooksJSON(NSData *data) {
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

static BOOL JC2LooksText(NSData *data) {
    if (!data.length) return NO;
    NSUInteger sample = MIN((NSUInteger)8192, data.length);
    const uint8_t *p = data.bytes;
    NSUInteger bad = 0;
    for (NSUInteger i = 0; i < sample; i++) {
        uint8_t c = p[i];
        if (c == 0) return NO;
        if (c < 0x09 || (c > 0x0D && c < 0x20)) bad++;
    }
    if (bad * 20 > sample) return NO;
    NSString *s = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, sample)]
                                         encoding:NSUTF8StringEncoding] autorelease];
    return s != nil;
}

static NSString *JC2FormatForData(NSData *data, NSString *assetName) {
    if (JC2LooksJSON(data)) return @"json";
    NSInteger luaOff = JC4FindLua53SignatureOffset(data);
    if (luaOff == 0) return @"luac";
    if (luaOff != NSNotFound) return @"luacwrap";
    const uint8_t *p = data.bytes;
    if (data.length >= 7 && memcmp(p, "UnityFS", 7) == 0) return @"bundle";
    if (JC2LooksText(data)) {
        NSString *lower = assetName.lowercaseString;
        if ([lower containsString:@"lua"] || [lower hasSuffix:@".lua"]) return @"lua";
        return @"txt";
    }
    return @"bin";
}

static NSString *JC2JSONStringEscape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithString:s];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static void JC2CaptureData(NSData *data, NSString *source, NSString *assetName) {
    if (!data.length || data.length > JC2_MAX_TEXTASSET_BYTES) return;
    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = source.length ? [NSString stringWithString:source] : @"textasset";
    NSString *name = assetName.length ? [NSString stringWithString:assetName] : @"unnamed";
    dispatch_async(gJC2Queue, ^{
        @autoreleasepool {
            NSString *hash = JC2SHA256(snapshot);
            if (!hash.length) return;
            if ([gJC2SeenHashes containsObject:hash]) return;
            [gJC2SeenHashes addObject:hash];

            unsigned long long idx = ++gJC2Seq;
            NSString *fmt = JC2FormatForData(snapshot, name);
            NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
            NSString *base = [NSString stringWithFormat:@"%06llu_%@_%@_%@", idx, JC2SafeName(src), JC2SafeName(name), shortHash];
            NSString *dir = [gJC2RootPath stringByAppendingPathComponent:@"textasset"];
            NSString *dataPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", base, fmt]];
            NSString *metaPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".meta.json"]];

            NSError *err = nil;
            if (![snapshot writeToFile:dataPath options:NSDataWritingAtomic error:&err]) {
                JC2Log([NSString stringWithFormat:@"WRITE-FAIL source=%@ asset=%@ err=%@", src, name, err]);
                return;
            }

            NSString *meta = [NSString stringWithFormat:
                @"{\n  \"version\": \"%@\",\n  \"source\": \"%@\",\n  \"asset\": \"%@\",\n  \"bytes\": %lu,\n  \"sha256\": \"%@\",\n  \"format\": \"%@\",\n  \"captured_at\": \"%@\",\n  \"file\": \"%@\"\n}\n",
                JC2JSONStringEscape(JC2_VERSION), JC2JSONStringEscape(src), JC2JSONStringEscape(name),
                (unsigned long)snapshot.length, hash, fmt, JC2JSONStringEscape(JC2NowText()), JC2JSONStringEscape(dataPath.lastPathComponent)];
            [meta writeToFile:metaPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            JC2Log([NSString stringWithFormat:@"CAPTURE #%llu source=%@ asset=%@ bytes=%lu format=%@ sha256=%@ file=%@",
                    idx, src, name, (unsigned long)snapshot.length, fmt, hash, dataPath.lastPathComponent]);

            NSInteger luaOff = JC4FindLua53SignatureOffset(snapshot);
            if (luaOff != NSNotFound) {
                JC2Log([NSString stringWithFormat:@"LUA53-DETECTED asset=%@ signature_offset=%ld source=%@", name, (long)luaOff, src]);
                JC4AnalyzeLua53Data(snapshot, src, name, gJC2RootPath);
            }
        }
    });
}

static void JC2LogAssetRequest(NSString *api, NSString *name) {
    if (!name.length) name = @"unnamed";
    JC2Log([NSString stringWithFormat:@"ASSET-REQUEST api=%@ name=%@", api ?: @"?", name]);
    dispatch_async(gJC2Queue, ^{
        NSString *path = [[gJC2RootPath stringByAppendingPathComponent:@"assetbundle"] stringByAppendingPathComponent:@"LoadAsset.jsonl"];
        NSString *line = [NSString stringWithFormat:@"{\"time\":\"%@\",\"api\":\"%@\",\"name\":\"%@\"}\n",
                          JC2JSONStringEscape(JC2NowText()), JC2JSONStringEscape(api ?: @""), JC2JSONStringEscape(name)];
        FILE *f = fopen(path.fileSystemRepresentation, "a");
        if (f) {
            NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
            fwrite(d.bytes, 1, d.length, f);
            fclose(f);
        }
    });
}

#pragma mark - Hooks

static void *JC2HookTextAssetGetText(void *self, const void *method) {
    void *ret = gJC2OrigTextAssetGetText ? gJC2OrigTextAssetGetText(self, method) : NULL;
    NSString *text = JC2NSStringFromIl2CppString(ret);
    if (text.length) {
        NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
        JC2CaptureData(d, @"textasset-get_text", JC2TextAssetName(self));
    }
    return ret;
}

static void *JC2HookTextAssetGetBytes(void *self, const void *method) {
    void *ret = gJC2OrigTextAssetGetBytes ? gJC2OrigTextAssetGetBytes(self, method) : NULL;
    NSData *d = JC2DataFromByteArray(ret);
    if (d.length) JC2CaptureData(d, @"textasset-get_bytes", JC2TextAssetName(self));
    return ret;
}

static void *JC2HookLoadAsset(void *self, void *name, void *type, const void *method) {
    NSString *assetName = JC2NSStringFromIl2CppString(name);
    JC2LogAssetRequest(@"AssetBundle::LoadAsset", assetName);
    return gJC2OrigLoadAsset ? gJC2OrigLoadAsset(self, name, type, method) : NULL;
}

static void *JC2HookLoadAssetAsync(void *self, void *name, void *type, const void *method) {
    NSString *assetName = JC2NSStringFromIl2CppString(name);
    JC2LogAssetRequest(@"AssetBundle::LoadAssetAsync", assetName);
    return gJC2OrigLoadAssetAsync ? gJC2OrigLoadAssetAsync(self, name, type, method) : NULL;
}

#pragma mark - Hook backend

static void *JC2ResolveHookSymbol(const char *symbol) {
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

static BOOL JC2HookAddress(void *address, void *replacement, void **original, NSString **apiOut) {
    if (!address) return NO;
    JC2MSHookFunctionFn ms = (JC2MSHookFunctionFn)JC2ResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (apiOut) *apiOut = @"MSHookFunction";
            return YES;
        }
    }
    JC2DobbyHookFn dobby = (JC2DobbyHookFn)JC2ResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (apiOut) *apiOut = @"DobbyHook";
            return YES;
        }
    }
    return NO;
}

static void *JC2ResolveExport(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    const char *paths[] = {
        "@rpath/UnityFramework.framework/UnityFramework",
        "UnityFramework.framework/UnityFramework"
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        void *h = dlopen(paths[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, name);
        if (p) return p;
    }
    return NULL;
}

static void *JC2MethodPointer(const void *methodInfo) {
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

#pragma mark - IL2CPP resolution

static BOOL JC2InstallIL2CPPHooks(void) {
    if (gJC2Installed) return YES;

    JC2DomainGetFn domainGet = (JC2DomainGetFn)JC2ResolveExport("il2cpp_domain_get");
    JC2DomainGetAssembliesFn domainGetAssemblies = (JC2DomainGetAssembliesFn)JC2ResolveExport("il2cpp_domain_get_assemblies");
    JC2AssemblyGetImageFn assemblyGetImage = (JC2AssemblyGetImageFn)JC2ResolveExport("il2cpp_assembly_get_image");
    JC2ImageGetNameFn imageGetName = (JC2ImageGetNameFn)JC2ResolveExport("il2cpp_image_get_name");
    JC2ClassFromNameFn classFromName = (JC2ClassFromNameFn)JC2ResolveExport("il2cpp_class_from_name");
    JC2ClassGetMethodFromNameFn classGetMethod = (JC2ClassGetMethodFromNameFn)JC2ResolveExport("il2cpp_class_get_method_from_name");

    if (!domainGet || !domainGetAssemblies || !assemblyGetImage || !classFromName || !classGetMethod) {
        return NO;
    }

    void *domain = domainGet();
    if (!domain) return NO;
    size_t count = 0;
    const void **assemblies = domainGetAssemblies(domain, &count);
    if (!assemblies || !count) return NO;

    void *textAssetClass = NULL;
    void *objectClass = NULL;
    void *assetBundleClass = NULL;
    NSString *textImageName = nil;
    NSString *bundleImageName = nil;

    for (size_t i = 0; i < count; i++) {
        void *image = assemblyGetImage(assemblies[i]);
        if (!image) continue;
        if (!textAssetClass) {
            textAssetClass = classFromName(image, "UnityEngine", "TextAsset");
            if (textAssetClass && imageGetName) {
                const char *n = imageGetName(image);
                if (n) textImageName = [NSString stringWithUTF8String:n];
            }
        }
        if (!objectClass) objectClass = classFromName(image, "UnityEngine", "Object");
        if (!assetBundleClass) {
            assetBundleClass = classFromName(image, "UnityEngine", "AssetBundle");
            if (assetBundleClass && imageGetName) {
                const char *n = imageGetName(image);
                if (n) bundleImageName = [NSString stringWithUTF8String:n];
            }
        }
        if (textAssetClass && objectClass && assetBundleClass) break;
    }

    if (!textAssetClass && !assetBundleClass) return NO;

    if (objectClass) {
        gJC2ObjectGetNameMethod = classGetMethod(objectClass, "get_name", 0);
        gJC2ObjectGetName = (JC2ObjectGetNameFn)JC2MethodPointer(gJC2ObjectGetNameMethod);
    }

    NSString *hookAPI = nil;
    BOOL textOK = NO, bytesOK = NO, loadOK = NO, asyncOK = NO;

    if (textAssetClass) {
        const void *mText = classGetMethod(textAssetClass, "get_text", 0);
        const void *mBytes = classGetMethod(textAssetClass, "get_bytes", 0);
        void *pText = JC2MethodPointer(mText);
        void *pBytes = JC2MethodPointer(mBytes);
        textOK = JC2HookAddress(pText, (void *)JC2HookTextAssetGetText, (void **)&gJC2OrigTextAssetGetText, &hookAPI);
        bytesOK = JC2HookAddress(pBytes, (void *)JC2HookTextAssetGetBytes, (void **)&gJC2OrigTextAssetGetBytes, &hookAPI);
    }

    if (assetBundleClass) {
        const void *mLoad = classGetMethod(assetBundleClass, "LoadAsset", 2);
        const void *mAsync = classGetMethod(assetBundleClass, "LoadAssetAsync", 2);
        void *pLoad = JC2MethodPointer(mLoad);
        void *pAsync = JC2MethodPointer(mAsync);
        loadOK = JC2HookAddress(pLoad, (void *)JC2HookLoadAsset, (void **)&gJC2OrigLoadAsset, &hookAPI);
        asyncOK = JC2HookAddress(pAsync, (void *)JC2HookLoadAssetAsync, (void **)&gJC2OrigLoadAssetAsync, &hookAPI);
    }

    gJC2Installed = textOK || bytesOK || loadOK || asyncOK;
    JC2Log([NSString stringWithFormat:@"IL2CPP-HOOK installed=%d api=%@ assemblies=%lu textImage=%@ bundleImage=%@ TextAsset::get_text=%d TextAsset::get_bytes=%d AssetBundle::LoadAsset=%d AssetBundle::LoadAssetAsync=%d Object::get_name=%d",
            gJC2Installed, hookAPI ?: @"none", (unsigned long)count,
            textImageName ?: @"?", bundleImageName ?: @"?",
            textOK, bytesOK, loadOK, asyncOK, gJC2ObjectGetName != NULL]);
    return gJC2Installed;
}

static void JC2Poll(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (gJC2Installed) return;
        if (JC2InstallIL2CPPHooks()) return;
        if (attempt < JC2_POLL_MAX) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JC2Poll(attempt + 1); });
        } else {
            JC2Log(@"IL2CPP-HOOK timeout: exports/classes/methods not ready or hook backend unavailable");
        }
    });
}

__attribute__((constructor)) static void JC2Entry(void) {
    @autoreleasepool {
        JC2SetupPaths();
        gJC2Queue = dispatch_queue_create("com.hfamap187.jsoncapture.il2cpp.v04", DISPATCH_QUEUE_SERIAL);
        gJC2SeenHashes = [[NSMutableSet alloc] init];
        JC2Log([NSString stringWithFormat:@"%@ loaded; waiting for IL2CPP domain; Lua53 wrapper analyzer enabled", JC2_VERSION]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JC2Poll(0); });
    }
}
