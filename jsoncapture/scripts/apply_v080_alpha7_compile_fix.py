#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
MARKER = "JCG5_V080_ALPHA7_COMPILE_FIX"
if MARKER in s:
    print("alpha7 compile fix already applied")
    raise SystemExit(0)
if "JCG5_V080_ALPHA7_SKILL_ROUTER_RECOVERY" not in s:
    raise SystemExit("alpha7 skill router/recovery marker missing")

proto = "static BOOL JCG87RejectCurrentRouter(NSString *reason);\n"
if proto not in s:
    anchor = "static void JCG80Mode2Pump(void *L);\n"
    if anchor not in s:
        raise SystemExit("Mode2 forward-declaration anchor missing")
    s = s.replace(anchor, proto + anchor, 1)

s += "\n// JCG5_V080_ALPHA7_COMPILE_FIX router-reject-forward-declaration\n"
p.write_text(s, encoding="utf-8")
print("applied alpha7 compile fix")
