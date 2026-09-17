#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_PAGE_PROTOBUF_V060"
if MARKER in s:
    print("v0.6.0 page/protobuf patch already applied")
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
    "JCG5_NETWORK_COVERAGE_V059",
    "JCG5_NETWORK_COVERAGE_V059_COMPILE_FIX",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.6.0 patch anchor missing: {label}")
    s = s.replace(old, new, 1)


core = r'''
// JCG5_PAGE_PROTOBUF_V060
// Page-context + protobuf business-message capture. This is deliberately a Lua
// wrapper layer: no additional MSHookFunction target, constructor, TLS/TLV, or
// polling queue is introduced. NetWorkManager.sendMsg(msgid, object) is the
// recovered outbound center; NetWorkManager.parseMsg(packet) constructs the
// registered protobuf response, ParseFromString(packet.payload), then returns
// (msgid, decodedMessage).
#define JCG60_PROTOBUF_RAW_MAX_BYTES (64ULL * 1024ULL * 1024ULL)
#define JCG60_LUA_SNAPSHOT_MAX_STRING (1024ULL * 1024ULL)
#define JCG60_LUA_SNAPSHOT_MAX_BINARY (256ULL * 1024ULL)
#define JCG60_LUA_SNAPSHOT_MAX_DEPTH 8
#define JCG60_LUA_SNAPSHOT_MAX_NODES 8192
#define JCG60_LUA_TNIL 0
#define JCG60_LUA_TBOOLEAN 1
#define JCG60_LUA_TNUMBER 3
#define JCG60_LUA_TSTRING 4
#define JCG60_LUA_TTABLE 5
#define JCG60_LUA_TFUNCTION 6
#define JCG60_LUA_TUSERDATA 7
#define JCG60_LUA_TTHREAD 8

typedef int (*JCG60LuaGetFieldFn)(void *L, int idx, const char *key);
typedef void (*JCG60LuaSetFieldFn)(void *L, int idx, const char *key);
typedef void (*JCG60LuaPushNilFn)(void *L);
typedef int (*JCG60LuaNextFn)(void *L, int idx);
typedef double (*JCG60LuaToNumberXFn)(void *L, int idx, int *isnum);
typedef const void *(*JCG60LuaToPointerFn)(void *L, int idx);

static JCG60LuaGetFieldFn gJCG60LuaGetField;
static JCG60LuaSetFieldFn gJCG60LuaSetField;
static JCG60LuaPushNilFn gJCG60LuaPushNil;
static JCG60LuaNextFn gJCG60LuaNext;
static JCG60LuaToNumberXFn gJCG60LuaToNumberX;
static JCG60LuaToPointerFn gJCG60LuaToPointer;
static BOOL gJCG60ExtraLuaAPIReady = NO;
static BOOL gJCG60SendWrapperReady = NO;
static BOOL gJCG60ParseWrapperReady = NO;
static NSMutableDictionary *gJCG60MsgNames;
static BOOL gJCG60MsgNamesReady = NO;

static NSString *gJCG60LatestLua;
static NSString *gJCG60TabLua;
static NSString *gJCG60UILua;
static NSTimeInterval gJCG60LatestLuaAt = 0;
static NSTimeInterval gJCG60TabLuaAt = 0;
static NSTimeInterval gJCG60UILuaAt = 0;

static NSString *gJCG60ProtoEventsPath;
static NSString *gJCG60ProtoRawDir;
static NSString *gJCG60PageMapPath;
static NSMutableDictionary *gJCG60PageMap;
static BOOL gJCG60PageMapWriteScheduled = NO;
static unsigned long long gJCG60ProtoSequence = 0;
static unsigned long long gJCG60ProtoRequests = 0;
static unsigned long long gJCG60ProtoResponses = 0;
static unsigned long long gJCG60ProtoRawSaved = 0;
static unsigned long long gJCG60ProtoSnapshotFailures = 0;
static long long gJCG60LastMsgID = 0;
static NSString *gJCG60LastMsgName;

static void JCG55AppendJSONLine(NSString *path, NSDictionary *obj);

static int JCG60AbsIndex(void *L, int idx) {
    if (idx > 0 || idx <= JCG58_LUA_REGISTRYINDEX) return idx;
    return gJCG58LuaGetTop ? (gJCG58LuaGetTop(L) + idx + 1) : idx;
}

static void JCG60Pop(void *L, int n) {
    if (!L || !gJCG58LuaGetTop || !gJCG58LuaSetTop || n <= 0) return;
    int top = gJCG58LuaGetTop(L);
    gJCG58LuaSetTop(L, MAX(0, top - n));
}

static BOOL JCG60ResolveExtraLuaAPI(void *L) {
    if (gJCG60ExtraLuaAPIReady) return YES;
    if (!L || !JCG58ResolveLuaAPI(L)) return NO;
    gJCG60LuaGetField = (JCG60LuaGetFieldFn)JCG5ResolveExport("lua_getfield");
    gJCG60LuaSetField = (JCG60LuaSetFieldFn)JCG5ResolveExport("lua_setfield");
    gJCG60LuaPushNil = (JCG60LuaPushNilFn)JCG5ResolveExport("lua_pushnil");
    gJCG60LuaNext = (JCG60LuaNextFn)JCG5ResolveExport("lua_next");
    gJCG60LuaToNumberX = (JCG60LuaToNumberXFn)JCG5ResolveExport("lua_tonumberx");
    gJCG60LuaToPointer = (JCG60LuaToPointerFn)JCG5ResolveExport("lua_topointer");
    if (!gJCG60LuaGetField || !gJCG60LuaSetField || !gJCG60LuaPushNil ||
        !gJCG60LuaNext || !gJCG60LuaToNumberX) return NO;
    gJCG60ExtraLuaAPIReady = YES;
    JCG5Log(@"PROTOBUF Lua API ready; waiting for NetWorkManager.sendMsg/parseMsg");
    return YES;
}

static NSString *JCG60ChunkBase(const char *name) {
    if (!name) return @"";
    NSString *raw = [[[NSString alloc] initWithUTF8String:name] autorelease];
    if (!raw.length) return @"";
    NSString *norm = [raw stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    return norm.lastPathComponent.length ? norm.lastPathComponent : norm;
}

static void JCG60NoteLuaChunk(const char *name) {
    NSString *base = JCG60ChunkBase(name);
    if (!base.length) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSString *lower = base.lowercaseString;
    BOOL isTab = [lower hasPrefix:@"tab_"];
    BOOL isUI = [lower hasPrefix:@"ui"] &&
                ([lower hasSuffix:@".lua"] || [lower hasSuffix:@".luac"] || [lower containsString:@"_"]);
    pthread_mutex_lock(&gJCG5StateLock);
    [gJCG60LatestLua release]; gJCG60LatestLua = [base copy]; gJCG60LatestLuaAt = now;
    if (isTab) { [gJCG60TabLua release]; gJCG60TabLua = [base copy]; gJCG60TabLuaAt = now; }
    if (isUI) { [gJCG60UILua release]; gJCG60UILua = [base copy]; gJCG60UILuaAt = now; }
    pthread_mutex_unlock(&gJCG5StateLock);
}

static NSDictionary *JCG60PageContextSnapshot(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    pthread_mutex_lock(&gJCG5StateLock);
    NSString *latest = [[(gJCG60LatestLua ?: @"") copy] autorelease];
    NSString *tab = [[(gJCG60TabLua ?: @"") copy] autorelease];
    NSString *ui = [[(gJCG60UILua ?: @"") copy] autorelease];
    NSTimeInterval latestAt = gJCG60LatestLuaAt, tabAt = gJCG60TabLuaAt, uiAt = gJCG60UILuaAt;
    pthread_mutex_unlock(&gJCG5StateLock);
    NSString *page = @""; NSString *kind = @"none"; NSTimeInterval at = 0;
    if (tab.length && tabAt >= uiAt) { page = tab; kind = @"tab"; at = tabAt; }
    else if (ui.length) { page = ui; kind = @"ui"; at = uiAt; }
    else if (latest.length) { page = latest; kind = @"latest"; at = latestAt; }
    long long ageMS = at > 0 ? (long long)MAX(0.0, (now - at) * 1000.0) : -1;
    return @{
        @"page_context": page ?: @"",
        @"page_context_kind": kind,
        @"page_context_age_ms": @(ageMS),
        @"page_tab_lua": tab ?: @"",
        @"page_ui_lua": ui ?: @"",
        @"latest_lua": latest ?: @""
    };
}

static id JCG60SnapshotLuaValue(void *L, int idx, NSUInteger depth, NSMutableSet *visited, NSUInteger *budget) {
    if (!L || !gJCG58LuaType || !gJCG58LuaGetTop || !gJCG58LuaSetTop || !budget) return [NSNull null];
    if (*budget >= JCG60_LUA_SNAPSHOT_MAX_NODES) return @"<node-limit>";
    (*budget)++;
    int abs = JCG60AbsIndex(L, idx);
    int type = gJCG58LuaType(L, abs);
    if (type == JCG60_LUA_TNIL) return [NSNull null];
    if (type == JCG60_LUA_TBOOLEAN) return @(gJCG58LuaToBoolean ? (gJCG58LuaToBoolean(L, abs) != 0) : NO);
    if (type == JCG60_LUA_TNUMBER) {
        int isint = 0;
        int64_t iv = gJCG58LuaToIntegerX ? gJCG58LuaToIntegerX(L, abs, &isint) : 0;
        if (isint) return @(iv);
        int isnum = 0;
        double dv = gJCG60LuaToNumberX ? gJCG60LuaToNumberX(L, abs, &isnum) : 0;
        return isnum ? @(dv) : @0;
    }
    if (type == JCG60_LUA_TSTRING) {
        size_t n = 0; const char *p = gJCG58LuaToLString ? gJCG58LuaToLString(L, abs, &n) : NULL;
        if (!p) return @"";
        if (n > JCG60_LUA_SNAPSHOT_MAX_STRING) return [NSString stringWithFormat:@"<string:%llu bytes>", (unsigned long long)n];
        NSString *text = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
        if (text) return text;
        if (n <= JCG60_LUA_SNAPSHOT_MAX_BINARY) {
            NSData *d = [NSData dataWithBytes:p length:n];
            return @{ @"$binary_base64": [d base64EncodedStringWithOptions:0] ?: @"", @"$bytes": @(n) };
        }
        return [NSString stringWithFormat:@"<binary:%llu bytes>", (unsigned long long)n];
    }
    if (type == JCG60_LUA_TTABLE) {
        if (depth >= JCG60_LUA_SNAPSHOT_MAX_DEPTH) return @"<table-depth-limit>";
        const void *ptr = gJCG60LuaToPointer ? gJCG60LuaToPointer(L, abs) : NULL;
        NSValue *pv = ptr ? [NSValue valueWithPointer:ptr] : nil;
        if (pv && [visited containsObject:pv]) return @"<cycle>";
        if (pv) [visited addObject:pv];

        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        NSMutableDictionary *numeric = [NSMutableDictionary dictionary];
        BOOL arrayCandidate = YES; NSUInteger numericCount = 0, maxIndex = 0;
        gJCG60LuaPushNil(L);
        while (gJCG60LuaNext(L, abs) != 0) {
            int keyType = gJCG58LuaType(L, -2);
            id value = JCG60SnapshotLuaValue(L, -1, depth + 1, visited, budget) ?: [NSNull null];
            NSString *key = nil; NSUInteger arrayIndex = 0; BOOL positiveIndex = NO;
            if (keyType == JCG60_LUA_TSTRING) {
                size_t kn = 0; const char *kp = gJCG58LuaToLString(L, -2, &kn);
                if (kp && kn < 4096) key = [[[NSString alloc] initWithBytes:kp length:kn encoding:NSUTF8StringEncoding] autorelease];
            } else if (keyType == JCG60_LUA_TNUMBER) {
                int ok = 0; int64_t kv = gJCG58LuaToIntegerX(L, -2, &ok);
                if (ok && kv > 0 && kv <= 1000000) { positiveIndex = YES; arrayIndex = (NSUInteger)kv; }
                else if (ok) key = [NSString stringWithFormat:@"%lld", (long long)kv];
            }
            if (positiveIndex) {
                [numeric setObject:value forKey:@(arrayIndex)]; numericCount++; maxIndex = MAX(maxIndex, arrayIndex);
            } else {
                arrayCandidate = NO;
                if (!key.length) key = [NSString stringWithFormat:@"<key-type-%d>", keyType];
                [dict setObject:value forKey:key];
            }
            JCG60Pop(L, 1); // pop value; keep key for lua_next
            if (*budget >= JCG60_LUA_SNAPSHOT_MAX_NODES) break;
        }
        if (pv) [visited removeObject:pv];
        if (arrayCandidate && numericCount > 0 && maxIndex == numericCount && maxIndex <= 8192) {
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:maxIndex];
            for (NSUInteger i = 1; i <= maxIndex; i++) [arr addObject:[numeric objectForKey:@(i)] ?: [NSNull null]];
            return arr;
        }
        for (NSNumber *k in numeric) [dict setObject:[numeric objectForKey:k] ?: [NSNull null] forKey:k.stringValue];
        return dict;
    }
    if (type == JCG60_LUA_TFUNCTION) return @"<function>";
    if (type == JCG60_LUA_TUSERDATA) return @"<userdata>";
    if (type == JCG60_LUA_TTHREAD) return @"<thread>";
    return [NSString stringWithFormat:@"<lua-type-%d>", type];
}

static id JCG60Snapshot(void *L, int idx) {
    NSUInteger budget = 0;
    NSMutableSet *visited = [NSMutableSet set];
    return JCG60SnapshotLuaValue(L, idx, 0, visited, &budget);
}

static void JCG60BuildMsgNames(void *L) {
    if (!L || gJCG60MsgNamesReady || !gJCG58LuaGetGlobal || !gJCG60LuaPushNil || !gJCG60LuaNext) return;
    int top = gJCG58LuaGetTop(L);
    int t = gJCG58LuaGetGlobal(L, "msg_pb");
    if (t != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return; }
    int tableIndex = JCG60AbsIndex(L, -1);
    if (!gJCG60MsgNames) gJCG60MsgNames = [[NSMutableDictionary alloc] init];
    gJCG60LuaPushNil(L);
    while (gJCG60LuaNext(L, tableIndex) != 0) {
        if (gJCG58LuaType(L, -2) == JCG60_LUA_TSTRING && gJCG58LuaType(L, -1) == JCG60_LUA_TNUMBER) {
            size_t kn = 0; const char *kp = gJCG58LuaToLString(L, -2, &kn);
            int ok = 0; int64_t msgid = gJCG58LuaToIntegerX(L, -1, &ok);
            if (kp && kn > 6 && kn < 256 && ok) {
                NSString *key = [[[NSString alloc] initWithBytes:kp length:kn encoding:NSUTF8StringEncoding] autorelease];
                if ([key hasPrefix:@"MSGID_"] && ![gJCG60MsgNames objectForKey:@(msgid)]) [gJCG60MsgNames setObject:key forKey:@(msgid)];
            }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, top);
    if (gJCG60MsgNames.count) {
        gJCG60MsgNamesReady = YES;
        JCG5Log([NSString stringWithFormat:@"PROTOBUF msgid map ready count=%lu", (unsigned long)gJCG60MsgNames.count]);
    }
}

static NSString *JCG60MsgName(void *L, long long msgid) {
    if (!gJCG60MsgNamesReady) JCG60BuildMsgNames(L);
    NSString *name = [gJCG60MsgNames objectForKey:@(msgid)];
    return name ?: [NSString stringWithFormat:@"MSGID_%lld", msgid];
}

static void JCG60EnsureOutputPaths(void) {
    if (!gJCG60ProtoEventsPath) gJCG60ProtoEventsPath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_protobuf_events.jsonl"] retain];
    if (!gJCG60ProtoRawDir) gJCG60ProtoRawDir = [[gJCG5Root stringByAppendingPathComponent:@"runtime_protobuf_raw"] retain];
    if (!gJCG60PageMapPath) gJCG60PageMapPath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_page_network_map.json"] retain];
    JCG5EnsureDir(gJCG60ProtoRawDir);
    if (!gJCG60PageMap) gJCG60PageMap = [[NSMutableDictionary alloc] init];
}

static NSMutableDictionary *JCG60PageEntry(NSDictionary *event) {
    JCG60EnsureOutputPaths();
    NSString *page = [event objectForKey:@"page_context"];
    if (!page.length) page = @"(unknown)";
    NSMutableDictionary *entry = [gJCG60PageMap objectForKey:page];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        [entry setObject:page forKey:@"page_context"];
        [entry setObject:([event objectForKey:@"page_context_kind"] ?: @"none") forKey:@"page_context_kind"];
        [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"first_seen"];
        [entry setObject:@0 forKey:@"json_events"];
        [entry setObject:@0 forKey:@"protobuf_requests"];
        [entry setObject:@0 forKey:@"protobuf_responses"];
        [entry setObject:[NSMutableDictionary dictionary] forKey:@"endpoints"];
        [entry setObject:[NSMutableDictionary dictionary] forKey:@"messages"];
        [gJCG60PageMap setObject:entry forKey:page];
    }
    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_seen"];
    return entry;
}

static void JCG60BumpDict(NSMutableDictionary *d, NSString *key) {
    if (!d || !key.length) return;
    unsigned long long n = [[d objectForKey:key] unsignedLongLongValue];
    [d setObject:@(n + 1) forKey:key];
}

static void JCG60WritePageMapNow(void) {
    JCG60EnsureOutputPaths();
    NSMutableArray *pages = [NSMutableArray array];
    for (NSString *key in [[gJCG60PageMap allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *e = [gJCG60PageMap objectForKey:key]; if (e) [pages addObject:e];
    }
    NSDictionary *root = @{ @"schema": @1, @"updated_at": @([[NSDate date] timeIntervalSince1970]), @"pages": pages };
    NSData *d = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (d.length) [d writeToFile:gJCG60PageMapPath options:NSDataWritingAtomic error:nil];
    gJCG60PageMapWriteScheduled = NO;
}

static void JCG60SchedulePageMapWrite(void) {
    if (!gJCG5CaptureQueue || gJCG60PageMapWriteScheduled) return;
    gJCG60PageMapWriteScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), gJCG5CaptureQueue, ^{@autoreleasepool { JCG60WritePageMapNow(); }});
}

static void JCG60RecordPageJSON(NSDictionary *meta, NSUInteger bytes) {
    if (!meta) return;
    NSMutableDictionary *entry = JCG60PageEntry(meta);
    JCG60BumpDict(entry, @"json_events");
    NSString *url = [meta objectForKey:@"url"] ?: @"";
    NSString *method = [meta objectForKey:@"method"] ?: @"";
    NSString *endpoint = JCG59EndpointKey(url, method);
    NSMutableDictionary *eps = (NSMutableDictionary *)[entry objectForKey:@"endpoints"];
    JCG60BumpDict(eps, endpoint.length ? endpoint : @"(no-endpoint)");
    [entry setObject:@(bytes) forKey:@"last_json_bytes"];
    JCG60SchedulePageMapWrite();
}

static void JCG60RecordPageProtobuf(NSDictionary *event) {
    if (!event) return;
    NSMutableDictionary *entry = JCG60PageEntry(event);
    NSString *direction = [event objectForKey:@"direction"] ?: @"";
    if ([direction isEqualToString:@"request"]) JCG60BumpDict(entry, @"protobuf_requests");
    else if ([direction isEqualToString:@"response"]) JCG60BumpDict(entry, @"protobuf_responses");
    NSString *msgKey = [[event objectForKey:@"msgid"] stringValue] ?: @"0";
    NSMutableDictionary *messages = (NSMutableDictionary *)[entry objectForKey:@"messages"];
    NSMutableDictionary *m = [messages objectForKey:msgKey];
    if (!m) {
        m = [NSMutableDictionary dictionary];
        [m setObject:([event objectForKey:@"msg_name"] ?: @"") forKey:@"name"];
        [m setObject:@0 forKey:@"request_count"];
        [m setObject:@0 forKey:@"response_count"];
        [messages setObject:m forKey:msgKey];
    }
    JCG60BumpDict(m, [direction isEqualToString:@"request"] ? @"request_count" : @"response_count");
    JCG60SchedulePageMapWrite();
}

static void JCG60QueueProtobufEvent(NSDictionary *event, NSData *rawPayload) {
    if (!event || !gJCG5CaptureQueue) return;
    NSDictionary *e = [event copy]; NSData *raw = [rawPayload retain];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG60EnsureOutputPaths();
        NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:e];
        if (raw.length && raw.length <= JCG60_PROTOBUF_RAW_MAX_BYTES) {
            NSString *sha = JCG5SHA256(raw);
            unsigned long long seq = [[record objectForKey:@"sequence"] unsignedLongLongValue];
            long long msgid = [[record objectForKey:@"msgid"] longLongValue];
            NSString *shortSha = sha.length > 12 ? [sha substringToIndex:12] : sha;
            NSString *file = [NSString stringWithFormat:@"resp_%06llu_%lld_%@.pb", seq, msgid, shortSha ?: @"nohash"];
            NSString *path = [gJCG60ProtoRawDir stringByAppendingPathComponent:file];
            if ([raw writeToFile:path atomically:YES]) {
                [record setObject:file forKey:@"raw_file"];
                [record setObject:@(raw.length) forKey:@"raw_bytes"];
                if (sha.length) [record setObject:sha forKey:@"raw_sha256"];
                pthread_mutex_lock(&gJCG5StateLock); gJCG60ProtoRawSaved++; pthread_mutex_unlock(&gJCG5StateLock);
            }
        }
        JCG55AppendJSONLine(gJCG60ProtoEventsPath, record);
        JCG60RecordPageProtobuf(record);
        [e release]; [raw release];
    }});
}

static int JCG60SendMsgWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;
    BOOL enabled = NO; pthread_mutex_lock(&gJCG5StateLock); enabled = gJCG5CaptureEnabled; pthread_mutex_unlock(&gJCG5StateLock);
    if (enabled && nargs >= 1) {
        int ok = 0; long long msgid = gJCG58LuaToIntegerX ? (long long)gJCG58LuaToIntegerX(L, 1, &ok) : 0;
        if (ok) {
            unsigned long long seq = 0;
            pthread_mutex_lock(&gJCG5StateLock); seq = ++gJCG60ProtoSequence; gJCG60ProtoRequests++; gJCG60LastMsgID = msgid; [gJCG60LastMsgName release]; gJCG60LastMsgName = [JCG60MsgName(L, msgid) copy]; pthread_mutex_unlock(&gJCG5StateLock);
            NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:JCG60PageContextSnapshot()];
            [event setObject:@1 forKey:@"schema"];
            [event setObject:@"request" forKey:@"direction"];
            [event setObject:@"NetWorkManager.sendMsg" forKey:@"source"];
            [event setObject:@"protobuf_business" forKey:@"capture_layer"];
            [event setObject:@(seq) forKey:@"sequence"];
            [event setObject:@(msgid) forKey:@"msgid"];
            [event setObject:JCG60MsgName(L, msgid) forKey:@"msg_name"];
            [event setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"time"];
            if (nargs >= 2) {
                id snapshot = JCG60Snapshot(L, 2);
                if (snapshot) [event setObject:snapshot forKey:@"decoded"];
                else { pthread_mutex_lock(&gJCG5StateLock); gJCG60ProtoSnapshotFailures++; pthread_mutex_unlock(&gJCG5StateLock); }
            }
            JCG60QueueProtobufEvent(event, nil);
            JCG5Log([NSString stringWithFormat:@"PROTOBUF request seq=%llu msgid=%lld name=%@ page=%@", seq, msgid, JCG60MsgName(L, msgid), [event objectForKey:@"page_context"] ?: @""]);
        }
    }
    if (gJCG58LuaPushValue && gJCG58LuaCallK) {
        gJCG58LuaPushValue(L, JCG58_LUA_UPVALUEINDEX(1));
        for (int i = 1; i <= nargs; i++) gJCG58LuaPushValue(L, i);
        gJCG58LuaCallK(L, nargs, 0, (intptr_t)0, NULL);
    }
    return 0;
}

static int JCG60ParseMsgWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;
    NSData *raw = nil; long long packetMsgID = 0; int packetIDOK = 0;
    if (nargs >= 1 && gJCG58LuaType(L, 1) == JCG60_LUA_TTABLE) {
        int top = gJCG58LuaGetTop(L);
        gJCG60LuaGetField(L, 1, "id"); packetMsgID = (long long)gJCG58LuaToIntegerX(L, -1, &packetIDOK); gJCG58LuaSetTop(L, top);
        gJCG60LuaGetField(L, 1, "payload");
        if (gJCG58LuaType(L, -1) == JCG60_LUA_TSTRING) {
            size_t n = 0; const char *p = gJCG58LuaToLString(L, -1, &n);
            if (p && n && n <= JCG60_PROTOBUF_RAW_MAX_BYTES) raw = [[NSData alloc] initWithBytes:p length:n];
        }
        gJCG58LuaSetTop(L, top);
    }

    gJCG58LuaPushValue(L, JCG58_LUA_UPVALUEINDEX(1));
    if (nargs >= 1) gJCG58LuaPushValue(L, 1);
    gJCG58LuaCallK(L, nargs >= 1 ? 1 : 0, 2, (intptr_t)0, NULL);

    int topAfter = gJCG58LuaGetTop(L);
    int resultMsgIndex = topAfter - 1, resultObjIndex = topAfter;
    int ok = 0; long long msgid = (long long)gJCG58LuaToIntegerX(L, resultMsgIndex, &ok);
    if (!ok && packetIDOK) { msgid = packetMsgID; ok = 1; }
    BOOL enabled = NO; pthread_mutex_lock(&gJCG5StateLock); enabled = gJCG5CaptureEnabled; pthread_mutex_unlock(&gJCG5StateLock);
    if (enabled && ok) {
        unsigned long long seq = 0;
        pthread_mutex_lock(&gJCG5StateLock); seq = ++gJCG60ProtoSequence; gJCG60ProtoResponses++; gJCG60LastMsgID = msgid; [gJCG60LastMsgName release]; gJCG60LastMsgName = [JCG60MsgName(L, msgid) copy]; pthread_mutex_unlock(&gJCG5StateLock);
        NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:JCG60PageContextSnapshot()];
        [event setObject:@1 forKey:@"schema"];
        [event setObject:@"response" forKey:@"direction"];
        [event setObject:@"NetWorkManager.parseMsg" forKey:@"source"];
        [event setObject:@"protobuf_business" forKey:@"capture_layer"];
        [event setObject:@(seq) forKey:@"sequence"];
        [event setObject:@(msgid) forKey:@"msgid"];
        [event setObject:JCG60MsgName(L, msgid) forKey:@"msg_name"];
        [event setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"time"];
        if (raw) [event setObject:@(raw.length) forKey:@"wire_bytes"];
        id snapshot = JCG60Snapshot(L, resultObjIndex);
        if (snapshot) [event setObject:snapshot forKey:@"decoded"];
        else { pthread_mutex_lock(&gJCG5StateLock); gJCG60ProtoSnapshotFailures++; pthread_mutex_unlock(&gJCG5StateLock); }
        JCG60QueueProtobufEvent(event, raw);
        JCG5Log([NSString stringWithFormat:@"PROTOBUF response seq=%llu msgid=%lld name=%@ bytes=%lu page=%@", seq, msgid, JCG60MsgName(L, msgid), (unsigned long)raw.length, [event objectForKey:@"page_context"] ?: @""]);
    }
    [raw release];
    return 2;
}

static void JCG60TryInstallProtobuf(void *L) {
    if (!L || !JCG60ResolveExtraLuaAPI(L)) return;
    int top = gJCG58LuaGetTop(L);
    int t = gJCG58LuaGetGlobal(L, "NetWorkManager");
    if (t != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return; }
    int tableIndex = JCG60AbsIndex(L, -1);
    BOOL sendReady = NO, parseReady = NO, changed = NO;

    int st = gJCG60LuaGetField(L, tableIndex, "sendMsg");
    if (st == JCG60_LUA_TFUNCTION) {
        JCG58LuaCFunction current = gJCG58LuaToCFunction(L, -1);
        if (current == JCG60SendMsgWrapper) sendReady = YES;
        else {
            gJCG58LuaPushValue(L, -1);
            gJCG58LuaPushCClosure(L, JCG60SendMsgWrapper, 1);
            gJCG60LuaSetField(L, tableIndex, "sendMsg");
            sendReady = YES; changed = YES;
        }
    }
    gJCG58LuaSetTop(L, tableIndex);

    int pt = gJCG60LuaGetField(L, tableIndex, "parseMsg");
    if (pt == JCG60_LUA_TFUNCTION) {
        JCG58LuaCFunction current = gJCG58LuaToCFunction(L, -1);
        if (current == JCG60ParseMsgWrapper) parseReady = YES;
        else {
            gJCG58LuaPushValue(L, -1);
            gJCG58LuaPushCClosure(L, JCG60ParseMsgWrapper, 1);
            gJCG60LuaSetField(L, tableIndex, "parseMsg");
            parseReady = YES; changed = YES;
        }
    }
    gJCG58LuaSetTop(L, top);

    pthread_mutex_lock(&gJCG5StateLock); gJCG60SendWrapperReady = sendReady; gJCG60ParseWrapperReady = parseReady; pthread_mutex_unlock(&gJCG5StateLock);
    if (changed) JCG5Log([NSString stringWithFormat:@"PROTOBUF wrapper ready send=%d parse=%d", sendReady, parseReady]);
}

static NSString *JCG60ProtoStatusText(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL send = gJCG60SendWrapperReady, parse = gJCG60ParseWrapperReady;
    unsigned long long req = gJCG60ProtoRequests, resp = gJCG60ProtoResponses, raw = gJCG60ProtoRawSaved, fail = gJCG60ProtoSnapshotFailures;
    long long msgid = gJCG60LastMsgID;
    NSString *name = [[(gJCG60LastMsgName ?: @"") copy] autorelease];
    NSString *page = [[(gJCG60TabLua ?: gJCG60UILua ?: @"") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return [NSString stringWithFormat:@"Protobuf：发送%@ 接收%@｜Req%llu Resp%llu Raw%llu 解析失败%llu\n最新：%lld %@｜%@",
            send ? @"✅" : @"…", parse ? @"✅" : @"…", req, resp, raw, fail,
            msgid, name.length ? name : @"暂无", page.length ? page : @"暂无页面"];
}

'''

rep(
    "#pragma mark - Dynamic symbols / loader hooks\n",
    core + "#pragma mark - Dynamic symbols / loader hooks\n",
    "v0.6.0 core insertion",
)

# Enrich all validated JSON metadata with the Lua page context captured at body
# observation time, so existing manifests/request traces gain page_context too.
rep(
    "    NSData *snapshot = [body retain];\n"
    "    NSDictionary *metaSnapshot = [[requestMeta ?: @{} copy] autorelease];\n"
    "    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {\n",
    "    NSData *snapshot = [body retain];\n"
    "    NSMutableDictionary *metaMerged = [NSMutableDictionary dictionaryWithDictionary:(requestMeta ?: @{})];\n"
    "    [metaMerged addEntriesFromDictionary:JCG60PageContextSnapshot()];\n"
    "    NSDictionary *metaSnapshot = [[metaMerged copy] autorelease];\n"
    "    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {\n",
    "JSON page metadata enrichment",
)

# Only fully parsed JSON enters the page map.
rep(
    "        if (JCG59ShouldCountValidatedMeta(metaSnapshot)) JCG59RecordResponse(metaSnapshot, 1, snapshot.length);\n\n"
    "        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];\n",
    "        if (JCG59ShouldCountValidatedMeta(metaSnapshot)) JCG59RecordResponse(metaSnapshot, 1, snapshot.length);\n"
    "        JCG60RecordPageJSON(metaSnapshot, snapshot.length);\n\n"
    "        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];\n",
    "JSON page-map event",
)

# Use the already serialized Lua loader thread as the wrapper-install point and
# update page context independently of the loader file dedupe cache.
rep(
    "static int JCG5HookTolua(void *L, const char *buffer, int size, const char *name) {\n"
    "    JCG58TryInstallSocketHTTP(L);\n"
    "    BOOL enabled; pthread_mutex_lock(&gJCG5StateLock);enabled=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);\n",
    "static int JCG5HookTolua(void *L, const char *buffer, int size, const char *name) {\n"
    "    JCG58TryInstallSocketHTTP(L);\n"
    "    JCG60TryInstallProtobuf(L);\n"
    "    BOOL enabled; pthread_mutex_lock(&gJCG5StateLock);enabled=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);\n"
    "    if (enabled && name) JCG60NoteLuaChunk(name);\n",
    "tolua protobuf/page integration",
)

rep(
    "static int JCG5HookLuaLX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {\n"
    "    JCG58TryInstallSocketHTTP(L);\n"
    "    BOOL enabled; pthread_mutex_lock(&gJCG5StateLock);enabled=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);\n",
    "static int JCG5HookLuaLX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {\n"
    "    JCG58TryInstallSocketHTTP(L);\n"
    "    JCG60TryInstallProtobuf(L);\n"
    "    BOOL enabled; pthread_mutex_lock(&gJCG5StateLock);enabled=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);\n"
    "    if (enabled && name) JCG60NoteLuaChunk(name);\n",
    "luaL protobuf/page integration",
)

rep(
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应抓取"],@[@"socket",@"SocketHTTP"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应抓取"],@[@"socket",@"SocketHTTP"],@[@"protobuf",@"页面 / Protobuf"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    "protobuf UI row",
)

rep(
    '    self.labels[@"socket"].text=JCG58SocketStatusText();\n    self.labels[@"scan"].text=',
    '    self.labels[@"socket"].text=JCG58SocketStatusText();\n    self.labels[@"protobuf"].text=JCG60ProtoStatusText();\n    self.labels[@"scan"].text=',
    "protobuf UI refresh",
)

p.write_text(s, encoding="utf-8")
print("applied v0.6.0 page-context protobuf business capture")
