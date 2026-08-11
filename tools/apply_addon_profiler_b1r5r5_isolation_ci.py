#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'upstream')
base = Path(__file__).with_name('apply_addon_profiler_b1r5r5_isolation.py')
subprocess.check_call([sys.executable, str(base), str(root)])

p = root / 'addonProfilerLite.cpp'
s = p.read_text(encoding='utf-8', errors='replace')
s = s.replace('AddonProfiler B1R5R5 Light-Isolated', 'AddonProfiler B1R4 Calibrated')
if 'B1R5R5_DEEP_LIGHT_ISOLATION' not in s:
    marker = 'constexpr const char* kVersion = "AddonProfiler B1R4 Calibrated";\n'
    if marker not in s:
        raise SystemExit('B1R4 version marker missing after isolation patch')
    s = s.replace(marker, marker + 'static constexpr const char* kB1R5R5Isolation = "B1R5R5_DEEP_LIGHT_ISOLATION";\n', 1)
p.write_text(s, encoding='utf-8', newline='\n')

check = p.read_text(encoding='utf-8', errors='replace')
assert 'AddonProfiler B1R4 Calibrated' in check
assert 'B1R5R5_DEEP_LIGHT_ISOLATION' in check
assert 'if (!deepIsolation)' in check
assert 'if (deepIsolationActive())' in check
assert 'lua_sethook' not in check
print('B1R5R5 CI isolation marker OK')
