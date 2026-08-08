#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'target')
native = root / 'native'

p = native / 'dllmain.cpp'
s = p.read_text(encoding='utf-8-sig')
inc = '#include "dirkNativeCreate.h"'
if inc not in s:
    for anchor in ('#include "dirkNativeDumpV4.h"', '#include "dirkNativeDumpV3.h"', '#include "dirkAreaTest.h"'):
        if anchor in s:
            s = s.replace(anchor, anchor + '\n' + inc, 1)
            break
    else:
        raise SystemExit('dirkNativeCreate include anchor missing')

sig = 'int __fastcall detoured_UnitXP(void* L) {'
if sig not in s:
    raise SystemExit('detoured_UnitXP signature missing')

if 'nativeCmd == "dirkNative"' not in s:
    block = r'''
    // Direct client CEffect/world-plant test for Peroth'arn AreaModel assets.
    if (lua_gettop(L) >= 2) {
        std::string nativeCmd = lua_tostring(L, 1);
        if (nativeCmd == "dirkNative") {
            std::string subcmd = lua_tostring(L, 2);
            std::string nativeStatus;
            bool ok = false;
            if (subcmd == "pre") ok = dirkNativeCreate::spawnPre(nativeStatus);
            else if (subcmd == "cast") ok = dirkNativeCreate::spawnCast(nativeStatus);
            else nativeStatus = "unknown_subcommand_use_pre_or_cast";
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushstring(L, nativeStatus.c_str());
            return 2;
        }
    }
'''
    s = s.replace(sig, sig + block, 1)
p.write_text(s, encoding='utf-8')

p = native / 'Makefile'
s = p.read_text(encoding='utf-8-sig')
if 'dirkNativeCreate.cpp' not in s:
    slash_n = chr(92) + chr(10)
    for source in ('dirkNativeDumpV4.cpp', 'dirkNativeDumpV3.cpp', 'dirkAreaTest.cpp', 'dllmain.cpp'):
        needle = f'            {source} ' + slash_n
        if needle in s:
            s = s.replace(needle, needle + '            dirkNativeCreate.cpp ' + slash_n, 1)
            break
    else:
        raise SystemExit('Makefile source-list anchor missing')
p.write_text(s, encoding='utf-8')

checks = {
    native / 'dllmain.cpp': ['#include "dirkNativeCreate.h"', 'nativeCmd == "dirkNative"', 'spawnPre', 'spawnCast'],
    native / 'Makefile': ['dirkNativeCreate.cpp'],
    native / 'dirkNativeCreate.cpp': ['0x0061FCF0', '0x0061F490', '0x006462E0', 'kPreEffectId = 4501', 'kCastEffectId = 4502'],
}
for path, needles in checks.items():
    t = path.read_text(encoding='utf-8-sig')
    for needle in needles:
        if needle not in t:
            raise SystemExit(f'native create integration assertion failed: {path}: {needle}')

print('Perotharn direct CEffect native create integration OK')
