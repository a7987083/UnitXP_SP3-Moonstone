#!/usr/bin/env python3
from pathlib import Path
import re

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_SHA256_IDENTITY_V082"
if MARKER in s:
    print("v0.8.2 SHA-256 identity patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_RUNTIME_CACHE_V052",
    "JCG5_RESPONSE_CAPTURE_V055",
    "JCG5_UNITY_ALL_JSON_V057",
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_RUNTIME_LATEST_SYNC_V081",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.2 sha256 anchor missing: {label}")
    s = s.replace(old, new, count)

def regex_rep(pattern: str, repl: str, label: str, count: int = 1) -> None:
    global s
    s2, n = re.subn(pattern, repl, s, count=count, flags=re.S)
    if n != count:
        raise SystemExit(f"v0.8.2 sha256 regex anchor missing: {label} ({n}/{count})")
    s = s2

# ---------------------------------------------------------------------------
# 1) Runtime Lua cache: SHA-256 is the only content identity.
#    Existing cache/manifest files are still readable because they already
#    persisted sha256 alongside the former MD5 field.
# ---------------------------------------------------------------------------
s = s.replace("static NSMutableSet *gJCG5CaptureMD5s;\n", "")

regex_rep(
    r"static NSString \*JCG5MD5\(NSData \*data\) \{.*?\n\}\n",
    "",
    "remove MD5 helper",
)

start = s.index("static void JCG5AppendRuntimeCaptureCache(")
end = s.index("#pragma mark - Dynamic symbols / loader hooks", start)
runtime_cache_helpers = r'''// JCG5_SHA256_IDENTITY_V082: all content identity uses full SHA-256.
static BOOL JCG82FileMatchesSHA256(NSString *path, NSString *expected) {
    if (!path.length || !expected.length) return NO;
    NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!d.length) return NO;
    return [[JCG5SHA256(d) lowercaseString] isEqualToString:[expected lowercaseString]];
}

static void JCG5AppendRuntimeCaptureCache(NSString *sha, NSString *source, NSString *chunk, NSUInteger bytes, NSString *status) {
    if (!gJCG5CaptureCachePath.length || !sha.length) return;
    NSDictionary *obj = @{
        @"schema": @2,
        @"algorithm": @"sha256",
        @"sha256": sha,
        @"source": source ?: @"",
        @"chunk": chunk ?: @"",
        @"bytes": @(bytes),
        @"status": status ?: @"captured",
        @"time": @([[NSDate date] timeIntervalSince1970])
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d.length) return;
    NSString *line = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    pthread_mutex_lock(&gJCG5LogLock);
    FILE *f = fopen(gJCG5CaptureCachePath.fileSystemRepresentation, "a");
    if (f) {
        NSData *ld = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(ld.bytes, 1, ld.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJCG5LogLock);
}

static void JCG5LoadSHA256ManifestIntoSet(NSString *path) {
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
            NSString *sha = [o[@"sha256"] lowercaseString];
            if (sha.length == 64) [gJCG5CaptureHashes addObject:sha];
        }
    }
}

static void JCG5LoadRuntimeCaptureCache(void) {
    if (!gJCG5CaptureHashes) gJCG5CaptureHashes = [[NSMutableSet alloc] init];
    [gJCG5CaptureCachePath release];
    gJCG5CaptureCachePath = [[gJCG5StateDir stringByAppendingPathComponent:@"RuntimeCapture.cache.jsonl"] retain];

    JCG5LoadSHA256ManifestIntoSet(gJCG5CaptureCachePath);
    JCG5LoadSHA256ManifestIntoSet([gJCG5Root stringByAppendingPathComponent:@"loader_manifest.jsonl"]);

    pthread_mutex_lock(&gJCG5StateLock);
    gJCG5CaptureCacheLoaded = gJCG5CaptureHashes.count;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5Log([NSString stringWithFormat:@"RUNTIME-CACHE ready sha256=%lu path=%@",
             (unsigned long)gJCG5CaptureHashes.count, gJCG5CaptureCachePath]);
}

'''
s = s[:start] + runtime_cache_helpers + s[end:]

# Replace the manifest + loader queue as one authoritative SHA-256 path.
mstart = s.index("static void JCG5AppendLoaderManifest(")
mend = s.index("static int JCG5HookTolua(", mstart)
loader_block = r'''static void JCG5AppendLoaderManifest(NSString *file, NSString *source, NSString *chunk, NSString *sha, NSUInteger bytes) {
    NSDictionary *obj = @{
        @"schema": @2,
        @"algorithm": @"sha256",
        @"file": file ?: @"",
        @"source": source ?: @"",
        @"chunk": chunk ?: @"",
        @"sha256": sha ?: @"",
        @"bytes": @(bytes),
        @"time": @([[NSDate date] timeIntervalSince1970])
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d) return;
    NSString *line = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    NSString *path = [gJCG5Root stringByAppendingPathComponent:@"loader_manifest.jsonl"];
    pthread_mutex_lock(&gJCG5LogLock);
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) {
        NSData *ld = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(ld.bytes, 1, ld.length, f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJCG5LogLock);
}

static void JCG5QueueLoaderCapture(NSData *data, NSString *source, NSString *chunkName) {
    if (!data.length || data.length > JCG5_MAX_BUFFER || !gJCG5CaptureQueue) return;
    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = [(source ?: @"loader") copy];
    NSString *chunk = [(chunkName ?: @"unnamed") copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        NSString *hash = JCG5SHA256(snapshot).lowercaseString;
        if (!hash.length) { [src release]; [chunk release]; return; }

        BOOL duplicate = [gJCG5CaptureHashes containsObject:hash];
        if (duplicate) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG5CaptureSkipped++;
            gJCG5CaptureCacheLoaded = gJCG5CaptureHashes.count;
            [gJCG5LastCaptureChunk release]; gJCG5LastCaptureChunk = [chunk copy];
            [gJCG5LastCaptureStatus release]; gJCG5LastCaptureStatus = [@"已抓过" copy];
            pthread_mutex_unlock(&gJCG5StateLock);

            // JCG5_RUNTIME_LATEST_SYNC_V081 preserved: same source as the visible “运行时抓取 -> 最新” field.
            NSDictionary *runtimeLatestCtx = JCG60PageContextSnapshot();
            JCG80ObserveLuaChunkOnQueue(chunk, runtimeLatestCtx);
            dispatch_async(dispatch_get_main_queue(), ^{
                JCG5SetEvent([NSString stringWithFormat:@"最新 %@ 已抓过，SHA256命中", chunk.lastPathComponent ?: chunk]);
            });
            [src release]; [chunk release]; return;
        }

        JCG5NotifyRuntimeCapture();
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG5CaptureCount++;
        unsigned long long seq = gJCG5CaptureCount;
        [gJCG5LastCaptureChunk release]; gJCG5LastCaptureChunk = [chunk copy];
        [gJCG5LastCaptureStatus release]; gJCG5LastCaptureStatus = [@"新抓取" copy];
        pthread_mutex_unlock(&gJCG5StateLock);

        NSDictionary *runtimeLatestCtx = JCG60PageContextSnapshot();
        JCG80ObserveLuaChunkOnQueue(chunk, runtimeLatestCtx);

        NSString *ext = JCG5HasLua53(snapshot) ? @"luac" : @"bin";
        NSString *file = [NSString stringWithFormat:@"%06llu_%@_%@_%@.%@",
                          seq, JCG5Safe(src,24), JCG5Safe(chunk,96), hash, ext];
        NSString *path = [gJCG5LoaderDir stringByAppendingPathComponent:file];
        BOOL wrote = [snapshot writeToFile:path atomically:YES];
        if (wrote) {
            [gJCG5CaptureHashes addObject:hash];
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG5CaptureCacheLoaded = gJCG5CaptureHashes.count;
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5AppendLoaderManifest(file, src, chunk, hash, snapshot.length);
            JCG5AppendRuntimeCaptureCache(hash, src, chunk, snapshot.length, @"captured");
            dispatch_async(dispatch_get_main_queue(), ^{
                JCG5SetEvent([NSString stringWithFormat:@"新抓取：%@", chunk.lastPathComponent ?: chunk]);
            });
        } else {
            pthread_mutex_lock(&gJCG5StateLock);
            [gJCG5LastCaptureStatus release]; gJCG5LastCaptureStatus = [@"写入失败" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
        }
        [src release]; [chunk release];
    }});
}

'''
s = s[:mstart] + loader_block + s[mend:]

s = s.replace("gJCG5CaptureHashes=[[NSMutableSet alloc]init];gJCG5CaptureMD5s=[[NSMutableSet alloc]init];",
              "gJCG5CaptureHashes=[[NSMutableSet alloc]init];")
s = s.replace("缓存MD5：", "缓存SHA256：")

# ---------------------------------------------------------------------------
# 2) Validated HTTP/JSON response cache: SHA-256 filename + SHA-256 dedupe.
# ---------------------------------------------------------------------------
s = s.replace("static NSMutableSet *gJCG55ResponseMD5s;\n", "")

rstart = s.index("static void JCG55LoadResponseCacheIfNeeded(void) {")
rend = s.index("static void JCG55QueueValidatedResponse(", rstart)
response_cache = r'''static void JCG55LoadResponseCacheIfNeeded(void) {
    if (gJCG55ResponseCacheReady) return;
    if (!gJCG55ResponseSHA256s) gJCG55ResponseSHA256s = [[NSMutableSet alloc] init];

    if (!gJCG55ResponseDir) gJCG55ResponseDir = [[gJCG5Root stringByAppendingPathComponent:@"runtime_response_json"] retain];
    if (!gJCG55ResponseCachePath) gJCG55ResponseCachePath = [[gJCG5StateDir stringByAppendingPathComponent:@"ResponseCapture.cache.jsonl"] retain];
    if (!gJCG55ResponseManifestPath) gJCG55ResponseManifestPath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_response_manifest.jsonl"] retain];
    if (!gJCG56RequestTracePath) gJCG56RequestTracePath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_response_requests.jsonl"] retain];
    JCG5EnsureDir(gJCG55ResponseDir);

    NSData *raw = [NSData dataWithContentsOfFile:gJCG55ResponseCachePath options:NSDataReadingMappedIfSafe error:nil];
    if (raw.length) {
        NSString *text = [[[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] autorelease];
        for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            @autoreleasepool {
                if (line.length < 2) continue;
                NSDictionary *o = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                id shaObj = [o isKindOfClass:[NSDictionary class]] ? [o objectForKey:@"sha256"] : nil;
                NSString *sha = [shaObj isKindOfClass:[NSString class]] ? [shaObj lowercaseString] : @"";
                if (sha.length == 64) [gJCG55ResponseSHA256s addObject:sha];
            }
        }
    }
    gJCG55ResponseCacheReady = YES;
    pthread_mutex_lock(&gJCG5StateLock);
    gJCG55ResponseCacheLoaded = gJCG55ResponseSHA256s.count;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE cache ready sha256=%lu path=%@",
             (unsigned long)gJCG55ResponseSHA256s.count, gJCG55ResponseCachePath]);
}

'''
s = s[:rstart] + response_cache + s[rend:]

# Remove the MD5 local from the final response writer and make SHA-256 authoritative.
s = re.sub(r'\n\s*NSString \*md5 = \[JCG5MD5\(snapshot\)\.lowercaseString copy\];', '', s)
s = s.replace("if (!md5.length || !sha.length)", "if (!sha.length)")
s = s.replace("[md5 release]; [sha release];", "[sha release];")
s = s.replace('NSString *file = [NSString stringWithFormat:@"%@.json", md5];',
              'NSString *file = [NSString stringWithFormat:@"%@.json", sha];')
s = s.replace(
    "BOOL duplicate = [gJCG55ResponseMD5s containsObject:md5] ||\n"
    "                         [gJCG55ResponseSHA256s containsObject:sha] ||\n"
    "                         [[NSFileManager defaultManager] fileExistsAtPath:path];",
    "BOOL duplicate = [gJCG55ResponseSHA256s containsObject:sha] || JCG82FileMatchesSHA256(path, sha);"
)
s = re.sub(r'\n\s*if \(!\[gJCG55ResponseMD5s containsObject:md5\]\) \[gJCG55ResponseMD5s addObject:md5\];', '', s)
s = s.replace("[gJCG55ResponseMD5s addObject:md5];\n", "")
s = s.replace("gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;",
              "gJCG55ResponseCacheLoaded = gJCG55ResponseSHA256s.count;")
s = re.sub(r'\n\s*@"md5": md5,', '', s)
s = s.replace(" file=%@ md5=%@ sha256=%@", " file=%@ sha256=%@")
s = s.replace("file, md5, sha", "file, sha")

# ---------------------------------------------------------------------------
# 3) UnityWebRequest backend duplicate suppression: SHA-256 only.
# ---------------------------------------------------------------------------
s = s.replace("gJCG57BackendMD5s", "gJCG57BackendSHA256s")
s = s.replace(
    "NSString *md5 = JCG5MD5(body).lowercaseString;\n"
    "        if (md5.length) {\n"
    "            if (!gJCG57BackendSHA256s) gJCG57BackendSHA256s = [[NSMutableSet alloc] init];\n"
    "            [gJCG57BackendSHA256s addObject:md5];\n"
    "        }",
    "NSString *backendSHA256 = JCG5SHA256(body).lowercaseString;\n"
    "        if (backendSHA256.length) {\n"
    "            if (!gJCG57BackendSHA256s) gJCG57BackendSHA256s = [[NSMutableSet alloc] init];\n"
    "            [gJCG57BackendSHA256s addObject:backendSHA256];\n"
    "        }"
)
s = s.replace("[gJCG57BackendSHA256s containsObject:md5]",
              "[gJCG57BackendSHA256s containsObject:sha]")

# ---------------------------------------------------------------------------
# 4) Raw/decrypted local files: keep content-addressed names, but use the FULL
#    SHA-256 rather than a 12-hex truncation/file-existence-only decision.
# ---------------------------------------------------------------------------
raw_start = s.index("static NSString *JCG5WriteRaw(NSData *data, NSString *asset) {")
raw_end = s.index("\n\nstatic void JCG5AppendRawManifest(", raw_start)
s = s[:raw_start] + r'''static NSString *JCG5WriteRaw(NSData *data, NSString *asset) {
    NSString *hash = JCG5SHA256(data).lowercaseString;
    NSString *file = [NSString stringWithFormat:@"%@_%@.bin", JCG5Safe(asset,150), hash];
    NSString *path = [gJCG5RawDir stringByAppendingPathComponent:file];
    if (!JCG82FileMatchesSHA256(path, hash)) [data writeToFile:path atomically:YES];
    return file;
}''' + s[raw_end:]
s = s.replace(
    'NSString*file=[NSString stringWithFormat:@"%@_%@.luac",stem,[dh substringToIndex:MIN((NSUInteger)12,dh.length)]];',
    'NSString*file=[NSString stringWithFormat:@"%@_%@.luac",stem,dh.lowercaseString];'
)

# ---------------------------------------------------------------------------
# 5) TAB config cache: name-only "captured once" is replaced by semantic
#    SHA-256. Cached data is attached to every relevant page event, while a
#    request refreshes the table and changes the cache only when content changes.
# ---------------------------------------------------------------------------
s = s.replace("static NSMutableSet *gJCG70CapturedTabConfigs;\n",
              "static NSMutableDictionary *gJCG82TabConfigByGlobal;\n"
              "static NSMutableDictionary *gJCG82TabConfigSHA256ByGlobal;\n")

tstart = s.index("static void JCG70AttachLocalTabConfig(void *L, NSMutableDictionary *event) {")
tend = s.index("\n}\n\nstatic void JCG60QueueProtobufEvent(", tstart) + 2
tab_func = r'''static void JCG70AttachLocalTabConfig(void *L, NSMutableDictionary *event) {
    if (!L || !event || !gJCG58LuaGetGlobal || !gJCG58LuaGetTop || !gJCG58LuaSetTop) return;
    NSString *tab = [event objectForKey:@"page_tab_lua"];
    if (!tab.length) return;
    NSString *globalName = JCG70TabGlobalName(tab);
    if (!globalName.length) return;

    if (!gJCG82TabConfigByGlobal) gJCG82TabConfigByGlobal = [[NSMutableDictionary alloc] init];
    if (!gJCG82TabConfigSHA256ByGlobal) gJCG82TabConfigSHA256ByGlobal = [[NSMutableDictionary alloc] init];

    id cached = [gJCG82TabConfigByGlobal objectForKey:globalName];
    NSString *cachedSHA = [gJCG82TabConfigSHA256ByGlobal objectForKey:globalName];
    BOOL shouldRefresh = !cached || [[event objectForKey:@"direction"] isEqualToString:@"request"];

    if (shouldRefresh) {
        int top = gJCG58LuaGetTop(L);
        int t = gJCG58LuaGetGlobal(L, globalName.UTF8String);
        if (t == JCG60_LUA_TTABLE) {
            id snapshot = JCG60Snapshot(L, -1);
            NSData *canonical = snapshot ? [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingSortedKeys error:nil] : nil;
            NSString *sha = canonical.length ? JCG5SHA256(canonical).lowercaseString : @"";
            if (snapshot && sha.length && ![sha isEqualToString:cachedSHA]) {
                [gJCG82TabConfigByGlobal setObject:snapshot forKey:globalName];
                [gJCG82TabConfigSHA256ByGlobal setObject:sha forKey:globalName];
                cached = snapshot;
                cachedSHA = sha;
            }
        }
        gJCG58LuaSetTop(L, top);
    }

    if (cached) {
        [event setObject:globalName forKey:@"page_local_tab_global"];
        [event setObject:cached forKey:@"page_local_tab_config"];
        if (cachedSHA.length) [event setObject:cachedSHA forKey:@"page_local_tab_sha256"];
    }
}'''
s = s[:tstart] + tab_func + s[tend:]

# ---------------------------------------------------------------------------
# 6) runtime_page_snapshot: same-name atomic overwrite remains mandatory.
#    SHA-256 determines semantic change; exact serialized bytes get file_sha256.
# ---------------------------------------------------------------------------
rep(
    "static void JCG70EnsureSnapshotPaths(void) {",
    "static void JCG82LoadSnapshotIndexIfNeeded(void);\\n"
    "static void JCG70EnsureSnapshotPaths(void) {",
    "snapshot index loader forward declaration",
)

anchor = '''static void JCG70WriteIndex(void) {'''
snapshot_hash_helpers = r'''
static NSDictionary *JCG82SemanticJSONState(NSDictionary *state) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in state ?: @{}) {
        NSDictionary *slot = [state objectForKey:key];
        if (![slot isKindOfClass:[NSDictionary class]]) { if (slot) [out setObject:slot forKey:key]; continue; }
        NSMutableDictionary *v = [NSMutableDictionary dictionaryWithDictionary:slot];
        [v removeObjectForKey:@"time"];
        [out setObject:v forKey:key];
    }
    return out;
}

static NSDictionary *JCG82SemanticPBState(NSDictionary *state) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in state ?: @{}) {
        NSDictionary *slot = [state objectForKey:key];
        if (![slot isKindOfClass:[NSDictionary class]]) { if (slot) [out setObject:slot forKey:key]; continue; }
        NSMutableDictionary *v = [NSMutableDictionary dictionaryWithDictionary:slot];
        [v removeObjectForKey:@"last_time"];
        [v removeObjectForKey:@"last_raw_file"];
        [out setObject:v forKey:key];
    }
    return out;
}

static NSDictionary *JCG82SemanticFlows(NSDictionary *flows) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in flows ?: @{}) {
        NSDictionary *flow = [flows objectForKey:key];
        if (![flow isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *cleanFlow = [NSMutableDictionary dictionary];
        for (NSString *side in @[@"request", @"response"]) {
            NSDictionary *part = [flow objectForKey:side];
            if (![part isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *v = [NSMutableDictionary dictionaryWithDictionary:part];
            [v removeObjectForKey:@"time"];
            [v removeObjectForKey:@"sequence"];
            [v removeObjectForKey:@"raw_file"];
            [cleanFlow setObject:v forKey:side];
        }
        if (cleanFlow.count) [out setObject:cleanFlow forKey:key];
    }
    return out;
}

static NSString *JCG82SnapshotSemanticSHA256(NSDictionary *entry) {
    NSDictionary *payload = @{
        @"page_context": [entry objectForKey:@"page_context"] ?: @"",
        @"page_ui_lua": [entry objectForKey:@"page_ui_lua"] ?: @"",
        @"page_tab_lua": [entry objectForKey:@"page_tab_lua"] ?: @"",
        @"local_tab_global": [entry objectForKey:@"local_tab_global"] ?: @"",
        @"local_tab_config": [entry objectForKey:@"local_tab_config"] ?: @{},
        @"json_state": JCG82SemanticJSONState([entry objectForKey:@"json_state"]),
        @"protobuf_state": JCG82SemanticPBState([entry objectForKey:@"protobuf_state"]),
        @"flows": JCG82SemanticFlows([entry objectForKey:@"flows"])
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
    return d.length ? JCG5SHA256(d).lowercaseString : @"";
}

static void JCG82LoadSnapshotIndexIfNeeded(void) {
    if (gJCG70SnapshotIndex.count || !gJCG70SnapshotIndexPath.length) return;
    NSData *d = [NSData dataWithContentsOfFile:gJCG70SnapshotIndexPath options:NSDataReadingMappedIfSafe error:nil];
    NSDictionary *root = d.length ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSArray *pages = [root isKindOfClass:[NSDictionary class]] ? root[@"pages"] : nil;
    if (![pages isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *item in pages) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *key = item[@"page_session_key"];
        if (key.length) [gJCG70SnapshotIndex setObject:item forKey:key];
    }
}

'''
rep(anchor, snapshot_hash_helpers + anchor, "snapshot semantic helpers")

# Ensure previous-run hashes are available before comparing.
rep(
    "    if (!gJCG70SnapshotWritePending) gJCG70SnapshotWritePending = [[NSMutableSet alloc] init];\n}",
    "    if (!gJCG70SnapshotWritePending) gJCG70SnapshotWritePending = [[NSMutableSet alloc] init];\n"
    "    JCG82LoadSnapshotIndexIfNeeded();\n}",
    "load persistent snapshot index",
)

# Add semantic change calculation before every same-name atomic overwrite.
rep(
    '    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"snapshot_written_at"];\n\n'
    '    NSError *err = nil;',
    '    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"snapshot_written_at"];\n'
    '    NSDictionary *previousIndex = [gJCG70SnapshotIndex objectForKey:sessionKey];\n'
    '    NSString *previousSemantic = [previousIndex objectForKey:@"semantic_sha256"] ?: @"";\n'
    '    NSString *semanticSHA = JCG82SnapshotSemanticSHA256(entry);\n'
    '    BOOL semanticChanged = !previousSemantic.length || ![previousSemantic isEqualToString:semanticSHA];\n'
    '    if (semanticSHA.length) [entry setObject:semanticSHA forKey:@"semantic_sha256"];\n'
    '    [entry setObject:@(semanticChanged) forKey:@"semantic_changed"];\n\n'
    '    NSError *err = nil;',
    "snapshot semantic calculation",
)

# file_sha256 is over the exact bytes that were atomically written. It lives in
# the index to avoid a self-referential file hash.
rep(
    '    if (d.length && [d writeToFile:path options:NSDataWritingAtomic error:&err]) {\n'
    '        NSDictionary *idx = @{',
    '    if (d.length && [d writeToFile:path options:NSDataWritingAtomic error:&err]) {\n'
    '        NSString *fileSHA = JCG5SHA256(d).lowercaseString;\n'
    '        NSDictionary *idx = @{',
    "snapshot file SHA",
)

rep(
    '            @"events": @([(NSArray *)[entry objectForKey:@"events"] count]),\n'
    '            @"updated_at": [entry objectForKey:@"last_seen"] ?: @0\n',
    '            @"events": @([(NSArray *)[entry objectForKey:@"events"] count]),\n'
    '            @"semantic_sha256": semanticSHA ?: @"",\n'
    '            @"file_sha256": fileSHA ?: @"",\n'
    '            @"changed": @(semanticChanged),\n'
    '            @"updated_at": [entry objectForKey:@"last_seen"] ?: @0\n',
    "snapshot index hashes",
)

# Preserve TAB config semantic hash inside snapshots when present.
rep(
    '        NSString *global = [event objectForKey:@"page_local_tab_global"];\n'
    '        if (global.length) [entry setObject:global forKey:@"local_tab_global"];\n',
    '        NSString *global = [event objectForKey:@"page_local_tab_global"];\n'
    '        if (global.length) [entry setObject:global forKey:@"local_tab_global"];\n'
    '        NSString *tabSHA = [event objectForKey:@"page_local_tab_sha256"];\n'
    '        if (tabSHA.length) [entry setObject:tabSHA forKey:@"local_tab_sha256"];\n',
    "snapshot TAB SHA",
)

# Hard invariants: no effective MD5 content identity is allowed after this patch.
for forbidden in ("JCG5MD5(", "CC_MD5_DIGEST_LENGTH", "gJCG5CaptureMD5s", "gJCG55ResponseMD5s", "gJCG57BackendMD5s"):
    if forbidden in s:
        raise SystemExit(f"v0.8.2 SHA-256 invariant failed, legacy identity remains: {forbidden}")

# Marker is deliberately ASCII so CI can verify the compiled binary.
s += '\n// JCG5_SHA256_IDENTITY_V082 effective-identity=full-sha256 snapshot=same-name-atomic-overwrite\n'
p.write_text(s, encoding="utf-8")
print("applied v0.8.2 full SHA-256 identity + semantic snapshot hashing")
