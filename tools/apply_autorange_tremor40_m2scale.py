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

# B3.1 already corrected the legacy AutoRange resolver's raw Spell.dbc schema.
# Verify it here rather than modifying it a second time.
a = auto.read_text(encoding="utf-8")
for needle in (
    'gCache.spell.u32(r, 82u + i)',
    'gCache.spell.u32(r, 85u + i)',
    'const std::uint32_t rid = gCache.spell.u32(r, 88u + i);',
    'Schema=CLIENT1121',
):
    if needle not in a:
        raise SystemExit(f"AutoRange B3.1 schema postcondition missing: {needle}")

# Raise only the dedicated AutoRange danger-visual max. MoonMarker's shared
# validation remains unchanged. A 40 yd radius needs scale 8.0 for W10 and
# about 6.667 for W12, so 20.0 leaves headroom without becoming unbounded.
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

# If a shared createPreview() variant also enforces the shared max internally,
# parameterize that helper. Other MoonMarker callers keep the old max through
# the default argument; only AutoRange passes kAutoRangeMaxScale.
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

# Strict postconditions: only AutoRange uses the larger bound.
n2 = native.read_text(encoding="utf-8")
if 'constexpr float kAutoRangeMaxScale = 20.0f;' not in n2:
    raise SystemExit('postcondition failed: AutoRange max scale constant missing')
for marker in ('bool setAutoRangeVisual(', 'bool moveAutoRangeVisual('):
    s, e = function_span(n2, marker)
    body = n2[s:e]
    if 'scale > kAutoRangeMaxScale' not in body:
        raise SystemExit(f'postcondition failed: {marker} does not use AutoRange max')
    if 'scale > moonMarkerAdvancedState::kMaxScale' in body:
        raise SystemExit(f'postcondition failed: {marker} still uses shared max')

# R6.1 calibration helper: direct local-player world position. This avoids
# asking UnitByGuid to discover the player and avoids a full object-list scan.
hp = root / 'GroundProbe.h'
cp = root / 'GroundProbe.cpp'
dp = root / 'dllmain.cpp'
for p in (hp, cp, dp):
    if not p.is_file():
        raise SystemExit(f'missing GroundProbe source: {p}')

h = hp.read_text(encoding='utf-8')
if 'playerPosition()' not in h:
    ns = '\n} // namespace groundProbe\n'
    h = replace_once(
        h, ns,
        '\n// Returns the local player world position only; no object-list scan.\nstd::string playerPosition();\n' + ns,
        'GroundProbe.h playerPosition declaration')
hp.write_text(h, encoding='utf-8', newline='\n')

c = cp.read_text(encoding='utf-8')
if 'std::string playerPosition()' not in c:
    snap = '\nstd::string snapshot(const float maxRangeYards, const bool includeGameObjects) {'
    fn = r'''
std::string playerPosition() {
    if (!moonMarkerRuntimeGuard::enabled()) {
        return std::string("E|") + moonMarkerRuntimeGuard::statusCode() + "|"
            + moonMarkerRuntimeGuard::userMessage();
    }

    const std::uint64_t playerGuid = vanilla1121_unitGUID("player");
    const std::uint32_t playerObject = vanilla1121_getVisiableObject(playerGuid);
    if (playerObject == 0u || (playerObject & 1u) != 0u) {
        return "E|PLAYER_OBJECT_UNAVAILABLE|player object is not available";
    }

    const C3Vector playerPos = vanilla1121_unitPosition(playerObject);
    if (!validPosition(playerPos)) {
        return "E|PLAYER_POSITION_INVALID|player position is not readable";
    }

    std::ostringstream out;
    out.setf(std::ios::fixed);
    out << std::setprecision(3);
    out << "P|" << playerPos.x << '|' << playerPos.y << '|' << playerPos.z;
    return out.str();
}
'''
    c = replace_once(c, snap, '\n' + fn + snap, 'GroundProbe.cpp playerPosition insertion')
cp.write_text(c, encoding='utf-8', newline='\n')

d = dp.read_text(encoding='utf-8')
if 'GroundProbe.PlayerPosition' not in d:
    status = (
        '        if (groundProbeCommand == "GroundProbe.Status") {\n'
        '            lua_pushboolean(L, moonMarkerRuntimeGuard::enabled() ? 1 : 0);\n'
        '            lua_pushstring(L, moonMarkerRuntimeGuard::statusCode());\n'
        '            lua_pushstring(L, moonMarkerRuntimeGuard::userMessage());\n'
        '            return 3;\n'
        '        }\n'
    )
    bridge = (
        '        if (groundProbeCommand == "GroundProbe.PlayerPosition") {\n'
        '            const std::string record = groundProbe::playerPosition();\n'
        '            lua_pushstring(L, record.c_str());\n'
        '            return 1;\n'
        '        }\n'
    )
    d = replace_once(d, status, status + bridge, 'dllmain GroundProbe.Status handler')
dp.write_text(d, encoding='utf-8', newline='\n')

for p, needles in {
    hp: ['std::string playerPosition();'],
    cp: ['std::string playerPosition()', '"P|" << playerPos.x'],
    dp: ['GroundProbe.PlayerPosition', 'groundProbe::playerPosition()'],
}.items():
    txt = p.read_text(encoding='utf-8')
    for needle in needles:
        if needle not in txt:
            raise SystemExit(f'postcondition failed: {needle} missing from {p}')

print('AutoRange dedicated M2 scale + calibration PlayerPosition fix: OK')