#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
marker = "JCG5_ROUTER_DISCOVERY_V083"
if marker in s:
    print("v0.8.3 router discovery already applied")
    raise SystemExit(0)

for required in ("JCG5_SNAPSHOT_MODE_UNIFY_V083", "JCG5_V083_COMPILE_CLEANUP"):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old, new, label, count=1):
    global s
    if old not in s:
        raise SystemExit(f"router discovery anchor missing: {label}")
    s = s.replace(old, new, count)

# Forward declaration before the existing Lua wrappers. The implementation is
# inserted later, after the v0.8 Mode2 globals/status helper exist.
rep(
    "static int JCG60SendMsgWrapper(void *L) {",
    "static void JCG83RouterObserveLuaState(void *L);\n\nstatic int JCG60SendMsgWrapper(void *L) {",
    "router observer forward declaration",
)

# Both request and response wrappers execute on the real Lua VM thread. The
# discovery function is guarded and runs at most once per Mode2 start.
rep(
    "static int JCG60SendMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;",
    "static int JCG60SendMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;\n    JCG83RouterObserveLuaState(L);",
    "send wrapper router observation",
)
rep(
    "static int JCG60ParseMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;",
    "static int JCG60ParseMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;\n    JCG83RouterObserveLuaState(L);",
    "parse wrapper router observation",
)

# Insert implementation immediately before the canonical snapshot callback.
anchor = "static void JCG83OnCanonicalSnapshotWrite(NSString *sessionKey, NSDictionary *entry, NSString *file, BOOL semanticChanged) {"
pos = s.find(anchor)
if pos < 0:
    raise SystemExit("canonical callback anchor missing")

impl = r'''// JCG5_ROUTER_DISCOVERY_V083
// Read-only discovery: no candidate function is invoked here.
static BOOL gJCG83RouterDiscoveryDone = NO;
static BOOL gJCG83RouterDiscoveryRunning = NO;
static unsigned long long gJCG83RouterDiscoveryGeneration = 0;

static BOOL JCG83RouterKeyword(NSString *name) {
    if (!name.length) return NO;
    NSString *l = name.lowercaseString;
    return [l containsString:@"ui"] || [l containsString:@"open"] ||
           [l containsString:@"show"] || [l containsString:@"close"] ||
           [l containsString:@"action"] || [l containsString:@"view"] ||
           [l containsString:@"panel"] || [l containsString:@"window"];
}

static NSString *JCG83LuaKeyString(void *L, int idx) {
    if (!L || !gJCG58LuaType) return @"";
    int type = gJCG58LuaType(L, idx);
    if (type == JCG60_LUA_TSTRING) {
        size_t n = 0;
        const char *p = gJCG58LuaToLString ? gJCG58LuaToLString(L, idx, &n) : NULL;
        if (p && n && n < 4096) {
            NSString *v = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
            return v ?: @"";
        }
    }
    if (type == JCG60_LUA_TNUMBER) {
        int ok = 0;
        long long v = gJCG58LuaToIntegerX ? (long long)gJCG58LuaToIntegerX(L, idx, &ok) : 0;
        if (ok) return [NSString stringWithFormat:@"%lld", v];
    }
    return @"";
}

static NSString *JCG83LuaFieldSummary(void *L, int tableIndex, const char *field) {
    if (!L || !field || !gJCG60LuaGetField || !gJCG58LuaGetTop || !gJCG58LuaSetTop) return @"";
    int top = gJCG58LuaGetTop(L);
    int type = gJCG60LuaGetField(L, tableIndex, field);
    NSString *out = @"";
    if (type == JCG60_LUA_TSTRING) {
        size_t n = 0;
        const char *p = gJCG58LuaToLString ? gJCG58LuaToLString(L, -1, &n) : NULL;
        if (p && n < 16384) out = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease] ?: @"";
    } else if (type == JCG60_LUA_TNUMBER) {
        int ok = 0;
        long long v = gJCG58LuaToIntegerX ? (long long)gJCG58LuaToIntegerX(L, -1, &ok) : 0;
        if (ok) out = [NSString stringWithFormat:@"%lld", v];
    } else if (type == JCG60_LUA_TBOOLEAN) {
        out = (gJCG58LuaToBoolean && gJCG58LuaToBoolean(L, -1)) ? @"true" : @"false";
    } else if (type == JCG60_LUA_TFUNCTION) out = @"<function>";
    else if (type == JCG60_LUA_TTABLE) out = @"<table>";
    gJCG58LuaSetTop(L, top);
    return out ?: @"";
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
    NSMutableArray *rows = [NSMutableArray array];
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0;
    while (gJCG60LuaNext(L, tableIndex) != 0 && visited < 2500) {
        visited++;
        @autoreleasepool {
            NSString *rowKey = JCG83LuaKeyString(L, -2);
            if (gJCG58LuaType(L, -1) == JCG60_LUA_TTABLE) {
                int rowIndex = JCG60AbsIndex(L, -1);
                NSString *ui = JCG83LuaFieldSummary(L, rowIndex, "UIName");
                NSString *action = JCG83LuaFieldSummary(L, rowIndex, "Action");
                NSString *close = JCG83LuaFieldSummary(L, rowIndex, "Close");
                NSString *title = JCG83LuaFieldSummary(L, rowIndex, "UITitle");
                NSString *obscure = JCG83LuaFieldSummary(L, rowIndex, "Obscure");
                NSString *hideCity = JCG83LuaFieldSummary(L, rowIndex, "HideUICity");
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
        JCG60Pop(L, 1); // pop value, keep key
    }
    gJCG58LuaSetTop(L, top);
    return rows;
}

static NSArray *JCG83SnapshotGlobalRouterCandidates(void *L) {
    if (!L || !gJCG58LuaGetTop || !gJCG58LuaSetTop || !gJCG58LuaGetGlobal ||
        !gJCG60LuaPushNil || !gJCG60LuaNext || !gJCG58LuaType) return @[];
    int top = gJCG58LuaGetTop(L);
    int t = gJCG58LuaGetGlobal(L, "_G");
    if (t != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return @[]; }
    int globalIndex = JCG60AbsIndex(L, -1);
    NSMutableArray *out = [NSMutableArray array];
    gJCG60LuaPushNil(L);
    NSUInteger globalsVisited = 0;
    while (gJCG60LuaNext(L, globalIndex) != 0 && globalsVisited < 10000) {
        globalsVisited++;
        @autoreleasepool {
            NSString *name = JCG83LuaKeyString(L, -2);
            int type = gJCG58LuaType(L, -1);
            if (name.length && JCG83RouterKeyword(name) && (type == JCG60_LUA_TFUNCTION || type == JCG60_LUA_TTABLE)) {
                [out addObject:@{ @"path":name, @"type":(type == JCG60_LUA_TFUNCTION ? @"function" : @"table") }];
            }
            if (name.length && type == JCG60_LUA_TTABLE && JCG83RouterKeyword(name) && out.count < 2000) {
                int childIndex = JCG60AbsIndex(L, -1);
                int childTop = gJCG58LuaGetTop(L);
                gJCG60LuaPushNil(L);
                NSUInteger childVisited = 0;
                while (gJCG60LuaNext(L, childIndex) != 0 && childVisited < 512 && out.count < 2000) {
                    childVisited++;
                    NSString *child = JCG83LuaKeyString(L, -2);
                    int childType = gJCG58LuaType(L, -1);
                    if (child.length && childType == JCG60_LUA_TFUNCTION && JCG83RouterKeyword(child)) {
                        [out addObject:@{ @"path":[NSString stringWithFormat:@"%@.%@",name,child], @"type":@"function" }];
                    }
                    JCG60Pop(L, 1);
                }
                gJCG58LuaSetTop(L, childTop);
            }
        }
        JCG60Pop(L, 1);
        if (out.count >= 2000) break;
    }
    gJCG58LuaSetTop(L, top);
    return out;
}

static void JCG83RouterObserveLuaState(void *L) {
    if (!L || !gJCG81Mode2Running || gJCG80Mode != JCG80CaptureModeAuto ||
        gJCG83RouterDiscoveryDone || gJCG83RouterDiscoveryRunning) return;
    if (!JCG60ResolveExtraLuaAPI(L)) return;
    gJCG83RouterDiscoveryRunning = YES;

    BOOL resourcesFound = NO;
    NSArray *resources = JCG83SnapshotResourcesUI(L, &resourcesFound);
    NSArray *globals = JCG83SnapshotGlobalRouterCandidates(L);
    gJCG83RouterDiscoveryGeneration++;

    NSDictionary *report = @{
        @"schema":@1,
        @"version":@"0.8.3-router-discovery",
        @"read_only":@YES,
        @"unknown_functions_invoked":@NO,
        @"generation":@(gJCG83RouterDiscoveryGeneration),
        @"resources_ui_found":@(resourcesFound),
        @"resources_ui_rows":resources ?: @[],
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
    JCG5Log([NSString stringWithFormat:@"MODE2 router discovery read-only resources=%lu candidates=%lu wrote=%d",
             (unsigned long)resources.count, (unsigned long)globals.count, wrote]);
    gJCG83RouterDiscoveryDone = YES;
    gJCG83RouterDiscoveryRunning = NO;
}

'''
s = s[:pos] + impl + s[pos:]

# Every Mode2 start gets a fresh discovery attempt. It remains read-only.
rep(
    "    [gJCG83Mode2RouterState release]; gJCG83Mode2RouterState = [@\"等待解析\" copy];",
    "    [gJCG83Mode2RouterState release]; gJCG83Mode2RouterState = [@\"等待解析\" copy];\n"
    "    gJCG83RouterDiscoveryDone = NO;\n"
    "    gJCG83RouterDiscoveryRunning = NO;",
    "reset router discovery at Mode2 start",
)

s += "\n// JCG5_ROUTER_DISCOVERY_V083 read-only=1 unknown-calls=0\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.3 read-only Mode2 router discovery")
