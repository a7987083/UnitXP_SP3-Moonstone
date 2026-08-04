#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def remove_once(path: Path, old: str, label: str) -> None:
    replace_once(path, old, "", label)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply-compat-cleanup.py <tree>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    native = root / "native"
    plugin = root / "plugin"
    if not native.is_dir() or not plugin.is_dir():
        raise RuntimeError(f"expected native/ and plugin/ below {root}")

    presets = plugin / "Presets.lua"
    remove_once(presets, 'local LEGACY_FORMAT_HEADER = "MOONMARKER_PRESET_V1"\n',
                "remove legacy full-preset header")
    replace_once(presets,
        '        format = 1, id = nil, name = "", category = "未分类", mapName = "",\n',
        '        format = 2, id = nil, name = "", category = "未分类", mapName = "",\n',
        "mark parsed full presets as V2")
    replace_once(presets,
        '        if line == FORMAT_HEADER or line == LEGACY_FORMAT_HEADER then\n',
        '        if line == FORMAT_HEADER then\n',
        "reject legacy full-preset header")

    quick = plugin / "QuickPresets.lua"
    replace_once(quick,
        'local QUICK_FORMAT_HEADER = "MOONMARKER_QUICK_PRESETS_V1"\n',
        'local QUICK_FORMAT_HEADER = "MOONMARKER_QUICK_PRESETS_V2"\n',
        "bump quick-preset transfer header")
    remove_once(quick,
        '''\n    -- Compatibility with exports created before the YS signature was introduced.\n    RED = "red", ORANGE = "orange", YELLOW = "yellow", GREEN = "green",\n    CYAN = "cyan", BLUE = "blue", PURPLE = "purple", WHITE = "white",\n''',
        "remove unsigned quick-preset color tokens")
    replace_once(quick,
        '            elseif kindKey == "mark" or kindKey == "marked" then\n',
        '            elseif kindKey == "mark" then\n',
        "remove MARKed legacy parser branch")
    replace_once(quick,
        '''                local color, marker, x, y, z\n                local rawColor = fields[2]\n                local normalizedColorToken = ""\n                if kindKey == "marked" then\n                    -- Compatibility with V1 text copied from WoW EditBox:\n                    -- MARK|red|... may be rendered/copied as MARKed|...\n                    color = "red"\n                    marker = NormalizeKey(fields[2])\n                    x, y, z = tonumber(fields[3]), tonumber(fields[4]), tonumber(fields[5])\n                else\n                    color, normalizedColorToken = NormalizeQuickColor(rawColor)\n                    marker = NormalizeKey(QuickDecode(fields[3]))\n                    x, y, z = tonumber(fields[4]), tonumber(fields[5]), tonumber(fields[6])\n                end\n''',
        '''                local rawColor = fields[2]\n                local color, normalizedColorToken = NormalizeQuickColor(rawColor)\n                local marker = NormalizeKey(QuickDecode(fields[3]))\n                local x, y, z = tonumber(fields[4]), tonumber(fields[5]), tonumber(fields[6])\n''',
        "simplify current quick-preset MARK parser")

    scanner = native / "MoonMarkerM2Scanner.cpp"
    replace_once(scanner,
        '''        if (lower.find("listfile") != std::string::npos\n            && lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".txt") == 0) {\n            parseTextFile(full);\n        }\n''',
        '''        if (lower == "moonmarkerm2list.txt") {\n            parseTextFile(full);\n        }\n''',
        "standardize external text-list filename")
    replace_once(scanner,
        '''void parseArchiveSidecars(const std::string& archivePath) {\n    parseTextFile(archivePath + ".listfile");\n    parseTextFile(withoutExtension(archivePath) + ".listfile");\n    parseTextFile(withoutExtension(archivePath) + "-listfile.txt");\n    parseTextFile(withoutExtension(archivePath) + ".txt");\n}\n''',
        '''void parseArchiveSidecars(const std::string& archivePath) {\n    parseTextFile(archivePath + ".listfile");\n}\n''',
        "remove ambiguous archive sidecar names")
    remove_once(scanner,
        '''std::string withoutExtension(std::string path) {\n    const std::size_t slash = path.find_last_of("\\\\/");\n    const std::size_t dot = path.find_last_of('.');\n    if (dot == std::string::npos || (slash != std::string::npos && dot < slash)) return path;\n    path.resize(dot);\n    return path;\n}\n\n''',
        "remove unused sidecar helper")

    dllmain = native / "dllmain.cpp"
    replace_once(dllmain,
        '        if (placeCommand && argumentCount >= 2) {\n',
        '        if (placeCommand && argumentCount >= 3 && lua_isstring(L, 3)) {\n',
        "require icon in local marker protocol")
    replace_once(dllmain,
        '''            const string iconText = argumentCount >= 3\n                ? string{ lua_tostring(L, 3) }\n                : nativeM2Test::defaultIconForColor(colorText);\n''',
        '            const string iconText{ lua_tostring(L, 3) };\n',
        "remove local optional-icon fallback")
    replace_once(dllmain,
        '''        else if (remoteCommand && argumentCount >= 5\n                 && lua_isnumber(L, 3) && lua_isnumber(L, 4) && lua_isnumber(L, 5)) {\n''',
        '''        else if (remoteCommand && argumentCount >= 6\n                 && lua_isnumber(L, 3) && lua_isnumber(L, 4) && lua_isnumber(L, 5)\n                 && lua_isstring(L, 6)) {\n''',
        "require icon in remote marker protocol")
    replace_once(dllmain,
        '''            const string iconText = argumentCount >= 6\n                ? string{ lua_tostring(L, 6) }\n                : nativeM2Test::defaultIconForColor(colorText);\n''',
        '            const string iconText{ lua_tostring(L, 6) };\n',
        "remove remote optional-icon fallback")

    native_m2 = native / "nativeM2Test.cpp"
    remove_once(native_m2, '    if (normalized == "x") return 6;\n',
                "remove native x icon alias")
    main_model = native / "MoonMarkerMainModel.cpp"
    remove_once(main_model, '    if (normalized == "x") return 6;\n',
                "remove signed-packet x icon alias")
    native_h = native / "nativeM2Test.h"
    replace_once(native_h,
        '// Returns normalized icon names and preserves legacy calls that omit an icon.\n',
        '// Returns the configured canonical icon name for a color slot.\n',
        "remove legacy API comment")

    toc = plugin / "MoonMarker.toc"
    replace_once(toc,
        '## Version: 0.8.0-consolidated\n',
        '## Version: 0.8.1-compat-cleanup\n',
        "update addon version")

    print("Applied allowlisted compatibility cleanup")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
