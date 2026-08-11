#!/usr/bin/env python3
import sys, re, difflib
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

def transform_deep_text(s):
    s = s.replace('addonProfiler.h', 'addonProfilerDeep.h')
    s = s.replace('AddonProfiler B1R2', 'AddonProfiler Deep B1R5')
    s = s.replace('AddonProfiler B1R1', 'AddonProfiler Deep B1R5')
    s = s.replace('AddonProfiler B1', 'AddonProfiler Deep B1R5')
    s = s.replace('AddonProfiler', 'AddonProfilerDeep')
    s = s.replace('ADDON_PROFILER_', 'ADDON_PROFILER_DEEP_')
    s = s.replace('"profiler"', '"profilerdeep"')
    return s

cpp = transform_deep_text(cpp)
hdr = transform_deep_text(hdr)
(final / 'addonProfilerDeep.cpp').write_text(cpp, encoding='utf-8', newline='\n')
(final / 'addonProfilerDeep.h').write_text(hdr, encoding='utf-8', newline='\n')

# Merge only B1R2 dllmain integration hunks into the already-patched B1R4 dllmain.
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
    before = clean_dll[max(0, i1 - 4):i1]
    after = clean_dll[i2:min(len(clean_dll), i2 + 4)]
    blocks.append((before, after, transform_deep_text(joined)))

if not blocks:
    raise SystemExit('could not discover B1R2 dllmain integration blocks')

text = ''.join(final_lines)

def find_context_position(text, before, after):
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
    if 'profilerdeep' in block:
        candidate = block.strip('\n')
    if candidate in text:
        continue
    pos = find_context_position(text, before, after)
    if pos < 0:
        continue
    text = text[:pos] + '\n' + candidate + '\n' + text[pos:]
    inserted += 1

if '#include "addonProfilerDeep.h"' not in text:
    m = re.search(r'(#include\s+"addonProfilerLite\.h"\s*\n)', text)
    if not m:
        raise SystemExit('cannot place deep profiler header include')
    text = text[:m.end()] + '#include "addonProfilerDeep.h"\n' + text[m.end():]

if 'profilerdeep' not in text:
    deep_text = ''.join(deep_dll)
    lines = deep_text.splitlines()
    idxs = [i for i, l in enumerate(lines) if 'AddonProfiler' in l and ('Handle' in l or 'Command' in l)]
    if not idxs:
        raise SystemExit('cannot find B1R2 profiler command dispatch')
    i = idxs[0]
    lo = max(0, i - 4)
    hi = min(len(lines), i + 5)
    block_lines = lines[lo:hi]
    for k in range(i - lo, -1, -1):
        if 'profiler' in block_lines[k]:
            block_lines = block_lines[k:]
            break
    block = transform_deep_text('\n'.join(block_lines)) + '\n'
    anchor = text.find('"profiler"')
    if anchor < 0:
        raise SystemExit('cannot place profilerdeep command dispatch')
    line_start = text.rfind('\n', 0, anchor) + 1
    text = text[:line_start] + block + text[line_start:]

final_path.write_text(text, encoding='utf-8', newline='\n')

# Makefile integration.
# B1R4's generator can add its source token as a standalone appended line.  Do not
# repeat that pattern here: normalize profiler source tokens and inject both units
# inside the SRCS continuation block, before OBJS.
mk_path = final / 'Makefile'
mk = mk_path.read_text(encoding='utf-8', errors='replace')
lines = mk.splitlines()

# Remove only malformed standalone profiler source lines outside the SRCS block.
in_srcs = False
cleaned = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith('SRCS') and '=' in stripped:
        in_srcs = True
    if in_srcs and stripped and not stripped.endswith('\\') and not stripped.startswith('SRCS'):
        # This is the final source line of the continuation block.
        in_srcs = False
    malformed = (not in_srcs and stripped in (
        'addonProfilerLite.cpp', 'addonProfilerDeep.cpp',
        'addonProfilerLite.o', 'addonProfilerDeep.o',
        'addonProfilerLite.cpp addonProfilerDeep.cpp',
        'addonProfilerLite.o addonProfilerDeep.o'))
    if malformed:
        continue
    cleaned.append(line)

# Remove profiler tokens from any existing SRCS continuation lines to avoid duplicates.
normalized = []
for line in cleaned:
    if 'addonProfilerLite.cpp' in line or 'addonProfilerDeep.cpp' in line:
        line = line.replace('addonProfilerLite.cpp', '').replace('addonProfilerDeep.cpp', '')
        # Preserve a continuation-only line only if it still has another token.
        content = line.replace('\\', '').strip()
        if not content:
            continue
    normalized.append(line)

# Insert both profiler sources immediately before the first MinHook source in SRCS.
insert_at = None
for idx, line in enumerate(normalized):
    if '$(MINHOOK_DIR)/src/' in line:
        insert_at = idx
        break
if insert_at is None:
    # Fallback: immediately before OBJS, while preserving a valid continuation.
    for idx, line in enumerate(normalized):
        if line.lstrip().startswith('OBJS'):
            insert_at = idx
            break
if insert_at is None:
    raise SystemExit('cannot locate Makefile SRCS/OBJS insertion point')

# If the previous source line was the final non-continuation line, make it continue.
prev = insert_at - 1
while prev >= 0 and not normalized[prev].strip():
    prev -= 1
if prev >= 0 and normalized[prev].lstrip().startswith('SRCS') is False and not normalized[prev].rstrip().endswith('\\'):
    normalized[prev] = normalized[prev].rstrip() + ' \\'

prof_lines = [
    '            addonProfilerLite.cpp \\',
    '            addonProfilerDeep.cpp \\',
]
normalized[insert_at:insert_at] = prof_lines
mk = '\n'.join(normalized) + '\n'
mk_path.write_text(mk, encoding='utf-8', newline='\n')

# Assertions.
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
mk_check = mk_path.read_text(encoding='utf-8', errors='replace')
if mk_check.count('addonProfilerLite.cpp') != 1 or mk_check.count('addonProfilerDeep.cpp') != 1:
    raise SystemExit('profiler Makefile source count invalid')

print('B1R5 deep merge OK; integration blocks:', inserted)
