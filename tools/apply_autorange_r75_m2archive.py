#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
scanner = root / "MoonMarkerM2Scanner.cpp"
header = root / "MoonMarkerM2Scanner.h"
dllmain = root / "dllmain.cpp"
for p in (scanner, header, dllmain):
    if not p.exists():
        raise SystemExit(f"missing required source: {p}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)

s = scanner.read_text(encoding="utf-8")
s = replace_once(s,
'''#include <string>\n#include <unordered_set>\n#include <vector>''',
'''#include <string>\n#include <unordered_map>\n#include <unordered_set>\n#include <vector>''',
"scanner include unordered_map")

s = replace_once(s,
'''std::vector<std::string> gArchives;\nstd::vector<std::string> gResults;\nstd::unordered_set<std::string> gSeen;''',
'''std::vector<std::string> gArchives;\nstd::vector<std::string> gResults;\nstd::unordered_set<std::string> gSeen;\nstd::unordered_map<std::string, std::string> gSourceByPath;''',
"scanner source map")

s = replace_once(s,
'''void addResult(std::string path) {\n    if (gResults.size() >= kMaxResults) return;\n    path = trim(normalizeSlashes(path));\n    if (!safeModelPath(path)) return;\n    const std::string key = lowerAscii(path);\n    if (gSeen.insert(key).second) gResults.push_back(path);\n}\n\nvoid parseListfile(const char* data, std::size_t size) {\n    std::size_t start = 0;\n    for (std::size_t i = 0; i <= size; ++i) {\n        if (i == size || data[i] == '\\n' || data[i] == '\\0') {\n            if (i > start) addResult(std::string(data + start, data + i));\n            start = i + 1;\n        }\n    }\n}''',
'''void addResult(std::string path, const std::string& source) {\n    if (gResults.size() >= kMaxResults) return;\n    path = trim(normalizeSlashes(path));\n    if (!safeModelPath(path)) return;\n    const std::string key = lowerAscii(path);\n    if (gSeen.insert(key).second) {\n        gResults.push_back(path);\n        gSourceByPath[key] = source;\n    }\n}\n\nvoid addResult(std::string path) {\n    addResult(path, "LOOSE");\n}\n\nvoid parseListfile(const char* data, std::size_t size, const std::string& source) {\n    std::size_t start = 0;\n    for (std::size_t i = 0; i <= size; ++i) {\n        if (i == size || data[i] == '\\n' || data[i] == '\\0') {\n            if (i > start) addResult(std::string(data + start, data + i), source);\n            start = i + 1;\n        }\n    }\n}''',
"scanner result/source functions")

s = replace_once(s,
'''void parseTextFile(const std::string& path) {\n    std::ifstream input(path, std::ios::binary);''',
'''void parseTextFile(const std::string& path, const std::string& source) {\n    std::ifstream input(path, std::ios::binary);''',
"parseTextFile signature")

s = replace_once(s,
'''    if (input.gcount() > 0) parseListfile(bytes.data(), static_cast<std::size_t>(input.gcount()));''',
'''    if (input.gcount() > 0)\n        parseListfile(bytes.data(), static_cast<std::size_t>(input.gcount()), source);''',
"parseTextFile source propagation")

s = replace_once(s,
'''            addResult(relative);\n        }\n        if (lower == "moonmarkerm2list.txt") {\n            parseTextFile(full);''',
'''            addResult(relative, "LOOSE");\n        }\n        if (lower == "moonmarkerm2list.txt") {\n            parseTextFile(full, "LOOSE");''',
"loose source propagation")

s = replace_once(s,
'''    parseListfile(buffer.data(), read);\n    gLastError.clear();''',
'''    parseListfile(buffer.data(), read, fileNameOnly(archivePath));\n    gLastError.clear();''',
"archive listfile source")

s = replace_once(s,
'''void parseArchiveSidecars(const std::string& archivePath) {\n    parseTextFile(archivePath + ".listfile");\n}''',
'''void parseArchiveSidecars(const std::string& archivePath) {\n    parseTextFile(archivePath + ".listfile", fileNameOnly(archivePath));\n}''',
"archive sidecar source")

s = replace_once(s,
'''    gResults.clear();\n    gSeen.clear();\n    gArchiveIndex = 0;''',
'''    gResults.clear();\n    gSeen.clear();\n    gSourceByPath.clear();\n    gArchiveIndex = 0;''',
"clear source map")

s = replace_once(s,
'''    addResult("Spells\\\\MoonBeam_Impact_Base.mdx");\n    addResult("Spells\\\\TargetingCircle.mdx");''',
'''    addResult("Spells\\\\MoonBeam_Impact_Base.mdx", "BUILTIN");\n    addResult("Spells\\\\TargetingCircle.mdx", "BUILTIN");''',
"starter source")

s = replace_once(s,
'''bool get(const std::size_t index, std::string& path) {\n    if (index >= gResults.size()) return false;\n    path = gResults[index];\n    return true;\n}\n''',
'''bool get(const std::size_t index, std::string& path) {\n    std::string ignoredSource;\n    return get(index, path, ignoredSource);\n}\n\nbool get(const std::size_t index, std::string& path, std::string& source) {\n    if (index >= gResults.size()) return false;\n    path = gResults[index];\n    const auto it = gSourceByPath.find(lowerAscii(path));\n    source = it == gSourceByPath.end() ? std::string() : it->second;\n    return true;\n}\n''',
"scanner source getter")
scanner.write_text(s, encoding="utf-8")

h = header.read_text(encoding="utf-8")
h = replace_once(h,
'''Status status();\nbool get(std::size_t index, std::string& path);''',
'''Status status();\nbool get(std::size_t index, std::string& path);\n// Extended result for AutoRange's archive browser. The legacy two-argument\n// getter stays intact for MoonMarker callers.\nbool get(std::size_t index, std::string& path, std::string& source);''',
"scanner header getter")
header.write_text(h, encoding="utf-8")

d = dllmain.read_text(encoding="utf-8")
d = replace_once(d,
'''#include "UnitXPDbc.h"\n#include "MoonMarkerGuildAuth.h"''',
'''#include "UnitXPDbc.h"\n#include "MoonMarkerM2Scanner.h"\n#include "MoonMarkerGuildAuth.h"''',
"dllmain scanner include")

marker = '''        if (autoRangeCommand == "AutoRange.Status") {\n            const std::string record = autoRange::status();\n            lua_pushstring(L, record.c_str());\n            return 1;\n        }\n'''
addition = marker + '''        // R7.5 public M2 browser API. This deliberately lives in AutoRange rather\n        // than MoonMarker.Advanced so the scanner is usable without the guild-auth gate.\n        // Work remains incremental: Start prepares, each Step processes at most one MPQ.\n        if (autoRangeCommand == "AutoRange.M2Scan.Start") {\n            moonMarkerM2Scanner::start();\n            const auto st = moonMarkerM2Scanner::status();\n            lua_pushboolean(L, st.running ? 1 : 0);\n            lua_pushboolean(L, st.complete ? 1 : 0);\n            lua_pushnumber(L, static_cast<double>(st.processedArchives));\n            lua_pushnumber(L, static_cast<double>(st.totalArchives));\n            lua_pushnumber(L, static_cast<double>(st.resultCount));\n            if (st.currentArchive.empty()) lua_pushnil(L); else lua_pushstring(L, st.currentArchive.c_str());\n            if (st.lastError.empty()) lua_pushnil(L); else lua_pushstring(L, st.lastError.c_str());\n            return 7;\n        }\n        if (autoRangeCommand == "AutoRange.M2Scan.Step") {\n            moonMarkerM2Scanner::step();\n            const auto st = moonMarkerM2Scanner::status();\n            lua_pushboolean(L, st.running ? 1 : 0);\n            lua_pushboolean(L, st.complete ? 1 : 0);\n            lua_pushnumber(L, static_cast<double>(st.processedArchives));\n            lua_pushnumber(L, static_cast<double>(st.totalArchives));\n            lua_pushnumber(L, static_cast<double>(st.resultCount));\n            if (st.currentArchive.empty()) lua_pushnil(L); else lua_pushstring(L, st.currentArchive.c_str());\n            if (st.lastError.empty()) lua_pushnil(L); else lua_pushstring(L, st.lastError.c_str());\n            return 7;\n        }\n        if (autoRangeCommand == "AutoRange.M2Scan.Status") {\n            const auto st = moonMarkerM2Scanner::status();\n            lua_pushboolean(L, st.running ? 1 : 0);\n            lua_pushboolean(L, st.complete ? 1 : 0);\n            lua_pushnumber(L, static_cast<double>(st.processedArchives));\n            lua_pushnumber(L, static_cast<double>(st.totalArchives));\n            lua_pushnumber(L, static_cast<double>(st.resultCount));\n            if (st.currentArchive.empty()) lua_pushnil(L); else lua_pushstring(L, st.currentArchive.c_str());\n            if (st.lastError.empty()) lua_pushnil(L); else lua_pushstring(L, st.lastError.c_str());\n            return 7;\n        }\n        if (autoRangeCommand == "AutoRange.M2Scan.Get" && argumentCount >= 2\n            && lua_isnumber(L, 2)) {\n            const int luaIndex = static_cast<int>(lua_tonumber(L, 2));\n            if (luaIndex < 1) {\n                lua_pushboolean(L, 0);\n                lua_pushstring(L, "INDEX_OUT_OF_RANGE");\n                return 2;\n            }\n            std::string path;\n            std::string source;\n            if (!moonMarkerM2Scanner::get(static_cast<std::size_t>(luaIndex - 1), path, source)) {\n                lua_pushboolean(L, 0);\n                lua_pushstring(L, "INDEX_OUT_OF_RANGE");\n                return 2;\n            }\n            lua_pushboolean(L, 1);\n            lua_pushstring(L, path.c_str());\n            if (source.empty()) lua_pushnil(L); else lua_pushstring(L, source.c_str());\n            return 3;\n        }\n'''
d = replace_once(d, marker, addition, "dllmain AutoRange M2 scan API")
dllmain.write_text(d, encoding="utf-8")

print("Applied AutoRange R7.5 M2 archive source extension")
