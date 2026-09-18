#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_SNAPSHOT_MODE_UNIFY_V083"
if MARKER in s:
    print("v0.8.3 snapshot/mode unification already applied")
    raise SystemExit(0)

for required in (
    "JCG5_SHA256_IDENTITY_V082",
    "JCG5_FOUNDATION_FIXES_V083",
    "JCG5_PAGE_DEPENDENCY_V080_RUNTIME_AUTO_FIX",
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.3 snapshot unify anchor missing: {label}")
    s = s.replace(old, new, count)

# ---------------------------------------------------------------------------
# Canonical snapshot callback. Mode1/Mode2 are control/orchestration only.
# They no longer own a second JSON/protobuf reducer.
# ---------------------------------------------------------------------------
rep(
    "static void JCG70WriteSnapshotNow(NSString *sessionKey) {",
    "static void JCG83OnCanonicalSnapshotWrite(NSString *sessionKey, NSDictionary *entry, NSString *file, BOOL semanticChanged);\n"
    "static void JCG70WriteSnapshotNow(NSString *sessionKey) {",
    "canonical callback forward declaration",
)

# v0.8.2 creates semanticChanged in this scope. Notify the mode controller only
# after the canonical snapshot has been atomically written and indexed.
rep(
    "        JCG5Log([NSString stringWithFormat:@\"PAGE-SNAPSHOT saved page=%@ events=%lu file=%@ bytes=%lu\",\n"
    "                 sessionKey, (unsigned long)[[entry objectForKey:@\"events\"] count], file, (unsigned long)d.length]);",
    "        JCG5Log([NSString stringWithFormat:@\"PAGE-SNAPSHOT saved page=%@ events=%lu file=%@ bytes=%lu\",\n"
    "                 sessionKey, (unsigned long)[[entry objectForKey:@\"events\"] count], file, (unsigned long)d.length]);\n"
    "        JCG83OnCanonicalSnapshotWrite(sessionKey, entry, file, semanticChanged);",
    "canonical callback after atomic write",
)

# Controller-only runtime state. No business JSON is stored here.
rep(
    "static NSString *gJCG81Mode2DataDir;\n",
    "static NSString *gJCG81Mode2DataDir;\n"
    "// JCG5_SNAPSHOT_MODE_UNIFY_V083\n"
    "static NSString *gJCG83Mode1PendingUI;\n"
    "static unsigned long long gJCG83Mode1RuntimeGeneration = 0;\n"
    "static unsigned long long gJCG83Mode1CompletedGeneration = 0;\n"
    "static NSString *gJCG83Mode1SnapshotKey;\n"
    "static NSString *gJCG83Mode1SnapshotFile;\n"
    "static NSMutableSet *gJCG83Mode2CanonicalPages;\n"
    "static NSString *gJCG83Mode2SnapshotKey;\n"
    "static NSString *gJCG83Mode2SnapshotFile;\n"
    "static NSString *gJCG83Mode2RouterState;\n",
    "canonical mode globals",
)

# Disable the parallel business-data reducer. The helper code is left compiled
# for binary compatibility with the patch chain, but no active path feeds or
# writes it anymore.
for old, label in [
    ("        JCG81CaptureProtobufData(gJCG80Mode1Session, event);\n", "mode1 protobuf parallel reducer"),
    ("    JCG81CaptureProtobufData(session, event);\n", "mode2 protobuf parallel reducer"),
    ("        JCG81CaptureJSONData(gJCG80Mode1Session, meta, obj, bytes);\n", "mode1 JSON parallel reducer"),
    ("    JCG81CaptureJSONData(session, meta, obj, bytes);\n", "mode2 JSON parallel reducer"),
    ("    JCG81WriteCleanPageData(gJCG80Mode1Session, gJCG81Mode1DataDir);\n", "mode1 page_data writer"),
    ("    if (session) JCG81WriteCleanPageData(session, gJCG81Mode2DataDir);\n", "mode2 page_data writer"),
]:
    if old in s:
        s = s.replace(old, "", 1)
    else:
        raise SystemExit(f"v0.8.3 snapshot unify anchor missing: {label}")

# Define canonical callback immediately before the old observer; all v0.8 globals
# and JCG80SetStatus are already declared at this point.
observer_start = s.index("static void JCG80ObserveLuaChunkOnQueue(NSString *chunk, NSDictionary *ctx) {")
observer_end = s.index("\nstatic void JCG80ObserveLuaChunk(NSString *chunk) {", observer_start)

controller = r'''static void JCG83OnCanonicalSnapshotWrite(NSString *sessionKey, NSDictionary *entry, NSString *file, BOOL semanticChanged) {
    if (!sessionKey.length || !entry || !file.length) return;
    NSString *ui = [entry objectForKey:@"page_ui_lua"] ?: @"";
    NSString *tab = [entry objectForKey:@"page_tab_lua"] ?: @"";
    NSArray *children = [entry objectForKey:@"child_ui_luas"];
    NSDictionary *counts = [entry objectForKey:@"counts"] ?: @{};

    if (gJCG81Mode2Running && gJCG80Mode == JCG80CaptureModeAuto) {
        if (!gJCG83Mode2CanonicalPages) gJCG83Mode2CanonicalPages = [[NSMutableSet alloc] init];
        [gJCG83Mode2CanonicalPages addObject:sessionKey];
        [gJCG83Mode2SnapshotKey release]; gJCG83Mode2SnapshotKey = [sessionKey copy];
        [gJCG83Mode2SnapshotFile release]; gJCG83Mode2SnapshotFile = [file copy];
        [gJCG81Mode2CurrentUI release]; gJCG81Mode2CurrentUI = [ui copy];

        JCG80SetStatus([NSString stringWithFormat:
            @"Mode2 🔄 已启动｜导航器%@\n快照%lu页｜当前 %@\nJSON%@ Req%@ Resp%@｜%@",
            gJCG83Mode2RouterState.length ? gJCG83Mode2RouterState : @"未解析",
            (unsigned long)gJCG83Mode2CanonicalPages.count,
            ui.length ? ui : sessionKey,
            [counts objectForKey:@"json_events"] ?: @0,
            [counts objectForKey:@"protobuf_requests"] ?: @0,
            [counts objectForKey:@"protobuf_responses"] ?: @0,
            semanticChanged ? @"数据有变化" : @"数据未变化"]);
        return;
    }

    if (gJCG80Mode == JCG80CaptureModeManual) {
        BOOL matchesPending = !gJCG83Mode1PendingUI.length ||
                              [ui isEqualToString:gJCG83Mode1PendingUI] ||
                              ([children isKindOfClass:[NSArray class]] && [children containsObject:gJCG83Mode1PendingUI]);
        if (!matchesPending) return;

        [gJCG83Mode1SnapshotKey release]; gJCG83Mode1SnapshotKey = [sessionKey copy];
        [gJCG83Mode1SnapshotFile release]; gJCG83Mode1SnapshotFile = [file copy];
        gJCG83Mode1CompletedGeneration = gJCG83Mode1RuntimeGeneration;
        JCG80SetStatus([NSString stringWithFormat:
            @"Mode1 ✅ canonical snapshot｜gen %llu/%llu\n%@%@%@\n%@｜%@",
            gJCG83Mode1CompletedGeneration, gJCG83Mode1RuntimeGeneration,
            ui.length ? ui : @"(no-ui)",
            tab.length ? @" | " : @"",
            tab.length ? tab : @"",
            file,
            semanticChanged ? @"数据有变化" : @"数据未变化"]);
    }
}

static void JCG80ObserveLuaChunkOnQueue(NSString *chunk, NSDictionary *ctx) {
    if (!chunk.length) return;

    // Runtime-latest UI is a TRIGGER only. The authoritative page/result is the
    // canonical v0.7.1+ snapshot callback above.
    if (gJCG80Mode == JCG80CaptureModeManual) {
        if (JCG80IsUIChunk(chunk) && ![chunk isEqualToString:gJCG83Mode1PendingUI]) {
            [gJCG83Mode1PendingUI release];
            gJCG83Mode1PendingUI = [chunk copy];
            gJCG83Mode1RuntimeGeneration++;
            JCG80SetStatus([NSString stringWithFormat:
                @"Mode1 🔄 runtime变化 gen %llu\n%@\n等待对应 runtime_page_snapshot",
                gJCG83Mode1RuntimeGeneration, chunk]);
            JCG5Log([NSString stringWithFormat:@"MODE1 trigger generation=%llu ui=%@ authority=runtime_page_snapshot",
                     gJCG83Mode1RuntimeGeneration, chunk]);
        }
        return;
    }

    // Mode2 may observe the latest Lua for diagnostics, but observed UI chunks
    // are NOT counted as completed pages. Canonical snapshot keys are the only
    // page-completion identity, so transient popup/child UI follows v0.7.1 aliasing.
    if (gJCG80Mode == JCG80CaptureModeAuto && gJCG81Mode2Running && JCG80IsUIChunk(chunk)) {
        [gJCG81Mode2CurrentUI release];
        gJCG81Mode2CurrentUI = [chunk copy];
        if (!gJCG83Mode2SnapshotKey.length) {
            JCG80SetStatus([NSString stringWithFormat:
                @"Mode2 ✅ 已启动｜导航器%@\n观察到 %@\n等待 canonical snapshot",
                gJCG83Mode2RouterState.length ? gJCG83Mode2RouterState : @"未解析", chunk]);
        }
    }
}
'''

s = s[:observer_start] + controller + s[observer_end:]

# Start/stop lifecycle is truthful. Until a real router is discovered, do not
# claim active full-auto navigation. The button still arms Mode2 at server select.
start = s.index("static void JCG81StartMode2OnQueue(void) {")
end = s.index("\nstatic void JCG81StartMode2(void) {", start)
new_start = r'''static void JCG81StartMode2OnQueue(void) {
    JCG80EnsurePaths();
    if (!gJCG80Whitelist) JCG80LoadWhitelist();
    gJCG80Mode = JCG80CaptureModeAuto;
    gJCG81Mode2Running = YES;
    gJCG81Mode2JSONEvents = 0;
    gJCG81Mode2PBEvents = 0;
    if (!gJCG83Mode2CanonicalPages) gJCG83Mode2CanonicalPages = [[NSMutableSet alloc] init];
    [gJCG83Mode2CanonicalPages removeAllObjects];
    [gJCG83Mode2SnapshotKey release]; gJCG83Mode2SnapshotKey = nil;
    [gJCG83Mode2SnapshotFile release]; gJCG83Mode2SnapshotFile = nil;
    [gJCG81Mode2CurrentUI release]; gJCG81Mode2CurrentUI = nil;
    [gJCG83Mode2RouterState release]; gJCG83Mode2RouterState = [@"等待解析" copy];
    JCG80SetStatus([NSString stringWithFormat:
        @"Mode2 ✅ 已启动｜等待 UI 导航器解析\n结果统一到 runtime_page_snapshot\n白名单%lu",
        (unsigned long)gJCG80Whitelist.count]);
    JCG5Log([NSString stringWithFormat:@"MODE2 start authority=runtime_page_snapshot router=pending whitelist=%lu",
             (unsigned long)gJCG80Whitelist.count]);
}'''
s = s[:start] + new_start + s[end:]

# Stop summary uses canonical pages, not number of Lua UI chunks observed.
s = s.replace("NSUInteger pages = gJCG81Mode2RunPages.count;",
              "NSUInteger pages = gJCG83Mode2CanonicalPages.count;", 1)
s = s.replace("Mode2 ✅ 已停止｜页面%lu JSON%llu Protobuf%llu\\n最后 %@｜Mode1 自动监听已恢复",
              "Mode2 ✅ 已停止｜canonical快照%lu页\\n最后 %@｜Mode1 canonical监听已恢复", 1)
s = s.replace("(unsigned long)pages, gJCG81Mode2JSONEvents, gJCG81Mode2PBEvents, last",
              "(unsigned long)pages, last", 1)

# Initialization wording: Mode1 follows canonical snapshots, not an independent page reducer.
s = s.replace(
    "Mode1 ✅ 自动监听｜白名单%lu\\n等待运行时最新 UI 变化",
    "Mode1 ✅ canonical监听｜白名单%lu\\n等待运行时 UI 变化 → runtime_page_snapshot",
    1)

# Hard gate: active Mode1/2 paths must not feed or write the old parallel reducer.
for forbidden in (
    "JCG81CaptureJSONData(gJCG80Mode1Session",
    "JCG81CaptureJSONData(session, meta",
    "JCG81CaptureProtobufData(gJCG80Mode1Session",
    "JCG81CaptureProtobufData(session, event",
    "JCG81WriteCleanPageData(gJCG80Mode1Session",
    "JCG81WriteCleanPageData(session, gJCG81Mode2DataDir",
):
    if forbidden in s:
        raise SystemExit(f"parallel mode reducer still active: {forbidden}")

s += '\n// JCG5_SNAPSHOT_MODE_UNIFY_V083 authority=runtime_page_snapshot mode1-mode2=control-only\n'
p.write_text(s, encoding="utf-8")
print("applied v0.8.3 Mode1/Mode2 canonical runtime_page_snapshot unification")
