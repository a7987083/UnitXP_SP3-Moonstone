#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else 'target')
native=root/'native'

p=native/'dllmain.cpp'
s=p.read_text(encoding='utf-8-sig')
inc='#include "dirkNativeDumpV3.h"'
if inc not in s:
    anchor='#include "dirkNativeDump.h"'
    if anchor not in s: raise SystemExit('missing dirkNativeDump include anchor')
    s=s.replace(anchor,anchor+'\n'+inc,1)
sig='int __fastcall detoured_UnitXP(void* L) {'
if 'dumpCmd3 == "dirkDump3"' not in s:
    block=r'''
    if (lua_gettop(L) >= 1) {
        std::string dumpCmd3 = lua_tostring(L, 1);
        if (dumpCmd3 == "dirkDump3") {
            std::string outputPath;
            std::string dumpStatus;
            const bool ok = dirkNativeDumpV3::dump(outputPath, dumpStatus);
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushstring(L, dumpStatus.c_str());
            lua_pushstring(L, outputPath.c_str());
            return 3;
        }
    }
'''
    if sig not in s: raise SystemExit('detoured_UnitXP signature missing')
    s=s.replace(sig,sig+block,1)
p.write_text(s,encoding='utf-8')

p=native/'Makefile'
s=p.read_text(encoding='utf-8-sig')
if 'dirkNativeDumpV3.cpp' not in s:
    needle='            dirkNativeDump.cpp \\\n'
    if needle not in s:
        needle='            dirkAreaTest.cpp \\\n'
    if needle not in s: raise SystemExit('Makefile anchor missing')
    s=s.replace(needle,needle+'            dirkNativeDumpV3.cpp \\\n',1)
p.write_text(s,encoding='utf-8')

for path, needles in {
    native/'dllmain.cpp':['#include "dirkNativeDumpV3.h"','dumpCmd3 == "dirkDump3"','dirkNativeDumpV3::dump'],
    native/'Makefile':['dirkNativeDumpV3.cpp'],
    native/'dirkNativeDumpV3.cpp':['DirkNativeDump-v3.txt','GetModuleHandleExA','source_rel32_target','MOV EAX immediate'],
}.items():
    t=path.read_text(encoding='utf-8-sig')
    for n in needles:
        if n not in t: raise SystemExit(f'v3 integration assertion failed: {path}: {n}')
print('Native Dump v3 integration OK')
