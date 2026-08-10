#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
make_path = root / "Makefile"
dll_path = root / "dllmain.cpp"
for p in (make_path, dll_path):
    if not p.is_file():
        raise SystemExit(f"missing required source: {p}")


def replace_once(text: str, needle: str, replacement: str, label: str) -> str:
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, got {count}")
    return text.replace(needle, replacement, 1)

header = r'''#pragma once

#include <string>

namespace unitxpDbc {

bool isCommand(const std::string& cmd);
int dispatch(void* L, const std::string& cmd, unsigned int id);

} // namespace unitxpDbc
'''

cpp = r'''#include "UnitXPDbc.h"
#include "Vanilla1121_functions.h"

#include <Windows.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

namespace unitxpDbc {
namespace {

// Same client-side Storm/MPQ entry points already used by AutoRange B3.x.
// No hook, worker thread, timer, or frame callback is installed here.
constexpr std::uintptr_t kSFileOpenArchiveAddress = 0x00648DD0u;
constexpr std::uintptr_t kSFileOpenFileExAddress = 0x006477C0u;
constexpr std::uintptr_t kSFileReadFileAddress = 0x00648460u;
constexpr std::uintptr_t kSFileGetFileSizeAddress = 0x006487F0u;
constexpr std::uintptr_t kSFileCloseFileAddress = 0x00648730u;
constexpr std::uintptr_t kSFileCloseArchiveAddress = 0x00648EF0u;
constexpr DWORD kInvalidFileSize = 0xFFFFFFFFu;
constexpr DWORD kMaxDbcBytes = 96u * 1024u * 1024u;

using SFileOpenArchiveProc = BOOL (__stdcall*)(const char*, DWORD, DWORD, void**);
using SFileOpenFileExProc = BOOL (__stdcall*)(void*, const char*, DWORD, void**);
using SFileReadFileProc = BOOL (__stdcall*)(void*, void*, DWORD, DWORD*, void*, DWORD);
using SFileGetFileSizeProc = DWORD (__stdcall*)(void*, DWORD*);
using SFileCloseFileProc = BOOL (__stdcall*)(void*);
using SFileCloseArchiveProc = BOOL (__stdcall*)(void*);

std::string lowerAscii(std::string value) {
    for (char& c : value) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return value;
}

std::string parentDirectory(std::string path) {
    for (char& c : path) if (c == '/') c = '\\';
    const std::size_t slash = path.find_last_of('\\');
    return slash == std::string::npos ? std::string(".") : path.substr(0, slash);
}

std::string baseName(std::string path) {
    for (char& c : path) if (c == '/') c = '\\';
    const std::size_t slash = path.find_last_of('\\');
    return slash == std::string::npos ? path : path.substr(slash + 1u);
}

void collectMpqArchives(const std::string& directory, int depth,
                        std::vector<std::string>& archives) {
    if (depth < 0) return;
    WIN32_FIND_DATAA data = {};
    HANDLE find = FindFirstFileA((directory + "\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return;
    do {
        const std::string name = data.cFileName;
        if (name == "." || name == "..") continue;
        const std::string full = directory + "\\" + name;
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            collectMpqArchives(full, depth - 1, archives);
            continue;
        }
        const std::string lowered = lowerAscii(name);
        if (lowered.size() >= 4u
            && lowered.compare(lowered.size() - 4u, 4u, ".mpq") == 0) {
            archives.push_back(full);
        }
    } while (FindNextFileA(find, &data));
    FindClose(find);
}

int archivePriority(const std::string& path) {
    const std::string name = lowerAscii(baseName(path));
    if (name == "patch.mpq") return 1000;
    if (name.size() == 11u && name.compare(0, 6, "patch-") == 0
        && name.compare(7, 4, ".mpq") == 0) {
        const char ch = name[6];
        if (ch >= '0' && ch <= '9') return 1001 + (ch - '0');
        if (ch >= 'a' && ch <= 'z') return 1011 + (ch - 'a');
    }
    // Locale/custom patch names still outrank base archives.
    if (name.compare(0, 6, "patch-") == 0) return 900;
    if (name == "dbc.mpq") return 100;
    return 0;
}

bool readFileFromArchive(const std::string& archivePath, const char* internalPath,
                         std::vector<std::uint8_t>& bytes) {
    const auto openArchive = reinterpret_cast<SFileOpenArchiveProc>(kSFileOpenArchiveAddress);
    const auto openFile = reinterpret_cast<SFileOpenFileExProc>(kSFileOpenFileExAddress);
    const auto readFile = reinterpret_cast<SFileReadFileProc>(kSFileReadFileAddress);
    const auto getFileSize = reinterpret_cast<SFileGetFileSizeProc>(kSFileGetFileSizeAddress);
    const auto closeFile = reinterpret_cast<SFileCloseFileProc>(kSFileCloseFileAddress);
    const auto closeArchive = reinterpret_cast<SFileCloseArchiveProc>(kSFileCloseArchiveAddress);

    void* archive = nullptr;
    if (!openArchive(archivePath.c_str(), 0, 0, &archive) || archive == nullptr) return false;
    void* file = nullptr;
    if (!openFile(archive, internalPath, 0, &file) || file == nullptr) {
        closeArchive(archive);
        return false;
    }
    DWORD high = 0;
    const DWORD size = getFileSize(file, &high);
    if (size == kInvalidFileSize || high != 0 || size < 20u || size > kMaxDbcBytes) {
        closeFile(file);
        closeArchive(archive);
        return false;
    }
    bytes.resize(size);
    DWORD read = 0;
    const BOOL ok = readFile(file, bytes.data(), size, &read, nullptr, 0);
    closeFile(file);
    closeArchive(archive);
    if (!ok || read != size) {
        bytes.clear();
        return false;
    }
    return true;
}

const std::vector<std::string>& clientArchives() {
    // Deliberately lazy: even the Data directory is not scanned until the first DBC API call.
    static bool attempted = false;
    static std::vector<std::string> archives;
    if (attempted) return archives;
    attempted = true;

    char exePath[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameA(nullptr, exePath, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return archives;
    collectMpqArchives(parentDirectory(std::string(exePath, length)) + "\\Data", 2, archives);
    std::sort(archives.begin(), archives.end(), [](const std::string& a, const std::string& b) {
        const int ap = archivePriority(a);
        const int bp = archivePriority(b);
        if (ap != bp) return ap > bp;
        return lowerAscii(a) > lowerAscii(b);
    });
    archives.erase(std::unique(archives.begin(), archives.end(),
        [](const std::string& a, const std::string& b) {
            return lowerAscii(a) == lowerAscii(b);
        }), archives.end());
    return archives;
}

std::uint32_t le32(const std::uint8_t* p) {
    return static_cast<std::uint32_t>(p[0])
        | (static_cast<std::uint32_t>(p[1]) << 8u)
        | (static_cast<std::uint32_t>(p[2]) << 16u)
        | (static_cast<std::uint32_t>(p[3]) << 24u);
}

struct DbcTable {
    bool attempted = false;
    bool ready = false;
    std::vector<std::uint8_t> bytes;
    std::unordered_map<std::uint32_t, std::uint32_t> byId;
    std::uint32_t records = 0u;
    std::uint32_t fields = 0u;
    std::uint32_t recordSize = 0u;
    std::uint32_t stringSize = 0u;
    std::size_t stringStart = 0u;
    std::string source;
    std::string error;

    bool ensure(const char* internalPath, std::uint32_t minimumFields) {
        if (attempted) return ready;
        attempted = true;
        const std::vector<std::string>& archives = clientArchives();
        if (archives.empty()) {
            error = "NO_MPQ";
            return false;
        }
        for (const std::string& archive : archives) {
            if (readFileFromArchive(archive, internalPath, bytes)) {
                source = baseName(archive);
                break;
            }
        }
        if (bytes.size() < 20u || std::memcmp(bytes.data(), "WDBC", 4u) != 0) {
            error = "NOT_FOUND_OR_BAD_WDBC";
            return false;
        }
        records = le32(bytes.data() + 4u);
        fields = le32(bytes.data() + 8u);
        recordSize = le32(bytes.data() + 12u);
        stringSize = le32(bytes.data() + 16u);
        if (records == 0u || fields < minimumFields || recordSize < fields * 4u) {
            error = "DBC_SCHEMA";
            return false;
        }
        const std::uint64_t recordBytes = static_cast<std::uint64_t>(records) * recordSize;
        const std::uint64_t total = 20ull + recordBytes + stringSize;
        if (total > bytes.size()) {
            error = "DBC_TRUNCATED";
            return false;
        }
        stringStart = 20u + static_cast<std::size_t>(recordBytes);
        byId.reserve(records);
        for (std::uint32_t i = 0u; i < records; ++i) {
            const std::uint8_t* row = bytes.data() + 20u + static_cast<std::size_t>(i) * recordSize;
            byId[le32(row)] = i;
        }
        ready = true;
        return true;
    }

    const std::uint8_t* record(std::uint32_t id) const {
        const auto it = byId.find(id);
        if (it == byId.end()) return nullptr;
        return bytes.data() + 20u + static_cast<std::size_t>(it->second) * recordSize;
    }

    std::uint32_t u32(const std::uint8_t* row, std::uint32_t field) const {
        if (row == nullptr || field >= fields || (field + 1u) * 4u > recordSize) return 0u;
        return le32(row + field * 4u);
    }

    std::int32_t i32(const std::uint8_t* row, std::uint32_t field) const {
        return static_cast<std::int32_t>(u32(row, field));
    }

    float f32(const std::uint8_t* row, std::uint32_t field) const {
        const std::uint32_t bits = u32(row, field);
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        return value;
    }

    std::string str(const std::uint8_t* row, std::uint32_t field) const {
        const std::uint32_t offset = u32(row, field);
        if (offset >= stringSize || stringStart + offset >= bytes.size()) return std::string();
        const char* begin = reinterpret_cast<const char*>(bytes.data() + stringStart + offset);
        const std::size_t maxLength = static_cast<std::size_t>(stringSize - offset);
        std::size_t length = 0u;
        while (length < maxLength && begin[length] != '\0') ++length;
        return std::string(begin, length);
    }
};

DbcTable gSpell;
DbcTable gRadius;
DbcTable gRange;
DbcTable gDuration;
DbcTable gItemDisplay;
DbcTable gSpellVisual;
DbcTable gSpellVisualKit;
DbcTable gSpellVisualEffect;

void setNumber(void* L, const char* key, double value) {
    lua_pushstring(L, key);
    lua_pushnumber(L, value);
    lua_settable(L, -3);
}

void setString(void* L, const char* key, const std::string& value) {
    lua_pushstring(L, key);
    lua_pushstring(L, value.c_str());
    lua_settable(L, -3);
}

void addMeta(void* L, const char* dbc, const DbcTable& table, std::uint32_t id) {
    setNumber(L, "id", id);
    setString(L, "dbc", dbc);
    setString(L, "source", table.source);
    setNumber(L, "fieldCount", table.fields);
    setNumber(L, "recordSize", table.recordSize);
}

int fail(void* L, const char* dbc, const std::string& error) {
    lua_pushnil(L);
    const std::string message = std::string("UnitXP DBC ") + dbc + ": " + error;
    lua_pushstring(L, message.c_str());
    return 2;
}

const std::uint8_t* requireRow(void* L, DbcTable& table, const char* dbc,
                               const char* path, std::uint32_t minFields,
                               std::uint32_t id, int& returnCount) {
    if (!table.ensure(path, minFields)) {
        returnCount = fail(L, dbc, table.error);
        return nullptr;
    }
    const std::uint8_t* row = table.record(id);
    if (row == nullptr) {
        returnCount = fail(L, dbc, "ID_NOT_FOUND");
        return nullptr;
    }
    returnCount = 0;
    return row;
}

int pushSpell(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gSpell, "Spell", "DBFilesClient\\Spell.dbc", 120u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "Spell", gSpell, id);
    setNumber(L, "school", gSpell.u32(r, 1u));
    setNumber(L, "category", gSpell.u32(r, 2u));
    setNumber(L, "dispelType", gSpell.u32(r, 4u));
    setNumber(L, "mechanic", gSpell.u32(r, 5u));
    setNumber(L, "attributes", gSpell.u32(r, 6u));
    setNumber(L, "attributesEx", gSpell.u32(r, 7u));
    setNumber(L, "attributesEx2", gSpell.u32(r, 8u));
    setNumber(L, "attributesEx3", gSpell.u32(r, 9u));
    setNumber(L, "attributesEx4", gSpell.u32(r, 10u));
    setNumber(L, "castingTimeIndex", gSpell.u32(r, 18u));
    setNumber(L, "recoveryTime", gSpell.u32(r, 19u));
    setNumber(L, "categoryRecoveryTime", gSpell.u32(r, 20u));
    setNumber(L, "durationIndex", gSpell.u32(r, 30u));
    setNumber(L, "powerType", gSpell.u32(r, 31u));
    setNumber(L, "manaCost", gSpell.u32(r, 32u));
    setNumber(L, "rangeIndex", gSpell.u32(r, 36u));
    setNumber(L, "speed", gSpell.f32(r, 37u));
    setNumber(L, "stackAmount", gSpell.u32(r, 39u));
    for (std::uint32_t i = 0u; i < 3u; ++i) {
        const std::string suffix(1, static_cast<char>('1' + i));
        setNumber(L, (std::string("effect") + suffix).c_str(), gSpell.u32(r, 61u + i));
        setNumber(L, (std::string("targetA") + suffix).c_str(), gSpell.u32(r, 85u + i));
        setNumber(L, (std::string("targetB") + suffix).c_str(), gSpell.u32(r, 88u + i));
        setNumber(L, (std::string("radiusIndex") + suffix).c_str(), gSpell.u32(r, 91u + i));
        setNumber(L, (std::string("miscValue") + suffix).c_str(), gSpell.u32(r, 106u + i));
        setNumber(L, (std::string("triggerSpell") + suffix).c_str(), gSpell.u32(r, 109u + i));
    }
    setNumber(L, "spellVisual1", gSpell.u32(r, 115u));
    setNumber(L, "spellVisual2", gSpell.u32(r, 116u));
    setNumber(L, "spellIconID", gSpell.u32(r, 117u));
    setNumber(L, "activeIconID", gSpell.u32(r, 118u));
    setNumber(L, "spellPriority", gSpell.u32(r, 119u));
    if (gSpell.fields > 120u) setString(L, "name", gSpell.str(r, 120u));
    return 1;
}

int pushRadius(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gRadius, "SpellRadius", "DBFilesClient\\SpellRadius.dbc", 4u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "SpellRadius", gRadius, id);
    setNumber(L, "radius", gRadius.f32(r, 1u));
    setNumber(L, "radiusPerLevel", gRadius.f32(r, 2u));
    setNumber(L, "radiusMax", gRadius.f32(r, 3u));
    return 1;
}

int pushRange(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gRange, "SpellRange", "DBFilesClient\\SpellRange.dbc", 4u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "SpellRange", gRange, id);
    setNumber(L, "rangeMin", gRange.f32(r, 1u));
    setNumber(L, "rangeMax", gRange.f32(r, 2u));
    setNumber(L, "flags", gRange.u32(r, 3u));
    if (gRange.fields > 4u) setString(L, "name", gRange.str(r, 4u));
    if (gRange.fields > 13u) setString(L, "shortName", gRange.str(r, 13u));
    return 1;
}

int pushDuration(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gDuration, "SpellDuration", "DBFilesClient\\SpellDuration.dbc", 4u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "SpellDuration", gDuration, id);
    setNumber(L, "duration", gDuration.i32(r, 1u));
    setNumber(L, "durationPerLevel", gDuration.i32(r, 2u));
    setNumber(L, "maxDuration", gDuration.i32(r, 3u));
    return 1;
}

int pushItemDisplay(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gItemDisplay, "ItemDisplayInfo", "DBFilesClient\\ItemDisplayInfo.dbc", 6u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "ItemDisplayInfo", gItemDisplay, id);
    setString(L, "modelName1", gItemDisplay.str(r, 1u));
    setString(L, "modelName2", gItemDisplay.str(r, 2u));
    setString(L, "modelTexture1", gItemDisplay.str(r, 3u));
    setString(L, "modelTexture2", gItemDisplay.str(r, 4u));
    setString(L, "inventoryIcon", gItemDisplay.str(r, 5u));
    if (gItemDisplay.fields > 9u) setNumber(L, "flags", gItemDisplay.u32(r, 9u));
    if (gItemDisplay.fields > 10u) setNumber(L, "spellVisualId", gItemDisplay.u32(r, 10u));
    if (gItemDisplay.fields > 11u) setNumber(L, "groupSoundIndex", gItemDisplay.u32(r, 11u));
    if (gItemDisplay.fields > 12u) setNumber(L, "helmetGeosetVisId1", gItemDisplay.u32(r, 12u));
    if (gItemDisplay.fields > 13u) setNumber(L, "helmetGeosetVisId2", gItemDisplay.u32(r, 13u));
    return 1;
}

int pushSpellVisual(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gSpellVisual, "SpellVisual", "DBFilesClient\\SpellVisual.dbc", 16u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "SpellVisual", gSpellVisual, id);
    static const char* keys[15] = {
        "precastKit", "castKit", "impactKit", "stateKit", "channelKit",
        "hasMissile", "missileModel", "missilePathType", "missileDestinationAttachment",
        "missileSound", "hasArea", "areaModel", "areaKit", "animEventSoundID", "flags"
    };
    for (std::uint32_t i = 0u; i < 15u; ++i) setNumber(L, keys[i], gSpellVisual.u32(r, i + 1u));
    return 1;
}

int pushSpellVisualKit(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gSpellVisualKit, "SpellVisualKit", "DBFilesClient\\SpellVisualKit.dbc", 35u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "SpellVisualKit", gSpellVisualKit, id);
    static const char* keys[34] = {
        "kitType", "animID", "headEffect", "chestEffect", "baseEffect", "leftHandEffect",
        "rightHandEffect", "breathEffect", "specialEffect1", "specialEffect2", "specialEffect3",
        "worldEffect", "soundID", "shakeID", "charProc1", "charProc2", "charProc3", "charProc4",
        "charParamZero1", "charParamZero2", "charParamZero3", "charParamZero4",
        "charParamOne1", "charParamOne2", "charParamOne3", "charParamOne4",
        "charParamTwo1", "charParamTwo2", "charParamTwo3", "charParamTwo4",
        "charParamThree1", "charParamThree2", "charParamThree3", "charParamThree4"
    };
    for (std::uint32_t i = 0u; i < 34u; ++i) setNumber(L, keys[i], gSpellVisualKit.u32(r, i + 1u));
    return 1;
}

int pushSpellVisualEffect(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gSpellVisualEffect, "SpellVisualEffectName", "DBFilesClient\\SpellVisualEffectName.dbc", 5u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "SpellVisualEffectName", gSpellVisualEffect, id);
    setString(L, "name", gSpellVisualEffect.str(r, 1u));
    setString(L, "fileName", gSpellVisualEffect.str(r, 2u));
    setNumber(L, "specialAttachPoint", gSpellVisualEffect.u32(r, 3u));
    setNumber(L, "scale", gSpellVisualEffect.f32(r, 4u));
    return 1;
}

} // namespace

bool isCommand(const std::string& cmd) {
    return cmd == "spell"
        || cmd == "spellradius"
        || cmd == "spellrange"
        || cmd == "spellduration"
        || cmd == "itemdisplayinfo"
        || cmd == "spellvisual"
        || cmd == "spellvisualkit"
        || cmd == "spellvisualeffect";
}

int dispatch(void* L, const std::string& cmd, unsigned int id) {
    if (cmd == "spell") return pushSpell(L, id);
    if (cmd == "spellradius") return pushRadius(L, id);
    if (cmd == "spellrange") return pushRange(L, id);
    if (cmd == "spellduration") return pushDuration(L, id);
    if (cmd == "itemdisplayinfo") return pushItemDisplay(L, id);
    if (cmd == "spellvisual") return pushSpellVisual(L, id);
    if (cmd == "spellvisualkit") return pushSpellVisualKit(L, id);
    if (cmd == "spellvisualeffect") return pushSpellVisualEffect(L, id);
    return 0;
}

} // namespace unitxpDbc
'''

(root / "UnitXPDbc.h").write_text(header, encoding="utf-8", newline="\n")
(root / "UnitXPDbc.cpp").write_text(cpp, encoding="utf-8", newline="\n")

m = make_path.read_text(encoding="utf-8")
if "UnitXPDbc.cpp" not in m:
    m = replace_once(m, "            AutoRange.cpp \\\n", "            AutoRange.cpp \\\n            UnitXPDbc.cpp \\\n", "Makefile AutoRange source")
make_path.write_text(m, encoding="utf-8", newline="\n")

d = dll_path.read_text(encoding="utf-8-sig")
if '#include "UnitXPDbc.h"' not in d:
    d = replace_once(d, '#include "AutoRange.h"\n', '#include "AutoRange.h"\n#include "UnitXPDbc.h"\n', "dllmain AutoRange include")

if 'unitxpDbc::dispatch' not in d:
    marker = "    }\n    return p_original_UnitXP(L);\n}"
    bridge = r'''        // DBC fusion is deliberately last in the legacy command chain.
        // Existing UnitXP commands return before reaching this point, so they gain no
        // per-call DBC work. The DBC module itself scans/loads only after one of these
        // explicit commands is called.
        else if (unitxpDbc::isCommand(cmd) && lua_isnumber(L, 2)) {
            return unitxpDbc::dispatch(
                L,
                cmd,
                static_cast<unsigned int>(lua_tonumber(L, 2)));
        }
'''
    d = replace_once(d, marker, bridge + marker, "dllmain final UnitXP return")
dll_path.write_text(d, encoding="utf-8", newline="\n")

checks = {
    make_path: ["UnitXPDbc.cpp"],
    dll_path: ['#include "UnitXPDbc.h"', "unitxpDbc::dispatch", "unitxpDbc::isCommand"],
    root / "UnitXPDbc.cpp": [
        'cmd == "spell"', 'cmd == "spellradius"', 'cmd == "spellrange"',
        'cmd == "spellduration"', 'cmd == "itemdisplayinfo"',
        'cmd == "spellvisual"', 'cmd == "spellvisualkit"', 'cmd == "spellvisualeffect"',
        'DBFilesClient\\\\SpellVisual.dbc', 'DBFilesClient\\\\SpellVisualKit.dbc',
        'DBFilesClient\\\\SpellVisualEffectName.dbc',
        "static bool attempted = false;",
    ],
}
for p, needles in checks.items():
    text = p.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"postcondition failed: {needle} missing from {p}")

print("UnitXP DBC fusion B1 deterministic injection: OK")
