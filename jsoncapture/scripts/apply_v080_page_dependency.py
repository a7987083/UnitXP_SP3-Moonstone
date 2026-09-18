#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_PAGE_DEPENDENCY_V080"
if MARKER in s:
    print("v0.8.0 page dependency patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_PAGE_PROTOBUF_V060_HARDENED",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.0 patch anchor missing: {label}")
    s = s.replace(old, new, 1)

# Forward declarations. v0.8.0 reuses the existing serialized capture queue:
# no new hook, constructor, queue, polling thread, or active network invocation.
rep(
    "static void JCG60NoteLuaChunk(const char *name) {\n",
    "// JCG5_PAGE_DEPENDENCY_V080\n"
    "static void JCG80ObserveLuaChunk(NSString *chunk);\n"
    "static void JCG80ObserveJSON(NSDictionary *meta, id obj, NSUInteger bytes);\n"
    "static void JCG80ObserveProtobuf(NSDictionary *event);\n"
    "static void JCG80Initialize(void);\n"
    "static NSString *JCG80StatusText(void);\n"
    "static void JCG80StartManualCapture(void);\n"
    "static void JCG80StopManualCapture(NSString *reason);\n"
    "static void JCG80ToggleMode(void);\n"
    "static void JCG80ImportWhitelistURL(NSURL *url);\n\n"
    "static void JCG60NoteLuaChunk(const char *name) {\n",
    "v0.8 forward declarations",
)

# Every loader chunk is observed independently of the persistent loader-file
# dedupe cache. This is important because dependency observation is about the
# current page lifetime, not whether the same Lua bytes were seen in a prior run.
rep(
    "    if (isUI) { [gJCG60UILua release]; gJCG60UILua = [base copy]; gJCG60UILuaAt = now; }\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n"
    "}\n\n"
    "static NSDictionary *JCG60PageContextSnapshot(void) {\n",
    "    if (isUI) { [gJCG60UILua release]; gJCG60UILua = [base copy]; gJCG60UILuaAt = now; }\n"
    "    pthread_mutex_unlock(&gJCG5StateLock);\n"
    "    JCG80ObserveLuaChunk(base);\n"
    "}\n\n"
    "static NSDictionary *JCG60PageContextSnapshot(void) {\n",
    "runtime chunk observation",
)

core = r'''
// JCG5_PAGE_DEPENDENCY_V080
// v0.8.0 Page Dependency Capture.
//
// Mode 1 is deliberately policy-isolated:
//   - manual page anchor;
//   - TXT whitelist only;
//   - runtime TAB/config + observed model/cache + request-correlated protobuf;
//   - Mode 2 policy is never consulted.
//
// Mode 2 is a passive learner only. It records page_allow/global_background/
// unknown observations, keeps page_deny/active_call_deny as explicit policy
// buckets, and never actively invokes any unknown request.
#define JCG80_COMPLETION_QUIET_SECONDS 1.8

typedef NS_ENUM(NSInteger, JCG80CaptureMode) {
    JCG80CaptureModeManual = 1,
    JCG80CaptureModeAuto = 2,
};

static NSString *gJCG80Root;
static NSString *gJCG80Mode1Dir;
static NSString *gJCG80Mode2Dir;
static NSString *gJCG80WhitelistPath;
static NSString *gJCG80Mode1GraphPath;
static NSString *gJCG80Mode2GraphPath;
static NSString *gJCG80Mode2PolicyPath;

static NSMutableSet *gJCG80Whitelist;
static NSMutableDictionary *gJCG80Mode1Session;
static NSMutableDictionary *gJCG80Mode1Graph;
static NSMutableDictionary *gJCG80Mode2Sessions;
static NSMutableDictionary *gJCG80Mode2Graph;
static NSMutableDictionary *gJCG80Mode2Policy;

static JCG80CaptureMode gJCG80Mode = JCG80CaptureModeManual;
static BOOL gJCG80Mode1Active = NO;
static unsigned long long gJCG80Generation = 0;
static NSString *gJCG80Status = nil;

static NSString *JCG80NowISO(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    return [fmt stringFromDate:[NSDate date]];
}

static void JCG80EnsurePaths(void) {
    if (!gJCG80Root) gJCG80Root = [[gJCG5Root stringByAppendingPathComponent:@"runtime_page_dependency"] retain];
    if (!gJCG80Mode1Dir) gJCG80Mode1Dir = [[gJCG80Root stringByAppendingPathComponent:@"mode1_manual"] retain];
    if (!gJCG80Mode2Dir) gJCG80Mode2Dir = [[gJCG80Root stringByAppendingPathComponent:@"mode2_auto"] retain];
    if (!gJCG80WhitelistPath) gJCG80WhitelistPath = [[gJCG80Root stringByAppendingPathComponent:@"whitelist.json"] retain];
    if (!gJCG80Mode1GraphPath) gJCG80Mode1GraphPath = [[gJCG80Mode1Dir stringByAppendingPathComponent:@"dependency_graph.json"] retain];
    if (!gJCG80Mode2GraphPath) gJCG80Mode2GraphPath = [[gJCG80Mode2Dir stringByAppendingPathComponent:@"dependency_graph.json"] retain];
    if (!gJCG80Mode2PolicyPath) gJCG80Mode2PolicyPath = [[gJCG80Mode2Dir stringByAppendingPathComponent:@"policy.json"] retain];
    JCG5EnsureDir(gJCG80Root);
    JCG5EnsureDir(gJCG80Mode1Dir);
    JCG5EnsureDir(gJCG80Mode2Dir);
}

static NSString *JCG80ConfigStem(NSString *raw) {
    if (!raw.length) return @"";
    NSString *base = [[raw stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];
    NSString *lower = base.lowercaseString;
    for (NSString *ext in @[@".json", @".luac", @".lua", @".bytes", @".bin"]) {
        if ([lower hasSuffix:ext] && base.length > ext.length) {
            base = [base substringToIndex:base.length - ext.length];
            lower = base.lowercaseString;
            break;
        }
    }
    if ([base hasPrefix:@"TAB_"] && base.length > 4) base = [base substringFromIndex:4];

    NSRange r = [base rangeOfString:@"_" options:NSBackwardsSearch];
    if (r.location != NSNotFound && r.location + 1 < base.length) {
        NSString *suffix = [base substringFromIndex:r.location + 1];
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if (suffix.length <= 4 && [suffix rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            base = [base substringToIndex:r.location];
        }
    }
    return [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSString *JCG80TabName(NSString *chunk) {
    NSString *config = JCG80ConfigStem(chunk);
    return config.length ? [@"TAB_" stringByAppendingString:config] : @"";
}

static BOOL JCG80LooksLikeModel(NSString *chunk) {
    NSString *lower = chunk.lowercaseString;
    return [lower containsString:@"cache"] || [lower containsString:@"model"];
}

static BOOL JCG80AddUnique(NSMutableArray *array, NSString *value) {
    if (!array || !value.length || [array containsObject:value]) return NO;
    [array addObject:value];
    return YES;
}

static NSMutableDictionary *JCG80DependencyContainer(void) {
    return [NSMutableDictionary dictionaryWithDictionary:@{
        @"configs": [NSMutableArray array],
        @"tabs": [NSMutableArray array],
        @"models_observed": [NSMutableArray array],
        @"protocols": [NSMutableArray array],
        @"protocol_candidates": [NSMutableArray array],
        @"json_endpoints": [NSMutableArray array],
        @"lua_observed": [NSMutableArray array],
    }];
}

static NSMutableDictionary *JCG80GraphEntry(NSMutableDictionary *graph, NSString *ui) {
    if (!ui.length) return nil;
    NSMutableDictionary *entry = [graph objectForKey:ui];
    if (!entry) {
        entry = [NSMutableDictionary dictionaryWithDictionary:@{
            @"configs": [NSMutableArray array],
            @"tabs": [NSMutableArray array],
            @"models_observed": [NSMutableArray array],
            @"protocols": [NSMutableArray array],
            @"protocol_candidates": [NSMutableArray array],
            @"json_endpoints": [NSMutableArray array],
        }];
        [graph setObject:entry forKey:ui];
    }
    return entry;
}

static void JCG80CopyDependenciesToGraph(NSMutableDictionary *graph, NSDictionary *session) {
    NSString *ui = [session objectForKey:@"page_ui_lua"];
    NSDictionary *deps = [session objectForKey:@"dependencies"];
    NSMutableDictionary *entry = JCG80GraphEntry(graph, ui);
    if (!entry || ![deps isKindOfClass:[NSDictionary class]]) return;
    for (NSString *key in @[@"configs", @"tabs", @"models_observed", @"protocols", @"protocol_candidates", @"json_endpoints"]) {
        NSArray *values = [deps objectForKey:key];
        NSMutableArray *dst = [entry objectForKey:key];
        for (id value in values) if ([value isKindOfClass:[NSString class]]) JCG80AddUnique(dst, value);
    }
}

static void JCG80WriteGraph(NSMutableDictionary *graph, NSString *path, NSString *mode) {
    if (!graph || !path.length) return;
    NSDictionary *root = @{
        @"schema": @1,
        @"version": @"0.8.0",
        @"mode": mode ?: @"",
        @"updated_at": JCG80NowISO(),
        @"pages": graph,
        @"evidence": @{
            @"config": @"runtime TAB observed + imported whitelist match",
            @"model": @"runtime Lua chunk name candidate containing Cache/Model",
            @"protocol": @"manual session request or request-correlated response",
            @"protocol_candidate": @"unmatched/push/ambiguous observation; not promoted automatically",
        },
    };
    JCG5WriteJSON(root, path);
}

static void JCG80SetStatus(NSString *text) {
    pthread_mutex_lock(&gJCG5StateLock);
    [gJCG80Status release];
    gJCG80Status = [(text.length ? text : @"等待") copy];
    pthread_mutex_unlock(&gJCG5StateLock);
}

static void JCG80LoadWhitelist(void) {
    JCG80EnsurePaths();
    if (!gJCG80Whitelist) gJCG80Whitelist = [[NSMutableSet alloc] init];
    [gJCG80Whitelist removeAllObjects];

    NSDictionary *root = JCG5ReadJSON(gJCG80WhitelistPath);
    NSArray *items = [root objectForKey:@"items"];
    if ([items isKindOfClass:[NSArray class]]) {
        for (id value in items) {
            if (![value isKindOfClass:[NSString class]]) continue;
            NSString *stem = JCG80ConfigStem(value);
            if (stem.length) [gJCG80Whitelist addObject:stem];
        }
    }
}

static void JCG80SaveWhitelist(void) {
    JCG80EnsurePaths();
    NSArray *items = [[gJCG80Whitelist allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    JCG5WriteJSON(@{
        @"schema": @1,
        @"version": @"0.8.0",
        @"updated_at": JCG80NowISO(),
        @"items": items ?: @[],
        @"count": @(items.count),
        @"input_rule": @"UTF-8 text, one .json filename per line; blanks ignored; deduplicated",
    }, gJCG80WhitelistPath);
}

static BOOL JCG80WhitelistAllowsChunk(NSString *chunk, NSString **configOut, NSString **tabOut) {
    if (!gJCG80Whitelist) JCG80LoadWhitelist();
    NSString *config = JCG80ConfigStem(chunk);
    if (!config.length || ![gJCG80Whitelist containsObject:config]) return NO;
    if (configOut) *configOut = config;
    if (tabOut) *tabOut = [@"TAB_" stringByAppendingString:config];
    return YES;
}

static NSMutableDictionary *JCG80NewSession(NSString *ui, NSString *mode) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return [NSMutableDictionary dictionaryWithDictionary:@{
        @"schema": @1,
        @"version": @"0.8.0",
        @"mode": mode ?: @"",
        @"page_ui_lua": ui ?: @"",
        @"started_at": @(now),
        @"updated_at": @(now),
        @"status": @"collecting",
        @"dependencies": JCG80DependencyContainer(),
        @"completion": [NSMutableDictionary dictionaryWithDictionary:@{
            @"quiet_seconds_required": @(JCG80_COMPLETION_QUIET_SECONDS),
            @"observed": @0,
            @"captured": @0,
            @"missing": @0,
            @"stable_seconds": @0,
        }],
        @"evidence_policy": @{
            @"config": @"whitelist + runtime TAB",
            @"protocol": @"request or matched response during this page session",
            @"model": @"observed candidate only; runtime name heuristic",
        },
    }];
}

static NSUInteger JCG80PrimaryDependencyCount(NSDictionary *session) {
    NSDictionary *deps = [session objectForKey:@"dependencies"];
    return [[deps objectForKey:@"configs"] count] +
           [[deps objectForKey:@"models_observed"] count] +
           [[deps objectForKey:@"protocols"] count];
}

static NSString *JCG80SessionFilename(NSDictionary *session) {
    NSString *ui = [[session objectForKey:@"page_ui_lua"] stringByDeletingPathExtension];
    if (!ui.length) ui = @"unknown_page";
    return [[JCG70SafeFilename(ui) stringByAppendingString:@"__dependency"] stringByAppendingPathExtension:@"json"];
}

static void JCG80WriteMode1Session(void) {
    if (!gJCG80Mode1Session) return;
    JCG80EnsurePaths();
    [gJCG80Mode1Session setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"updated_at"];
    NSString *file = JCG80SessionFilename(gJCG80Mode1Session);
    NSString *path = [gJCG80Mode1Dir stringByAppendingPathComponent:file];
    [gJCG80Mode1Session setObject:file forKey:@"file"];
    JCG5WriteJSON(gJCG80Mode1Session, path);
    JCG80CopyDependenciesToGraph(gJCG80Mode1Graph, gJCG80Mode1Session);
    JCG80WriteGraph(gJCG80Mode1Graph, gJCG80Mode1GraphPath, @"mode1_manual");
}

static void JCG80RefreshMode1Status(NSString *state) {
    if (!gJCG80Mode1Session) {
        JCG80SetStatus([NSString stringWithFormat:@"Mode1｜白名单%lu｜等待开始", (unsigned long)gJCG80Whitelist.count]);
        return;
    }
    NSDictionary *deps = [gJCG80Mode1Session objectForKey:@"dependencies"];
    NSUInteger configs = [[deps objectForKey:@"configs"] count];
    NSUInteger models = [[deps objectForKey:@"models_observed"] count];
    NSUInteger protocols = [[deps objectForKey:@"protocols"] count];
    NSUInteger candidates = [[deps objectForKey:@"protocol_candidates"] count];
    NSString *ui = [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"";
    JCG80SetStatus([NSString stringWithFormat:@"Mode1 %@｜%@\n白名单%lu 配置%lu Model候选%lu 协议%lu 候选%lu",
                    state ?: @"采集中", ui.length ? ui : @"无UI",
                    (unsigned long)gJCG80Whitelist.count, (unsigned long)configs,
                    (unsigned long)models, (unsigned long)protocols, (unsigned long)candidates]);
}

static void JCG80ScheduleCompletion(void) {
    if (!gJCG80Mode1Active || !gJCG80Mode1Session || !gJCG5CaptureQueue) return;
    gJCG80Generation++;
    unsigned long long generation = gJCG80Generation;
    [gJCG80Mode1Session setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_dependency_at"];
    [gJCG80Mode1Session setObject:@"collecting" forKey:@"status"];
    JCG80RefreshMode1Status(@"采集中");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(JCG80_COMPLETION_QUIET_SECONDS * NSEC_PER_SEC)),
                   gJCG5CaptureQueue, ^{@autoreleasepool {
        if (!gJCG80Mode1Active || generation != gJCG80Generation || !gJCG80Mode1Session) return;
        NSUInteger count = JCG80PrimaryDependencyCount(gJCG80Mode1Session);
        NSMutableDictionary *completion = [gJCG80Mode1Session objectForKey:@"completion"];
        [completion setObject:@(count) forKey:@"observed"];
        [completion setObject:@(count) forKey:@"captured"];
        [completion setObject:@0 forKey:@"missing"];
        [completion setObject:@(JCG80_COMPLETION_QUIET_SECONDS) forKey:@"stable_seconds"];
        if (count > 0) {
            [gJCG80Mode1Session setObject:@"complete" forKey:@"status"];
            [gJCG80Mode1Session setObject:JCG80NowISO() forKey:@"completed_at"];
            JCG80RefreshMode1Status(@"✅ 已抓取完成");
            JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 complete ui=%@ deps=%lu quiet=%.1fs",
                     [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"",
                     (unsigned long)count, JCG80_COMPLETION_QUIET_SECONDS]);
        } else {
            [gJCG80Mode1Session setObject:@"collecting_waiting_dependency" forKey:@"status"];
            JCG80RefreshMode1Status(@"等待依赖");
        }
        JCG80WriteMode1Session();
    }});
}

static BOOL JCG80SessionAdd(NSMutableDictionary *session, NSString *bucket, NSString *value, BOOL primary) {
    if (!session || !bucket.length || !value.length) return NO;
    NSMutableDictionary *deps = [session objectForKey:@"dependencies"];
    NSMutableArray *array = [deps objectForKey:bucket];
    if (![array isKindOfClass:[NSMutableArray class]]) return NO;
    BOOL changed = JCG80AddUnique(array, value);
    if (changed) {
        [session setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"updated_at"];
        if (primary && session == gJCG80Mode1Session) JCG80ScheduleCompletion();
    }
    return changed;
}

static void JCG80StartManualCaptureOnQueue(void) {
    JCG80EnsurePaths();
    if (!gJCG80Whitelist) JCG80LoadWhitelist();
    NSDictionary *ctx = JCG60PageContextSnapshot();
    NSString *ui = [ctx objectForKey:@"page_ui_lua"];
    if (!ui.length) {
        NSString *page = [ctx objectForKey:@"page_context"];
        if ([[page lowercaseString] hasPrefix:@"ui"]) ui = page;
    }
    if (!ui.length) {
        JCG80SetStatus(@"Mode1 无法开始：当前未识别到 UI*.lua");
        JCG5Log(@"PAGE-DEPENDENCY mode1 start rejected: no current UI");
        return;
    }

    gJCG80Mode = JCG80CaptureModeManual;
    gJCG80Mode1Active = YES;
    gJCG80Generation++;
    [gJCG80Mode1Session release];
    gJCG80Mode1Session = [JCG80NewSession(ui, @"mode1_manual") retain];
    [gJCG80Mode1Session setObject:(ctx ?: @{}) forKey:@"start_page_context"];

    // Seed the current TAB only when it is both temporally close to this UI and
    // explicitly allowed by the imported whitelist. This prevents a stale prior
    // TAB from becoming a dependency merely because it was "latest".
    NSString *tabChunk = [ctx objectForKey:@"page_tab_lua"];
    NSTimeInterval tabAt = 0, uiAt = 0;
    pthread_mutex_lock(&gJCG5StateLock);
    tabAt = gJCG60TabLuaAt;
    uiAt = gJCG60UILuaAt;
    pthread_mutex_unlock(&gJCG5StateLock);
    NSString *config = nil, *tab = nil;
    if (tabChunk.length && fabs(tabAt - uiAt) <= 5.0 &&
        JCG80WhitelistAllowsChunk(tabChunk, &config, &tab)) {
        JCG80SessionAdd(gJCG80Mode1Session, @"configs", config, YES);
        JCG80SessionAdd(gJCG80Mode1Session, @"tabs", tab, NO);
    }

    JCG80RefreshMode1Status(@"采集中");
    JCG80WriteMode1Session();
    JCG80ScheduleCompletion();
    JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 start ui=%@ whitelist=%lu",
             ui, (unsigned long)gJCG80Whitelist.count]);
}

static void JCG80StartManualCapture(void) {
    if (!gJCG5CaptureQueue) return;
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool { JCG80StartManualCaptureOnQueue(); }});
}

static void JCG80StopManualCaptureOnQueue(NSString *reason) {
    if (!gJCG80Mode1Session) {
        gJCG80Mode1Active = NO;
        JCG80RefreshMode1Status(@"已停止");
        return;
    }
    gJCG80Mode1Active = NO;
    gJCG80Generation++;
    NSUInteger count = JCG80PrimaryDependencyCount(gJCG80Mode1Session);
    NSString *status = count > 0 ? @"stopped" : @"partial";
    [gJCG80Mode1Session setObject:status forKey:@"status"];
    [gJCG80Mode1Session setObject:(reason.length ? reason : @"manual_stop") forKey:@"stop_reason"];
    [gJCG80Mode1Session setObject:JCG80NowISO() forKey:@"stopped_at"];
    JCG80WriteMode1Session();
    JCG80RefreshMode1Status(count > 0 ? @"已停止" : @"partial");
    JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 stop ui=%@ deps=%lu reason=%@",
             [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"",
             (unsigned long)count, reason ?: @"manual_stop"]);
}

static void JCG80StopManualCapture(NSString *reason) {
    NSString *copy = [(reason ?: @"manual_stop") copy];
    if (!gJCG5CaptureQueue) { [copy release]; return; }
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG80StopManualCaptureOnQueue(copy);
        [copy release];
    }});
}

static NSMutableDictionary *JCG80Mode2Session(NSString *ui) {
    if (!ui.length) return nil;
    if (!gJCG80Mode2Sessions) gJCG80Mode2Sessions = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *session = [gJCG80Mode2Sessions objectForKey:ui];
    if (!session) {
        session = JCG80NewSession(ui, @"mode2_auto");
        [gJCG80Mode2Sessions setObject:session forKey:ui];
    }
    return session;
}

static NSMutableDictionary *JCG80PolicyPage(NSString *ui) {
    if (!gJCG80Mode2Policy) {
        gJCG80Mode2Policy = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"schema": @1,
            @"version": @"0.8.0",
            @"global_background": [NSMutableArray array],
            @"pages": [NSMutableDictionary dictionary],
            @"rule": @"unknown is observation-only and is never promoted to active invocation",
        }];
    }
    NSMutableDictionary *pages = [gJCG80Mode2Policy objectForKey:@"pages"];
    NSMutableDictionary *page = [pages objectForKey:ui ?: @""];
    if (!page && ui.length) {
        page = [NSMutableDictionary dictionaryWithDictionary:@{
            @"page_allow": [NSMutableArray array],
            @"page_deny": [NSMutableArray array],
            @"active_call_deny": [NSMutableArray array],
            @"unknown": [NSMutableArray array],
        }];
        [pages setObject:page forKey:ui];
    }
    return page;
}

static void JCG80WriteMode2State(NSMutableDictionary *session) {
    JCG80EnsurePaths();
    if (session) {
        NSString *file = JCG80SessionFilename(session);
        JCG5WriteJSON(session, [gJCG80Mode2Dir stringByAppendingPathComponent:file]);
        JCG80CopyDependenciesToGraph(gJCG80Mode2Graph, session);
    }
    JCG80WriteGraph(gJCG80Mode2Graph, gJCG80Mode2GraphPath, @"mode2_auto");
    if (gJCG80Mode2Policy) {
        [gJCG80Mode2Policy setObject:JCG80NowISO() forKey:@"updated_at"];
        JCG5WriteJSON(gJCG80Mode2Policy, gJCG80Mode2PolicyPath);
    }
}

static void JCG80ObserveLuaChunkOnQueue(NSString *chunk, NSDictionary *ctx) {
    if (!chunk.length) return;

    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {
        JCG80SessionAdd(gJCG80Mode1Session, @"lua_observed", chunk, NO);
        NSString *config = nil, *tab = nil;
        if (JCG80WhitelistAllowsChunk(chunk, &config, &tab)) {
            BOOL changed = JCG80SessionAdd(gJCG80Mode1Session, @"configs", config, YES);
            JCG80SessionAdd(gJCG80Mode1Session, @"tabs", tab, NO);
            if (changed) JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 config ui=%@ config=%@",
                                  [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"", config]);
        }
        if (JCG80LooksLikeModel(chunk)) {
            if (JCG80SessionAdd(gJCG80Mode1Session, @"models_observed", chunk, YES)) {
                JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 model-candidate ui=%@ chunk=%@",
                         [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"", chunk]);
            }
        }
        JCG80WriteMode1Session();
        return;
    }

    if (gJCG80Mode != JCG80CaptureModeAuto) return;
    NSString *ui = [ctx objectForKey:@"page_ui_lua"];
    if (!ui.length) return;
    NSMutableDictionary *session = JCG80Mode2Session(ui);
    JCG80SessionAdd(session, @"lua_observed", chunk, NO);
    NSString *config = nil, *tab = nil;
    if (JCG80WhitelistAllowsChunk(chunk, &config, &tab)) {
        JCG80SessionAdd(session, @"configs", config, NO);
        JCG80SessionAdd(session, @"tabs", tab, NO);
    }
    if (JCG80LooksLikeModel(chunk)) JCG80SessionAdd(session, @"models_observed", chunk, NO);
    JCG80WriteMode2State(session);
}

static void JCG80ObserveLuaChunk(NSString *chunk) {
    if (!chunk.length || !gJCG5CaptureQueue) return;
    NSString *chunkCopy = [chunk copy];
    NSDictionary *ctx = [JCG60PageContextSnapshot() copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG80ObserveLuaChunkOnQueue(chunkCopy, ctx);
        [chunkCopy release];
        [ctx release];
    }});
}

static BOOL JCG80EventMatchesManualRoot(NSDictionary *event) {
    NSString *root = [gJCG80Mode1Session objectForKey:@"page_ui_lua"];
    NSString *ui = [event objectForKey:@"page_ui_lua"];
    return root.length && ui.length && [root isEqualToString:ui];
}

static void JCG80ObserveProtobuf(NSDictionary *event) {
    if (!event) return;
    NSString *name = [event objectForKey:@"msg_name"];
    if (!name.length) name = [NSString stringWithFormat:@"MSGID_%@", [event objectForKey:@"msgid"] ?: @0];

    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {
        NSString *direction = [event objectForKey:@"direction"] ?: @"";
        BOOL sameUI = JCG80EventMatchesManualRoot(event);
        BOOL matched = [[event objectForKey:@"matched_request"] boolValue];
        BOOL primary = ([direction isEqualToString:@"request"] && sameUI) ||
                       ([direction isEqualToString:@"response"] && matched && sameUI);
        if (primary) {
            if (JCG80SessionAdd(gJCG80Mode1Session, @"protocols", name, YES)) {
                JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 protocol ui=%@ name=%@ direction=%@ matched=%d",
                         [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"", name, direction, matched]);
            }
        } else {
            JCG80SessionAdd(gJCG80Mode1Session, @"protocol_candidates", name, NO);
        }
        JCG80WriteMode1Session();
        return;
    }

    if (gJCG80Mode != JCG80CaptureModeAuto) return;
    NSString *ui = [event objectForKey:@"page_ui_lua"] ?: @"";
    NSString *direction = [event objectForKey:@"direction"] ?: @"";
    BOOL matched = [[event objectForKey:@"matched_request"] boolValue];

    if (!ui.length) {
        JCG80PolicyPage(@"");
        NSMutableArray *global = [gJCG80Mode2Policy objectForKey:@"global_background"];
        JCG80AddUnique(global, name);
        JCG80WriteMode2State(nil);
        return;
    }

    NSMutableDictionary *session = JCG80Mode2Session(ui);
    NSMutableDictionary *policy = JCG80PolicyPage(ui);
    if ([direction isEqualToString:@"request"] || matched) {
        JCG80SessionAdd(session, @"protocols", name, NO);
        JCG80AddUnique([policy objectForKey:@"page_allow"], name);
    } else {
        JCG80SessionAdd(session, @"protocol_candidates", name, NO);
        JCG80AddUnique([policy objectForKey:@"unknown"], name);
    }
    // page_deny and active_call_deny remain explicit empty buckets until there
    // is stronger evidence. v0.8.0 never turns unknown into an active request.
    JCG80WriteMode2State(session);
}

static void JCG80ObserveJSON(NSDictionary *meta, id obj, NSUInteger bytes) {
    (void)obj; (void)bytes;
    NSString *endpoint = JCG59EndpointKey([meta objectForKey:@"url"] ?: @"",
                                          [meta objectForKey:@"method"] ?: @"");
    if (!endpoint.length) endpoint = @"(no-endpoint)";

    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {
        JCG80SessionAdd(gJCG80Mode1Session, @"json_endpoints", endpoint, NO);
        JCG80WriteMode1Session();
        return;
    }
    if (gJCG80Mode != JCG80CaptureModeAuto) return;
    NSString *ui = [meta objectForKey:@"page_ui_lua"] ?: @"";
    if (!ui.length) return;
    NSMutableDictionary *session = JCG80Mode2Session(ui);
    JCG80SessionAdd(session, @"json_endpoints", endpoint, NO);
    JCG80WriteMode2State(session);
}

static void JCG80ToggleModeOnQueue(void) {
    JCG80EnsurePaths();
    if (gJCG80Mode == JCG80CaptureModeManual) {
        if (gJCG80Mode1Active) JCG80StopManualCaptureOnQueue(@"switch_to_mode2");
        gJCG80Mode = JCG80CaptureModeAuto;
        JCG80SetStatus([NSString stringWithFormat:@"Mode2 自动分类｜白名单%lu\nunknown 仅记录，永不主动调用",
                        (unsigned long)gJCG80Whitelist.count]);
        JCG5Log(@"PAGE-DEPENDENCY mode2 enabled passive-policy-only");
    } else {
        gJCG80Mode = JCG80CaptureModeManual;
        JCG80RefreshMode1Status(@"等待开始");
        JCG5Log(@"PAGE-DEPENDENCY mode1 selected policy-isolated");
    }
}

static void JCG80ToggleMode(void) {
    if (!gJCG5CaptureQueue) return;
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool { JCG80ToggleModeOnQueue(); }});
}

static void JCG80ImportWhitelistURL(NSURL *url) {
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!text.length) {
        JCG80SetStatus([NSString stringWithFormat:@"白名单导入失败：%@", err.localizedDescription ?: @"空文件"]);
        return;
    }

    NSMutableArray *stems = [NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trim.length || ![[trim lowercaseString] hasSuffix:@".json"]) return;
        NSString *stem = JCG80ConfigStem(trim);
        if (stem.length && ![stems containsObject:stem]) [stems addObject:stem];
    }];

    NSArray *copy = [stems copy];
    NSString *source = [[url lastPathComponent] copy];
    if (!gJCG5CaptureQueue) { [copy release]; [source release]; return; }
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG80EnsurePaths();
        if (!gJCG80Whitelist) gJCG80Whitelist = [[NSMutableSet alloc] init];
        [gJCG80Whitelist removeAllObjects];
        [gJCG80Whitelist addObjectsFromArray:copy];
        JCG80SaveWhitelist();
        if (gJCG80Mode == JCG80CaptureModeManual) JCG80RefreshMode1Status(@"白名单已导入");
        else JCG80SetStatus([NSString stringWithFormat:@"Mode2｜白名单%lu｜%@",
                             (unsigned long)gJCG80Whitelist.count, source ?: @"txt"]);
        JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY whitelist import file=%@ items=%lu",
                 source ?: @"", (unsigned long)gJCG80Whitelist.count]);
        [copy release];
        [source release];
    }});
}

static NSString *JCG80StatusText(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    NSString *text = [[(gJCG80Status ?: @"v0.8 初始化中") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return text;
}

static void JCG80Initialize(void) {
    if (!gJCG5CaptureQueue) return;
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG80EnsurePaths();
        if (!gJCG80Mode1Graph) gJCG80Mode1Graph = [[NSMutableDictionary alloc] init];
        if (!gJCG80Mode2Graph) gJCG80Mode2Graph = [[NSMutableDictionary alloc] init];
        JCG80LoadWhitelist();
        JCG80RefreshMode1Status(@"等待开始");
        JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY v0.8.0 ready mode1=manual-passive mode2=policy-learning whitelist=%lu quiet=%.1fs unknown=never-active",
                 (unsigned long)gJCG80Whitelist.count, JCG80_COMPLETION_QUIET_SECONDS]);
    }});
}

'''
rep(
    "static NSString *JCG60ProtoStatusText(void) {\n",
    core + "static NSString *JCG60ProtoStatusText(void) {\n",
    "v0.8 core insertion",
)

# Feed already-parsed page JSON/protobuf observations into the independent
# v0.8 dependency model without changing the v0.7.1 snapshot output.
rep(
    "static void JCG70RecordJSONSnapshot(NSDictionary *meta, id obj, NSUInteger bytes) {\n"
    "    if (!meta || !obj) return;\n",
    "static void JCG70RecordJSONSnapshot(NSDictionary *meta, id obj, NSUInteger bytes) {\n"
    "    if (!meta || !obj) return;\n"
    "    JCG80ObserveJSON(meta, obj, bytes);\n",
    "JSON dependency feed",
)

rep(
    "static void JCG70RecordProtobufSnapshot(NSDictionary *event) {\n"
    "    if (!event) return;\n",
    "static void JCG70RecordProtobufSnapshot(NSDictionary *event) {\n"
    "    if (!event) return;\n"
    "    JCG80ObserveProtobuf(event);\n",
    "protobuf dependency feed",
)

# Add one status row and four controls. JCG5ScrollFix moves operational content
# into the existing scroll view, so small screens remain usable.
rep(
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应抓取"],@[@"socket",@"SocketHTTP"],@[@"protobuf",@"页面 / Protobuf"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应抓取"],@[@"socket",@"SocketHTTP"],@[@"protobuf",@"页面 / Protobuf"],@[@"dependency",@"v0.8 页面依赖"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    "dependency UI row",
)

rep(
    'self.labels[@"protobuf"].text=JCG60ProtoStatusText();\n    self.labels[@"scan"].text=',
    'self.labels[@"protobuf"].text=JCG60ProtoStatusText();\n    self.labels[@"dependency"].text=JCG80StatusText();\n    self.labels[@"scan"].text=',
    "dependency UI refresh",
)

rep(
    'NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))]];',
    'NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))],@[@"导入白名单TXT",NSStringFromSelector(@selector(importDependencyWhitelist))],@[@"Mode1开始页面采集",NSStringFromSelector(@selector(startDependencyCapture))],@[@"Mode1停止页面采集",NSStringFromSelector(@selector(stopDependencyCapture))],@[@"切换Mode1 / Mode2",NSStringFromSelector(@selector(toggleDependencyMode))]];',
    "dependency UI controls",
)

picker_methods = r'''
- (void)importDependencyWhitelist {
    UIDocumentPickerViewController *picker = [[[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.plain-text", @"public.text"]
        inMode:UIDocumentPickerModeImport] autorelease];
    picker.delegate = (id<UIDocumentPickerDelegate>)self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)startDependencyCapture { JCG80StartManualCapture(); }
- (void)stopDependencyCapture { JCG80StopManualCapture(@"manual_stop"); }
- (void)toggleDependencyMode { JCG80ToggleMode(); }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (url) JCG80ImportWhitelistURL(url);
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    (void)controller;
    if (url) JCG80ImportWhitelistURL(url);
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    JCG5SetEvent(@"白名单导入已取消");
}
'''
rep(
    "- (void)retryRecover { JCG5RequestTask(JCG5TaskRecover,YES); }\n@end\n",
    "- (void)retryRecover { JCG5RequestTask(JCG5TaskRecover,YES); }\n"
    + picker_methods +
    "@end\n",
    "document picker and dependency actions",
)

# Initialize the dependency subsystem only after the existing serial queue exists.
rep(
    'JCG5SetupPaths();gJCG5CaptureQueue=dispatch_queue_create("com.openai.jsoncapture.v05.capture",DISPATCH_QUEUE_SERIAL);gJCG5TaskQueue=dispatch_queue_create("com.openai.jsoncapture.v05.manualtask",DISPATCH_QUEUE_SERIAL);',
    'JCG5SetupPaths();gJCG5CaptureQueue=dispatch_queue_create("com.openai.jsoncapture.v05.capture",DISPATCH_QUEUE_SERIAL);gJCG5TaskQueue=dispatch_queue_create("com.openai.jsoncapture.v05.manualtask",DISPATCH_QUEUE_SERIAL);JCG80Initialize();',
    "v0.8 initialize on existing queue",
)

# Upgrade readiness marker while retaining the v0.7.1 marker elsewhere in the
# build history and preserving all existing hook/queue invariants.
rep(
    '        JCG5Log(@"PAGE-SNAPSHOT v0.7.1 ready descriptor=runtime protobuf-depth=32 nodes=32768 child-ui=stable-parent reducer=serial-capture-queue");\n',
    '        JCG5Log(@"PAGE-SNAPSHOT v0.7.1 ready descriptor=runtime protobuf-depth=32 nodes=32768 child-ui=stable-parent reducer=serial-capture-queue");\n'
    '        JCG5Log(@"PAGE-DEPENDENCY v0.8.0 wrappers-ready mode1-policy-isolated mode2-passive unknown-never-active");\n',
    "v0.8 readiness marker",
)

p.write_text(s, encoding="utf-8")
print("applied v0.8.0 page dependency capture")
