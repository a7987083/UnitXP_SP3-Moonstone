#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "AutoRange.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing {cpp}")
text = cpp.read_text(encoding="utf-8")

# B3.2: select the actual dangerous geometry instead of the largest radius.
# This runs AFTER apply_autorange_b31_fix.py, so all raw client Spell.dbc
# column offsets are already corrected.

old_struct = '''struct Candidate {
    bool valid = false;
    std::uint32_t castSpell = 0;
    std::uint32_t geometrySpell = 0;
    float radius = 0.0f;
    Mode mode = Mode::Unknown;
    std::uint32_t radiusIndex = 0;
    std::uint32_t targetA = 0;
    std::uint32_t targetB = 0;
    std::uint32_t depth = 0;
};

int modeScore(Mode m) {
    switch (m) {
        case Mode::Caster: return 4;
        case Mode::Ground: return 4;
        case Mode::Cone: return 2;
        default: return 1;
    }
}

bool better(const Candidate& a, const Candidate& b) {
    if (!b.valid) return true;
    const int as = modeScore(a.mode), bs = modeScore(b.mode);
    if (as != bs) return as > bs;
    if (a.depth != b.depth) return a.depth < b.depth;
    return a.radius > b.radius;
}
'''

new_struct = '''struct Candidate {
    bool valid = false;
    std::uint32_t castSpell = 0;
    std::uint32_t geometrySpell = 0;
    float radius = 0.0f;
    Mode mode = Mode::Unknown;
    std::uint32_t radiusIndex = 0;
    std::uint32_t targetA = 0;
    std::uint32_t targetB = 0;
    std::uint32_t depth = 0;
    std::uint32_t effect = 0;
    std::uint32_t effectIndex = 0;
};

int modeScore(Mode m) {
    switch (m) {
        case Mode::Caster: return 30;
        case Mode::Ground: return 32;
        case Mode::Cone: return 12;
        default: return 0;
    }
}

// Geometry relevance, not spell power.  A DUMMY radius is often a search /
// script envelope (Axe Flurry 24019 is the canonical 30 yd example), while
// damage, hostile aura and persistent-area effects describe the actual space
// the player must avoid.
int effectGeometryScore(std::uint32_t effect) {
    switch (effect) {
        case 2u:   // SCHOOL_DAMAGE
        case 7u:   // ENVIRONMENTAL_DAMAGE
        case 9u:   // HEALTH_LEECH
        case 17u:  // WEAPON_DAMAGE_NOSCHOOL
        case 31u:  // WEAPON_PERCENT_DAMAGE
        case 58u:  // WEAPON_DAMAGE
        case 62u:  // POWER_BURN
        case 98u:  // KNOCK_BACK
        case 121u: // NORMALIZED_WEAPON_DMG (custom/backport clients)
            return 100;
        case 27u:  // PERSISTENT_AREA_AURA
            return 98;
        case 6u:   // APPLY_AURA
        case 35u:  // APPLY_AREA_AURA_PARTY
        case 119u: // APPLY_AREA_AURA_PET
        case 128u: // APPLY_AREA_AURA_FRIEND (backport)
        case 129u: // APPLY_AREA_AURA_ENEMY (backport)
        case 132u: // APPLY_AREA_AURA_RAID (backport)
            return 90;
        case 32u:  // TRIGGER_MISSILE
            return 65;
        case 68u:  // INTERRUPT_CAST
        case 78u:  // ATTACK
        case 114u: // ATTACK_ME
            return 55;
        case 64u:  // TRIGGER_SPELL -- child is scored instead
            return 5;
        case 3u:   // DUMMY -- commonly server/script/search envelope
        case 77u:  // SCRIPT_EFFECT
            return 1;
        default:
            return 25;
    }
}

int targetGeometryScore(std::uint32_t a, std::uint32_t b) {
    const std::uint32_t values[2] = {a, b};
    int score = 0;
    for (std::uint32_t t : values) {
        switch (t) {
            case 15u: // enemy AOE at caster/source
            case 36u: // enemies within caster range
                score = std::max(score, 30); break;
            case 8u:  // script AOE dest
            case 16u: // enemy AOE dest
            case 28u: // enemy AOE at dynobj
                score = std::max(score, 30); break;
            case 7u:  // script AOE source
                score = std::max(score, 24); break;
            case 22u: // caster source location
                score = std::max(score, 18); break;
            case 24u: // cone
            case 54u:
            case 60u:
                score = std::max(score, 8); break;
            default: break;
        }
    }
    return score;
}

int candidateScore(const Candidate& c) {
    // Child geometry is mildly preferred over wrapper/root effects, but only
    // after semantic effect/target scoring.  This prevents a 30 yd DUMMY child
    // from beating a 5 yd hostile aura/damage child merely because it is larger.
    const int depthBonus = std::min<int>(static_cast<int>(c.depth), 4) * 2;
    return effectGeometryScore(c.effect) + modeScore(c.mode)
        + targetGeometryScore(c.targetA, c.targetB) + depthBonus;
}

bool better(const Candidate& a, const Candidate& b) {
    if (!b.valid) return true;
    const int as = candidateScore(a), bs = candidateScore(b);
    if (as != bs) return as > bs;
    // For equally meaningful circular hazards prefer the tighter local danger
    // envelope rather than the largest scripting/search envelope.
    if (a.radius != b.radius) return a.radius < b.radius;
    if (a.depth != b.depth) return a.depth > b.depth;
    return a.geometrySpell < b.geometrySpell;
}
'''

if old_struct not in text:
    raise SystemExit("Candidate/better block marker missing")
text = text.replace(old_struct, new_struct, 1)

old_assign = '''        c.valid = true; c.castSpell = castSpell; c.geometrySpell = spellId;
        c.radius = rv; c.mode = specific; c.radiusIndex = rid;
        c.targetA = ta; c.targetB = tb; c.depth = depth;
        if (better(c, best)) best = c;
'''
new_assign = '''        c.valid = true; c.castSpell = castSpell; c.geometrySpell = spellId;
        c.radius = rv; c.mode = specific; c.radiusIndex = rid;
        c.targetA = ta; c.targetB = tb; c.depth = depth;
        c.effect = effect; c.effectIndex = i;
        if (better(c, best)) best = c;
'''
if old_assign not in text:
    raise SystemExit("candidate assignment marker missing")
text = text.replace(old_assign, new_assign, 1)

# Correct and broaden target classification for vanilla 1.12 area target enums.
old_classify = '''Mode classifyTarget(std::uint32_t target) {
    switch (target) {
        case 24u: return Mode::Cone;
        case 8u:
        case 16u:
        case 28u:
        case 29u:
            return Mode::Ground;
        case 1u:
        case 7u:
        case 15u:
        case 20u:
        case 22u:
            return Mode::Caster;
        default:
            return Mode::Unknown;
    }
}
'''
new_classify = '''Mode classifyTarget(std::uint32_t target) {
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
'''
if old_classify not in text:
    raise SystemExit("classifyTarget marker missing")
text = text.replace(old_classify, new_classify, 1)

# Append selected effect, slot and score. Existing Lua parsers ignore extras; B3.2
# Lua consumes them for diagnostics.
old_out = '''        << best.depth << '|'
        << safeSource(gCache.spell.source) << '|'
        << safeSource(gCache.radius.source) << '|'
        << safeSource(gCache.duration.source);
'''
new_out = '''        << best.depth << '|'
        << safeSource(gCache.spell.source) << '|'
        << safeSource(gCache.radius.source) << '|'
        << safeSource(gCache.duration.source) << '|'
        << best.effect << '|' << best.effectIndex << '|' << candidateScore(best);
'''
if old_out not in text:
    raise SystemExit("resolve output marker missing")
text = text.replace(old_out, new_out, 1)

text = text.replace('Schema=CLIENT1121|Spell=', 'Schema=CLIENT1121-B32|Spell=', 1)
cpp.write_text(text, encoding="utf-8", newline="\n")

final = cpp.read_text(encoding="utf-8")
for needle in ("effectGeometryScore", "candidateScore", "c.effect = effect", "Schema=CLIENT1121-B32"):
    if needle not in final:
        raise SystemExit(f"postcondition missing: {needle}")
print("AutoRange B3.2 dangerous-geometry candidate scoring: OK")
