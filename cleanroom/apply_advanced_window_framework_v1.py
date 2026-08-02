#!/usr/bin/env python3
"""Install the phase-1 advanced marker editor window framework."""

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
    source = source_dir / "AdvancedEditorFramework.lua"
    if not source.is_file():
        raise RuntimeError(f"missing advanced editor framework source: {source}")

    target = addon_root / "AdvancedEditorFramework.lua"
    shutil.copyfile(source, target)

    toc_path = addon_root / "MoonMarker.toc"
    toc = toc_path.read_text(encoding="utf-8-sig")
    if "AdvancedEditorFramework.lua" not in toc:
        toc = replace_once(
            toc,
            "GuildAdvanced.lua\n",
            "GuildAdvanced.lua\nAdvancedEditorFramework.lua\n",
            "advanced framework toc entry",
        )
    toc = toc.replace("## Version: 0.2.1-test", "## Version: 0.3.0-test", 1)
    toc_path.write_text(toc, encoding="utf-8", newline="\n")

    help_path = addon_root / "高级编辑器框架说明.txt"
    help_path.write_text(
        "高级标记编辑器框架 V1\n"
        "\n"
        "普通面板的“高级”按钮：打开新框架。\n"
        "FuBar 左键：显示/隐藏普通光柱面板。\n"
        "FuBar 右键：打开高级标记编辑器。\n"
        "命令：/mmadvanced\n"
        "\n"
        "本阶段只增加窗口、分页、本地预览勾选、权限与身份显示。\n"
        "高级团队同步和自动重登恢复均未启用。\n",
        encoding="utf-8",
        newline="\n",
    )

    final = target.read_text(encoding="utf-8")
    required = (
        'MoonMarkerAdvancedEditorFrame',
        'MoonMarkerDB.advancedLocalPreview',
        'MoonMarkerDB.advancedEditorTab',
        'MoonMarkerDB.advancedEditorPoint',
        'label = "模型编辑"',
        'label = "顶部模型"',
        'label = "模型库"',
        'label = "当前标记"',
        'label = "预设"',
        'label = "设置诊断"',
        'function MoonMarker_OpenAdvancedEditor()',
        'function MoonMarker_ToggleAdvancedEditor()',
        'SLASH_MOONMARKERADVANCED1 = "/mmadvanced"',
        '自动重登恢复仍然禁用',
    )
    for token in required:
        if token not in final:
            raise RuntimeError("missing advanced editor framework token: " + token)

    forbidden = (
        'SendAddonMessage(',
        'MoonMarker.Remote',
        'MoonMarker.Clear',
        'SYNCREQ',
        'TEAM_SYNC_INTERVAL',
    )
    for token in forbidden:
        if token in final:
            raise RuntimeError("framework must not mutate or synchronize scenes: " + token)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()
    install(Path(args.addon) / "MoonMarker", Path(args.source_dir))


if __name__ == "__main__":
    main()
