#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_MODE2_AUTO_V080A2"
if MARKER in s:
    print("v0.8.0-alpha2 Mode2 auto already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
    "JCG5_MODE1_EXACT_MIRROR_V080A1",
):
    if required not in s:
        raise SystemExit(f"required clean baseline marker missing: {required}")


def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.0-alpha2 anchor missing: {label}")
    s = s.replace(old, new, count)

rep(
    "static int JCG60SendMsgWrapper(void *L) {",
    "static void JCG80Mode2Pump(void *L);\n\nstatic int JCG60SendMsgWrapper(void *L) {",
    "Mode2 pump forward declaration",
)
rep(
    "static int JCG60SendMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;",
    "static int JCG60SendMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;\n    JCG80Mode2Pump(L);",
    "Mode2 pump on sendMsg Lua thread",
)
rep(
    "static int JCG60ParseMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;",
    "static int JCG60ParseMsgWrapper(void *L) {\n    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;\n    JCG80Mode2Pump(L);",
    "Mode2 pump on parseMsg Lua thread",
)

core = r'''
// JCG5_MODE2_AUTO_V080A2
// Mode2 = active UI navigation orchestration over the proven v0.7.1 reducer.
// It does NOT create another JSON/protobuf reducer and never calls business
// purchase/claim/network functions. All Lua calls run only from an existing
// game Lua callback (sendMsg/parseMsg), preserving lua_State thread identity.
typedef int (*JCG80LuaPCallKFn)(void *L, int nargs, int nresults, int errfunc, intptr_t ctx, void *k);
typedef const char *(*JCG80LuaPushLStringFn)(void *L, const char *s, size_t len);

static JCG80LuaPCallKFn gJCG80LuaPCallK = NULL;
static JCG80LuaPushLStringFn gJCG80LuaPushLString = NULL;
static BOOL gJCG80Mode2LuaAPIReady = NO;
static BOOL gJCG80Mode2Active = NO;
static BOOL gJCG80Mode2QueueReady = NO;
static BOOL gJCG80Mode2RouterReady = NO;
static BOOL gJCG80Mode2WaitingSnapshot = NO;
static BOOL gJCG80Mode2NeedClose = NO;
static BOOL gJCG80Mode2TriedNoSelf = NO;
static BOOL gJCG80Mode2CloseTriedNoSelf = NO;
static NSMutableArray *gJCG80Mode2Queue = nil;
static NSMutableSet *gJCG80Mode2Seen = nil;
static NSString *gJCG80Mode2Dir = nil;
static NSString *gJCG80Mode2RouterSource = nil; // global | package
static NSString *gJCG80Mode2RouterModule = nil;
static NSString *gJCG80Mode2OpenFunction = nil;
static NSString *gJCG80Mode2CloseFunction = nil;
static NSString *gJCG80Mode2CurrentUI = nil;
static unsigned long long gJCG80Mode2Index = 0;
static unsigned long long gJCG80Mode2Completed = 0;
static unsigned long long gJCG80Mode2Skipped = 0;
static unsigned long long gJCG80Mode2Failed = 0;
static NSTimeInterval gJCG80Mode2ActionAt = 0;
static NSTimeInterval gJCG80Mode2SnapshotAt = 0;

#define JCG80_MODE2_OPEN_TIMEOUT 6.0
#define JCG80_MODE2_CLOSE_TIMEOUT 3.0

static void JCG80Mode2SetString(NSString **slot, NSString *value) {
    [*slot release];
    *slot = [(value ?: @"") copy];
}

static NSString *JCG80Mode2Stem(NSString *name) {
    if (!name.length) return @"";
    NSString *base = [[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];
    return [base stringByDeletingPathExtension] ?: @"";
}

static BOOL JCG80Mode2DangerousUI(NSString *ui) {
    if (!ui.length || ![ui hasPrefix:@"UI"]) return YES;
    NSString *l = ui.lowercaseString;
    NSArray *deny = @[
        @"login", @"server", @"loading", @"reconnect", @"notice", @"tips", @"toast", @"pop", @"alert", @"confirm",
        @"pay", @"recharge", @"buy", @"purchase", @"sell", @"exchange", @"lottery", @"draw", @"reward", @"claim",
        @"gift", @"mailget", @"receive", @"charge", @"order", @"sdk", @"facebook", @"video", @"guide",
        @"fight", @"battle", @"combat", @"loading", @"hud", @"touch"
    ];
    for (NSString *x in deny) if ([l containsString:x]) return YES;
    return NO;
}

static BOOL JCG80Mode2ResolveLuaAPI(void *L) {
    if (gJCG80Mode2LuaAPIReady) return YES;
    if (!L || !JCG60ResolveExtraLuaAPI(L)) return NO;
    gJCG80LuaPCallK = (JCG80LuaPCallKFn)JCG5ResolveExport("lua_pcallk");
    gJCG80LuaPushLString = (JCG80LuaPushLStringFn)JCG5ResolveExport("lua_pushlstring");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 thread=existing-game-lua");
    return YES;
}

static NSString *JCG80Mode2LuaString(void *L, int idx) {
    if (!L || !gJCG58LuaToLString || !gJCG58LuaType || gJCG58LuaType(L, idx) != JCG60_LUA_TSTRING) return @"";
    size_t n = 0; const char *p = gJCG58LuaToLString(L, idx, &n);
    if (!p || !n || n > 4096) return @"";
    NSString *v = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
    return v ?: @"";
}

static void JCG80Mode2EnsureDir(void) {
    JCG5SetupPaths();
    if (!gJCG80Mode2Dir) gJCG80Mode2Dir = [[gJCG5Root stringByAppendingPathComponent:@"mode2_auto"] retain];
    JCG5EnsureDir(gJCG80Mode2Dir);
}

static BOOL JCG80Mode2PushModuleTable(void *L, NSString *source, NSString *module) {
    if (!L || !source.length || !module.length) return NO;
    if ([source isEqualToString:@"global"]) {
        return gJCG58LuaGetGlobal(L, module.UTF8String) == JCG60_LUA_TTABLE;
    }
    int top = gJCG58LuaGetTop(L);
    if (gJCG58LuaGetGlobal(L, "package") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return NO; }
    int pkg = JCG60AbsIndex(L, -1);
    if (gJCG60LuaGetField(L, pkg, "loaded") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return NO; }
    int loaded = JCG60AbsIndex(L, -1);
    if (gJCG60LuaGetField(L, loaded, module.UTF8String) != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return NO; }
    return YES;
}

static NSInteger JCG80Mode2OpenRank(NSString *name) {
    NSString *l = name.lowercaseString;
    NSArray *order = @[@"openui", @"showui", @"opendlg", @"showdlg", @"openview", @"showview", @"open", @"show", @"pushui", @"push"];
    NSUInteger i = [order indexOfObject:l];
    return i == NSNotFound ? 9999 : (NSInteger)i;
}

static NSInteger JCG80Mode2CloseRank(NSString *name) {
    NSString *l = name.lowercaseString;
    NSArray *order = @[@"closeui", @"hideui", @"closedlg", @"hidedlg", @"closeview", @"hideview", @"close", @"hide", @"popui", @"pop", @"back"];
    NSUInteger i = [order indexOfObject:l];
    return i == NSNotFound ? 9999 : (NSInteger)i;
}

static void JCG80Mode2InspectModuleAtTop(void *L, NSString *source, NSString *module,
                                         NSString **bestOpen, NSInteger *bestOpenRank,
                                         NSString **bestClose, NSInteger *bestCloseRank) {
    if (!L || gJCG58LuaType(L, -1) != JCG60_LUA_TTABLE) return;
    int tableIndex = JCG60AbsIndex(L, -1);
    int tableTop = gJCG58LuaGetTop(L);
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0;
    while (gJCG60LuaNext(L, tableIndex) != 0 && visited++ < 512) {
        NSString *key = JCG80Mode2LuaString(L, -2);
        if (key.length && gJCG58LuaType(L, -1) == JCG60_LUA_TFUNCTION) {
            NSInteger ro = JCG80Mode2OpenRank(key), rc = JCG80Mode2CloseRank(key);
            if (ro < *bestOpenRank) { *bestOpenRank = ro; JCG80Mode2SetString(bestOpen, key); }
            if (rc < *bestCloseRank) { *bestCloseRank = rc; JCG80Mode2SetString(bestClose, key); }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, tableTop);
}

static BOOL JCG80Mode2DiscoverRouter(void *L) {
    if (gJCG80Mode2RouterReady) return YES;
    if (!JCG80Mode2ResolveLuaAPI(L)) return NO;

    int rootTop = gJCG58LuaGetTop(L);
    NSArray *globals = @[@"DlgManager", @"UIManager", @"DialogManager", @"UIBase"];
    NSInteger bestOpenRank = 9999, bestCloseRank = 9999;
    NSString *bestOpen = nil, *bestClose = nil, *bestSource = nil, *bestModule = nil;

    for (NSString *module in globals) {
        gJCG58LuaSetTop(L, rootTop);
        if (gJCG58LuaGetGlobal(L, module.UTF8String) != JCG60_LUA_TTABLE) continue;
        NSString *o = nil, *c = nil; NSInteger ro = 9999, rc = 9999;
        JCG80Mode2InspectModuleAtTop(L, @"global", module, &o, &ro, &c, &rc);
        if (o.length && c.length && (ro + rc) < (bestOpenRank + bestCloseRank)) {
            bestOpenRank = ro; bestCloseRank = rc;
            JCG80Mode2SetString(&bestOpen, o); JCG80Mode2SetString(&bestClose, c);
            JCG80Mode2SetString(&bestSource, @"global"); JCG80Mode2SetString(&bestModule, module);
        }
        [o release]; [c release];
    }

    gJCG58LuaSetTop(L, rootTop);
    if (gJCG58LuaGetGlobal(L, "package") == JCG60_LUA_TTABLE) {
        int pkg = JCG60AbsIndex(L, -1);
        if (gJCG60LuaGetField(L, pkg, "loaded") == JCG60_LUA_TTABLE) {
            int loaded = JCG60AbsIndex(L, -1);
            int loadedTop = gJCG58LuaGetTop(L);
            gJCG60LuaPushNil(L);
            NSUInteger visited = 0;
            while (gJCG60LuaNext(L, loaded) != 0 && visited++ < 4096) {
                NSString *module = JCG80Mode2LuaString(L, -2);
                NSString *lm = module.lowercaseString;
                if (module.length && gJCG58LuaType(L, -1) == JCG60_LUA_TTABLE &&
                    ([lm containsString:@"dlgmanager"] || [lm containsString:@"uimanager"] || [lm containsString:@"dialogmanager"] || [lm containsString:@"uibase"])) {
                    NSString *o = nil, *c = nil; NSInteger ro = 9999, rc = 9999;
                    JCG80Mode2InspectModuleAtTop(L, @"package", module, &o, &ro, &c, &rc);
                    if (o.length && c.length && (ro + rc) < (bestOpenRank + bestCloseRank)) {
                        bestOpenRank = ro; bestCloseRank = rc;
                        JCG80Mode2SetString(&bestOpen, o); JCG80Mode2SetString(&bestClose, c);
                        JCG80Mode2SetString(&bestSource, @"package"); JCG80Mode2SetString(&bestModule, module);
                    }
                    [o release]; [c release];
                }
                JCG60Pop(L, 1);
            }
            gJCG58LuaSetTop(L, loadedTop);
        }
    }
    gJCG58LuaSetTop(L, rootTop);

    if (bestOpen.length && bestClose.length && bestSource.length && bestModule.length) {
        JCG80Mode2SetString(&gJCG80Mode2RouterSource, bestSource);
        JCG80Mode2SetString(&gJCG80Mode2RouterModule, bestModule);
        JCG80Mode2SetString(&gJCG80Mode2OpenFunction, bestOpen);
        JCG80Mode2SetString(&gJCG80Mode2CloseFunction, bestClose);
        gJCG80Mode2RouterReady = YES;
        JCG5Log([NSString stringWithFormat:@"MODE2 router ready source=%@ module=%@ open=%@ close=%@",
                 bestSource, bestModule, bestOpen, bestClose]);
    }
    [bestOpen release]; [bestClose release]; [bestSource release]; [bestModule release];
    return gJCG80Mode2RouterReady;
}

static BOOL JCG80Mode2BuildQueue(void *L) {
    if (gJCG80Mode2QueueReady) return YES;
    if (!JCG80Mode2ResolveLuaAPI(L)) return NO;
    int top = gJCG58LuaGetTop(L);
    if (gJCG58LuaGetGlobal(L, "TAB_ResourcesUI") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L, top); return NO; }
    int tableIndex = JCG60AbsIndex(L, -1);
    if (!gJCG80Mode2Queue) gJCG80Mode2Queue = [[NSMutableArray alloc] init];
    if (!gJCG80Mode2Seen) gJCG80Mode2Seen = [[NSMutableSet alloc] init];
    [gJCG80Mode2Queue removeAllObjects]; [gJCG80Mode2Seen removeAllObjects];
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0;
    while (gJCG60LuaNext(L, tableIndex) != 0 && visited++ < 2500) {
        if (gJCG58LuaType(L, -1) == JCG60_LUA_TTABLE) {
            int row = JCG60AbsIndex(L, -1);
            int before = gJCG58LuaGetTop(L);
            int t = gJCG60LuaGetField(L, row, "UIName");
            NSString *ui = t == JCG60_LUA_TSTRING ? JCG80Mode2LuaString(L, -1) : @"";
            gJCG58LuaSetTop(L, before);
            if (ui.length && !JCG80Mode2DangerousUI(ui) && ![gJCG80Mode2Seen containsObject:ui]) {
                [gJCG80Mode2Seen addObject:ui]; [gJCG80Mode2Queue addObject:ui];
            }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, top);
    [gJCG80Mode2Queue sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    gJCG80Mode2QueueReady = gJCG80Mode2Queue.count > 0;
    if (gJCG80Mode2QueueReady) {
        JCG5Log([NSString stringWithFormat:@"MODE2 queue ready safe=%lu visited=%lu source=TAB_ResourcesUI",
                 (unsigned long)gJCG80Mode2Queue.count, (unsigned long)visited]);
    }
    return gJCG80Mode2QueueReady;
}

static BOOL JCG80Mode2Invoke(void *L, NSString *functionName, NSString *ui, BOOL withSelf, NSString **errorOut) {
    if (errorOut) *errorOut = nil;
    if (!L || !functionName.length || !gJCG80Mode2RouterReady || !JCG80Mode2ResolveLuaAPI(L)) return NO;
    int top = gJCG58LuaGetTop(L);
    if (!JCG80Mode2PushModuleTable(L, gJCG80Mode2RouterSource, gJCG80Mode2RouterModule)) { gJCG58LuaSetTop(L, top); return NO; }
    int tableIndex = JCG60AbsIndex(L, -1);
    if (gJCG60LuaGetField(L, tableIndex, functionName.UTF8String) != JCG60_LUA_TFUNCTION) { gJCG58LuaSetTop(L, top); return NO; }
    int nargs = 0;
    if (withSelf) { gJCG58LuaPushValue(L, tableIndex); nargs++; }
    if (ui.length) { NSData *u = [ui dataUsingEncoding:NSUTF8StringEncoding]; gJCG80LuaPushLString(L, u.bytes, u.length); nargs++; }
    int status = gJCG80LuaPCallK(L, nargs, 0, 0, (intptr_t)0, NULL);
    if (status != 0 && errorOut) {
        NSString *err = JCG80Mode2LuaString(L, -1);
        *errorOut = [[(err.length ? err : [NSString stringWithFormat:@"lua_pcall status=%d", status]) copy] autorelease];
    }
    gJCG58LuaSetTop(L, top);
    return status == 0;
}

static BOOL JCG80Mode2CurrentGameReady(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    NSString *ui = [[(gJCG60UILua ?: @"") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    NSString *stem = JCG80Mode2Stem(ui).lowercaseString;
    if (!stem.length) return NO;
    if ([stem containsString:@"login"] || [stem containsString:@"server"] || [stem containsString:@"loading"]) return NO;
    return YES;
}

static void JCG80Mode2Advance(void) {
    gJCG80Mode2Index++;
    gJCG80Mode2WaitingSnapshot = NO;
    gJCG80Mode2NeedClose = NO;
    gJCG80Mode2TriedNoSelf = NO;
    gJCG80Mode2CloseTriedNoSelf = NO;
    gJCG80Mode2ActionAt = 0;
    gJCG80Mode2SnapshotAt = 0;
    JCG80Mode2SetString(&gJCG80Mode2CurrentUI, @"");
}

static void JCG80Mode2Stop(NSString *reason) {
    gJCG80Mode2Active = NO;
    JCG5SetEvent([NSString stringWithFormat:@"Mode2 %@｜完成%llu 跳过%llu 失败%llu/%lu",
                  reason ?: @"已停止", gJCG80Mode2Completed, gJCG80Mode2Skipped, gJCG80Mode2Failed,
                  (unsigned long)gJCG80Mode2Queue.count]);
    JCG5Log([NSString stringWithFormat:@"MODE2 stop reason=%@ completed=%llu skipped=%llu failed=%llu total=%lu",
             reason ?: @"", gJCG80Mode2Completed, gJCG80Mode2Skipped, gJCG80Mode2Failed,
             (unsigned long)gJCG80Mode2Queue.count]);
}

static void JCG80ToggleMode2(void) {
    if (gJCG80Mode2Active) { JCG80Mode2Stop(@"手动停止"); return; }
    JCG80Mode1SetActive(NO);
    JCG80Mode2EnsureDir();
    JCG5ResetDirectory(gJCG80Mode2Dir);
    gJCG80Mode2Active = YES;
    gJCG80Mode2QueueReady = NO; gJCG80Mode2RouterReady = NO;
    gJCG80Mode2WaitingSnapshot = NO; gJCG80Mode2NeedClose = NO;
    gJCG80Mode2TriedNoSelf = NO; gJCG80Mode2CloseTriedNoSelf = NO;
    gJCG80Mode2Index = gJCG80Mode2Completed = gJCG80Mode2Skipped = gJCG80Mode2Failed = 0;
    JCG80Mode2SetString(&gJCG80Mode2RouterSource, @"");
    JCG80Mode2SetString(&gJCG80Mode2RouterModule, @"");
    JCG80Mode2SetString(&gJCG80Mode2OpenFunction, @"");
    JCG80Mode2SetString(&gJCG80Mode2CloseFunction, @"");
    JCG80Mode2SetString(&gJCG80Mode2CurrentUI, @"");
    JCG5SetEvent(@"Mode2 ✅ 已预备｜正常选服进入游戏，进入后自动导航");
    JCG5Log(@"MODE2 v0.8.0-alpha2 armed active-navigation=1 authority=runtime_page_snapshot");
}

static void JCG80Mode2OnSnapshot(NSString *file, NSData *canonicalData, NSString *sessionKey, NSDictionary *entry) {
    if (!gJCG80Mode2Active || !file.length || !canonicalData.length) return;
    JCG80Mode2EnsureDir();
    NSString *dest = [gJCG80Mode2Dir stringByAppendingPathComponent:file.lastPathComponent];
    NSError *err = nil;
    BOOL wrote = [canonicalData writeToFile:dest options:NSDataWritingAtomic error:&err];
    NSData *verify = wrote ? [NSData dataWithContentsOfFile:dest options:NSDataReadingMappedIfSafe error:&err] : nil;
    BOOL exact = wrote && [verify isEqualToData:canonicalData];
    if (!exact) {
        JCG5Log([NSString stringWithFormat:@"MODE2 mirror failed file=%@ error=%@", file.lastPathComponent, err ?: @"byte-compare"]);
        return;
    }
    NSString *entryUI = JCG80Mode2Stem([entry objectForKey:@"page_ui_lua"]);
    NSString *target = gJCG80Mode2CurrentUI ?: @"";
    if (gJCG80Mode2WaitingSnapshot && target.length && [entryUI caseInsensitiveCompare:target] == NSOrderedSame) {
        gJCG80Mode2WaitingSnapshot = NO;
        gJCG80Mode2NeedClose = YES;
        gJCG80Mode2Completed++;
        gJCG80Mode2SnapshotAt = [NSDate timeIntervalSinceReferenceDate];
        JCG5SetEvent([NSString stringWithFormat:@"Mode2 ✅ %llu/%lu %@ snapshot完成｜准备关闭",
                      gJCG80Mode2Index + 1, (unsigned long)gJCG80Mode2Queue.count, target]);
        JCG5Log([NSString stringWithFormat:@"MODE2 snapshot complete index=%llu ui=%@ file=%@ sha256=%@ exact=1",
                 gJCG80Mode2Index, target, file.lastPathComponent, JCG5SHA256(canonicalData)]);
    }
}

static void JCG80Mode2Pump(void *L) {
    if (!gJCG80Mode2Active || !L || !JCG80Mode2ResolveLuaAPI(L)) return;
    if (!JCG80Mode2BuildQueue(L) || !JCG80Mode2DiscoverRouter(L)) {
        JCG5SetEvent([NSString stringWithFormat:@"Mode2 等待游戏UI系统｜ResourcesUI:%@ Router:%@",
                      gJCG80Mode2QueueReady ? @"✅" : @"…", gJCG80Mode2RouterReady ? @"✅" : @"…"]);
        return;
    }
    if (!JCG80Mode2CurrentGameReady()) {
        JCG5SetEvent([NSString stringWithFormat:@"Mode2 已就绪｜安全页%lu｜等待进入游戏主界面",
                      (unsigned long)gJCG80Mode2Queue.count]);
        return;
    }
    if (gJCG80Mode2Index >= gJCG80Mode2Queue.count) { JCG80Mode2Stop(@"✅ 全自动遍历完成"); return; }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSString *target = [gJCG80Mode2Queue objectAtIndex:(NSUInteger)gJCG80Mode2Index];
    if (!gJCG80Mode2CurrentUI.length) JCG80Mode2SetString(&gJCG80Mode2CurrentUI, target);

    if (gJCG80Mode2NeedClose) {
        NSString *err = nil;
        BOOL withSelf = !gJCG80Mode2CloseTriedNoSelf;
        BOOL ok = JCG80Mode2Invoke(L, gJCG80Mode2CloseFunction, gJCG80Mode2CurrentUI, withSelf, &err);
        JCG5Log([NSString stringWithFormat:@"MODE2 close index=%llu ui=%@ fn=%@ self=%d ok=%d error=%@",
                 gJCG80Mode2Index, gJCG80Mode2CurrentUI, gJCG80Mode2CloseFunction, withSelf, ok, err ?: @""]);
        if (ok || gJCG80Mode2CloseTriedNoSelf) {
            JCG80Mode2Advance();
        } else {
            gJCG80Mode2CloseTriedNoSelf = YES;
        }
        return;
    }

    if (gJCG80Mode2WaitingSnapshot) {
        if (now - gJCG80Mode2ActionAt >= JCG80_MODE2_OPEN_TIMEOUT) {
            if (!gJCG80Mode2TriedNoSelf) {
                gJCG80Mode2TriedNoSelf = YES;
                NSString *err = nil;
                BOOL ok = JCG80Mode2Invoke(L, gJCG80Mode2OpenFunction, gJCG80Mode2CurrentUI, NO, &err);
                gJCG80Mode2ActionAt = now;
                JCG5Log([NSString stringWithFormat:@"MODE2 open retry-noself index=%llu ui=%@ fn=%@ ok=%d error=%@",
                         gJCG80Mode2Index, gJCG80Mode2CurrentUI, gJCG80Mode2OpenFunction, ok, err ?: @""]);
            } else {
                gJCG80Mode2Skipped++;
                JCG5Log([NSString stringWithFormat:@"MODE2 timeout no-snapshot index=%llu ui=%@", gJCG80Mode2Index, gJCG80Mode2CurrentUI]);
                gJCG80Mode2NeedClose = YES; gJCG80Mode2WaitingSnapshot = NO;
            }
        }
        return;
    }

    NSString *err = nil;
    BOOL ok = JCG80Mode2Invoke(L, gJCG80Mode2OpenFunction, gJCG80Mode2CurrentUI, YES, &err);
    gJCG80Mode2ActionAt = now;
    if (ok) {
        gJCG80Mode2WaitingSnapshot = YES;
        JCG5SetEvent([NSString stringWithFormat:@"Mode2 ▶️ %llu/%lu 自动打开 %@｜等待snapshot",
                      gJCG80Mode2Index + 1, (unsigned long)gJCG80Mode2Queue.count, gJCG80Mode2CurrentUI]);
        JCG5Log([NSString stringWithFormat:@"MODE2 open index=%llu/%lu ui=%@ fn=%@ module=%@ self=1 ok=1",
                 gJCG80Mode2Index + 1, (unsigned long)gJCG80Mode2Queue.count, gJCG80Mode2CurrentUI,
                 gJCG80Mode2OpenFunction, gJCG80Mode2RouterModule]);
    } else {
        gJCG80Mode2TriedNoSelf = YES;
        BOOL ok2 = JCG80Mode2Invoke(L, gJCG80Mode2OpenFunction, gJCG80Mode2CurrentUI, NO, &err);
        gJCG80Mode2ActionAt = now;
        if (ok2) {
            gJCG80Mode2WaitingSnapshot = YES;
            JCG5Log([NSString stringWithFormat:@"MODE2 open index=%llu ui=%@ fn=%@ self=0 ok=1", gJCG80Mode2Index, gJCG80Mode2CurrentUI, gJCG80Mode2OpenFunction]);
        } else {
            gJCG80Mode2Failed++;
            JCG5Log([NSString stringWithFormat:@"MODE2 open failed index=%llu ui=%@ fn=%@ error=%@", gJCG80Mode2Index, gJCG80Mode2CurrentUI, gJCG80Mode2OpenFunction, err ?: @""]);
            JCG80Mode2Advance();
        }
    }
}

'''

rep(
    "static void JCG70WriteSnapshotNow(NSString *sessionKey) {",
    core + "static void JCG70WriteSnapshotNow(NSString *sessionKey) {",
    "insert Mode2 core before canonical writer",
)

rep(
    "        JCG80Mode1MirrorSnapshot(file, d, sessionKey);\n",
    "        JCG80Mode1MirrorSnapshot(file, d, sessionKey);\n"
    "        JCG80Mode2OnSnapshot(file, d, sessionKey, entry);\n",
    "Mode2 exact canonical snapshot callback",
)

rep(
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha1 Mode1 Exact Mirror"',
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha2 Mode1+Mode2 Auto"',
    "version string",
)
rep(
    't.text=@"JSONCapture v0.8｜Mode1 手动";',
    't.text=@"JSONCapture v0.8｜Mode1手动 / Mode2全自动";',
    "panel title",
)
old_buttons = 'NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))],@[@"Mode1 手动 开/关",NSStringFromSelector(@selector(toggleMode1))]];'
new_buttons = 'NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))],@[@"Mode1 手动 开/关",NSStringFromSelector(@selector(toggleMode1))],@[@"Mode2 全自动 开/关",NSStringFromSelector(@selector(toggleMode2))]];'
rep(old_buttons, new_buttons, "Mode2 toggle button")
rep(
    '- (void)toggleMode1 { JCG80ToggleMode1(); }\n@end',
    '- (void)toggleMode1 { JCG80ToggleMode1(); }\n'
    '- (void)toggleMode2 { JCG80ToggleMode2(); }\n@end',
    "Mode2 controller action",
)
rep(
    'MODE1 exact-byte-mirror canonical=runtime_page_snapshot',
    'MODE1 exact-byte-mirror canonical=runtime_page_snapshot; MODE2 active-navigation router=DlgManager/UIBase snapshot=canonical',
    "binary runtime marker",
)

s += "\n// JCG5_MODE2_AUTO_V080A2 active-router=1 canonical-snapshot=1 no-second-reducer=1\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.0-alpha2 Mode2 active navigation state machine")
