-- 技能搜索库 v0.1.0
-- 公会-太阳神殿-yanz
-- WoW 1.12 / Lua 5.0 compatible

local SSL = {}
SSL.VERSION = "0.1.0"
SSL.PAGE_SIZE = 16
SSL.SEARCH_LIMIT = 300
SSL.results = {}
SSL.page = 1
SSL.selectedId = nil
SSL.currentSpell = nil
SSL.currentEffect = 0

local function SafeText(v)
    if v == nil then return "-" end
    if v == "" then return "-" end
    return tostring(v)
end

local function TrimText(v)
    if not v then return "" end
    v = string.gsub(v, "^%s+", "")
    v = string.gsub(v, "%s+$", "")
    return v
end

local function CallUnitXP(command, value, extra)
    if type(UnitXP) ~= "function" then
        return nil, "未检测到 UnitXP"
    end
    local ok, a, b, c, d
    if extra ~= nil then
        ok, a, b, c, d = pcall(UnitXP, command, value, extra)
    elseif value ~= nil then
        ok, a, b, c, d = pcall(UnitXP, command, value)
    else
        ok, a, b, c, d = pcall(UnitXP, command)
    end
    if not ok then return nil, a end
    return a, b, c, d
end

local function NewText(parent, font, x, y, width, justify)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local frame = CreateFrame("Frame", "SpellSearchLibraryFrame", UIParent)
SSL.frame = frame
frame:SetWidth(1000)
frame:SetHeight(690)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() this:StartMoving() end)
frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(0.035, 0.045, 0.065, 0.98)
frame:SetBackdropBorderColor(0.22, 0.38, 0.55, 1)
frame:Hide()

table.insert(UISpecialFrames, "SpellSearchLibraryFrame")

local title = NewText(frame, "GameFontNormalLarge", 18, -16, 500, "LEFT")
title:SetText("技能搜索库")
title:SetTextColor(0.82, 0.92, 1.0)

local versionText = NewText(frame, "GameFontNormalSmall", 150, -20, 160, "LEFT")
versionText:SetText("v" .. SSL.VERSION)
versionText:SetTextColor(0.45, 0.58, 0.70)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

local searchLabel = NewText(frame, "GameFontNormalSmall", 20, -53, 85, "LEFT")
searchLabel:SetText("搜索技能")
searchLabel:SetTextColor(0.65, 0.78, 0.90)

local searchBox = CreateFrame("EditBox", "SpellSearchLibrarySearchBox", frame, "InputBoxTemplate")
SSL.searchBox = searchBox
searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 95, -48)
searchBox:SetWidth(465)
searchBox:SetHeight(24)
searchBox:SetAutoFocus(false)
searchBox:SetMaxLetters(120)
searchBox:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    SpellSearchLibrary_DoSearch()
end)
searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

local searchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
searchButton:SetPoint("TOPLEFT", searchBox, "TOPRIGHT", 10, 0)
searchButton:SetWidth(78)
searchButton:SetHeight(24)
searchButton:SetText("搜索")
searchButton:SetScript("OnClick", function() SpellSearchLibrary_DoSearch() end)

local hint = NewText(frame, "GameFontNormalSmall", 660, -54, 290, "RIGHT")
hint:SetText("支持：中文 / 英文 / SpellID")
hint:SetTextColor(0.42, 0.52, 0.62)

local divider = frame:CreateTexture(nil, "ARTWORK")
divider:SetTexture(0.16, 0.25, 0.34, 0.75)
divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 338, -82)
divider:SetWidth(1)
divider:SetHeight(568)

local listHeader = NewText(frame, "GameFontNormal", 20, -89, 300, "LEFT")
listHeader:SetText("搜索结果")
listHeader:SetTextColor(0.72, 0.86, 0.98)

local resultStat = NewText(frame, "GameFontNormalSmall", 20, -112, 300, "LEFT")
SSL.resultStat = resultStat
resultStat:SetText("输入技能名称或 SpellID 后搜索")
resultStat:SetTextColor(0.46, 0.58, 0.68)

SSL.rowButtons = {}
local rowStartY = -137
local rowHeight = 29
local i
for i = 1, SSL.PAGE_SIZE do
    local b = CreateFrame("Button", nil, frame)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, rowStartY - (i - 1) * rowHeight)
    b:SetWidth(305)
    b:SetHeight(27)
    b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    b:SetBackdropColor(0.06, 0.075, 0.095, 0.80)
    b:RegisterForClicks("LeftButtonUp")
    b.slot = i
    b.nameText = NewText(b, "GameFontNormalSmall", 7, -4, 286, "LEFT")
    b.nameText:SetTextColor(0.88, 0.94, 1.0)
    b.subText = NewText(b, "GameFontNormalSmall", 7, -15, 286, "LEFT")
    b.subText:SetTextColor(0.43, 0.55, 0.64)
    b:SetScript("OnEnter", function()
        if this.resultId then this:SetBackdropColor(0.10, 0.18, 0.25, 0.95) end
    end)
    b:SetScript("OnLeave", function()
        if this.resultId == SSL.selectedId then
            this:SetBackdropColor(0.10, 0.28, 0.40, 0.95)
        else
            this:SetBackdropColor(0.06, 0.075, 0.095, 0.80)
        end
    end)
    b:SetScript("OnClick", function()
        if this.resultId then SpellSearchLibrary_SelectSpell(this.resultId) end
    end)
    SSL.rowButtons[i] = b
end

local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
prev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 42)
prev:SetWidth(76)
prev:SetHeight(22)
prev:SetText("上一页")
prev:SetScript("OnClick", function()
    if SSL.page > 1 then SSL.page = SSL.page - 1; SpellSearchLibrary_RefreshRows() end
end)
SSL.prevButton = prev

local nextb = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
nextb:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 242, 42)
nextb:SetWidth(76)
nextb:SetHeight(22)
nextb:SetText("下一页")
nextb:SetScript("OnClick", function()
    local pages = math.ceil(table.getn(SSL.results) / SSL.PAGE_SIZE)
    if pages < 1 then pages = 1 end
    if SSL.page < pages then SSL.page = SSL.page + 1; SpellSearchLibrary_RefreshRows() end
end)
SSL.nextButton = nextb

local pageText = NewText(frame, "GameFontNormalSmall", 102, -628, 132, "CENTER")
SSL.pageText = pageText
pageText:SetText("1 / 1")
pageText:SetTextColor(0.50, 0.62, 0.72)

local detailTitle = NewText(frame, "GameFontNormalLarge", 360, -90, 600, "LEFT")
SSL.detailTitle = detailTitle
detailTitle:SetText("技能详情")
detailTitle:SetTextColor(0.88, 0.94, 1.0)

local detailSub = NewText(frame, "GameFontNormalSmall", 360, -116, 600, "LEFT")
SSL.detailSub = detailSub
detailSub:SetText("从左侧选择一个技能")
detailSub:SetTextColor(0.46, 0.60, 0.72)

local descBox = CreateFrame("Frame", nil, frame)
descBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 358, -139)
descBox:SetWidth(615)
descBox:SetHeight(124)
descBox:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10, insets = {left=3,right=3,top=3,bottom=3} })
descBox:SetBackdropColor(0.035, 0.050, 0.070, 0.92)
descBox:SetBackdropBorderColor(0.14, 0.23, 0.31, 0.9)
local descTitle = NewText(descBox, "GameFontNormalSmall", 10, -8, 590, "LEFT")
descTitle:SetText("技能说明")
descTitle:SetTextColor(0.54, 0.73, 0.89)
local descText = NewText(descBox, "GameFontNormalSmall", 10, -27, 590, "LEFT")
SSL.descText = descText
descText:SetHeight(86)
descText:SetJustifyV("TOP")
descText:SetText("-")
descText:SetTextColor(0.82, 0.86, 0.90)

local tabs = {}
local tabNames = { "基础", "Effect 1", "Effect 2", "Effect 3" }
for i = 1, 4 do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 358 + (i - 1) * 108, -274)
    b:SetWidth(100)
    b:SetHeight(24)
    b:SetText(tabNames[i])
    b.effectIndex = i - 1
    b:SetScript("OnClick", function()
        SSL.currentEffect = this.effectIndex
        SpellSearchLibrary_RefreshDetail()
    end)
    tabs[i] = b
end
SSL.tabs = tabs

local fieldArea = CreateFrame("Frame", nil, frame)
SSL.fieldArea = fieldArea
fieldArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 358, -310)
fieldArea:SetWidth(615)
fieldArea:SetHeight(322)
fieldArea:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
fieldArea:SetBackdropColor(0.025, 0.035, 0.050, 0.78)

SSL.fieldLabels = {}
SSL.fieldValues = {}
for i = 1, 16 do
    local col = 0
    local row = i - 1
    if i > 8 then col = 1; row = i - 9 end
    local x = 12 + col * 302
    local y = -13 - row * 37
    local lab = NewText(fieldArea, "GameFontNormalSmall", x, y, 136, "LEFT")
    lab:SetTextColor(0.48, 0.66, 0.80)
    local val = NewText(fieldArea, "GameFontNormalSmall", x + 139, y, 150, "LEFT")
    val:SetTextColor(0.90, 0.93, 0.96)
    SSL.fieldLabels[i] = lab
    SSL.fieldValues[i] = val
end

local signature = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
signature:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17, 10)
signature:SetText("公会-太阳神殿-yanz")
signature:SetTextColor(0.31, 0.38, 0.45)

local footer = NewText(frame, "GameFontNormalSmall", 360, -654, 520, "LEFT")
SSL.footer = footer
footer:SetText("按需查询：只有搜索或选择技能时调用 UnitXP")
footer:SetTextColor(0.34, 0.44, 0.52)

local function SetField(slot, label, value)
    SSL.fieldLabels[slot]:SetText(label or "")
    SSL.fieldValues[slot]:SetText(SafeText(value))
end

local function ClearFields()
    local n
    for n = 1, 16 do
        SSL.fieldLabels[n]:SetText("")
        SSL.fieldValues[n]:SetText("")
    end
end

local function ResolveRange(index)
    if not index or index == 0 then return "-" end
    local r = CallUnitXP("spellrange", index)
    if type(r) ~= "table" then return "索引 " .. SafeText(index) end
    return SafeText(r.rangeMin) .. " ~ " .. SafeText(r.rangeMax) .. " 码"
end

local function ResolveDuration(index)
    if not index or index == 0 then return "-" end
    local d = CallUnitXP("spellduration", index)
    if type(d) ~= "table" then return "索引 " .. SafeText(index) end
    local value = d.duration
    if type(value) == "number" then
        if value < 0 then return "无限/特殊 (" .. SafeText(value) .. ")" end
        return SafeText(value) .. " ms"
    end
    return SafeText(value)
end

local function ResolveRadius(index)
    if not index or index == 0 then return "-" end
    local r = CallUnitXP("spellradius", index)
    if type(r) ~= "table" then return "索引 " .. SafeText(index) end
    return SafeText(r.radius) .. " 码"
end

local function DisplayDescription(spell)
    if not spell then SSL.descText:SetText("-"); return end
    local d = spell.descriptionZhCN
    if not d or d == "" then d = spell.descriptionEnUS end
    local aura = spell.auraDescriptionZhCN
    if not aura or aura == "" then aura = spell.auraDescriptionEnUS end
    local text = d or ""
    if aura and aura ~= "" and aura ~= text then
        if text ~= "" then text = text .. "\n|cff7892a8Aura：|r" .. aura else text = aura end
    end
    if text == "" then text = "-" end
    SSL.descText:SetText(text)
end

function SpellSearchLibrary_RefreshDetail()
    local s = SSL.currentSpell
    ClearFields()
    if not s then return end

    local i
    for i = 1, 4 do
        if SSL.tabs[i].effectIndex == SSL.currentEffect then SSL.tabs[i]:Disable() else SSL.tabs[i]:Enable() end
    end

    if SSL.currentEffect == 0 then
        SetField(1, "SpellID", s.id)
        SetField(2, "school", s.school)
        SetField(3, "mechanic", s.mechanic)
        SetField(4, "castingTimeIndex", s.castingTimeIndex)
        SetField(5, "durationIndex", s.durationIndex)
        SetField(6, "实际持续时间", ResolveDuration(s.durationIndex))
        SetField(7, "rangeIndex", s.rangeIndex)
        SetField(8, "实际范围", ResolveRange(s.rangeIndex))
        SetField(9, "radiusIndex1", s.radiusIndex1)
        SetField(10, "实际半径1", ResolveRadius(s.radiusIndex1))
        SetField(11, "radiusIndex2", s.radiusIndex2)
        SetField(12, "实际半径2", ResolveRadius(s.radiusIndex2))
        SetField(13, "radiusIndex3", s.radiusIndex3)
        SetField(14, "实际半径3", ResolveRadius(s.radiusIndex3))
        SetField(15, "DBC 来源", s.source)
        SetField(16, "recordSize", s.recordSize)
    else
        local n = tostring(SSL.currentEffect)
        SetField(1, "effect" .. n, s["effect" .. n])
        SetField(2, "applyAura" .. n, s["applyAura" .. n])
        SetField(3, "effectSimpleValue" .. n, s["effectSimpleValue" .. n])
        SetField(4, "effectDieSides" .. n, s["effectDieSides" .. n])
        SetField(5, "effectRealPointsPerLevel" .. n, s["effectRealPointsPerLevel" .. n])
        SetField(6, "effectAmplitude" .. n, s["effectAmplitude" .. n])
        SetField(7, "effectChainTarget" .. n, s["effectChainTarget" .. n])
        SetField(8, "effectMechanic" .. n, s["effectMechanic" .. n])
        SetField(9, "miscValue" .. n, s["miscValue" .. n])
        SetField(10, "triggerSpell" .. n, s["triggerSpell" .. n])
        SetField(11, "targetA" .. n, s["targetA" .. n])
        SetField(12, "targetB" .. n, s["targetB" .. n])
        SetField(13, "radiusIndex" .. n, s["radiusIndex" .. n])
        SetField(14, "实际半径", ResolveRadius(s["radiusIndex" .. n]))
        SetField(15, "中文名称", s.nameZhCN)
        SetField(16, "英文名称", s.name)
    end
end

function SpellSearchLibrary_SelectSpell(id)
    if not id then return end
    local spell, err = CallUnitXP("spell", id)
    if type(spell) ~= "table" then
        SSL.detailTitle:SetText("读取失败")
        SSL.detailSub:SetText(SafeText(err))
        SSL.currentSpell = nil
        ClearFields()
        return
    end
    SSL.selectedId = id
    SSL.currentSpell = spell
    SSL.currentEffect = 0
    local displayName = spell.nameZhCN
    if not displayName or displayName == "" then displayName = spell.name end
    if not displayName or displayName == "" then displayName = "未命名技能" end
    SSL.detailTitle:SetText(displayName .. "  |cff70879b[" .. SafeText(spell.id) .. "]|r")
    local sub = spell.name or ""
    if sub == displayName then sub = "" end
    if sub ~= "" then SSL.detailSub:SetText(sub) else SSL.detailSub:SetText("Spell.dbc 技能记录") end
    DisplayDescription(spell)
    SpellSearchLibrary_RefreshRows()
    SpellSearchLibrary_RefreshDetail()
end

function SpellSearchLibrary_RefreshRows()
    local count = table.getn(SSL.results)
    local pages = math.ceil(count / SSL.PAGE_SIZE)
    if pages < 1 then pages = 1 end
    if SSL.page > pages then SSL.page = pages end
    if SSL.page < 1 then SSL.page = 1 end
    SSL.pageText:SetText(SSL.page .. " / " .. pages)
    if SSL.page <= 1 then SSL.prevButton:Disable() else SSL.prevButton:Enable() end
    if SSL.page >= pages then SSL.nextButton:Disable() else SSL.nextButton:Enable() end

    local i
    for i = 1, SSL.PAGE_SIZE do
        local b = SSL.rowButtons[i]
        local idx = (SSL.page - 1) * SSL.PAGE_SIZE + i
        local r = SSL.results[idx]
        if r then
            b.resultId = r.id
            local zh = r.nameZhCN
            if not zh or zh == "" then zh = r.name end
            if not zh or zh == "" then zh = "未命名技能" end
            b.nameText:SetText("|cff7fbce8[" .. SafeText(r.id) .. "]|r " .. zh)
            local en = r.name or ""
            local match = ""
            if r.matchField then match = r.matchField .. "/" .. SafeText(r.matchType) end
            if en ~= "" and en ~= zh then
                b.subText:SetText(en .. (match ~= "" and "  ·  " .. match or ""))
            else
                b.subText:SetText(match)
            end
            b:Show()
            if r.id == SSL.selectedId then b:SetBackdropColor(0.10, 0.28, 0.40, 0.95) else b:SetBackdropColor(0.06, 0.075, 0.095, 0.80) end
        else
            b.resultId = nil
            b.nameText:SetText("")
            b.subText:SetText("")
            b:Hide()
        end
    end
end

function SpellSearchLibrary_DoSearch()
    local query = TrimText(SSL.searchBox:GetText())
    if query == "" then
        SSL.resultStat:SetText("请输入中文、英文技能名或 SpellID")
        return
    end

    local numeric = tonumber(query)
    if numeric and numeric >= 0 and math.floor(numeric) == numeric then
        SSL.results = { { id = numeric, name = "", nameZhCN = "", matchField = "SpellID", matchType = "exact" } }
        SSL.page = 1
        SSL.resultStat:SetText("SpellID 精确查询：" .. SafeText(numeric))
        SpellSearchLibrary_RefreshRows()
        SpellSearchLibrary_SelectSpell(numeric)
        return
    end

    local rows, total, truncated = CallUnitXP("spellsearch", query, SSL.SEARCH_LIMIT)
    if type(rows) ~= "table" then
        SSL.results = {}
        SSL.page = 1
        SSL.selectedId = nil
        SSL.resultStat:SetText("搜索失败：" .. SafeText(total))
        SpellSearchLibrary_RefreshRows()
        return
    end

    SSL.results = rows
    SSL.page = 1
    SSL.selectedId = nil
    local shown = table.getn(rows)
    local stat = "匹配 " .. SafeText(total or shown) .. " 条，显示 " .. shown .. " 条"
    if truncated then stat = stat .. "（已达上限）" end
    SSL.resultStat:SetText(stat)
    SpellSearchLibrary_RefreshRows()
    if shown > 0 and rows[1] and rows[1].id then
        SpellSearchLibrary_SelectSpell(rows[1].id)
    else
        SSL.detailTitle:SetText("技能详情")
        SSL.detailSub:SetText("没有匹配结果")
        SSL.descText:SetText("-")
        SSL.currentSpell = nil
        ClearFields()
    end
end

local function ToggleWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        SSL.searchBox:SetFocus()
    end
end

SLASH_SPELLSEARCHLIBRARY1 = "/spellsearch"
SLASH_SPELLSEARCHLIBRARY2 = "/ssl"
SlashCmdList["SPELLSEARCHLIBRARY"] = function(msg)
    local q = TrimText(msg or "")
    if q ~= "" then
        frame:Show()
        SSL.searchBox:SetText(q)
        SpellSearchLibrary_DoSearch()
    else
        ToggleWindow()
    end
end

DEFAULT_CHAT_FRAME:AddMessage("|cff78b7e6技能搜索库|r v" .. SSL.VERSION .. "：输入 |cffffffff/ssl|r 打开")
