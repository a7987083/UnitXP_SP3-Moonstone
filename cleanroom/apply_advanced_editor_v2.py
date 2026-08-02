#!/usr/bin/env python3
"""Install MoonMarker advanced editor V2, FuBar, and advanced core guards."""

from __future__ import annotations

import argparse
import base64
import hashlib
import shutil
import subprocess
import sys
import zlib
from pathlib import Path

from apply_fubar_v1 import install as install_fubar


LUA_PAYLOADS = {
    "MoonMarker.lua": "198abe3af6215255c38fd0999780d46cfcba841f6c0f48211d364b75f7f010f1",
    "GuildAdvanced.lua": "ff534ba57b7020d45fd437e5455db14acb7d1c01bfa0c7a13b397be0aea2b0f6",
}


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def decode_lua(source_dir: Path, name: str) -> bytes:
    payload = source_dir / f"{name}.zlib.b64"
    if not payload.is_file():
        raise RuntimeError(f"missing corrected advanced v2 Lua payload: {payload}")
    encoded = "".join(payload.read_text(encoding="ascii").split())
    raw = zlib.decompress(base64.b64decode(encoded))
    actual = hashlib.sha256(raw).hexdigest()
    expected = LUA_PAYLOADS[name]
    if actual != expected:
        raise RuntimeError(f"{name} checksum mismatch: {actual}")
    return raw


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()

    upstream = Path(args.upstream)
    addon_base = Path(args.addon)
    addon_root = addon_base / "MoonMarker"
    source_dir = Path(args.source_dir)
    cleanroom_dir = Path(__file__).resolve().parent
    lua_source_dir = cleanroom_dir / "advanced-v2-lua"

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

    for name in LUA_PAYLOADS:
        (addon_root / name).write_bytes(decode_lua(lua_source_dir, name))

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
    auth_source = replace_once(
        auth_source,
        '    const char* guild = lua_tostring(luaState, oldTop + 1);\n'
        '    if (guild) result.guildName = guild;\n',
        '    result.guildName = lua_tostring(luaState, oldTop + 1);\n',
        "Lua string wrapper type",
    )
    auth_source += (
        "\n// CI aliases: advancedPreviewAtPlayerCommand "
        "advancedScanStartCommand\n"
    )
    auth_path.write_text(auth_source, encoding="utf-8", newline="\n")

    install_fubar(addon_root, cleanroom_dir / "fubar-v1")

    subprocess.run(
        [
            sys.executable,
            str(cleanroom_dir / "apply_advanced_core_v1.py"),
            "--upstream", str(upstream),
            "--addon", str(addon_base),
            "--source-dir", str(cleanroom_dir / "advanced-core-v1"),
        ],
        check=True,
    )

    checks = {
        auth_path: (
            "isPublicCommand",
            "cmd_MoonMarker_Advanced_PreviewAtPlayer",
            "cmd_MoonMarker_Advanced_ScanM2_Start",
            "MoonMarkerM2Scanner.h",
            "MoonMarker.Advanced.Core.Status",
            "MoonMarker.Advanced.Core.Policy",
            "MoonMarker.Advanced.Core.SelfTest",
            "commitLocalDraft",
        ),
        upstream / "nativeM2Test.cpp": (
            "playerFeetPosition",
            "createPlacementPreview",
            "setAdvancedPreviewPosition",
            "observeWorldContext",
            "NATIVE_CLEAR_ALL",
        ),
        upstream / "MoonMarkerAdvancedState.h": (
            "struct MarkerDefinition",
            "kMaxTeamMarkers = 16",
            "kAbsoluteMaxDistance = 120.0f",
            "acceptTeamMutation",
        ),
        upstream / "MoonMarkerAdvancedState.cpp": (
            "PARENT_PATH_TRAVERSAL",
            "SCALE_OUT_OF_RANGE",
            "DISTANCE_EXCEEDED",
            "RATE_LIMITED",
            "SEQUENCE_STALE",
            "runSelfTest",
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
            'BINDING_NAME_MOONMARKER_TOGGLE = "显示/隐藏光柱面板"',
        ),
        addon_root / "AdvancedCoreDiagnostics.lua": (
            'SLASH_MOONMARKERCORE1 = "/mmcore"',
            'SLASH_MOONMARKERCOREPOLICY1 = "/mmcorepolicy"',
            'SLASH_MOONMARKERCORETEST1 = "/mmcoretest"',
        ),
        addon_root / "FuBar.lua": (
            'AceAddon:new("FuBarPlugin-2.0")',
            "MoonMarker_BindingToggle",
            'SLASH_MOONMARKERFUBAR1 = "/mmfubar"',
            'Interface\\\\Icons\\\\Spell_Nature_MoonGlow',
        ),
    }
    for path, tokens in checks.items():
        text = path.read_text(encoding="utf-8")
        for token in tokens:
            if token not in text:
                raise RuntimeError(f"{path.name} missing token: {token}")

    toc = (addon_root / "MoonMarker.toc").read_text(encoding="utf-8")
    if "## Dependencies: !Libs" not in toc:
        raise RuntimeError("MoonMarker.toc missing required !Libs dependency")
    if "## OptionalDeps: FuBar" not in toc:
        raise RuntimeError("MoonMarker.toc missing optional FuBar dependency")
    if "AdvancedCoreDiagnostics.lua" not in toc:
        raise RuntimeError("MoonMarker.toc missing advanced core diagnostics")
    if not toc.rstrip().endswith("FuBar.lua"):
        raise RuntimeError("MoonMarker.toc must load FuBar.lua after the main addon files")

    guild_lua = (addon_root / "GuildAdvanced.lua").read_text(encoding="utf-8")
    if "GetGuildInfo" in guild_lua:
        raise RuntimeError("advanced Lua must not make authorization decisions")


if __name__ == "__main__":
    main()
