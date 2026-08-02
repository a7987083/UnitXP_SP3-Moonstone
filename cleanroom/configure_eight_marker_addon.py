#!/usr/bin/env python3
"""Install MoonMarker key bindings, DLL guild entry, and configure TOC metadata."""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

TITLE = "光柱测试板-由太阳神殿-yanz"
SAVED_VARIABLE = "MoonMarkerDB"
GUILD_FILE = "GuildAdvanced.lua"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()

    addon_root = Path(args.addon) / "MoonMarker"
    source_dir = Path(args.source_dir)
    if not addon_root.is_dir():
        raise RuntimeError(f"addon directory does not exist: {addon_root}")

    bindings_source = source_dir / "Bindings.xml"
    if not bindings_source.is_file():
        raise RuntimeError(f"missing bindings source: {bindings_source}")
    shutil.copyfile(bindings_source, addon_root / "Bindings.xml")

    guild_source = source_dir / GUILD_FILE
    if not guild_source.is_file():
        raise RuntimeError(f"missing guild entry source: {guild_source}")
    shutil.copyfile(guild_source, addon_root / GUILD_FILE)

    toc_files = sorted(addon_root.glob("*.toc"))
    if len(toc_files) != 1:
        raise RuntimeError(f"expected one TOC file, found {len(toc_files)}")

    toc_path = toc_files[0]
    toc = toc_path.read_text(encoding="utf-8-sig")
    title_line = f"## Title: {TITLE}"
    if re.search(r"(?mi)^##\s*Title\s*:.*$", toc):
        toc = re.sub(r"(?mi)^##\s*Title\s*:.*$", title_line, toc, count=1)
    else:
        toc = title_line + "\n" + toc

    saved_pattern = r"(?mi)^##\s*SavedVariables\s*:.*$"
    saved_line = f"## SavedVariables: {SAVED_VARIABLE}"
    if re.search(saved_pattern, toc):
        toc = re.sub(saved_pattern, saved_line, toc, count=1)
    else:
        lines = toc.splitlines()
        insert_at = 0
        for index, line in enumerate(lines):
            if line.startswith("##"):
                insert_at = index + 1
        lines.insert(insert_at, saved_line)
        toc = "\n".join(lines) + "\n"

    # Load the DLL-authorized guild entry after the normal MoonMarker implementation.
    lines = [line for line in toc.splitlines() if line.strip() != GUILD_FILE]
    insert_at = len(lines)
    for index, line in enumerate(lines):
        if line.strip() == "MoonMarker.lua":
            insert_at = index + 1
            break
    lines.insert(insert_at, GUILD_FILE)
    toc = "\n".join(lines) + "\n"
    toc_path.write_text(toc, encoding="utf-8", newline="\n")

    lua = (addon_root / "MoonMarker.lua").read_text(encoding="utf-8")
    required_lua = (
        "BINDING_HEADER_MOONMARKER",
        "MoonMarker_BindingPlace",
        "MoonMarker_BindingClear",
        "SenderCanControl",
        TITLE,
    )
    for token in required_lua:
        if token not in lua:
            raise RuntimeError(f"MoonMarker.lua missing required token: {token}")

    guild_lua = (addon_root / GUILD_FILE).read_text(encoding="utf-8")
    required_guild_tokens = (
        'pcall(UnitXP, "MMAuth")',
        "MoonMarkerAdvancedButton",
        "MoonMarkerPlaceButton",
        "MoonMarker_IsTargetGuildMember",
        "MoonMarker_GetAuthReason",
        "已确认：你是太阳神殿工会成员。",
        "成员身份由 UnitXP_SP3.dll 验证。",
    )
    for token in required_guild_tokens:
        if token not in guild_lua:
            raise RuntimeError(f"GuildAdvanced.lua missing required token: {token}")
    if "GetGuildInfo(" in guild_lua or "TARGET_GUILD" in guild_lua:
        raise RuntimeError("GuildAdvanced.lua must not decide guild authorization in Lua")

    bindings = (addon_root / "Bindings.xml").read_text(encoding="utf-8")
    if bindings.count("<Binding ") != 7:
        raise RuntimeError("Bindings.xml must contain exactly seven bindings")
    if saved_line not in toc:
        raise RuntimeError("TOC SavedVariables declaration was not written")
    if title_line not in toc:
        raise RuntimeError("TOC title was not written")
    if toc.count(GUILD_FILE) != 1:
        raise RuntimeError("TOC must load GuildAdvanced.lua exactly once")


if __name__ == "__main__":
    main()
