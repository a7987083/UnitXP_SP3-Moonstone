#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
header_path = root / "GroundProbe.h"
cpp_path = root / "GroundProbe.cpp"
dll_path = root / "dllmain.cpp"

for p in (header_path, cpp_path, dll_path):
    if not p.is_file():
        raise SystemExit(f"missing required source: {p}")


def replace_once(text: str, needle: str, replacement: str, label: str) -> str:
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, got {count}")
    return text.replace(needle, replacement, 1)

# Header: add the GUID resolver declaration immediately before the namespace close.
h = header_path.read_text(encoding="utf-8")
if "unitByGuid(" not in h:
    marker = "\n} // namespace groundProbe\n"
    addition = (
        "\n// Resolves a SuperWoW caster GUID to a visible Unit/Player and returns\n"
        "// live world position plus player distance. Read-only diagnostic API.\n"
        "std::string unitByGuid(const std::string& guidText);\n"
    )
    h = replace_once(h, marker, addition + marker, "GroundProbe.h namespace marker")
header_path.write_text(h, encoding="utf-8", newline="\n")

# CPP include needed for overflow-safe GUID parsing.
c = cpp_path.read_text(encoding="utf-8")
if "#include <limits>" not in c:
    include_marker = "#include <iomanip>\n"
    c = replace_once(c, include_marker, include_marker + "#include <limits>\n", "GroundProbe.cpp include marker")

# Helper functions: accept 0x-prefixed hex, A-F hex, and decimal GUID strings.
if "parseGuidBase(" not in c:
    helper_marker = "bool descriptorPtr("
    pos = c.find(helper_marker)
    if pos < 0:
        raise SystemExit("GroundProbe.cpp: descriptorPtr marker not found")
    helpers = r'''bool parseGuidBase(const std::string& text, const std::size_t start,
                   const unsigned base, std::uint64_t& value) {
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

bool normalizeGuidText(const std::string& input, std::string& text, bool& explicitHex,
                       bool& hasHexAlpha) {
    text.clear();
    for (const char ch : input) {
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

'''
    c = c[:pos] + helpers + c[pos:]

# Public resolver. For an all-digit GUID, try decimal first and then hex; this makes
# the probe tolerant of SuperWoW builds that stringify GUIDs differently.
if "std::string unitByGuid(" not in c:
    end_marker = "\n} // namespace groundProbe\n"
    pos = c.rfind(end_marker)
    if pos < 0:
        raise SystemExit("GroundProbe.cpp: final namespace marker not found")
    resolver = r'''
std::string unitByGuid(const std::string& guidText) {
    if (!moonMarkerRuntimeGuard::enabled()) {
        return std::string("E|") + moonMarkerRuntimeGuard::statusCode() + "|"
            + moonMarkerRuntimeGuard::userMessage();
    }

    std::string normalized;
    bool explicitHex = false;
    bool hasHexAlpha = false;
    if (!normalizeGuidText(guidText, normalized, explicitHex, hasHexAlpha)) {
        return "E|GUID_INVALID|caster GUID could not be parsed";
    }

    const std::size_t start = explicitHex ? 2u : 0u;
    std::uint64_t first = 0;
    std::uint64_t second = 0;
    bool haveFirst = false;
    bool haveSecond = false;
    if (explicitHex || hasHexAlpha) {
        haveFirst = parseGuidBase(normalized, start, 16u, first);
    }
    else {
        haveFirst = parseGuidBase(normalized, start, 10u, first);
        haveSecond = parseGuidBase(normalized, start, 16u, second) && second != first;
    }
    if (!haveFirst && !haveSecond) {
        return "E|GUID_INVALID|caster GUID could not be parsed";
    }

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
    if (object == 0u) {
        const std::uint64_t reportGuid = haveFirst ? first : second;
        return std::string("E|GUID_NOT_VISIBLE|") + hex64(reportGuid);
    }

    std::uint32_t type = 0;
    if (!safeRead<std::uint32_t>(static_cast<std::uintptr_t>(object) + kObjectTypeOffset, type)) {
        return "E|UNIT_TYPE_UNREADABLE|object type is not readable";
    }
    if (type != OBJECT_TYPE_Unit && type != OBJECT_TYPE_Player) {
        return std::string("E|GUID_NOT_UNIT|") + hex64(guid);
    }

    const C3Vector pos = vanilla1121_unitPosition(object);
    if (!validPosition(pos)) {
        return "E|UNIT_POSITION_INVALID|unit position is not readable";
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

    std::uint32_t entry = 0;
    std::uint32_t descriptor = 0;
    if (descriptorPtr(object, descriptor)) descriptorU32(descriptor, kObjectFieldEntry, entry);

    const float xy = distanceXY(playerPos, pos);
    const float zdiff = std::fabs(playerPos.z - pos.z);
    std::ostringstream out;
    out.setf(std::ios::fixed);
    out << std::setprecision(3);
    out << "U|" << hex64(guid) << '|' << entry << '|' << type << '|'
        << pos.x << '|' << pos.y << '|' << pos.z << '|'
        << xy << '|' << zdiff << '|' << hex32(object);
    return out.str();
}
'''
    c = c[:pos] + resolver + c[pos:]
cpp_path.write_text(c, encoding="utf-8", newline="\n")

# DLL Lua bridge: insert immediately after the B1 Snapshot handler.
d = dll_path.read_text(encoding="utf-8")
if 'GroundProbe.UnitByGuid' not in d:
    snapshot_tail = (
        '            lua_pushstring(L, groundProbe::snapshot(range, includeGameObjects));\n'
        '            return 1;\n'
        '        }\n'
    )
    bridge = (
        '        if (groundProbeCommand == "GroundProbe.UnitByGuid" && argumentCount >= 2\n'
        '            && lua_isstring(L, 2)) {\n'
        '            const std::string record = groundProbe::unitByGuid(lua_tostring(L, 2));\n'
        '            lua_pushstring(L, record.c_str());\n'
        '            return 1;\n'
        '        }\n'
    )
    d = replace_once(d, snapshot_tail, snapshot_tail + bridge, "dllmain.cpp Snapshot handler")
d ll_removed = None
# Write the updated Lua bridge.
dll_path.write_text(d, encoding="utf-8", newline="\n")

# Postconditions: fail the workflow before compilation if injection did not land exactly.
checks = {
    header_path: ["unitByGuid"],
    cpp_path: ["parseGuidBase", "GUID_NOT_VISIBLE", "std::string unitByGuid"],
    dll_path: ["GroundProbe.UnitByGuid", "groundProbe::unitByGuid"],
}
for p, needles in checks.items():
    text = p.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"postcondition failed: {needle} missing from {p}")

print("GroundProbe B2 deterministic injection: OK")
