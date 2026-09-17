#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_UNITY_ALL_JSON_V057"
if MARKER in s:
    print("v0.5.7 Unity backend JSON patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_RUNTIME_CACHE_V052",
    "JCG5_RESPONSE_OBSERVER_V054",
    "JCG5_RESPONSE_CAPTURE_V055",
    "JCG5_RESPONSE_METADATA_V056",
    "JCG5_RESPONSE_METADATA_V056_HARDENED",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.5.7 patch anchor missing: {label}")
    s = s.replace(old, new, 1)


rep(
    "static NSDictionary *JCG56ClassifyJSONObject(id obj);\n",
    "static NSDictionary *JCG56ClassifyJSONObject(id obj);\n"
    "// JCG5_UNITY_ALL_JSON_V057: NSURLSession delegate body capture for all UnityWebRequest handlers.\n"
    "typedef void (*JCG57DidReceiveDataFn)(id selfObj, SEL cmd, NSURLSession *session, NSURLSessionDataTask *task, NSData *data);\n"
    "typedef void (*JCG57DidCompleteFn)(id selfObj, SEL cmd, NSURLSession *session, NSURLSessionTask *task, NSError *error);\n"
    "static JCG57DidReceiveDataFn gJCG57OrigDidReceiveData;\n"
    "static JCG57DidCompleteFn gJCG57OrigDidComplete;\n"
    "static NSMutableDictionary *gJCG57BackendStates;\n"
    "static NSMutableSet *gJCG57AcceptedTasks;\n"
    "static NSMutableSet *gJCG57RejectedTasks;\n"
    "static NSMutableSet *gJCG57BackendMD5s;\n"
    "static BOOL gJCG57BackendHookReady = NO;\n"
    "static unsigned long long gJCG57BackendCandidates = 0;\n"
    "static unsigned long long gJCG57BackendCompleted = 0;\n"
    "static unsigned long long gJCG57BackendOverflow = 0;\n"
    "static unsigned long long gJCG57BackendRejected = 0;\n",
    "v0.5.7 globals",
)

rep(
    "#define JCG56_GET_RESPONSE_CODE_RVA 0x0ECFE0C4ULL\n",
    "#define JCG56_GET_RESPONSE_CODE_RVA 0x0ECFE0C4ULL\n"
    "#define JCG57_UWR_DELEGATE_DATA_RVA 0x00013E88ULL\n"
    "#define JCG57_UWR_DELEGATE_COMPLETE_RVA 0x00014A1CULL\n"
    "#define JCG57_BACKEND_JSON_MAX_BYTES (64ULL * 1024ULL * 1024ULL)\n",
    "v0.5.7 RVAs",
)

rep(
    "        id obj = [NSJSONSerialization JSONObjectWithData:snapshot options:0 error:&jsonError];\n"
    "        BOOL complete = [obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]];\n",
    "        id obj = [NSJSONSerialization JSONObjectWithData:snapshot options:NSJSONReadingAllowFragments error:&jsonError];\n"
    "        BOOL complete = (obj != nil);\n",
    "allow JSON fragments",
)

rep(
    "    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithObject:@\"json\" forKey:@\"classification\"];\n"
    "    if (![obj isKindOfClass:[NSDictionary class]]) return out;\n",
    "    NSString *baseClass = ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) ? @\"json\" : @\"json_scalar\";\n"
    "    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithObject:baseClass forKey:@\"classification\"];\n"
    "    if (![obj isKindOfClass:[NSDictionary class]]) return out;\n",
    "classify scalar JSON",
)

helpers = r'''
static NSNumber *JCG57TaskKey(NSURLSessionTask *task) {
    if (!task) return nil;
    return [NSNumber numberWithUnsignedInteger:task.taskIdentifier];
}

static BOOL JCG57ResponseSaysJSON(NSURLResponse *response) {
    NSString *mime = [response.MIMEType lowercaseString];
    if ([mime rangeOfString:@"json"].location != NSNotFound) return YES;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
        id ct = headers[@"Content-Type"] ?: headers[@"content-type"];
        if ([ct isKindOfClass:[NSString class]] &&
            [[(NSString *)ct lowercaseString] rangeOfString:@"json"].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL JCG57ChunkStartsJSON(NSData *data, BOOL contentTypeJSON, BOOL *onlyWhitespace) {
    if (onlyWhitespace) *onlyWhitespace = NO;
    if (!data.length) return NO;
    const uint8_t *p = data.bytes;
    NSUInteger n = data.length;
    NSUInteger i = 0;
    if (n >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) i = 3;
    for (; i < n && i < 512; i++) {
        uint8_t c = p[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        if (c == '{' || c == '[') return YES;
        if (contentTypeJSON) {
            if (c == '"' || c == '-' || (c >= '0' && c <= '9') ||
                c == 't' || c == 'f' || c == 'n') return YES;
        }
        return NO;
    }
    if (onlyWhitespace) *onlyWhitespace = YES;
    return NO;
}

static NSMutableDictionary *JCG57NewBackendState(NSURLSessionTask *task, NSData *firstChunk) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    NSMutableData *body = [NSMutableData dataWithCapacity:MIN((NSUInteger)(firstChunk.length * 2), (NSUInteger)(1024 * 1024))];
    if (firstChunk.length) [body appendData:firstChunk];
    state[@"body"] = body;

    NSURLRequest *req = task.currentRequest ?: task.originalRequest;
    NSString *url = req.URL.absoluteString ?: @"";
    NSString *method = req.HTTPMethod ?: @"";
    NSURLResponse *response = task.response;
    NSString *mime = response.MIMEType ?: @"";
    NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;

    state[@"url"] = url;
    state[@"method"] = method;
    state[@"content_type"] = mime;
    state[@"http_status"] = @(status);
    state[@"backend_task_id"] = @(task.taskIdentifier);
    state[@"source"] = @"UnityWebRequestDelegate.URLSession:dataTask:didReceiveData:";
    state[@"rva"] = @"0x00013E88";
    state[@"capture_layer"] = @"unity_nsurlsession_delegate";
    state[@"metadata_matched"] = @YES;
    return state;
}

static void JCG57HookDidReceiveData(id selfObj, SEL cmd, NSURLSession *session, NSURLSessionDataTask *task, NSData *data) {
    if (gJCG57OrigDidReceiveData) gJCG57OrigDidReceiveData(selfObj, cmd, session, task, data);

    BOOL enabled = NO;
    pthread_mutex_lock(&gJCG5StateLock);
    enabled = gJCG5CaptureEnabled;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (!enabled || !task || !data.length || !gJCG5CaptureQueue) return;

    NSNumber *key = JCG57TaskKey(task);
    if (!key) return;

    BOOL accepted = NO;
    BOOL rejected = NO;
    pthread_mutex_lock(&gJCG5StateLock);
    accepted = [gJCG57AcceptedTasks containsObject:key];
    rejected = [gJCG57RejectedTasks containsObject:key];
    pthread_mutex_unlock(&gJCG5StateLock);

    if (!accepted && !rejected) {
        BOOL whitespaceOnly = NO;
        BOOL candidate = JCG57ChunkStartsJSON(data, JCG57ResponseSaysJSON(task.response), &whitespaceOnly);
        if (!candidate && whitespaceOnly) return;

        pthread_mutex_lock(&gJCG5StateLock);
        if (!gJCG57AcceptedTasks) gJCG57AcceptedTasks = [[NSMutableSet alloc] init];
        if (!gJCG57RejectedTasks) gJCG57RejectedTasks = [[NSMutableSet alloc] init];
        if (candidate) {
            [gJCG57AcceptedTasks addObject:key];
            gJCG57BackendCandidates++;
            accepted = YES;
        } else {
            [gJCG57RejectedTasks addObject:key];
            gJCG57BackendRejected++;
            rejected = YES;
        }
        pthread_mutex_unlock(&gJCG5StateLock);
        if (rejected) return;
    } else if (rejected) {
        return;
    }

    NSData *chunk = [data retain];
    NSURLSessionDataTask *taskRef = [task retain];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        NSNumber *qkey = JCG57TaskKey(taskRef);
        if (!gJCG57BackendStates) gJCG57BackendStates = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *state = [gJCG57BackendStates objectForKey:qkey];
        if (!state) {
            state = JCG57NewBackendState(taskRef, chunk);
            [gJCG57BackendStates setObject:state forKey:qkey];
        } else {
            NSMutableData *body = state[@"body"];
            unsigned long long next = (unsigned long long)body.length + (unsigned long long)chunk.length;
            if (next > JCG57_BACKEND_JSON_MAX_BYTES) {
                [gJCG57BackendStates removeObjectForKey:qkey];
                pthread_mutex_lock(&gJCG5StateLock);
                [gJCG57AcceptedTasks removeObject:qkey];
                [gJCG57RejectedTasks addObject:qkey];
                gJCG57BackendOverflow++;
                pthread_mutex_unlock(&gJCG5StateLock);
                JCG5Log([NSString stringWithFormat:@"UWR-BACKEND overflow task=%lu bytes>%llu url=%@",
                         (unsigned long)taskRef.taskIdentifier,
                         (unsigned long long)JCG57_BACKEND_JSON_MAX_BYTES,
                         taskRef.currentRequest.URL.absoluteString ?: taskRef.originalRequest.URL.absoluteString ?: @""]);
                [taskRef release];
                [chunk release];
                return;
            }
            [body appendData:chunk];
        }

        if ([state[@"body"] length] == chunk.length) {
            JCG5Log([NSString stringWithFormat:@"UWR-BACKEND candidate task=%lu status=%@ method=%@ url=%@ mime=%@",
                     (unsigned long)taskRef.taskIdentifier,
                     state[@"http_status"] ?: @0,
                     state[@"method"] ?: @"",
                     state[@"url"] ?: @"",
                     state[@"content_type"] ?: @""]);
        }
        [taskRef release];
        [chunk release];
    }});
}

static void JCG57HookDidComplete(id selfObj, SEL cmd, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
    if (!task) {
        if (gJCG57OrigDidComplete) gJCG57OrigDidComplete(selfObj, cmd, session, task, error);
        return;
    }

    NSNumber *key = JCG57TaskKey(task);
    BOOL accepted = NO;
    pthread_mutex_lock(&gJCG5StateLock);
    accepted = [gJCG57AcceptedTasks containsObject:key];
    pthread_mutex_unlock(&gJCG5StateLock);

    // Retain before the original callback in case Unity releases its last
    // native/request references while handling completion.
    NSURLSessionTask *taskRef = accepted ? [task retain] : nil;
    NSError *errorRef = accepted ? [error retain] : nil;

    if (gJCG57OrigDidComplete) gJCG57OrigDidComplete(selfObj, cmd, session, task, error);

    pthread_mutex_lock(&gJCG5StateLock);
    [gJCG57AcceptedTasks removeObject:key];
    [gJCG57RejectedTasks removeObject:key];
    pthread_mutex_unlock(&gJCG5StateLock);
    if (!accepted || !gJCG5CaptureQueue) {
        [errorRef release];
        [taskRef release];
        return;
    }

    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        NSNumber *qkey = JCG57TaskKey(taskRef);
        NSMutableDictionary *state = [[gJCG57BackendStates objectForKey:qkey] retain];
        [gJCG57BackendStates removeObjectForKey:qkey];
        if (!state) {
            [errorRef release];
            [taskRef release];
            return;
        }

        NSData *body = [state[@"body"] retain];
        NSURLRequest *req = taskRef.currentRequest ?: taskRef.originalRequest;
        NSURLResponse *resp = taskRef.response;
        if (req.URL.absoluteString.length) state[@"url"] = req.URL.absoluteString;
        if (req.HTTPMethod.length) state[@"method"] = req.HTTPMethod;
        if (resp.MIMEType.length) state[@"content_type"] = resp.MIMEType;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            state[@"http_status"] = @([(NSHTTPURLResponse *)resp statusCode]);
        }
        if (errorRef) {
            state[@"transport_error_domain"] = errorRef.domain ?: @"";
            state[@"transport_error_code"] = @(errorRef.code);
        }
        [state removeObjectForKey:@"body"];

        unsigned long long backendHit = 0;
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG57BackendCompleted++;
        backendHit = gJCG57BackendCompleted;
        pthread_mutex_unlock(&gJCG5StateLock);

        NSString *md5 = JCG5MD5(body).lowercaseString;
        if (md5.length) {
            if (!gJCG57BackendMD5s) gJCG57BackendMD5s = [[NSMutableSet alloc] init];
            [gJCG57BackendMD5s addObject:md5];
        }

        JCG5Log([NSString stringWithFormat:@"UWR-BACKEND complete hit=%llu task=%lu bytes=%lu status=%@ method=%@ url=%@ error=%@",
                 backendHit,
                 (unsigned long)taskRef.taskIdentifier,
                 (unsigned long)body.length,
                 state[@"http_status"] ?: @0,
                 state[@"method"] ?: @"",
                 state[@"url"] ?: @"",
                 errorRef ? errorRef.localizedDescription : @"none"]);

        JCG55QueueValidatedResponse(body, backendHit, state);
        [body release];
        [state release];
        [errorRef release];
        [taskRef release];
    }});
}

static BOOL JCG57InstallUnityBackendJSON(void *unityExport) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL already = gJCG57BackendHookReady;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (already) return YES;
    if (!unityExport) return NO;

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr(unityExport, &info) == 0 || !info.dli_fbase) return NO;
    if (!JCG54MachOUUIDMatches(info.dli_fbase)) {
        JCG5Log(@"UWR-BACKEND target UUID mismatch; disabled");
        return NO;
    }
    if (!NSClassFromString(@"UnityWebRequestDelegate")) {
        JCG5Log(@"UWR-BACKEND UnityWebRequestDelegate missing; disabled");
        return NO;
    }

    uintptr_t base = (uintptr_t)info.dli_fbase;
    void *dataTarget = (void *)(base + (uintptr_t)JCG57_UWR_DELEGATE_DATA_RVA);
    void *completeTarget = (void *)(base + (uintptr_t)JCG57_UWR_DELEGATE_COMPLETE_RVA);
    void *targets[] = { dataTarget, completeTarget };
    for (NSUInteger i = 0; i < 2; i++) {
        Dl_info ti; memset(&ti, 0, sizeof(ti));
        if (dladdr(targets[i], &ti) == 0 || ti.dli_fbase != info.dli_fbase) {
            JCG5Log(@"UWR-BACKEND target address validation failed; disabled");
            return NO;
        }
    }

    // Install completion first. If the data hook fails, completion alone is harmless.
    BOOL b = JCG5Hook(completeTarget,
                      (void *)JCG57HookDidComplete,
                      (void **)&gJCG57OrigDidComplete);
    BOOL a = b ? JCG5Hook(dataTarget,
                          (void *)JCG57HookDidReceiveData,
                          (void **)&gJCG57OrigDidReceiveData) : NO;
    BOOL ok = a && b;
    if (ok) {
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG57BackendHookReady = YES;
        if (!gJCG57AcceptedTasks) gJCG57AcceptedTasks = [[NSMutableSet alloc] init];
        if (!gJCG57RejectedTasks) gJCG57RejectedTasks = [[NSMutableSet alloc] init];
        pthread_mutex_unlock(&gJCG5StateLock);
        JCG5Log([NSString stringWithFormat:@"UWR-BACKEND ready data=0x%llX complete=0x%llX max=%llu",
                 (unsigned long long)JCG57_UWR_DELEGATE_DATA_RVA,
                 (unsigned long long)JCG57_UWR_DELEGATE_COMPLETE_RVA,
                 (unsigned long long)JCG57_BACKEND_JSON_MAX_BYTES]);
    } else {
        JCG5Log([NSString stringWithFormat:@"UWR-BACKEND hook failed data=%d complete=%d", a, b]);
    }
    return ok;
}

'''

rep(
    "static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {\n",
    helpers + "static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {\n",
    "insert Unity backend capture",
)

rep(
    "    BOOL d=anchor?JCG56InstallRequestMetadata(anchor):NO;\n"
    "    gJCG5HooksReady=a||b;\n"
    "    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@\"HOOK ready tolua=%d luaL_loadbufferx=%d response_observer=%d response_metadata=%d\",a,b,c,d]);\n",
    "    BOOL d=anchor?JCG56InstallRequestMetadata(anchor):NO;\n"
    "    // v0.5.7: still serialized in this same install call; no new polling queue.\n"
    "    BOOL e=anchor?JCG57InstallUnityBackendJSON(anchor):NO;\n"
    "    gJCG5HooksReady=a||b;\n"
    "    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@\"HOOK ready tolua=%d luaL_loadbufferx=%d response_observer=%d response_metadata=%d uwr_backend=%d\",a,b,c,d,e]);\n",
    "serialized Unity backend hook install",
)

rep(
    "        if (duplicate) {\n"
    "            record[@\"saved\"] = @NO;\n"
    "            JCG55AppendJSONLine(gJCG56RequestTracePath, record);\n",
    "        if (duplicate) {\n"
    "            record[@\"saved\"] = @NO;\n"
    "            BOOL backendAlreadyTraced = [record[@\"source\"] isEqualToString:@\"UnityWebRequest.DownloadHandlerBuffer.GetData\"] &&\n"
    "                                        [gJCG57BackendMD5s containsObject:md5];\n"
    "            if (!backendAlreadyTraced) JCG55AppendJSONLine(gJCG56RequestTracePath, record);\n",
    "suppress backend/GetData duplicate trace",
)

rep(
    "    unsigned long long notices = gJCG56NoticeDetected;\n"
    "    NSString *state = [[(gJCG54ObserverLastState ?: @\"暂无\") copy] autorelease];\n",
    "    unsigned long long notices = gJCG56NoticeDetected;\n"
    "    unsigned long long backendCandidates = gJCG57BackendCandidates;\n"
    "    unsigned long long backendCompleted = gJCG57BackendCompleted;\n"
    "    unsigned long long backendOverflow = gJCG57BackendOverflow;\n"
    "    NSString *state = [[(gJCG54ObserverLastState ?: @\"暂无\") copy] autorelease];\n",
    "backend UI counters vars",
)

rep(
    "    return [NSString stringWithFormat:@\"目标：%@ Hook：%@ 命中%llu JSON%llu\\n保存%llu 跳过%llu 失败%llu 缓存%llu｜元数据%llu/%llu 热更%llu 公告%llu\\n%lluB %@\",\n"
    "            matched ? @\"匹配 ✅\" : @\"未匹配\",\n"
    "            ready ? @\"就绪\" : @\"等待\",\n"
    "            hits, json, saved, skipped, invalid, cache,\n"
    "            matchedMeta, tracked, hot, notices, bytes, state];\n",
    "    return [NSString stringWithFormat:@\"目标：%@ Hook：%@ 命中%llu JSON%llu\\n保存%llu 跳过%llu 失败%llu 缓存%llu｜元数据%llu/%llu 热更%llu 公告%llu\\nUWR全层%llu/%llu 溢出%llu｜%lluB %@\",\n"
    "            matched ? @\"匹配 ✅\" : @\"未匹配\",\n"
    "            ready ? @\"就绪\" : @\"等待\",\n"
    "            hits, json, saved, skipped, invalid, cache,\n"
    "            matchedMeta, tracked, hot, notices,\n"
    "            backendCompleted, backendCandidates, backendOverflow, bytes, state];\n",
    "backend UI status",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.7 all-UnityWebRequest JSON backend capture")
