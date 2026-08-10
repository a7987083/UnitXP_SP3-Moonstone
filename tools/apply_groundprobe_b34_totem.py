#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
h_path = root / "GroundProbe.h"
cpp_path = root / "GroundProbe.cpp"
dll_path = root / "dllmain.cpp"
for p in (h_path, cpp_path, dll_path):
    if not p.is_file():
        raise SystemExit(f"missing required source: {p}")


def replace_once(text: str, needle: str, replacement: str, label: str) -> str:
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, got {count}")
    return text.replace(needle, replacement, 1)

# Public diagnostic/snapshot API.
h = h_path.read_text(encoding="utf-8")
if "totemSnapshot(" not in h:
    marker = "\n} // namespace groundProbe\n"
    addition = (
        "\n// Native group-scope lookup for a SuperWoW caster GUID.\n"
        "std::string scopeByGuid(const std::string& guidText);\n"
        "\n// Native WoW 1.12 totem scanner. Mode: OFF/SELF/PARTY/PARTY_ONLY/RAID/ALL.\n"
        "std::string totemSnapshot(const std::string& mode, float maxRangeYards = 140.0f);\n"
    )
    h = replace_once(h, marker, addition + marker, "GroundProbe.h namespace marker")
h_path.write_text(h, encoding="utf-8", newline="\n")

c = cpp_path.read_text(encoding="utf-8")
if "#include <unordered_set>" not in c:
    c = replace_once(c, "#include <string>\n", "#include <string>\n#include <unordered_set>\n", "GroundProbe.cpp include")

if "std::string totemSnapshot(" not in c:
    marker = "\n} // namespace groundProbe\n"
    pos = c.rfind(marker)
    if pos < 0:
        raise SystemExit("GroundProbe.cpp final namespace marker missing")

    addition = r'''
namespace {

// WoW 1.12.1 build 5875 absolute Unit update-field indices.
// Verified against UpdateFields_1_12_1.h:
// SUMMONEDBY=0x0C, CREATEDBY=0x0E, AURA[0]=0x2F, CREATED_BY_SPELL=0x92.
constexpr std::size_t kUnitFieldSummonedBy = 0x0Cu;
constexpr std::size_t kUnitFieldCreatedBy = 0x0Eu;
constexpr std::size_t kUnitAuraFirst = 0x2Fu;
constexpr std::size_t kUnitAuraCount = 48u;
constexpr std::size_t kUnitCreatedBySpell = 0x92u;
constexpr int kCreatureTypeTotem = 11;

std::string upperAsciiTotem(std::string value) {
    for (char& c : value) {
        if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    }
    return value;
}

const char* groupScopeForGuid(const std::uint64_t guid) {
    if (guid == 0u) return "UNKNOWN";
    const std::uint64_t self = vanilla1121_unitGUID("player");
    if (self != 0u && guid == self) return "SELF";

    for (int i = 1; i <= 4; ++i) {
        const std::string unit = std::string("party") + std::to_string(i);
        const std::uint64_t member = vanilla1121_unitGUID(unit.c_str());
        if (member != 0u && guid == member) return "PARTY";
    }
    for (int i = 1; i <= 40; ++i) {
        const std::string unit = std::string("raid") + std::to_string(i);
        const std::uint64_t member = vanilla1121_unitGUID(unit.c_str());
        if (member != 0u && guid == member) return "RAID";
    }
    return "OTHER";
}

bool modeAllowsScope(const std::string& rawMode, const char* scope) {
    const std::string mode = upperAsciiTotem(rawMode);
    if (mode == "OFF") return false;
    if (mode == "ALL") return true;
    if (mode == "SELF") return std::strcmp(scope, "SELF") == 0;
    if (mode == "PARTY")
        return std::strcmp(scope, "SELF") == 0 || std::strcmp(scope, "PARTY") == 0;
    if (mode == "PARTY_ONLY") return std::strcmp(scope, "PARTY") == 0;
    if (mode == "RAID")
        return std::strcmp(scope, "SELF") == 0 || std::strcmp(scope, "PARTY") == 0
            || std::strcmp(scope, "RAID") == 0;
    // Invalid/missing mode fails closed to SELF to avoid filling the world with totem rings.
    return std::strcmp(scope, "SELF") == 0;
}

bool resolveGuidForScope(const std::string& guidText, std::uint64_t& guid) {
    guid = 0u;
    std::string normalized;
    bool explicitHex = false;
    bool hasHexAlpha = false;
    if (!normalizeGuidText(guidText, normalized, explicitHex, hasHexAlpha)) return false;
    const std::size_t start = explicitHex ? 2u : 0u;

    std::uint64_t first = 0u, second = 0u;
    bool haveFirst = false, haveSecond = false;
    if (explicitHex || hasHexAlpha) {
        haveFirst = parseGuidBase(normalized, start, 16u, first);
    } else {
        haveFirst = parseGuidBase(normalized, start, 10u, first);
        haveSecond = parseGuidBase(normalized, start, 16u, second) && second != first;
    }
    if (!haveFirst && !haveSecond) return false;

    // UNIT_CASTEVENT GUIDs are visible in the normal AutoRange path. Prefer the
    // candidate that resolves through the client's GUID hash table, matching
    // RelationByGuid's decimal/hex compatibility behavior.
    if (haveFirst) {
        const std::uint32_t object = vanilla1121_getVisiableObject(first);
        if (object != 0u && (object & 1u) == 0u) { guid = first; return true; }
    }
    if (haveSecond) {
        const std::uint32_t object = vanilla1121_getVisiableObject(second);
        if (object != 0u && (object & 1u) == 0u) { guid = second; return true; }
    }

    guid = haveFirst ? first : second;
    return guid != 0u;
}

std::uint64_t totemOwnerGuid(const std::uint32_t descriptor) {
    std::uint64_t createdBy = 0u;
    std::uint64_t summonedBy = 0u;
    descriptorU64(descriptor, kUnitFieldCreatedBy, createdBy);
    descriptorU64(descriptor, kUnitFieldSummonedBy, summonedBy);
    return createdBy != 0u ? createdBy : summonedBy;
}

std::string totemAuraCsv(const std::uint32_t descriptor) {
    std::ostringstream out;
    std::unordered_set<std::uint32_t> seen;
    bool first = true;
    for (std::size_t i = 0; i < kUnitAuraCount; ++i) {
        std::uint32_t spell = 0u;
        if (!descriptorU32(descriptor, kUnitAuraFirst + i, spell) || spell == 0u) continue;
        if (!seen.insert(spell).second) continue;
        if (!first) out << ',';
        first = false;
        out << spell;
    }
    return out.str();
}

} // namespace

std::string scopeByGuid(const std::string& guidText) {
    std::uint64_t guid = 0u;
    if (!resolveGuidForScope(guidText, guid))
        return "G|UNKNOWN|0000000000000000|GUID_INVALID";
    return std::string("G|") + groupScopeForGuid(guid) + '|' + hex64(guid) + "|OK";
}

std::string totemSnapshot(const std::string& rawMode, const float maxRangeYards) {
    if (!moonMarkerRuntimeGuard::enabled()) {
        return std::string("E|") + moonMarkerRuntimeGuard::statusCode() + "|"
            + moonMarkerRuntimeGuard::userMessage();
    }

    const std::string mode = upperAsciiTotem(rawMode.empty() ? "SELF" : rawMode);
    if (mode == "OFF") return "S|0|0|OFF";

    const std::uint64_t playerGuid = vanilla1121_unitGUID("player");
    const std::uint32_t playerObject = vanilla1121_getVisiableObject(playerGuid);
    if (playerObject == 0u || (playerObject & 1u) != 0u)
        return "E|PLAYER_OBJECT_UNAVAILABLE|player object is not available";
    const C3Vector playerPos = vanilla1121_unitPosition(playerObject);
    if (!validPosition(playerPos))
        return "E|PLAYER_POSITION_INVALID|player position is not readable";

    std::uint32_t objects = 0u;
    if (!safeRead<std::uint32_t>(kObjectManagerPtr, objects) || objects == 0u)
        return "E|OBJECT_MANAGER_UNAVAILABLE|object manager is not available";
    std::uint32_t current = 0u;
    if (!safeRead<std::uint32_t>(static_cast<std::uintptr_t>(objects) + 0xACu, current))
        return "E|OBJECT_HEAD_UNAVAILABLE|object list head is not readable";

    const float range = (std::isfinite(maxRangeYards) && maxRangeYards > 0.0f)
        ? maxRangeYards : 140.0f;
    std::ostringstream out;
    out.setf(std::ios::fixed);
    out << std::setprecision(3);

    std::size_t visited = 0u;
    std::size_t count = 0u;
    while (current != 0u && (current & 1u) == 0u && visited < 8192u) {
        ++visited;
        std::uint32_t type = 0u;
        if (!safeRead<std::uint32_t>(static_cast<std::uintptr_t>(current) + kObjectTypeOffset, type))
            break;

        if (type == OBJECT_TYPE_Unit && vanilla1121_unitCreatureType(current) == kCreatureTypeTotem) {
            std::uint32_t descriptor = 0u;
            std::uint64_t guid = 0u;
            if (descriptorPtr(current, descriptor)
                && safeRead<std::uint64_t>(static_cast<std::uintptr_t>(current) + kObjectGuidOffset, guid)
                && guid != 0u) {
                const std::uint64_t owner = totemOwnerGuid(descriptor);
                const char* scope = groupScopeForGuid(owner);
                if (modeAllowsScope(mode, scope)) {
                    const C3Vector pos = vanilla1121_unitPosition(current);
                    if (validPosition(pos)) {
                        const float xy = distanceXY(playerPos, pos);
                        if (xy <= range) {
                            std::uint32_t entry = 0u;
                            std::uint32_t createdSpell = 0u;
                            descriptorU32(descriptor, kObjectFieldEntry, entry);
                            descriptorU32(descriptor, kUnitCreatedBySpell, createdSpell);
                            const float zdiff = std::fabs(playerPos.z - pos.z);
                            ++count;
                            out << "T|" << hex64(guid) << '|' << entry << '|'
                                << hex64(owner) << '|' << scope << '|' << createdSpell << '|'
                                << pos.x << '|' << pos.y << '|' << pos.z << '|'
                                << xy << '|' << zdiff << '|' << totemAuraCsv(descriptor) << '\n';
                        }
                    }
                }
            }
        }

        std::uint32_t next = 0u;
        if (!nextObject(objects, current, next) || next == current) break;
        current = next;
    }

    out << "S|" << count << '|' << visited << '|' << mode;
    return out.str();
}
'''
    c = c[:pos] + addition + c[pos:]

cpp_path.write_text(c, encoding="utf-8", newline="\n")

d = dll_path.read_text(encoding="utf-8")
if 'GroundProbe.TotemSnapshot' not in d:
    # B2 has UnitByGuid after Snapshot; add the new handlers immediately after it.
    marker = '''        if (groundProbeCommand == "GroundProbe.UnitByGuid" && argumentCount >= 2
            && lua_isstring(L, 2)) {
            const std::string record = groundProbe::unitByGuid(lua_tostring(L, 2));
            lua_pushstring(L, record.c_str());
            return 1;
        }
'''
    bridge = '''        if (groundProbeCommand == "GroundProbe.ScopeByGuid" && argumentCount >= 2
            && lua_isstring(L, 2)) {
            const std::string record = groundProbe::scopeByGuid(lua_tostring(L, 2));
            lua_pushstring(L, record.c_str());
            return 1;
        }
        if (groundProbeCommand == "GroundProbe.TotemSnapshot") {
            std::string mode = "SELF";
            float range = 140.0f;
            if (argumentCount >= 2 && lua_isstring(L, 2)) mode = lua_tostring(L, 2);
            if (argumentCount >= 3 && lua_isnumber(L, 3))
                range = static_cast<float>(lua_tonumber(L, 3));
            const std::string record = groundProbe::totemSnapshot(mode, range);
            lua_pushstring(L, record.c_str());
            return 1;
        }
'''
    d = replace_once(d, marker, marker + bridge, "dllmain GroundProbe.UnitByGuid handler")
dll_path.write_text(d, encoding="utf-8", newline="\n")

checks = {
    h_path: ["scopeByGuid", "totemSnapshot"],
    cpp_path: [
        "kUnitFieldSummonedBy = 0x0C", "kUnitFieldCreatedBy = 0x0E",
        "kUnitAuraFirst = 0x2F", "kUnitCreatedBySpell = 0x92",
        "kCreatureTypeTotem = 11", "party", "raid",
        "std::string scopeByGuid", "std::string totemSnapshot",
        "vanilla1121_unitCreatureType(current)", "toTem" if False else "totemAuraCsv",
    ],
    dll_path: ["GroundProbe.ScopeByGuid", "GroundProbe.TotemSnapshot"],
}
for p, needles in checks.items():
    text = p.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"postcondition failed: {needle} missing from {p}")

print("GroundProbe B3.4 native totem owner/group snapshot: OK")
