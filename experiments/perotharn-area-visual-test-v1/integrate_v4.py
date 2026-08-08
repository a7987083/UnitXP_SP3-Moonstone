#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else 'target')
native=root/'native'
p=native/'dllmain.cpp'
s=p.read_text(encoding='utf-8-sig')
inc='#include "dirkNativeDumpV4.h"'
anchor='#include "dirkNativeDumpV3.h"'
if inc not in s:
    if anchor not in s: raise SystemExit('missing v3 include anchor')
    s=s.replace(anchor,anchor+'\n'+inc,1)
sig='int __fastcall detoured_UnitXP(void* L) {'
if 'dumpCmd4 == "dirkDump4"' not in s:
    block=r'''
    if (lua_gettop(L) >= 1) {
        std::string dumpCmd4 = lua_tostring(L, 1);
        if (dumpCmd4 == "dirkDump4") {
            std::string outputPath;
            std::string dumpStatus;
            const bool ok = dirkNativeDumpV4::dump(outputPath, dumpStatus);
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushstring(L, dumpStatus.c_str());
            lua_pushstring(L, outputPath.c_str());
            return 3;
        }
    }
'''
    if sig not in s: raise SystemExit('UnitXP signature missing')
    s=s.replace(sig,sig+block,1)
p.write_text(s,encoding='utf-8')
p=native/'Makefile'
s=p.read_text(encoding='utf-8-sig')
if 'dirkNativeDumpV4.cpp' not in s:
    needle='            dirkNativeDumpV3.cpp \\\n'
    if needle not in s: raise SystemExit('Makefile v3 anchor missing')
    s=s.replace(needle,needle+'            dirkNativeDumpV4.cpp \\\n',1)
p.write_text(s,encoding='utf-8')
for path,needles in {native/'dllmain.cpp':['dirkNativeDumpV4.h','dirkDump4','dirkNativeDumpV4::dump'],native/'Makefile':['dirkNativeDumpV4.cpp'],native/'dirkNativeDumpV4.cpp':['0x0061FCF0u','0x00620BE0u','0x00620C86u','DirkNativeDump-v4.txt']}.items():
    t=path.read_text(encoding='utf-8-sig')
    for n in needles:
        if n not in t: raise SystemExit(f'v4 integration assertion failed: {path}: {n}')
print('Native Dump v4 integration OK')
