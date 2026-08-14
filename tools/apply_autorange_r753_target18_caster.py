#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "AutoRange.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing {cpp}")
text = cpp.read_text(encoding="utf-8")

# Vanilla 1.12 target semantics fix:
#   18 = TARGET_LOCATION_CASTER_DEST
#   16 = TARGET_ENUM_UNITS_ENEMY_AOE_AT_DEST_LOC
# A pair such as (18,16), used by Hellfire Effect and similar triggered
# self-centered AoE spells, means "enumerate units around the caster's
# destination", not an arbitrary ground-selected DynamicObject location.
#
# Keep target 16 as GROUND when it appears without an explicit caster-dest
# partner so normal client-selected ground AoEs retain their current behavior.

old_target = '''Mode classifyTarget(std::uint32_t target) {
    switch (target) {
        case 24u:
        case 54u:
        case 59u:
        case 60u:
            return Mode::Cone;
        case 8u:
        case 16u:
        case 28u:
        case 29u:
        case 31u:
        case 34u:
        case 52u:
            return Mode::Ground;
        case 1u:
        case 2u:
        case 4u:
        case 7u:
        case 15u:
        case 20u:
        case 22u:
        case 30u:
        case 33u:
        case 36u:
        case 51u:
        case 56u:
            return Mode::Caster;
        default:
            return Mode::Unknown;
    }
}

Mode combineMode(Mode a, Mode b) {
'''
new_target = '''Mode classifyTarget(std::uint32_t target) {
    switch (target) {
        case 24u:
        case 54u:
        case 59u:
        case 60u:
            return Mode::Cone;
        case 8u:
        case 16u:
        case 28u:
        case 29u:
        case 31u:
        case 34u:
        case 52u:
            return Mode::Ground;
        case 1u:
        case 2u:
        case 4u:
        case 7u:
        case 15u:
        case 18u: // TARGET_LOCATION_CASTER_DEST
        case 20u:
        case 22u:
        case 30u:
        case 33u:
        case 36u:
        case 51u:
        case 56u:
            return Mode::Caster;
        default:
            return Mode::Unknown;
    }
}

Mode combineMode(Mode a, Mode b) {
'''
if old_target not in text:
    raise SystemExit("classifyTarget marker missing")
text = text.replace(old_target, new_target, 1)

old_combine_tail = '''    if (a == Mode::Caster || b == Mode::Caster) return Mode::Caster;
    return Mode::Unknown;
}

Mode spellHint(const std::uint8_t* r) {
    Mode result = Mode::Unknown;
    for (std::uint32_t i = 0; i < 3u; ++i) {
        result = combineMode(result, classifyTarget(gCache.spell.u32(r, 85u + i)));
        result = combineMode(result, classifyTarget(gCache.spell.u32(r, 88u + i)));
    }
    return result;
}
'''
new_combine_tail = '''    if (a == Mode::Caster || b == Mode::Caster) return Mode::Caster;
    return Mode::Unknown;
}

bool isDestinationAreaEnumerator(std::uint32_t target) {
    switch (target) {
        case 8u:  // script AOE at dest
        case 16u: // enemy AOE at dest
        case 31u: // friend AOE at dest
        case 34u: // party AOE at dest
        case 52u: // gameobject script AOE at dest
            return true;
        default:
            return false;
    }
}

Mode classifyEffectTargets(std::uint32_t a, std::uint32_t b) {
    // TARGET_LOCATION_CASTER_DEST explicitly supplies the destination.  A
    // destination-area enumerator paired with it is therefore caster-centered.
    if ((a == 18u && isDestinationAreaEnumerator(b))
        || (b == 18u && isDestinationAreaEnumerator(a))) {
        return Mode::Caster;
    }
    return combineMode(classifyTarget(a), classifyTarget(b));
}

Mode spellHint(const std::uint8_t* r) {
    Mode result = Mode::Unknown;
    for (std::uint32_t i = 0; i < 3u; ++i) {
        const std::uint32_t ta = gCache.spell.u32(r, 85u + i);
        const std::uint32_t tb = gCache.spell.u32(r, 88u + i);
        result = combineMode(result, classifyEffectTargets(ta, tb));
    }
    return result;
}
'''
if old_combine_tail not in text:
    raise SystemExit("combine/spellHint marker missing")
text = text.replace(old_combine_tail, new_combine_tail, 1)

old_specific = '        Mode specific = combineMode(classifyTarget(ta), classifyTarget(tb));\n'
new_specific = '        Mode specific = classifyEffectTargets(ta, tb);\n'
if old_specific not in text:
    raise SystemExit("walkSpell target pair marker missing")
text = text.replace(old_specific, new_specific, 1)

# Give status/source diagnostics a unique build marker without changing the API.
text = text.replace('Schema=CLIENT1121-B32|Spell=', 'Schema=CLIENT1121-B32-T18CASTER|Spell=', 1)

cpp.write_text(text, encoding="utf-8", newline="\n")
final = cpp.read_text(encoding="utf-8")
for needle in (
    'case 18u: // TARGET_LOCATION_CASTER_DEST',
    'isDestinationAreaEnumerator',
    'classifyEffectTargets',
    'Mode specific = classifyEffectTargets(ta, tb);',
    'Schema=CLIENT1121-B32-T18CASTER',
):
    if needle not in final:
        raise SystemExit(f"postcondition missing: {needle}")
print("AutoRange R7.5.3 target18 caster-destination pair fix: OK")
