#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
path = root / "dllmain.cpp"
text = path.read_text(encoding="utf-8")

include_old = "#include <limits>\n"
include_new = "#include <limits>\n#include <vector>\n#include <algorithm>\n#include <cctype>\n"
if "#include <vector>" not in text:
    if include_old not in text:
        raise SystemExit("include anchor not found")
    text = text.replace(include_old, include_new, 1)

helper_anchor = "int __fastcall detoured_UnitXP(void* L) {\n"
helper_code = r'''namespace {
std::vector<std::string> gAutoRangeMediaFiles;
std::string gAutoRangeMediaStatus = "NOT_SCANNED";

std::string autoRangeAsciiLower(const std::string& value) {
    std::string out = value;
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(out[i])));
    }
    return out;
}

std::string autoRangeMediaDirectory() {
    // scan-root-marker: Interface\\AddOns\\AutoRange\\Media
    char exePath[MAX_PATH] = {};
    const DWORD n = GetModuleFileNameA(nullptr, exePath, static_cast<DWORD>(sizeof(exePath)));
    if (n == 0 || n >= sizeof(exePath)) return std::string();
    std::string base(exePath, n);
    const std::size_t slash = base.find_last_of("\\/");
    if (slash == std::string::npos) return std::string();
    base.resize(slash);
    return base + "\\Interface\\AddOns\\AutoRange\\Media";
}

bool autoRangeScanMediaDirectory() {
    gAutoRangeMediaFiles.clear();
    const std::string directory = autoRangeMediaDirectory();
    if (directory.empty()) {
        gAutoRangeMediaStatus = "GAME_DIR_NOT_FOUND";
        return false;
    }

    WIN32_FIND_DATAA data = {};
    HANDLE find = FindFirstFileA((directory + "\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        gAutoRangeMediaStatus = "MEDIA_DIR_NOT_FOUND";
        return false;
    }

    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) continue;
        const std::string name = data.cFileName;
        if (name.empty()) continue;
        const std::string lower = autoRangeAsciiLower(name);
        if (lower.size() < 4 || lower.compare(lower.size() - 4, 4, ".tga") != 0) continue;
        gAutoRangeMediaFiles.push_back(name);
        if (gAutoRangeMediaFiles.size() >= 1024) break;
    } while (FindNextFileA(find, &data));
    FindClose(find);

    std::sort(gAutoRangeMediaFiles.begin(), gAutoRangeMediaFiles.end(),
        [](const std::string& a, const std::string& b) {
            const std::string al = autoRangeAsciiLower(a);
            const std::string bl = autoRangeAsciiLower(b);
            if (al == bl) return a < b;
            return al < bl;
        });

    gAutoRangeMediaStatus = gAutoRangeMediaFiles.empty() ? "EMPTY" : "OK";
    return true;
}
}

'''
if "gAutoRangeMediaFiles" not in text:
    if helper_anchor not in text:
        raise SystemExit("detour anchor not found")
    text = text.replace(helper_anchor, helper_code + helper_anchor, 1)

api_anchor = '''        // R7.5 public M2 browser API. This deliberately lives in AutoRange rather
'''
api_code = r'''        // AutoRange warning-media browser. Scanning is explicit/on-demand only:
        // there is no worker thread, timer, hook, or per-frame directory polling.
        if (autoRangeCommand == "AutoRange.Media.Scan") {
            const bool ok = autoRangeScanMediaDirectory();
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushnumber(L, static_cast<double>(gAutoRangeMediaFiles.size()));
            lua_pushstring(L, gAutoRangeMediaStatus.c_str());
            return 3;
        }
        if (autoRangeCommand == "AutoRange.Media.Status") {
            lua_pushnumber(L, static_cast<double>(gAutoRangeMediaFiles.size()));
            lua_pushstring(L, gAutoRangeMediaStatus.c_str());
            return 2;
        }
        if (autoRangeCommand == "AutoRange.Media.Get" && argumentCount >= 2
            && lua_isnumber(L, 2)) {
            const int luaIndex = static_cast<int>(lua_tonumber(L, 2));
            if (luaIndex < 1 || static_cast<std::size_t>(luaIndex) > gAutoRangeMediaFiles.size()) {
                lua_pushboolean(L, 0);
                lua_pushstring(L, "INDEX_OUT_OF_RANGE");
                return 2;
            }
            lua_pushboolean(L, 1);
            lua_pushstring(L, gAutoRangeMediaFiles[static_cast<std::size_t>(luaIndex - 1)].c_str());
            return 2;
        }
'''
if 'AutoRange.Media.Scan' not in text:
    if api_anchor not in text:
        raise SystemExit("AutoRange API anchor not found")
    text = text.replace(api_anchor, api_code + api_anchor, 1)

path.write_text(text, encoding="utf-8", newline="\n")
print("patched", path)
