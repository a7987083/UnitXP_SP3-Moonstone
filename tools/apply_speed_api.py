#!/usr/bin/env python3
from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_speed_api.py <UnitXP source dir>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    dllmain = root / "dllmain.cpp"
    text = dllmain.read_text(encoding="utf-8-sig")

    marker = '        else if (cmd == "distanceBetween" && lua_gettop(L) >= 3) {'
    if marker not in text:
        raise SystemExit("speed patch marker not found in dllmain.cpp")

    if 'cmd == "speed"' in text:
        print("speed API already present; nothing to do")
        return 0

    block = r'''        else if (cmd == "speed" && lua_gettop(L) >= 2) {
            // Compatibility API from the X2.0 UnitXP_SP3 branch.
            // Legacy behavior returns three movement-speed fields, rounded to 4 decimals.
            // CAT currently consumes the first return value via UnitXP("speed", "player").
            // Keep a tiny volatile marker so post-link validation survives ThinLTO string folding.
            static volatile char speedApiBuildMarker[] = "speed";
            (void)speedApiBuildMarker[0];

            uint32_t unit = 0;
            const std::string unitID = lua_tostring(L, 2);
            if (!unitID.empty()) {
                const uint64_t guid = vanilla1121_unitGUID(unitID.c_str());
                if (guid != 0) {
                    unit = vanilla1121_getVisiableObject(guid);
                }
            }

            double speed0 = 0.0;
            double speed1 = 0.0;
            double speed2 = 0.0;

            if (unit != 0 && (unit & 1) == 0) {
                const int objectType = vanilla1121_objectType(unit);
                if (objectType == OBJECT_TYPE_Unit || objectType == OBJECT_TYPE_Player) {
                    const auto round4 = [](float value) -> double {
                        return std::round(static_cast<double>(value) * 10000.0) / 10000.0;
                    };

                    // Exact legacy X2.0 fields observed in the 432,640-byte DLL.
                    speed0 = round4(*reinterpret_cast<float*>(unit + 0xA2C));
                    speed1 = round4(*reinterpret_cast<float*>(unit + 0xA34));
                    speed2 = round4(*reinterpret_cast<float*>(unit + 0xA3C));
                }
            }

            lua_pushnumber(L, speed0);
            lua_pushnumber(L, speed1);
            lua_pushnumber(L, speed2);
            return 3;
        }
'''

    text = text.replace(marker, block + marker, 1)
    dllmain.write_text(text, encoding="utf-8", newline="\n")
    print("patched UnitXP speed API into dllmain.cpp")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
