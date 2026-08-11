#!/usr/bin/env python3
import sys, os, re, shutil, difflib
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit('usage: apply_addon_profiler_b1r5_deep_merge.py <final_b1r4_tree> <clean_tree> <b1r2_tree>')

final = Path(sys.argv[1])
clean = Path(sys.argv[2])
deep = Path(sys.argv[3])

for p in (final, clean, deep):
    if not p.is_dir():
        raise SystemExit('missing tree: %s' % p)

# Copy the already-tested B1R2 debug-hook profiler as an isolated, opt-in deep module.
src_cpp = deep / 'addonProfiler.cpp'
src_h = deep / 'addonProfiler.h'
if not src_cpp.exists() or not src_h.exists():
    raise SystemExit('B1R2 profiler source not found')

cpp = src_cpp.read_text(encoding='utf-8', errors='replace')
hdr = src_h.read_text(encoding='utf-8', errors='replace')

# Keep the light profiler and deep profiler linkable in the same DLL.
def transform_deep_text(s):
    s = s.replace('addonProfiler.h', 'addonProfilerDeep.h')
    s = s.replace('AddonProfiler B1R2', 'AddonProfiler Deep B1R5')
    s = s.replace('AddonProfiler B1R1', 'AddonProfiler Deep B1R5')
    s = s.replace('AddonProfiler B1', 'AddonProfiler Deep B1R5')
    s = s.replace('AddonProfiler', 'AddonProfilerDeep')
    s = s.replace('ADDON_PROFILER_', 'ADDON_PROFILER_DEEP_')
    # Outer UnitXP namespace for the isolated module.
    s = s.replace('"profiler"', '"profilerdeep"')
    return s

cpp = transform_deep_text(cpp)
hdr = transform_deep_text(hdr)
(final / 'addonProfilerDeep.cpp').write_text(cpp, encoding='utf-8', newline='\n')
(final / 'addonProfilerDeep.h').write_text(hdr, encoding='utf-8', newline='\n')

# Merge only the B1R2 integration hunks from dllmain.cpp into the already-patched B1R4 dllmain.
clean_dll = (clean / 'dllmain.cpp').read_text(encoding='utf-8', errors='replace').splitlines(True)
deep_dll = (deep / 'dllmain.cpp').read_text(encoding='utf-8', errors='replace').splitlines(True)
final_path = final / 'dllmain.cpp'
final_lines = final_path.read_text(encoding='utf-8', errors='replace').splitlines(True)

sm = difflib.SequenceMatcher(a=clean_dll, b=deep_dll, autojunk=False)
blocks = []
for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == 'equal':
        continue
    added = deep_dll[j1:j2]
    joined = ''.join(added)
    if 'AddonProfiler' not in joined and 'addonProfiler' not in joined and 'profiler' not in joined:
        continue
    before = clean_dll[max(0, i1-4):i1]
    after = clean_dll[i2:min(len(clean_dll), i2+4)]
    transformed = transform_deep_text(joined)
    # Only integration code, never copy the old profiler source body into dllmain.
    blocks.append((before, after, transformed))

if not blocks:
    raise SystemExit('could not discover B1R2 dllmain integration blocks')

text = ''.join(final_lines)

def find_context_position(text, before, after):
    # Prefer the closest unchanged context. B1R4 may have inserted its own light-profiler lines between them.
    b_candidates = [''.join(before[k:]) for k in range(len(before)) if ''.join(before[k:]).strip()]
    a_candidates = [''.join(after[:k]) for k in range(len(after), 0, -1) if ''.join(after[:k]).strip()]
    for b in b_candidates:
        pos = text.find(b)
        if pos >= 0:
            return pos + len(b)
    for a in a_candidates:
        pos = text.find(a)
        if pos >= 0:
            return pos
    return -1

inserted = 0
for before, after, block in blocks:
    if 'AddonProfilerDeep' in block and block.strip() in text:
        continue
    # Avoid importing an old include guard or duplicated ordinary lines from a replace hunk.
    keep = []
    for line in block.splitlines(True):
        if ('AddonProfilerDeep' in line or 'addonProfilerDeep' in line or 'profilerdeep' in line or
            (keep and line.strip() in ('{', '}', 'return 1;', 'return true;', 'return false;'))):
            keep.append(line)
        elif keep and (line.startswith(' ') or line.startswith('\t')):
            keep.append(line)
    candidate = ''.join(keep).strip('\n')
    if not candidate:
        candidate = block.strip('\n')
    # For a command block, retain its nearby condition/braces from the transformed diff.
    if 'profilerdeep' in block:
        candidate = block.strip('\n')
    if candidate in text:
        continue
    pos = find_context_position(text, before, after)
    if pos < 0:
        continue
    insertion = '\n' + candidate + '\n'
    text = text[:pos] + insertion + text[pos:]
    inserted += 1

# Safety fallback: include header if diff-context integration missed only the include.
if '#include "addonProfilerDeep.h"' not in text:
    m = re.search(r'(#include\s+"addonProfilerLite\.h"\s*\n)', text)
    if not m:
        raise SystemExit('cannot place deep profiler header include')
    text = text[:m.end()] + '#include "addonProfilerDeep.h"\n' + text[m.end():]

# If the command block was not inserted, derive it from the B1R2 source around the profiler call.
if 'profilerdeep' not in text:
    deep_text = ''.join(deep_dll)
    lines = deep_text.splitlines()
    idxs = [i for i,l in enumerate(lines) if 'AddonProfiler' in l and ('Handle' in l or 'Command' in l)]
    if not idxs:
        raise SystemExit('cannot find B1R2 profiler command dispatch')
    i = idxs[0]
    lo = max(0, i-4); hi = min(len(lines), i+5)
    block_lines = lines[lo:hi]
    # Trim to nearest profiler condition and closing brace.
    for k in range(i-lo, -1, -1):
        if 'profiler' in block_lines[k]:
            block_lines = block_lines[k:]
            break
    block = transform_deep_text('\n'.join(block_lines)) + '\n'
    # Place immediately before the light profiler dispatch when possible.
    anchor = text.find('"profiler"')
    if anchor < 0:
        raise SystemExit('cannot place profilerdeep command dispatch')
    line_start = text.rfind('\n', 0, anchor) + 1
    text = text[:line_start] + block + text[line_start:]

final_path.write_text(text, encoding='utf-8', newline='\n')

# Add the deep translation unit to the existing B1R4 Makefile next to the lite one.
mk_path = final / 'Makefile'
mk = mk_path.read_text(encoding='utf-8', errors='replace')
if 'addonProfilerDeep.cpp' not in mk and 'addonProfilerDeep.o' not in mk:
    if 'addonProfilerLite.cpp' in mk:
        mk = mk.replace('addonProfilerLite.cpp', 'addonProfilerLite.cpp addonProfilerDeep.cpp', 1)
    elif 'addonProfilerLite.o' in mk:
        mk = mk.replace('addonProfilerLite.o', 'addonProfilerLite.o addonProfilerDeep.o', 1)
    else:
        # Derive the object/source token the B1 script added to its Makefile.
        clean_mk = (clean / 'Makefile').read_text(encoding='utf-8', errors='replace')
        deep_mk = (deep / 'Makefile').read_text(encoding='utf-8', errors='replace')
        additions = []
        smm = difflib.SequenceMatcher(a=clean_mk.splitlines(True), b=deep_mk.splitlines(True), autojunk=False)
        for tag,i1,i2,j1,j2 in smm.get_opcodes():
            if tag != 'equal':
                additions.extend(deep_mk.splitlines(True)[j1:j2])
        token = None
        for l in additions:
            if 'addonProfiler' in l:
                token = transform_deep_text(l)
                break
        if not token:
            raise SystemExit('cannot add addonProfilerDeep to Makefile')
        mk += '\n' + token + '\n'
mk_path.write_text(mk, encoding='utf-8', newline='\n')

# Build-time assertions: light stays hook-free; deep module exists and is opt-in under its own namespace.
final_dll = final_path.read_text(encoding='utf-8', errors='replace')
if 'addonProfilerDeep.h' not in final_dll:
    raise SystemExit('deep header integration missing')
if 'profilerdeep' not in final_dll:
    raise SystemExit('profilerdeep command namespace missing')
if not (final / 'addonProfilerLite.cpp').exists():
    raise SystemExit('B1R4 light profiler missing')
light = (final / 'addonProfilerLite.cpp').read_text(encoding='utf-8', errors='replace')
if 'lua_sethook' in light or 'LUA_MASKCALL' in light:
    raise SystemExit('light profiler unexpectedly contains debug hook')
if 'lua_sethook' not in cpp:
    raise SystemExit('deep profiler template has no debug hook; wrong B1 source')

print('B1R5 deep merge OK; integration blocks:', inserted)
