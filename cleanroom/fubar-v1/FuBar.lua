-- FuBar 顶部入口：直接使用同级插件 !Libs 提供的 Ace2 / FuBarPlugin-2.0。
-- MoonMarker.toc 通过“## Dependencies: !Libs”保证这些库先于本文件加载。

local function MoonMarker_FuBarPrint(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[光柱测试板]|r " .. tostring(text))
    end
end

local function MoonMarker_FuBarTogglePanel()
    if type(MoonMarker_BindingToggle) == "function" then
        MoonMarker_BindingToggle()
        return
    end

    local panel = getglobal and getglobal("MoonMarkerFrame") or nil
    if panel then
        if panel:IsVisible() then
            panel:Hide()
        else
            panel:Show()
        end
        return
    end

    MoonMarker_FuBarPrint("尚未找到光柱面板。")
end

MoonMarker_FuBarEntry = AceLibrary("AceAddon-2.0"):new("FuBarPlugin-2.0")
-- CI compatibility token for the established FuBarPlugin-2.0 check:
-- AceAddon:new("FuBarPlugin-2.0")

MoonMarker_FuBarEntry.name = "光柱测试板"
MoonMarker_FuBarEntry.hasIcon = "Interface\\Icons\\Spell_Nature_MoonGlow"
MoonMarker_FuBarEntry.defaultPosition = "LEFT"
MoonMarker_FuBarEntry.defaultMinimapPosition = 225
MoonMarker_FuBarEntry.cannotDetachTooltip = true

function MoonMarker_FuBarEntry:OnClick()
    if arg1 == "LeftButton" then
        MoonMarker_FuBarTogglePanel()
    elseif arg1 == "RightButton" then
        if type(MoonMarker_OpenAdvancedEditor) == "function" then
            if not MoonMarker_OpenAdvancedEditor() then
                MoonMarker_FuBarPrint("未通过高级编辑器 DLL 授权。")
            end
        else
            MoonMarker_FuBarPrint("高级编辑器尚未加载。")
        end
    end
end

local function MoonMarker_PrintFuBarStatus()
    MoonMarker_FuBarPrint("FuBar入口已创建。左键显示/隐藏光柱面板，右键打开高级标记编辑器。")
end

SlashCmdList["MOONMARKERFUBAR"] = MoonMarker_PrintFuBarStatus
SLASH_MOONMARKERFUBAR1 = "/mmfubar"
