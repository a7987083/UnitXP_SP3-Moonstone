#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
h_path = root / "AutoRange.h"
cpp_path = root / "AutoRange.cpp"
dll_path = root / "dllmain.cpp"
for p in (h_path, cpp_path, dll_path):
    if not p.is_file():
        raise SystemExit(f"missing required source: {p}")


def replace_once(text: str, needle: str, replacement: str, label: str) -> str:
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, got {count}")
    return text.replace(needle, replacement, 1)

h = h_path.read_text(encoding="utf-8")
if "totemInfo(" not in h:
    marker = "\n} // namespace autoRange\n"
    addition = (
        "\n// DBC-only totem summon classifier. Follows trigger-spell chains.\n"
        "std::string totemInfo(unsigned int spellId);\n"
    )
    h = replace_once(h, marker, addition + marker, "AutoRange.h namespace marker")
h_path.write_text(h, encoding="utf-8", newline="\n")

c = cpp_path.read_text(encoding="utf-8")
if "std::string totemInfo(" not in c:
    marker = "\n} // namespace autoRange\n"
    pos = c.rfind(marker)
    if pos < 0:
        raise SystemExit("AutoRange.cpp final namespace marker missing")

    addition = r'''

namespace {

constexpr std::uint32_t kSpellEffectTriggerSpell = 64u;
constexpr std::uint32_t kSpellEffectSummonTotem = 74u;
constexpr std::uint32_t kSpellEffectSummonTotemSlot1 = 87u;
constexpr std::uint32_t kSpellEffectSummonTotemSlot4 = 90u;

bool isTotemSummonEffect(const std::uint32_t effect) {
    return effect == kSpellEffectSummonTotem
        || (effect >= kSpellEffectSummonTotemSlot1
            && effect <= kSpellEffectSummonTotemSlot4);
}

struct TotemDbcCandidate {
    bool valid = false;
    std::uint32_t summonSpell = 0u;
    std::uint32_t effectIndex = 0u;
    std::uint32_t effectType = 0u;
    std::uint32_t creatureEntry = 0u;
    std::uint32_t depth = 0u;
};

bool findTotemSummon(const std::uint32_t spellId,
                     const std::uint32_t depth,
                     std::unordered_set<std::uint32_t>& visited,
                     TotemDbcCandidate& out) {
    if (spellId == 0u || depth > 4u || visited.count(spellId) != 0u) return false;
    visited.insert(spellId);
    const std::uint8_t* r = gCache.spell.record(spellId);
    if (r == nullptr) return false;

    // Raw WoW 1.12.1 client Spell.dbc columns after the B3.1 offset fix:
    // Effect[3] = 61..63; EffectMiscValue[3] = 106..108;
    // EffectTriggerSpell[3] = 109..111.
    for (std::uint32_t i = 0u; i < 3u; ++i) {
        const std::uint32_t effect = gCache.spell.u32(r, 61u + i);
        if (!isTotemSummonEffect(effect)) continue;
        out.valid = true;
        out.summonSpell = spellId;
        out.effectIndex = i;
        out.effectType = effect;
        out.creatureEntry = gCache.spell.u32(r, 106u + i);
        out.depth = depth;
        return true;
    }

    for (std::uint32_t i = 0u; i < 3u; ++i) {
        const std::uint32_t effect = gCache.spell.u32(r, 61u + i);
        if (effect != kSpellEffectTriggerSpell) continue;
        const std::uint32_t child = gCache.spell.u32(r, 109u + i);
        if (child == 0u) continue;
        if (findTotemSummon(child, depth + 1u, visited, out)) return true;
    }
    return false;
}

} // namespace

std::string totemInfo(const unsigned int spellId) {
    if (spellId == 0u) return "T|0|0|0|0|0|0|0|SPELL_INVALID";
    if (!ensureCache()) return std::string("E|TOTEM_DBC|") + gCache.error;

    TotemDbcCandidate candidate;
    std::unordered_set<std::uint32_t> visited;
    const bool found = findTotemSummon(spellId, 0u, visited, candidate);
    if (!found || !candidate.valid) {
        std::ostringstream out;
        out << "T|0|" << spellId << "|0|0|0|0|0|NOT_TOTEM";
        return out.str();
    }

    std::uint32_t lifeMs = durationMs(candidate.summonSpell);
    if (lifeMs == 0u && candidate.summonSpell != spellId) lifeMs = durationMs(spellId);

    std::ostringstream out;
    out << "T|1|" << spellId << '|'
        << candidate.summonSpell << '|'
        << candidate.effectIndex << '|'
        << candidate.effectType << '|'
        << candidate.creatureEntry << '|'
        << lifeMs << "|TOTEM_DBC_EVENT";
    return out.str();
}
'''
    c = c[:pos] + addition + c[pos:]
cpp_path.write_text(c, encoding="utf-8", newline="\n")

d = dll_path.read_text(encoding="utf-8")
if 'AutoRange.TotemInfo' not in d:
    marker = '''        if (autoRangeCommand == "AutoRange.Resolve" && argumentCount >= 2
            && lua_isnumber(L, 2)) {
            const unsigned int spellId = static_cast<unsigned int>(lua_tonumber(L, 2));
            const std::string record = autoRange::resolve(spellId);
            lua_pushstring(L, record.c_str());
            return 1;
        }
'''
    bridge = '''        if (autoRangeCommand == "AutoRange.TotemInfo" && argumentCount >= 2
            && lua_isnumber(L, 2)) {
            const unsigned int spellId = static_cast<unsigned int>(lua_tonumber(L, 2));
            const std::string record = autoRange::totemInfo(spellId);
            lua_pushstring(L, record.c_str());
            return 1;
        }
'''
    d = replace_once(d, marker, marker + bridge, "dllmain AutoRange.Resolve handler")
dll_path.write_text(d, encoding="utf-8", newline="\n")

checks = {
    h_path: ["totemInfo"],
    cpp_path: [
        "kSpellEffectSummonTotem = 74u",
        "kSpellEffectSummonTotemSlot1 = 87u",
        "kSpellEffectSummonTotemSlot4 = 90u",
        "gCache.spell.u32(r, 106u + i)",
        "gCache.spell.u32(r, 109u + i)",
        "TOTEM_DBC_EVENT",
        "std::string totemInfo",
    ],
    dll_path: ["AutoRange.TotemInfo"],
}
for p, needles in checks.items():
    text = p.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"postcondition failed: {needle} missing from {p}")

print("AutoRange B3.7 DBC totem classifier: OK")
