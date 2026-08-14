#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
p = root / "dllmain.cpp"
s = p.read_text(encoding="utf-8-sig")

if 'cmd == "facing"' in s:
    print("facing API already present")
    raise SystemExit(0)

needle = '''        else if (cmd == "behind" && lua_gettop(L) >= 3) {\n'''
if needle not in s:
    raise SystemExit("could not find behind command insertion point")

block = r'''        else if (cmd == "facing" && lua_gettop(L) >= 2) {
            // Lightweight native unit facing in radians. No timer/thread/cache is created;
            // the value is read only when Lua explicitly calls UnitXP("facing", unit).
            string unitName{ lua_tostring(L, 2) };
            uint64_t guid = 0;

            if (unitName.find(u8"0x") == 0) {
                stringstream ss{ unitName };
                ss >> hex >> guid;
                if (ss.fail()) {
                    lua_pushnil(L);
                    return 1;
                }
            }
            else {
                guid = vanilla1121_unitGUID(unitName.data());
            }

            if (guid == 0) {
                lua_pushnil(L);
                return 1;
            }

            uint32_t unit = vanilla1121_getVisiableObject(guid);
            if (unit == 0 || (unit & 1) != 0) {
                lua_pushnil(L);
                return 1;
            }

            uint32_t type = vanilla1121_objectType(unit);
            if (type != OBJECT_TYPE_Unit && type != OBJECT_TYPE_Player) {
                lua_pushnil(L);
                return 1;
            }

            float value = vanilla1121_unitFacing(unit);
            if (!std::isfinite(value)) {
                lua_pushnil(L);
                return 1;
            }

            lua_pushnumber(L, static_cast<double>(value));
            return 1;
        }
'''

s = s.replace(needle, block + needle, 1)
p.write_text(s, encoding="utf-8")
print("Added UnitXP(\"facing\", unit) native API")
