-- DLL-authorized guild entry button for future MoonMarker advanced features.
-- Lua only controls visibility. The DLL is the authority for membership.

local guildName = nil
local authReason = "GUILD_NOT_READY"
local isTargetGuildMember = false

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd56a[光柱测试板]|r " .. tostring(message))
end

local function QueryDLLAuth()
    if type(UnitXP) ~= "function" then
        return false, nil, "DLL_MISSING"
    end

    local callOK, allowed, detectedGuild, reason = pcall(UnitXP, "MMAuth")
    if not callOK then
        return false, nil, "DLL_CALL_FAILED"
    end

    local granted = allowed == true or allowed == 1
    if not detectedGuild or detectedGuild == "" then detectedGuild = nil end
    return granted, detectedGuild, reason or "AUTH_UNAVAILABLE"
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

local function UpdateGuildAccess()
    isTargetGuildMember, guildName, authReason = QueryDLLAuth()
    if isTargetGuildMember then
        advancedButton:Show()
    else
        advancedButton:Hide()
    end
    return isTargetGuildMember
end

advancedButton:SetScript("OnClick", function()
    if UpdateGuildAccess() then
        Print("已确认：你是太阳神殿工会成员。")
    end
end)

advancedButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("太阳神殿工会成员入口")
    GameTooltip:AddLine("成员身份由 UnitXP_SP3.dll 验证。", 0.85, 0.85, 0.85)
    GameTooltip:Show()
end)
advancedButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
advancedButton:Hide()

-- Read-only helpers reserved for the future advanced panel.
function MoonMarker_IsTargetGuildMember()
    return UpdateGuildAccess()
end

function MoonMarker_GetDetectedGuildName()
    UpdateGuildAccess()
    return guildName
end

function MoonMarker_GetAuthReason()
    UpdateGuildAccess()
    return authReason
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

    if authReason ~= "GUILD_NOT_READY" or this.retryCount >= 10 then
        this.retrying = false
    end
end)
