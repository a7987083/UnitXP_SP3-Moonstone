-- MoonMarker advanced marker editor framework V1.
-- UI/state only: no team publishing, no relog restore, and no automatic scene mutation.

local FRAME_WIDTH = 650
local FRAME_HEIGHT = 500
local TAB_WIDTH = 100
local TAB_GAP = 5

local frameworkFrame = nil
local frameworkPages = {}
local frameworkTabs = {}
local frameworkCurrentTab = "model"
local frameworkAuthText = nil
local frameworkRoleText = nil
local frameworkCurrentText = nil
local frameworkLocalPreviewButton = nil
local frameworkLocalPreviewMark = nil
local frameworkSettingsAuth = nil
local frameworkSettingsRole = nil
local frameworkSettingsMode = nil
local frameworkLegacyClick = nil

local TAB_ORDER = {
    { key = "model", label = "模型编辑" },
    { key = "top", label = "顶部模型" },
    { key = "library", label = "模型库" },
    { key = "markers", label = "当前标记" },
    { key = "presets", label = "预设" },
    { key = "settings", label = "设置诊断" },
}

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd56a[光柱测试板·高级]|r " .. tostring(message))
    end
end

local function EnsureStorage()
    if type(MoonMarkerDB) ~= "table" then MoonMarkerDB = {} end
    if MoonMarkerDB.advancedLocalPreview == nil then
        MoonMarkerDB.advancedLocalPreview = true
    end
end

local function ShortPath(value, maximum)
    value = tostring(value or "")
    maximum = maximum or 60
    if string.len(value) <= maximum then return value end
    return "..." .. string.sub(value, -(maximum - 3))
end

local function MakeButton(name, parent, width, height, label, r, g, b)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(height)
    button.texture = button:CreateTexture(nil, "BACKGROUND")
    button.texture:SetAllPoints(button)
    button.texture:SetTexture(r, g, b, 0.96)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetText(label)
    return button
end

local function GroupRole()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        if IsPartyLeader and IsPartyLeader("player") == 1 then
            return "团队团长", true
        end
        if IsRaidOfficer and IsRaidOfficer() == 1 then
            return "团队助理", true
        end
        return "团队成员", false
    end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        if IsPartyLeader and IsPartyLeader("player") == 1 then
            return "小队队长", true
        end
        return "小队成员", false
    end
    return "未组队", false
end

local function ReadAuthorization()
    local allowed, guildName, reason = false, nil, "AUTH_UNAVAILABLE"
    if type(MoonMarker_IsTargetGuildMember) == "function" then
        local ok, result, detail = pcall(MoonMarker_IsTargetGuildMember)
        if ok then
            allowed = result and true or false
            reason = detail or reason
        else
            reason = "AUTH_CALL_FAILED"
        end
    end
    if type(MoonMarker_GetDetectedGuildName) == "function" then
        local ok, value = pcall(MoonMarker_GetDetectedGuildName)
        if ok then guildName = value end
    end
    if type(MoonMarker_GetAuthReason) == "function" then
        local ok, value = pcall(MoonMarker_GetAuthReason)
        if ok and value then reason = value end
    end
    return allowed, guildName, reason
end

local function RefreshLocalPreviewVisual()
    if not frameworkLocalPreviewButton then return end
    EnsureStorage()
    if MoonMarkerDB.advancedLocalPreview then
        frameworkLocalPreviewButton.texture:SetTexture(0.10, 0.55, 0.30, 0.96)
        frameworkLocalPreviewMark:SetText("√")
    else
        frameworkLocalPreviewButton.texture:SetTexture(0.22, 0.24, 0.29, 0.96)
        frameworkLocalPreviewMark:SetText("")
    end
end

local function RefreshFrameworkStatus(refreshAuthorization)
    EnsureStorage()
    local allowed, guildName, reason
    if refreshAuthorization then
        allowed, guildName, reason = ReadAuthorization()
        MoonMarkerDB.advancedFrameworkAuth = allowed and true or false
        MoonMarkerDB.advancedFrameworkGuild = guildName
        MoonMarkerDB.advancedFrameworkReason = reason
    else
        allowed = MoonMarkerDB.advancedFrameworkAuth and true or false
        guildName = MoonMarkerDB.advancedFrameworkGuild
        reason = MoonMarkerDB.advancedFrameworkReason or "AUTH_UNAVAILABLE"
    end

    local role, canPublish = GroupRole()
    local guildSuffix = guildName and guildName ~= "" and ("（" .. tostring(guildName) .. "）") or ""
    local authLine
    if allowed then
        authLine = "|cff66ff88DLL 授权：已通过" .. guildSuffix .. "|r"
    else
        authLine = "|cffff7777DLL 授权：未通过（" .. tostring(reason) .. "）|r"
    end
    local roleLine = "当前身份：" .. role .. "；团队发布条件："
        .. (canPublish and "满足" or "不满足") .. "（功能尚未开放）"
    local path = MoonMarkerDB.advancedPath or "Spells\\MoonBeam_Impact_Base.mdx"
    local currentLine = "当前标记：本地编辑草稿；M2：" .. ShortPath(path, 65)
    local modeLine
    if MoonMarkerDB.advancedLocalPreview then
        modeLine = "本地预览：已勾选。所有高级操作只在本机显示。"
    else
        modeLine = "本地预览：未勾选。团队发布尚未开放，本阶段仍只在本机生效。"
    end

    if frameworkAuthText then frameworkAuthText:SetText(authLine) end
    if frameworkRoleText then frameworkRoleText:SetText(roleLine) end
    if frameworkCurrentText then frameworkCurrentText:SetText(currentLine) end
    if frameworkSettingsAuth then frameworkSettingsAuth:SetText(authLine) end
    if frameworkSettingsRole then frameworkSettingsRole:SetText(roleLine) end
    if frameworkSettingsMode then frameworkSettingsMode:SetText(modeLine) end
    RefreshLocalPreviewVisual()
    return allowed
end

local function SetPage(pageName)
    if not frameworkPages[pageName] then pageName = "model" end
    frameworkCurrentTab = pageName
    MoonMarkerDB.advancedEditorTab = pageName
    for _, info in ipairs(TAB_ORDER) do
        local active = info.key == pageName
        local page = frameworkPages[info.key]
        local tab = frameworkTabs[info.key]
        if page then
            if active then page:Show() else page:Hide() end
        end
        if tab then
            if active then tab.texture:SetTexture(0.55, 0.38, 0.08, 0.96)
            else tab.texture:SetTexture(0.12, 0.18, 0.28, 0.96) end
        end
    end
    RefreshFrameworkStatus(false)
end

local function AddPageText(page, titleText, bodyText)
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -8)
    title:SetText(titleText)
    local body = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    body:SetWidth(610)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(bodyText)
end

local function OpenLegacyEditor()
    if frameworkFrame then frameworkFrame:Hide() end
    if frameworkLegacyClick then
        frameworkLegacyClick()
        return
    end
    Print("现有 M2 编辑工具尚未加载。")
end

local function BuildModelPage(page)
    AddPageText(page, "模型编辑",
        "本阶段先建立新的高级编辑器框架。当前已验证的地面选点、人物脚下预览、"
        .. "M2 扫描、收藏和旋转功能继续保留在现有 V2 工具中，暂不改动其场景调用。")

    local open = MakeButton("MoonMarkerFrameworkOpenLegacy", page, 150, 28,
        "打开现有 M2 工具", 0.10, 0.46, 0.58)
    open:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -92)
    open:SetScript("OnClick", OpenLegacyEditor)

    local pathLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pathLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -145)
    pathLabel:SetWidth(610)
    pathLabel:SetJustifyH("LEFT")
    pathLabel:SetText("当前保存的主模型路径："
        .. ShortPath(MoonMarkerDB.advancedPath or "Spells\\MoonBeam_Impact_Base.mdx", 72))

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -185)
    note:SetWidth(610)
    note:SetJustifyH("LEFT")
    note:SetText("下一阶段会把现有模型编辑控件逐项迁入本页；迁移前不会删除旧工具，"
        .. "也不会修改普通光柱 PLACE / CLEAR 同步。")
end

local function BuildLibraryPage(page)
    AddPageText(page, "模型库",
        "模型库页框架已经建立。当前扫描器仍在现有 V2 工具中运行，"
        .. "这样可以避免本阶段同时改动扫描器与窗口生命周期。")
    local open = MakeButton("MoonMarkerFrameworkOpenScannerTool", page, 150, 28,
        "打开现有 M2 工具", 0.25, 0.35, 0.60)
    open:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -92)
    open:SetScript("OnClick", OpenLegacyEditor)
end

local function BuildSettingsPage(page)
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -8)
    title:SetText("设置与诊断")

    frameworkSettingsAuth = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkSettingsAuth:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -42)
    frameworkSettingsAuth:SetWidth(610)
    frameworkSettingsAuth:SetJustifyH("LEFT")

    frameworkSettingsRole = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkSettingsRole:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -70)
    frameworkSettingsRole:SetWidth(610)
    frameworkSettingsRole:SetJustifyH("LEFT")

    frameworkSettingsMode = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkSettingsMode:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -98)
    frameworkSettingsMode:SetWidth(610)
    frameworkSettingsMode:SetJustifyH("LEFT")

    local safety = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    safety:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -140)
    safety:SetWidth(610)
    safety:SetJustifyH("LEFT")
    safety:SetText("底层保护保持启用：DLL 工会授权、路径验证、缩放范围、坐标有限值、"
        .. "标记容量和小退生命周期保护。自动重登恢复仍然禁用。")

    local refresh = MakeButton("MoonMarkerFrameworkRefresh", page, 100, 28,
        "刷新权限状态", 0.18, 0.36, 0.58)
    refresh:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -198)
    refresh:SetScript("OnClick", function()
        RefreshFrameworkStatus(true)
        Print("高级编辑器权限与身份状态已刷新。")
    end)

    local commands = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    commands:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -246)
    commands:SetWidth(610)
    commands:SetJustifyH("LEFT")
    commands:SetText("诊断命令：/mmcore、/mmcorepolicy、/mmcoretest、/mmfubar、/mmadvanced。")
end

local function BuildFramework()
    if frameworkFrame then return end
    EnsureStorage()

    local legacyButton = getglobal and getglobal("MoonMarkerAdvancedButton") or nil
    if legacyButton and not frameworkLegacyClick then
        frameworkLegacyClick = legacyButton:GetScript("OnClick")
    end

    frameworkFrame = CreateFrame("Frame", "MoonMarkerAdvancedEditorFrame", UIParent)
    frameworkFrame:SetWidth(FRAME_WIDTH)
    frameworkFrame:SetHeight(FRAME_HEIGHT)
    if MoonMarkerDB.advancedEditorPoint then
        frameworkFrame:SetPoint(MoonMarkerDB.advancedEditorPoint, UIParent,
            MoonMarkerDB.advancedEditorRelativePoint or MoonMarkerDB.advancedEditorPoint,
            MoonMarkerDB.advancedEditorX or 0, MoonMarkerDB.advancedEditorY or 0)
    else
        frameworkFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
    frameworkFrame:SetMovable(true)
    frameworkFrame:EnableMouse(true)
    frameworkFrame:RegisterForDrag("LeftButton")
    frameworkFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    frameworkFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relativePoint, x, y = this:GetPoint(1)
        MoonMarkerDB.advancedEditorPoint = point
        MoonMarkerDB.advancedEditorRelativePoint = relativePoint
        MoonMarkerDB.advancedEditorX = x
        MoonMarkerDB.advancedEditorY = y
    end)
    frameworkFrame:SetScript("OnShow", function() RefreshFrameworkStatus(true) end)

    local bg = frameworkFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frameworkFrame)
    bg:SetTexture(0.025, 0.035, 0.065, 0.97)
    local border = frameworkFrame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 1, -1)
    border:SetPoint("BOTTOMRIGHT", frameworkFrame, "BOTTOMRIGHT", -1, 1)
    border:SetTexture(0.55, 0.38, 0.08, 0.72)

    local title = frameworkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 12, -11)
    title:SetText("光柱测试板 · 高级标记编辑器")

    local close = MakeButton("MoonMarkerAdvancedEditorClose", frameworkFrame, 24, 22,
        "×", 0.48, 0.12, 0.14)
    close:SetPoint("TOPRIGHT", frameworkFrame, "TOPRIGHT", -7, -7)
    close:SetScript("OnClick", function() frameworkFrame:Hide() end)

    frameworkLocalPreviewButton = MakeButton("MoonMarkerAdvancedLocalPreview", frameworkFrame,
        18, 18, "", 0.10, 0.55, 0.30)
    frameworkLocalPreviewButton:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 12, -37)
    frameworkLocalPreviewMark = frameworkLocalPreviewButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkLocalPreviewMark:SetPoint("CENTER", frameworkLocalPreviewButton, "CENTER", 0, 0)
    local previewLabel = frameworkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("LEFT", frameworkLocalPreviewButton, "RIGHT", 5, 0)
    previewLabel:SetText("本地预览")
    frameworkLocalPreviewButton:SetScript("OnClick", function()
        MoonMarkerDB.advancedLocalPreview = not MoonMarkerDB.advancedLocalPreview
        RefreshFrameworkStatus(false)
        if MoonMarkerDB.advancedLocalPreview then
            Print("本地预览已勾选。")
        else
            Print("本地预览已取消勾选；团队发布尚未开放，当前仍只在本机生效。")
        end
    end)

    frameworkAuthText = frameworkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkAuthText:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 126, -38)
    frameworkAuthText:SetWidth(505)
    frameworkAuthText:SetJustifyH("LEFT")

    frameworkRoleText = frameworkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkRoleText:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 12, -59)
    frameworkRoleText:SetWidth(626)
    frameworkRoleText:SetJustifyH("LEFT")

    frameworkCurrentText = frameworkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frameworkCurrentText:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 12, -77)
    frameworkCurrentText:SetWidth(626)
    frameworkCurrentText:SetJustifyH("LEFT")

    for index, info in ipairs(TAB_ORDER) do
        local tab = MakeButton("MoonMarkerAdvancedEditorTab" .. index, frameworkFrame,
            TAB_WIDTH, 24, info.label, 0.12, 0.18, 0.28)
        tab:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT",
            12 + (index - 1) * (TAB_WIDTH + TAB_GAP), -101)
        tab.pageName = info.key
        tab:SetScript("OnClick", function() SetPage(this.pageName) end)
        frameworkTabs[info.key] = tab

        local page = CreateFrame("Frame", "MoonMarkerAdvancedEditorPage" .. index, frameworkFrame)
        page:SetWidth(626)
        page:SetHeight(328)
        page:SetPoint("TOPLEFT", frameworkFrame, "TOPLEFT", 12, -132)
        frameworkPages[info.key] = page
    end

    BuildModelPage(frameworkPages.model)
    AddPageText(frameworkPages.top, "顶部模型",
        "顶部 M2、顶部高度、顶部大小和独立旋转将在后续阶段接入。"
        .. " 本阶段只建立页面框架，不创建、替换或释放任何模型。")
    BuildLibraryPage(frameworkPages.library)
    AddPageText(frameworkPages.markers, "当前标记",
        "后续将在这里显示本地草稿和团队高级标记列表。高级团队同步尚未开放，"
        .. " 本阶段不会读取或修改队友场景。")
    AddPageText(frameworkPages.presets, "预设",
        "后续用于保存主模型、顶部模型、旋转、缩放和高度组合。"
        .. " 本阶段不会写入新的模型预设数据。")
    BuildSettingsPage(frameworkPages.settings)

    local footer = frameworkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("BOTTOMLEFT", frameworkFrame, "BOTTOMLEFT", 12, 9)
    footer:SetWidth(626)
    footer:SetJustifyH("LEFT")
    footer:SetText("框架阶段：高级团队同步和自动重登恢复均未启用。关闭窗口不会清除模型。")

    frameworkFrame:Hide()
    SetPage(MoonMarkerDB.advancedEditorTab or "model")

    if legacyButton then
        legacyButton:SetScript("OnClick", function()
            if type(MoonMarker_ToggleAdvancedEditor) == "function" then
                MoonMarker_ToggleAdvancedEditor()
            end
        end)
        legacyButton:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText("高级标记编辑器")
            GameTooltip:AddLine("打开六页高级编辑器框架。", 0.85, 0.85, 0.85)
            GameTooltip:Show()
        end)
        legacyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

function MoonMarker_OpenAdvancedEditor()
    EnsureStorage()
    BuildFramework()
    local allowed = RefreshFrameworkStatus(true)
    if not allowed then
        Print("未通过 DLL 工会授权，无法打开高级标记编辑器。")
        frameworkFrame:Hide()
        return false
    end
    SetPage(MoonMarkerDB.advancedEditorTab or frameworkCurrentTab or "model")
    frameworkFrame:Show()
    return true
end

function MoonMarker_ToggleAdvancedEditor()
    BuildFramework()
    if frameworkFrame:IsShown() then
        frameworkFrame:Hide()
        return true
    end
    return MoonMarker_OpenAdvancedEditor()
end

SLASH_MOONMARKERADVANCED1 = "/mmadvanced"
SlashCmdList["MOONMARKERADVANCED"] = MoonMarker_ToggleAdvancedEditor

local loader = CreateFrame("Frame", "MoonMarkerAdvancedEditorLoader")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function()
    EnsureStorage()
    BuildFramework()
    RefreshFrameworkStatus(false)
end)
