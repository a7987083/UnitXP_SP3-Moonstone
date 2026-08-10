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

# Public API: relation is deliberately tri-state. Lua should suppress only FRIENDLY.
h = h_path.read_text(encoding="utf-8")
if "relationByGuid(" not in h:
    h = replace_once(
        h,
        "std::string status();\n",
        "std::string status();\nstd::string relationByGuid(const std::string& guidText);\n",
        "AutoRange.h status declaration",
    )
h_path.write_text(h, encoding="utf-8", newline="\n")

cpp = cpp_path.read_text(encoding="utf-8")
if '#include "Vanilla1121_functions.h"' not in cpp:
    cpp = replace_once(
        cpp,
        '#include "AutoRange.h"\n',
        '#include "AutoRange.h"\n#include "Vanilla1121_functions.h"\n',
        "AutoRange.cpp include",
    )
if "#include <limits>" not in cpp:
    cpp = replace_once(
        cpp,
        "#include <iomanip>\n",
        "#include <iomanip>\n#include <limits>\n",
        "AutoRange.cpp limits include",
    )

if "std::string relationByGuid(" not in cpp:
    marker = "\n} // namespace autoRange\n"
    pos = cpp.rfind(marker)
    if pos < 0:
        raise SystemExit("AutoRange.cpp final namespace marker missing")

    addition = r'''
namespace {

bool relationParseGuidBase(const std::string& text, std::size_t start,
                           unsigned base, std::uint64_t& value) {
    if (start >= text.size() || (base != 10u && base != 16u)) return false;
    std::uint64_t parsed = 0;
    for (std::size_t i = start; i < text.size(); ++i) {
        const char ch = text[i];
        unsigned digit = 0;
        if (ch >= '0' && ch <= '9') digit = static_cast<unsigned>(ch - '0');
        else if (ch >= 'A' && ch <= 'F') digit = 10u + static_cast<unsigned>(ch - 'A');
        else if (ch >= 'a' && ch <= 'f') digit = 10u + static_cast<unsigned>(ch - 'a');
        else return false;
        if (digit >= base) return false;
        if (parsed > (std::numeric_limits<std::uint64_t>::max() - digit) / base) return false;
        parsed = parsed * base + digit;
    }
    if (parsed == 0u) return false;
    value = parsed;
    return true;
}

bool relationNormalizeGuid(const std::string& input, std::string& text,
                           bool& explicitHex, bool& hasHexAlpha) {
    text.clear();
    for (char ch : input) {
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') text.push_back(ch);
    }
    if (text.empty()) return false;
    explicitHex = text.size() > 2u && text[0] == '0' && (text[1] == 'x' || text[1] == 'X');
    const std::size_t start = explicitHex ? 2u : 0u;
    if (start >= text.size()) return false;
    hasHexAlpha = false;
    for (std::size_t i = start; i < text.size(); ++i) {
        const char ch = text[i];
        if ((ch >= 'A' && ch <= 'F') || (ch >= 'a' && ch <= 'f')) hasHexAlpha = true;
        else if (ch < '0' || ch > '9') return false;
    }
    return true;
}

std::string relationHex64(std::uint64_t value) {
    std::ostringstream out;
    out << std::uppercase << std::hex << std::setw(16) << std::setfill('0') << value;
    return out.str();
}

const char* relationLabel(int reaction, int canAttack, bool self) {
    if (self) return "FRIENDLY";

    // Attackability is a strong hostile signal (including neutral/yellow units
    // that can actually be attacked). Reaction protects enemy players that are
    // not currently attackable because of PvP state.
    if (canAttack == 1) return "HOSTILE";
    if (reaction >= UNIT_REACTION_HATED && reaction <= UNIT_REACTION_UNFRIENDLY)
        return "HOSTILE";

    // Only an explicit friendly reaction is allowed to suppress AutoRange.
    // Neutral, unreadable and contradictory states intentionally remain UNKNOWN
    // so Lua will keep the danger visual instead of risking a false negative.
    if (reaction >= UNIT_REACTION_AMIABLE && reaction <= UNIT_REACTION_REVERED)
        return "FRIENDLY";
    return "UNKNOWN";
}

} // namespace

std::string relationByGuid(const std::string& guidText) {
    std::string normalized;
    bool explicitHex = false;
    bool hasHexAlpha = false;
    if (!relationNormalizeGuid(guidText, normalized, explicitHex, hasHexAlpha))
        return "R|UNKNOWN|-1|-1|-1|0000000000000000|GUID_INVALID";

    const std::size_t start = explicitHex ? 2u : 0u;
    std::uint64_t first = 0;
    std::uint64_t second = 0;
    bool haveFirst = false;
    bool haveSecond = false;
    if (explicitHex || hasHexAlpha) {
        haveFirst = relationParseGuidBase(normalized, start, 16u, first);
    } else {
        haveFirst = relationParseGuidBase(normalized, start, 10u, first);
        haveSecond = relationParseGuidBase(normalized, start, 16u, second) && second != first;
    }
    if (!haveFirst && !haveSecond)
        return "R|UNKNOWN|-1|-1|-1|0000000000000000|GUID_INVALID";

    std::uint64_t guid = 0;
    std::uint32_t object = 0;
    if (haveFirst) {
        object = vanilla1121_getVisiableObject(first);
        if (object != 0u && (object & 1u) == 0u) guid = first;
        else object = 0u;
    }
    if (object == 0u && haveSecond) {
        object = vanilla1121_getVisiableObject(second);
        if (object != 0u && (object & 1u) == 0u) guid = second;
        else object = 0u;
    }

    const std::uint64_t reportGuid = guid != 0u ? guid : (haveFirst ? first : second);
    if (object == 0u) {
        return std::string("R|UNKNOWN|-1|-1|-1|") + relationHex64(reportGuid)
            + "|NOT_VISIBLE";
    }

    const int objectType = vanilla1121_objectType(object);
    if (objectType != OBJECT_TYPE_Unit && objectType != OBJECT_TYPE_Player) {
        std::ostringstream out;
        out << "R|UNKNOWN|-1|-1|" << objectType << '|'
            << relationHex64(reportGuid) << "|NOT_UNIT";
        return out.str();
    }

    const std::uint64_t playerGuid = vanilla1121_unitGUID("player");
    const bool self = playerGuid != 0u && playerGuid == guid;
    const int reaction = self ? UNIT_REACTION_FRIENDLY : vanilla1121_unitReaction(object);
    const int canAttack = self ? 0 : vanilla1121_unitCanBeAttacked(object);
    const char* label = relationLabel(reaction, canAttack, self);

    const char* reason = "UNKNOWN_DEFAULT_SHOW";
    if (self) reason = "SELF";
    else if (std::strcmp(label, "HOSTILE") == 0) reason = "HOSTILE_SIGNAL";
    else if (std::strcmp(label, "FRIENDLY") == 0) reason = "FRIENDLY_REACTION";

    std::ostringstream out;
    out << "R|" << label << '|' << reaction << '|' << canAttack << '|'
        << objectType << '|' << relationHex64(guid) << '|' << reason;
    return out.str();
}
'''
    cpp = cpp[:pos] + addition + cpp[pos:]

cpp_path.write_text(cpp, encoding="utf-8", newline="\n")

# Lua bridge. UNIT_CASTEVENT already gives AutoRange the caster GUID, so this
# API is called only when a cast event matters; there is no per-frame 40-unit scan.
d = dll_path.read_text(encoding="utf-8")
if 'AutoRange.RelationByGuid' not in d:
    marker = '''        if (autoRangeCommand == "AutoRange.Resolve" && argumentCount >= 2
            && lua_isnumber(L, 2)) {
            const unsigned int spellId = static_cast<unsigned int>(lua_tonumber(L, 2));
            const std::string record = autoRange::resolve(spellId);
            lua_pushstring(L, record.c_str());
            return 1;
        }
'''
    bridge = '''        if (autoRangeCommand == "AutoRange.RelationByGuid" && argumentCount >= 2
            && lua_isstring(L, 2)) {
            const std::string record = autoRange::relationByGuid(lua_tostring(L, 2));
            lua_pushstring(L, record.c_str());
            return 1;
        }
'''
    d = replace_once(d, marker, marker + bridge, "dllmain AutoRange.Resolve handler")
dll_path.write_text(d, encoding="utf-8", newline="\n")

checks = {
    h_path: ["relationByGuid"],
    cpp_path: [
        '#include "Vanilla1121_functions.h"',
        "vanilla1121_unitReaction(object)",
        "vanilla1121_unitCanBeAttacked(object)",
        'return "FRIENDLY"',
        'return "UNKNOWN"',
        "std::string relationByGuid",
    ],
    dll_path: ["AutoRange.RelationByGuid", "autoRange::relationByGuid"],
}
for p, needles in checks.items():
    text = p.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"postcondition failed: {needle} missing from {p}")

print("AutoRange B3.3 native tri-state relation classifier: OK")
