#!/usr/bin/env python3
"""Install the optional MoonMarker FuBar entry and clarify the panel binding."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(addon_root: Path, source_dir: Path) -> None:
    fubar_source = source_dir / "FuBar.lua"
    if not fubar_source.is_file():
        raise RuntimeError(f"missing FuBar source: {fubar_source}")
    shutil.copyfile(fubar_source, addon_root / "FuBar.lua")

    moonmarker_path = addon_root / "MoonMarker.lua"
    moonmarker = moonmarker_path.read_text(encoding="utf-8-sig")
    moonmarker = replace_once(
        moonmarker,
        'BINDING_NAME_MOONMARKER_TOGGLE = "显示或隐藏测试板"',
        'BINDING_NAME_MOONMARKER_TOGGLE = "显示/隐藏光柱面板"',
        "panel binding label",
    )
    moonmarker_path.write_text(moonmarker, encoding="utf-8", newline="\n")

    bindings_path = addon_root / "Bindings.xml"
    bindings = bindings_path.read_text(encoding="utf-8-sig")
    if bindings.count('name="MOONMARKER_TOGGLE"') != 1:
        raise RuntimeError("Bindings.xml must contain exactly one MOONMARKER_TOGGLE binding")
    if "MoonMarker_BindingToggle()" not in bindings:
        raise RuntimeError("MOONMARKER_TOGGLE is not connected to MoonMarker_BindingToggle")

    toc_path = addon_root / "MoonMarker.toc"
    toc = toc_path.read_text(encoding="utf-8-sig")
    if "## OptionalDeps:" not in toc:
        toc = replace_once(
            toc,
            "## Version: 0.1.0\n",
            "## Version: 0.2.1-test\n## OptionalDeps: !Libs, FuBar\n",
            "toc optional dependencies",
        )
    else:
        raise RuntimeError("unexpected existing OptionalDeps line; review required")

    toc = replace_once(
        toc,
        "MoonMarker.lua\nGuildAdvanced.lua\n",
        "MoonMarker.lua\nGuildAdvanced.lua\nFuBar.lua\n",
        "toc FuBar load order",
    )
    toc_path.write_text(toc, encoding="utf-8", newline="\n")

    fubar = (addon_root / "FuBar.lua").read_text(encoding="utf-8")
    required = (
        'AceAddon:new("FuBarPlugin-2.0")',
        "MoonMarker_BindingToggle",
        'SLASH_MOONMARKERFUBAR1 = "/mmfubar"',
        "ACE_LIBRARY_MISSING",
        "FUBAR_PLUGIN_MISSING",
    )
    for token in required:
        if token not in fubar:
            raise RuntimeError(f"FuBar.lua missing token: {token}")

    help_path = addon_root / "FuBar说明.txt"
    help_path.write_text(
        "光柱测试板 FuBar 入口\n"
        "\n"
        "需要启用兼容的 !Libs 与 FuBar。\n"
        "左键 FuBar 图标：显示/隐藏光柱面板。\n"
        "右键 FuBar 图标：显示简短使用说明。\n"
        "诊断命令：/mmfubar\n"
        "未安装 FuBar 时，光柱测试板其他功能仍可正常使用。\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()

    install(Path(args.addon) / "MoonMarker", Path(args.source_dir))


if __name__ == "__main__":
    main()
