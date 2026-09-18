#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_V080_ALPHA4_MODE1_MODE2_FIX"
if MARKER in s:
    print("v0.8.0-alpha4 Mode1/Mode2 fix already applied")
    raise SystemExit(0)

for required in (
    "JCG5_MODE1_EXACT_MIRROR_V080A1",
    "JCG5_MODE2_AUTO_V080A2",
    "JCG5_V080_ALPHA3_RUNTIME_SYNC",
):
    if required not in s:
        raise SystemExit(f"required clean baseline marker missing: {required}")


def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.0-alpha4 anchor missing: {label}")
    s = s.replace(old, new, count)


# ---------------------------------------------------------------------------
# Mode1: absolute canonical follower.
# - No UI/TAB matching.
# - No duplicate/skip policy.
# - On enable, mirror every existing runtime_page_snapshot JSON byte-for-byte.
# - Future canonical writes are already mirrored by alpha1 callback.
# ---------------------------------------------------------------------------
old_toggle = '''static void JCG80ToggleMode1(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL next = !gJCG80Mode1Active;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG80Mode1SetActive(next);
    if (next) JCG80CanonicalResyncCurrentContext();
}
'''
new_toggle = r'''static void JCG80Mode1MirrorSnapshot(NSString *file, NSData *canonicalData, NSString *sessionKey);

static void JCG80Mode1SyncAllCanonical(void) {
    if (!gJCG5CaptureQueue) return;
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        pthread_mutex_lock(&gJCG5StateLock);
        BOOL active = gJCG80Mode1Active;
        pthread_mutex_unlock(&gJCG5StateLock);
        if (!active) return;

        JCG70EnsureSnapshotPaths();
        JCG80Mode1EnsurePath();
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:gJCG70SnapshotDir error:nil];
        names = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSUInteger total = 0, exact = 0;
        for (NSString *name in names) {
            if (![name.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
            NSString *src = [gJCG70SnapshotDir stringByAppendingPathComponent:name];
            NSData *d = [NSData dataWithContentsOfFile:src options:NSDataReadingMappedIfSafe error:nil];
            if (!d.length) continue;
            total++;
            JCG80Mode1MirrorSnapshot(name, d, @"directory-follow");
            NSString *dst = [gJCG80Mode1Dir stringByAppendingPathComponent:name];
            NSData *verify = [NSData dataWithContentsOfFile:dst options:NSDataReadingMappedIfSafe error:nil];
            if (verify.length == d.length && [verify isEqualToData:d]) exact++;
        }
        JCG5Log([NSString stringWithFormat:@"MODE1 directory-follow sync total=%lu exact=%lu authority=runtime_page_snapshot skip-policy=none",
                 (unsigned long)total, (unsigned long)exact]);
        JCG5SetEvent([NSString stringWithFormat:@"Mode1 ✅ 运行时有什么就同步什么｜现有%lu份，字节一致%lu份",
                      (unsigned long)total, (unsigned long)exact]);
    }});
}

static void JCG80ToggleMode1(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL next = !gJCG80Mode1Active;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG80Mode1SetActive(next);
    if (next) JCG80Mode1SyncAllCanonical();
}
'''
rep(old_toggle, new_toggle, "Mode1 directory follower toggle")

# The alpha3 current-context resync is now Mode2-only. Mode1 never participates
# in page matching; it follows the canonical directory as a whole.
rep(
    '''    BOOL mode1 = gJCG80Mode1Active;
    NSString *ui = [[(gJCG60UILua ?: @"") copy] autorelease];
    NSString *tab = [[(gJCG60TabLua ?: @"") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    BOOL mode2 = gJCG80Mode2Active;
    if ((!mode1 && !mode2) || (!ui.length && !tab.length) || !gJCG5CaptureQueue) return;
''',
    '''    NSString *ui = [[(gJCG60UILua ?: @"") copy] autorelease];
    NSString *tab = [[(gJCG60TabLua ?: @"") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    BOOL mode2 = gJCG80Mode2Active;
    if (!mode2 || (!ui.length && !tab.length) || !gJCG5CaptureQueue) return;
''',
    "Mode1 removed from context resync entry",
)
rep(
    '''        pthread_mutex_lock(&gJCG5StateLock);
        BOOL m1 = gJCG80Mode1Active;
        pthread_mutex_unlock(&gJCG5StateLock);
        BOOL m2 = gJCG80Mode2Active;
        if (!m1 && !m2) { [uiCopy release]; [tabCopy release]; return; }
''',
    '''        BOOL m2 = gJCG80Mode2Active;
        if (!m2) { [uiCopy release]; [tabCopy release]; return; }
''',
    "Mode1 removed from context resync worker",
)
rep(
    '''        if (m1) JCG80Mode1MirrorSnapshot(file, canonical, session);
        if (m2 && JCG80Mode2CurrentGameReady()) {
''',
    '''        if (m2 && JCG80Mode2CurrentGameReady()) {
''',
    "Mode1 no page-match mirror",
)

# ---------------------------------------------------------------------------
# Mode2: read ResourcesUI UIName directly from the live Lua row using rawgeti.
# Static recovery and the device log prove: table=1, rows=765, header=12 and
# UIName is column 1. This avoids JCG60Snapshot row representation ambiguity.
# ---------------------------------------------------------------------------
rep(
    '''typedef int (*JCG80LuaPCallKFn)(void *L, int nargs, int nresults, int errfunc, intptr_t ctx, void *k);
typedef const char *(*JCG80LuaPushLStringFn)(void *L, const char *s, size_t len);
''',
    '''typedef int (*JCG80LuaPCallKFn)(void *L, int nargs, int nresults, int errfunc, intptr_t ctx, void *k);
typedef const char *(*JCG80LuaPushLStringFn)(void *L, const char *s, size_t len);
typedef int (*JCG80LuaRawGetIFn)(void *L, int idx, long long n);
''',
    "Mode2 rawgeti typedef",
)
rep(
    '''static JCG80LuaPCallKFn gJCG80LuaPCallK = NULL;
static JCG80LuaPushLStringFn gJCG80LuaPushLString = NULL;
''',
    '''static JCG80LuaPCallKFn gJCG80LuaPCallK = NULL;
static JCG80LuaPushLStringFn gJCG80LuaPushLString = NULL;
static JCG80LuaRawGetIFn gJCG80LuaRawGetI = NULL;
''',
    "Mode2 rawgeti global",
)
rep(
    '''    gJCG80LuaPCallK = (JCG80LuaPCallKFn)JCG5ResolveExport("lua_pcallk");
    gJCG80LuaPushLString = (JCG80LuaPushLStringFn)JCG5ResolveExport("lua_pushlstring");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 thread=existing-game-lua");
''',
    '''    gJCG80LuaPCallK = (JCG80LuaPCallKFn)JCG5ResolveExport("lua_pcallk");
    gJCG80LuaPushLString = (JCG80LuaPushLStringFn)JCG5ResolveExport("lua_pushlstring");
    gJCG80LuaRawGetI = (JCG80LuaRawGetIFn)JCG5ResolveExport("lua_rawgeti");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString || !gJCG80LuaRawGetI) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 rawgeti=1 thread=existing-game-lua");
''',
    "Mode2 resolve rawgeti",
)

start = s.find("static BOOL JCG80Mode2BuildQueue(void *L) {")
end = s.find("\nstatic BOOL JCG80Mode2Invoke", start)
if start < 0 or end < 0:
    raise SystemExit("alpha4 Mode2 BuildQueue boundaries missing")

new_queue = r'''static BOOL JCG80Mode2BuildQueue(void *L) {
    if (gJCG80Mode2QueueReady) return YES;
    if (!JCG80Mode2ResolveLuaAPI(L)) return NO;
    static unsigned long long attempts = 0;
    attempts++;

    int top = gJCG58LuaGetTop(L);
    if (gJCG58LuaGetGlobal(L, "TAB_ResourcesUI") != JCG60_LUA_TTABLE) {
        gJCG58LuaSetTop(L, top);
        if (attempts == 1 || attempts % 20 == 0)
            JCG5Log([NSString stringWithFormat:@"MODE2 queue wait ResourcesUI table=0 attempt=%llu", attempts]);
        return NO;
    }
    int tableIndex = JCG60AbsIndex(L, -1);

    NSMutableDictionary *headerMap = [NSMutableDictionary dictionary];
    gJCG60LuaPushNil(L);
    while (gJCG60LuaNext(L, tableIndex) != 0) {
        if (gJCG58LuaType(L, -2) == JCG60_LUA_TNUMBER) {
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

    NSInteger uiColumn = [[headerMap objectForKey:@"UIName"] integerValue];
    if (uiColumn <= 0) uiColumn = 1; // verified ResourcesUI schema fallback

    if (!gJCG80Mode2Queue) gJCG80Mode2Queue = [[NSMutableArray alloc] init];
    if (!gJCG80Mode2Seen) gJCG80Mode2Seen = [[NSMutableSet alloc] init];
    [gJCG80Mode2Queue removeAllObjects];
    [gJCG80Mode2Seen removeAllObjects];

    gJCG60LuaPushNil(L);
    NSUInteger visited = 0, candidateRows = 0, uiValues = 0;
    NSString *firstUI = nil;
    while (gJCG60LuaNext(L, tableIndex) != 0 && visited < 2500) {
        visited++;
        BOOL rowCandidate = NO;
        int keyType = gJCG58LuaType(L, -2);
        if (keyType == JCG60_LUA_TNUMBER) {
            int ok = 0;
            long long key = gJCG58LuaToIntegerX ? (long long)gJCG58LuaToIntegerX(L, -2, &ok) : 0;
            rowCandidate = ok && key > 0;
        } else if (keyType == JCG60_LUA_TSTRING) {
            rowCandidate = YES;
        }

        if (rowCandidate && gJCG58LuaType(L, -1) == JCG60_LUA_TTABLE) {
            candidateRows++;
            int rowIndex = JCG60AbsIndex(L, -1);
            gJCG80LuaRawGetI(L, rowIndex, (long long)uiColumn);
            NSString *ui = JCG80Mode2LuaString(L, -1);
            JCG60Pop(L, 1);

            // Fallback only for non-standard runtime variants. It is diagnostic,
            // not the primary path; live numeric Lua access above is authoritative.
            if (!ui.length) {
                id row = JCG60Snapshot(L, -1);
                if ([row isKindOfClass:[NSArray class]]) {
                    NSInteger idx = uiColumn - 1;
                    if (idx >= 0 && idx < (NSInteger)[row count])
                        ui = JCG80ResourcesString([(NSArray *)row objectAtIndex:(NSUInteger)idx]);
                } else if ([row isKindOfClass:[NSDictionary class]]) {
                    id v = [(NSDictionary *)row objectForKey:@"UIName"];
                    if (!v) v = [(NSDictionary *)row objectForKey:[NSString stringWithFormat:@"%ld", (long)uiColumn]];
                    if (!v && uiColumn > 0) v = [(NSDictionary *)row objectForKey:[NSString stringWithFormat:@"%ld", (long)(uiColumn - 1)]];
                    ui = JCG80ResourcesString(v);
                }
            }

            if (ui.length) {
                uiValues++;
                if (!firstUI) firstUI = [ui copy];
                if (!JCG80Mode2DangerousUI(ui) && ![gJCG80Mode2Seen containsObject:ui]) {
                    [gJCG80Mode2Seen addObject:ui];
                    [gJCG80Mode2Queue addObject:ui];
                }
            }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, top);

    [gJCG80Mode2Queue sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    gJCG80Mode2QueueReady = gJCG80Mode2Queue.count > 0;
    if (gJCG80Mode2QueueReady) {
        JCG5Log([NSString stringWithFormat:@"MODE2 queue ready safe=%lu rows=%lu uiValues=%lu visited=%lu header=%lu uiColumn=%ld first=%@ source=TAB_ResourcesUI-live-rawgeti",
                 (unsigned long)gJCG80Mode2Queue.count, (unsigned long)candidateRows,
                 (unsigned long)uiValues, (unsigned long)visited, (unsigned long)headerMap.count,
                 (long)uiColumn, firstUI ?: @""]);
    } else if (attempts == 1 || attempts % 20 == 0) {
        JCG5Log([NSString stringWithFormat:@"MODE2 queue wait ResourcesUI table=1 rows=%lu uiValues=%lu header=%lu uiColumn=%ld keys=%@ attempt=%llu",
                 (unsigned long)candidateRows, (unsigned long)uiValues, (unsigned long)headerMap.count,
                 (long)uiColumn, [[headerMap allKeys] componentsJoinedByString:@","], attempts]);
    }
    [firstUI release];
    return gJCG80Mode2QueueReady;
}
'''
s = s[:start] + new_queue + s[end:]

# Version/markers so CI can prove the effective alpha4 code reached the dylib.
rep(
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha3 Mode1+Mode2 SyncFix"',
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha4 Mode1Follower+Mode2RawUI"',
    "alpha4 version",
)
rep(
    't.text=@"JSONCapture v0.8｜Mode1手动 / Mode2全自动";',
    't.text=@"JSONCapture v0.8｜Mode1实时镜像 / Mode2全自动";',
    "alpha4 panel title",
)
rep(
    'MODE1 exact-byte-mirror canonical=runtime_page_snapshot; MODE2 active-navigation router=DlgManager/UIBase snapshot=canonical',
    'MODE1 canonical-directory-follower skip-policy=none; MODE2 active-navigation resourcesui=live-rawgeti router=DlgManager/UIBase snapshot=canonical',
    "alpha4 runtime marker",
)

s += "\n// JCG5_V080_ALPHA4_MODE1_MODE2_FIX mode1=canonical-directory-follower mode2=resourcesui-live-rawgeti\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.0-alpha4 Mode1 canonical follower + Mode2 live ResourcesUI row access")
