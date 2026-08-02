-- MoonMarker optional FuBar entry for WoW 1.12 / Turtle WoW.
-- This file must never prevent the main addon from loading when Ace2 or
-- FuBarPlugin-2.0 is unavailable.

MoonMarker_FuBar = MoonMarker_FuBar or nil
MoonMarker_FuBarStatus = MoonMarker_FuBarStatus or "NOT_INITIALIZED"

local function FuBarPrint(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[光柱测试板]|r " .. tostring(text))
    end
end

local function ToggleMoonMarkerPanel()
    if type(MoonMarker_BindingToggle) == "function" then
        MoonMarker_BindingToggle()
        return true
    end

    local panel = getglobal and getglobal("MoonMarkerFrame") or nil
    if panel then
        if panel:IsVisible() then
            panel:Hide()
        else
            panel:Show()
        end
        return true
    end

    FuBarPrint("尚未找到光柱面板。")
    return false
end

local function RegisterMoonMarkerFuBar()
    if MoonMarker_FuBar then
        MoonMarker_FuBarStatus = "READY"
        return true
    end

    if type(AceLibrary) ~= "function" then
        MoonMarker_FuBarStatus = "ACE_LIBRARY_MISSING"
        return false
    end

    local okAddon, AceAddon = pcall(AceLibrary, "AceAddon-2.0")
    local okPlugin = pcall(AceLibrary, "FuBarPlugin-2.0")
    if not okAddon or not AceAddon or not okPlugin then
        MoonMarker_FuBarStatus = "FUBAR_PLUGIN_MISSING"
        return false
    end

    local okCreate, plugin = pcall(function()
        return AceAddon:new("FuBarPlugin-2.0")
    end)
    if not okCreate or not plugin then
        MoonMarker_FuBarStatus = "CREATE_FAILED"
        return false
    end

    MoonMarker_FuBar = plugin
    MoonMarker_FuBarStatus = "READY"

    plugin.name = "光柱测试板"
    plugin.hasIcon = "Interface\\AddOns\\MoonMarker\\Textures\\moonbeam"
    plugin.defaultPosition = "LEFT"
    plugin.defaultMinimapPosition = 225
    plugin.cannotDetachTooltip = true

    function plugin:OnClick()
        if arg1 == "LeftButton" then
            ToggleMoonMarkerPanel()
        elseif arg1 == "RightButton" then
            FuBarPrint("左键：显示/隐藏光柱面板。也可以在按键设置中绑定。")
        end
    end

    return true
end

local retryFrame = CreateFrame("Frame", "MoonMarkerFuBarRetryFrame")
retryFrame:RegisterEvent("PLAYER_LOGIN")
retryFrame:SetScript("OnEvent", function()
    if RegisterMoonMarkerFuBar() then
        this:UnregisterAllEvents()
    end
end)

RegisterMoonMarkerFuBar()

local function PrintFuBarStatus()
    if MoonMarker_FuBar then
        FuBarPrint("FuBar入口已创建。左键可显示/隐藏光柱面板。")
    else
        FuBarPrint("FuBar入口未创建：" .. tostring(MoonMarker_FuBarStatus) .. "。插件其他功能不受影响。")
    end
end

SlashCmdList["MOONMARKERFUBAR"] = PrintFuBarStatus
SLASH_MOONMARKERFUBAR1 = "/mmfubar"
