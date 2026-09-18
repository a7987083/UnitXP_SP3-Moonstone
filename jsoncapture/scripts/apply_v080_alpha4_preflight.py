#!/usr/bin/env python3
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
if "JCG5_V080_ALPHA4_MODE1_MODE2_FIX" in s:
    print("alpha4 preflight already satisfied")
    raise SystemExit(0)
old = 't.text=@"JSONCapture v0.8 alpha3｜Mode1手动 / Mode2全自动";'
new = 't.text=@"JSONCapture v0.8｜Mode1手动 / Mode2全自动";'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit("alpha4 preflight panel-title anchor missing")
p.write_text(s, encoding="utf-8")
print("alpha4 preflight normalized panel title anchor")
