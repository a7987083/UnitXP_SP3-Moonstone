#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_PAGE_SNAPSHOT_V070"
if MARKER in s:
    print("v0.7.0 page snapshot patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_PROTOBUF_V060",
    "JCG5_PAGE_PROTOBUF_V060_HARDENED",
    "JCG5_NETWORK_COVERAGE_V059",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.7.0 patch anchor missing: {label}")
    s = s.replace(old, new, 1)

# Forward declarations used by the already-existing JSON/protobuf capture paths.
rep(
    "static void JCG55AppendJSONLine(NSString *path, NSDictionary *obj);\n",
    "static void JCG55AppendJSONLine(NSString *path, NSDictionary *obj);\n"
    "// JCG5_PAGE_SNAPSHOT_V070\n"
    "static void JCG70RecordJSONSnapshot(NSDictionary *meta, id obj, NSUInteger bytes);\n"
    "static void JCG70RecordProtobufSnapshot(NSDictionary *event);\n",
    "snapshot forward declarations",
)

# Descriptor-aware table-key recovery. Lua protobuf stores message values in
# _fields keyed by FieldDescriptor tables. v0.6.0 treated every table key as the
# same <key-type-5> string, which both hid names and overwrote sibling fields.
descriptor_helpers = r'''
// JCG5_PAGE_SNAPSHOT_V070 descriptor-aware key recovery.
// A descriptor key is accepted only when name + number + full_name are present;
// arbitrary table keys retain a pointer-derived stable diagnostic key.
static NSString *JCG70DescriptorKeyName(void *L, int idx) {
    if (!L || !gJCG58LuaGetTop || !gJCG58LuaSetTop || !gJCG58LuaType ||
        !gJCG60LuaGetField || !gJCG58LuaToLString || !gJCG58LuaToIntegerX) return nil;
    int top = gJCG58LuaGetTop(L);
    int abs = JCG60AbsIndex(L, idx);
    if (gJCG58LuaType(L, abs) != JCG60_LUA_TTABLE) return nil;

    NSString *name = nil, *fullName = nil;
    int numberOK = 0;
    gJCG60LuaGetField(L, abs, "name");
    if (gJCG58LuaType(L, -1) == JCG60_LUA_TSTRING) {
        size_t n = 0; const char *p = gJCG58LuaToLString(L, -1, &n);
        if (p && n > 0 && n < 512) name = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
    }
    gJCG58LuaSetTop(L, top);

    gJCG60LuaGetField(L, abs, "number");
    (void)gJCG58LuaToIntegerX(L, -1, &numberOK);
    gJCG58LuaSetTop(L, top);

    gJCG60LuaGetField(L, abs, "full_name");
    if (gJCG58LuaType(L, -1) == JCG60_LUA_TSTRING) {
        size_t n = 0; const char *p = gJCG58LuaToLString(L, -1, &n);
        if (p && n > 0 && n < 2048) fullName = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
    }
    gJCG58LuaSetTop(L, top);

    if (name.length && numberOK && fullName.length) return name;
    return nil;
}

static NSString *JCG70StableTableKey(void *L, int idx) {
    NSString *descriptor = JCG70DescriptorKeyName(L, idx);
    if (descriptor.length) return descriptor;
    const void *ptr = gJCG60LuaToPointer ? gJCG60LuaToPointer(L, JCG60AbsIndex(L, idx)) : NULL;
    return ptr ? [NSString stringWithFormat:@"<table-key:%p>", ptr] : @"<table-key>";
}

'''
rep(
    "static id JCG60SnapshotLuaValue(void *L, int idx, NSUInteger depth, NSMutableSet *visited, NSUInteger *budget) {\n",
    descriptor_helpers + "static id JCG60SnapshotLuaValue(void *L, int idx, NSUInteger depth, NSMutableSet *visited, NSUInteger *budget) {\n",
    "descriptor helper insertion",
)

rep(
    '''            } else if (keyType == JCG60_LUA_TNUMBER) {
                int ok = 0; int64_t kv = gJCG58LuaToIntegerX(L, -2, &ok);
                if (ok && kv > 0 && kv <= 1000000) { positiveIndex = YES; arrayIndex = (NSUInteger)kv; }
                else if (ok) key = [NSString stringWithFormat:@"%lld", (long long)kv];
            }
''',
    '''            } else if (keyType == JCG60_LUA_TNUMBER) {
                int ok = 0; int64_t kv = gJCG58LuaToIntegerX(L, -2, &ok);
                if (ok && kv > 0 && kv <= 1000000) { positiveIndex = YES; arrayIndex = (NSUInteger)kv; }
                else if (ok) key = [NSString stringWithFormat:@"%lld", (long long)kv];
            } else if (keyType == JCG60_LUA_TTABLE) {
                key = JCG70StableTableKey(L, -2);
            }
''',
    "descriptor table-key handling",
)

helpers = r'''
// Normalize the Python-style Lua protobuf runtime object into JSON-oriented
// data. Exact raw protobuf bytes remain preserved separately, so this view can
// be regenerated if a game-specific protobuf fork needs different semantics.
static BOOL JCG70PositiveIndex(NSString *s, NSUInteger *outValue) {
    if (![s isKindOfClass:[NSString class]] || !s.length) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    NSInteger value = 0;
    if (![scanner scanInteger:&value] || !scanner.isAtEnd || value <= 0) return NO;
    if (outValue) *outValue = (NSUInteger)value;
    return YES;
}

static id JCG70NormalizeProtobufObject(id obj) {
    if (!obj || obj == [NSNull null]) return [NSNull null];
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[obj count]];
        for (id v in (NSArray *)obj) [out addObject:JCG70NormalizeProtobufObject(v) ?: [NSNull null]];
        return out;
    }
    if (![obj isKindOfClass:[NSDictionary class]]) return obj;

    NSDictionary *d = (NSDictionary *)obj;
    id fields = [d objectForKey:@"_fields"];
    if ([fields isKindOfClass:[NSDictionary class]]) {
        return JCG70NormalizeProtobufObject(fields);
    }

    NSMutableDictionary *named = [NSMutableDictionary dictionary];
    NSMutableDictionary *numeric = [NSMutableDictionary dictionary];
    NSUInteger maxIndex = 0;
    BOOL hasNamed = NO;
    for (id rawKey in d) {
        NSString *key = [rawKey isKindOfClass:[NSString class]] ? rawKey : [rawKey description];
        if (!key.length) continue;
        if ([key hasPrefix:@"_"]) continue; // protobuf runtime bookkeeping
        id value = JCG70NormalizeProtobufObject([d objectForKey:rawKey]) ?: [NSNull null];
        NSUInteger idx = 0;
        if (JCG70PositiveIndex(key, &idx) && idx <= 1000000) {
            [numeric setObject:value forKey:@(idx)];
            if (idx > maxIndex) maxIndex = idx;
        } else {
            hasNamed = YES;
            [named setObject:value forKey:key];
        }
    }

    if (!hasNamed && numeric.count && maxIndex == numeric.count && maxIndex <= 8192) {
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:maxIndex];
        for (NSUInteger i = 1; i <= maxIndex; i++) {
            [arr addObject:[numeric objectForKey:@(i)] ?: [NSNull null]];
        }
        return arr;
    }
    for (NSNumber *n in numeric) [named setObject:[numeric objectForKey:n] ?: [NSNull null] forKey:n.stringValue];
    return named;
}

static NSMutableDictionary *gJCG70MsgIDsByName;
static NSMutableDictionary *gJCG70PendingByResponse;
static NSMutableSet *gJCG70CapturedTabConfigs;

static void JCG70BuildMsgIDsByName(void *L) {
    if (!gJCG60MsgNamesReady) JCG60BuildMsgNames(L);
    if (!gJCG60MsgNames.count) return;
    if (!gJCG70MsgIDsByName) gJCG70MsgIDsByName = [[NSMutableDictionary alloc] init];
    if (gJCG70MsgIDsByName.count) return;
    for (NSNumber *msgid in gJCG60MsgNames) {
        NSString *name = [gJCG60MsgNames objectForKey:msgid];
        if (name.length && ![gJCG70MsgIDsByName objectForKey:name]) [gJCG70MsgIDsByName setObject:msgid forKey:name];
    }
}

static long long JCG70ExpectedResponseMsgID(void *L, long long requestMsgID, NSString *requestName, NSString **responseNameOut) {
    JCG70BuildMsgIDsByName(L);
    NSString *responseName = nil;
    NSNumber *responseID = nil;
    if ([requestName hasSuffix:@"_REQ"]) {
        responseName = [[requestName substringToIndex:requestName.length - 4] stringByAppendingString:@"_RESP"];
        responseID = [gJCG70MsgIDsByName objectForKey:responseName];
    }
    if (!responseID) {
        responseID = @(requestMsgID);
        responseName = [gJCG60MsgNames objectForKey:responseID] ?: requestName;
    }
    if (responseNameOut) *responseNameOut = responseName ?: @"";
    return responseID.longLongValue;
}

static void JCG70RememberPendingRequest(void *L, NSMutableDictionary *event) {
    if (!event) return;
    long long reqID = [[event objectForKey:@"msgid"] longLongValue];
    NSString *reqName = [event objectForKey:@"msg_name"] ?: @"";
    NSString *respName = nil;
    long long respID = JCG70ExpectedResponseMsgID(L, reqID, reqName, &respName);
    [event setObject:@(respID) forKey:@"expected_response_msgid"];
    if (respName.length) [event setObject:respName forKey:@"expected_response_name"];

    if (!gJCG70PendingByResponse) gJCG70PendingByResponse = [[NSMutableDictionary alloc] init];
    NSNumber *key = @(respID);
    NSMutableArray *queue = [gJCG70PendingByResponse objectForKey:key];
    if (!queue) {
        queue = [NSMutableArray array];
        [gJCG70PendingByResponse setObject:queue forKey:key];
    }
    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    NSArray *copyKeys = @[@"page_context", @"page_context_kind", @"page_context_age_ms",
                          @"page_tab_lua", @"page_ui_lua", @"latest_lua"];
    for (NSString *k in copyKeys) {
        id v = [event objectForKey:k]; if (v) [ctx setObject:v forKey:k];
    }
    [ctx setObject:([event objectForKey:@"sequence"] ?: @0) forKey:@"request_sequence"];
    [ctx setObject:@(reqID) forKey:@"request_msgid"];
    [ctx setObject:reqName forKey:@"request_msg_name"];
    [ctx setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"request_time"];
    [queue addObject:ctx];
    while (queue.count > 64) [queue removeObjectAtIndex:0];
}

static NSDictionary *JCG70TakePendingResponse(long long responseMsgID) {
    NSMutableArray *queue = [gJCG70PendingByResponse objectForKey:@(responseMsgID)];
    if (!queue.count) return nil;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    while (queue.count) {
        NSDictionary *ctx = [[queue objectAtIndex:0] retain];
        [queue removeObjectAtIndex:0];
        NSTimeInterval t = [[ctx objectForKey:@"request_time"] doubleValue];
        if (t <= 0 || now - t <= 120.0) return [ctx autorelease];
        [ctx release];
    }
    return nil;
}

static NSString *JCG70TabGlobalName(NSString *chunk) {
    if (!chunk.length) return @"";
    NSString *stem = [[chunk lastPathComponent] stringByDeletingPathExtension];
    NSRange r = [stem rangeOfString:@"_" options:NSBackwardsSearch];
    if (r.location != NSNotFound && r.location + 1 < stem.length) {
        NSString *suffix = [stem substringFromIndex:r.location + 1];
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if (suffix.length <= 4 && [suffix rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            stem = [stem substringToIndex:r.location];
        }
    }
    return stem ?: @"";
}

static void JCG70AttachLocalTabConfig(void *L, NSMutableDictionary *event) {
    if (!L || !event || !gJCG58LuaGetGlobal || !gJCG58LuaGetTop || !gJCG58LuaSetTop) return;
    NSString *tab = [event objectForKey:@"page_tab_lua"];
    if (!tab.length) return;
    NSString *globalName = JCG70TabGlobalName(tab);
    if (!globalName.length) return;
    if (!gJCG70CapturedTabConfigs) gJCG70CapturedTabConfigs = [[NSMutableSet alloc] init];
    if ([gJCG70CapturedTabConfigs containsObject:globalName]) return;

    int top = gJCG58LuaGetTop(L);
    int t = gJCG58LuaGetGlobal(L, globalName.UTF8String);
    if (t == JCG60_LUA_TTABLE) {
        id snapshot = JCG60Snapshot(L, -1);
        if (snapshot) {
            [event setObject:globalName forKey:@"page_local_tab_global"];
            [event setObject:snapshot forKey:@"page_local_tab_config"];
            [gJCG70CapturedTabConfigs addObject:globalName];
        }
    }
    gJCG58LuaSetTop(L, top);
}

'''
rep(
    "static void JCG60QueueProtobufEvent(NSDictionary *event, NSData *rawPayload) {\n",
    helpers + "static void JCG60QueueProtobufEvent(NSDictionary *event, NSData *rawPayload) {\n",
    "protobuf helpers insertion",
)

# Normalize decoded protobuf objects before they leave the Lua VM thread.
rep(
    "                id snapshot = JCG60Snapshot(L, 2);\n",
    "                id snapshot = JCG70NormalizeProtobufObject(JCG60Snapshot(L, 2));\n",
    "request protobuf normalization",
)
rep(
    "        id snapshot = JCG60Snapshot(L, resultObjIndex);\n",
    "        id snapshot = JCG70NormalizeProtobufObject(JCG60Snapshot(L, resultObjIndex));\n",
    "response protobuf normalization",
)

# Capture local TAB config once and remember the request->expected-response page.
rep(
    "            JCG60QueueProtobufEvent(event, nil);\n"
    "            JCG5Log([NSString stringWithFormat:@\"PROTOBUF request seq=%llu msgid=%lld name=%@ page=%@\", seq, msgid, JCG60MsgName(L, msgid), [event objectForKey:@\"page_context\"] ?: @\"\"]);\n",
    "            JCG70AttachLocalTabConfig(L, event);\n"
    "            JCG70RememberPendingRequest(L, event);\n"
    "            JCG60QueueProtobufEvent(event, nil);\n"
    "            JCG5Log([NSString stringWithFormat:@\"PROTOBUF request seq=%llu msgid=%lld name=%@ page=%@\", seq, msgid, JCG60MsgName(L, msgid), [event objectForKey:@\"page_context\"] ?: @\"\"]);\n",
    "request pending/local-config integration",
)

# Response page context inherits the actual request page when a request pair is
# available. Unmatched responses remain visible as push/unsolicited traffic.
rep(
    "        NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:JCG60PageContextSnapshot()];\n"
    "        [event setObject:@1 forKey:@\"schema\"];\n"
    "        [event setObject:@\"response\" forKey:@\"direction\"];\n",
    "        NSDictionary *livePage = JCG60PageContextSnapshot();\n"
    "        NSDictionary *matchedRequest = JCG70TakePendingResponse(msgid);\n"
    "        NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:livePage];\n"
    "        if (matchedRequest) {\n"
    "            for (NSString *k in @[@\"page_context\", @\"page_context_kind\", @\"page_context_age_ms\", @\"page_tab_lua\", @\"page_ui_lua\", @\"latest_lua\"]) {\n"
    "                id v = [matchedRequest objectForKey:k]; if (v) [event setObject:v forKey:k];\n"
    "            }\n"
    "            [event setObject:@YES forKey:@\"matched_request\"];\n"
    "            [event setObject:([matchedRequest objectForKey:@\"request_sequence\"] ?: @0) forKey:@\"request_sequence\"];\n"
    "            [event setObject:([matchedRequest objectForKey:@\"request_msgid\"] ?: @0) forKey:@\"request_msgid\"];\n"
    "            [event setObject:([matchedRequest objectForKey:@\"request_msg_name\"] ?: @\"\") forKey:@\"request_msg_name\"];\n"
    "            [event setObject:@\"response\" forKey:@\"flow_kind\"];\n"
    "        } else {\n"
    "            [event setObject:@NO forKey:@\"matched_request\"];\n"
    "            [event setObject:@\"push_or_unsolicited\" forKey:@\"flow_kind\"];\n"
    "        }\n"
    "        [event setObject:@1 forKey:@\"schema\"];\n"
    "        [event setObject:@\"response\" forKey:@\"direction\"];\n",
    "response request-page inheritance",
)

rep(
    "        JCG60QueueProtobufEvent(event, raw);\n"
    "        JCG5Log([NSString stringWithFormat:@\"PROTOBUF response seq=%llu msgid=%lld name=%@ bytes=%lu page=%@\", seq, msgid, JCG60MsgName(L, msgid), (unsigned long)raw.length, [event objectForKey:@\"page_context\"] ?: @\"\"]);\n",
    "        JCG70AttachLocalTabConfig(L, event);\n"
    "        JCG60QueueProtobufEvent(event, raw);\n"
    "        JCG5Log([NSString stringWithFormat:@\"PROTOBUF response seq=%llu msgid=%lld name=%@ bytes=%lu page=%@ matched=%@\", seq, msgid, JCG60MsgName(L, msgid), (unsigned long)raw.length, [event objectForKey:@\"page_context\"] ?: @\"\", [[event objectForKey:@\"matched_request\"] boolValue] ? @\"yes\" : @\"no\"]);\n",
    "response local-config integration",
)

# Record page snapshots only after raw_file/hash enrichment is complete.
rep(
    "        JCG55AppendJSONLine(gJCG60ProtoEventsPath, record);\n"
    "        JCG60RecordPageProtobuf(record);\n",
    "        JCG55AppendJSONLine(gJCG60ProtoEventsPath, record);\n"
    "        JCG60RecordPageProtobuf(record);\n"
    "        JCG70RecordProtobufSnapshot(record);\n",
    "protobuf snapshot feed",
)

# Preserve the page captured at UnityWebRequest send time. The later JSON body
# observer must not overwrite it just because another Lua chunk loaded meanwhile.
rep(
    "static void *JCG56HookSendWebRequest(void *self, const void *methodInfo) {\n",
    "static NSDictionary *JCG60PageContextSnapshot(void);\n"
    "static void *JCG56HookSendWebRequest(void *self, const void *methodInfo) {\n",
    "Unity page-context forward declaration",
)
rep(
    "        NSDictionary *ctx = [[NSDictionary alloc] initWithObjectsAndKeys:\n"
    "                             [NSValue valueWithPointer:self], @\"request\",\n"
    "                             (url ?: @\"\"), @\"url\",\n"
    "                             (httpMethod ?: @\"\"), @\"method\",\n"
    "                             nil];\n",
    "        NSMutableDictionary *ctx = [[NSMutableDictionary alloc] initWithObjectsAndKeys:\n"
    "                                      [NSValue valueWithPointer:self], @\"request\",\n"
    "                                      (url ?: @\"\"), @\"url\",\n"
    "                                      (httpMethod ?: @\"\"), @\"method\",\n"
    "                                      nil];\n"
    "        [ctx addEntriesFromDictionary:JCG60PageContextSnapshot()];\n",
    "Unity request page capture",
)
rep(
    "    [metaMerged addEntriesFromDictionary:JCG60PageContextSnapshot()];\n",
    "    if (![[metaMerged objectForKey:@\"page_context\"] length]) [metaMerged addEntriesFromDictionary:JCG60PageContextSnapshot()];\n",
    "preserve request-time JSON page",
)

# Feed the fully parsed JSON body into the page snapshot reducer.
rep(
    "        JCG60RecordPageJSON(metaSnapshot, snapshot.length);\n\n"
    "        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];\n",
    "        JCG60RecordPageJSON(metaSnapshot, snapshot.length);\n"
    "        JCG70RecordJSONSnapshot(metaSnapshot, obj, snapshot.length);\n\n"
    "        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];\n",
    "JSON snapshot feed",
)

snapshot_core = r'''
// v0.7.0 Page Snapshot reducer. All mutation happens on the existing serial
// capture queue. There is no new native hook, constructor, polling loop, TLS,
// or dispatch queue.
#define JCG70_PAGE_EVENT_MAX 2048

static NSString *gJCG70SnapshotDir;
static NSString *gJCG70SnapshotIndexPath;
static NSMutableDictionary *gJCG70Snapshots;
static NSMutableDictionary *gJCG70SnapshotIndex;
static NSMutableSet *gJCG70SnapshotWritePending;
static unsigned long long gJCG70SnapshotPages = 0;
static unsigned long long gJCG70SnapshotWrites = 0;
static unsigned long long gJCG70DescriptorFields = 0;
static NSString *gJCG70LastSnapshotFile;

static NSString *JCG70PageSessionKey(NSDictionary *event) {
    NSString *ui = [event objectForKey:@"page_ui_lua"] ?: @"";
    NSString *tab = [event objectForKey:@"page_tab_lua"] ?: @"";
    NSString *page = [event objectForKey:@"page_context"] ?: @"";
    if (ui.length && tab.length) return [NSString stringWithFormat:@"%@|%@", ui, tab];
    if (tab.length) return tab;
    if (ui.length) return ui;
    return page.length ? page : @"(unknown)";
}

static NSString *JCG70SafeFilename(NSString *name) {
    if (!name.length) return @"unknown";
    NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [allowed addCharactersInString:@"._-"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:[allowed invertedSet]];
    NSString *safe = [parts componentsJoinedByString:@"_"];
    while ([safe containsString:@"__"]) safe = [safe stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    if (safe.length > 150) safe = [safe substringToIndex:150];
    return safe.length ? safe : @"unknown";
}

static NSString *JCG70DisplayURL(NSString *raw) {
    NSURLComponents *c = [NSURLComponents componentsWithString:(raw ?: @"")];
    if (!c || !c.scheme.length) return @"";
    c.query = nil; c.fragment = nil; c.user = nil; c.password = nil;
    return c.string ?: @"";
}

static void JCG70EnsureSnapshotPaths(void) {
    if (!gJCG70SnapshotDir) gJCG70SnapshotDir = [[gJCG5Root stringByAppendingPathComponent:@"runtime_page_snapshot"] retain];
    if (!gJCG70SnapshotIndexPath) gJCG70SnapshotIndexPath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_page_snapshot_index.json"] retain];
    JCG5EnsureDir(gJCG70SnapshotDir);
    if (!gJCG70Snapshots) gJCG70Snapshots = [[NSMutableDictionary alloc] init];
    if (!gJCG70SnapshotIndex) gJCG70SnapshotIndex = [[NSMutableDictionary alloc] init];
    if (!gJCG70SnapshotWritePending) gJCG70SnapshotWritePending = [[NSMutableSet alloc] init];
}

static id JCG70DeepMerge(id oldValue, id newValue) {
    if (!newValue) return oldValue ?: [NSNull null];
    if (![oldValue isKindOfClass:[NSDictionary class]] || ![newValue isKindOfClass:[NSDictionary class]]) return newValue;
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:oldValue];
    for (id key in (NSDictionary *)newValue) {
        id incoming = [newValue objectForKey:key];
        id existing = [out objectForKey:key];
        [out setObject:JCG70DeepMerge(existing, incoming) ?: [NSNull null] forKey:key];
    }
    return out;
}

static NSMutableDictionary *JCG70SnapshotEntry(NSDictionary *event) {
    JCG70EnsureSnapshotPaths();
    NSString *sessionKey = JCG70PageSessionKey(event);
    NSMutableDictionary *entry = [gJCG70Snapshots objectForKey:sessionKey];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        [entry setObject:@1 forKey:@"schema"];
        [entry setObject:@"observed_page_snapshot" forKey:@"snapshot_kind"];
        [entry setObject:sessionKey forKey:@"page_session_key"];
        [entry setObject:([event objectForKey:@"page_context"] ?: @"") forKey:@"page_context"];
        [entry setObject:([event objectForKey:@"page_ui_lua"] ?: @"") forKey:@"page_ui_lua"];
        [entry setObject:([event objectForKey:@"page_tab_lua"] ?: @"") forKey:@"page_tab_lua"];
        [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"first_seen"];
        [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_seen"];
        [entry setObject:[NSMutableDictionary dictionaryWithDictionary:@{
            @"json_events": @0, @"protobuf_requests": @0, @"protobuf_responses": @0,
            @"matched_responses": @0, @"push_or_unsolicited": @0
        }] forKey:@"counts"];
        [entry setObject:[NSMutableDictionary dictionary] forKey:@"json_state"];
        [entry setObject:[NSMutableDictionary dictionary] forKey:@"protobuf_state"];
        [entry setObject:[NSMutableDictionary dictionary] forKey:@"flows"];
        [entry setObject:[NSMutableArray array] forKey:@"events"];
        [entry setObject:@{
            @"scope": @"all observed client data associated with this Lua page context",
            @"protobuf_fields": @"runtime descriptor driven",
            @"merge_policy": @"exact event history + latest recursive merge per message/endpoint",
            @"screen_widget_state": @NO
        } forKey:@"completeness"];
        [gJCG70Snapshots setObject:entry forKey:sessionKey];
        pthread_mutex_lock(&gJCG5StateLock); gJCG70SnapshotPages++; pthread_mutex_unlock(&gJCG5StateLock);
    }
    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_seen"];
    NSString *ctx = [event objectForKey:@"page_context"]; if (ctx.length) [entry setObject:ctx forKey:@"page_context"];
    NSString *ui = [event objectForKey:@"page_ui_lua"]; if (ui.length) [entry setObject:ui forKey:@"page_ui_lua"];
    NSString *tab = [event objectForKey:@"page_tab_lua"]; if (tab.length) [entry setObject:tab forKey:@"page_tab_lua"];
    id localConfig = [event objectForKey:@"page_local_tab_config"];
    if (localConfig) {
        [entry setObject:localConfig forKey:@"local_tab_config"];
        NSString *global = [event objectForKey:@"page_local_tab_global"];
        if (global.length) [entry setObject:global forKey:@"local_tab_global"];
    }
    return entry;
}

static void JCG70BumpCount(NSMutableDictionary *entry, NSString *key) {
    NSMutableDictionary *counts = [entry objectForKey:@"counts"];
    unsigned long long n = [[counts objectForKey:key] unsignedLongLongValue];
    [counts setObject:@(n + 1) forKey:key];
}

static void JCG70AppendEvent(NSMutableDictionary *entry, NSDictionary *event) {
    NSMutableArray *events = [entry objectForKey:@"events"];
    if (events.count < JCG70_PAGE_EVENT_MAX) [events addObject:event];
    else [entry setObject:@YES forKey:@"events_truncated"];
}

static void JCG70WriteIndex(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in [[gJCG70SnapshotIndex allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *v = [gJCG70SnapshotIndex objectForKey:key];
        if (v) [items addObject:v];
    }
    NSDictionary *root = @{@"schema": @1,
                           @"updated_at": @([[NSDate date] timeIntervalSince1970]),
                           @"pages": items};
    NSData *d = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (d.length) [d writeToFile:gJCG70SnapshotIndexPath options:NSDataWritingAtomic error:nil];
}

static void JCG70WriteSnapshotNow(NSString *sessionKey) {
    JCG70EnsureSnapshotPaths();
    NSMutableDictionary *entry = [gJCG70Snapshots objectForKey:sessionKey];
    if (!entry) { [gJCG70SnapshotWritePending removeObject:sessionKey]; return; }
    NSString *ui = [[entry objectForKey:@"page_ui_lua"] stringByDeletingPathExtension] ?: @"";
    NSString *tab = [[entry objectForKey:@"page_tab_lua"] stringByDeletingPathExtension] ?: @"";
    NSString *base = nil;
    if (ui.length && tab.length) base = [NSString stringWithFormat:@"%@__%@", ui, tab];
    else base = ui.length ? ui : (tab.length ? tab : sessionKey);
    NSString *file = [[JCG70SafeFilename(base) stringByAppendingPathExtension:@"json"] copy];
    NSString *path = [gJCG70SnapshotDir stringByAppendingPathComponent:file];
    [entry setObject:file forKey:@"snapshot_file"];
    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"snapshot_written_at"];

    NSError *err = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingPrettyPrinted error:&err];
    if (d.length && [d writeToFile:path options:NSDataWritingAtomic error:&err]) {
        NSDictionary *idx = @{
            @"page_session_key": sessionKey,
            @"page_context": [entry objectForKey:@"page_context"] ?: @"",
            @"page_ui_lua": [entry objectForKey:@"page_ui_lua"] ?: @"",
            @"page_tab_lua": [entry objectForKey:@"page_tab_lua"] ?: @"",
            @"file": file,
            @"events": @([[(NSArray *)[entry objectForKey:@"events"] count] unsignedLongLongValue]),
            @"updated_at": [entry objectForKey:@"last_seen"] ?: @0
        };
        [gJCG70SnapshotIndex setObject:idx forKey:sessionKey];
        JCG70WriteIndex();
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG70SnapshotWrites++;
        [gJCG70LastSnapshotFile release]; gJCG70LastSnapshotFile = [file copy];
        pthread_mutex_unlock(&gJCG5StateLock);
        JCG5Log([NSString stringWithFormat:@"PAGE-SNAPSHOT saved page=%@ events=%lu file=%@ bytes=%lu",
                 sessionKey, (unsigned long)[[entry objectForKey:@"events"] count], file, (unsigned long)d.length]);
    } else {
        JCG5Log([NSString stringWithFormat:@"PAGE-SNAPSHOT write failed page=%@ error=%@", sessionKey, err ?: @"unknown"]);
    }
    [file release];
    [gJCG70SnapshotWritePending removeObject:sessionKey];
}

static void JCG70ScheduleSnapshotWrite(NSString *sessionKey) {
    if (!gJCG5CaptureQueue || !sessionKey.length) return;
    JCG70EnsureSnapshotPaths();
    if ([gJCG70SnapshotWritePending containsObject:sessionKey]) return;
    [gJCG70SnapshotWritePending addObject:sessionKey];
    NSString *key = [sessionKey copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.60 * NSEC_PER_SEC)), gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG70WriteSnapshotNow(key);
        [key release];
    }});
}

static void JCG70RecordJSONSnapshot(NSDictionary *meta, id obj, NSUInteger bytes) {
    if (!meta || !obj) return;
    NSMutableDictionary *entry = JCG70SnapshotEntry(meta);
    JCG70BumpCount(entry, @"json_events");
    NSString *endpoint = JCG59EndpointKey([meta objectForKey:@"url"] ?: @"", [meta objectForKey:@"method"] ?: @"");
    NSMutableDictionary *jsonState = [entry objectForKey:@"json_state"];
    NSMutableDictionary *slot = [NSMutableDictionary dictionary];
    [slot setObject:endpoint.length ? endpoint : @"(no-endpoint)" forKey:@"endpoint"];
    [slot setObject:JCG70DisplayURL([meta objectForKey:@"url"]) forKey:@"url"];
    [slot setObject:([meta objectForKey:@"method"] ?: @"") forKey:@"method"];
    [slot setObject:([meta objectForKey:@"http_status"] ?: @0) forKey:@"http_status"];
    [slot setObject:@(bytes) forKey:@"bytes"];
    [slot setObject:([meta objectForKey:@"classification"] ?: @"json") forKey:@"classification"];
    [slot setObject:obj forKey:@"data"];
    [slot setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"time"];
    id oldData = [[jsonState objectForKey:endpoint] objectForKey:@"data"];
    if (oldData) [slot setObject:JCG70DeepMerge(oldData, obj) forKey:@"data"];
    [jsonState setObject:slot forKey:endpoint.length ? endpoint : @"(no-endpoint)"];

    NSDictionary *ev = @{
        @"kind": @"json",
        @"time": @([[NSDate date] timeIntervalSince1970]),
        @"endpoint": endpoint.length ? endpoint : @"(no-endpoint)",
        @"method": [meta objectForKey:@"method"] ?: @"",
        @"http_status": [meta objectForKey:@"http_status"] ?: @0,
        @"bytes": @(bytes),
        @"data": obj
    };
    JCG70AppendEvent(entry, ev);
    JCG70ScheduleSnapshotWrite(JCG70PageSessionKey(meta));
}

static void JCG70RecordProtobufSnapshot(NSDictionary *event) {
    if (!event) return;
    NSMutableDictionary *entry = JCG70SnapshotEntry(event);
    NSString *direction = [event objectForKey:@"direction"] ?: @"";
    NSString *name = [event objectForKey:@"msg_name"] ?: [NSString stringWithFormat:@"MSGID_%@", [event objectForKey:@"msgid"] ?: @0];
    id decoded = [event objectForKey:@"decoded"] ?: [NSNull null];

    if ([direction isEqualToString:@"request"]) JCG70BumpCount(entry, @"protobuf_requests");
    else {
        JCG70BumpCount(entry, @"protobuf_responses");
        if ([[event objectForKey:@"matched_request"] boolValue]) JCG70BumpCount(entry, @"matched_responses");
        else JCG70BumpCount(entry, @"push_or_unsolicited");
    }

    NSMutableDictionary *pbState = [entry objectForKey:@"protobuf_state"];
    NSMutableDictionary *slot = [pbState objectForKey:name];
    if (!slot) { slot = [NSMutableDictionary dictionary]; [pbState setObject:slot forKey:name]; }
    [slot setObject:([event objectForKey:@"msgid"] ?: @0) forKey:@"msgid"];
    [slot setObject:name forKey:@"msg_name"];
    [slot setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_time"];
    if ([direction isEqualToString:@"request"]) {
        [slot setObject:decoded forKey:@"last_request"];
    } else {
        id old = [slot objectForKey:@"merged_response"];
        [slot setObject:JCG70DeepMerge(old, decoded) forKey:@"merged_response"];
        [slot setObject:decoded forKey:@"last_response"];
        if ([event objectForKey:@"raw_file"]) [slot setObject:[event objectForKey:@"raw_file"] forKey:@"last_raw_file"];
        if ([event objectForKey:@"raw_sha256"]) [slot setObject:[event objectForKey:@"raw_sha256"] forKey:@"last_raw_sha256"];
    }

    NSMutableDictionary *flows = [entry objectForKey:@"flows"];
    NSNumber *flowKey = nil;
    if ([direction isEqualToString:@"request"]) flowKey = [event objectForKey:@"sequence"];
    else flowKey = [event objectForKey:@"request_sequence"];
    if (flowKey) {
        NSString *fk = [flowKey stringValue];
        NSMutableDictionary *flow = [flows objectForKey:fk];
        if (!flow) { flow = [NSMutableDictionary dictionary]; [flows setObject:flow forKey:fk]; }
        if ([direction isEqualToString:@"request"]) {
            [flow setObject:@{
                @"sequence": [event objectForKey:@"sequence"] ?: @0,
                @"msgid": [event objectForKey:@"msgid"] ?: @0,
                @"msg_name": name,
                @"data": decoded,
                @"time": [event objectForKey:@"time"] ?: @0
            } forKey:@"request"];
        } else {
            [flow setObject:@{
                @"sequence": [event objectForKey:@"sequence"] ?: @0,
                @"msgid": [event objectForKey:@"msgid"] ?: @0,
                @"msg_name": name,
                @"data": decoded,
                @"raw_file": [event objectForKey:@"raw_file"] ?: @"",
                @"time": [event objectForKey:@"time"] ?: @0
            } forKey:@"response"];
        }
    }

    NSMutableDictionary *ev = [NSMutableDictionary dictionaryWithDictionary:@{
        @"kind": @"protobuf",
        @"direction": direction,
        @"time": [event objectForKey:@"time"] ?: @0,
        @"sequence": [event objectForKey:@"sequence"] ?: @0,
        @"msgid": [event objectForKey:@"msgid"] ?: @0,
        @"msg_name": name,
        @"data": decoded
    }];
    for (NSString *k in @[@"matched_request", @"request_sequence", @"request_msgid", @"request_msg_name",
                           @"flow_kind", @"raw_file", @"raw_bytes", @"raw_sha256"]) {
        id v = [event objectForKey:k]; if (v) [ev setObject:v forKey:k];
    }
    JCG70AppendEvent(entry, ev);
    JCG70ScheduleSnapshotWrite(JCG70PageSessionKey(event));
}

'''
rep(
    "static NSString *JCG60ProtoStatusText(void) {\n",
    snapshot_core + "static NSString *JCG60ProtoStatusText(void) {\n",
    "page snapshot reducer insertion",
)

# Surface snapshot progress in the existing protobuf/page row without adding a
# new view/controller lifecycle.
rep(
    "    NSString *page = [[(gJCG60TabLua ?: gJCG60UILua ?: @\"\") copy] autorelease];\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n"
    "    return [NSString stringWithFormat:@\"Protobuf：发送%@ 接收%@｜Req%llu Resp%llu Raw%llu 解析失败%llu\\n最新：%lld %@｜%@\",\n"
    "            send ? @\"✅\" : @\"…\", parse ? @\"✅\" : @\"…\", req, resp, raw, fail,\n"
    "            msgid, name.length ? name : @\"暂无\", page.length ? page : @\"暂无页面\"];\n",
    "    NSString *page = [[(gJCG60TabLua ?: gJCG60UILua ?: @\"\") copy] autorelease];\n"
    "    unsigned long long snapPages = gJCG70SnapshotPages, snapWrites = gJCG70SnapshotWrites;\n"
    "    NSString *snapFile = [[(gJCG70LastSnapshotFile ?: @\"\") copy] autorelease];\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n"
    "    return [NSString stringWithFormat:@\"Protobuf：发送%@ 接收%@｜Req%llu Resp%llu Raw%llu 解析失败%llu\\n页面快照：%llu页 写入%llu｜%@\\n最新：%lld %@｜%@\",\n"
    "            send ? @\"✅\" : @\"…\", parse ? @\"✅\" : @\"…\", req, resp, raw, fail,\n"
    "            snapPages, snapWrites, snapFile.length ? snapFile : @\"等待页面数据\",\n"
    "            msgid, name.length ? name : @\"暂无\", page.length ? page : @\"暂无页面\"];\n",
    "snapshot UI status",
)

# Emit a readiness marker when the Lua wrappers are installed/reinstalled.
rep(
    "    if (changed) JCG5Log([NSString stringWithFormat:@\"PROTOBUF wrapper ready send=%d parse=%d\", sendReady, parseReady]);\n",
    "    if (changed) {\n"
    "        JCG5Log([NSString stringWithFormat:@\"PROTOBUF wrapper ready send=%d parse=%d\", sendReady, parseReady]);\n"
    "        JCG5Log(@\"PAGE-SNAPSHOT v0.7.0 ready descriptor=runtime page=request-correlated reducer=serial-capture-queue\");\n"
    "    }\n",
    "snapshot readiness log",
)

p.write_text(s, encoding="utf-8")
print("applied v0.7.0 descriptor-driven page snapshot reducer")
