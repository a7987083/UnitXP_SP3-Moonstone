#!/usr/bin/env python3
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
MARKER = "JCG5_V080_ALPHA4_COMPILE_FIX"
if MARKER in s:
    print("alpha4 compile fix already applied")
    raise SystemExit(0)
old = '        NSString *session = [idx objectForKey:@"page_session_key"] ?: @"";\n'
if old not in s:
    raise SystemExit("obsolete session local anchor missing")
s = s.replace(old, '', 1)
s += '\n// JCG5_V080_ALPHA4_COMPILE_FIX remove-unused-mode2-resync-session\n'
p.write_text(s, encoding='utf-8')
print('applied alpha4 compile fix')
