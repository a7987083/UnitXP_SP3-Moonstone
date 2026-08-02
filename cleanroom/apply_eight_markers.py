#!/usr/bin/env python3
"""Apply the eight-color/eight-marker stage after the existing cleanroom patches."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--addon", required=True)
    parser.add_argument("--addon-source", required=True)
    args = parser.parse_args()

    upstream = Path(args.upstream)
    addon = Path(args.addon)

    moon_path = upstream / "moonMarker.cpp"
    moon = moon_path.read_text(encoding="utf-8-sig")
    moon = replace_once(moon,
        'constexpr std::size_t kColorCount = 7;',
        'constexpr std::size_t kColorCount = 8;',
        'color count')
    moon = replace_once(moon,
        '    {"blue",    78, 165, 255},\n',
        '    {"blue",    78, 165, 255},\n    {"cyan",    40, 230, 230},\n',
        'cyan color')
    moon = replace_once(moon,
        '#include "MinHook.h"\n',
        '#include "MinHook.h"\n#include "nativeM2Test.h"\n',
        'native icon include')
    moon = replace_once(moon,
        '    renderPresent(device);\n\n    PresentProc original = gOriginalPresent;',
        '    renderPresent(device);\n    nativeM2Test::renderIcons(device);\n\n    PresentProc original = gOriginalPresent;',
        'Present icon render')
    moon_path.write_text(moon, encoding="utf-8", newline="\n")

    dll_path = upstream / "dllmain.cpp"
    dll = dll_path.read_text(encoding="utf-8-sig")
    dll = replace_once(dll,
        '            setNumber("loadReadyTransitions", m2.loadReadyTransitions);\n'
        '            setNumber("x", m2.position.x);',
        '            setNumber("loadReadyTransitions", m2.loadReadyTransitions);\n'
        '            setNumber("activeCount", m2.activeCount);\n'
        '            setString("color", m2.color);\n'
        '            setString("icon", m2.icon);\n'
        '            setNumber("x", m2.position.x);',
        'M2 status fields')

    old_place = '''            const string colorText{ lua_tostring(L, 2) };
            const bool nativeWhite = colorText == "white";
            if (moonMarker::placeAtCursor(colorText, placedPosition, normalizedColor, !nativeWhite)) {
                if (nativeWhite) {
                    C3Vector modelPosition = placedPosition;
                    modelPosition.z += 0.05f;
                    if (!nativeM2Test::createAt(modelPosition)) {
                        moonMarker::remove("white");
                        return 0;
                    }
                }
                lua_pushnumber(L, placedPosition.x);
                lua_pushnumber(L, placedPosition.y);
                lua_pushnumber(L, placedPosition.z);
                lua_pushstring(L, normalizedColor);
                return 4;
            }
'''
    new_place = '''            const string colorText{ lua_tostring(L, 2) };
            const string iconText = argumentCount >= 3
                ? string{ lua_tostring(L, 3) }
                : nativeM2Test::defaultIconForColor(colorText);
            if (moonMarker::placeAtCursor(colorText, placedPosition, normalizedColor, false)) {
                C3Vector modelPosition = placedPosition;
                modelPosition.z += 0.05f;
                if (!nativeM2Test::createAt(normalizedColor, iconText, modelPosition)) {
                    moonMarker::remove(normalizedColor);
                    return 0;
                }
                const std::string normalizedIcon = nativeM2Test::iconForColor(normalizedColor);
                lua_pushnumber(L, placedPosition.x);
                lua_pushnumber(L, placedPosition.y);
                lua_pushnumber(L, placedPosition.z);
                lua_pushstring(L, normalizedColor);
                lua_pushstring(L, normalizedIcon);
                return 5;
            }
'''
    dll = replace_once(dll, old_place, new_place, 'native placement block')

    old_remote = '''            const string colorText{ lua_tostring(L, 2) };
            const bool nativeWhite = colorText == "white";
            if (!moonMarker::placeRemote(colorText, remotePosition, !nativeWhite)) {
                lua_pushboolean(L, false);
                return 1;
            }
            if (nativeWhite) {
                C3Vector modelPosition = remotePosition;
                modelPosition.z += 0.05f;
                if (!nativeM2Test::createAt(modelPosition)) {
                    moonMarker::remove("white");
                    lua_pushboolean(L, false);
                    return 1;
                }
            }
            lua_pushboolean(L, true);
'''
    new_remote = '''            const string colorText{ lua_tostring(L, 2) };
            const string iconText = argumentCount >= 6
                ? string{ lua_tostring(L, 6) }
                : nativeM2Test::defaultIconForColor(colorText);
            if (!moonMarker::placeRemote(colorText, remotePosition, false)) {
                lua_pushboolean(L, false);
                return 1;
            }
            C3Vector modelPosition = remotePosition;
            modelPosition.z += 0.05f;
            if (!nativeM2Test::createAt(colorText, iconText, modelPosition)) {
                moonMarker::remove(colorText);
                lua_pushboolean(L, false);
                return 1;
            }
            lua_pushboolean(L, true);
'''
    dll = replace_once(dll, old_remote, new_remote, 'native remote block')
    dll = dll.replace('moonMarker::MarkInfo marks[7] = {};',
                      'moonMarker::MarkInfo marks[8] = {};')
    dll = dll.replace('moonMarker::snapshot(marks, 7)',
                      'moonMarker::snapshot(marks, 8)')
    if 'moonMarker::MarkInfo marks[7]' in dll or 'snapshot(marks, 7)' in dll:
        raise RuntimeError('query capacity replacement failed')

    dll = replace_once(dll,
        '                lua_pushstring(L, marks[i].color);\n'
        '                lua_settable(L, -3);\n'
        '                lua_pushstring(L, "x");',
        '                lua_pushstring(L, marks[i].color);\n'
        '                lua_settable(L, -3);\n'
        '                lua_pushstring(L, "icon");\n'
        '                lua_pushstring(L, nativeM2Test::iconForColor(marks[i].color));\n'
        '                lua_settable(L, -3);\n'
        '                lua_pushstring(L, "x");',
        'query icon field')
    dll_path.write_text(dll, encoding="utf-8", newline="\n")

    scene_path = upstream / "sceneBegin_sceneEnd.cpp"
    scene = scene_path.read_text(encoding="utf-8-sig")
    count = scene.count('moonMarker::remove("white");')
    if count != 2:
        raise RuntimeError(f'scene clear: expected two white removals, found {count}')
    scene = scene.replace('moonMarker::remove("white");', 'moonMarker::clearAll();')
    scene_path.write_text(scene, encoding="utf-8", newline="\n")

    addon_source = Path(args.addon_source)
    target = addon / "MoonMarker" / "MoonMarker.lua"
    target.write_text(addon_source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
