#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_V080_ALPHA3_COMPILE_FIX"
if MARKER in s:
    print("v0.8.0-alpha3 compile fix already applied")
    raise SystemExit(0)
if "JCG5_V080_ALPHA3_RUNTIME_SYNC" not in s:
    raise SystemExit("alpha3 runtime-sync patch missing")

# alpha3's first implementation tried to mechanically surround Mode2 Pump with
# @try/@finally.  The generated boundary accidentally extended across the
# canonical-resync helper functions.  Remove that guard completely here.  The
# core alpha3 fixes (ResourcesUI header-array parser + canonical byte resync)
# remain unchanged.
old_start = '''static BOOL gJCG80Mode2PumpBusy = NO;
static void JCG80Mode2Pump(void *L) {
    if (!gJCG80Mode2Active || !L || gJCG80Mode2PumpBusy || !JCG80Mode2ResolveLuaAPI(L)) return;
    gJCG80Mode2PumpBusy = YES;
    @try {
'''
new_start = '''static void JCG80Mode2Pump(void *L) {
    if (!gJCG80Mode2Active || !L || !JCG80Mode2ResolveLuaAPI(L)) return;
'''
if old_start not in s:
    raise SystemExit("malformed alpha3 pump-guard start not found")
s = s.replace(old_start, new_start, 1)

old_end = '''
    } @finally {
        gJCG80Mode2PumpBusy = NO;
    }
'''
if old_end not in s:
    raise SystemExit("malformed alpha3 pump-guard end not found")
s = s.replace(old_end, "\n", 1)

# Replace the marker claim so CI cannot mistake the removed guard for an active
# invariant.  Re-entry hardening will be reintroduced only with an explicit
# wrapper/body implementation after the functional alpha3 path is verified.
s = s.replace(
    "JCG5_V080_ALPHA3_RUNTIME_SYNC resourcesui=header-array canonical-resync=1 pump-reentry=guarded",
    "JCG5_V080_ALPHA3_RUNTIME_SYNC resourcesui=header-array canonical-resync=1 pump-reentry=deferred",
    1,
)

s += "\n// JCG5_V080_ALPHA3_COMPILE_FIX malformed-pump-guard-removed=1\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.0-alpha3 compile fix: removed malformed pump guard")
