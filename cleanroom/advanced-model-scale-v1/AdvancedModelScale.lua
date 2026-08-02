-- MoonMarker advanced editor main-model scale controls V1.
-- User-driven local transform only: no team publishing and no automatic scene mutation.

local SCALE_MIN = 0.10
local SCALE_MAX = 5.00
local scalePage = nil
local scaleValueText = nil
local scaleStateText = nil
local scaleInstalled = false

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd56a[光柱测试板·高级]|r " .. tostring(message))
    end
end

local function EnsureStorage()
    if type(MoonMarkerDB) ~= "table" then MoonMarkerDB = {} end
    if type(MoonMarkerDB.advancedScale) ~= "number" then
        MoonMarkerDB.advancedScale = 1.00
    end
    if type(MoonMarkerDB.advancedYaw) ~= "number" then
        MoonMarkerDB.advancedYaw = 0.00
    end
end

local function ClampScale(value)
    value = tonumber(value) or 1.00
    if value < SCALE_MIN then value = SCALE_MIN end
    if value > SCALE_MAX then value = SCALE_MAX end
    return math.floor(value * 100 + 0.5) / 100
end

local function ReadTransform()
    EnsureStorage()
    local scale = ClampScale(MoonMarkerDB.advancedScale)
    local yaw = tonumber(MoonMarkerDB.advancedYaw) or 0.00
    if type(MoonMarker_AdvancedGetTransform) == "function" then
        local ok, sharedScale, sharedYaw = pcall(MoonMarker_AdvancedGetTransform)
        if ok then
            scale = ClampScale(sharedScale or scale)
            yaw = tonumber(sharedYaw) or yaw
        end
    end
    MoonMarkerDB.advancedScale = scale
    MoonMarkerDB.advancedYaw = yaw
    return scale, yaw
end

local function RefreshScaleDisplay(detail)
    local scale, yaw = ReadTransform()
    if scaleValueText then
        scaleValueText:SetText(string.format("模型大小：%.2f 倍", scale))
    end
    if scaleStateText then
        local suffix = detail and ("；" .. tostring(detail)) or ""
        scaleStateText:SetText(string.format(
            "当前本地参数：大小 %.2f，旋转 %.1f°%s",
            scale, yaw, suffix))
    end
end

function MoonMarker_AdvancedScaleRefresh()
    RefreshScaleDisplay()
end

local function ApplyScale(value)
    EnsureStorage()
    local scale = ClampScale(value)
    local _, yaw = ReadTransform()
    MoonMarkerDB.advancedScale = scale
    MoonMarkerDB.advancedYaw = yaw

    if type(MoonMarker_AdvancedSetTransform) ~= "function" then
        RefreshScaleDisplay("变换桥接尚未加载")
        Print("模型大小调整失败：变换桥接尚未加载。")
        return
    end

    local ok, applied, returnedScale, returnedYaw, reason = pcall(
        MoonMarker_AdvancedSetTransform, scale, yaw)
    if not ok then
        RefreshScaleDisplay("Lua 调用失败")
        Print("模型大小调整失败：Lua 调用失败。")
        return
    end

    MoonMarkerDB.advancedScale = ClampScale(returnedScale or scale)
    MoonMarkerDB.advancedYaw = tonumber(returnedYaw) or yaw
    reason = reason or "TRANSFORM_REJECTED"
    RefreshScaleDisplay(reason == "APPLIED" and "已应用到当前预览" or "已保存给下一次预览")

    if applied and reason == "APPLIED" then
        Print(string.format("当前高级预览大小已调整为 %.2f 倍。",
            MoonMarkerDB.advancedScale))
    elseif applied and reason == "SAVED_FOR_NEXT_PREVIEW" then
        Print(string.format("模型大小已保存为 %.2f 倍；下一次高级预览时生效。",
            MoonMarkerDB.advancedScale))
    else
        Print("模型大小调整失败：" .. tostring(reason))
    end
end

local function MakeButton(name, parent, width, height, label, r, g, b)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(height)
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(button)
    texture:SetTexture(r, g, b, 0.96)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetText(label)
    button.text = text
    return button
end

local function InstallScaleControls()
    if scaleInstalled then return true end
    scalePage = getglobal and getglobal("MoonMarkerAdvancedEditorPage1") or nil
    if not scalePage then return false end

    scaleValueText = scalePage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleValueText:SetPoint("TOPLEFT", scalePage, "TOPLEFT", 4, -222)
    scaleValueText:SetWidth(210)
    scaleValueText:SetJustifyH("LEFT")

    local minus = MakeButton("MoonMarkerAdvancedScaleMinus", scalePage, 62, 28,
        "－ 缩小", 0.20, 0.32, 0.48)
    minus:SetPoint("TOPLEFT", scalePage, "TOPLEFT", 4, -246)
    minus:SetScript("OnClick", function()
        local scale = ReadTransform()
        local step = IsShiftKeyDown() == 1 and 0.01 or 0.10
        ApplyScale(scale - step)
    end)

    local reset = MakeButton("MoonMarkerAdvancedScaleReset", scalePage, 92, 28,
        "恢复 1.00", 0.42, 0.31, 0.12)
    reset:SetPoint("LEFT", minus, "RIGHT", 7, 0)
    reset:SetScript("OnClick", function() ApplyScale(1.00) end)

    local plus = MakeButton("MoonMarkerAdvancedScalePlus", scalePage, 62, 28,
        "＋ 放大", 0.16, 0.44, 0.30)
    plus:SetPoint("LEFT", reset, "RIGHT", 7, 0)
    plus:SetScript("OnClick", function()
        local scale = ReadTransform()
        local step = IsShiftKeyDown() == 1 and 0.01 or 0.10
        ApplyScale(scale + step)
    end)

    local range = scalePage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    range:SetPoint("LEFT", plus, "RIGHT", 14, 0)
    range:SetText("范围 0.10～5.00；Shift 每次 0.01")

    scaleStateText = scalePage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleStateText:SetPoint("TOPLEFT", scalePage, "TOPLEFT", 4, -286)
    scaleStateText:SetWidth(610)
    scaleStateText:SetJustifyH("LEFT")

    local oldShow = scalePage:GetScript("OnShow")
    scalePage:SetScript("OnShow", function()
        if oldShow then oldShow() end
        RefreshScaleDisplay()
    end)

    scaleInstalled = true
    RefreshScaleDisplay("未放置预览时只保存数值，不创建模型")
    return true
end

local loader = CreateFrame("Frame", "MoonMarkerAdvancedScaleLoader")
loader:RegisterEvent("VARIABLES_LOADED")
loader.elapsed = 0
loader.attempts = 0
loader:SetScript("OnEvent", function()
    EnsureStorage()
    if InstallScaleControls() then
        this:SetScript("OnUpdate", nil)
        return
    end
    this:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + (arg1 or 0)
        if this.elapsed < 0.20 then return end
        this.elapsed = 0
        this.attempts = this.attempts + 1
        if InstallScaleControls() or this.attempts >= 25 then
            this:SetScript("OnUpdate", nil)
        end
    end)
end)
