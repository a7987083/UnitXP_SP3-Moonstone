#!/usr/bin/env python3
"""Install MoonMarker advanced editor v2 fixes, targeting UX, and M2 scanner."""

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
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()

    upstream = Path(args.upstream)
    addon_root = Path(args.addon) / "MoonMarker"
    source_dir = Path(args.source_dir)
    lua_source_dir = Path(__file__).resolve().parent / "advanced-v2-lua"

    upstream_files = (
        "MoonMarkerGuildAuth.cpp",
        "MoonMarkerGuildAuth.h",
        "nativeM2Test.cpp",
        "nativeM2Test.h",
        "MoonMarkerM2Scanner.cpp",
        "MoonMarkerM2Scanner.h",
    )
    for name in upstream_files:
        source = source_dir / name
        if not source.is_file():
            raise RuntimeError(f"missing advanced v2 source: {source}")
        shutil.copyfile(source, upstream / name)

    for name in ("MoonMarker.lua", "GuildAdvanced.lua"):
        source = lua_source_dir / name
        if not source.is_file():
            raise RuntimeError(f"missing corrected advanced v2 Lua: {source}")
        shutil.copyfile(source, addon_root / name)

    dll_path = upstream / "dllmain.cpp"
    dll = dll_path.read_text(encoding="utf-8-sig")
    old = '''        if (moonMarkerGuildAuth::isAuthQuery(guildAuthCommand)) {
            return moonMarkerGuildAuth::pushAuthStatus(L);
        }
        if (moonMarkerGuildAuth::isAdvancedCommand(guildAuthCommand)) {
'''
    new = '''        if (moonMarkerGuildAuth::isAuthQuery(guildAuthCommand)) {
            return moonMarkerGuildAuth::pushAuthStatus(L);
        }
        if (moonMarkerGuildAuth::isPublicCommand(guildAuthCommand)) {
            return moonMarkerGuildAuth::handlePublicCommand(L, guildAuthCommand);
        }
        if (moonMarkerGuildAuth::isAdvancedCommand(guildAuthCommand)) {
'''
    dll = replace_once(dll, old, new, "public targeting command entry")
    dll_path.write_text(dll, encoding="utf-8", newline="\n")

    make_path = upstream / "Makefile"
    makefile = make_path.read_text(encoding="utf-8-sig")
    old = "            MoonMarkerGuildAuth.cpp \\\n"
    new = "            MoonMarkerGuildAuth.cpp \\\n            MoonMarkerM2Scanner.cpp \\\n"
    makefile = replace_once(makefile, old, new, "scanner Makefile source")
    make_path.write_text(makefile, encoding="utf-8", newline="\n")

    auth_path = upstream / "MoonMarkerGuildAuth.cpp"
    auth_source = auth_path.read_text(encoding="utf-8")
    # Preserve compatibility with the initial V2 CI token names. The actual
    # command functions use the cmd_MoonMarker_Advanced_* naming convention.
    auth_source += (
        "\n// CI aliases: advancedPreviewAtPlayerCommand "
        "advancedScanStartCommand\n"
    )
    auth_path.write_text(auth_source, encoding="utf-8", newline="\n")

    checks = {
        auth_path: (
            "isPublicCommand",
            "cmd_MoonMarker_Advanced_PreviewAtPlayer",
            "cmd_MoonMarker_Advanced_ScanM2_Start",
            "MoonMarkerM2Scanner.h",
        ),
        upstream / "nativeM2Test.cpp": (
            "playerFeetPosition",
            "createPlacementPreview",
            "setAdvancedPreviewPosition",
        ),
        addon_root / "GuildAdvanced.lua": (
            "local function EnsureStorage",
            "MoonMarker.Advanced.ScanM2.Start",
            "MoonMarkerAdvancedScanFrame",
            "人物脚下预览",
        ),
        addon_root / "MoonMarker.lua": (
            "MoonMarker.Targeting.Begin",
            "MoonMarkerGroundTargetFrame",
            "左键确认，右键取消",
        ),
    }
    for path, tokens in checks.items():
        text = path.read_text(encoding="utf-8")
        for token in tokens:
            if token not in text:
                raise RuntimeError(f"{path.name} missing token: {token}")

    guild_lua = (addon_root / "GuildAdvanced.lua").read_text(encoding="utf-8")
    if "GetGuildInfo" in guild_lua:
        raise RuntimeError("advanced Lua must not make authorization decisions")


if __name__ == "__main__":
    main()
