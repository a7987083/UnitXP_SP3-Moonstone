#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_NETWORK_COVERAGE_V059"
if MARKER in s:
    print("v0.5.9 network coverage patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_RUNTIME_CACHE_V052",
    "JCG5_RESPONSE_OBSERVER_V054",
    "JCG5_RESPONSE_CAPTURE_V055",
    "JCG5_RESPONSE_METADATA_V056",
    "JCG5_RESPONSE_METADATA_V056_HARDENED",
    "JCG5_UNITY_ALL_JSON_V057",
    "JCG5_UNITY_ALL_JSON_V057_COMPILE_COMPAT",
    "JCG5_SOCKET_HTTP_JSON_V058",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.5.9 patch anchor missing: {label}")
    s = s.replace(old, new, 1)


coverage = r'''
// JCG5_NETWORK_COVERAGE_V059
// Session-scoped coverage accounting across the two real-device-proven network
// paths: UnityWebRequest/NSURLSession and SocketTCP/protobuf post-decrypt body.
// This adds NO native hook, constructor, TLS/TLV, or polling queue.
static NSString *gJCG59CoveragePath;
static NSString *gJCG59CoverageSessionID;
static NSTimeInterval gJCG59CoverageStartedAt = 0;
static NSMutableDictionary *gJCG59CoverageEndpoints;
static NSMutableDictionary *gJCG59CoverageURLs;
static BOOL gJCG59CoverageWriteScheduled = NO;
static unsigned long long gJCG59RequestsTotal = 0;
static unsigned long long gJCG59ResponsesTotal = 0;
static unsigned long long gJCG59UnityRequests = 0;
static unsigned long long gJCG59SocketRequests = 0;
static unsigned long long gJCG59JSONResponses = 0;
static unsigned long long gJCG59NonJSONResponses = 0;
static unsigned long long gJCG59UnknownResponses = 0;
static unsigned long long gJCG59SocketDecryptTrueRequests = 0;
static unsigned long long gJCG59SocketDecryptFalseRequests = 0;
static unsigned long long gJCG59SocketDecryptTrueJSON = 0;
static unsigned long long gJCG59SocketDecryptFalseJSON = 0;
static unsigned long long gJCG59JSONBytes = 0;
static unsigned long long gJCG59NonJSONBytes = 0;

static NSString *JCG59EndpointKey(NSString *url, NSString *method) {
    NSString *u = url ?: @"";
    NSString *m = method.length ? [method uppercaseString] : @"UNKNOWN";
    NSURLComponents *c = [NSURLComponents componentsWithString:u];
    if (c && c.scheme.length && c.host.length) {
        NSString *path = c.path.length ? c.path : @"/";
        NSNumber *port = c.port;
        NSString *authority = port ? [NSString stringWithFormat:@"%@:%@", c.host.lowercaseString, port] : c.host.lowercaseString;
        return [NSString stringWithFormat:@"%@ %@://%@%@", m, c.scheme.lowercaseString, authority, path];
    }
    return [NSString stringWithFormat:@"%@ %@", m, u.length ? u : @"(no-url)"];
}

static NSMutableDictionary *JCG59MutableEntry(NSMutableDictionary *table, NSString *key, NSDictionary *meta) {
    if (!table || !key.length) return nil;
    NSMutableDictionary *e = [table objectForKey:key];
    if (!e) {
        e = [NSMutableDictionary dictionary];
        e[@"key"] = key;
        e[@"method"] = meta[@"method"] ?: @"";
        e[@"source"] = meta[@"source"] ?: @"";
        e[@"capture_layer"] = meta[@"capture_layer"] ?: @"";
        e[@"first_seen"] = @([[NSDate date] timeIntervalSince1970]);
        e[@"request_count"] = @0;
        e[@"response_count"] = @0;
        e[@"json_count"] = @0;
        e[@"non_json_count"] = @0;
        e[@"unknown_count"] = @0;
        e[@"json_bytes"] = @0;
        e[@"non_json_bytes"] = @0;
        e[@"status_codes"] = [NSMutableDictionary dictionary];
        [table setObject:e forKey:key];
    }
    NSString *url = meta[@"url"];
    if (url.length) e[@"example_url"] = url;
    e[@"last_seen"] = @([[NSDate date] timeIntervalSince1970]);
    return e;
}

static void JCG59Bump(NSMutableDictionary *e, NSString *key, unsigned long long delta) {
    if (!e || !key.length) return;
    unsigned long long old = [[e objectForKey:key] unsignedLongLongValue];
    e[key] = @(old + delta);
}

static NSDictionary *JCG59CoverageSnapshot(void) {
    NSMutableArray *endpoints = [NSMutableArray array];
    for (NSString *key in [[gJCG59CoverageEndpoints allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *e = [gJCG59CoverageEndpoints objectForKey:key];
        if (e) [endpoints addObject:e];
    }
    NSMutableArray *urls = [NSMutableArray array];
    for (NSString *key in [[gJCG59CoverageURLs allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *e = [gJCG59CoverageURLs objectForKey:key];
        if (e) [urls addObject:e];
    }
    return @{
        @"schema": @1,
        @"session_id": gJCG59CoverageSessionID ?: @"",
        @"session_start": @(gJCG59CoverageStartedAt),
        @"updated_at": @([[NSDate date] timeIntervalSince1970]),
        @"totals": @{
            @"requests_total": @(gJCG59RequestsTotal),
            @"responses_total": @(gJCG59ResponsesTotal),
            @"unique_urls": @(gJCG59CoverageURLs.count),
            @"unique_endpoints": @(gJCG59CoverageEndpoints.count),
            @"unity_requests": @(gJCG59UnityRequests),
            @"socket_requests": @(gJCG59SocketRequests),
            @"json_responses": @(gJCG59JSONResponses),
            @"non_json_responses": @(gJCG59NonJSONResponses),
            @"unknown_responses": @(gJCG59UnknownResponses),
            @"socket_decrypt_true_requests": @(gJCG59SocketDecryptTrueRequests),
            @"socket_decrypt_false_requests": @(gJCG59SocketDecryptFalseRequests),
            @"socket_decrypt_true_json": @(gJCG59SocketDecryptTrueJSON),
            @"socket_decrypt_false_json": @(gJCG59SocketDecryptFalseJSON),
            @"json_bytes": @(gJCG59JSONBytes),
            @"non_json_bytes": @(gJCG59NonJSONBytes)
        },
        @"endpoints": endpoints,
        @"urls": urls
    };
}

static void JCG59WriteCoverageNow(void) {
    if (!gJCG59CoveragePath.length) return;
    NSDictionary *snapshot = JCG59CoverageSnapshot();
    NSData *d = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
    if (d.length) [d writeToFile:gJCG59CoveragePath options:NSDataWritingAtomic error:nil];
    gJCG59CoverageWriteScheduled = NO;
}

static void JCG59ScheduleCoverageWrite(void) {
    if (!gJCG5CaptureQueue || gJCG59CoverageWriteScheduled) return;
    gJCG59CoverageWriteScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG59WriteCoverageNow();
    }});
}

static void JCG59ResetCoverageSession(void) {
    if (!gJCG59CoveragePath) gJCG59CoveragePath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_network_coverage.json"] retain];
    [gJCG59CoverageSessionID release];
    gJCG59CoverageSessionID = [[[NSUUID UUID] UUIDString] copy];
    gJCG59CoverageStartedAt = [[NSDate date] timeIntervalSince1970];
    [gJCG59CoverageEndpoints release];
    [gJCG59CoverageURLs release];
    gJCG59CoverageEndpoints = [[NSMutableDictionary alloc] init];
    gJCG59CoverageURLs = [[NSMutableDictionary alloc] init];
    gJCG59RequestsTotal = gJCG59ResponsesTotal = 0;
    gJCG59UnityRequests = gJCG59SocketRequests = 0;
    gJCG59JSONResponses = gJCG59NonJSONResponses = gJCG59UnknownResponses = 0;
    gJCG59SocketDecryptTrueRequests = gJCG59SocketDecryptFalseRequests = 0;
    gJCG59SocketDecryptTrueJSON = gJCG59SocketDecryptFalseJSON = 0;
    gJCG59JSONBytes = gJCG59NonJSONBytes = 0;
    gJCG59CoverageWriteScheduled = NO;
    JCG59WriteCoverageNow();
    JCG5Log([NSString stringWithFormat:@"COVERAGE session ready id=%@ path=%@", gJCG59CoverageSessionID, gJCG59CoveragePath]);
}

static void JCG59RecordRequest(NSDictionary *meta) {
    if (!meta || !gJCG5CaptureQueue) return;
    NSDictionary *m = [meta copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        NSString *url = [m objectForKey:@"url"] ?: @"";
        NSString *method = [m objectForKey:@"method"] ?: @"";
        NSString *layer = [m objectForKey:@"capture_layer"] ?: @"";
        NSString *endpointKey = JCG59EndpointKey(url, method);
        NSString *urlKey = [NSString stringWithFormat:@"%@ %@", method.length ? [method uppercaseString] : @"UNKNOWN", url.length ? url : @"(no-url)"];
        NSMutableDictionary *ep = JCG59MutableEntry(gJCG59CoverageEndpoints, endpointKey, m);
        NSMutableDictionary *ue = JCG59MutableEntry(gJCG59CoverageURLs, urlKey, m);
        JCG59Bump(ep, @"request_count", 1);
        JCG59Bump(ue, @"request_count", 1);
        gJCG59RequestsTotal++;
        if ([layer hasPrefix:@"unity_"]) gJCG59UnityRequests++;
        if ([layer hasPrefix:@"sockettcp_"]) {
            gJCG59SocketRequests++;
            BOOL decrypt = [[m objectForKey:@"socket_decrypt"] boolValue];
            if (decrypt) gJCG59SocketDecryptTrueRequests++; else gJCG59SocketDecryptFalseRequests++;
        }
        JCG59ScheduleCoverageWrite();
        [m release];
    }});
}

// kind: 1=json, 0=non-json, -1=unknown/no body observation.
static void JCG59RecordResponse(NSDictionary *meta, NSInteger kind, NSUInteger bytes) {
    if (!meta || !gJCG5CaptureQueue) return;
    NSDictionary *m = [meta copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        NSString *url = [m objectForKey:@"url"] ?: @"";
        NSString *method = [m objectForKey:@"method"] ?: @"";
        NSString *endpointKey = JCG59EndpointKey(url, method);
        NSString *urlKey = [NSString stringWithFormat:@"%@ %@", method.length ? [method uppercaseString] : @"UNKNOWN", url.length ? url : @"(no-url)"];
        NSMutableDictionary *ep = JCG59MutableEntry(gJCG59CoverageEndpoints, endpointKey, m);
        NSMutableDictionary *ue = JCG59MutableEntry(gJCG59CoverageURLs, urlKey, m);
        JCG59Bump(ep, @"response_count", 1);
        JCG59Bump(ue, @"response_count", 1);
        gJCG59ResponsesTotal++;
        if (kind > 0) {
            JCG59Bump(ep, @"json_count", 1); JCG59Bump(ue, @"json_count", 1);
            JCG59Bump(ep, @"json_bytes", bytes); JCG59Bump(ue, @"json_bytes", bytes);
            gJCG59JSONResponses++; gJCG59JSONBytes += bytes;
            if ([[m objectForKey:@"capture_layer"] hasPrefix:@"sockettcp_"]) {
                BOOL decrypt = [[m objectForKey:@"socket_decrypt"] boolValue];
                if (decrypt) gJCG59SocketDecryptTrueJSON++; else gJCG59SocketDecryptFalseJSON++;
            }
        } else if (kind == 0) {
            JCG59Bump(ep, @"non_json_count", 1); JCG59Bump(ue, @"non_json_count", 1);
            JCG59Bump(ep, @"non_json_bytes", bytes); JCG59Bump(ue, @"non_json_bytes", bytes);
            gJCG59NonJSONResponses++; gJCG59NonJSONBytes += bytes;
        } else {
            JCG59Bump(ep, @"unknown_count", 1); JCG59Bump(ue, @"unknown_count", 1);
            gJCG59UnknownResponses++;
        }
        NSNumber *status = [m objectForKey:@"http_status"];
        if (status && status.integerValue != 0) {
            for (NSMutableDictionary *e in @[ep, ue]) {
                NSMutableDictionary *sc = (NSMutableDictionary *)[e objectForKey:@"status_codes"];
                NSString *sk = [status stringValue];
                unsigned long long old = [[sc objectForKey:sk] unsignedLongLongValue];
                sc[sk] = @(old + 1);
            }
        }
        JCG59ScheduleCoverageWrite();
        [m release];
    }});
}

static BOOL JCG59ShouldCountValidatedMeta(NSDictionary *meta) {
    NSString *layer = [meta objectForKey:@"capture_layer"];
    return [layer isEqualToString:@"unity_nsurlsession_delegate"] ||
           [layer isEqualToString:@"sockettcp_protobuf_post_decrypt"];
}

'''

rep(
    "#pragma mark - Dynamic symbols / loader hooks\n",
    coverage + "#pragma mark - Dynamic symbols / loader hooks\n",
    "coverage core insertion",
)

# Count every UnityWebRequest when SendWebRequest is invoked.
rep(
    "    if (handler) {\n"
    "        NSDictionary *ctx = [[NSDictionary alloc] initWithObjectsAndKeys:\n",
    "    NSDictionary *coverageMeta = @{\n"
    "        @\"source\": @\"UnityWebRequest.SendWebRequest\",\n"
    "        @\"capture_layer\": @\"unity_sendwebrequest\",\n"
    "        @\"url\": url ?: @\"\",\n"
    "        @\"method\": httpMethod ?: @\"\"\n"
    "    };\n"
    "    JCG59RecordRequest(coverageMeta);\n\n"
    "    if (handler) {\n"
    "        NSDictionary *ctx = [[NSDictionary alloc] initWithObjectsAndKeys:\n",
    "Unity request coverage",
)

# Count every Socket request at the g_requestHttpServer wrapper, not only responses.
rep(
    "static int JCG58RequestWrapper(void *L) {\n"
    "    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;\n"
    "    if (!gJCG58LuaGetGlobal || !gJCG58LuaPushValue || !gJCG58LuaCallK) return 0;\n\n",
    "static int JCG58RequestWrapper(void *L) {\n"
    "    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;\n"
    "    if (!gJCG58LuaGetGlobal || !gJCG58LuaPushValue || !gJCG58LuaCallK) return 0;\n\n"
    "    NSString *coverageURL = nargs >= 1 ? JCG58StringAt(L, 1, 2 * 1024 * 1024) : @\"\";\n"
    "    BOOL coverageDecrypt = (nargs >= 3 && gJCG58LuaToBoolean) ? (gJCG58LuaToBoolean(L, 3) != 0) : NO;\n"
    "    JCG59RecordRequest(@{\n"
    "        @\"source\": @\"SocketTCP.g_requestHttpServer\",\n"
    "        @\"capture_layer\": @\"sockettcp_request\",\n"
    "        @\"url\": coverageURL ?: @\"\",\n"
    "        @\"method\": @\"SOCKET_HTTP\",\n"
    "        @\"socket_decrypt\": @(coverageDecrypt)\n"
    "    });\n\n",
    "Socket request coverage",
)

# Full JSON validator is the authoritative JSON/non-JSON decision for backend
# candidate bodies and all Socket response bodies. Skip the legacy GetData copy
# so one Unity response is not counted twice.
rep(
    "        if (!complete) {\n"
    "            pthread_mutex_lock(&gJCG5StateLock);\n",
    "        if (!complete) {\n"
    "            if (JCG59ShouldCountValidatedMeta(metaSnapshot)) JCG59RecordResponse(metaSnapshot, 0, snapshot.length);\n"
    "            pthread_mutex_lock(&gJCG5StateLock);\n",
    "validated non-JSON coverage",
)

rep(
    "        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];\n",
    "        if (JCG59ShouldCountValidatedMeta(metaSnapshot)) JCG59RecordResponse(metaSnapshot, 1, snapshot.length);\n\n"
    "        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];\n",
    "validated JSON coverage",
)

# Unity backend rejects obvious non-JSON responses before accumulating them.
# Count those at task completion; accepted candidates are classified later by
# JCG55QueueValidatedResponse, and empty/unobserved responses are unknown.
rep(
    "    BOOL accepted = NO;\n"
    "    pthread_mutex_lock(&gJCG5StateLock);\n"
    "    accepted = [gJCG57AcceptedTasks containsObject:key];\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n",
    "    BOOL accepted = NO;\n"
    "    BOOL rejected = NO;\n"
    "    pthread_mutex_lock(&gJCG5StateLock);\n"
    "    accepted = [gJCG57AcceptedTasks containsObject:key];\n"
    "    rejected = [gJCG57RejectedTasks containsObject:key];\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n",
    "Unity completion accepted/rejected coverage",
)

rep(
    "    pthread_mutex_lock(&gJCG5StateLock);\n"
    "    [gJCG57AcceptedTasks removeObject:key];\n"
    "    [gJCG57RejectedTasks removeObject:key];\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n"
    "    if (!accepted || !gJCG5CaptureQueue) {\n",
    "    pthread_mutex_lock(&gJCG5StateLock);\n"
    "    [gJCG57AcceptedTasks removeObject:key];\n"
    "    [gJCG57RejectedTasks removeObject:key];\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n\n"
    "    if (!accepted) {\n"
    "        NSURLRequest *covReq = task.currentRequest ?: task.originalRequest;\n"
    "        NSURLResponse *covResp = task.response;\n"
    "        NSInteger covStatus = [covResp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)covResp statusCode] : 0;\n"
    "        NSDictionary *covMeta = @{\n"
    "            @\"source\": @\"UnityWebRequestDelegate.URLSession:task:didCompleteWithError:\",\n"
    "            @\"capture_layer\": @\"unity_nsurlsession_delegate\",\n"
    "            @\"url\": covReq.URL.absoluteString ?: @\"\",\n"
    "            @\"method\": covReq.HTTPMethod ?: @\"\",\n"
    "            @\"http_status\": @(covStatus)\n"
    "        };\n"
    "        NSUInteger covBytes = (NSUInteger)MAX((int64_t)0, task.countOfBytesReceived);\n"
    "        JCG59RecordResponse(covMeta, rejected ? 0 : -1, covBytes);\n"
    "    }\n\n"
    "    if (!accepted || !gJCG5CaptureQueue) {\n",
    "Unity non-JSON/unknown coverage",
)

# Start a fresh coverage session inside the existing constructor. No additional
# constructor or lifecycle entry point is introduced.
rep(
    "        JCG5SetupPaths();gJCG5CaptureQueue=dispatch_queue_create(\"com.openai.jsoncapture.v05.capture\",DISPATCH_QUEUE_SERIAL);gJCG5TaskQueue=dispatch_queue_create(\"com.openai.jsoncapture.v05.manualtask\",DISPATCH_QUEUE_SERIAL);gJCG5CaptureHashes=[[NSMutableSet alloc]init];",
    "        JCG5SetupPaths();gJCG5CaptureQueue=dispatch_queue_create(\"com.openai.jsoncapture.v05.capture\",DISPATCH_QUEUE_SERIAL);gJCG5TaskQueue=dispatch_queue_create(\"com.openai.jsoncapture.v05.manualtask\",DISPATCH_QUEUE_SERIAL);gJCG5CaptureHashes=[[NSMutableSet alloc]init];JCG59ResetCoverageSession();",
    "coverage session initialization",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.9 unified network coverage statistics")
