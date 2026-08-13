#!/usr/bin/env python3
from pathlib import Path
import sys


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 marker, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_unitxp_creature_spell_link.py <upstream-source-dir>")
    root = Path(sys.argv[1])
    cpp_path = root / "UnitXPDbc.cpp"
    cpp = cpp_path.read_text(encoding="utf-8")

    cpp = replace_once(
        cpp,
        'constexpr DWORD kMaxDbcBytes = 96u * 1024u * 1024u;\n',
        'constexpr DWORD kMaxDbcBytes = 96u * 1024u * 1024u;\n'
        'constexpr DWORD kMaxWdbBytes = 64u * 1024u * 1024u;\n',
        "WDB size limit",
    )

    helper = r'''

void collectNamedFiles(const std::string& directory, int depth,
                       const std::string& wantedLowerName,
                       std::vector<std::string>& files) {
    if (depth < 0) return;
    WIN32_FIND_DATAA data = {};
    HANDLE find = FindFirstFileA((directory + "\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return;
    do {
        const std::string name = data.cFileName;
        if (name == "." || name == "..") continue;
        const std::string full = directory + "\\" + name;
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            collectNamedFiles(full, depth - 1, wantedLowerName, files);
            continue;
        }
        if (lowerAscii(name) == wantedLowerName) files.push_back(full);
    } while (FindNextFileA(find, &data));
    FindClose(find);
}

bool readWholeDiskFile(const std::string& path, std::vector<std::uint8_t>& bytes) {
    HANDLE file = CreateFileA(path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0
        || size.QuadPart > static_cast<LONGLONG>(kMaxWdbBytes)) {
        CloseHandle(file);
        return false;
    }
    bytes.resize(static_cast<std::size_t>(size.QuadPart));
    DWORD totalRead = 0u;
    while (totalRead < bytes.size()) {
        const DWORD remaining = static_cast<DWORD>(bytes.size() - totalRead);
        DWORD read = 0u;
        if (!ReadFile(file, bytes.data() + totalRead, remaining, &read, nullptr) || read == 0u) {
            CloseHandle(file);
            bytes.clear();
            return false;
        }
        totalRead += read;
    }
    CloseHandle(file);
    return true;
}
'''
    cpp = replace_once(
        cpp,
        '\nint archivePriority(const std::string& path) {',
        helper + '\n\nint archivePriority(const std::string& path) {',
        "disk helper insertion",
    )

    cache_impl = r'''

bool readCStringBounded(const std::vector<std::uint8_t>& bytes,
                       std::size_t& pos, std::size_t end,
                       std::string& value) {
    if (pos >= end || end > bytes.size()) return false;
    const std::size_t begin = pos;
    while (pos < end && bytes[pos] != 0u) ++pos;
    if (pos >= end) return false;
    value.assign(reinterpret_cast<const char*>(bytes.data() + begin), pos - begin);
    ++pos;
    return true;
}

struct CreatureCacheRecord {
    std::uint32_t entry = 0u;
    std::string name[4];
    std::string subName;
    std::uint32_t typeFlags = 0u;
    std::uint32_t type = 0u;
    std::uint32_t petFamily = 0u;
    std::uint32_t rank = 0u;
    std::uint32_t unknown = 0u;
    std::uint32_t petSpellListId = 0u;
    std::uint32_t displayId = 0u;
    std::uint8_t civilian = 0u;
    std::uint8_t leader = 0u;
};

bool parseCreatureCacheFile(const std::string& path,
                            std::vector<CreatureCacheRecord>& out,
                            std::uint32_t& build,
                            std::string& locale) {
    std::vector<std::uint8_t> bytes;
    if (!readWholeDiskFile(path, bytes) || bytes.size() < 20u) return false;

    build = le32(bytes.data() + 4u);
    if (build < 4000u) return false; // This module targets Classic/Turtle 1.12 cache layouts.
    locale.assign(reinterpret_cast<const char*>(bytes.data() + 8u), 4u);
    for (char& c : locale) {
        if (c < 32 || c > 126) c = '?';
    }

    std::size_t pos = 20u; // signature, build, locale, recordSize, recordVersion
    std::size_t guard = 0u;
    while (pos + 8u <= bytes.size() && guard++ < 200000u) {
        const std::uint32_t entry = le32(bytes.data() + pos);
        pos += 4u;
        if (entry == 0u) break;
        const std::uint32_t entrySize = le32(bytes.data() + pos);
        pos += 4u;
        if (entrySize == 0u) break;
        const std::size_t recordStart = pos;
        const std::size_t recordEnd = recordStart + static_cast<std::size_t>(entrySize);
        if (recordEnd < recordStart || recordEnd > bytes.size()) return false;

        CreatureCacheRecord rec;
        rec.entry = entry;
        for (std::uint32_t i = 0u; i < 4u; ++i) {
            if (!readCStringBounded(bytes, pos, recordEnd, rec.name[i])) return false;
        }
        if (!readCStringBounded(bytes, pos, recordEnd, rec.subName)) return false;
        if (pos + 30u > recordEnd) return false;
        rec.typeFlags = le32(bytes.data() + pos); pos += 4u;
        rec.type = le32(bytes.data() + pos); pos += 4u;
        rec.petFamily = le32(bytes.data() + pos); pos += 4u;
        rec.rank = le32(bytes.data() + pos); pos += 4u;
        rec.unknown = le32(bytes.data() + pos); pos += 4u;
        rec.petSpellListId = le32(bytes.data() + pos); pos += 4u;
        rec.displayId = le32(bytes.data() + pos); pos += 4u;
        rec.civilian = bytes[pos++];
        rec.leader = bytes[pos++];
        out.push_back(rec);
        pos = recordEnd;
    }
    return !out.empty();
}

struct CreatureCacheTable {
    bool attempted = false;
    bool ready = false;
    std::vector<CreatureCacheRecord> rows;
    std::unordered_map<std::uint32_t, std::uint32_t> byEntry;
    std::uint32_t build = 0u;
    std::string locale;
    std::string source;
    std::string error;

    bool ensure() {
        if (attempted) return ready;
        attempted = true;

        char exePath[MAX_PATH] = {};
        const DWORD length = GetModuleFileNameA(nullptr, exePath, MAX_PATH);
        if (length == 0 || length >= MAX_PATH) {
            error = "NO_EXE_PATH";
            return false;
        }
        const std::string root = parentDirectory(std::string(exePath, length));
        std::vector<std::string> files;
        collectNamedFiles(root + "\\Cache\\WDB", 3, "creaturecache.wdb", files);
        if (files.empty()) {
            error = "NO_CREATURE_CACHE";
            return false;
        }
        std::sort(files.begin(), files.end());

        for (const std::string& path : files) {
            std::vector<CreatureCacheRecord> parsed;
            std::uint32_t fileBuild = 0u;
            std::string fileLocale;
            if (!parseCreatureCacheFile(path, parsed, fileBuild, fileLocale)) continue;
            if (build == 0u) build = fileBuild;
            if (locale.empty()) locale = fileLocale;
            if (source.empty()) source = fileLocale + "\\creaturecache.wdb";
            for (const CreatureCacheRecord& rec : parsed) {
                const auto it = byEntry.find(rec.entry);
                if (it == byEntry.end()) {
                    byEntry[rec.entry] = static_cast<std::uint32_t>(rows.size());
                    rows.push_back(rec);
                } else {
                    rows[it->second] = rec;
                }
            }
        }

        if (rows.empty()) {
            error = "NOT_FOUND_OR_BAD_WDB";
            return false;
        }
        ready = true;
        return true;
    }
};
'''
    cpp = replace_once(
        cpp,
        '\nstruct DbcTable {',
        cache_impl + '\n\nstruct DbcTable {',
        "creature cache implementation",
    )

    cpp = replace_once(
        cpp,
        'DbcTable gDuration;\nDbcTable gItemDisplay;',
        'DbcTable gDuration;\nDbcTable gCreatureSpellData;\nCreatureCacheTable gCreatureCache;\nDbcTable gItemDisplay;',
        "creature globals",
    )

    api_impl = r'''

int pushCreatureSpellData(void* L, std::uint32_t id) {
    int rc = 0;
    const std::uint8_t* r = requireRow(L, gCreatureSpellData, "CreatureSpellData",
        "DBFilesClient\\CreatureSpellData.dbc", 5u, id, rc);
    if (r == nullptr) return rc;
    lua_newtable(L);
    addMeta(L, "CreatureSpellData", gCreatureSpellData, id);
    for (std::uint32_t i = 0u; i < 4u; ++i) {
        const std::string key = std::string("spell") + static_cast<char>('1' + i);
        setNumber(L, key.c_str(), gCreatureSpellData.u32(r, 1u + i));
    }
    return 1;
}

int pushCreatureSpellSearch(void* L, std::uint32_t spellId) {
    if (spellId == 0u) return fail(L, "CreatureSpellSearch", "SPELL_REQUIRED");
    if (!gCreatureSpellData.ensure("DBFilesClient\\CreatureSpellData.dbc", 5u)) {
        return fail(L, "CreatureSpellSearch", gCreatureSpellData.error);
    }
    lua_newtable(L);
    std::uint32_t emitted = 0u;
    std::uint32_t total = 0u;
    for (std::uint32_t i = 0u; i < gCreatureSpellData.records; ++i) {
        const std::uint8_t* r = gCreatureSpellData.recordAt(i);
        if (r == nullptr) continue;
        for (std::uint32_t slot = 0u; slot < 4u; ++slot) {
            if (gCreatureSpellData.u32(r, 1u + slot) != spellId) continue;
            ++total;
            if (emitted < 500u) {
                ++emitted;
                lua_pushnumber(L, emitted);
                lua_newtable(L);
                setNumber(L, "dataId", gCreatureSpellData.u32(r, 0u));
                setNumber(L, "slot", slot + 1u);
                setNumber(L, "spellId", spellId);
                setString(L, "dbcSource", gCreatureSpellData.source);
                lua_settable(L, -3);
            }
            break;
        }
    }
    lua_pushnumber(L, total);
    lua_pushboolean(L, total > emitted ? 1 : 0);
    return 3;
}

int pushCreatureBySpell(void* L, std::uint32_t spellId) {
    if (spellId == 0u) return fail(L, "CreatureBySpell", "SPELL_REQUIRED");
    if (!gCreatureSpellData.ensure("DBFilesClient\\CreatureSpellData.dbc", 5u)) {
        return fail(L, "CreatureBySpell", gCreatureSpellData.error);
    }
    if (!gCreatureCache.ensure()) {
        return fail(L, "CreatureBySpell", gCreatureCache.error);
    }

    lua_newtable(L);
    std::uint32_t emitted = 0u;
    std::uint32_t total = 0u;
    for (const CreatureCacheRecord& rec : gCreatureCache.rows) {
        if (rec.petSpellListId == 0u) continue;
        const std::uint8_t* data = gCreatureSpellData.record(rec.petSpellListId);
        if (data == nullptr) continue;
        std::uint32_t matchedSlot = 0u;
        for (std::uint32_t slot = 0u; slot < 4u; ++slot) {
            if (gCreatureSpellData.u32(data, 1u + slot) == spellId) {
                matchedSlot = slot + 1u;
                break;
            }
        }
        if (matchedSlot == 0u) continue;
        ++total;
        if (emitted >= 500u) continue;
        ++emitted;
        lua_pushnumber(L, emitted);
        lua_newtable(L);
        setNumber(L, "entry", rec.entry);
        setString(L, "name", rec.name[0]);
        setString(L, "name2", rec.name[1]);
        setString(L, "name3", rec.name[2]);
        setString(L, "name4", rec.name[3]);
        setString(L, "subName", rec.subName);
        setNumber(L, "typeFlags", rec.typeFlags);
        setNumber(L, "creatureType", rec.type);
        setNumber(L, "petFamily", rec.petFamily);
        setNumber(L, "rank", rec.rank);
        setNumber(L, "petSpellListId", rec.petSpellListId);
        setNumber(L, "displayId", rec.displayId);
        setNumber(L, "civilian", rec.civilian);
        setNumber(L, "leader", rec.leader);
        setNumber(L, "slot", matchedSlot);
        setNumber(L, "spellId", spellId);
        setString(L, "relationSource", "CreatureSpellData.dbc + creaturecache.wdb");
        setString(L, "cacheSource", gCreatureCache.source);
        setNumber(L, "cacheBuild", gCreatureCache.build);
        setString(L, "cacheLocale", gCreatureCache.locale);
        lua_settable(L, -3);
    }
    lua_pushnumber(L, total);
    lua_pushboolean(L, total > emitted ? 1 : 0);
    return 3;
}
'''
    cpp = replace_once(
        cpp,
        '\nint pushRadius(void* L, std::uint32_t id) {',
        api_impl + '\n\nint pushRadius(void* L, std::uint32_t id) {',
        "creature API insertion",
    )

    cpp = replace_once(
        cpp,
        '        || cmd == "spellduration"\n        || cmd == "itemdisplayinfo"',
        '        || cmd == "spellduration"\n'
        '        || cmd == "creaturespelldata"\n'
        '        || cmd == "creaturespellsearch"\n'
        '        || cmd == "creaturebyspell"\n'
        '        || cmd == "itemdisplayinfo"',
        "command registration",
    )

    cpp = replace_once(
        cpp,
        '    if (cmd == "spellduration") return pushDuration(L, id);\n'
        '    if (cmd == "itemdisplayinfo") return pushItemDisplay(L, id);',
        '    if (cmd == "spellduration") return pushDuration(L, id);\n'
        '    if (cmd == "creaturespelldata") return pushCreatureSpellData(L, id);\n'
        '    if (cmd == "creaturespellsearch") return pushCreatureSpellSearch(L, id);\n'
        '    if (cmd == "creaturebyspell") return pushCreatureBySpell(L, id);\n'
        '    if (cmd == "itemdisplayinfo") return pushItemDisplay(L, id);',
        "dispatch registration",
    )

    cpp_path.write_text(cpp, encoding="utf-8")

    checks = [
        'DBFilesClient\\\\CreatureSpellData.dbc',
        'pushCreatureSpellData',
        'pushCreatureSpellSearch',
        'pushCreatureBySpell',
        'creaturecache.wdb',
        'cmd == "creaturespelldata"',
        'cmd == "creaturebyspell"',
        'CreatureSpellData.dbc + creaturecache.wdb',
    ]
    final = cpp_path.read_text(encoding="utf-8")
    for marker in checks:
        if marker not in final:
            raise RuntimeError(f"postcondition failed: missing {marker}")
    print("UnitXP CreatureSpellData + creaturecache static link patch applied successfully")


if __name__ == "__main__":
    main()
