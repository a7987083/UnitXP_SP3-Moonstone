#!/usr/bin/env python3
"""Install the phase-one MoonMarker guild authorization module."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()

    upstream = Path(args.upstream)
    source_dir = Path(args.source_dir)

    for name in ("MoonMarkerGuildAuth.h", "MoonMarkerGuildAuth.cpp"):
        source = source_dir / name
        if not source.is_file():
            raise RuntimeError(f"missing guild auth source: {source}")
        shutil.copyfile(source, upstream / name)

    dll_path = upstream / "dllmain.cpp"
    dll = dll_path.read_text(encoding="utf-8-sig")
    dll = replace_once(
        dll,
        '#include "gameEvent.h"\n',
        '#include "gameEvent.h"\n#include "MoonMarkerGuildAuth.h"\n',
        "guild auth include",
    )

    entry = '''int __fastcall detoured_UnitXP(void* L) {
'''
    guarded_entry = '''int __fastcall detoured_UnitXP(void* L) {
    const int guildAuthArgumentCount = lua_gettop(L);
    if (guildAuthArgumentCount >= 1 && lua_isstring(L, 1)) {
        const string guildAuthCommand{ lua_tostring(L, 1) };
        if (moonMarkerGuildAuth::isAuthQuery(guildAuthCommand)) {
            return moonMarkerGuildAuth::pushAuthStatus(L);
        }
        if (moonMarkerGuildAuth::isAdvancedCommand(guildAuthCommand)) {
            if (!moonMarkerGuildAuth::isAuthorized(L)) {
                return moonMarkerGuildAuth::denyAdvanced(L);
            }
            return moonMarkerGuildAuth::handleAdvancedCommand(L, guildAuthCommand);
        }
    }
'''
    dll = replace_once(dll, entry, guarded_entry, "UnitXP guild auth entry")
    dll_path.write_text(dll, encoding="utf-8", newline="\n")

    make_path = upstream / "Makefile"
    makefile = make_path.read_text(encoding="utf-8-sig")
    makefile = replace_once(
        makefile,
        "            LuaDebug.cpp \\\n",
        "            LuaDebug.cpp \\\n            MoonMarkerGuildAuth.cpp \\\n",
        "guild auth Makefile source",
    )
    make_path.write_text(makefile, encoding="utf-8", newline="\n")

    generated = (upstream / "MoonMarkerGuildAuth.cpp").read_text(encoding="utf-8")
    if "太阳神殿" in generated:
        raise RuntimeError("target guild must not be stored as a plain UTF-8 DLL string")
    for token in (
        "kLuaIsCFunctionAddress = 0x006F34A0",
        "kLuaToCFunctionAddress = 0x006F3720",
        "FUNCTION_TAMPERED",
        "ACCESS_DENIED",
        "originalGetGuildInfo",
    ):
        if token not in generated:
            raise RuntimeError(f"guild auth source missing token: {token}")


if __name__ == "__main__":
    main()
