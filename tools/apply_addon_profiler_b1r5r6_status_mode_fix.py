#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(sys.argv[1] if len(sys.argv) > 1 else 'upstream')
p = root / 'addonProfilerLite.cpp'
s = p.read_text(encoding='utf-8')
old='pushStringField(L,"mode","LIGHT_ENTRY_WRAPPER");'
new='pushStringField(L,"mode","LIGHT_ENTRY_WRAPPER_B1R5R6_LONGFRAME_CONTRIBUTION");'
if s.count(old) != 1:
    raise SystemExit('B1R5R6 status mode: expected one old status mode')
p.write_text(s.replace(old,new,1),encoding='utf-8')
print('B1R5R6 status mode unified')
