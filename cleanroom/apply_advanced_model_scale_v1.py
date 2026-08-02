#!/usr/bin/env python3
"""Share advanced preview transform state with the new editor model page."""

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
    path = addon_root / "GuildAdvanced.lua"
    source = path.read_text(encoding="utf-8")

    source = replace_once(
        source,
        '''    if type(MoonMarkerDB.advancedFavorites) ~= "table" then
        MoonMarkerDB.advancedFavorites = {}
    end
end

EnsureStorage()
''',
        '''    if type(MoonMarkerDB.advancedFavorites) ~= "table" then
        MoonMarkerDB.advancedFavorites = {}
    end
    if type(MoonMarkerDB.advancedScale) ~= "number" then
        MoonMarkerDB.advancedScale = 1.00
    end
    if type(MoonMarkerDB.advancedYaw) ~= "number" then
        MoonMarkerDB.advancedYaw = 0.00
    end
end

EnsureStorage()
previewScale = tonumber(MoonMarkerDB.advancedScale) or 1.00
previewYaw = tonumber(MoonMarkerDB.advancedYaw) or 0.00
''',
        "shared transform storage",
    )

    source = replace_once(
        source,
        '''    previewScale = tonumber(appliedScale) or previewScale
    previewYaw = tonumber(appliedYaw) or previewYaw
    SetStatus(string.format("当前模型：缩放 %.2f，旋转 %.1f°", previewScale, previewYaw))
end
''',
        '''    previewScale = tonumber(appliedScale) or previewScale
    previewYaw = tonumber(appliedYaw) or previewYaw
    MoonMarkerDB.advancedScale = previewScale
    MoonMarkerDB.advancedYaw = previewYaw
    if type(MoonMarker_AdvancedScaleRefresh) == "function" then
        pcall(MoonMarker_AdvancedScaleRefresh)
    end
    SetStatus(string.format("当前模型：缩放 %.2f，旋转 %.1f°", previewScale, previewYaw))
end
''',
        "persist applied transform",
    )

    source = replace_once(
        source,
        '''    SetSelectedPath(normalized)
    RememberPath(normalized)
    RefreshList()
    SetStatus((description or "已预览") .. "，旋转 " .. string.format("%.1f°", previewYaw))
''',
        '''    SetSelectedPath(normalized)
    RememberPath(normalized)
    MoonMarkerDB.advancedScale = previewScale
    MoonMarkerDB.advancedYaw = previewYaw
    RefreshList()
    if type(MoonMarker_AdvancedScaleRefresh) == "function" then
        pcall(MoonMarker_AdvancedScaleRefresh)
    end
    SetStatus((description or "已预览") .. "，大小 "
        .. string.format("%.2f", previewScale) .. "，旋转 "
        .. string.format("%.1f°", previewYaw))
''',
        "persist preview transform",
    )

    anchor = '''function MoonMarker_GetAuthReason()
    UpdateGuildAccess()
    return authReason
end

local eventFrame = CreateFrame("Frame", "MoonMarkerGuildAccessFrame")
'''
    bridge = '''function MoonMarker_GetAuthReason()
    UpdateGuildAccess()
    return authReason
end

function MoonMarker_AdvancedGetTransform()
    EnsureStorage()
    previewScale = tonumber(MoonMarkerDB.advancedScale) or previewScale or 1.00
    previewYaw = tonumber(MoonMarkerDB.advancedYaw) or previewYaw or 0.00
    return previewScale, previewYaw
end

function MoonMarker_AdvancedSetTransform(scale, yaw)
    EnsureStorage()
    scale = tonumber(scale)
    yaw = tonumber(yaw)
    if not scale or scale < 0.10 or scale > 5.00 then
        return false, previewScale, previewYaw, "SCALE_OUT_OF_RANGE"
    end
    if not yaw then yaw = previewYaw or 0.00 end

    previewScale = math.floor(scale * 100 + 0.5) / 100
    previewYaw = yaw
    MoonMarkerDB.advancedScale = previewScale
    MoonMarkerDB.advancedYaw = previewYaw

    if not isAuthorized then
        return false, previewScale, previewYaw, "ACCESS_DENIED"
    end
    if type(UnitXP) ~= "function" then
        return false, previewScale, previewYaw, "DLL_NOT_FOUND"
    end

    local ok, applied, appliedScale, appliedYaw = pcall(
        UnitXP, TRANSFORM_COMMAND, previewScale, previewYaw)
    if not ok then
        return false, previewScale, previewYaw, "DLL_CALL_FAILED"
    end
    if applied then
        previewScale = tonumber(appliedScale) or previewScale
        previewYaw = tonumber(appliedYaw) or previewYaw
        MoonMarkerDB.advancedScale = previewScale
        MoonMarkerDB.advancedYaw = previewYaw
        SetStatus(string.format("当前模型：缩放 %.2f，旋转 %.1f°", previewScale, previewYaw))
        return true, previewScale, previewYaw, "APPLIED"
    end

    local reason = tostring(appliedScale or "TRANSFORM_REJECTED")
    if reason == "LOCAL_DRAFT_NOT_FOUND" then
        SetStatus(string.format("大小 %.2f 已保存，将用于下一次高级预览。", previewScale))
        return true, previewScale, previewYaw, "SAVED_FOR_NEXT_PREVIEW"
    end
    return false, previewScale, previewYaw, reason
end

local eventFrame = CreateFrame("Frame", "MoonMarkerGuildAccessFrame")
'''
    source = replace_once(source, anchor, bridge, "public transform bridge")

    required = (
        "MoonMarkerDB.advancedScale",
        "MoonMarkerDB.advancedYaw",
        "function MoonMarker_AdvancedGetTransform()",
        "function MoonMarker_AdvancedSetTransform(scale, yaw)",
        '"SAVED_FOR_NEXT_PREVIEW"',
        '"SCALE_OUT_OF_RANGE"',
    )
    for token in required:
        if token not in source:
            raise RuntimeError("missing shared transform token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")

    ui_source = source_dir / "AdvancedModelScale.lua"
    if not ui_source.is_file():
        raise RuntimeError(f"missing advanced model scale UI source: {ui_source}")
    shutil.copyfile(ui_source, addon_root / "AdvancedModelScale.lua")

    toc_path = addon_root / "MoonMarker.toc"
    toc = toc_path.read_text(encoding="utf-8-sig")
    if "AdvancedModelScale.lua" not in toc:
        anchor = "AdvancedEditorFramework.lua\n"
        if anchor not in toc:
            raise RuntimeError("MoonMarker.toc missing advanced editor framework anchor")
        toc = toc.replace(anchor, anchor + "AdvancedModelScale.lua\n", 1)
    toc = toc.replace("## Version: 0.3.0-test", "## Version: 0.3.1-test", 1)
    toc_path.write_text(toc, encoding="utf-8", newline="\n")

    ui = (addon_root / "AdvancedModelScale.lua").read_text(encoding="utf-8")
    ui_required = (
        'MoonMarkerAdvancedScaleMinus',
        'MoonMarkerAdvancedScaleReset',
        'MoonMarkerAdvancedScalePlus',
        'MoonMarker_AdvancedSetTransform',
        'SCALE_MIN = 0.10',
        'SCALE_MAX = 5.00',
        'Shift 每次 0.01',
    )
    for token in ui_required:
        if token not in ui:
            raise RuntimeError("missing model scale UI token: " + token)

    forbidden = (
        'SendAddonMessage(',
        'MoonMarker.Remote',
        'MoonMarker.Clear',
        'SYNCREQ',
        'TEAM_SYNC_INTERVAL',
    )
    for token in forbidden:
        if token in ui:
            raise RuntimeError("model scale UI must not synchronize or clear scenes: " + token)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()
    install(Path(args.addon) / "MoonMarker", Path(args.source_dir))


if __name__ == "__main__":
    main()
