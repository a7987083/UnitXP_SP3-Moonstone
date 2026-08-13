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
'''std::vector<std::string> gArchives;\nstd::vector<std::string> gResults;\nstd::unordered_set<std::string> gSeen;\nstd::unordered_map<std::string, std::string> gSourceByPath;''',
'''struct ScanResult {\n    std::string path;\n    std::string source;\n};\n\nstd::vector<std::string> gArchives;\nstd::vector<ScanResult> gResults;\nstd::unordered_set<std::string> gSeen;''',
"scanner result storage")

s = replace_once(s,
'''void addResult(std::string path, const std::string& source) {\n    if (gResults.size() >= kMaxResults) return;\n    path = trim(normalizeSlashes(path));\n    if (!safeModelPath(path)) return;\n    const std::string key = lowerAscii(path);\n    if (gSeen.insert(key).second) {\n        gResults.push_back(path);\n        gSourceByPath[key] = source;\n    }\n}''',
'''void addResult(std::string path, const std::string& source) {\n    if (gResults.size() >= kMaxResults) return;\n    path = trim(normalizeSlashes(path));\n    if (!safeModelPath(path)) return;\n    const std::string normalizedSource = source.empty() ? std::string("UNCLASSIFIED") : source;\n    // R7.5.1: deduplicate only inside the same archive. The same virtual M2 path\n    // may legitimately exist in patch-O.mpq and patch-P.mpq and must be visible\n    // under both sources in AutoRange's archive browser.\n    const std::string key = lowerAscii(normalizedSource) + "\\n" + lowerAscii(path);\n    if (gSeen.insert(key).second) {\n        gResults.push_back(ScanResult{ path, normalizedSource });\n    }\n}''',
"scanner archive-aware dedup")

s = replace_once(s,
'''void finish() {\n    std::sort(gResults.begin(), gResults.end(), [](const std::string& a, const std::string& b) {\n        return lowerAscii(a) < lowerAscii(b);\n    });\n    gRunning = false;''',
'''void finish() {\n    std::sort(gResults.begin(), gResults.end(), [](const ScanResult& a, const ScanResult& b) {\n        const std::string as = lowerAscii(a.source);\n        const std::string bs = lowerAscii(b.source);\n        if (as != bs) return as < bs;\n        return lowerAscii(a.path) < lowerAscii(b.path);\n    });\n    gRunning = false;''',
"scanner result sort")

s = replace_once(s,
'''    gResults.clear();\n    gSeen.clear();\n    gSourceByPath.clear();\n    gArchiveIndex = 0;''',
'''    gResults.clear();\n    gSeen.clear();\n    gArchiveIndex = 0;''',
"scanner reset source map removal")

s = replace_once(s,
'''bool get(const std::size_t index, std::string& path, std::string& source) {\n    if (index >= gResults.size()) return false;\n    path = gResults[index];\n    const auto it = gSourceByPath.find(lowerAscii(path));\n    source = it == gSourceByPath.end() ? std::string() : it->second;\n    return true;\n}\n''',
'''bool get(const std::size_t index, std::string& path, std::string& source) {\n    if (index >= gResults.size()) return false;\n    path = gResults[index].path;\n    source = gResults[index].source;\n    return true;\n}\n\nbool getArchive(const std::size_t index, std::string& archive) {\n    if (index >= gArchives.size()) return false;\n    archive = fileNameOnly(gArchives[index]);\n    return true;\n}\n''',
"scanner getters")
scanner.write_text(s, encoding="utf-8")

h = header.read_text(encoding="utf-8")
h = replace_once(h,
'''bool get(std::size_t index, std::string& path, std::string& source);''',
'''bool get(std::size_t index, std::string& path, std::string& source);\n// Enumerates every MPQ discovered under Data independently of whether that\n// archive contributes a unique M2 result. This is the authoritative left-side\n// source list for AutoRange's archive browser.\nbool getArchive(std::size_t index, std::string& archive);''',
"scanner header archive getter")
header.write_text(h, encoding="utf-8")

d = dllmain.read_text(encoding="utf-8")
marker = '''        if (autoRangeCommand == "AutoRange.M2Scan.Get" && argumentCount >= 2\n            && lua_isnumber(L, 2)) {\n            const int luaIndex = static_cast<int>(lua_tonumber(L, 2));\n            if (luaIndex < 1) {\n                lua_pushboolean(L, 0);\n                lua_pushstring(L, "INDEX_OUT_OF_RANGE");\n                return 2;\n            }\n            std::string path;\n            std::string source;\n            if (!moonMarkerM2Scanner::get(static_cast<std::size_t>(luaIndex - 1), path, source)) {\n                lua_pushboolean(L, 0);\n                lua_pushstring(L, "INDEX_OUT_OF_RANGE");\n                return 2;\n            }\n            lua_pushboolean(L, 1);\n            lua_pushstring(L, path.c_str());\n            if (source.empty()) lua_pushnil(L); else lua_pushstring(L, source.c_str());\n            return 3;\n        }\n'''
addition = marker + '''        if (autoRangeCommand == "AutoRange.M2Scan.ArchiveGet" && argumentCount >= 2\n            && lua_isnumber(L, 2)) {\n            const int luaIndex = static_cast<int>(lua_tonumber(L, 2));\n            if (luaIndex < 1) {\n                lua_pushboolean(L, 0);\n                lua_pushstring(L, "INDEX_OUT_OF_RANGE");\n                return 2;\n            }\n            std::string archive;\n            if (!moonMarkerM2Scanner::getArchive(static_cast<std::size_t>(luaIndex - 1), archive)) {\n                lua_pushboolean(L, 0);\n                lua_pushstring(L, "INDEX_OUT_OF_RANGE");\n                return 2;\n            }\n            lua_pushboolean(L, 1);\n            lua_pushstring(L, archive.c_str());\n            return 2;\n        }\n'''
d = replace_once(d, marker, addition, "dllmain archive getter API")
dllmain.write_text(d, encoding="utf-8")

print("Applied AutoRange R7.5.1 M2 archive dedup/source-list fix")
