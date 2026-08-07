#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "target")
native = root / "native"

# dllmain.cpp: add the test command before all existing UnitXP command routing.
p = native / "dllmain.cpp"
s = p.read_text(encoding="utf-8-sig")
if '#include "dirkAreaTest.h"' not in s:
    for anchor in ('#include "nativeM2Test.h"', '#include "Vanilla1121_functions.h"'):
        if anchor in s:
            s = s.replace(anchor, anchor + '\n#include "dirkAreaTest.h"', 1)
            break
    else:
        raise SystemExit("could not find dllmain include anchor")

signature = "int __fastcall detoured_UnitXP(void* L) {"
if signature not in s:
    raise SystemExit("detoured_UnitXP signature not found")
if 'dirkCmd == "dirkTest"' not in s:
    block = r'''
    // Peroth'arn Dirk of the Beast local visual test.
    if (lua_gettop(L) >= 2) {
        std::string dirkCmd = lua_tostring(L, 1);
        if (dirkCmd == "dirkTest") {
            std::string subcmd = lua_tostring(L, 2);
            bool ok = false;
            if (subcmd == "pre") {
                float scale = 1.0f;
                if (lua_gettop(L) >= 3 && lua_isnumber(L, 3)) scale = static_cast<float>(lua_tonumber(L, 3));
                ok = dirkAreaTest::showPre(scale);
            }
            else if (subcmd == "cast") {
                float scale = 1.0f;
                if (lua_gettop(L) >= 3 && lua_isnumber(L, 3)) scale = static_cast<float>(lua_tonumber(L, 3));
                ok = dirkAreaTest::showCast(scale);
            }
            else if (subcmd == "full") {
                float preDelay = 2.0f;
                float castHold = 2.0f;
                float scale = 1.0f;
                if (lua_gettop(L) >= 3 && lua_isnumber(L, 3)) preDelay = static_cast<float>(lua_tonumber(L, 3));
                if (lua_gettop(L) >= 4 && lua_isnumber(L, 4)) castHold = static_cast<float>(lua_tonumber(L, 4));
                if (lua_gettop(L) >= 5 && lua_isnumber(L, 5)) scale = static_cast<float>(lua_tonumber(L, 5));
                ok = dirkAreaTest::showFull(preDelay, castHold, scale);
            }
            else if (subcmd == "clear") { dirkAreaTest::clear(); ok = true; }
            else if (subcmd == "status") ok = true;
            lua_pushboolean(L, ok);
            lua_pushstring(L, dirkAreaTest::statusText());
            return 2;
        }
    }
'''
    s = s.replace(signature, signature + block, 1)
p.write_text(s, encoding="utf-8")

# sceneBegin_sceneEnd.cpp: update the M2 objects only on the game/main render path.
p = native / "sceneBegin_sceneEnd.cpp"
s = p.read_text(encoding="utf-8-sig")
if '#include "dirkAreaTest.h"' not in s:
    anchor = '#include "FPScap.h"'
    if anchor not in s:
        raise SystemExit("scene include anchor not found")
    s = s.replace(anchor, anchor + '\n#include "dirkAreaTest.h"', 1)
sig = "void __fastcall detoured_sceneEnd(uint32_t CGxDevice, void* ignored) {"
if "dirkAreaTest::update();" not in s:
    if sig not in s:
        raise SystemExit("sceneEnd signature not found")
    s = s.replace(sig, sig + "\n    dirkAreaTest::update();", 1)
leave = "void scene_onPlayerLeavingWorld() {"
if "dirkAreaTest::clear();\n    scene_inWorld = 0;" not in s:
    if leave not in s:
        raise SystemExit("leave-world function not found")
    s = s.replace(leave, leave + "\n    dirkAreaTest::clear();", 1)
p.write_text(s, encoding="utf-8")

# Makefile: append the sibling C++ module to SRCS.
p = native / "Makefile"
s = p.read_text(encoding="utf-8-sig")
if "dirkAreaTest.cpp" not in s:
    slash_n = chr(92) + chr(10)
    candidates = (
        "            nativeM2Test.cpp " + slash_n,
        "            dllmain.cpp " + slash_n,
    )
    for needle in candidates:
        if needle in s:
            s = s.replace(needle, needle + "            dirkAreaTest.cpp " + slash_n, 1)
            break
    else:
        raise SystemExit("Makefile source-list anchor not found")
p.write_text(s, encoding="utf-8")

checks = {
    native / "dllmain.cpp": ['#include "dirkAreaTest.h"', 'dirkCmd == "dirkTest"', 'showPre(scale)', 'showCast(scale)', 'showFull(preDelay, castHold, scale)'],
    native / "sceneBegin_sceneEnd.cpp": ['#include "dirkAreaTest.h"', 'dirkAreaTest::update();'],
    native / "Makefile": ["dirkAreaTest.cpp"],
    native / "dirkAreaTest.cpp": [
        "DirkOfTheBeast_Area_PreCast.mdx",
        "DirkOfTheBeast_Area_Cast.mdx",
        "kLineLengthYards = 100.0f",
        "kDynamicObjectLoopSequence = 0x9E",
        "kSetTransformAddress = 0x00710650",
    ],
}
for file, needles in checks.items():
    text = file.read_text(encoding="utf-8-sig")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"integration assertion failed: {file}: {needle}")

print("Perotharn Area Visual Test v2 integration OK")
