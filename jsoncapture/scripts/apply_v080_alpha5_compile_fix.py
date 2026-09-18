#!/usr/bin/env python3
from pathlib import Path
p=Path(__file__).resolve().parents[1]/"src"/"ManualTaskEngineV05.m"
s=p.read_text(encoding="utf-8")
MARKER="JCG5_V080_ALPHA5_COMPILE_FIX"
if MARKER in s:
    print("alpha5 compile fix already applied")
    raise SystemExit(0)
if "JCG5_V080_ALPHA5_ROUTER_DISCOVERY" not in s:
    raise SystemExit("alpha5 router marker missing")
anchor='static BOOL JCG80Mode2BuildQueue(void *L) {'
if anchor not in s:
    raise SystemExit("Mode2 BuildQueue anchor missing")
helper='''static NSString *JCG85ResourcesString(id v) {\n    if ([v isKindOfClass:[NSString class]]) return v;\n    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];\n    return @"";\n}\n\n'''
s=s.replace(anchor,helper+anchor,1)
s=s.replace('JCG80ResourcesString(', 'JCG85ResourcesString(')
s+='\n// JCG5_V080_ALPHA5_COMPILE_FIX restore-resources-string-helper\n'
p.write_text(s,encoding='utf-8')
print('applied alpha5 compile fix')
