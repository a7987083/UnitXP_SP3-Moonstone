#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
path = root / "dllmain.cpp"
if not path.is_file():
    raise SystemExit(f"missing {path}")

text = path.read_text(encoding="utf-8")
if 'cmd == "speed"' in text:
    raise SystemExit("speed command already present")

marker = '''        else if (cmd == "inSight" && lua_gettop(L) >= 3) {\n'''
if marker not in text:
    raise SystemExit("inSight command marker missing")

# Ported from the supplied UnitXP_SP3_X2.0 binary (2026-07-07):
#   current speed = unit object + 0xA2C
#   ground speed  = unit object + 0xA34
#   swim speed    = unit object + 0xA3C
# X2.0 rounds each result to 4 decimal places before returning it to Lua.
block = r'''        else if (cmd == "speed" && lua_gettop(L) >= 2) {
            const char* unitId = lua_tostring(L, 2);
            uint32_t unitObject = 0;
            if (unitId != nullptr) {
                const uint64_t guid = vanilla1121_unitGUID(unitId);
                if (guid != 0) {
                    unitObject = vanilla1121_getVisiableObject(guid);
                }
            }

            double currentSpeed = 0.0;
            double groundSpeed = 0.0;
            double swimSpeed = 0.0;
            if (unitObject != 0) {
                const float currentRaw = *reinterpret_cast<float*>(unitObject + 0xA2C);
                const float groundRaw  = *reinterpret_cast<float*>(unitObject + 0xA34);
                const float swimRaw    = *reinterpret_cast<float*>(unitObject + 0xA3C);

                currentSpeed = std::round(static_cast<double>(currentRaw) * 10000.0) / 10000.0;
                groundSpeed  = std::round(static_cast<double>(groundRaw)  * 10000.0) / 10000.0;
                swimSpeed    = std::round(static_cast<double>(swimRaw)    * 10000.0) / 10000.0;
            }

            lua_pushnumber(L, currentSpeed);
            lua_pushnumber(L, groundSpeed);
            lua_pushnumber(L, swimSpeed);
            return 3;
        }
'''

text = text.replace(marker, block + marker, 1)
path.write_text(text, encoding="utf-8", newline="\n")

final = path.read_text(encoding="utf-8")
for needle in ('cmd == "speed"', 'unitObject + 0xA2C', 'unitObject + 0xA34', 'unitObject + 0xA3C', '10000.0'):
    if needle not in final:
        raise SystemExit(f"postcondition missing: {needle}")

print("UnitXP X2.0 speed API port: OK")
