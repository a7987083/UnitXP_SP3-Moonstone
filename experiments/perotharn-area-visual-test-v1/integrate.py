#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "target")
native = root / "native"

# dllmain.cpp: add the visual test and read-only native dump commands before existing routing.
p = native / "dllmain.cpp"
s = p.read_text(encoding="utf-8-sig")
for header in ('dirkAreaTest.h', 'dirkNativeDump.h'):
    inc = f'#include "{header}"'
    if inc not in s:
        for anchor in ('#include "nativeM2Test.h"', '#include "Vanilla1121_functions.h"'):
            if anchor in s:
                s = s.replace(anchor, anchor + '\n' + inc, 1)
                break
        else:
            raise SystemExit(f"could not find dllmain include anchor for {header}")

signature = "int __fastcall detoured_UnitXP(void* L) {"
if signature not in s:
    raise SystemExit("detoured_UnitXP signature not found")

if 'dumpCmd == "dirkDump"' not in s:
    dump_block = r'''
    // Read-only reverse-engineering dump for the DynamicObject / AreaModel client path.
    if (lua_gettop(L) >= 1) {
        std::string dumpCmd = lua_tostring(L, 1);
        if (dumpCmd == "dirkDump") {
            std::string outputPath;
            std::string dumpStatus;
            const bool ok = dirkNativeDump::dump(outputPath, dumpStatus);
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushstring(L, dumpStatus.c_str());
            lua_pushstring(L, outputPath.c_str());
            return 3;
        }
    }
'''
    s = s.replace(signature, signature + dump_block, 1)

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
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushstring(L, dirkAreaTest::statusText().c_str());
            return 2;
        }
    }
'''
    s = s.replace(signature, signature + block, 1)
p.write_text(s, encoding="utf-8")

# sceneBegin_sceneEnd.cpp: update the old visual-test M2 objects only on the game/main render path.
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

# Makefile: append the two sibling C++ modules to SRCS.
p = native / "Makefile"
s = p.read_text(encoding="utf-8-sig")
slash_n = chr(92) + chr(10)
for source in ('dirkAreaTest.cpp', 'dirkNativeDump.cpp'):
    if source not in s:
        candidates = (
            "            nativeM2Test.cpp " + slash_n,
            "            dllmain.cpp " + slash_n,
            "            dirkAreaTest.cpp " + slash_n,
        )
        for needle in candidates:
            if needle in s:
                s = s.replace(needle, needle + f"            {source} " + slash_n, 1)
                break
        else:
            raise SystemExit(f"Makefile source-list anchor not found for {source}")
p.write_text(s, encoding="utf-8")

checks = {
    native / "dllmain.cpp": [
        '#include "dirkAreaTest.h"', '#include "dirkNativeDump.h"',
        'dirkCmd == "dirkTest"', 'dumpCmd == "dirkDump"', 'dirkNativeDump::dump'
    ],
    native / "sceneBegin_sceneEnd.cpp": ['#include "dirkAreaTest.h"', 'dirkAreaTest::update();'],
    native / "Makefile": ["dirkAreaTest.cpp", "dirkNativeDump.cpp"],
    native / "dirkAreaTest.cpp": [
        "DirkOfTheBeast_Area_PreCast.mdx",
        "DirkOfTheBeast_Area_Cast.mdx",
        "kLineLengthYards = 100.0f",
        "kDynamicObjectLoopSequence = 0x9E",
        "kSetTransformAddress = 0x00710650",
    ],
    native / "dirkNativeDump.cpp": [
        "0x005D5000u", "0x00613C00u", "0x006E7E00u", "0x007BDB00u",
        "ReadProcessMemory", "DirkNativeDump-v2.txt", "kDetourSources", "appendDetourTarget"
    ],
}
for file, needles in checks.items():
    text = file.read_text(encoding="utf-8-sig")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"integration assertion failed: {file}: {needle}")

print("Perotharn native reverse dump v2 integration OK")
