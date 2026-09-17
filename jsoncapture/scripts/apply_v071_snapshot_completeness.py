#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_SNAPSHOT_COMPLETENESS_V071"
if MARKER in s:
    print("v0.7.1 snapshot completeness patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_PAGE_PROTOBUF_V060_HARDENED",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.7.1 patch anchor missing: {label}")
    s = s.replace(old, new, 1)

# JCG5_SNAPSHOT_COMPLETENESS_V071
# Keep the generic Lua/TAB snapshot limits unchanged, but let protobuf business
# messages use a deeper, still-bounded descriptor-aware walker. This avoids
# weakening safety for unrelated Lua tables.
rep(
    "static id JCG60SnapshotLuaValue(void *L, int idx, NSUInteger depth, NSMutableSet *visited, NSUInteger *budget) {\n",
    "// JCG5_SNAPSHOT_COMPLETENESS_V071\\n"\n    "static id JCG60SnapshotLuaValueLimited(void *L, int idx, NSUInteger depth, NSMutableSet *visited, NSUInteger *budget, NSUInteger maxDepth, NSUInteger maxNodes) {\\n",
    "parameterize lua snapshot function",
)
rep(
    '    if (*budget >= JCG60_LUA_SNAPSHOT_MAX_NODES) return @"<node-limit>";\n',
    '    if (*budget >= maxNodes) return @"<node-limit>";\n',
    "parameterized node-limit check",
)
rep(
    '        if (depth >= JCG60_LUA_SNAPSHOT_MAX_DEPTH) return @"<table-depth-limit>";\n',
    '        if (depth >= maxDepth) return @"<table-depth-limit>";\n',
    "parameterized depth-limit check",
)
rep(
    "            id value = JCG60SnapshotLuaValue(L, -1, depth + 1, visited, budget) ?: [NSNull null];\n",
    "            id value = JCG60SnapshotLuaValueLimited(L, -1, depth + 1, visited, budget, maxDepth, maxNodes) ?: [NSNull null];\n",
    "parameterized recursive snapshot",
)
rep(
    "            if (*budget >= JCG60_LUA_SNAPSHOT_MAX_NODES) { JCG60Pop(L, 1); break; }\n",
    "            if (*budget >= maxNodes) { JCG60Pop(L, 1); break; }\n",
    "parameterized balanced node break",
)

old_snapshot = r'''static id JCG60Snapshot(void *L, int idx) {
    NSUInteger budget = 0;
    NSMutableSet *visited = [NSMutableSet set];
    return JCG60SnapshotLuaValue(L, idx, 0, visited, &budget);
}
'''
new_snapshot = r'''#define JCG71_PROTOBUF_SNAPSHOT_MAX_DEPTH 32
#define JCG71_PROTOBUF_SNAPSHOT_MAX_NODES 32768

static id JCG60Snapshot(void *L, int idx) {
    NSUInteger budget = 0;
    NSMutableSet *visited = [NSMutableSet set];
    return JCG60SnapshotLuaValueLimited(L, idx, 0, visited, &budget,
                                        JCG60_LUA_SNAPSHOT_MAX_DEPTH,
                                        JCG60_LUA_SNAPSHOT_MAX_NODES);
}

static id JCG71SnapshotProtobuf(void *L, int idx) {
    NSUInteger budget = 0;
    NSMutableSet *visited = [NSMutableSet set];
    return JCG60SnapshotLuaValueLimited(L, idx, 0, visited, &budget,
                                        JCG71_PROTOBUF_SNAPSHOT_MAX_DEPTH,
                                        JCG71_PROTOBUF_SNAPSHOT_MAX_NODES);
}
'''
rep(old_snapshot, new_snapshot, "protobuf-specific snapshot limits")

rep(
    "JCG70NormalizeProtobufObject(JCG60Snapshot(L, 2))",
    "JCG70NormalizeProtobufObject(JCG71SnapshotProtobuf(L, 2))",
    "deep request protobuf snapshot",
)
rep(
    "JCG70NormalizeProtobufObject(JCG60Snapshot(L, resultObjIndex))",
    "JCG70NormalizeProtobufObject(JCG71SnapshotProtobuf(L, resultObjIndex))",
    "deep response protobuf snapshot",
)

# Stable-parent child-UI merge. A new UI sharing the same TAB is folded into a
# recent parent only when that parent has already shown enough lifetime/events
# to be a real page. This avoids anchoring transient startup UIHud/Loading pages.
rep(
    "static NSString *gJCG70LastSnapshotFile;\n\n"
    "static NSString *JCG70PageSessionKey(NSDictionary *event) {\n"
    "    NSString *ui = [event objectForKey:@\"page_ui_lua\"] ?: @\"\";\n"
    "    NSString *tab = [event objectForKey:@\"page_tab_lua\"] ?: @\"\";\n"
    "    NSString *page = [event objectForKey:@\"page_context\"] ?: @\"\";\n"
    "    if (ui.length && tab.length) return [NSString stringWithFormat:@\"%@|%@\", ui, tab];\n"
    "    if (tab.length) return tab;\n"
    "    if (ui.length) return ui;\n"
    "    return page.length ? page : @\"(unknown)\";\n"
    "}\n",
    "static NSString *gJCG70LastSnapshotFile;\n"
    "static NSMutableDictionary *gJCG71SessionAliases;\n"
    "static unsigned long long gJCG71ChildUIMerges = 0;\n\n"
    "static NSString *JCG71RawPageSessionKey(NSDictionary *event) {\n"
    "    NSString *ui = [event objectForKey:@\"page_ui_lua\"] ?: @\"\";\n"
    "    NSString *tab = [event objectForKey:@\"page_tab_lua\"] ?: @\"\";\n"
    "    NSString *page = [event objectForKey:@\"page_context\"] ?: @\"\";\n"
    "    if (ui.length && tab.length) return [NSString stringWithFormat:@\"%@|%@\", ui, tab];\n"
    "    if (tab.length) return tab;\n"
    "    if (ui.length) return ui;\n"
    "    return page.length ? page : @\"(unknown)\";\n"
    "}\n\n"
    "static NSString *JCG70PageSessionKey(NSDictionary *event) {\n"
    "    NSString *raw = JCG71RawPageSessionKey(event);\n"
    "    NSString *canonical = [gJCG71SessionAliases objectForKey:raw];\n"
    "    return canonical.length ? canonical : raw;\n"
    "}\n",
    "canonical page-session aliasing",
)

merge_helpers = r'''
#define JCG71_CHILD_PARENT_MAX_GAP 4.0
#define JCG71_STABLE_PARENT_MIN_SECONDS 5.0
#define JCG71_STABLE_PARENT_MIN_EVENTS 8

static BOOL JCG71EntryIsStableParent(NSDictionary *entry) {
    if (!entry) return NO;
    NSUInteger events = [[entry objectForKey:@"events"] count];
    NSTimeInterval first = [[entry objectForKey:@"first_seen"] doubleValue];
    NSTimeInterval last = [[entry objectForKey:@"last_seen"] doubleValue];
    return events >= JCG71_STABLE_PARENT_MIN_EVENTS ||
           (first > 0 && last >= first && (last - first) >= JCG71_STABLE_PARENT_MIN_SECONDS);
}

static NSString *JCG71FindStableParentSession(NSDictionary *event, NSString *rawSessionKey) {
    NSString *tab = [event objectForKey:@"page_tab_lua"] ?: @"";
    if (!tab.length || !gJCG70Snapshots.count) return nil;

    NSTimeInterval eventTime = [[event objectForKey:@"time"] doubleValue];
    if (eventTime <= 0) eventTime = [[NSDate date] timeIntervalSince1970];

    NSString *best = nil;
    NSTimeInterval bestLast = 0;
    for (NSString *key in gJCG70Snapshots) {
        if ([key isEqualToString:rawSessionKey]) continue;
        NSDictionary *candidate = [gJCG70Snapshots objectForKey:key];
        if (!candidate || !JCG71EntryIsStableParent(candidate)) continue;
        NSString *candidateTab = [candidate objectForKey:@"page_tab_lua"] ?: @"";
        if (![candidateTab isEqualToString:tab]) continue;

        NSTimeInterval last = [[candidate objectForKey:@"last_seen"] doubleValue];
        NSTimeInterval gap = eventTime - last;
        if (gap < -0.25 || gap > JCG71_CHILD_PARENT_MAX_GAP) continue;
        if (!best || last > bestLast) {
            best = key;
            bestLast = last;
        }
    }
    return best;
}

static void JCG71NoteChildUI(NSMutableDictionary *entry, NSDictionary *event) {
    NSString *ui = [event objectForKey:@"page_ui_lua"] ?: @"";
    NSString *rootUI = [entry objectForKey:@"page_ui_lua"] ?: @"";
    if (!ui.length || [ui isEqualToString:rootUI]) return;
    NSMutableArray *children = [entry objectForKey:@"child_ui_luas"];
    if (![children isKindOfClass:[NSMutableArray class]]) {
        children = [NSMutableArray array];
        [entry setObject:children forKey:@"child_ui_luas"];
    }
    if (![children containsObject:ui]) [children addObject:ui];
    [entry setObject:ui forKey:@"last_event_ui_lua"];
    NSString *ctx = [event objectForKey:@"page_context"] ?: @"";
    if (ctx.length) [entry setObject:ctx forKey:@"last_event_context"];
}

'''
rep(
    "static NSMutableDictionary *JCG70SnapshotEntry(NSDictionary *event) {\n",
    merge_helpers + "static NSMutableDictionary *JCG70SnapshotEntry(NSDictionary *event) {\n",
    "stable-parent helpers",
)

old_entry_head = r'''static NSMutableDictionary *JCG70SnapshotEntry(NSDictionary *event) {
    JCG70EnsureSnapshotPaths();
    NSString *sessionKey = JCG70PageSessionKey(event);
    NSMutableDictionary *entry = [gJCG70Snapshots objectForKey:sessionKey];
    if (!entry) {
'''
new_entry_head = r'''static NSMutableDictionary *JCG70SnapshotEntry(NSDictionary *event) {
    JCG70EnsureSnapshotPaths();
    if (!gJCG71SessionAliases) gJCG71SessionAliases = [[NSMutableDictionary alloc] init];

    NSString *rawSessionKey = JCG71RawPageSessionKey(event);
    NSString *sessionKey = [gJCG71SessionAliases objectForKey:rawSessionKey] ?: rawSessionKey;
    BOOL mergedChild = ![sessionKey isEqualToString:rawSessionKey];

    NSMutableDictionary *entry = [gJCG70Snapshots objectForKey:sessionKey];
    if (!entry && !mergedChild) {
        NSString *parent = JCG71FindStableParentSession(event, rawSessionKey);
        if (parent.length) {
            [gJCG71SessionAliases setObject:parent forKey:rawSessionKey];
            sessionKey = parent;
            entry = [gJCG70Snapshots objectForKey:sessionKey];
            mergedChild = entry != nil;
            if (mergedChild) {
                pthread_mutex_lock(&gJCG5StateLock);
                gJCG71ChildUIMerges++;
                pthread_mutex_unlock(&gJCG5StateLock);
                JCG5Log([NSString stringWithFormat:@"PAGE-SNAPSHOT child-ui merge raw=%@ parent=%@ ui=%@",
                         rawSessionKey, sessionKey, [event objectForKey:@"page_ui_lua"] ?: @""]);
            }
        }
    }

    if (!entry) {
'''
rep(old_entry_head, new_entry_head, "snapshot entry parent resolution")

rep(
    '            @"merge_policy": @"exact event history + latest recursive merge per message/endpoint",\n'
    '            @"screen_widget_state": @NO\n',
    '            @"merge_policy": @"exact event history + latest recursive merge per message/endpoint",\n'
    '            @"protobuf_snapshot_limits": @{@"max_depth": @32, @"max_nodes": @32768},\n'
    '            @"child_ui_policy": @"same TAB + <=4s gap + stable parent (>=8 events or >=5s lifetime)",\n'
    '            @"screen_widget_state": @NO\n',
    "snapshot completeness metadata",
)

old_entry_tail = r'''    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_seen"];
    NSString *ctx = [event objectForKey:@"page_context"]; if (ctx.length) [entry setObject:ctx forKey:@"page_context"];
    NSString *ui = [event objectForKey:@"page_ui_lua"]; if (ui.length) [entry setObject:ui forKey:@"page_ui_lua"];
    NSString *tab = [event objectForKey:@"page_tab_lua"]; if (tab.length) [entry setObject:tab forKey:@"page_tab_lua"];
'''
new_entry_tail = r'''    [entry setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"last_seen"];
    NSString *ctx = [event objectForKey:@"page_context"];
    NSString *ui = [event objectForKey:@"page_ui_lua"];
    if (mergedChild) {
        JCG71NoteChildUI(entry, event);
    } else {
        if (ctx.length) [entry setObject:ctx forKey:@"page_context"];
        if (ui.length) [entry setObject:ui forKey:@"page_ui_lua"];
    }
    NSString *tab = [event objectForKey:@"page_tab_lua"]; if (tab.length) [entry setObject:tab forKey:@"page_tab_lua"];
'''
rep(old_entry_tail, new_entry_tail, "preserve root UI for merged child events")

# Surface the child-merge count and explicit v0.7.1 readiness marker.
rep(
    "    unsigned long long snapPages = gJCG70SnapshotPages, snapWrites = gJCG70SnapshotWrites;\n",
    "    unsigned long long snapPages = gJCG70SnapshotPages, snapWrites = gJCG70SnapshotWrites, childMerges = gJCG71ChildUIMerges;\n",
    "child merge UI counter",
)
rep(
    '    return [NSString stringWithFormat:@"Protobuf：发送%@ 接收%@｜Req%llu Resp%llu Raw%llu 解析失败%llu\\n页面快照：%llu页 写入%llu｜%@\\n最新：%lld %@｜%@",\n'
    '            send ? @"✅" : @"…", parse ? @"✅" : @"…", req, resp, raw, fail,\n'
    '            snapPages, snapWrites, snapFile.length ? snapFile : @"等待页面数据",\n',
    '    return [NSString stringWithFormat:@"Protobuf：发送%@ 接收%@｜Req%llu Resp%llu Raw%llu 解析失败%llu\\n页面快照：%llu页 写入%llu 子窗合并%llu｜%@\\n最新：%lld %@｜%@",\n'
    '            send ? @"✅" : @"…", parse ? @"✅" : @"…", req, resp, raw, fail,\n'
    '            snapPages, snapWrites, childMerges, snapFile.length ? snapFile : @"等待页面数据",\n',
    "snapshot status merge count",
)
rep(
    '        JCG5Log(@"PAGE-SNAPSHOT v0.7.0 ready descriptor=runtime page=request-correlated reducer=serial-capture-queue");\n',
    '        JCG5Log(@"PAGE-SNAPSHOT v0.7.1 ready descriptor=runtime protobuf-depth=32 nodes=32768 child-ui=stable-parent reducer=serial-capture-queue");\n',
    "v0.7.1 readiness marker",
)

p.write_text(s, encoding="utf-8")
print("applied v0.7.1 snapshot completeness")
