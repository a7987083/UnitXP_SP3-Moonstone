#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
mainp = root / "src" / "ManualTaskEngineV05.m"
recp = root / "src" / "OnDeviceLuaRecovery.m"
m = mainp.read_text(encoding="utf-8")
r = recp.read_text(encoding="utf-8")

MMARK = "JCG5_V080_ALPHA7_SKILL_ROUTER_RECOVERY"
RMARK = "ODLR_V080_ALPHA7_COOPERATIVE_VERIFY"
if MMARK in m and RMARK in r:
    print("alpha7 skill router/recovery already applied")
    raise SystemExit(0)

for required in (
    "JCG5_V080_ALPHA6_NONBLOCKING_RUNTIME",
    "JCG5_V080_ALPHA6_COMPILE_FIX",
    "JCG5_V080_ALPHA5_ROUTER_DISCOVERY",
):
    if required not in m:
        raise SystemExit(f"required alpha6/main marker missing: {required}")
for required in (
    "ODLR_V080_ALPHA6_FAST_RESUME",
    "ODLR_V080_ALPHA6_RECOVERED_JSON_HASHCHECK",
):
    if required not in r:
        raise SystemExit(f"required alpha6/recovery marker missing: {required}")


def rep(text, old, new, label, count=1):
    if old not in text:
        raise SystemExit(f"alpha7 anchor missing: {label}")
    return text.replace(old, new, count)

# ---------------------------------------------------------------------------
# rev-router: module-name affinity must never outrank method semantics.
# The alpha6 device log proved DlgManager.openGuideDlg was a false-positive:
# it always tries to require src.app.beginner.UIBeginnerGuide regardless of UI.
# ---------------------------------------------------------------------------
open_start = m.find('static NSInteger JCG85OpenRank(NSString *name) {')
open_end = m.find('\nstatic NSInteger JCG85CloseRank(NSString *name) {', open_start)
if open_start < 0 or open_end < 0:
    raise SystemExit('alpha7 open-rank boundaries missing')

new_open_rank = r'''static NSMutableSet *gJCG87RejectedOpenNames = nil;
static NSUInteger gJCG87RouterRejectCount = 0;

static BOOL JCG87SpecializedOpenName(NSString *name) {
    NSString *l=name.lowercaseString;
    if (!l.length) return YES;
    NSArray *deny=@[@"guide",@"tutorial",@"beginner",@"newbie",@"reward",@"claim",@"receive",@"purchase",@"recharge",@"pay",@"lottery",@"draw",@"battle",@"fight",@"sdk"];
    for (NSString *x in deny) if ([l containsString:x]) return YES;
    return NO;
}

static NSInteger JCG85OpenRank(NSString *name) {
    NSString *l = name.lowercaseString;
    if (!l.length || JCG87SpecializedOpenName(l) || [gJCG87RejectedOpenNames containsObject:l]) return 9999;
    // Exact generic navigation names are evidence-backed candidates.  Fuzzy
    // business-specific names are intentionally much lower confidence.
    NSArray *exact = @[@"openui",@"showui",@"opendlg",@"showdlg",@"openview",@"showview",@"openpanel",@"showpanel",@"openwindow",@"showwindow",@"pushui",@"pushview",@"open",@"show",@"push",@"loadui",@"createui"];
    NSUInteger i = [exact indexOfObject:l];
    if (i != NSNotFound) return (NSInteger)i;
    BOOL action = [l containsString:@"open"] || [l containsString:@"show"] || [l containsString:@"push"] || [l containsString:@"display"];
    BOOL target = [l containsString:@"ui"] || [l containsString:@"dlg"] || [l containsString:@"dialog"] || [l containsString:@"view"] || [l containsString:@"panel"] || [l containsString:@"window"];
    return action && target ? 1000 : 9999;
}
'''
m = m[:open_start] + new_open_rank + m[open_end:]

# Function semantics dominate module name.  This specifically prevents a fuzzy
# DlgManager method from outranking an exact UIManager/UIBase generic router.
m = rep(
    m,
    'NSInteger score = nameRank * 10000 + ro * 100 + rc;',
    'NSInteger score = ro * 1000000 + rc * 1000 + nameRank;',
    'router scoring semantics-first',
)

# First scan logs all viable module/object pairs so future evidence shows what
# the runtime actually exposed, without invoking any candidate.
m = rep(
    m,
    '''    JCG85InspectRouterTarget(L, targetIndex, &o, &ro, &os, &c, &rc, &cs);
    if (o.length && c.length) {''',
    '''    JCG85InspectRouterTarget(L, targetIndex, &o, &ro, &os, &c, &rc, &cs);
    if (gJCG85RouterScanAttempts == 1 && (o.length || c.length)) {
        JCG5Log([NSString stringWithFormat:@"MODE2 router candidate source=%@ module=%@ object=%@ open=%@[%@]/%ld close=%@[%@]/%ld",
                 source?:@"", module?:@"", objectField?:@"", o?:@"", os?:@"", (long)ro, c?:@"", cs?:@"", (long)rc]);
    }
    if (o.length && c.length) {''',
    'router candidate evidence log',
)

# Reset rejection state on each Mode2 start.
m = rep(
    m,
    'gJCG80Mode2Index = gJCG80Mode2Completed = gJCG80Mode2Skipped = gJCG80Mode2Failed = 0;',
    '''gJCG80Mode2Index = gJCG80Mode2Completed = gJCG80Mode2Skipped = gJCG80Mode2Failed = 0;
    if (!gJCG87RejectedOpenNames) gJCG87RejectedOpenNames=[[NSMutableSet alloc] init];
    [gJCG87RejectedOpenNames removeAllObjects]; gJCG87RouterRejectCount=0;''',
    'reset Mode2 rejected router names',
)

# Helper: a Lua error is runtime evidence that the selected Open function is
# not a generic navigation entry. Reject it and rediscover without advancing
# the target UI. Cap retries to avoid an endless loop on pathological builds.
insert_anchor = 'static void JCG80Mode2Pump(void *L) {'
if insert_anchor not in m:
    raise SystemExit('Mode2 pump anchor missing')
reject_helper = r'''static BOOL JCG87RejectCurrentRouter(NSString *reason) {
    NSString *fn=gJCG80Mode2OpenFunction.lowercaseString;
    if (!fn.length || gJCG87RouterRejectCount >= 12) return NO;
    if (!gJCG87RejectedOpenNames) gJCG87RejectedOpenNames=[[NSMutableSet alloc] init];
    [gJCG87RejectedOpenNames addObject:fn];
    gJCG87RouterRejectCount++;
    JCG5Log([NSString stringWithFormat:@"MODE2 router reject fn=%@ module=%@ reason=%@ reject=%lu/12 action=rediscover-same-ui",
             gJCG80Mode2OpenFunction?:@"",gJCG80Mode2RouterModule?:@"",reason?:@"",(unsigned long)gJCG87RouterRejectCount]);
    gJCG80Mode2RouterReady=NO;
    gJCG80Mode2WaitingSnapshot=NO;
    gJCG80Mode2NeedClose=NO;
    gJCG80Mode2TriedNoSelf=NO;
    gJCG80Mode2CloseTriedNoSelf=NO;
    JCG80Mode2SetString(&gJCG80Mode2OpenFunction,@"");
    JCG80Mode2SetString(&gJCG80Mode2CloseFunction,@"");
    JCG80Mode2SetString(&gJCG80Mode2RouterSource,@"");
    JCG80Mode2SetString(&gJCG80Mode2RouterModule,@"");
    JCG80Mode2SetString(&gJCG85RouterObjectField,@"");
    JCG80Mode2SetString(&gJCG85RouterOpenSource,@"");
    JCG80Mode2SetString(&gJCG85RouterCloseSource,@"");
    return YES;
}

'''
m = m.replace(insert_anchor, reject_helper + insert_anchor, 1)

old_fail = '''        } else {
            gJCG80Mode2Failed++;
            JCG5Log([NSString stringWithFormat:@"MODE2 open failed index=%llu ui=%@ fn=%@ error=%@", gJCG80Mode2Index, gJCG80Mode2CurrentUI, gJCG80Mode2OpenFunction, err ?: @""]);
            JCG80Mode2Advance();
        }
'''
new_fail = '''        } else {
            NSString *failedFn=[[gJCG80Mode2OpenFunction copy] autorelease];
            NSString *failedModule=[[gJCG80Mode2RouterModule copy] autorelease];
            JCG5Log([NSString stringWithFormat:@"MODE2 open failed index=%llu ui=%@ fn=%@ module=%@ error=%@", gJCG80Mode2Index, gJCG80Mode2CurrentUI, failedFn?:@"", failedModule?:@"", err ?: @""]);
            if (JCG87RejectCurrentRouter(err ?: @"pcall-failed")) return;
            gJCG80Mode2Failed++;
            JCG80Mode2Advance();
        }
'''
m = rep(m, old_fail, new_fail, 'adaptive router rejection')

# Runtime identity / visible marker.
m = rep(
    m,
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha6 NonBlocking+FastResume"',
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha7 RouterSemantic+RecoveryContinuous"',
    'alpha7 version',
)
m = rep(
    m,
    'MODE2ROUTER=alpha6-bounded-raw-exact; RECOVERYSHA=journal-v1-fast-resume; MODE2PUMP=parseMsg-post-only',
    'MODE2ROUTER=alpha7-semantic-adaptive; RECOVERYSHA=journal-v1-continuous; MODE2PUMP=parseMsg-post-only',
    'alpha7 load marker',
)

# ---------------------------------------------------------------------------
# rev-struct/recovery: static JSON recovery must not be cancelled merely because
# runtime capture occurs. It does not touch the game lua_State or Unity bundle
# objects. Local scan/decrypt still remain preemptible.
# ---------------------------------------------------------------------------
m = rep(
    m,
    'if(gJCG5Task!=JCG5TaskIdle){gJCG5Cancel=YES;gJCG5PendingTask=JCG5TaskIdle;gJCG5PendingRetry=NO;gJCG5PreemptedByCapture=YES;preempt=YES;}',
    'if(gJCG5Task!=JCG5TaskIdle && gJCG5Task!=JCG5TaskRecover){gJCG5Cancel=YES;gJCG5PendingTask=JCG5TaskIdle;gJCG5PendingRetry=NO;gJCG5PreemptedByCapture=YES;preempt=YES;}',
    'do not preempt static recovery on runtime capture',
)

# Run manual file work at Utility QoS so a long first recovery cannot starve
# the game/render/network threads. Queue count remains unchanged.
m = rep(
    m,
    'gJCG5CaptureQueue=dispatch_queue_create("com.openai.jsoncapture.v05.capture",DISPATCH_QUEUE_SERIAL);gJCG5TaskQueue=dispatch_queue_create("com.openai.jsoncapture.v05.manualtask",DISPATCH_QUEUE_SERIAL);',
    '''gJCG5CaptureQueue=dispatch_queue_create("com.openai.jsoncapture.v05.capture",DISPATCH_QUEUE_SERIAL);
        dispatch_queue_attr_t taskAttr=dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0);
        gJCG5TaskQueue=dispatch_queue_create("com.openai.jsoncapture.v05.manualtask",taskAttr);''',
    'manual task utility QoS',
)

# Cooperative SHA verification: still hash the actual recovered_json bytes, but
# periodically yield CPU/IO after verified files. This changes no integrity rule.
validator_start = r.find('// ODLR_V080_ALPHA6_RECOVERED_JSON_HASHCHECK')
if validator_start < 0:
    raise SystemExit('alpha7 recovery validator marker missing')
loop_old = '''    for (NSDictionary *rec in records) {
        NSString *expectedSHA=[rec[@"sha256"] isKindOfClass:[NSString class]]?rec[@"sha256"]:@"";
        NSString *stored=[rec[@"path"] isKindOfClass:[NSString class]]?rec[@"path"]:@"";
        if (expectedSHA.length!=64 || !stored.length) return NO;

        // Recovery FILE records are expected to point at recovered_json/*.json
        // for complete output.  Keep recorded relative-path support so partial
        // output remains verifiable too.
        NSString *path=ODLRStoredOutputPath(stored,outputRoot);
        NSString *actual=ODLRFileSHA256(path);
        if (actual.length!=64 || ![actual isEqualToString:expectedSHA]) return NO;
    }
'''
loop_new = '''    static unsigned long long sAlpha7VerifiedFiles=0;
    for (NSDictionary *rec in records) {@autoreleasepool {
        NSString *expectedSHA=[rec[@"sha256"] isKindOfClass:[NSString class]]?rec[@"sha256"]:@"";
        NSString *stored=[rec[@"path"] isKindOfClass:[NSString class]]?rec[@"path"]:@"";
        if (expectedSHA.length!=64 || !stored.length) return NO;

        // Always hash the actual recovered_json/recorded file; yielding only
        // lowers contention and never weakens the SHA-256 integrity check.
        NSString *path=ODLRStoredOutputPath(stored,outputRoot);
        NSString *actual=ODLRFileSHA256(path);
        if (actual.length!=64 || ![actual isEqualToString:expectedSHA]) return NO;
        sAlpha7VerifiedFiles++;
        if ((sAlpha7VerifiedFiles % 4ULL)==0) usleep(750);
    }}
'''
if loop_old not in r:
    raise SystemExit('alpha7 recovered_json hash loop anchor missing')
r = r.replace(loop_old, loop_new, 1)
r += '\n// ODLR_V080_ALPHA7_COOPERATIVE_VERIFY actual-recovered-json-sha256 qos=cooperative\n'

m += '\n// JCG5_V080_ALPHA7_SKILL_ROUTER_RECOVERY router=semantic-adaptive recovery=uninterrupted-utility-qos\n'
mainp.write_text(m, encoding='utf-8')
recp.write_text(r, encoding='utf-8')
print('applied alpha7 semantic/adaptive Router + uninterrupted cooperative recovery')
