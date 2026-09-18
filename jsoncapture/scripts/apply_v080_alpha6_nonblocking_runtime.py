#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
mainp = root / "src" / "ManualTaskEngineV05.m"
recp = root / "src" / "OnDeviceLuaRecovery.m"
m = mainp.read_text(encoding="utf-8")
r = recp.read_text(encoding="utf-8")

MMARK = "JCG5_V080_ALPHA6_NONBLOCKING_RUNTIME"
RMARK = "ODLR_V080_ALPHA6_FAST_RESUME"
if MMARK in m and RMARK in r:
    print("alpha6 nonblocking runtime already applied")
    raise SystemExit(0)
for required in (
    "JCG5_V080_ALPHA5_ROUTER_DISCOVERY",
    "JCG5_V080_ALPHA5_RECOVERY_SHA256_RESUME",
    "JCG5_V080_ALPHA5_IDENTITY",
    "JCG5_V080_ALPHA5_COMPILE_FIX",
):
    if required not in m:
        raise SystemExit(f"required alpha5 marker missing: {required}")
if "ODLR_V080_ALPHA5_SHA256_RESUME" not in r:
    raise SystemExit("alpha5 recovery marker missing")


def rep(text, old, new, label, count=1):
    if old not in text:
        raise SystemExit(f"alpha6 anchor missing: {label}")
    return text.replace(old, new, count)

# ---------------------------------------------------------------------------
# Mode2 / lang-lua + rev-router fix
# ---------------------------------------------------------------------------
# Discovery must never invoke __index or scan thousands of keys synchronously
# on the game's Lua/network callback. Resolve lua_rawget and use raw table
# access for discovery/invocation.
m = rep(
    m,
    'typedef int (*JCG85LuaGetMetatableFn)(void *L, int objindex);',
    'typedef int (*JCG85LuaGetMetatableFn)(void *L, int objindex);\ntypedef int (*JCG86LuaRawGetFn)(void *L, int idx);',
    'lua_rawget typedef',
)
m = rep(
    m,
    'static JCG85LuaGetMetatableFn gJCG85LuaGetMetatable = NULL;',
    '''static JCG85LuaGetMetatableFn gJCG85LuaGetMetatable = NULL;
static JCG86LuaRawGetFn gJCG86LuaRawGet = NULL;
static BOOL gJCG86Mode2PumpBusy = NO;
static NSTimeInterval gJCG86Mode2LastPumpAt = 0;
static NSTimeInterval gJCG86Mode2LastWaitingEventAt = 0;''',
    'alpha6 runtime globals',
)
m = rep(
    m,
    '''    gJCG80LuaRawGetI = (JCG80LuaRawGetIFn)JCG5ResolveExport("lua_rawgeti");
    gJCG85LuaGetMetatable = (JCG85LuaGetMetatableFn)JCG5ResolveExport("lua_getmetatable");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString || !gJCG80LuaRawGetI || !gJCG85LuaGetMetatable) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 rawgeti=1 getmetatable=1 thread=existing-game-lua");''',
    '''    gJCG80LuaRawGetI = (JCG80LuaRawGetIFn)JCG5ResolveExport("lua_rawgeti");
    gJCG85LuaGetMetatable = (JCG85LuaGetMetatableFn)JCG5ResolveExport("lua_getmetatable");
    gJCG86LuaRawGet = (JCG86LuaRawGetFn)JCG5ResolveExport("lua_rawget");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString || !gJCG80LuaRawGetI || !gJCG85LuaGetMetatable || !gJCG86LuaRawGet) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 rawgeti=1 rawget=1 getmetatable=1 thread=existing-game-lua");''',
    'resolve rawget',
)

# Replace alpha5 router-discovery implementation with a bounded exact lookup.
# No _G enumeration, no package.loaded enumeration, and no metamethod-triggering
# lua_getfield on candidate objects.
start = m.find('#define JCG85_LUA_TUSERDATA 7')
end = m.find('\nstatic BOOL JCG80Mode2BuildQueue(void *L) {', start)
if start < 0 or end < 0:
    raise SystemExit('alpha6 router section boundaries missing')

router = r'''#define JCG85_LUA_TUSERDATA 7

static BOOL JCG85RouterValueType(int t) {
    return t == JCG60_LUA_TTABLE || t == JCG85_LUA_TUSERDATA;
}

static int JCG86RawGetField(void *L, int idx, NSString *key) {
    if (!L || !key.length || !gJCG86LuaRawGet || !gJCG80LuaPushLString) return 0;
    int abs = JCG60AbsIndex(L, idx);
    NSData *d = [key dataUsingEncoding:NSUTF8StringEncoding];
    gJCG80LuaPushLString(L, d.bytes, d.length);
    return gJCG86LuaRawGet(L, abs);
}

static NSInteger JCG85RouterNameRank(NSString *name) {
    NSString *l = name.lowercaseString;
    if (!l.length) return 9999;
    if ([l hasSuffix:@"dlgmanager"] || [l isEqualToString:@"dlgmanager"]) return 0;
    if ([l hasSuffix:@"uibase"] || [l isEqualToString:@"uibase"]) return 2;
    if ([l hasSuffix:@"dialogmanager"] || [l isEqualToString:@"dialogmanager"]) return 4;
    if ([l hasSuffix:@"uimanager"] || [l isEqualToString:@"uimanager"]) return 6;
    return 9999;
}

static NSInteger JCG85OpenRank(NSString *name) {
    NSString *l = name.lowercaseString;
    NSArray *exact = @[@"openui",@"showui",@"opendlg",@"showdlg",@"openview",@"showview",@"openpanel",@"showpanel",@"openwindow",@"showwindow",@"pushui",@"pushview",@"open",@"show",@"push",@"loadui",@"createui"];
    NSUInteger i = [exact indexOfObject:l];
    if (i != NSNotFound) return (NSInteger)i;
    BOOL action = [l containsString:@"open"] || [l containsString:@"show"] || [l containsString:@"push"] || [l containsString:@"display"];
    BOOL target = [l containsString:@"ui"] || [l containsString:@"dlg"] || [l containsString:@"dialog"] || [l containsString:@"view"] || [l containsString:@"panel"] || [l containsString:@"window"];
    return action && target ? 100 : 9999;
}

static NSInteger JCG85CloseRank(NSString *name) {
    NSString *l = name.lowercaseString;
    NSArray *exact = @[@"closeui",@"hideui",@"closedlg",@"hidedlg",@"closeview",@"hideview",@"closepanel",@"hidepanel",@"closewindow",@"hidewindow",@"popui",@"popview",@"removeui",@"destroyui",@"close",@"hide",@"pop",@"back"];
    NSUInteger i = [exact indexOfObject:l];
    if (i != NSNotFound) return (NSInteger)i;
    BOOL action = [l containsString:@"close"] || [l containsString:@"hide"] || [l containsString:@"pop"] || [l containsString:@"remove"] || [l containsString:@"back"];
    BOOL target = [l containsString:@"ui"] || [l containsString:@"dlg"] || [l containsString:@"dialog"] || [l containsString:@"view"] || [l containsString:@"panel"] || [l containsString:@"window"];
    return action && target ? 100 : 9999;
}

static void JCG85InspectFunctionTable(void *L, int tableIndex, NSString *methodSource,
                                      NSString **bestOpen, NSInteger *bestOpenRank, NSString **bestOpenSource,
                                      NSString **bestClose, NSInteger *bestCloseRank, NSString **bestCloseSource) {
    if (!L || gJCG58LuaType(L, tableIndex) != JCG60_LUA_TTABLE) return;
    int abs = JCG60AbsIndex(L, tableIndex), top = gJCG58LuaGetTop(L);
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0;
    while (gJCG60LuaNext(L, abs) != 0 && visited++ < 256) {
        NSString *key = JCG80Mode2LuaString(L, -2);
        if (key.length && gJCG58LuaType(L, -1) == JCG60_LUA_TFUNCTION) {
            NSInteger ro = JCG85OpenRank(key), rc = JCG85CloseRank(key);
            if (ro < *bestOpenRank) { *bestOpenRank = ro; JCG80Mode2SetString(bestOpen, key); JCG80Mode2SetString(bestOpenSource, methodSource); }
            if (rc < *bestCloseRank) { *bestCloseRank = rc; JCG80Mode2SetString(bestClose, key); JCG80Mode2SetString(bestCloseSource, methodSource); }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, top);
}

static void JCG85InspectRouterTarget(void *L, int targetIndex,
                                     NSString **bestOpen, NSInteger *bestOpenRank, NSString **bestOpenSource,
                                     NSString **bestClose, NSInteger *bestCloseRank, NSString **bestCloseSource) {
    int target = JCG60AbsIndex(L, targetIndex), targetType = gJCG58LuaType(L, target);
    if (!JCG85RouterValueType(targetType)) return;
    int top = gJCG58LuaGetTop(L);
    if (targetType == JCG60_LUA_TTABLE)
        JCG85InspectFunctionTable(L, target, @"target", bestOpen, bestOpenRank, bestOpenSource, bestClose, bestCloseRank, bestCloseSource);
    gJCG58LuaSetTop(L, top);
    if (gJCG85LuaGetMetatable(L, target)) {
        int meta = JCG60AbsIndex(L, -1);
        JCG85InspectFunctionTable(L, meta, @"metatable", bestOpen, bestOpenRank, bestOpenSource, bestClose, bestCloseRank, bestCloseSource);
        int mtTop = gJCG58LuaGetTop(L);
        if (JCG86RawGetField(L, meta, @"__index") == JCG60_LUA_TTABLE)
            JCG85InspectFunctionTable(L, -1, @"index", bestOpen, bestOpenRank, bestOpenSource, bestClose, bestCloseRank, bestCloseSource);
        gJCG58LuaSetTop(L, mtTop);
    }
    gJCG58LuaSetTop(L, top);
}

static void JCG85ConsiderRouterTarget(void *L, int targetIndex, NSString *source, NSString *module, NSString *objectField,
                                      NSInteger nameRank, NSInteger *bestScore,
                                      NSString **bestSource, NSString **bestModule, NSString **bestObjectField,
                                      NSString **bestOpen, NSString **bestOpenSource,
                                      NSString **bestClose, NSString **bestCloseSource) {
    NSString *o=nil,*c=nil,*os=nil,*cs=nil; NSInteger ro=9999,rc=9999;
    JCG85InspectRouterTarget(L, targetIndex, &o, &ro, &os, &c, &rc, &cs);
    if (o.length && c.length) {
        NSInteger score = nameRank * 10000 + ro * 100 + rc;
        if (score < *bestScore) {
            *bestScore = score;
            JCG80Mode2SetString(bestSource, source); JCG80Mode2SetString(bestModule, module); JCG80Mode2SetString(bestObjectField, objectField ?: @"");
            JCG80Mode2SetString(bestOpen, o); JCG80Mode2SetString(bestOpenSource, os);
            JCG80Mode2SetString(bestClose, c); JCG80Mode2SetString(bestCloseSource, cs);
        }
    }
    [o release]; [c release]; [os release]; [cs release];
}

static void JCG85ConsiderModuleAtTop(void *L, NSString *source, NSString *module, NSInteger nameRank,
                                     NSInteger *bestScore,
                                     NSString **bestSource, NSString **bestModule, NSString **bestObjectField,
                                     NSString **bestOpen, NSString **bestOpenSource,
                                     NSString **bestClose, NSString **bestCloseSource) {
    if (!L || !JCG85RouterValueType(gJCG58LuaType(L,-1))) return;
    int target=JCG60AbsIndex(L,-1);
    JCG85ConsiderRouterTarget(L,target,source,module,@"",nameRank,bestScore,bestSource,bestModule,bestObjectField,bestOpen,bestOpenSource,bestClose,bestCloseSource);
    if (gJCG58LuaType(L,target) != JCG60_LUA_TTABLE) return;
    NSArray *fields=@[@"instance",@"Instance",@"_instance",@"sharedInstance",@"SharedInstance",@"singleton",@"Singleton",@"shared",@"default"];
    int top=gJCG58LuaGetTop(L);
    for (NSString *field in fields) {
        gJCG58LuaSetTop(L,top);
        int t=JCG86RawGetField(L,target,field);
        if (JCG85RouterValueType(t))
            JCG85ConsiderRouterTarget(L,-1,source,module,field,nameRank+1,bestScore,bestSource,bestModule,bestObjectField,bestOpen,bestOpenSource,bestClose,bestCloseSource);
    }
    gJCG58LuaSetTop(L,top);
}

static BOOL JCG80Mode2PushModuleTable(void *L, NSString *source, NSString *module) {
    if (!L || !source.length || !module.length) return NO;
    int top=gJCG58LuaGetTop(L), t=0;
    if ([source isEqualToString:@"global"]) {
        t=gJCG58LuaGetGlobal(L,module.UTF8String);
    } else {
        if (gJCG58LuaGetGlobal(L,"package") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L,top); return NO; }
        int pkg=JCG60AbsIndex(L,-1);
        if (JCG86RawGetField(L,pkg,@"loaded") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L,top); return NO; }
        int loaded=JCG60AbsIndex(L,-1);
        t=JCG86RawGetField(L,loaded,module);
    }
    if (!JCG85RouterValueType(t)) { gJCG58LuaSetTop(L,top); return NO; }
    if (gJCG85RouterObjectField.length) {
        int parent=JCG60AbsIndex(L,-1);
        int ot=JCG86RawGetField(L,parent,gJCG85RouterObjectField);
        if (!JCG85RouterValueType(ot)) { gJCG58LuaSetTop(L,top); return NO; }
    }
    return YES;
}

static BOOL JCG85PushRouterFunction(void *L, int targetIndex, NSString *functionName, NSString *methodSource) {
    int target=JCG60AbsIndex(L,targetIndex);
    if ([methodSource isEqualToString:@"target"])
        return JCG86RawGetField(L,target,functionName) == JCG60_LUA_TFUNCTION;
    if (!gJCG85LuaGetMetatable(L,target)) return NO;
    int meta=JCG60AbsIndex(L,-1);
    if ([methodSource isEqualToString:@"metatable"])
        return JCG86RawGetField(L,meta,functionName) == JCG60_LUA_TFUNCTION;
    if ([methodSource isEqualToString:@"index"] && JCG86RawGetField(L,meta,@"__index") == JCG60_LUA_TTABLE) {
        int idx=JCG60AbsIndex(L,-1);
        return JCG86RawGetField(L,idx,functionName) == JCG60_LUA_TFUNCTION;
    }
    return NO;
}

static void JCG86TryRouterCandidate(void *L, NSString *source, NSString *module, NSInteger rank,
                                    NSInteger *bestScore, NSString **bs, NSString **bm, NSString **bf,
                                    NSString **bo, NSString **bos, NSString **bc, NSString **bcs,
                                    NSUInteger *candidates) {
    int top=gJCG58LuaGetTop(L);
    BOOL pushed=JCG80Mode2PushModuleTable(L,source,module);
    if (pushed) {
        (*candidates)++;
        JCG85ConsiderModuleAtTop(L,source,module,rank,bestScore,bs,bm,bf,bo,bos,bc,bcs);
    }
    gJCG58LuaSetTop(L,top);
}

static BOOL JCG80Mode2DiscoverRouter(void *L) {
    if (gJCG80Mode2RouterReady) return YES;
    if (!JCG80Mode2ResolveLuaAPI(L)) return NO;
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    static NSTimeInterval lastScanAt=0;
    if (lastScanAt>0 && now-lastScanAt<0.50) return NO;
    lastScanAt=now;
    gJCG85RouterScanAttempts++;

    int rootTop=gJCG58LuaGetTop(L); NSInteger bestScore=NSIntegerMax; NSUInteger candidates=0;
    NSString *bs=nil,*bm=nil,*bf=nil,*bo=nil,*bos=nil,*bc=nil,*bcs=nil;

    NSArray *globals=@[@"DlgManager",@"UIBase",@"DialogManager",@"UIManager"];
    for (NSString *module in globals)
        JCG86TryRouterCandidate(L,@"global",module,JCG85RouterNameRank(module),&bestScore,&bs,&bm,&bf,&bo,&bos,&bc,&bcs,&candidates);

    NSArray *packages=@[
        @"DlgManager",@"UIBase",@"DialogManager",@"UIManager",
        @"src.utils.DlgManager",@"src.utils.UIBase",
        @"src/utils/DlgManager",@"src/utils/UIBase",
        @"src/utils/DlgManager.lua",@"src/utils/UIBase.lua",
        @"@src/utils/DlgManager.lua",@"@src/utils/UIBase.lua"
    ];
    for (NSString *module in packages) {
        NSString *leaf=[module.lastPathComponent stringByDeletingPathExtension];
        NSInteger rank=JCG85RouterNameRank(leaf.length?leaf:module);
        JCG86TryRouterCandidate(L,@"package",module,rank,&bestScore,&bs,&bm,&bf,&bo,&bos,&bc,&bcs,&candidates);
    }
    gJCG58LuaSetTop(L,rootTop);

    if (bo.length && bc.length && bm.length && bs.length) {
        JCG80Mode2SetString(&gJCG80Mode2RouterSource,bs); JCG80Mode2SetString(&gJCG80Mode2RouterModule,bm);
        JCG80Mode2SetString(&gJCG85RouterObjectField,bf); JCG80Mode2SetString(&gJCG80Mode2OpenFunction,bo); JCG80Mode2SetString(&gJCG85RouterOpenSource,bos);
        JCG80Mode2SetString(&gJCG80Mode2CloseFunction,bc); JCG80Mode2SetString(&gJCG85RouterCloseSource,bcs);
        gJCG80Mode2RouterReady=YES;
        JCG5Log([NSString stringWithFormat:@"MODE2 router ready source=%@ module=%@ object=%@ open=%@[%@] close=%@[%@] candidates=%lu discovery=alpha6-bounded-raw-exact",
                 bs,bm,bf?:@"",bo,bos?:@"",bc,bcs?:@"",(unsigned long)candidates]);
    } else if (gJCG85RouterScanAttempts==1 || gJCG85RouterScanAttempts%10==0) {
        JCG5Log([NSString stringWithFormat:@"MODE2 router wait attempt=%llu exactCandidates=%lu bestModule=%@ bestOpen=%@ bestClose=%@ discovery=alpha6-bounded-raw-exact",
                 gJCG85RouterScanAttempts,(unsigned long)candidates,bm?:@"",bo?:@"",bc?:@""]);
    }
    [bs release];[bm release];[bf release];[bo release];[bos release];[bc release];[bcs release];
    return gJCG80Mode2RouterReady;
}
'''
m = m[:start] + router + m[end:]

# Mode2 must not run on sendMsg (user input) at all. Advance only after the
# original parseMsg has returned/capture completed, preserving game input.
m = rep(
    m,
    '''static int JCG60SendMsgWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;
    JCG80Mode2Pump(L);''',
    '''static int JCG60SendMsgWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;''',
    'remove Mode2 from sendMsg input path',
)
m = rep(
    m,
    '''static int JCG60ParseMsgWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;
    JCG80Mode2Pump(L);''',
    '''static int JCG60ParseMsgWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;''',
    'remove pre-parse Mode2 pump',
)
m = rep(
    m,
    '''    [raw release];
    return 2;
}''',
    '''    [raw release];
    JCG80Mode2Pump(L); // alpha6: post-parse only; never blocks user sendMsg input
    return 2;
}''',
    'post-parse Mode2 pump',
)

# Wrap the state machine in a correct re-entry guard. OpenUI may itself cause a
# send/parse callback; nested Mode2 pump must be a no-op.
pump_start = m.find('static void JCG80Mode2Pump(void *L) {')
writer_start = m.find('\nstatic void JCG70WriteSnapshotNow(NSString *sessionKey) {', pump_start)
if pump_start < 0 or writer_start < 0:
    raise SystemExit('Mode2 pump boundaries missing')
pump = m[pump_start:writer_start]
pump = pump.replace('static void JCG80Mode2Pump(void *L) {', 'static void JCG86Mode2PumpInner(void *L) {', 1)
old_wait = '''    if (!JCG80Mode2BuildQueue(L) || !JCG80Mode2DiscoverRouter(L)) {
        JCG5SetEvent([NSString stringWithFormat:@"Mode2 等待游戏UI系统｜ResourcesUI:%@ Router:%@",
                      gJCG80Mode2QueueReady ? @"✅" : @"…", gJCG80Mode2RouterReady ? @"✅" : @"…"]);
        return;
    }'''
new_wait = '''    if (!JCG80Mode2BuildQueue(L) || !JCG80Mode2DiscoverRouter(L)) {
        NSTimeInterval waitNow=[NSDate timeIntervalSinceReferenceDate];
        if (waitNow-gJCG86Mode2LastWaitingEventAt>=1.0) {
            gJCG86Mode2LastWaitingEventAt=waitNow;
            JCG5SetEvent([NSString stringWithFormat:@"Mode2 等待游戏UI系统｜ResourcesUI:%@ Router:%@",
                          gJCG80Mode2QueueReady ? @"✅" : @"…", gJCG80Mode2RouterReady ? @"✅" : @"…"]);
        }
        return;
    }'''
if old_wait not in pump:
    raise SystemExit('Mode2 wait block missing in pump')
pump = pump.replace(old_wait,new_wait,1)
wrapper = pump + r'''

static void JCG80Mode2Pump(void *L) {
    if (!gJCG80Mode2Active || !L || gJCG86Mode2PumpBusy) return;
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if (gJCG86Mode2LastPumpAt>0 && now-gJCG86Mode2LastPumpAt<0.20) return;
    gJCG86Mode2LastPumpAt=now;
    gJCG86Mode2PumpBusy=YES;
    @try { JCG86Mode2PumpInner(L); }
    @finally { gJCG86Mode2PumpBusy=NO; }
}
'''
m = m[:pump_start] + wrapper + m[writer_start:]

# Reset alpha6 scheduling state when Mode2 is armed.
m = rep(
    m,
    '''    gJCG85RouterScanAttempts = 0;
    JCG80Mode2SetString(&gJCG80Mode2CurrentUI, @"");''',
    '''    gJCG85RouterScanAttempts = 0;
    gJCG86Mode2PumpBusy = NO;
    gJCG86Mode2LastPumpAt = 0;
    gJCG86Mode2LastWaitingEventAt = 0;
    JCG80Mode2SetString(&gJCG80Mode2CurrentUI, @"");''',
    'reset alpha6 pump state',
)

# ---------------------------------------------------------------------------
# Recovery fast resume fix
# ---------------------------------------------------------------------------
# The SHA256 journal remains authoritative and user-readable. On later runs we
# do NOT reread every output file to recompute SHA256. A committed group with
# the same source signature is accepted when all recorded output files exist.
# SHA256 is calculated when the file is originally produced and stays in TXT.
rv_start = r.find('static BOOL ODLRValidateManifestEntry(NSDictionary *entry, NSString *outputRoot) {')
rv_end = r.find('\nstatic NSArray *ODLROutputRecordsForResult(', rv_start)
if rv_start < 0 or rv_end < 0:
    raise SystemExit('recovery manifest validator boundaries missing')
fast_validator = r'''// ODLR_V080_ALPHA6_FAST_RESUME
// Fast journal validation: source signature + committed manifest + output
// existence. Do not re-hash every recovered JSON on each app launch.
static BOOL ODLRValidateManifestEntry(NSDictionary *entry, NSString *outputRoot) {
    if (![entry[@"committed"] boolValue]) return NO;
    NSArray *records=ODLRManifestRecords(entry); NSInteger expected=[entry[@"expected"] integerValue];
    if ((NSInteger)records.count!=expected) return NO;
    if (expected==0) return YES;
    NSFileManager *fm=[NSFileManager defaultManager];
    for (NSDictionary *rec in records) {
        NSString *expectedSHA=rec[@"sha256"],*path=ODLRStoredOutputPath(rec[@"path"],outputRoot);
        BOOL isDir=NO;
        if (expectedSHA.length!=64 || ![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) return NO;
    }
    return YES;
}
'''
r = r[:rv_start] + fast_validator + r[rv_end:]

# Throttle skip UI updates. Alpha5 posted 2479 JCG5SetEvent updates during a
# no-op resume, flooding the main queue even though recovery finished in ~2s.
old_skip = '''            }else if([stage isEqualToString:@"recover_skip"]){
                unsigned long long skipped=[event[@"skipped_verified"] unsignedLongLongValue];
                JCG5SetEvent([NSString stringWithFormat:@"SHA256 已验证，跳过 %llu｜%@",skipped,g]);
                if(skipped<=5 || skipped%100==0) JCG5Log([NSString stringWithFormat:@"RECOVERY skip verified group=%@ skipped=%llu outputs=%@ status=%@",g,skipped,event[@"outputs"]?:@0,event[@"status"]?:@"unknown"]);
            }'''
new_skip = '''            }else if([stage isEqualToString:@"recover_skip"]){
                unsigned long long skipped=[event[@"skipped_verified"] unsignedLongLongValue];
                if(skipped<=3 || skipped%250==0 || skipped==total)
                    JCG5SetEvent([NSString stringWithFormat:@"SHA256清单命中，跳过 %llu/%llu｜%@",skipped,total,g]);
                if(skipped<=3 || skipped%250==0 || skipped==total)
                    JCG5Log([NSString stringWithFormat:@"RECOVERY skip journal-hit group=%@ skipped=%llu/%llu outputs=%@ status=%@",g,skipped,total,event[@"outputs"]?:@0,event[@"status"]?:@"unknown"]);
            }'''
m = rep(m, old_skip, new_skip, 'throttle recovery skip UI')

m = rep(
    m,
    'JCG5FinishTask(stopped?@"JSON恢复已停止":[NSString stringWithFormat:@"JSON恢复完成｜本次恢复%llu组｜SHA256跳过%llu组",attempted,skipped]);',
    'JCG5FinishTask(stopped?@"JSON恢复已停止":[NSString stringWithFormat:@"JSON恢复完成｜本次恢复%llu组｜SHA256清单跳过%llu组",attempted,skipped]);',
    'alpha6 recovery finish wording',
)

# Version / binary identity.
m = rep(
    m,
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha5 Router+SHA256Resume"',
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha6 NonBlocking+FastResume"',
    'alpha6 version',
)
m = rep(
    m,
    't.text=@"JSONCapture v0.8 alpha5｜Mode1实时镜像 / Mode2全自动";',
    't.text=@"JSONCapture v0.8 alpha6｜Mode1实时镜像 / Mode2全自动";',
    'alpha6 panel title',
)
m = rep(
    m,
    'MODE2ROUTER=alpha5-metatable-index; RECOVERYSHA=journal-v1-resume',
    'MODE2ROUTER=alpha6-bounded-raw-exact; RECOVERYSHA=journal-v1-fast-resume; MODE2PUMP=parseMsg-post-only',
    'alpha6 runtime marker',
)
m += '\n// JCG5_V080_ALPHA6_NONBLOCKING_RUNTIME mode2=parse-post-only bounded-raw-exact recovery=journal-fast\n'
r += '\n// ODLR_V080_ALPHA6_FAST_RESUME committed-journal+existence no-repeat-output-rehash\n'

mainp.write_text(m,encoding='utf-8')
recp.write_text(r,encoding='utf-8')
print('applied alpha6 nonblocking Mode2 + fast SHA256 resume')
