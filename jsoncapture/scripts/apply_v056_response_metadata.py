#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RESPONSE_METADATA_V056"
if MARKER in s:
    print("v0.5.6 response metadata patch already applied")
    raise SystemExit(0)

for required in ("JCG5_RUNTIME_CACHE_V052", "JCG5_RESPONSE_OBSERVER_V054", "JCG5_RESPONSE_CAPTURE_V055"):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"patch anchor missing: {label}")
    s = s.replace(old, new, 1)


rep(
    "static unsigned long long gJCG55ResponseCacheLoaded = 0;\n",
    "static unsigned long long gJCG55ResponseCacheLoaded = 0;\n"
    "// JCG5_RESPONSE_METADATA_V056: request metadata + response classification.\n"
    "typedef void *(*JCG56SendWebRequestFn)(void *self, const void *method);\n"
    "typedef JCG5Il2CppString *(*JCG56GetStringFn)(void *self, const void *method);\n"
    "typedef int64_t (*JCG56GetResponseCodeFn)(void *self, const void *method);\n"
    "typedef struct { void *klass; void *monitor; void *m_Ptr; void *m_DownloadHandler; } JCG56UnityWebRequestObject;\n"
    "static JCG56SendWebRequestFn gJCG56OrigSendWebRequest;\n"
    "static JCG56GetStringFn gJCG56GetUrl;\n"
    "static JCG56GetStringFn gJCG56GetMethod;\n"
    "static JCG56GetResponseCodeFn gJCG56GetResponseCode;\n"
    "static NSMutableDictionary *gJCG56RequestByHandler;\n"
    "static NSString *gJCG56RequestTracePath;\n"
    "static BOOL gJCG56MetadataHookReady = NO;\n"
    "static unsigned long long gJCG56RequestsTracked = 0;\n"
    "static unsigned long long gJCG56MetadataMatched = 0;\n"
    "static unsigned long long gJCG56HotUpdateDetected = 0;\n"
    "static unsigned long long gJCG56NoticeDetected = 0;\n",
    "metadata globals",
)

rep(
    "#define JCG54_OBSERVER_MAX_BYTES (256ULL * 1024ULL * 1024ULL)\n",
    "#define JCG54_OBSERVER_MAX_BYTES (256ULL * 1024ULL * 1024ULL)\n"
    "#define JCG56_SEND_WEB_REQUEST_RVA 0x0ECFD938ULL\n"
    "#define JCG56_GET_METHOD_RVA 0x0ECFDD54ULL\n"
    "#define JCG56_GET_URL_RVA 0x0ECFE328ULL\n"
    "#define JCG56_GET_RESPONSE_CODE_RVA 0x0ECFE0C4ULL\n",
    "metadata RVAs",
)

helpers = r'''
static NSString *JCG56NSStringFromIl2Cpp(JCG5Il2CppString *s) {
    if (!s || s->length <= 0 || s->length > 1024 * 1024) return @"";
    return [[[NSString alloc] initWithCharacters:s->chars length:(NSUInteger)s->length] autorelease] ?: @"";
}

static NSDictionary *JCG56CopyRequestMetaForHandler(void *handler) {
    if (!handler) return nil;
    NSValue *key = [NSValue valueWithPointer:handler];
    pthread_mutex_lock(&gJCG5StateLock);
    NSDictionary *ctx = [[gJCG56RequestByHandler objectForKey:key] retain];
    pthread_mutex_unlock(&gJCG5StateLock);
    return ctx;
}

static NSString *JCG56HotUpdateVersion(NSArray *downurls) {
    if (![downurls isKindOfClass:[NSArray class]] || downurls.count == 0) return @"";
    id first = downurls[0];
    if (![first isKindOfClass:[NSDictionary class]]) return @"";
    NSString *u = first[@"packurl"];
    if (![u isKindOfClass:[NSString class]] || !u.length) return @"";
    NSString *name = u.lastPathComponent ?: @"";
    NSRange r = [name rangeOfString:@"_"];
    if (r.location == NSNotFound || r.location == 0) return @"";
    return [name substringToIndex:r.location] ?: @"";
}

static NSDictionary *JCG56ClassifyJSONObject(id obj) {
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithObject:@"json" forKey:@"classification"];
    if (![obj isKindOfClass:[NSDictionary class]]) return out;
    NSDictionary *d = (NSDictionary *)obj;

    NSArray *downurls = d[@"downurls"];
    NSString *packverurl = d[@"packverurl"];
    if ([downurls isKindOfClass:[NSArray class]] &&
        [packverurl isKindOfClass:[NSString class]] &&
        (downurls.count || packverurl.length)) {
        out[@"classification"] = @"hot_update_config";
        out[@"hot_update_package_count"] = @(downurls.count);
        if (packverurl.length) out[@"packverurl"] = packverurl;
        NSString *ver = JCG56HotUpdateVersion(downurls);
        if (ver.length) out[@"hot_update_version"] = ver;
        return out;
    }

    NSArray *notics = d[@"notics"];
    if ([notics isKindOfClass:[NSArray class]]) {
        out[@"classification"] = @"notice_config";
        out[@"notice_count"] = @(notics.count);
    }
    return out;
}

static void *JCG56HookSendWebRequest(void *self, const void *methodInfo) {
    void *handler = NULL;
    NSString *url = @"";
    NSString *httpMethod = @"";
    if (self) {
        JCG56UnityWebRequestObject *req = (JCG56UnityWebRequestObject *)self;
        handler = req->m_DownloadHandler;
        if (gJCG56GetUrl) url = JCG56NSStringFromIl2Cpp(gJCG56GetUrl(self, NULL));
        if (gJCG56GetMethod) httpMethod = JCG56NSStringFromIl2Cpp(gJCG56GetMethod(self, NULL));
    }

    if (handler) {
        NSDictionary *ctx = [[NSDictionary alloc] initWithObjectsAndKeys:
                             [NSValue valueWithPointer:self], @"request",
                             (url ?: @""), @"url",
                             (httpMethod ?: @""), @"method",
                             nil];
        NSValue *key = [NSValue valueWithPointer:handler];
        pthread_mutex_lock(&gJCG5StateLock);
        if (!gJCG56RequestByHandler) gJCG56RequestByHandler = [[NSMutableDictionary alloc] init];
        [gJCG56RequestByHandler setObject:ctx forKey:key];
        gJCG56RequestsTracked++;
        pthread_mutex_unlock(&gJCG5StateLock);
        [ctx release];
    }

    return gJCG56OrigSendWebRequest ? gJCG56OrigSendWebRequest(self, methodInfo) : NULL;
}

static BOOL JCG56InstallRequestMetadata(void *unityExport) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL already = gJCG56MetadataHookReady;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (already) return YES;
    if (!unityExport) return NO;

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr(unityExport, &info) == 0 || !info.dli_fbase) return NO;
    if (!JCG54MachOUUIDMatches(info.dli_fbase)) {
        JCG5Log(@"RESPONSE-METADATA target UUID mismatch; metadata hook disabled");
        return NO;
    }

    uintptr_t base = (uintptr_t)info.dli_fbase;
    void *sendTarget = (void *)(base + (uintptr_t)JCG56_SEND_WEB_REQUEST_RVA);
    void *urlTarget = (void *)(base + (uintptr_t)JCG56_GET_URL_RVA);
    void *methodTarget = (void *)(base + (uintptr_t)JCG56_GET_METHOD_RVA);
    void *codeTarget = (void *)(base + (uintptr_t)JCG56_GET_RESPONSE_CODE_RVA);

    void *targets[] = { sendTarget, urlTarget, methodTarget, codeTarget };
    for (NSUInteger i = 0; i < sizeof(targets)/sizeof(targets[0]); i++) {
        Dl_info ti; memset(&ti, 0, sizeof(ti));
        if (dladdr(targets[i], &ti) == 0 || ti.dli_fbase != info.dli_fbase) {
            JCG5Log(@"RESPONSE-METADATA target address validation failed; metadata hook disabled");
            return NO;
        }
    }

    gJCG56GetUrl = (JCG56GetStringFn)urlTarget;
    gJCG56GetMethod = (JCG56GetStringFn)methodTarget;
    gJCG56GetResponseCode = (JCG56GetResponseCodeFn)codeTarget;

    BOOL ok = JCG5Hook(sendTarget,
                       (void *)JCG56HookSendWebRequest,
                       (void **)&gJCG56OrigSendWebRequest);
    if (ok) {
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG56MetadataHookReady = YES;
        if (!gJCG56RequestByHandler) gJCG56RequestByHandler = [[NSMutableDictionary alloc] init];
        pthread_mutex_unlock(&gJCG5StateLock);
        JCG5Log([NSString stringWithFormat:
                 @"RESPONSE-METADATA ready send=0x%llX url=0x%llX method=0x%llX code=0x%llX",
                 (unsigned long long)JCG56_SEND_WEB_REQUEST_RVA,
                 (unsigned long long)JCG56_GET_URL_RVA,
                 (unsigned long long)JCG56_GET_METHOD_RVA,
                 (unsigned long long)JCG56_GET_RESPONSE_CODE_RVA]);
    } else {
        JCG5Log(@"RESPONSE-METADATA hook failed");
    }
    return ok;
}

'''
rep(
    "static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {\n",
    helpers + "static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {\n",
    "metadata helpers",
)

rep(
    "static void JCG55QueueValidatedResponse(NSData *body, unsigned long long hit) {\n"
    "    if (!body.length || !gJCG5CaptureQueue) return;\n"
    "    NSData *snapshot = [body retain];\n"
    "    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {\n",
    "static void JCG55QueueValidatedResponse(NSData *body, unsigned long long hit, NSDictionary *requestMeta) {\n"
    "    if (!body.length || !gJCG5CaptureQueue) return;\n"
    "    NSData *snapshot = [body retain];\n"
    "    NSDictionary *metaSnapshot = [[requestMeta ?: @{} copy] autorelease];\n"
    "    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {\n",
    "response queue metadata signature",
)

rep(
    "    if (!gJCG55ResponseManifestPath) gJCG55ResponseManifestPath = [[gJCG5Root stringByAppendingPathComponent:@\"runtime_response_manifest.jsonl\"] retain];\n"
    "    JCG5EnsureDir(gJCG55ResponseDir);\n",
    "    if (!gJCG55ResponseManifestPath) gJCG55ResponseManifestPath = [[gJCG5Root stringByAppendingPathComponent:@\"runtime_response_manifest.jsonl\"] retain];\n"
    "    if (!gJCG56RequestTracePath) gJCG56RequestTracePath = [[gJCG5Root stringByAppendingPathComponent:@\"runtime_response_requests.jsonl\"] retain];\n"
    "    JCG5EnsureDir(gJCG55ResponseDir);\n",
    "request trace path",
)

old_record = r'''        NSString *file = [NSString stringWithFormat:@"%@.json", md5];
        NSString *path = [gJCG55ResponseDir stringByAppendingPathComponent:file];
        BOOL duplicate = [gJCG55ResponseMD5s containsObject:md5] ||
                         [gJCG55ResponseSHA256s containsObject:sha] ||
                         [[NSFileManager defaultManager] fileExistsAtPath:path];
        if (duplicate) {
            if (![gJCG55ResponseMD5s containsObject:md5]) [gJCG55ResponseMD5s addObject:md5];
            if (![gJCG55ResponseSHA256s containsObject:sha]) [gJCG55ResponseSHA256s addObject:sha];
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseSkipped++;
            gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [@"完整JSON｜重复跳过" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            [md5 release]; [sha release]; [snapshot release];
            return;
        }

        BOOL wrote = [snapshot writeToFile:path atomically:YES];
        if (wrote) {
            [gJCG55ResponseMD5s addObject:md5];
            [gJCG55ResponseSHA256s addObject:sha];
            NSDictionary *record = @{
                @"schema": @1,
                @"source": @"UnityWebRequest.DownloadHandlerBuffer.GetData",
                @"rva": @"0x0ECFC0C0",
                @"hit": @(hit),
                @"file": file,
                @"md5": md5,
                @"sha256": sha,
                @"bytes": @(snapshot.length),
                @"time": @([[NSDate date] timeIntervalSince1970])
            };
            JCG55AppendJSONLine(gJCG55ResponseManifestPath, record);
            JCG55AppendJSONLine(gJCG55ResponseCachePath, record);
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseSaved++;
            gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [@"完整JSON｜已保存" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE saved hit=%llu bytes=%lu file=%@ md5=%@ sha256=%@",
                     hit, (unsigned long)snapshot.length, file, md5, sha]);
        } else {
'''
new_record = r'''        NSString *file = [NSString stringWithFormat:@"%@.json", md5];
        NSString *path = [gJCG55ResponseDir stringByAppendingPathComponent:file];

        NSDictionary *classInfo = JCG56ClassifyJSONObject(obj);
        NSString *classification = classInfo[@"classification"] ?: @"json";
        NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:@{
            @"schema": @2,
            @"source": @"UnityWebRequest.DownloadHandlerBuffer.GetData",
            @"rva": @"0x0ECFC0C0",
            @"hit": @(hit),
            @"file": file,
            @"md5": md5,
            @"sha256": sha,
            @"bytes": @(snapshot.length),
            @"time": @([[NSDate date] timeIntervalSince1970])
        }];
        if (metaSnapshot.count) [record addEntriesFromDictionary:metaSnapshot];
        if (classInfo.count) [record addEntriesFromDictionary:classInfo];

        if ([classification isEqualToString:@"hot_update_config"]) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG56HotUpdateDetected++;
            pthread_mutex_unlock(&gJCG5StateLock);
        } else if ([classification isEqualToString:@"notice_config"]) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG56NoticeDetected++;
            pthread_mutex_unlock(&gJCG5StateLock);
        }

        BOOL duplicate = [gJCG55ResponseMD5s containsObject:md5] ||
                         [gJCG55ResponseSHA256s containsObject:sha] ||
                         [[NSFileManager defaultManager] fileExistsAtPath:path];
        record[@"duplicate"] = @(duplicate);
        record[@"saved"] = @(!duplicate);
        JCG55AppendJSONLine(gJCG56RequestTracePath, record);

        if (duplicate) {
            if (![gJCG55ResponseMD5s containsObject:md5]) [gJCG55ResponseMD5s addObject:md5];
            if (![gJCG55ResponseSHA256s containsObject:sha]) [gJCG55ResponseSHA256s addObject:sha];
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseSkipped++;
            gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [[NSString stringWithFormat:@"%@｜重复跳过", classification] copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            [md5 release]; [sha release]; [snapshot release];
            return;
        }

        BOOL wrote = [snapshot writeToFile:path atomically:YES];
        if (wrote) {
            [gJCG55ResponseMD5s addObject:md5];
            [gJCG55ResponseSHA256s addObject:sha];
            JCG55AppendJSONLine(gJCG55ResponseManifestPath, record);
            JCG55AppendJSONLine(gJCG55ResponseCachePath, record);
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseSaved++;
            gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [[NSString stringWithFormat:@"%@｜已保存", classification] copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE saved hit=%llu bytes=%lu type=%@ status=%@ method=%@ url=%@ file=%@ md5=%@ sha256=%@",
                     hit, (unsigned long)snapshot.length, classification,
                     record[@"http_status"] ?: @0,
                     record[@"method"] ?: @"",
                     record[@"url"] ?: @"",
                     file, md5, sha]);
        } else {
'''
rep(old_record, new_record, "manifest enrichment and request trace")

old_queue_call = r'''    if (jsonLike) {
        // The Il2Cpp byte[] belongs to the returned managed object. Copy only
        // JSON-looking bodies before leaving this call, then validate and save
        // asynchronously on the existing v0.5.2 serial capture queue.
        NSData *body = [NSData dataWithBytes:a->vector length:len];
        JCG55QueueValidatedResponse(body, hit);
    }
'''
new_queue_call = r'''    if (jsonLike) {
        NSDictionary *ctx = JCG56CopyRequestMetaForHandler(self);
        NSMutableDictionary *meta = [NSMutableDictionary dictionary];
        if (ctx[@"url"]) meta[@"url"] = ctx[@"url"];
        if (ctx[@"method"]) meta[@"method"] = ctx[@"method"];
        NSValue *requestValue = ctx[@"request"];
        void *request = requestValue ? [requestValue pointerValue] : NULL;
        int64_t status = (request && gJCG56GetResponseCode) ? gJCG56GetResponseCode(request, NULL) : 0;
        meta[@"http_status"] = @(status);
        meta[@"metadata_matched"] = @(ctx != nil);
        if (ctx) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG56MetadataMatched++;
            pthread_mutex_unlock(&gJCG5StateLock);
        }

        // The Il2Cpp byte[] belongs to the returned managed object. Copy only
        // JSON-looking bodies before leaving this call, then validate and save
        // asynchronously on the existing v0.5.2 serial capture queue.
        NSData *body = [NSData dataWithBytes:a->vector length:len];
        JCG55QueueValidatedResponse(body, hit, meta);
        JCG5Log([NSString stringWithFormat:@"RESPONSE-METADATA hit=%llu status=%lld method=%@ url=%@ matched=%d",
                 hit, (long long)status, meta[@"method"] ?: @"", meta[@"url"] ?: @"", ctx != nil]);
        [ctx release];
    }
'''
rep(old_queue_call, new_queue_call, "response metadata lookup")

old_install = r'''    void *anchor=pTolua?pTolua:pLuaLX;
    BOOL c=anchor?JCG54InstallResponseObserver(anchor):NO;
    gJCG5HooksReady=a||b;
    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@"HOOK ready tolua=%d luaL_loadbufferx=%d response_observer=%d",a,b,c]);
'''
new_install = r'''    void *anchor=pTolua?pTolua:pLuaLX;
    BOOL c=anchor?JCG54InstallResponseObserver(anchor):NO;
    // Keep all MSHookFunction installs serialized in this same call.
    BOOL d=anchor?JCG56InstallRequestMetadata(anchor):NO;
    gJCG5HooksReady=a||b;
    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@"HOOK ready tolua=%d luaL_loadbufferx=%d response_observer=%d response_metadata=%d",a,b,c,d]);
'''
rep(old_install, new_install, "serialized metadata hook install")

old_status = r'''    unsigned long long saved = gJCG55ResponseSaved;
    unsigned long long skipped = gJCG55ResponseSkipped;
    unsigned long long invalid = gJCG55ResponseInvalid;
    unsigned long long cache = gJCG55ResponseCacheLoaded;
    NSString *state = [[(gJCG54ObserverLastState ?: @"暂无") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return [NSString stringWithFormat:@"目标：%@ Hook：%@ 命中%llu JSON%llu\n保存%llu 跳过%llu 失败%llu 缓存%llu｜%lluB %@",
            matched ? @"匹配 ✅" : @"未匹配",
            ready ? @"就绪" : @"等待",
            hits, json, saved, skipped, invalid, cache, bytes, state];
'''
new_status = r'''    unsigned long long saved = gJCG55ResponseSaved;
    unsigned long long skipped = gJCG55ResponseSkipped;
    unsigned long long invalid = gJCG55ResponseInvalid;
    unsigned long long cache = gJCG55ResponseCacheLoaded;
    unsigned long long tracked = gJCG56RequestsTracked;
    unsigned long long matchedMeta = gJCG56MetadataMatched;
    unsigned long long hot = gJCG56HotUpdateDetected;
    unsigned long long notices = gJCG56NoticeDetected;
    NSString *state = [[(gJCG54ObserverLastState ?: @"暂无") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return [NSString stringWithFormat:@"目标：%@ Hook：%@ 命中%llu JSON%llu\n保存%llu 跳过%llu 失败%llu 缓存%llu｜元数据%llu/%llu 热更%llu 公告%llu\n%lluB %@",
            matched ? @"匹配 ✅" : @"未匹配",
            ready ? @"就绪" : @"等待",
            hits, json, saved, skipped, invalid, cache,
            matchedMeta, tracked, hot, notices, bytes, state];
'''
rep(old_status, new_status, "metadata UI counters")

p.write_text(s, encoding="utf-8")
print("applied v0.5.6 request metadata + response classification")
