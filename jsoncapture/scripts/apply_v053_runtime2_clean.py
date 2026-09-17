#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RUNTIME_CAPTURE2_V053_CLEAN"
if MARKER in s:
    print("v0.5.3 clean runtime capture2 patch already applied")
    raise SystemExit(0)

# This patch intentionally runs AFTER apply_v052_runtime_cache.py.
if "JCG5_RUNTIME_CACHE_V052" not in s:
    raise SystemExit("v0.5.2 runtime cache patch must be applied first")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"patch anchor missing: {label}")
    s = s.replace(old, new, 1)

runtime2 = r'''
// JCG5_RUNTIME_CAPTURE2_V053_CLEAN
// Runtime Capture 2 is deliberately integrated into the existing v0.5.2
// lifecycle. There is NO additional constructor, ObjC +load method, TLS/TLV
// state, or independent master switch.
typedef int (*JCG53LuaCFunction)(void *L);
typedef void (*JCG53ToluaVariableFn)(void *L, const char *name, JCG53LuaCFunction getter, JCG53LuaCFunction setter);
typedef const char *(*JCG53LuaToLStringFn)(void *L, int index, size_t *len);

static JCG53ToluaVariableFn gJCG53OrigToluaVariable;
static JCG53LuaToLStringFn gJCG53LuaToLString;
static JCG53LuaCFunction gJCG53OrigXHRResponseGetter;
static JCG53LuaCFunction gJCG53OrigXHRResponseTextGetter;

static NSMutableSet *gJCG53Runtime2MD5s;
static NSMutableSet *gJCG53Runtime2SHA256s;
static NSString *gJCG53Runtime2Dir;
static NSString *gJCG53Runtime2CachePath;
static NSString *gJCG53Runtime2ManifestPath;
static NSString *gJCG53Runtime2LastItem;
static NSString *gJCG53Runtime2LastStatus;
static BOOL gJCG53Runtime2Started = NO;
static BOOL gJCG53RegistrationHookReady = NO;
static BOOL gJCG53ResponseGetterReady = NO;
static BOOL gJCG53ResponseTextGetterReady = NO;
static unsigned int gJCG53XHRRegistrationProgress = 0;
static unsigned long long gJCG53Runtime2Captured = 0;
static unsigned long long gJCG53Runtime2Skipped = 0;
static unsigned long long gJCG53Runtime2CacheLoaded = 0;
static pthread_mutex_t gJCG53RegistrationLock = PTHREAD_MUTEX_INITIALIZER;

#define JCG53_MAX_JSON_BYTES (256ULL * 1024ULL * 1024ULL)
#define JCG53_XHR_SEQUENCE_COUNT 8

static const char *gJCG53XHRVariableSequence[JCG53_XHR_SEQUENCE_COUNT] = {
    "responseType", "withCredentials", "timeout", "readyState",
    "status", "statusText", "responseText", "response"
};

static void JCG53Runtime2SetupPaths(void) {
    if (gJCG53Runtime2Dir.length) return;
    gJCG53Runtime2Dir = [[gJCG5Root stringByAppendingPathComponent:@"runtime_json"] retain];
    gJCG53Runtime2CachePath = [[gJCG5StateDir stringByAppendingPathComponent:@"RuntimeCapture2.cache.jsonl"] retain];
    gJCG53Runtime2ManifestPath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_json_manifest.jsonl"] retain];
    JCG5EnsureDir(gJCG53Runtime2Dir);
}

static void JCG53AppendJSONL(NSString *path, NSDictionary *obj) {
    if (!path.length || !obj) return;
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d.length) return;
    pthread_mutex_lock(&gJCG5LogLock);
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) {
        fwrite(d.bytes, 1, d.length, f);
        fwrite("\n", 1, 1, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJCG5LogLock);
}

static void JCG53LoadHashFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length) return;
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text.length) return;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        @autoreleasepool {
            if (line.length < 2) continue;
            NSData *ld = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *o = [NSJSONSerialization JSONObjectWithData:ld options:0 error:nil];
            if (![o isKindOfClass:[NSDictionary class]]) continue;
            NSString *md5 = o[@"md5"];
            NSString *sha = o[@"sha256"];
            if (md5.length) [gJCG53Runtime2MD5s addObject:md5.lowercaseString];
            if (sha.length) [gJCG53Runtime2SHA256s addObject:sha.lowercaseString];
        }
    }
}

static void JCG53LoadRuntime2Cache(void) {
    if (!gJCG53Runtime2MD5s) gJCG53Runtime2MD5s = [[NSMutableSet alloc] init];
    if (!gJCG53Runtime2SHA256s) gJCG53Runtime2SHA256s = [[NSMutableSet alloc] init];
    JCG53LoadHashFile(gJCG53Runtime2CachePath);
    JCG53LoadHashFile(gJCG53Runtime2ManifestPath);
    pthread_mutex_lock(&gJCG5StateLock);
    gJCG53Runtime2CacheLoaded = gJCG53Runtime2MD5s.count;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5Log([NSString stringWithFormat:@"RUNTIME2-CACHE ready md5=%lu sha256=%lu path=%@",
             (unsigned long)gJCG53Runtime2MD5s.count,
             (unsigned long)gJCG53Runtime2SHA256s.count,
             gJCG53Runtime2CachePath]);
}

static void JCG53Runtime2SetLast(NSString *item, NSString *status) {
    pthread_mutex_lock(&gJCG5StateLock);
    [gJCG53Runtime2LastItem release];
    [gJCG53Runtime2LastStatus release];
    gJCG53Runtime2LastItem = [(item.length ? item : @"暂无") copy];
    gJCG53Runtime2LastStatus = [(status.length ? status : @"暂无") copy];
    pthread_mutex_unlock(&gJCG5StateLock);
}

static void JCG53Runtime2BumpSkipped(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    gJCG53Runtime2Skipped++;
    pthread_mutex_unlock(&gJCG5StateLock);
}

static NSString *JCG53Runtime2StatusText(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL enabled = gJCG5CaptureEnabled;
    BOOL reg = gJCG53RegistrationHookReady;
    BOOL response = gJCG53ResponseGetterReady;
    BOOL responseText = gJCG53ResponseTextGetterReady;
    unsigned long long captured = gJCG53Runtime2Captured;
    unsigned long long skipped = gJCG53Runtime2Skipped;
    unsigned long long cache = gJCG53Runtime2CacheLoaded;
    NSString *last = [[(gJCG53Runtime2LastItem ?: @"暂无") copy] autorelease];
    NSString *status = [[(gJCG53Runtime2LastStatus ?: @"暂无") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    NSUInteger targets = (response ? 1 : 0) + (responseText ? 1 : 0);
    NSString *hook = targets ? @"就绪" : (reg ? @"监听" : @"等待");
    return [NSString stringWithFormat:@"状态：%@  Hook：%@  目标%lu/2  新抓%llu\n跳过%llu 缓存MD5：%llu  最新：%@｜%@",
            enabled ? @"开启 ✅" : @"关闭", hook, (unsigned long)targets,
            captured, skipped, cache, last.lastPathComponent ?: last, status];
}

static BOOL JCG53PrefixLooksJSON(NSData *data) {
    if (!data.length || data.length > JCG53_MAX_JSON_BYTES) return NO;
    const unsigned char *p = data.bytes;
    NSUInteger i = 0;
    if (data.length >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) i = 3;
    while (i < data.length) {
        unsigned char c = p[i++];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        return c == '{' || c == '[';
    }
    return NO;
}

static BOOL JCG53CompleteJSON(NSData *data) {
    if (!JCG53PrefixLooksJSON(data)) return NO;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    return obj && !err && ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]);
}

static void JCG53Runtime2Queue(NSData *data, NSString *source) {
    if (!data.length || data.length > JCG53_MAX_JSON_BYTES || !gJCG5CaptureQueue) return;
    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = [(source.length ? source : @"xhr.response") copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        BOOL enabled;
        pthread_mutex_lock(&gJCG5StateLock);
        enabled = gJCG5CaptureEnabled;
        pthread_mutex_unlock(&gJCG5StateLock);
        if (!enabled) { [src release]; return; }
        if (!JCG53CompleteJSON(snapshot)) {
            JCG53Runtime2BumpSkipped();
            JCG53Runtime2SetLast(src, @"非完整JSON");
            [src release];
            return;
        }

        NSString *md5 = JCG5MD5(snapshot).lowercaseString;
        NSString *sha = JCG5SHA256(snapshot).lowercaseString;
        if (!md5.length || !sha.length) { [src release]; return; }
        BOOL duplicate = [gJCG53Runtime2MD5s containsObject:md5] || [gJCG53Runtime2SHA256s containsObject:sha];
        NSString *shortHash = sha.length > 12 ? [sha substringToIndex:12] : sha;
        if (duplicate) {
            JCG53Runtime2BumpSkipped();
            JCG53Runtime2SetLast([NSString stringWithFormat:@"JSON_%@", shortHash], @"已抓过");
            [src release];
            return;
        }

        NSString *safeSource = [src isEqualToString:@"xhr.responseText"] ? @"xhr_responseText" : @"xhr_response";
        NSString *file = [NSString stringWithFormat:@"%@_%@.json", safeSource, shortHash];
        NSString *path = [gJCG53Runtime2Dir stringByAppendingPathComponent:file];
        NSError *writeErr = nil;
        if (![snapshot writeToFile:path options:NSDataWritingAtomic error:&writeErr]) {
            JCG53Runtime2SetLast(file, @"写入失败");
            JCG5Log([NSString stringWithFormat:@"RUNTIME2 WRITE-FAIL source=%@ sha256=%@ err=%@", src, sha, writeErr]);
            [src release];
            return;
        }

        [gJCG53Runtime2MD5s addObject:md5];
        [gJCG53Runtime2SHA256s addObject:sha];
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG53Runtime2Captured++;
        gJCG53Runtime2CacheLoaded = gJCG53Runtime2MD5s.count;
        pthread_mutex_unlock(&gJCG5StateLock);

        NSDictionary *record = @{
            @"schema": @3,
            @"source": src,
            @"file": file,
            @"md5": md5,
            @"sha256": sha,
            @"bytes": @(snapshot.length),
            @"time": @([[NSDate date] timeIntervalSince1970])
        };
        JCG53AppendJSONL(gJCG53Runtime2ManifestPath, record);
        JCG53AppendJSONL(gJCG53Runtime2CachePath, record);
        JCG53Runtime2SetLast(file, @"新抓取");
        JCG5Log([NSString stringWithFormat:@"RUNTIME2 CAPTURE source=%@ file=%@ bytes=%lu sha256=%@",
                 src, file, (unsigned long)snapshot.length, sha]);
        [src release];
    }});
}

static void JCG53CaptureGetterResult(void *L, int resultCount, NSString *source) {
    if (!L || resultCount != 1 || !gJCG53LuaToLString) return;
    BOOL enabled;
    pthread_mutex_lock(&gJCG5StateLock);
    enabled = gJCG5CaptureEnabled;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (!enabled) return;

    size_t len = 0;
    const char *bytes = gJCG53LuaToLString(L, -1, &len);
    if (!bytes || !len || len > JCG53_MAX_JSON_BYTES) return;
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:bytes length:len];
        if (!JCG53PrefixLooksJSON(data)) {
            JCG53Runtime2BumpSkipped();
            return;
        }
        JCG53Runtime2Queue(data, source);
    }
}

static int JCG53XHRResponseGetter(void *L) {
    int rc = gJCG53OrigXHRResponseGetter ? gJCG53OrigXHRResponseGetter(L) : 0;
    JCG53CaptureGetterResult(L, rc, @"xhr.response");
    return rc;
}

static int JCG53XHRResponseTextGetter(void *L) {
    int rc = gJCG53OrigXHRResponseTextGetter ? gJCG53OrigXHRResponseTextGetter(L) : 0;
    JCG53CaptureGetterResult(L, rc, @"xhr.responseText");
    return rc;
}

static int JCG53MatchXHRVariableLocked(const char *name) {
    if (!name) { gJCG53XHRRegistrationProgress = 0; return -1; }
    unsigned int p = gJCG53XHRRegistrationProgress;
    if (p < JCG53_XHR_SEQUENCE_COUNT && strcmp(name, gJCG53XHRVariableSequence[p]) == 0) {
        int matched = (int)p;
        p++;
        gJCG53XHRRegistrationProgress = (p >= JCG53_XHR_SEQUENCE_COUNT) ? 0 : p;
        return matched;
    }
    if (strcmp(name, gJCG53XHRVariableSequence[0]) == 0) {
        gJCG53XHRRegistrationProgress = 1;
        return 0;
    }
    gJCG53XHRRegistrationProgress = 0;
    return -1;
}

static void JCG53HookToluaVariable(void *L, const char *name, JCG53LuaCFunction getter, JCG53LuaCFunction setter) {
    JCG53LuaCFunction passGetter = getter;
    pthread_mutex_lock(&gJCG53RegistrationLock);
    int matched = JCG53MatchXHRVariableLocked(name);
    if (matched == 6 && getter && setter == NULL) {
        if (!gJCG53OrigXHRResponseTextGetter) gJCG53OrigXHRResponseTextGetter = getter;
        if (gJCG53OrigXHRResponseTextGetter == getter) {
            passGetter = JCG53XHRResponseTextGetter;
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG53ResponseTextGetterReady = YES;
            pthread_mutex_unlock(&gJCG5StateLock);
        }
    } else if (matched == 7 && getter && setter == NULL) {
        if (!gJCG53OrigXHRResponseGetter) gJCG53OrigXHRResponseGetter = getter;
        if (gJCG53OrigXHRResponseGetter == getter) {
            passGetter = JCG53XHRResponseGetter;
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG53ResponseGetterReady = YES;
            pthread_mutex_unlock(&gJCG5StateLock);
        }
    }
    pthread_mutex_unlock(&gJCG53RegistrationLock);
    if (gJCG53OrigToluaVariable) gJCG53OrigToluaVariable(L, name, passGetter, setter);
}

static BOOL JCG53InstallRegistrationHook(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL ready = gJCG53RegistrationHookReady;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (ready) return YES;

    void *variable = JCG5ResolveExport("tolua_variable");
    void *tolstring = JCG5ResolveExport("lua_tolstring");
    if (!variable || !tolstring) return NO;
    gJCG53LuaToLString = (JCG53LuaToLStringFn)tolstring;
    BOOL ok = JCG5Hook(variable, (void *)JCG53HookToluaVariable, (void **)&gJCG53OrigToluaVariable);
    if (ok) {
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG53RegistrationHookReady = YES;
        pthread_mutex_unlock(&gJCG5StateLock);
        JCG5Log([NSString stringWithFormat:@"RUNTIME2-HOOK registration ready tolua_variable=%p lua_tolstring=%p", variable, tolstring]);
    }
    return ok;
}

static void JCG53PollRegistrationHook(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (JCG53InstallRegistrationHook()) return;
        if (attempt < 120) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                JCG53PollRegistrationHook(attempt + 1);
            });
        } else {
            JCG5Log(@"RUNTIME2-HOOK unavailable/timeout tolua_variable or lua_tolstring");
        }
    });
}

static void JCG53Runtime2Start(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    if (gJCG53Runtime2Started) { pthread_mutex_unlock(&gJCG5StateLock); return; }
    gJCG53Runtime2Started = YES;
    pthread_mutex_unlock(&gJCG5StateLock);

    // Keep constructor work minimal: initialization and hook polling happen on
    // the same utility queue pattern already used by v0.5.2.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{@autoreleasepool {
        JCG53Runtime2SetupPaths();
        gJCG53Runtime2MD5s = [[NSMutableSet alloc] init];
        gJCG53Runtime2SHA256s = [[NSMutableSet alloc] init];
        gJCG53Runtime2LastItem = [@"暂无" copy];
        gJCG53Runtime2LastStatus = [@"暂无" copy];
        JCG53LoadRuntime2Cache();
        JCG5Log(@"JSONCapture v0.5.3 Runtime Capture 2 clean loaded inside v0.5.2 lifecycle; no extra constructor; no TLS/TLV");
        JCG53PollRegistrationHook(0);
    }});
}

'''

# Reuse the original v0.5.2 hook resolver and hook backend instead of creating
# a second startup module or a separate swizzle layer.
rep(
    "static void JCG5NotifyRuntimeCapture(void) {\n",
    runtime2 + "static void JCG5NotifyRuntimeCapture(void) {\n",
    "runtime2 core insertion",
)

# Add the second runtime row directly to the existing controller layout.
rep(
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"运行时抓取二"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    "runtime2 UI row",
)

# Refresh Capture2 from the same existing timer and the same master switch.
rep(
    '    self.labels[@"scan"].text=',
    '    self.labels[@"capture2"].text=JCG53Runtime2StatusText();\n    self.labels[@"scan"].text=',
    "runtime2 UI refresh",
)

# Start Capture2 from the ONE existing v0.5.2 constructor. No second entrypoint.
rep(
    'JCG5PollHooks(0);dispatch_after(',
    'JCG5PollHooks(0);JCG53Runtime2Start();dispatch_after(',
    "single-constructor runtime2 start",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.3 clean Runtime Capture 2 patch on v0.5.2 lifecycle")
