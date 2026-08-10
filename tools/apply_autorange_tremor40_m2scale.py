#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
auto = root / "AutoRange.cpp"
native = root / "nativeM2Test.cpp"
for p in (auto, native):
    if not p.is_file():
        raise SystemExit(f"missing required generated source: {p}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def function_span(text: str, marker: str):
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"function marker not found: {marker}")
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"function opening brace not found: {marker}")
    depth = 0
    i = brace
    while i < len(text):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
        i += 1
    raise SystemExit(f"function closing brace not found: {marker}")

# Correct the Classic 1.12 Spell.dbc fields used by the legacy AutoRange resolver.
a = auto.read_text(encoding="utf-8")
a = replace_once(
    a,
    'result = combineMode(result, classifyTarget(gCache.spell.u32(r, 85u + i)));',
    'result = combineMode(result, classifyTarget(gCache.spell.u32(r, 82u + i)));',
    'AutoRange ImplicitTargetA offset',
)
a = replace_once(
    a,
    'result = combineMode(result, classifyTarget(gCache.spell.u32(r, 88u + i)));',
    'result = combineMode(result, classifyTarget(gCache.spell.u32(r, 85u + i)));',
    'AutoRange ImplicitTargetB offset',
)
a = replace_once(
    a,
    'const std::uint32_t rid = gCache.spell.u32(r, 91u + i);',
    'const std::uint32_t rid = gCache.spell.u32(r, 88u + i);',
    'AutoRange EffectRadiusIndex offset',
)

# Match the generic B1R1 DBC loader's explicit MPQ priority. This allows
# Spell.dbc to resolve from patch-9 and SpellRadius.dbc to fall through to
# patch-8 when the higher archive does not carry SpellRadius.dbc.
priority_func = r'''
int archivePriority(const std::string& path) {
    const std::string name = lowerAscii(baseName(path));
    if (name == "patch.mpq") return 1000;
    if (name.size() == 11u && name.compare(0, 6, "patch-") == 0
        && name.compare(7, 4, ".mpq") == 0) {
        const char ch = name[6];
        if (ch >= '0' && ch <= '9') return 1001 + (ch - '0');
        if (ch >= 'a' && ch <= 'z') return 1011 + (ch - 'a');
    }
    if (name.compare(0, 6, "patch-") == 0) return 900;
    if (name == "dbc.mpq") return 100;
    return 0;
}
'''
client_marker = 'std::vector<std::string> clientArchives() {'
if 'int archivePriority(const std::string& path)' not in a:
    a = replace_once(a, client_marker, priority_func + '\n' + client_marker,
                     'AutoRange archivePriority insertion')
old_sort = r'''    std::sort(archives.begin(), archives.end(), [](const std::string& a, const std::string& b) {
        return lowerAscii(a) > lowerAscii(b);
    });'''
new_sort = r'''    std::sort(archives.begin(), archives.end(), [](const std::string& a, const std::string& b) {
        const int ap = archivePriority(a);
        const int bp = archivePriority(b);
        if (ap != bp) return ap > bp;
        return lowerAscii(a) > lowerAscii(b);
    });'''
a = replace_once(a, old_sort, new_sort, 'AutoRange MPQ priority sort')
auto.write_text(a, encoding="utf-8", newline="\n")

# Raise only the dedicated AutoRange danger-visual max. MoonMarker's shared
# validation remains unchanged. A 40 yd radius needs scale 8.0 for W10 and
# about 6.667 for W12, so 20.0 leaves safe headroom without becoming unbounded.
n = native.read_text(encoding="utf-8")
if 'constexpr float kAutoRangeMaxScale = 20.0f;' not in n:
    n = replace_once(
        n,
        'constexpr std::size_t kAutoRangePreviewCount = 16;\n',
        'constexpr std::size_t kAutoRangePreviewCount = 16;\nconstexpr float kAutoRangeMaxScale = 20.0f;\n',
        'AutoRange max scale constant',
    )
set_start, set_end = function_span(n, 'bool setAutoRangeVisual(')
set_body = n[set_start:set_end]
if set_body.count('scale > moonMarkerAdvancedState::kMaxScale') != 1:
    raise SystemExit('setAutoRangeVisual: expected one shared max-scale validation')
set_body = set_body.replace('scale > moonMarkerAdvancedState::kMaxScale',
                            'scale > kAutoRangeMaxScale', 1)
n = n[:set_start] + set_body + n[set_end:]
move_start, move_end = function_span(n, 'bool moveAutoRangeVisual(')
move_body = n[move_start:move_end]
if move_body.count('scale > moonMarkerAdvancedState::kMaxScale') != 1:
    raise SystemExit('moveAutoRangeVisual: expected one shared max-scale validation')
move_body = move_body.replace('scale > moonMarkerAdvancedState::kMaxScale',
                              'scale > kAutoRangeMaxScale', 1)
n = n[:move_start] + move_body + n[move_end:]

# If this source variant also validates scale inside shared createPreview(),
# parameterize that helper and pass 20.0 only from AutoRange. Other callers keep
# the original MoonMarker max through the default argument.
cp_start, cp_end = function_span(n, 'bool createPreview(')
cp_body = n[cp_start:cp_end]
shared_check = 'scale > moonMarkerAdvancedState::kMaxScale'
if shared_check in cp_body:
    if cp_body.count(shared_check) != 1:
        raise SystemExit('createPreview: unexpected number of shared max-scale checks')
    brace = n.find('{', cp_start)
    close_paren = n.rfind(')', cp_start, brace)
    if close_paren < 0:
        raise SystemExit('createPreview: signature close paren not found')
    n = n[:close_paren] + ',\n                   float maxScale = moonMarkerAdvancedState::kMaxScale' + n[close_paren:]
    cp_start, cp_end = function_span(n, 'bool createPreview(')
    cp_body = n[cp_start:cp_end].replace(shared_check, 'scale > maxScale', 1)
    n = n[:cp_start] + cp_body + n[cp_end:]
    set_start, set_end = function_span(n, 'bool setAutoRangeVisual(')
    set_body = n[set_start:set_end]
    old_tail = '"autorange_ready", "autorange_waiting_resources"))'
    new_tail = '"autorange_ready", "autorange_waiting_resources", kAutoRangeMaxScale))'
    if set_body.count(old_tail) != 1:
        raise SystemExit('setAutoRangeVisual: createPreview call tail not found for maxScale')
    set_body = set_body.replace(old_tail, new_tail, 1)
    n = n[:set_start] + set_body + n[set_end:]
native.write_text(n, encoding="utf-8", newline="\n")

# Strict postconditions.
a2 = auto.read_text(encoding="utf-8")
n2 = native.read_text(encoding="utf-8")
checks = [
    (a2, 'gCache.spell.u32(r, 82u + i)', 'TargetA corrected'),
    (a2, 'gCache.spell.u32(r, 85u + i)', 'TargetB corrected'),
    (a2, 'const std::uint32_t rid = gCache.spell.u32(r, 88u + i);', 'RadiusIndex corrected'),
    (a2, 'int archivePriority(const std::string& path)', 'archive priority present'),
    (a2, 'const int ap = archivePriority(a);', 'archive priority used'),
    (n2, 'constexpr float kAutoRangeMaxScale = 20.0f;', 'AutoRange max scale present'),
]
for text, needle, label in checks:
    if needle not in text:
        raise SystemExit(f'postcondition failed: {label}')
for marker in ('bool setAutoRangeVisual(', 'bool moveAutoRangeVisual('):
    s, e = function_span(n2, marker)
    body = n2[s:e]
    if 'scale > kAutoRangeMaxScale' not in body:
        raise SystemExit(f'postcondition failed: {marker} does not use AutoRange max')
    if 'scale > moonMarkerAdvancedState::kMaxScale' in body:
        raise SystemExit(f'postcondition failed: {marker} still uses shared max')

print('AutoRange Tremor40 + dedicated M2 scale fix: OK')
