#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
marker = "JCG5_V083_COMPILE_CLEANUP"
if marker in s:
    print("v0.8.3 compile cleanup already applied")
    raise SystemExit(0)
old = "static NSMutableSet *gJCG81Mode2RunPages;\n"
if old not in s:
    raise SystemExit("obsolete Mode2 observed-page set declaration missing")
s = s.replace(old, "", 1)
s += "\n// JCG5_V083_COMPILE_CLEANUP obsolete-observed-page-set=removed\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.3 compile cleanup")
