#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
MARKER = "JCG5_V080_ALPHA6_COMPILE_FIX"
if MARKER in s:
    print("alpha6 compile fix already applied")
    raise SystemExit(0)
if "JCG5_V080_ALPHA6_NONBLOCKING_RUNTIME" not in s:
    raise SystemExit("alpha6 runtime marker missing")
anchor = 'static BOOL JCG80Mode2BuildQueue(void *L) {'
if anchor not in s:
    raise SystemExit("Mode2 BuildQueue anchor missing")
if 'static NSString *JCG85ResourcesString(id v)' not in s:
    helper = '''static NSString *JCG85ResourcesString(id v) {\n    if ([v isKindOfClass:[NSString class]]) return v;\n    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];\n    return @"";\n}\n\n'''
    s = s.replace(anchor, helper + anchor, 1)
s += '\n// JCG5_V080_ALPHA6_COMPILE_FIX restore-resources-helper-after-router-rewrite\n'
p.write_text(s, encoding='utf-8')
print('applied alpha6 compile fix')
