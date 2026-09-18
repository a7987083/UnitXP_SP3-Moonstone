#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_V080_ALPHA3_RUNTIME_SYNC"
if MARKER in s:
    print("v0.8.0-alpha3 runtime sync already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
    "JCG5_MODE1_EXACT_MIRROR_V080A1",
    "JCG5_MODE2_AUTO_V080A2",
):
    if required not in s:
        raise SystemExit(f"required clean baseline marker missing: {required}")


def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.0-alpha3 anchor missing: {label}")
    s = s.replace(old, new, count)


# ---------------------------------------------------------------------------
# 1) Mode1/Mode2 resync: a duplicate runtime Lua chunk must still be able to
#    mirror the already-existing canonical runtime_page_snapshot file.  This is
#    NOT another reducer: bytes are read directly from runtime_page_snapshot.
# ---------------------------------------------------------------------------
rep(
    "static void JCG60NoteLuaChunk(const char *name) {",
    "static void JCG80CanonicalResyncCurrentContext(void);\n\n"
    "static void JCG60NoteLuaChunk(const char *name) {",
    "canonical resync forward declaration",
)

old_note_tail = '''    if (isTab) { [gJCG60TabLua release]; gJCG60TabLua = [base copy]; gJCG60TabLuaAt = now; }
    if (isUI) { [gJCG60UILua release]; gJCG60UILua = [base copy]; gJCG60UILuaAt = now; }
    pthread_mutex_unlock(&gJCG5StateLock);
}
'''
new_note_tail = '''    if (isTab) { [gJCG60TabLua release]; gJCG60TabLua = [base copy]; gJCG60TabLuaAt = now; }
    if (isUI) { [gJCG60UILua release]; gJCG60UILua = [base copy]; gJCG60UILuaAt = now; }
    pthread_mutex_unlock(&gJCG5StateLock);
    // Page context is updated independently of the loader-cache duplicate path.
    // If Mode1/Mode2 is active, resync an existing canonical snapshot even when
    // RuntimeCapture reports "already captured / skipped" for the Lua bytes.
    if (isUI || isTab) JCG80CanonicalResyncCurrentContext();
}
'''
rep(old_note_tail, new_note_tail, "page-context duplicate-safe resync hook")

old_toggle_mode1 = '''static void JCG80ToggleMode1(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL next = !gJCG80Mode1Active;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG80Mode1SetActive(next);
}
'''
new_toggle_mode1 = '''static void JCG80ToggleMode1(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL next = !gJCG80Mode1Active;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG80Mode1SetActive(next);
    if (next) JCG80CanonicalResyncCurrentContext();
}
'''
rep(old_toggle_mode1, new_toggle_mode1, "Mode1 immediate canonical resync")

# ---------------------------------------------------------------------------
# 2) TAB_ResourcesUI in this game is a standard config-table:
#       key -1 => header array, positive keys => row arrays.
#    alpha2 incorrectly used row.UIName and therefore built an empty queue.
#    Replace only the queue reader; Router/state-machine logic stays intact.
# ---------------------------------------------------------------------------
start = s.find("static BOOL JCG80Mode2BuildQueue(void *L) {")
end = s.find("\nstatic BOOL JCG80Mode2Invoke", start)
if start < 0 or end < 0:
    raise SystemExit("Mode2 BuildQueue boundaries missing")

new_queue = r'''static id JCG80ResourcesValueFromRow(id row, NSDictionary *headerMap, NSString *field) {
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

static NSString *JCG80ResourcesString(id value) {
    if (!value || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return [value description] ?: @"";
}

static BOOL JCG80Mode2BuildQueue(void *L) {
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

    // Pass 1: recover [-1] header -> one-based field index map.
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

    if (!gJCG80Mode2Queue) gJCG80Mode2Queue = [[NSMutableArray alloc] init];
    if (!gJCG80Mode2Seen) gJCG80Mode2Seen = [[NSMutableSet alloc] init];
    [gJCG80Mode2Queue removeAllObjects];
    [gJCG80Mode2Seen removeAllObjects];

    // Pass 2: snapshot each row separately so the 765-row table does not share
    // one global JCG60Snapshot node budget. Supports array rows and dict rows.
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0, candidateRows = 0;
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
            @autoreleasepool {
                id row = JCG60Snapshot(L, -1);
                NSString *ui = JCG80ResourcesString(JCG80ResourcesValueFromRow(row, headerMap, @"UIName"));
                if (ui.length && !JCG80Mode2DangerousUI(ui) && ![gJCG80Mode2Seen containsObject:ui]) {
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
        JCG5Log([NSString stringWithFormat:@"MODE2 queue ready safe=%lu rows=%lu visited=%lu header=%lu source=TAB_ResourcesUI-array",
                 (unsigned long)gJCG80Mode2Queue.count, (unsigned long)candidateRows,
                 (unsigned long)visited, (unsigned long)headerMap.count]);
    } else if (attempts == 1 || attempts % 20 == 0) {
        JCG5Log([NSString stringWithFormat:@"MODE2 queue wait ResourcesUI table=1 rows=%lu header=%lu attempt=%llu",
                 (unsigned long)candidateRows, (unsigned long)headerMap.count, attempts]);
    }
    return gJCG80Mode2QueueReady;
}
'''

s = s[:start] + new_queue + s[end:]

# ---------------------------------------------------------------------------
# 3) Canonical resync implementation. It loads runtime_page_snapshot_index.json,
#    chooses the best UI/TAB match, reads the existing canonical file bytes, and
#    mirrors those bytes. It never parses/merges business data.
# ---------------------------------------------------------------------------
resync_impl = r'''
// JCG5_V080_ALPHA3_RUNTIME_SYNC
static NSString *gJCG80LastResyncMiss = nil;

static BOOL JCG80SameStemName(NSString *a, NSString *b) {
    NSString *sa = JCG80Mode2Stem(a ?: @"");
    NSString *sb = JCG80Mode2Stem(b ?: @"");
    return sa.length && sb.length && [sa caseInsensitiveCompare:sb] == NSOrderedSame;
}

static NSDictionary *JCG80FindCanonicalIndexEntry(NSString *ui, NSString *tab) {
    JCG70EnsureSnapshotPaths();
    NSData *idxData = [NSData dataWithContentsOfFile:gJCG70SnapshotIndexPath options:NSDataReadingMappedIfSafe error:nil];
    if (!idxData.length) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:idxData options:0 error:nil];
    NSArray *pages = [root isKindOfClass:[NSDictionary class]] ? [root objectForKey:@"pages"] : nil;
    if (![pages isKindOfClass:[NSArray class]]) return nil;

    NSDictionary *best = nil;
    NSInteger bestScore = -1;
    for (id raw in pages) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *e = raw;
        NSString *eui = [e objectForKey:@"page_ui_lua"] ?: @"";
        NSString *etab = [e objectForKey:@"page_tab_lua"] ?: @"";
        NSInteger score = 0;
        if (ui.length) {
            if (!JCG80SameStemName(ui, eui)) continue;
            score += 10;
        }
        if (tab.length && JCG80SameStemName(tab, etab)) score += 5;
        if (!ui.length && tab.length) {
            if (!JCG80SameStemName(tab, etab)) continue;
            score += 5;
        }
        if (score > bestScore && [[e objectForKey:@"file"] length]) {
            best = e;
            bestScore = score;
        }
    }
    return best;
}

static void JCG80CanonicalResyncCurrentContext(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL mode1 = gJCG80Mode1Active;
    NSString *ui = [[(gJCG60UILua ?: @"") copy] autorelease];
    NSString *tab = [[(gJCG60TabLua ?: @"") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    BOOL mode2 = gJCG80Mode2Active;
    if ((!mode1 && !mode2) || (!ui.length && !tab.length) || !gJCG5CaptureQueue) return;

    NSString *uiCopy = [ui copy];
    NSString *tabCopy = [tab copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        pthread_mutex_lock(&gJCG5StateLock);
        BOOL m1 = gJCG80Mode1Active;
        pthread_mutex_unlock(&gJCG5StateLock);
        BOOL m2 = gJCG80Mode2Active;
        if (!m1 && !m2) { [uiCopy release]; [tabCopy release]; return; }

        NSDictionary *idx = JCG80FindCanonicalIndexEntry(uiCopy, tabCopy);
        NSString *file = [idx objectForKey:@"file"];
        NSString *session = [idx objectForKey:@"page_session_key"] ?: @"";
        if (!file.length) {
            NSString *miss = [NSString stringWithFormat:@"%@|%@", JCG80Mode2Stem(uiCopy), JCG80Mode2Stem(tabCopy)];
            if (![gJCG80LastResyncMiss isEqualToString:miss]) {
                [gJCG80LastResyncMiss release]; gJCG80LastResyncMiss = [miss copy];
                JCG5Log([NSString stringWithFormat:@"CANONICAL-RESYNC no-match ui=%@ tab=%@", uiCopy, tabCopy]);
            }
            [uiCopy release]; [tabCopy release]; return;
        }

        NSString *srcPath = [gJCG70SnapshotDir stringByAppendingPathComponent:file.lastPathComponent];
        NSData *canonical = [NSData dataWithContentsOfFile:srcPath options:NSDataReadingMappedIfSafe error:nil];
        if (!canonical.length) {
            JCG5Log([NSString stringWithFormat:@"CANONICAL-RESYNC missing-file ui=%@ tab=%@ file=%@", uiCopy, tabCopy, file]);
            [uiCopy release]; [tabCopy release]; return;
        }

        if (m1) JCG80Mode1MirrorSnapshot(file, canonical, session);
        if (m2 && JCG80Mode2CurrentGameReady()) {
            JCG80Mode2EnsureDir();
            NSString *dest = [gJCG80Mode2Dir stringByAppendingPathComponent:file.lastPathComponent];
            NSError *err = nil;
            BOOL wrote = [canonical writeToFile:dest options:NSDataWritingAtomic error:&err];
            NSData *verify = wrote ? [NSData dataWithContentsOfFile:dest options:NSDataReadingMappedIfSafe error:&err] : nil;
            BOOL exact = wrote && [verify isEqualToData:canonical];
            JCG5Log([NSString stringWithFormat:@"MODE2 canonical-resync ui=%@ tab=%@ file=%@ bytes=%lu sha256=%@ exact=%d",
                     uiCopy, tabCopy, file.lastPathComponent, (unsigned long)canonical.length,
                     exact ? JCG5SHA256(canonical) : @"", exact]);
        }
        [uiCopy release]; [tabCopy release];
    }});
}

'''

writer_anchor = "static void JCG70WriteSnapshotNow(NSString *sessionKey) {"
pos = s.find(writer_anchor)
if pos < 0:
    raise SystemExit("canonical writer anchor missing")
s = s[:pos] + resync_impl + s[pos:]

# Add re-entry guard around Mode2 Pump. Opening a UI can itself send network
# messages and recursively hit sendMsg; without this guard the state machine can
# recursively call the router on the same lua_State stack.
rep(
    "static void JCG80Mode2Pump(void *L) {\n    if (!gJCG80Mode2Active || !L || !JCG80Mode2ResolveLuaAPI(L)) return;",
    "static BOOL gJCG80Mode2PumpBusy = NO;\n"
    "static void JCG80Mode2Pump(void *L) {\n"
    "    if (!gJCG80Mode2Active || !L || gJCG80Mode2PumpBusy || !JCG80Mode2ResolveLuaAPI(L)) return;\n"
    "    gJCG80Mode2PumpBusy = YES;",
    "Mode2 pump reentry guard start",
)

# Every return path in Pump would require clearing the guard; wrap the existing
# body in @try/@finally with a mechanical transformation instead of patching each
# return individually.
pump_start = s.find("static BOOL gJCG80Mode2PumpBusy = NO;\nstatic void JCG80Mode2Pump(void *L) {")
pump_end = s.find("\n}\n\n''';", pump_start)
# The generated Objective-C source does not contain the Python raw-string tail;
# find the next function boundary: Mode2 Pump is immediately before JCG70 writer
# after alpha2 core insertion.
if pump_start >= 0:
    body_sig = "    gJCG80Mode2PumpBusy = YES;\n"
    body_pos = s.find(body_sig, pump_start)
    writer_pos = s.find("\nstatic void JCG70WriteSnapshotNow", body_pos)
    if body_pos < 0 or writer_pos < 0:
        raise SystemExit("Mode2 Pump guard boundaries missing")
    # Function closes immediately before writer. Replace the final function brace.
    close_pos = s.rfind("\n}", body_pos, writer_pos)
    if close_pos < 0:
        raise SystemExit("Mode2 Pump closing brace missing")
    s = s[:body_pos + len(body_sig)] + "    @try {\n" + s[body_pos + len(body_sig):close_pos] + "\n    } @finally {\n        gJCG80Mode2PumpBusy = NO;\n    }" + s[close_pos:]

# Version/markers make the tested binary unambiguous.
rep(
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha2 Mode1+Mode2 Auto"',
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha3 Mode1+Mode2 SyncFix"',
    "alpha3 version string",
)
rep(
    't.text=@"JSONCapture v0.8｜Mode1手动 / Mode2全自动";',
    't.text=@"JSONCapture v0.8 alpha3｜Mode1手动 / Mode2全自动";',
    "alpha3 panel title",
)

s += "\n// JCG5_V080_ALPHA3_RUNTIME_SYNC resourcesui=header-array canonical-resync=1 pump-reentry=guarded\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.0-alpha3 ResourcesUI + canonical resync + Mode2 reentry guard")
