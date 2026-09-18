#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
marker = "JCG5_ROUTER_DISCOVERY_FIX_V083"
if marker in s:
    print("v0.8.3 router discovery fix already applied")
    raise SystemExit(0)
if "JCG5_ROUTER_DISCOVERY_V083" not in s:
    raise SystemExit("router discovery base patch missing")

# Add retry state.
old = "static unsigned long long gJCG83RouterDiscoveryGeneration = 0;\n"
new = old + "static unsigned long long gJCG83RouterDiscoveryAttempts = 0;\nstatic NSTimeInterval gJCG83RouterLastAttemptAt = 0;\n"
if old not in s:
    raise SystemExit("router retry globals anchor missing")
s = s.replace(old, new, 1)

# Replace ResourcesUI reader. Supports both standard config-table shape
# (-1 header + positive numeric array rows) and dictionary/object rows.
start = s.find("static NSArray *JCG83SnapshotResourcesUI(void *L, BOOL *foundOut) {")
end = s.find("\nstatic NSArray *JCG83SnapshotGlobalRouterCandidates", start)
if start < 0 or end < 0:
    raise SystemExit("ResourcesUI reader anchors missing")
new_reader = r'''static id JCG83ResourcesValueFromRow(id row, NSDictionary *headerMap, NSString *field) {
    if (!row || !field.length) return nil;
    if ([row isKindOfClass:[NSDictionary class]]) return [(NSDictionary *)row objectForKey:field];
    if ([row isKindOfClass:[NSArray class]]) {
        NSNumber *oneBased = [headerMap objectForKey:field];
        if (!oneBased) return nil;
        NSInteger idx = oneBased.integerValue - 1;
        if (idx >= 0 && idx < (NSInteger)[(NSArray *)row count]) return [(NSArray *)row objectAtIndex:(NSUInteger)idx];
    }
    return nil;
}

static NSString *JCG83ResourcesString(id value) {
    if (!value || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return [value description] ?: @"";
}

static NSArray *JCG83SnapshotResourcesUI(void *L, BOOL *foundOut) {
    if (foundOut) *foundOut = NO;
    if (!L || !gJCG58LuaGetTop || !gJCG58LuaSetTop || !gJCG58LuaGetGlobal ||
        !gJCG60LuaPushNil || !gJCG60LuaNext || !gJCG58LuaType) return @[];
    int top = gJCG58LuaGetTop(L);
    int t = gJCG58LuaGetGlobal(L, "TAB_ResourcesUI");
    if (t != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return @[]; }
    if (foundOut) *foundOut = YES;
    int tableIndex = JCG60AbsIndex(L, -1);

    // Pass 1: recover the standard TAB header stored at numeric key -1.
    NSMutableDictionary *headerMap = [NSMutableDictionary dictionary];
    gJCG60LuaPushNil(L);
    while (gJCG60LuaNext(L, tableIndex) != 0) {
        int keyType = gJCG58LuaType(L, -2);
        if (keyType == JCG60_LUA_TNUMBER) {
            int ok = 0;
            long long key = gJCG58LuaToIntegerX ? (long long)gJCG58LuaToIntegerX(L, -2, &ok) : 0;
            if (ok && key == -1 && gJCG58LuaType(L, -1) == JCG60_LUA_TTABLE) {
                id header = JCG60Snapshot(L, -1);
                if ([header isKindOfClass:[NSArray class]]) {
                    NSUInteger i = 0;
                    for (id name in (NSArray *)header) {
                        i++;
                        if ([name isKindOfClass:[NSString class]] && [name length])
                            [headerMap setObject:@(i) forKey:name];
                    }
                }
            }
        }
        JCG60Pop(L, 1);
    }

    // Pass 2: snapshot one row at a time. Per-row JCG60Snapshot gets a fresh
    // node budget, so a 700+ row ResourcesUI table is not truncated globally.
    NSMutableArray *rows = [NSMutableArray array];
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0;
    while (gJCG60LuaNext(L, tableIndex) != 0 && visited < 2500) {
        visited++;
        int keyType = gJCG58LuaType(L, -2);
        BOOL positiveRow = NO;
        NSString *rowKey = JCG83LuaKeyString(L, -2);
        if (keyType == JCG60_LUA_TNUMBER) {
            int ok = 0;
            long long k = gJCG58LuaToIntegerX ? (long long)gJCG58LuaToIntegerX(L, -2, &ok) : 0;
            positiveRow = ok && k > 0;
        } else if (keyType == JCG60_LUA_TSTRING) {
            positiveRow = YES; // dictionary-keyed config variant
        }
        if (positiveRow && gJCG58LuaType(L, -1) == JCG60_LUA_TTABLE) {
            @autoreleasepool {
                id row = JCG60Snapshot(L, -1);
                NSString *ui = JCG83ResourcesString(JCG83ResourcesValueFromRow(row, headerMap, @"UIName"));
                NSString *action = JCG83ResourcesString(JCG83ResourcesValueFromRow(row, headerMap, @"Action"));
                NSString *close = JCG83ResourcesString(JCG83ResourcesValueFromRow(row, headerMap, @"Close"));
                NSString *title = JCG83ResourcesString(JCG83ResourcesValueFromRow(row, headerMap, @"UITitle"));
                NSString *obscure = JCG83ResourcesString(JCG83ResourcesValueFromRow(row, headerMap, @"Obscure"));
                NSString *hideCity = JCG83ResourcesString(JCG83ResourcesValueFromRow(row, headerMap, @"HideUICity"));
                if (ui.length || action.length || close.length) {
                    NSMutableDictionary *r = [NSMutableDictionary dictionary];
                    if (rowKey.length) r[@"key"] = rowKey;
                    if (ui.length) r[@"UIName"] = ui;
                    if (action.length) r[@"Action"] = action;
                    if (close.length) r[@"Close"] = close;
                    if (title.length) r[@"UITitle"] = title;
                    if (obscure.length) r[@"Obscure"] = obscure;
                    if (hideCity.length) r[@"HideUICity"] = hideCity;
                    [rows addObject:r];
                }
            }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, top);
    return rows;
}
'''
s = s[:start] + new_reader + s[end:]

# Replace observer with retry/cooldown. Global candidate scan only runs after
# ResourcesUI is actually loaded and yielded useful rows.
start = s.find("static void JCG83RouterObserveLuaState(void *L) {")
end = s.find("\nstatic void JCG83OnCanonicalSnapshotWrite", start)
if start < 0 or end < 0:
    raise SystemExit("router observer anchors missing")
new_observer = r'''static void JCG83RouterObserveLuaState(void *L) {
    if (!L || !gJCG81Mode2Running || gJCG80Mode != JCG80CaptureModeAuto ||
        gJCG83RouterDiscoveryDone || gJCG83RouterDiscoveryRunning) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gJCG83RouterLastAttemptAt > 0 && now - gJCG83RouterLastAttemptAt < 1.5) return;
    gJCG83RouterLastAttemptAt = now;
    if (!JCG60ResolveExtraLuaAPI(L)) return;
    gJCG83RouterDiscoveryRunning = YES;
    gJCG83RouterDiscoveryAttempts++;

    BOOL resourcesFound = NO;
    NSArray *resources = JCG83SnapshotResourcesUI(L, &resourcesFound);
    if (!resourcesFound || !resources.count) {
        [gJCG83Mode2RouterState release];
        gJCG83Mode2RouterState = [[NSString stringWithFormat:@"等待ResourcesUI(%llu)", gJCG83RouterDiscoveryAttempts] copy];
        if (gJCG83RouterDiscoveryAttempts == 1 || gJCG83RouterDiscoveryAttempts % 10 == 0) {
            JCG80SetStatus([NSString stringWithFormat:@"Mode2 ✅ 已启动｜%@\n结果统一到 runtime_page_snapshot",
                gJCG83Mode2RouterState]);
            JCG5Log([NSString stringWithFormat:@"MODE2 router discovery wait ResourcesUI attempt=%llu table=%d rows=%lu",
                gJCG83RouterDiscoveryAttempts, resourcesFound, (unsigned long)resources.count]);
        }
        gJCG83RouterDiscoveryRunning = NO;
        return;
    }

    NSArray *globals = JCG83SnapshotGlobalRouterCandidates(L);
    gJCG83RouterDiscoveryGeneration++;
    NSDictionary *report = @{
        @"schema":@2,
        @"version":@"0.8.3-router-discovery",
        @"read_only":@YES,
        @"unknown_functions_invoked":@NO,
        @"generation":@(gJCG83RouterDiscoveryGeneration),
        @"attempts":@(gJCG83RouterDiscoveryAttempts),
        @"resources_ui_found":@YES,
        @"resources_ui_rows":resources,
        @"resources_ui_row_count":@(resources.count),
        @"global_router_candidates":globals ?: @[],
        @"global_router_candidate_count":@(globals.count),
        @"written_at":@([[NSDate date] timeIntervalSince1970])
    };
    NSString *path = [gJCG5StateDir stringByAppendingPathComponent:@"Mode2.RouterDiscovery.json"];
    BOOL wrote = JCG5WriteJSON(report, path);
    [gJCG83Mode2RouterState release];
    gJCG83Mode2RouterState = [[NSString stringWithFormat:@"发现%lu候选/ResourcesUI%lu",
        (unsigned long)globals.count, (unsigned long)resources.count] copy];
    JCG80SetStatus([NSString stringWithFormat:
        @"Mode2 ✅ Router只读发现完成\nResourcesUI %lu｜候选函数/表 %lu\n%@",
        (unsigned long)resources.count, (unsigned long)globals.count,
        wrote ? @"已写 Mode2.RouterDiscovery.json" : @"写入诊断文件失败"]);
    JCG5Log([NSString stringWithFormat:@"MODE2 router discovery read-only resources=%lu candidates=%lu attempts=%llu wrote=%d",
             (unsigned long)resources.count, (unsigned long)globals.count, gJCG83RouterDiscoveryAttempts, wrote]);
    gJCG83RouterDiscoveryDone = YES;
    gJCG83RouterDiscoveryRunning = NO;
}
'''
s = s[:start] + new_observer + s[end:]

# Reset retry state per Mode2 start.
old = "    gJCG83RouterDiscoveryDone = NO;\n    gJCG83RouterDiscoveryRunning = NO;"
new = old + "\n    gJCG83RouterDiscoveryAttempts = 0;\n    gJCG83RouterLastAttemptAt = 0;"
if old not in s:
    raise SystemExit("router start reset anchor missing")
s = s.replace(old, new, 1)

s += "\n// JCG5_ROUTER_DISCOVERY_FIX_V083 resourcesui=array-or-dict retry=1\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.3 ResourcesUI array/dict + retry router discovery fix")
