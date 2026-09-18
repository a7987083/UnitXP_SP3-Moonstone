#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
MARKER = "JCG5_V080_ALPHA5_ROUTER_DISCOVERY"
if MARKER in s:
    print("alpha5 router discovery already applied")
    raise SystemExit(0)
for required in ("JCG5_V080_ALPHA4_MODE1_MODE2_FIX", "JCG5_V080_ALPHA4_STABILITY"):
    if required not in s:
        raise SystemExit(f"required alpha4 marker missing: {required}")

def replace_once(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f"alpha5 router anchor missing: {label}")
    s = s.replace(old, new, 1)

# Resolve Lua metatables in addition to the already verified rawgeti API.
replace_once(
    'typedef int (*JCG80LuaRawGetIFn)(void *L, int idx, long long n);',
    'typedef int (*JCG80LuaRawGetIFn)(void *L, int idx, long long n);\ntypedef int (*JCG85LuaGetMetatableFn)(void *L, int objindex);',
    'lua_getmetatable typedef')
replace_once(
    'static JCG80LuaRawGetIFn gJCG80LuaRawGetI = NULL;',
    '''static JCG80LuaRawGetIFn gJCG80LuaRawGetI = NULL;
static JCG85LuaGetMetatableFn gJCG85LuaGetMetatable = NULL;
static NSString *gJCG85RouterObjectField = nil;
static NSString *gJCG85RouterOpenSource = nil;   // target | metatable | index
static NSString *gJCG85RouterCloseSource = nil;  // target | metatable | index
static unsigned long long gJCG85RouterScanAttempts = 0;''',
    'router discovery globals')
replace_once(
    '''    gJCG80LuaRawGetI = (JCG80LuaRawGetIFn)JCG5ResolveExport("lua_rawgeti");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString || !gJCG80LuaRawGetI) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 rawgeti=1 thread=existing-game-lua");''',
    '''    gJCG80LuaRawGetI = (JCG80LuaRawGetIFn)JCG5ResolveExport("lua_rawgeti");
    gJCG85LuaGetMetatable = (JCG85LuaGetMetatableFn)JCG5ResolveExport("lua_getmetatable");
    if (!gJCG80LuaPCallK || !gJCG80LuaPushLString || !gJCG80LuaRawGetI || !gJCG85LuaGetMetatable) return NO;
    gJCG80Mode2LuaAPIReady = YES;
    JCG5Log(@"MODE2 Lua API ready pcallk=1 pushlstring=1 rawgeti=1 getmetatable=1 thread=existing-game-lua");''',
    'resolve lua_getmetatable')

# Replace the old router target / discovery section.  The real game ships
# DlgManager.lua and UIBase.lua, but they need not expose methods directly on a
# plain table.  Inspect direct tables, userdata metatables and __index tables,
# including common singleton fields, without executing any discovery method.
start = s.find('static BOOL JCG80Mode2PushModuleTable(void *L, NSString *source, NSString *module) {')
end = s.find('\nstatic BOOL JCG80Mode2BuildQueue(void *L) {', start)
if start < 0 or end < 0:
    raise SystemExit('router discovery section boundaries missing')

router = r'''#define JCG85_LUA_TUSERDATA 7

static BOOL JCG85RouterValueType(int t) {
    return t == JCG60_LUA_TTABLE || t == JCG85_LUA_TUSERDATA;
}

static NSInteger JCG85RouterNameRank(NSString *name) {
    NSString *l = name.lowercaseString;
    if (!l.length) return 9999;
    if ([l hasSuffix:@"dlgmanager"] || [l isEqualToString:@"dlgmanager"]) return 0;
    if ([l hasSuffix:@"uibase"] || [l isEqualToString:@"uibase"]) return 2;
    if ([l hasSuffix:@"dialogmanager"] || [l isEqualToString:@"dialogmanager"]) return 4;
    if ([l hasSuffix:@"uimanager"] || [l isEqualToString:@"uimanager"]) return 6;
    BOOL managerish = [l containsString:@"manager"] || [l containsString:@"router"] || [l containsString:@"navigator"];
    BOOL uiish = [l containsString:@"ui"] || [l containsString:@"dlg"] || [l containsString:@"dialog"] || [l containsString:@"view"] || [l containsString:@"window"] || [l containsString:@"panel"];
    if (managerish && uiish) return 50;
    if ([l containsString:@"dlg"] && [l containsString:@"base"]) return 60;
    if ([l containsString:@"ui"] && [l containsString:@"base"]) return 65;
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
    int abs = JCG60AbsIndex(L, tableIndex);
    int top = gJCG58LuaGetTop(L);
    gJCG60LuaPushNil(L);
    NSUInteger visited = 0;
    while (gJCG60LuaNext(L, abs) != 0 && visited++ < 1024) {
        NSString *key = JCG80Mode2LuaString(L, -2);
        if (key.length && gJCG58LuaType(L, -1) == JCG60_LUA_TFUNCTION) {
            NSInteger ro = JCG85OpenRank(key), rc = JCG85CloseRank(key);
            if (ro < *bestOpenRank) {
                *bestOpenRank = ro; JCG80Mode2SetString(bestOpen, key); JCG80Mode2SetString(bestOpenSource, methodSource);
            }
            if (rc < *bestCloseRank) {
                *bestCloseRank = rc; JCG80Mode2SetString(bestClose, key); JCG80Mode2SetString(bestCloseSource, methodSource);
            }
        }
        JCG60Pop(L, 1);
    }
    gJCG58LuaSetTop(L, top);
}

static void JCG85InspectRouterTarget(void *L, int targetIndex,
                                     NSString **bestOpen, NSInteger *bestOpenRank, NSString **bestOpenSource,
                                     NSString **bestClose, NSInteger *bestCloseRank, NSString **bestCloseSource) {
    int target = JCG60AbsIndex(L, targetIndex);
    int targetType = gJCG58LuaType(L, target);
    if (!JCG85RouterValueType(targetType)) return;
    int top = gJCG58LuaGetTop(L);
    if (targetType == JCG60_LUA_TTABLE)
        JCG85InspectFunctionTable(L, target, @"target", bestOpen, bestOpenRank, bestOpenSource, bestClose, bestCloseRank, bestCloseSource);
    gJCG58LuaSetTop(L, top);
    if (gJCG85LuaGetMetatable(L, target)) {
        int meta = JCG60AbsIndex(L, -1);
        JCG85InspectFunctionTable(L, meta, @"metatable", bestOpen, bestOpenRank, bestOpenSource, bestClose, bestCloseRank, bestCloseSource);
        int mtTop = gJCG58LuaGetTop(L);
        if (gJCG60LuaGetField(L, meta, "__index") == JCG60_LUA_TTABLE) {
            JCG85InspectFunctionTable(L, -1, @"index", bestOpen, bestOpenRank, bestOpenSource, bestClose, bestCloseRank, bestCloseSource);
        }
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
    int target = JCG60AbsIndex(L,-1);
    JCG85ConsiderRouterTarget(L,target,source,module,@"",nameRank,bestScore,bestSource,bestModule,bestObjectField,bestOpen,bestOpenSource,bestClose,bestCloseSource);
    if (gJCG58LuaType(L,target) != JCG60_LUA_TTABLE) return;
    NSArray *fields=@[@"instance",@"Instance",@"_instance",@"sharedInstance",@"SharedInstance",@"singleton",@"Singleton"];
    int top=gJCG58LuaGetTop(L);
    for (NSString *field in fields) {
        gJCG58LuaSetTop(L,top);
        int t=gJCG60LuaGetField(L,target,field.UTF8String);
        if (JCG85RouterValueType(t))
            JCG85ConsiderRouterTarget(L,-1,source,module,field,nameRank+1,bestScore,bestSource,bestModule,bestObjectField,bestOpen,bestOpenSource,bestClose,bestCloseSource);
    }
    gJCG58LuaSetTop(L,top);
}

static BOOL JCG80Mode2PushModuleTable(void *L, NSString *source, NSString *module) {
    if (!L || !source.length || !module.length) return NO;
    int top = gJCG58LuaGetTop(L);
    int t = 0;
    if ([source isEqualToString:@"global"]) {
        t = gJCG58LuaGetGlobal(L, module.UTF8String);
    } else {
        if (gJCG58LuaGetGlobal(L, "package") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L,top); return NO; }
        int pkg=JCG60AbsIndex(L,-1);
        if (gJCG60LuaGetField(L,pkg,"loaded") != JCG60_LUA_TTABLE) { gJCG58LuaSetTop(L,top); return NO; }
        int loaded=JCG60AbsIndex(L,-1);
        t=gJCG60LuaGetField(L,loaded,module.UTF8String);
    }
    if (!JCG85RouterValueType(t)) { gJCG58LuaSetTop(L,top); return NO; }
    if (gJCG85RouterObjectField.length) {
        int parent=JCG60AbsIndex(L,-1);
        int ot=gJCG60LuaGetField(L,parent,gJCG85RouterObjectField.UTF8String);
        if (!JCG85RouterValueType(ot)) { gJCG58LuaSetTop(L,top); return NO; }
    }
    return YES;
}

static BOOL JCG85PushRouterFunction(void *L, int targetIndex, NSString *functionName, NSString *methodSource) {
    int target=JCG60AbsIndex(L,targetIndex);
    if ([methodSource isEqualToString:@"target"]) return gJCG60LuaGetField(L,target,functionName.UTF8String) == JCG60_LUA_TFUNCTION;
    if (!gJCG85LuaGetMetatable(L,target)) return NO;
    int meta=JCG60AbsIndex(L,-1);
    if ([methodSource isEqualToString:@"metatable"]) return gJCG60LuaGetField(L,meta,functionName.UTF8String) == JCG60_LUA_TFUNCTION;
    if ([methodSource isEqualToString:@"index"] && gJCG60LuaGetField(L,meta,"__index") == JCG60_LUA_TTABLE) {
        int idx=JCG60AbsIndex(L,-1);
        return gJCG60LuaGetField(L,idx,functionName.UTF8String) == JCG60_LUA_TFUNCTION;
    }
    return NO;
}

static BOOL JCG80Mode2DiscoverRouter(void *L) {
    if (gJCG80Mode2RouterReady) return YES;
    if (!JCG80Mode2ResolveLuaAPI(L)) return NO;
    gJCG85RouterScanAttempts++;
    int rootTop=gJCG58LuaGetTop(L); NSInteger bestScore=NSIntegerMax; NSUInteger candidates=0;
    NSString *bs=nil,*bm=nil,*bf=nil,*bo=nil,*bos=nil,*bc=nil,*bcs=nil;

    NSArray *priority=@[@"DlgManager",@"UIBase",@"DialogManager",@"UIManager"];
    for (NSString *module in priority) {
        gJCG58LuaSetTop(L,rootTop); int t=gJCG58LuaGetGlobal(L,module.UTF8String);
        if (JCG85RouterValueType(t)) { candidates++; JCG85ConsiderModuleAtTop(L,@"global",module,JCG85RouterNameRank(module),&bestScore,&bs,&bm,&bf,&bo,&bos,&bc,&bcs); }
    }

    gJCG58LuaSetTop(L,rootTop);
    if (gJCG58LuaGetGlobal(L,"_G") == JCG60_LUA_TTABLE) {
        int globals=JCG60AbsIndex(L,-1); gJCG60LuaPushNil(L); NSUInteger visited=0;
        while (gJCG60LuaNext(L,globals) != 0 && visited++ < 4096) {
            NSString *module=JCG80Mode2LuaString(L,-2); NSInteger rank=JCG85RouterNameRank(module);
            if (rank < 9999 && JCG85RouterValueType(gJCG58LuaType(L,-1))) { candidates++; JCG85ConsiderModuleAtTop(L,@"global",module,rank,&bestScore,&bs,&bm,&bf,&bo,&bos,&bc,&bcs); }
            JCG60Pop(L,1);
        }
    }

    gJCG58LuaSetTop(L,rootTop);
    if (gJCG58LuaGetGlobal(L,"package") == JCG60_LUA_TTABLE) {
        int pkg=JCG60AbsIndex(L,-1);
        if (gJCG60LuaGetField(L,pkg,"loaded") == JCG60_LUA_TTABLE) {
            int loaded=JCG60AbsIndex(L,-1); gJCG60LuaPushNil(L); NSUInteger visited=0;
            while (gJCG60LuaNext(L,loaded) != 0 && visited++ < 8192) {
                NSString *module=JCG80Mode2LuaString(L,-2); NSInteger rank=JCG85RouterNameRank(module);
                if (rank < 9999 && JCG85RouterValueType(gJCG58LuaType(L,-1))) { candidates++; JCG85ConsiderModuleAtTop(L,@"package",module,rank,&bestScore,&bs,&bm,&bf,&bo,&bos,&bc,&bcs); }
                JCG60Pop(L,1);
            }
        }
    }
    gJCG58LuaSetTop(L,rootTop);

    if (bo.length && bc.length && bm.length && bs.length) {
        JCG80Mode2SetString(&gJCG80Mode2RouterSource,bs); JCG80Mode2SetString(&gJCG80Mode2RouterModule,bm);
        JCG80Mode2SetString(&gJCG85RouterObjectField,bf); JCG80Mode2SetString(&gJCG80Mode2OpenFunction,bo); JCG80Mode2SetString(&gJCG85RouterOpenSource,bos);
        JCG80Mode2SetString(&gJCG80Mode2CloseFunction,bc); JCG80Mode2SetString(&gJCG85RouterCloseSource,bcs);
        gJCG80Mode2RouterReady=YES;
        JCG5Log([NSString stringWithFormat:@"MODE2 router ready source=%@ module=%@ object=%@ open=%@[%@] close=%@[%@] candidates=%lu discovery=alpha5-metatable-index",
                 bs,bm,bf?:@"",bo,bos?:@"",bc,bcs?:@"",(unsigned long)candidates]);
    } else if (gJCG85RouterScanAttempts==1 || gJCG85RouterScanAttempts%20==0) {
        JCG5Log([NSString stringWithFormat:@"MODE2 router scan wait attempt=%llu candidates=%lu bestModule=%@ bestOpen=%@ bestClose=%@ discovery=alpha5-metatable-index",
                 gJCG85RouterScanAttempts,(unsigned long)candidates,bm?:@"",bo?:@"",bc?:@""]);
    }
    [bs release];[bm release];[bf release];[bo release];[bos release];[bc release];[bcs release];
    return gJCG80Mode2RouterReady;
}
'''
s = s[:start] + router + s[end:]

# Invocation must fetch inherited methods from the exact location found above,
# while passing the actual target object as self.  Discovery itself executes no
# game/business function.
start = s.find('static BOOL JCG80Mode2Invoke(void *L, NSString *functionName, NSString *ui, BOOL withSelf, NSString **errorOut) {')
end = s.find('\nstatic BOOL JCG80Mode2CurrentGameReady(void) {', start)
if start < 0 or end < 0:
    raise SystemExit('Mode2 invoke boundaries missing')
invoke = r'''static BOOL JCG80Mode2Invoke(void *L, NSString *functionName, NSString *ui, BOOL withSelf, NSString **errorOut) {
    if (errorOut) *errorOut=nil;
    if (!L || !functionName.length || !gJCG80Mode2RouterReady || !JCG80Mode2ResolveLuaAPI(L)) return NO;
    int top=gJCG58LuaGetTop(L);
    if (!JCG80Mode2PushModuleTable(L,gJCG80Mode2RouterSource,gJCG80Mode2RouterModule)) { gJCG58LuaSetTop(L,top); return NO; }
    int target=JCG60AbsIndex(L,-1);
    NSString *methodSource=[functionName isEqualToString:gJCG80Mode2OpenFunction] ? gJCG85RouterOpenSource : gJCG85RouterCloseSource;
    if (!JCG85PushRouterFunction(L,target,functionName,methodSource)) { gJCG58LuaSetTop(L,top); return NO; }
    int nargs=0;
    if (withSelf) { gJCG58LuaPushValue(L,target); nargs++; }
    if (ui.length) { NSData *u=[ui dataUsingEncoding:NSUTF8StringEncoding]; gJCG80LuaPushLString(L,u.bytes,u.length); nargs++; }
    int status=gJCG80LuaPCallK(L,nargs,0,0,(intptr_t)0,NULL);
    if (status!=0 && errorOut) {
        NSString *err=JCG80Mode2LuaString(L,-1);
        *errorOut=[[(err.length?err:[NSString stringWithFormat:@"lua_pcall status=%d",status]) copy] autorelease];
    }
    gJCG58LuaSetTop(L,top);
    return status==0;
}
'''
s = s[:start] + invoke + s[end:]

# Clear alpha5 router state whenever Mode2 is newly armed.
replace_once(
    '''    JCG80Mode2SetString(&gJCG80Mode2CloseFunction, @"");
    JCG80Mode2SetString(&gJCG80Mode2CurrentUI, @"");''',
    '''    JCG80Mode2SetString(&gJCG80Mode2CloseFunction, @"");
    JCG80Mode2SetString(&gJCG85RouterObjectField, @"");
    JCG80Mode2SetString(&gJCG85RouterOpenSource, @"");
    JCG80Mode2SetString(&gJCG85RouterCloseSource, @"");
    gJCG85RouterScanAttempts = 0;
    JCG80Mode2SetString(&gJCG80Mode2CurrentUI, @"");''',
    'reset alpha5 router state')

# Runtime marker must survive into the dylib for CI/binary inspection.
replace_once(
    'RECOVERY=memsafe-g5',
    'RECOVERY=memsafe-g5; MODE2ROUTER=alpha5-metatable-index',
    'alpha5 binary marker')
s += '\n// JCG5_V080_ALPHA5_ROUTER_DISCOVERY direct+metatable+index+singleton global+package scan\n'
p.write_text(s, encoding='utf-8')
print('applied alpha5 Mode2 router discovery')
