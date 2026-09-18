#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_PAGE_DEPENDENCY_V080_RUNTIME_AUTO_FIX"
if MARKER in s:
    print("v0.8.0 runtime-auto fix already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_DEPENDENCY_V080",
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"runtime-auto fix anchor missing: {label}")
    s = s.replace(old, new, 1)

# Add explicit Mode2 lifecycle controls and clean page-data exports.
rep(
    "static NSString *gJCG80Status = nil;\n",
    "static NSString *gJCG80Status = nil;\n"
    "// JCG5_PAGE_DEPENDENCY_V080_RUNTIME_AUTO_FIX\n"
    "static BOOL gJCG81Mode2Running = NO;\n"
    "static NSMutableSet *gJCG81Mode2RunPages;\n"
    "static NSString *gJCG81Mode2CurrentUI;\n"
    "static unsigned long long gJCG81Mode2JSONEvents = 0;\n"
    "static unsigned long long gJCG81Mode2PBEvents = 0;\n"
    "static NSString *gJCG81Mode1DataDir;\n"
    "static NSString *gJCG81Mode2DataDir;\n",
    "runtime-auto globals",
)

rep(
    "    JCG5EnsureDir(gJCG80Mode1Dir);\n"
    "    JCG5EnsureDir(gJCG80Mode2Dir);\n",
    "    JCG5EnsureDir(gJCG80Mode1Dir);\n"
    "    JCG5EnsureDir(gJCG80Mode2Dir);\n"
    "    if (!gJCG81Mode1DataDir) gJCG81Mode1DataDir = [[gJCG80Mode1Dir stringByAppendingPathComponent:@\"page_data\"] retain];\n"
    "    if (!gJCG81Mode2DataDir) gJCG81Mode2DataDir = [[gJCG80Mode2Dir stringByAppendingPathComponent:@\"page_data\"] retain];\n"
    "    JCG5EnsureDir(gJCG81Mode1DataDir);\n"
    "    JCG5EnsureDir(gJCG81Mode2DataDir);\n",
    "clean page-data paths",
)

helpers = r'''
static NSMutableDictionary *JCG81PageData(NSMutableDictionary *session) {
    if (!session) return nil;
    NSMutableDictionary *data = [session objectForKey:@"page_data"];
    if (![data isKindOfClass:[NSMutableDictionary class]]) {
        data = [NSMutableDictionary dictionaryWithDictionary:@{
            @"tab_configs": [NSMutableDictionary dictionary],
            @"http_json": [NSMutableDictionary dictionary],
            @"protobuf": [NSMutableDictionary dictionary],
        }];
        [session setObject:data forKey:@"page_data"];
    }
    return data;
}

static void JCG81UpdateSessionContext(NSMutableDictionary *session, NSDictionary *ctx) {
    if (!session || !ctx) return;
    NSString *ui = [ctx objectForKey:@"page_ui_lua"] ?: @"";
    NSString *tab = [ctx objectForKey:@"page_tab_lua"] ?: @"";
    if (ui.length) [session setObject:ui forKey:@"page_ui_lua"];
    if (tab.length) [session setObject:tab forKey:@"page_tab_lua"];
    id cfg = [ctx objectForKey:@"page_local_tab_config"];
    NSString *global = [ctx objectForKey:@"page_local_tab_global"] ?: @"";
    if (cfg) {
        NSMutableDictionary *tabs = [JCG81PageData(session) objectForKey:@"tab_configs"];
        NSString *key = global.length ? global : (tab.length ? JCG70TabGlobalName(tab) : @"TAB_unknown");
        if (key.length) [tabs setObject:cfg forKey:key];
    }
}

static void JCG81CaptureJSONData(NSMutableDictionary *session, NSDictionary *meta, id obj, NSUInteger bytes) {
    if (!session || !meta || !obj) return;
    JCG81UpdateSessionContext(session, meta);
    NSString *endpoint = JCG59EndpointKey([meta objectForKey:@"url"] ?: @"",
                                          [meta objectForKey:@"method"] ?: @"");
    if (!endpoint.length) endpoint = @"(no-endpoint)";
    NSMutableDictionary *http = [JCG81PageData(session) objectForKey:@"http_json"];
    NSMutableDictionary *slot = [NSMutableDictionary dictionary];
    id old = [[http objectForKey:endpoint] objectForKey:@"data"];
    [slot setObject:(old ? JCG70DeepMerge(old, obj) : obj) forKey:@"data"];
    [slot setObject:endpoint forKey:@"endpoint"];
    [slot setObject:([meta objectForKey:@"method"] ?: @"") forKey:@"method"];
    [slot setObject:([meta objectForKey:@"http_status"] ?: @0) forKey:@"http_status"];
    [slot setObject:@(bytes) forKey:@"bytes"];
    [slot setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"time"];
    [http setObject:slot forKey:endpoint];
}

static void JCG81CaptureProtobufData(NSMutableDictionary *session, NSDictionary *event) {
    if (!session || !event) return;
    JCG81UpdateSessionContext(session, event);
    NSString *name = [event objectForKey:@"msg_name"];
    if (!name.length) name = [NSString stringWithFormat:@"MSGID_%@", [event objectForKey:@"msgid"] ?: @0];
    NSString *direction = [event objectForKey:@"direction"] ?: @"";
    id decoded = [event objectForKey:@"decoded"] ?: [NSNull null];

    NSMutableDictionary *protobuf = [JCG81PageData(session) objectForKey:@"protobuf"];
    NSMutableDictionary *slot = [protobuf objectForKey:name];
    if (![slot isKindOfClass:[NSMutableDictionary class]]) {
        slot = [NSMutableDictionary dictionary];
        [protobuf setObject:slot forKey:name];
    }
    [slot setObject:([event objectForKey:@"msgid"] ?: @0) forKey:@"msgid"];
    [slot setObject:name forKey:@"msg_name"];
    [slot setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_time"];
    if ([direction isEqualToString:@"request"]) {
        [slot setObject:decoded forKey:@"last_request"];
    } else {
        id old = [slot objectForKey:@"merged_response"];
        [slot setObject:JCG70DeepMerge(old, decoded) forKey:@"merged_response"];
        [slot setObject:decoded forKey:@"last_response"];
        [slot setObject:([event objectForKey:@"matched_request"] ?: @NO) forKey:@"matched_request"];
        if ([event objectForKey:@"raw_file"]) [slot setObject:[event objectForKey:@"raw_file"] forKey:@"last_raw_file"];
        if ([event objectForKey:@"raw_sha256"]) [slot setObject:[event objectForKey:@"raw_sha256"] forKey:@"last_raw_sha256"];
    }
}

static void JCG81MergeV071SnapshotData(NSMutableDictionary *session) {
    if (!session || !gJCG70Snapshots.count) return;
    NSString *ui = [session objectForKey:@"page_ui_lua"] ?: @"";
    if (!ui.length) return;
    NSMutableDictionary *pageData = JCG81PageData(session);
    for (NSString *key in gJCG70Snapshots) {
        NSDictionary *snap = [gJCG70Snapshots objectForKey:key];
        NSString *snapUI = [snap objectForKey:@"page_ui_lua"] ?: @"";
        if (![snapUI isEqualToString:ui]) continue;
        id cfg = [snap objectForKey:@"local_tab_config"];
        NSString *global = [snap objectForKey:@"local_tab_global"] ?: @"";
        if (cfg) {
            NSMutableDictionary *tabs = [pageData objectForKey:@"tab_configs"];
            NSString *tab = [snap objectForKey:@"page_tab_lua"] ?: @"";
            NSString *name = global.length ? global : JCG70TabGlobalName(tab);
            if (name.length) [tabs setObject:cfg forKey:name];
        }
        NSDictionary *jsonState = [snap objectForKey:@"json_state"];
        if ([jsonState isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *dst = [pageData objectForKey:@"http_json"];
            for (NSString *endpoint in jsonState) {
                id value = [jsonState objectForKey:endpoint];
                if (value && ![dst objectForKey:endpoint]) [dst setObject:value forKey:endpoint];
            }
        }
        NSDictionary *pbState = [snap objectForKey:@"protobuf_state"];
        if ([pbState isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *dst = [pageData objectForKey:@"protobuf"];
            for (NSString *name in pbState) {
                id value = [pbState objectForKey:name];
                if (value && ![dst objectForKey:name]) [dst setObject:value forKey:name];
            }
        }
        break;
    }
}

static void JCG81WriteCleanPageData(NSMutableDictionary *session, NSString *dir) {
    if (!session || !dir.length) return;
    JCG81MergeV071SnapshotData(session);
    NSString *ui = [session objectForKey:@"page_ui_lua"] ?: @"";
    if (!ui.length) return;
    NSString *base = JCG70SafeFilename([[ui lastPathComponent] stringByDeletingPathExtension]);
    NSString *path = [dir stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"json"]];
    NSDictionary *data = [session objectForKey:@"page_data"] ?: @{};
    NSDictionary *out = @{
        @"schema": @2,
        @"version": @"0.8.0-runtime-auto",
        @"snapshot_kind": @"runtime_page_data",
        @"mode": [session objectForKey:@"mode"] ?: @"",
        @"page_ui_lua": ui,
        @"page_tab_lua": [session objectForKey:@"page_tab_lua"] ?: @"",
        @"updated_at": @([[NSDate date] timeIntervalSince1970]),
        @"tab_configs": [data objectForKey:@"tab_configs"] ?: @{},
        @"http_json": [data objectForKey:@"http_json"] ?: @{},
        @"protobuf": [data objectForKey:@"protobuf"] ?: @{},
    };
    JCG5WriteJSON(out, path);
}
'''
rep(
    "static NSMutableDictionary *JCG80NewSession(NSString *ui, NSString *mode) {\n",
    helpers + "\nstatic NSMutableDictionary *JCG80NewSession(NSString *ui, NSString *mode) {\n",
    "page-data helpers",
)

rep(
    '        @"dependencies": JCG80DependencyContainer(),\n',
    '        @"dependencies": JCG80DependencyContainer(),\n'
    '        @"page_data": [NSMutableDictionary dictionaryWithDictionary:@{\n'
    '            @"tab_configs": [NSMutableDictionary dictionary],\n'
    '            @"http_json": [NSMutableDictionary dictionary],\n'
    '            @"protobuf": [NSMutableDictionary dictionary],\n'
    '        }],\n',
    "page-data session container",
)

rep(
    "    JCG80WriteGraph(gJCG80Mode1Graph, gJCG80Mode1GraphPath, @\"mode1_manual\");\n"
    "}\n\n"
    "static void JCG80RefreshMode1Status",
    "    JCG80WriteGraph(gJCG80Mode1Graph, gJCG80Mode1GraphPath, @\"mode1_manual\");\n"
    "    JCG81WriteCleanPageData(gJCG80Mode1Session, gJCG81Mode1DataDir);\n"
    "}\n\n"
    "static void JCG80RefreshMode1Status",
    "mode1 clean-data write",
)

# Mode1 becomes a permanent runtime watcher. A new UI chunk automatically
# closes the prior page session and starts a new one; no arming button required.
start = s.index("static void JCG80ObserveLuaChunkOnQueue(NSString *chunk, NSDictionary *ctx) {")
end = s.index("\nstatic void JCG80ObserveLuaChunk(NSString *chunk) {", start)
old_observer = s[start:end]
new_observer = r'''static void JCG80ObserveLuaChunkOnQueue(NSString *chunk, NSDictionary *ctx) {
    if (!chunk.length) return;

    if (gJCG80Mode == JCG80CaptureModeManual) {
        gJCG80Mode1Active = YES;
        gJCG80Mode1Armed = NO;

        if (JCG80IsUIChunk(chunk)) {
            NSString *root = [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"";
            if (!root.length || ![root isEqualToString:chunk]) {
                if (gJCG80Mode1Session) {
                    [gJCG80Mode1Session setObject:@"superseded_by_runtime_ui_change" forKey:@"status"];
                    [gJCG80Mode1Session setObject:JCG80NowISO() forKey:@"completed_at"];
                    JCG80WriteMode1Session();
                }
                [gJCG80Mode1Session release];
                gJCG80Mode1Session = [JCG80NewSession(chunk, @"mode1_runtime_auto") retain];
                JCG81UpdateSessionContext(gJCG80Mode1Session, ctx);
                JCG80SessionAdd(gJCG80Mode1Session, @"lua_observed", chunk, NO);
                JCG80RefreshMode1Status(@"🔄 检测到页面变化，自动采集");
                JCG80ScheduleCompletion();
                JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 runtime-ui-change ui=%@ whitelist=%lu",
                         chunk, (unsigned long)gJCG80Whitelist.count]);
            }
        }

        if (gJCG80Mode1Session) {
            JCG81UpdateSessionContext(gJCG80Mode1Session, ctx);
            JCG80SessionAdd(gJCG80Mode1Session, @"lua_observed", chunk, NO);
            NSString *config = nil, *tab = nil;
            if (JCG80WhitelistAllowsChunk(chunk, &config, &tab)) {
                BOOL changed = JCG80SessionAdd(gJCG80Mode1Session, @"configs", config, YES);
                JCG80SessionAdd(gJCG80Mode1Session, @"tabs", tab, NO);
                if (changed) JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode1 config ui=%@ config=%@",
                                      [gJCG80Mode1Session objectForKey:@"page_ui_lua"] ?: @"", config]);
            }
            if (JCG80LooksLikeModel(chunk)) {
                JCG80SessionAdd(gJCG80Mode1Session, @"models_observed", chunk, YES);
            }
            JCG80WriteMode1Session();
        }
        return;
    }

    if (gJCG80Mode != JCG80CaptureModeAuto || !gJCG81Mode2Running) return;
    NSString *ui = [ctx objectForKey:@"page_ui_lua"];
    if (!ui.length && JCG80IsUIChunk(chunk)) ui = chunk;
    if (!ui.length) return;

    if (!gJCG81Mode2RunPages) gJCG81Mode2RunPages = [[NSMutableSet alloc] init];
    if (![gJCG81Mode2RunPages containsObject:ui]) [gJCG81Mode2RunPages addObject:ui];
    [gJCG81Mode2CurrentUI release];
    gJCG81Mode2CurrentUI = [ui copy];

    NSMutableDictionary *session = JCG80Mode2Session(ui);
    JCG81UpdateSessionContext(session, ctx);
    JCG80SessionAdd(session, @"lua_observed", chunk, NO);
    NSString *config = nil, *tab = nil;
    if (JCG80WhitelistAllowsChunk(chunk, &config, &tab)) {
        JCG80SessionAdd(session, @"configs", config, NO);
        JCG80SessionAdd(session, @"tabs", tab, NO);
    }
    if (JCG80LooksLikeModel(chunk)) JCG80SessionAdd(session, @"models_observed", chunk, NO);
    JCG80WriteMode2State(session);

    JCG80SetStatus([NSString stringWithFormat:@"Mode2 ✅ 运行中｜当前 %@\n已识别页面%lu｜JSON%llu｜Protobuf%llu",
                    ui, (unsigned long)gJCG81Mode2RunPages.count,
                    gJCG81Mode2JSONEvents, gJCG81Mode2PBEvents]);
}
'''
s = s[:start] + new_observer + s[end:]

# Capture real business data into Mode1/Mode2 page_data.
rep(
    "    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {\n"
    "        NSString *direction = [event objectForKey:@\"direction\"] ?: @\"\";\n",
    "    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {\n"
    "        JCG81CaptureProtobufData(gJCG80Mode1Session, event);\n"
    "        NSString *direction = [event objectForKey:@\"direction\"] ?: @\"\";\n",
    "mode1 protobuf real-data",
)

rep(
    "    if (gJCG80Mode != JCG80CaptureModeAuto) return;\n"
    "    NSString *ui = [event objectForKey:@\"page_ui_lua\"] ?: @\"\";\n",
    "    if (gJCG80Mode != JCG80CaptureModeAuto || !gJCG81Mode2Running) return;\n"
    "    gJCG81Mode2PBEvents++;\n"
    "    NSString *ui = [event objectForKey:@\"page_ui_lua\"] ?: @\"\";\n",
    "mode2 protobuf running gate",
)

rep(
    "    NSMutableDictionary *session = JCG80Mode2Session(ui);\n"
    "    NSMutableDictionary *policy = JCG80PolicyPage(ui);\n",
    "    NSMutableDictionary *session = JCG80Mode2Session(ui);\n"
    "    JCG81CaptureProtobufData(session, event);\n"
    "    NSMutableDictionary *policy = JCG80PolicyPage(ui);\n",
    "mode2 protobuf real-data",
)

rep(
    "    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {\n"
    "        JCG80SessionAdd(gJCG80Mode1Session, @\"json_endpoints\", endpoint, NO);\n",
    "    if (gJCG80Mode == JCG80CaptureModeManual && gJCG80Mode1Active && gJCG80Mode1Session) {\n"
    "        JCG81CaptureJSONData(gJCG80Mode1Session, meta, obj, bytes);\n"
    "        JCG80SessionAdd(gJCG80Mode1Session, @\"json_endpoints\", endpoint, NO);\n",
    "mode1 JSON real-data",
)

rep(
    "    if (gJCG80Mode != JCG80CaptureModeAuto) return;\n"
    "    NSString *ui = [meta objectForKey:@\"page_ui_lua\"] ?: @\"\";\n",
    "    if (gJCG80Mode != JCG80CaptureModeAuto || !gJCG81Mode2Running) return;\n"
    "    gJCG81Mode2JSONEvents++;\n"
    "    NSString *ui = [meta objectForKey:@\"page_ui_lua\"] ?: @\"\";\n",
    "mode2 JSON running gate",
)

rep(
    "    NSMutableDictionary *session = JCG80Mode2Session(ui);\n"
    "    JCG80SessionAdd(session, @\"json_endpoints\", endpoint, NO);\n"
    "    JCG80WriteMode2State(session);\n",
    "    NSMutableDictionary *session = JCG80Mode2Session(ui);\n"
    "    JCG81CaptureJSONData(session, meta, obj, bytes);\n"
    "    JCG80SessionAdd(session, @\"json_endpoints\", endpoint, NO);\n"
    "    JCG80WriteMode2State(session);\n",
    "mode2 JSON real-data",
)

rep(
    "    JCG80WriteGraph(gJCG80Mode2Graph, gJCG80Mode2GraphPath, @\"mode2_auto\");\n"
    "    if (gJCG80Mode2Policy) {\n",
    "    JCG80WriteGraph(gJCG80Mode2Graph, gJCG80Mode2GraphPath, @\"mode2_auto\");\n"
    "    if (session) JCG81WriteCleanPageData(session, gJCG81Mode2DataDir);\n"
    "    if (gJCG80Mode2Policy) {\n",
    "mode2 clean-data write",
)

# Replace mode toggle with explicit Mode2 start/stop. Stopping restores Mode1's
# permanent runtime watcher automatically.
mode2 = r'''
static void JCG81StartMode2OnQueue(void) {
    JCG80EnsurePaths();
    if (!gJCG80Whitelist) JCG80LoadWhitelist();
    gJCG80Mode = JCG80CaptureModeAuto;
    gJCG81Mode2Running = YES;
    gJCG81Mode2JSONEvents = 0;
    gJCG81Mode2PBEvents = 0;
    if (!gJCG81Mode2RunPages) gJCG81Mode2RunPages = [[NSMutableSet alloc] init];
    [gJCG81Mode2RunPages removeAllObjects];
    [gJCG81Mode2CurrentUI release];
    gJCG81Mode2CurrentUI = nil;
    JCG80SetStatus([NSString stringWithFormat:@"Mode2 ✅ 启动成功｜全自动采集中\n白名单%lu｜等待运行时页面数据",
                    (unsigned long)gJCG80Whitelist.count]);
    JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode2 start success whitelist=%lu",
             (unsigned long)gJCG80Whitelist.count]);
}

static void JCG81StartMode2(void) {
    if (!gJCG5CaptureQueue) return;
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool { JCG81StartMode2OnQueue(); }});
}

static void JCG81StopMode2OnQueue(NSString *reason) {
    gJCG81Mode2Running = NO;
    NSUInteger pages = gJCG81Mode2RunPages.count;
    NSString *last = gJCG81Mode2CurrentUI ?: @"无";
    JCG80SetStatus([NSString stringWithFormat:@"Mode2 ✅ 已停止｜页面%lu JSON%llu Protobuf%llu\n最后 %@｜Mode1 自动监听已恢复",
                    (unsigned long)pages, gJCG81Mode2JSONEvents, gJCG81Mode2PBEvents, last]);
    JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY mode2 stop pages=%lu json=%llu protobuf=%llu reason=%@",
             (unsigned long)pages, gJCG81Mode2JSONEvents, gJCG81Mode2PBEvents, reason ?: @"manual_stop"]);
    gJCG80Mode = JCG80CaptureModeManual;
    gJCG80Mode1Active = YES;
    gJCG80Mode1Armed = NO;
    [gJCG80Mode1Session release];
    gJCG80Mode1Session = nil;
}

static void JCG81StopMode2(void) {
    if (!gJCG5CaptureQueue) return;
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool { JCG81StopMode2OnQueue(@"manual_stop"); }});
}
'''
idx = s.index("static void JCG80ToggleModeOnQueue(void) {")
end = s.index("\nstatic void JCG80ImportWhitelistURL(NSURL *url) {", idx)
s = s[:idx] + mode2 + "\n" + s[end:]

# Status on initialization: Mode1 is immediately live and waiting for runtime UI changes.
rep(
    "        JCG80RefreshMode1Status(@\"等待开始\");\n"
    "        JCG5Log([NSString stringWithFormat:@\"PAGE-DEPENDENCY v0.8.0 ready mode1=manual-passive mode2=policy-learning whitelist=%lu quiet=%.1fs unknown=never-active\",\n",
    "        gJCG80Mode = JCG80CaptureModeManual;\n"
    "        gJCG80Mode1Active = YES;\n"
    "        gJCG80Mode1Armed = NO;\n"
    "        JCG80SetStatus([NSString stringWithFormat:@\"Mode1 ✅ 自动监听｜白名单%lu\\n等待运行时最新 UI 变化\", (unsigned long)gJCG80Whitelist.count]);\n"
    "        JCG5Log([NSString stringWithFormat:@\"PAGE-DEPENDENCY v0.8.0 runtime-auto ready mode1=runtime-ui-watch mode2=explicit-start whitelist=%lu quiet=%.1fs unknown=never-active\",\n",
    "runtime-auto initialization",
)

# Buttons: Mode1 no longer needs start/stop. Mode2 has explicit start and stop.
rep(
    '@[@\"导入白名单TXT\",NSStringFromSelector(@selector(importDependencyWhitelist))],@[@\"Mode1预备→打开页面\",NSStringFromSelector(@selector(startDependencyCapture))],@[@\"Mode1停止页面采集\",NSStringFromSelector(@selector(stopDependencyCapture))],@[@\"切换Mode1 / Mode2\",NSStringFromSelector(@selector(toggleDependencyMode))]',
    '@[@\"导入白名单TXT\",NSStringFromSelector(@selector(importDependencyWhitelist))],@[@\"Mode2 开始全自动\",NSStringFromSelector(@selector(startMode2Auto))],@[@\"Mode2 停止全自动\",NSStringFromSelector(@selector(stopMode2Auto))]',
    "runtime-auto UI buttons",
)

rep(
    "- (void)startDependencyCapture { JCG80StartManualCapture(); }\n"
    "- (void)stopDependencyCapture { JCG80StopManualCapture(@\"manual_stop\"); }\n"
    "- (void)toggleDependencyMode { JCG80ToggleMode(); }\n",
    "- (void)startMode2Auto { JCG81StartMode2(); }\n"
    "- (void)stopMode2Auto { JCG81StopMode2(); }\n",
    "runtime-auto UI methods",
)

# Refresh whitelist status without bringing back the old Mode1 manual wording.
rep(
    "        if (gJCG80Mode == JCG80CaptureModeManual) JCG80RefreshMode1Status(@\"白名单已导入\");\n"
    "        else JCG80SetStatus([NSString stringWithFormat:@\"Mode2｜白名单%lu｜%@\",\n"
    "                             (unsigned long)gJCG80Whitelist.count, source ?: @\"txt\"]);\n",
    "        if (gJCG80Mode == JCG80CaptureModeManual)\n"
    "            JCG80SetStatus([NSString stringWithFormat:@\"Mode1 ✅ 自动监听｜白名单%lu\\n白名单已导入，等待运行时 UI 变化\", (unsigned long)gJCG80Whitelist.count]);\n"
    "        else if (gJCG81Mode2Running)\n"
    "            JCG80SetStatus([NSString stringWithFormat:@\"Mode2 ✅ 运行中｜白名单%lu｜%@\", (unsigned long)gJCG80Whitelist.count, source ?: @\"txt\"]);\n",
    "whitelist status",
)

p.write_text(s, encoding="utf-8")
print("applied v0.8.0 runtime-auto + useful-page-data fix")
