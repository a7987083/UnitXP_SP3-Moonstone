#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit('usage: apply_addon_profiler_b1r5_deep_merge.py <final_b1r4_tree> <clean_tree> <b1r2_tree>')

final = Path(sys.argv[1])
clean = Path(sys.argv[2])  # kept for workflow compatibility / provenance
b1r2 = Path(sys.argv[3])
for p in (final, clean, b1r2):
    if not p.is_dir():
        raise SystemExit('missing tree: %s' % p)

# B1R5R3 rule: the normal B1R4 light profiler MUST already be fully integrated
# by apply_addon_profiler_b1r3_lite.py + apply_addon_profiler_b1r4_calibrated.py.
# Deep profiling is added beside it; never reconstruct or replace the light command.
required = [
    final / 'addonProfilerLite.cpp',
    final / 'addonProfilerLite.h',
    final / 'dllmain.cpp',
    final / 'sceneBegin_sceneEnd.cpp',
    final / 'Makefile',
]
for p in required:
    if not p.exists():
        raise SystemExit('missing integrated B1R4 file: %s' % p)

# Verify the known-good light command exists before touching anything.
dll_path = final / 'dllmain.cpp'
dll = dll_path.read_text(encoding='utf-8-sig', errors='replace')
light_cmd = '        else if (cmd == "profiler") {\n            return addonProfilerLite::handleLua(L);\n        }\n'
if light_cmd not in dll:
    raise SystemExit('B1R4 light profiler command is not integrated; run B1R3 lite integration first')
if '#include "addonProfilerLite.h"' not in dll:
    raise SystemExit('B1R4 light profiler header include missing')

# Copy the tested B1R2 CALL/RET engine, but isolate it in its own namespace.
src_cpp = b1r2 / 'addonProfiler.cpp'
src_h = b1r2 / 'addonProfiler.h'
if not src_cpp.exists() or not src_h.exists():
    raise SystemExit('B1R2 profiler source not found')

cpp = src_cpp.read_text(encoding='utf-8', errors='replace')
hdr = src_h.read_text(encoding='utf-8', errors='replace')

def transform_deep(s):
    s = s.replace('addonProfiler.h', 'addonProfilerDeep.h')
    # Lower-case C++ namespace is the important isolation boundary.
    s = s.replace('namespace addonProfiler {', 'namespace addonProfilerDeep {')
    s = s.replace('} // namespace addonProfiler', '} // namespace addonProfilerDeep')
    # Human-readable build ID only; do not blindly rewrite ordinary identifiers.
    s = s.replace('AddonProfiler B1R2', 'AddonProfiler Deep B1R5R3')
    s = s.replace('AddonProfiler B1R1', 'AddonProfiler Deep B1R5R3')
    s = s.replace('AddonProfiler B1', 'AddonProfiler Deep B1R5R3')
    return s

cpp = transform_deep(cpp)
hdr = transform_deep(hdr)
if 'namespace addonProfilerDeep' not in cpp or 'namespace addonProfilerDeep' not in hdr:
    raise SystemExit('deep namespace transform failed')
if 'lua_sethook' not in cpp:
    raise SystemExit('wrong B1R2 deep source: lua_sethook missing')
(final / 'addonProfilerDeep.cpp').write_text(cpp, encoding='utf-8', newline='\n')
(final / 'addonProfilerDeep.h').write_text(hdr, encoding='utf-8', newline='\n')

# Deterministic dllmain integration. Keep BOTH command namespaces.
dll = dll_path.read_text(encoding='utf-8-sig', errors='replace')
if '#include "addonProfilerDeep.h"' not in dll:
    marker = '#include "addonProfilerLite.h"\n'
    if marker not in dll:
        raise SystemExit('cannot place deep header include')
    dll = dll.replace(marker, marker + '#include "addonProfilerDeep.h"\n', 1)

deep_cmd = '        else if (cmd == "profilerdeep") {\n            return addonProfilerDeep::handleLua(L);\n        }\n'
if 'cmd == "profilerdeep"' not in dll:
    if light_cmd not in dll:
        raise SystemExit('cannot place profilerdeep beside profiler command')
    dll = dll.replace(light_cmd, deep_cmd + light_cmd, 1)

# Hard safety: never ship a DLL source tree that lost the light command.
if 'cmd == "profiler"' not in dll or 'addonProfilerLite::handleLua(L)' not in dll:
    raise SystemExit('light profiler command was lost during deep integration')
if 'cmd == "profilerdeep"' not in dll or 'addonProfilerDeep::handleLua(L)' not in dll:
    raise SystemExit('deep profiler command integration failed')
dll_path.write_text(dll, encoding='utf-8', newline='\n')

# Deep B1R2 statistics need frame boundaries to roll 1-second windows and peaks.
# The function is an immediate no-op while deep mode is OFF, so no debug hook is active.
scene_path = final / 'sceneBegin_sceneEnd.cpp'
scene = scene_path.read_text(encoding='utf-8-sig', errors='replace')
if '#include "addonProfilerDeep.h"' not in scene:
    marker = '#include "addonProfilerLite.h"\n'
    if marker not in scene:
        raise SystemExit('cannot place deep scene header include')
    scene = scene.replace(marker, marker + '#include "addonProfilerDeep.h"\n', 1)
if 'addonProfilerDeep::onFrameBoundary();' not in scene:
    marker = '    addonProfilerLite::onFrameBoundary();\n'
    if marker not in scene:
        raise SystemExit('B1R4 light frame boundary call missing')
    scene = scene.replace(marker, marker + '    addonProfilerDeep::onFrameBoundary();\n', 1)
scene_path.write_text(scene, encoding='utf-8', newline='\n')

# Deterministic Makefile integration: B1R3 already placed lite in SRCS.
mk_path = final / 'Makefile'
mk = mk_path.read_text(encoding='utf-8-sig', errors='replace')
deep_line = '            addonProfilerDeep.cpp \\\n'
if 'addonProfilerDeep.cpp' not in mk:
    lite_line = '            addonProfilerLite.cpp \\\n'
    if lite_line not in mk:
        raise SystemExit('B1R4 lite source is not inside Makefile SRCS')
    mk = mk.replace(lite_line, lite_line + deep_line, 1)
if mk.count('addonProfilerLite.cpp') != 1 or mk.count('addonProfilerDeep.cpp') != 1:
    raise SystemExit('profiler Makefile source count invalid')
mk_path.write_text(mk, encoding='utf-8', newline='\n')

# Final source assertions.
light = (final / 'addonProfilerLite.cpp').read_text(encoding='utf-8', errors='replace')
if 'lua_sethook' in light or 'LUA_MASKCALL' in light:
    raise SystemExit('light profiler unexpectedly contains debug hook')
final_dll = dll_path.read_text(encoding='utf-8', errors='replace')
if final_dll.count('cmd == "profiler"') != 1:
    raise SystemExit('expected exactly one light profiler command')
if final_dll.count('cmd == "profilerdeep"') != 1:
    raise SystemExit('expected exactly one deep profiler command')

print('B1R5R3 deterministic dual-profiler integration OK')
