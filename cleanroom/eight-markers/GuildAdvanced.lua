-- Guild-only entry button for future MoonMarker advanced features.
-- This stage only identifies membership and shows a message; no advanced action is executed.

local TARGET_GUILD = "太阳神殿"
local guildName = nil
local isTargetGuildMember = false

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd56a[光柱测试板]|r " .. tostring(message))
end

local function ReadGuildName()
    if type(GetGuildInfo) ~= "function" then
        return nil
    end
    local name = GetGuildInfo("player")
    if name and name ~= "" then
        return name
    end
    return nil
end

local advancedButton = CreateFrame("Button", "MoonMarkerAdvancedButton", MoonMarkerFrame)
advancedButton:SetWidth(34)
advancedButton:SetHeight(30)
advancedButton:SetPoint("TOPRIGHT", MoonMarkerPlaceButton, "TOPLEFT", -4, 0)

local advancedTexture = advancedButton:CreateTexture(nil, "ARTWORK")
advancedTexture:SetAllPoints(advancedButton)
advancedTexture:SetTexture(0.72, 0.48, 0.08, 0.96)

local advancedText = advancedButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
advancedText:SetPoint("CENTER", advancedButton, "CENTER", 0, 0)
advancedText:SetText("高级")

advancedButton:SetScript("OnClick", function()
    local currentGuild = ReadGuildName()
    if currentGuild == TARGET_GUILD then
        Print("已确认：你是太阳神殿工会成员。")
    else
        advancedButton:Hide()
    end
end)

advancedButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("太阳神殿工会成员入口")
    GameTooltip:AddLine("当前版本仅用于识别成员身份。", 0.85, 0.85, 0.85)
    GameTooltip:Show()
end)
advancedButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
advancedButton:Hide()

local function UpdateGuildAccess()
    guildName = ReadGuildName()
    isTargetGuildMember = guildName == TARGET_GUILD
    if isTargetGuildMember then
        advancedButton:Show()
    else
        advancedButton:Hide()
    end
    return isTargetGuildMember
end

-- Read-only helpers reserved for the future advanced panel.
function MoonMarker_IsTargetGuildMember()
    return UpdateGuildAccess()
end

function MoonMarker_GetDetectedGuildName()
    UpdateGuildAccess()
    return guildName
end

local eventFrame = CreateFrame("Frame", "MoonMarkerGuildAccessFrame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame.elapsed = 0
eventFrame.retryCount = 0
eventFrame.retrying = false

eventFrame:SetScript("OnEvent", function()
    UpdateGuildAccess()
    this.elapsed = 0
    this.retryCount = 0
    this.retrying = true
    if GuildRoster then GuildRoster() end
end)

eventFrame:SetScript("OnUpdate", function()
    if not this.retrying then return end
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 1 then return end

    this.elapsed = 0
    this.retryCount = this.retryCount + 1
    UpdateGuildAccess()

    if guildName or this.retryCount >= 10 then
        this.retrying = false
    end
end)
