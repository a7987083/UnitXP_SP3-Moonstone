-- MoonMarker: native M2 beams with eight independent colors and eight markers.
-- Turtle WoW / Vanilla 1.12 compatible; no Lua PlayerModel is used.

MoonMarkerDB = MoonMarkerDB or {}

local PREFIX = "MOONMARK"
local colors = {
    { key = "red",    label = "红", r = 1.00, g = 0.18, b = 0.18 },
    { key = "orange", label = "橙", r = 1.00, g = 0.45, b = 0.10 },
    { key = "yellow", label = "黄", r = 1.00, g = 0.82, b = 0.16 },
    { key = "green",  label = "绿", r = 0.15, g = 0.92, b = 0.28 },
    { key = "cyan",   label = "青", r = 0.10, g = 0.90, b = 0.90 },
    { key = "blue",   label = "蓝", r = 0.20, g = 0.55, b = 1.00 },
    { key = "purple", label = "紫", r = 0.68, g = 0.28, b = 1.00 },
    { key = "white",  label = "白", r = 0.86, g = 0.92, b = 1.00 },
}

local markers = {
    { key = "star",     label = "星", name = "星星" },
    { key = "circle",   label = "圆", name = "圆圈" },
    { key = "diamond",  label = "菱", name = "菱形" },
    { key = "triangle", label = "三", name = "三角" },
    { key = "moon",     label = "月", name = "月牙" },
    { key = "square",   label = "方", name = "方块" },
    { key = "cross",    label = "叉", name = "十字" },
    { key = "skull",    label = "骷", name = "骷髅" },
}

local colorByKey = {}
local markerByKey = {}
for _, info in ipairs(colors) do colorByKey[info.key] = info end
for _, info in ipairs(markers) do markerByKey[info.key] = info end

local selectedColor = MoonMarkerDB.selectedColor or "white"
local selectedMarker = MoonMarkerDB.selectedMarker or "skull"
if not colorByKey[selectedColor] then selectedColor = "white" end
if not markerByKey[selectedMarker] then selectedMarker = "skull" end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff91cfff[MoonMarker]|r " .. tostring(message))
end

local function HasDLL()
    return type(UnitXP) == "function"
end

local function GroupChannel()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

local function CanBroadcast()
    local channel = GroupChannel()
    if not channel then return true end
    if channel == "RAID" then
        return (IsPartyLeader("player") == 1) or (IsRaidOfficer and IsRaidOfficer() == 1)
    end
    return IsPartyLeader("player") == 1
end

local function Broadcast(payload)
    local channel = GroupChannel()
    if channel and CanBroadcast() then SendAddonMessage(PREFIX, payload, channel) end
end

local function SaveSelection()
    MoonMarkerDB.selectedColor = selectedColor
    MoonMarkerDB.selectedMarker = selectedMarker
end

local frame
local title
local colorButtons = {}
local markerButtons = {}

local function RefreshSelection()
    for key, button in pairs(colorButtons) do
        button:SetAlpha(key == selectedColor and 1.0 or 0.48)
    end
    for key, button in pairs(markerButtons) do
        button:SetAlpha(key == selectedMarker and 1.0 or 0.48)
    end
    if title then
        local c = colorByKey[selectedColor]
        local m = markerByKey[selectedMarker]
        title:SetText("MoonMarker  " .. (c and c.label or selectedColor) .. "色 + " .. (m and m.name or selectedMarker))
    end
end

local function SelectColor(color)
    if not colorByKey[color] then return end
    selectedColor = color
    SaveSelection()
    RefreshSelection()
end

local function SelectMarker(marker)
    if not markerByKey[marker] then return end
    selectedMarker = marker
    SaveSelection()
    RefreshSelection()
end

local function Place(color, marker)
    color = string.lower(color or selectedColor)
    marker = string.lower(marker or selectedMarker)
    if not colorByKey[color] then
        Print("未知颜色：" .. tostring(color))
        return
    end
    if not markerByKey[marker] then
        Print("未知标记：" .. tostring(marker))
        return
    end
    if not HasDLL() then
        Print("未检测到新版 UnitXP_SP3.dll")
        return
    end
    if GroupChannel() and not CanBroadcast() then
        Print("只有队长、团长或助理可以同步光柱")
        return
    end

    local ok, x, y, z, normalizedColor, normalizedMarker =
        pcall(UnitXP, "MoonMarker.Place", color, marker)
    if not ok then
        Print("DLL 调用失败：" .. tostring(x))
        return
    end
    if not x then
        Print("鼠标下没有可放置的地面")
        return
    end

    normalizedColor = normalizedColor or color
    normalizedMarker = normalizedMarker or marker
    SelectColor(normalizedColor)
    SelectMarker(normalizedMarker)
    Broadcast(string.format("PLACE %s %s %.5f %.5f %.5f",
        normalizedColor, normalizedMarker, x, y, z))
    Print("已放置：" .. normalizedColor .. " + " .. normalizedMarker)
end

local function Clear(send)
    if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
    if send then Broadcast("CLEAR") end
    Print("已清除全部光柱和标记")
end

local function Status()
    if not HasDLL() then
        Print("未检测到新版 UnitXP_SP3.dll")
        return
    end
    local ok, count, draws, projected, texture, hook = pcall(UnitXP, "MoonMarker.Status")
    if not ok then
        Print("状态查询失败：" .. tostring(count))
        return
    end
    local okM2, m2 = pcall(UnitXP, "M2Status")
    local active = okM2 and m2 and m2.activeCount or "?"
    Print(string.format("记录=%s，原生M2=%s，Present钩子=%s，图标投影=%s",
        tostring(count), tostring(active), hook and "已安装" or "未安装", tostring(projected)))
end

frame = CreateFrame("Frame", "MoonMarkerFrame", UIParent)
frame:SetWidth(370)
frame:SetHeight(78)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() this:StartMoving() end)
frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local point, _, relativePoint, x, y = this:GetPoint(1)
    MoonMarkerDB.point = point
    MoonMarkerDB.relativePoint = relativePoint
    MoonMarkerDB.x = x
    MoonMarkerDB.y = y
end)

local background = frame:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(frame)
background:SetTexture(0.02, 0.03, 0.06, 0.88)

local border = frame:CreateTexture(nil, "BORDER")
border:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
border:SetTexture(0.15, 0.28, 0.48, 0.42)

title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 4, 2)

local function MakeColorButton(index, info)
    local button = CreateFrame("Button", "MoonMarkerColorButton" .. index, frame)
    button:SetWidth(32)
    button:SetHeight(30)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 5 + (index - 1) * 36, -5)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    texture:SetTexture(info.r, info.g, info.b, 0.92)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetText(info.label)
    button:SetScript("OnClick", function() SelectColor(info.key) end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("选择" .. info.label .. "色")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    colorButtons[info.key] = button
end

local function MakeMarkerButton(index, info)
    local button = CreateFrame("Button", "MoonMarkerIconButton" .. index, frame)
    button:SetWidth(32)
    button:SetHeight(30)
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5 + (index - 1) * 36, 5)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    texture:SetTexture(0.18, 0.24, 0.36, 0.94)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetText(info.label)
    button:SetScript("OnClick", function() SelectMarker(info.key) end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("选择" .. info.name .. "标记")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    markerButtons[info.key] = button
end

for i, info in ipairs(colors) do MakeColorButton(i, info) end
for i, info in ipairs(markers) do MakeMarkerButton(i, info) end

local placeButton = CreateFrame("Button", "MoonMarkerPlaceButton", frame)
placeButton:SetWidth(34)
placeButton:SetHeight(30)
placeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
local placeTexture = placeButton:CreateTexture(nil, "ARTWORK")
placeTexture:SetAllPoints(placeButton)
placeTexture:SetTexture(0.10, 0.62, 0.34, 0.94)
local placeText = placeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
placeText:SetPoint("CENTER", placeButton, "CENTER", 0, 0)
placeText:SetText("放")
placeButton:SetScript("OnClick", function() Place(selectedColor, selectedMarker) end)

local clearButton = CreateFrame("Button", "MoonMarkerClearButton", frame)
clearButton:SetWidth(34)
clearButton:SetHeight(30)
clearButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
local clearTexture = clearButton:CreateTexture(nil, "ARTWORK")
clearTexture:SetAllPoints(clearButton)
clearTexture:SetTexture(0.58, 0.16, 0.18, 0.94)
local clearText = clearButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
clearText:SetPoint("CENTER", clearButton, "CENTER", 0, 0)
clearText:SetText("清")
clearButton:SetScript("OnClick", function() Clear(true) end)

RefreshSelection()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if MoonMarkerDB.point then
            frame:ClearAllPoints()
            frame:SetPoint(MoonMarkerDB.point, UIParent,
                MoonMarkerDB.relativePoint or MoonMarkerDB.point,
                MoonMarkerDB.x or 0, MoonMarkerDB.y or 0)
        end
        selectedColor = MoonMarkerDB.selectedColor or selectedColor
        selectedMarker = MoonMarkerDB.selectedMarker or selectedMarker
        if not colorByKey[selectedColor] then selectedColor = "white" end
        if not markerByKey[selectedMarker] then selectedMarker = "skull" end
        RefreshSelection()
        if MoonMarkerDB.hidden then frame:Hide() end
        Print("已加载：8种颜色 × 8个标记。/mmark red skull 可直接放置")
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = arg1, arg2, arg3, arg4
        if prefix ~= PREFIX or not HasDLL() then return end
        local playerName = UnitName("player")
        if sender and playerName and string.lower(sender) == string.lower(playerName) then return end
        if message == "CLEAR" then
            pcall(UnitXP, "MoonMarker.Clear")
            return
        end

        local _, _, color, marker, x, y, z = string.find(message or "",
            "^PLACE%s+(%S+)%s+(%S+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)$")
        if color and marker and x and y and z then
            pcall(UnitXP, "MoonMarker.Remote", color, tonumber(x), tonumber(y), tonumber(z), marker)
            return
        end

        -- Backward compatibility with Native White Team Sync v1 messages.
        local _, _, oldColor, oldX, oldY, oldZ = string.find(message or "",
            "^PLACE%s+(%S+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)$")
        if oldColor and oldX and oldY and oldZ then
            pcall(UnitXP, "MoonMarker.Remote", oldColor,
                tonumber(oldX), tonumber(oldY), tonumber(oldZ))
        end
    end
end)

SLASH_MOONMARKER1 = "/moonmarker"
SLASH_MOONMARKER2 = "/mmark"
SlashCmdList["MOONMARKER"] = function(message)
    local command = string.lower(message or "")
    command = string.gsub(command, "^%s+", "")
    command = string.gsub(command, "%s+$", "")

    if command == "" or command == "toggle" then
        if frame:IsShown() then
            frame:Hide()
            MoonMarkerDB.hidden = true
        else
            frame:Show()
            MoonMarkerDB.hidden = false
        end
    elseif command == "clear" then
        Clear(true)
    elseif command == "status" then
        Status()
    else
        local _, _, color, marker = string.find(command, "^(%S+)%s*(%S*)$")
        if marker == "" then marker = selectedMarker end
        Place(color, marker)
    end
end

SLASH_MOONMARKERSTATUS1 = "/mmstatus"
SlashCmdList["MOONMARKERSTATUS"] = Status

SLASH_MOONMARKERCLEAR1 = "/mmclear"
SlashCmdList["MOONMARKERCLEAR"] = function() Clear(true) end
