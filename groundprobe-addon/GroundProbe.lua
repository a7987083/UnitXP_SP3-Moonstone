-- GroundProbe B1 - TRUE 8x8 diagnostic probe for Turtle WoW 1.12.
-- Read-only: proves whether ground effects expose DynamicObject/GameObject XYZ.

GroundProbeDB = GroundProbeDB or {}

local F = CreateFrame("Frame", "GroundProbeFrame")
F:RegisterEvent("VARIABLES_LOADED")
F:RegisterEvent("PLAYER_ENTERING_WORLD")
F:RegisterEvent("PLAYER_LEAVING_WORLD")
F:RegisterEvent("UNIT_CASTEVENT") -- SuperWoW 2.2

local running = false
local elapsed = 0
local range = 120
local includeGO = true
local known = {}
local casts = {}
local logs = {}
local lastSnapshot = nil

local function Chat(s)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[GroundProbe]|r " .. tostring(s))
  end
end

local function Split(line)
  local t, p = {}, 1
  while true do
    local q = string.find(line, "|", p, true)
    if not q then table.insert(t, string.sub(line, p)); break end
    table.insert(t, string.sub(line, p, q - 1)); p = q + 1
  end
  return t
end

local function Lines(text, fn)
  local p = 1
  text = tostring(text or "")
  while p <= string.len(text) do
    local q = string.find(text, "\n", p, true)
    if q then fn(string.sub(text, p, q - 1)); p = q + 1
    else fn(string.sub(text, p)); break end
  end
end

local function Log(s)
  table.insert(logs, string.format("%.3f %s", GetTime(), tostring(s)))
  while table.getn(logs) > 1500 do table.remove(logs, 1) end
end

local function NormGuid(v)
  local s = string.upper(tostring(v or ""))
  return string.gsub(s, "^0X", "")
end

local function RecentCast(spell, caster)
  local now, best = GetTime(), nil
  local i
  for i = table.getn(casts), 1, -1 do
    local c = casts[i]
    local age = now - c.t
    if age <= 5 then
      if tonumber(c.spell) == tonumber(spell) or NormGuid(c.caster) == NormGuid(caster) then
        best = c; break
      end
    end
  end
  return best
end

local panel = CreateFrame("Frame", "GroundProbePanel", UIParent)
panel:SetWidth(680); panel:SetHeight(190)
panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3}})
panel:SetBackdropColor(0, 0, 0, 0.82)
panel:Hide()

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
title:SetText("GroundProbe B1 · TRUE 8x8 地面对象探针")
local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
body:SetWidth(655); body:SetHeight(150); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")

local function Parse(text)
  local s = {p=nil, objs={}, d=0, g=0, visited=0, err=nil}
  Lines(text, function(line)
    local a = Split(line)
    if a[1] == "P" then
      s.p = {x=tonumber(a[2]) or 0, y=tonumber(a[3]) or 0, z=tonumber(a[4]) or 0}
    elseif a[1] == "D" then
      table.insert(s.objs, {kind="D", guid=a[2], caster=a[3], spell=tonumber(a[4]) or 0,
        radius=tonumber(a[5]) or 0, x=tonumber(a[6]) or 0, y=tonumber(a[7]) or 0,
        z=tonumber(a[8]) or 0, dist=tonumber(a[9]) or 0, zdiff=tonumber(a[10]) or 0})
    elseif a[1] == "G" then
      table.insert(s.objs, {kind="G", guid=a[2], entry=tonumber(a[3]) or 0,
        x=tonumber(a[4]) or 0, y=tonumber(a[5]) or 0, z=tonumber(a[6]) or 0,
        dist=tonumber(a[7]) or 0, zdiff=tonumber(a[8]) or 0})
    elseif a[1] == "S" then
      s.d=tonumber(a[2]) or 0; s.g=tonumber(a[3]) or 0; s.visited=tonumber(a[4]) or 0
    elseif a[1] == "E" then s.err=(a[2] or "ERROR") .. " " .. (a[3] or "") end
  end)
  return s
end

local function Describe(o)
  if o.kind == "D" then
    return string.format("D spell=%d r=%.2f dist=%.2f zD=%.2f xyz=%.2f,%.2f,%.2f", o.spell,o.radius,o.dist,o.zdiff,o.x,o.y,o.z)
  end
  return string.format("G entry=%d dist=%.2f zD=%.2f xyz=%.2f,%.2f,%.2f", o.entry,o.dist,o.zdiff,o.x,o.y,o.z)
end

local function Lifecycle(s)
  local now = {}
  local i
  for i=1,table.getn(s.objs) do
    local o=s.objs[i]; local k=o.kind..":"..tostring(o.guid); now[k]=o
    if not known[k] then
      local line="NEW "..Describe(o).." guid="..tostring(o.guid)
      if o.kind=="D" then
        local c=RecentCast(o.spell,o.caster)
        line=line.." caster="..tostring(o.caster)
        if c then line=line..string.format(" <= CAST spell=%d type=%s age=%.2fs",c.spell,c.kind,GetTime()-c.t) end
      end
      Log(line); Chat(line)
    end
  end
  for k,o in pairs(known) do
    if not now[k] then local line="GONE "..Describe(o).." guid="..tostring(o.guid); Log(line); Chat(line) end
  end
  known=now
end

local function Render(s)
  if s.err then body:SetText("ERROR: "..s.err); return end
  local p=s.p or {x=0,y=0,z=0}
  local out={string.format("玩家 XYZ %.2f, %.2f, %.2f   Dynamic=%d   GameObject=%d   scanned=%d   SuperWoW=%s",p.x,p.y,p.z,s.d,s.g,s.visited,tostring(SUPERWOW_VERSION or "?"))}
  local i
  for i=1,table.getn(s.objs) do if i<=7 then table.insert(out,Describe(s.objs[i])) end end
  if table.getn(s.objs)==0 then table.insert(out,"附近没有目标对象；等地面黑水/火圈出现时观察 Dynamic 是否增加。") end
  body:SetText(table.concat(out,"\n"))
end

local function Poll()
  if type(UnitXP)~="function" then body:SetText("没有 UnitXP()；DLL 不是本测试包。") return end
  local ok,text=pcall(UnitXP,"GroundProbe.Snapshot",range,includeGO)
  if not ok or type(text)~="string" then body:SetText("Snapshot 调用失败: "..tostring(text)); return end
  local s=Parse(text); lastSnapshot=s; Lifecycle(s); Render(s)
end

local function Start()
  running=true; GroundProbeDB.running=true; known={}; panel:Show(); Log("=== START ==="); Chat("开始扫描。去测试地面黑水/火圈。") ; Poll()
end
local function Stop() running=false; GroundProbeDB.running=false; Log("=== STOP ==="); Chat("扫描停止。") end

F:SetScript("OnEvent",function()
  if event=="VARIABLES_LOADED" then
    range=tonumber(GroundProbeDB.range) or 120
    if GroundProbeDB.includeGO~=nil then includeGO=GroundProbeDB.includeGO and true or false end
  elseif event=="PLAYER_ENTERING_WORLD" then if GroundProbeDB.running then Start() end
  elseif event=="PLAYER_LEAVING_WORLD" then known={}
  elseif event=="UNIT_CASTEVENT" then
    local kind=tostring(arg3 or ""); local spell=tonumber(arg4) or 0
    if kind=="START" or kind=="CAST" or kind=="CHANNEL" then
      table.insert(casts,{t=GetTime(),caster=arg1,target=arg2,kind=kind,spell=spell})
      while table.getn(casts)>50 do table.remove(casts,1) end
      Log(string.format("CAST spell=%d type=%s caster=%s target=%s",spell,kind,tostring(arg1),tostring(arg2)))
    end
  end
end)

F:SetScript("OnUpdate",function()
  if not running then return end
  elapsed=elapsed+(arg1 or 0)
  if elapsed>=0.20 then elapsed=0; Poll() end
end)

SLASH_GROUNDPROBE1="/gprobe"
SlashCmdList["GROUNDPROBE"]=function(msg)
  msg=string.lower(tostring(msg or "")); msg=string.gsub(msg,"^%s+",""); msg=string.gsub(msg,"%s+$","")
  if msg=="start" or msg=="on" then Start()
  elseif msg=="stop" or msg=="off" then Stop()
  elseif msg=="show" then panel:Show(); Poll()
  elseif msg=="hide" then panel:Hide()
  elseif msg=="clear" then logs={}; known={}; casts={}; Chat("日志已清空。")
  elseif msg=="dump" then
    local first=table.getn(logs)-19; if first<1 then first=1 end
    local i; for i=first,table.getn(logs) do Chat(logs[i]) end
  elseif msg=="export" then
    if type(ExportFile)=="function" then
      local ok,err=pcall(ExportFile,"GroundProbe.txt",table.concat(logs,"\r\n")); Chat(ok and "已导出 GroundProbe.txt" or ("导出失败: "..tostring(err)))
    else Chat("没有 ExportFile()；请确认 SuperWoW 2.2 + 最新 SuperAPI。") end
  elseif string.find(msg,"^range%s+") then
    local n=tonumber(string.gsub(msg,"^range%s+","")); if n and n>=10 and n<=300 then range=n; GroundProbeDB.range=n; Chat("扫描半径="..n) else Chat("用法 /gprobe range 120") end
  elseif msg=="go" then includeGO=not includeGO; GroundProbeDB.includeGO=includeGO; Chat("GameObject="..tostring(includeGO))
  elseif msg=="status" then
    panel:Show(); if type(UnitXP)=="function" then local a,b,c=UnitXP("GroundProbe.Status"); Chat("DLL="..tostring(a).." code="..tostring(b).." "..tostring(c)) end
    Chat("running="..tostring(running).." range="..range.." SuperWoW="..tostring(SUPERWOW_VERSION or "?")); Poll()
  else Chat("/gprobe start|stop|show|hide|status|dump|export|clear|range 120|go") end
end