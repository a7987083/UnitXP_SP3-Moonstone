#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 marker, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_unitxp_spellsearch.py <upstream-source-dir>")
    root = Path(sys.argv[1])
    h_path = root / "UnitXPDbc.h"
    cpp_path = root / "UnitXPDbc.cpp"
    dll_path = root / "dllmain.cpp"

    h = h_path.read_text(encoding="utf-8")
    cpp = cpp_path.read_text(encoding="utf-8")
    dll = dll_path.read_text(encoding="utf-8")

    h = replace_once(
        h,
        'bool isCommand(const std::string& cmd);\nint dispatch(void* L, const std::string& cmd, unsigned int id);',
        'bool isCommand(const std::string& cmd);\n'
        'bool isSearchCommand(const std::string& cmd);\n'
        'int dispatch(void* L, const std::string& cmd, unsigned int id);\n'
        'int dispatchSearch(void* L, const std::string& cmd, const std::string& query, unsigned int limit);',
        "UnitXPDbc.h declarations",
    )

    cpp = replace_once(
        cpp,
        '    const std::uint8_t* record(std::uint32_t id) const {\n'
        '        const auto it = byId.find(id);\n'
        '        if (it == byId.end()) return nullptr;\n'
        '        return bytes.data() + 20u + static_cast<std::size_t>(it->second) * recordSize;\n'
        '    }\n',
        '    const std::uint8_t* record(std::uint32_t id) const {\n'
        '        const auto it = byId.find(id);\n'
        '        if (it == byId.end()) return nullptr;\n'
        '        return bytes.data() + 20u + static_cast<std::size_t>(it->second) * recordSize;\n'
        '    }\n\n'
        '    const std::uint8_t* recordAt(std::uint32_t index) const {\n'
        '        if (!ready || index >= records) return nullptr;\n'
        '        return bytes.data() + 20u + static_cast<std::size_t>(index) * recordSize;\n'
        '    }\n',
        "DbcTable recordAt",
    )

    search_impl = r'''

std::string trimAsciiSpace(const std::string& value) {
    std::size_t begin = 0u;
    while (begin < value.size()) {
        const unsigned char c = static_cast<unsigned char>(value[begin]);
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
        ++begin;
    }
    std::size_t end = value.size();
    while (end > begin) {
        const unsigned char c = static_cast<unsigned char>(value[end - 1u]);
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
        --end;
    }
    return value.substr(begin, end - begin);
}

struct SpellSearchHit {
    std::uint32_t id = 0u;
    std::string name;
    std::string nameZhCN;
    std::string matchField;
    std::string matchType;
    int rank = 999;
};

int textMatchRank(const std::string& value, const std::string& loweredQuery,
                  int exactRank, int prefixRank, int containsRank,
                  std::string& matchType) {
    if (value.empty()) return 999;
    const std::string lowered = lowerAscii(value);
    if (lowered == loweredQuery) {
        matchType = "exact";
        return exactRank;
    }
    if (lowered.size() >= loweredQuery.size()
        && lowered.compare(0u, loweredQuery.size(), loweredQuery) == 0) {
        matchType = "prefix";
        return prefixRank;
    }
    if (lowered.find(loweredQuery) != std::string::npos) {
        matchType = "contains";
        return containsRank;
    }
    return 999;
}

int pushSpellSearch(void* L, const std::string& rawQuery, std::uint32_t limit) {
    const std::string query = trimAsciiSpace(rawQuery);
    if (query.empty()) return fail(L, "SpellSearch", "QUERY_REQUIRED");
    if (!gSpell.ensure("DBFilesClient\\Spell.dbc", 120u)) {
        return fail(L, "SpellSearch", gSpell.error);
    }

    if (limit < 1u) limit = 100u;
    if (limit > 500u) limit = 500u;
    const std::string loweredQuery = lowerAscii(query);
    std::vector<SpellSearchHit> hits;
    hits.reserve(64u);

    for (std::uint32_t i = 0u; i < gSpell.records; ++i) {
        const std::uint8_t* r = gSpell.recordAt(i);
        if (r == nullptr) continue;
        const std::string name = gSpell.fields > 120u ? gSpell.str(r, 120u) : std::string();
        const std::string nameZhCN = gSpell.fields > 124u ? gSpell.str(r, 124u) : std::string();

        SpellSearchHit hit;
        hit.id = gSpell.u32(r, 0u);
        hit.name = name;
        hit.nameZhCN = nameZhCN;

        std::string matchType;
        int rank = textMatchRank(nameZhCN, loweredQuery, 0, 1, 2, matchType);
        if (rank != 999) {
            hit.rank = rank;
            hit.matchField = "nameZhCN";
            hit.matchType = matchType;
        } else {
            rank = textMatchRank(name, loweredQuery, 3, 4, 5, matchType);
            if (rank == 999) continue;
            hit.rank = rank;
            hit.matchField = "name";
            hit.matchType = matchType;
        }
        hits.push_back(hit);
    }

    std::sort(hits.begin(), hits.end(), [](const SpellSearchHit& a, const SpellSearchHit& b) {
        if (a.rank != b.rank) return a.rank < b.rank;
        return a.id < b.id;
    });

    const std::size_t totalMatches = hits.size();
    const std::size_t emitCount = std::min<std::size_t>(totalMatches, static_cast<std::size_t>(limit));
    lua_newtable(L);
    for (std::size_t i = 0u; i < emitCount; ++i) {
        const SpellSearchHit& hit = hits[i];
        lua_pushnumber(L, static_cast<double>(i + 1u));
        lua_newtable(L);
        setNumber(L, "id", hit.id);
        setString(L, "name", hit.name);
        setString(L, "nameZhCN", hit.nameZhCN);
        setString(L, "matchField", hit.matchField);
        setString(L, "matchType", hit.matchType);
        lua_settable(L, -3);
    }
    lua_pushnumber(L, static_cast<double>(totalMatches));
    lua_pushboolean(L, totalMatches > emitCount ? 1 : 0);
    return 3;
}
'''

    cpp = replace_once(
        cpp,
        '\nint pushRadius(void* L, std::uint32_t id) {',
        search_impl + '\n\nint pushRadius(void* L, std::uint32_t id) {',
        "spell search implementation insertion",
    )

    cpp = replace_once(
        cpp,
        'int dispatch(void* L, const std::string& cmd, unsigned int id) {',
        'bool isSearchCommand(const std::string& cmd) {\n'
        '    return cmd == "spellsearch";\n'
        '}\n\n'
        'int dispatch(void* L, const std::string& cmd, unsigned int id) {',
        "isSearchCommand",
    )

    cpp = replace_once(
        cpp,
        '    if (cmd == "spellvisualeffect") return pushSpellVisualEffect(L, id);\n'
        '    return 0;\n'
        '}\n\n'
        '} // namespace unitxpDbc',
        '    if (cmd == "spellvisualeffect") return pushSpellVisualEffect(L, id);\n'
        '    return 0;\n'
        '}\n\n'
        'int dispatchSearch(void* L, const std::string& cmd, const std::string& query, unsigned int limit) {\n'
        '    if (cmd == "spellsearch") return pushSpellSearch(L, query, limit);\n'
        '    return 0;\n'
        '}\n\n'
        '} // namespace unitxpDbc',
        "dispatchSearch",
    )

    old_dispatch = '''        else if (unitxpDbc::isCommand(cmd) && lua_isnumber(L, 2)) {
            return unitxpDbc::dispatch(
                L,
                cmd,
                static_cast<unsigned int>(lua_tonumber(L, 2)));
        }
'''
    new_dispatch = '''        else if (unitxpDbc::isSearchCommand(cmd)) {
            if (!lua_isstring(L, 2)) {
                lua_pushnil(L);
                lua_pushstring(L, "UnitXP DBC SpellSearch: QUERY_REQUIRED");
                return 2;
            }
            unsigned int limit = 100u;
            if (lua_isnumber(L, 3)) {
                const double requested = lua_tonumber(L, 3);
                if (requested >= 1.0) {
                    limit = requested > 500.0 ? 500u : static_cast<unsigned int>(requested);
                }
            }
            return unitxpDbc::dispatchSearch(L, cmd, lua_tostring(L, 2), limit);
        }
        else if (unitxpDbc::isCommand(cmd) && lua_isnumber(L, 2)) {
            return unitxpDbc::dispatch(
                L,
                cmd,
                static_cast<unsigned int>(lua_tonumber(L, 2)));
        }
'''
    dll = replace_once(dll, old_dispatch, new_dispatch, "dllmain DBC dispatch")

    h_path.write_text(h, encoding="utf-8")
    cpp_path.write_text(cpp, encoding="utf-8")
    dll_path.write_text(dll, encoding="utf-8")

    checks = {
        "UnitXPDbc.h": ["isSearchCommand", "dispatchSearch"],
        "UnitXPDbc.cpp": ["pushSpellSearch", 'cmd == "spellsearch"', '"nameZhCN"', '"matchType"'],
        "dllmain.cpp": ["isSearchCommand", "dispatchSearch", "QUERY_REQUIRED"],
    }
    for filename, markers in checks.items():
        text = (root / filename).read_text(encoding="utf-8")
        for marker in markers:
            if marker not in text:
                raise RuntimeError(f"postcondition failed: {filename} missing {marker}")
    print("UnitXP SpellSearch patch applied successfully")
    subprocess.run([
        sys.executable,
        str(Path(__file__).with_name("apply_unitxp_creature_spell_link.py")),
        str(root),
    ], check=True)
    subprocess.run([
        sys.executable,
        str(Path(__file__).with_name("apply_unitxp_tooltip_fields.py")),
        str(root),
    ], check=True)


if __name__ == "__main__":
    main()
