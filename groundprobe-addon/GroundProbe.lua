-- GroundProbe B2 Hybrid - TRUE 8x8 diagnostic probe for Turtle WoW 1.12.
-- Read-only hybrid detector: DynamicObject ground zones + caster-centered hazards.

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
local zTolerance = 4.0
local known = {}
local casts = {}
local casterHazards = {}
local logs = {}
local lastSnapshot = nil
local casterSkills = {}

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
  while table.getn(logs) > 2000 do table.remove(logs, 1) end
end

local function NormGuid(v)
  local s = string.upper(tostring(v or ""))
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return string.gsub(s, "^0X", "")
end

local function SkillName(spell, cfg)
  if cfg and cfg.name and cfg.name ~= "" then return cfg.name end
  if type(SpellInfo) == "function" then
    local ok, name = pcall(SpellInfo, spell)
    if ok and name then return tostring(name) end
  end
  return "Spell " .. tostring(spell)
end

local function EnsureDefaults()
  GroundProbeDB.casterSkills = GroundProbeDB.casterSkills or {}
  if not GroundProbeDB.casterSkills[24018] then
    -- 10 yd is deliberately a provisional TEST radius for B2 calibration.
    -- It is NOT treated as verified spell data and can be changed with /gprobe caster.
    GroundProbeDB.casterSkills[24018] = {radius=10.0, duration=10.0, name="利斧乱舞", provisional=true}
  end
  casterSkills = GroundProbeDB.casterSkills
  zTolerance = tonumber(GroundProbeDB.zTolerance) or 4.0
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
panel:SetWidth(800); panel:SetHeight(260)
panel:SetPoint("TOP", UIParent, "TOP", 0, -100)
panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3}})
panel:SetBackdropColor(0, 0, 0, 0.82)
panel:Hide()

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
title:SetText("GroundProbe B2 Hybrid · Dynamic + Caster 双模式")
local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
body:SetWidth(775); body:SetHeight(215); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")

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

local function ParseUnitRecord(text)
  if type(text) ~= "string" then return nil, "NO_RECORD" end
  local a = Split(text)
  if a[1] == "E" then return nil, (a[2] or "ERROR") .. " " .. (a[3] or "") end
  if a[1] ~= "U" then return nil, "BAD_RECORD " .. tostring(text) end
  return {guid=a[2], entry=tonumber(a[3]) or 0, type=tonumber(a[4]) or 0,
    x=tonumber(a[5]) or 0, y=tonumber(a[6]) or 0, z=tonumber(a[7]) or 0,
    dist=tonumber(a[8]) or 0, zdiff=tonumber(a[9]) or 0, object=a[10]}, nil
end

local function DynamicInside(o)
  return o.radius > 0 and o.dist <= o.radius and o.zdiff <= zTolerance
end

local function DescribeObject(o)
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
      local line="NEW "..DescribeObject(o).." guid="..tostring(o.guid)
      if o.kind=="D" then
        local c=RecentCast(o.spell,o.caster)
        line=line.." caster="..tostring(o.caster)
        if c then line=line..string.format(" <= CAST spell=%d type=%s age=%.2fs",c.spell,c.kind,GetTime()-c.t) end
      end
      Log(line); Chat(line)
    end
  end
  for k,o in pairs(known) do
    if not now[k] then local line="GONE "..DescribeObject(o).." guid="..tostring(o.guid); Log(line); Chat(line) end
  end
  known=now
end

local function CasterKey(caster, spell)
  return NormGuid(caster) .. ":" .. tostring(spell)
end

local function ActivateCaster(spell, caster, kind)
  local cfg = casterSkills[spell]
  if not cfg then return end
  local now = GetTime()
  local key = CasterKey(caster, spell)
  local h = casterHazards[key]
  if not h then
    h = {spell=spell, caster=tostring(caster or ""), start=now, inside=nil, resolvedGuid=nil, lastError=nil}
    casterHazards[key] = h
    Log(string.format("CNEW spell=%d caster=%s event=%s", spell, tostring(caster), tostring(kind)))
  end
  local duration = tonumber(cfg.duration) or 3.0
  if kind == "START" or kind == "CHANNEL" or not h.expires then h.expires = now + duration end
  if kind == "CAST" and h.expires and h.expires < now + 0.25 then h.expires = now + duration end
end

local function RemoveCaster(spell, caster, reason)
  local key = CasterKey(caster, spell)
  if casterHazards[key] then
    Log(string.format("CGONE spell=%d caster=%s reason=%s", spell, tostring(caster), tostring(reason)))
    casterHazards[key] = nil
  end
end

local function ResolveCaster(h)
  if type(UnitXP) ~= "function" then return nil, "NO_UNITXP" end
  local ok, text = pcall(UnitXP, "GroundProbe.UnitByGuid", h.caster)
  if not ok then return nil, tostring(text) end
  local u, err = ParseUnitRecord(text)
  if u then
    if not h.resolvedGuid then
      Log(string.format("CRESOLVE spell=%d caster=%s => guid=%s entry=%d", h.spell, tostring(h.caster), tostring(u.guid), u.entry))
    end
    h.resolvedGuid = u.guid
    h.lastError = nil
    return u, nil
  end
  h.lastError = err
  return nil, err
end

local function MatchingDynamic(s, h)
  local wanted = NormGuid(h.resolvedGuid or h.caster)
  local i
  for i=1,table.getn(s.objs) do
    local o=s.objs[i]
    if o.kind=="D" and tonumber(o.spell)==tonumber(h.spell) then
      if wanted=="" or NormGuid(o.caster)==wanted then return o end
    end
  end
  return nil
end

local function UpdateCasterHazards(s)
  local now = GetTime()
  local key, h
  for key,h in pairs(casterHazards) do
    if h.expires and now > h.expires then
      Log(string.format("CGONE spell=%d caster=%s reason=timeout", h.spell, tostring(h.caster)))
      casterHazards[key] = nil
    else
      local cfg = casterSkills[h.spell]
      if not cfg then
        casterHazards[key] = nil
      else
        local u = ResolveCaster(h)
        local d = MatchingDynamic(s, h)
        if d then
          h.suppressed = true
          h.unit = u
        else
          h.suppressed = false
          h.unit = u
          if u then
            local inside = u.dist <= (tonumber(cfg.radius) or 0) and u.zdiff <= zTolerance
            if h.inside ~= inside then
              Log(string.format("C%s spell=%d dist=%.2f radius=%.2f zD=%.2f", inside and "ENTER" or "LEAVE", h.spell, u.dist, tonumber(cfg.radius) or 0, u.zdiff))
              h.inside = inside
            end
          end
        end
      end
    end
  end
end

local function Render(s)
  if s.err then body:SetText("ERROR: "..s.err); return end
  local p=s.p or {x=0,y=0,z=0}
  local activeC, suppressedC = 0, 0
  local key,h
  for key,h in pairs(casterHazards) do
    if h.suppressed then suppressedC=suppressedC+1 else activeC=activeC+1 end
  end
  local out={string.format("玩家 XYZ %.2f, %.2f, %.2f   Dynamic=%d   Caster=%d   GO=%d   scanned=%d   zTol=%.1f   SuperWoW=%s",p.x,p.y,p.z,s.d,activeC,s.g,s.visited,zTolerance,tostring(SUPERWOW_VERSION or "?"))}

  local i, shown = 1, 0
  for i=1,table.getn(s.objs) do
    local o=s.objs[i]
    if o.kind=="D" and shown<5 then
      local state=DynamicInside(o) and "|cffff3333INSIDE|r" or "|cff66ff66OUT|r"
      table.insert(out,string.format("[D] spell=%d r=%.2f dist=%.2f zD=%.2f %s xyz=%.2f,%.2f,%.2f",o.spell,o.radius,o.dist,o.zdiff,state,o.x,o.y,o.z))
      shown=shown+1
    end
  end

  for key,h in pairs(casterHazards) do
    if shown<8 then
      local cfg=casterSkills[h.spell]
      if h.suppressed then
        table.insert(out,string.format("[C→D] %s spell=%d 已由同施法者 DynamicObject 接管",SkillName(h.spell,cfg),h.spell))
      elseif h.unit then
        local r=tonumber(cfg.radius) or 0
        local inside=h.unit.dist<=r and h.unit.zdiff<=zTolerance
        local state=inside and "|cffff3333INSIDE|r" or "|cff66ff66OUT|r"
        local mark=cfg.provisional and "*TEST" or ""
        table.insert(out,string.format("[C] %s spell=%d r=%.2f%s dist=%.2f zD=%.2f %s entry=%d xyz=%.2f,%.2f,%.2f",SkillName(h.spell,cfg),h.spell,r,mark,h.unit.dist,h.unit.zdiff,state,h.unit.entry,h.unit.x,h.unit.y,h.unit.z))
      else
        table.insert(out,string.format("[C] %s spell=%d caster=%s 位置未解析: %s",SkillName(h.spell,cfg),h.spell,tostring(h.caster),tostring(h.lastError or "waiting")))
      end
      shown=shown+1
    end
  end

  local goShown=0
  for i=1,table.getn(s.objs) do
    local o=s.objs[i]
    if o.kind=="G" and goShown<2 and shown<10 then
      table.insert(out,string.format("[G] entry=%d dist=%.2f zD=%.2f xyz=%.2f,%.2f,%.2f",o.entry,o.dist,o.zdiff,o.x,o.y,o.z))
      goShown=goShown+1; shown=shown+1
    end
  end

  if s.d==0 and activeC==0 then table.insert(out,"当前没有 D/C 危险区。D=地面对象；C=施法者中心跟随。") end
  if suppressedC>0 then table.insert(out,"去重：DynamicObject 优先，已压制 Caster="..suppressedC) end
  body:SetText(table.concat(out,"\n"))
end

local function Poll()
  if type(UnitXP)~="function" then body:SetText("没有 UnitXP()；DLL 不是本测试包。") return end
  local ok,text=pcall(UnitXP,"GroundProbe.Snapshot",range,includeGO)
  if not ok or type(text)~="string" then body:SetText("Snapshot 调用失败: "..tostring(text)); return end
  local s=Parse(text); lastSnapshot=s; Lifecycle(s); UpdateCasterHazards(s); Render(s)
end

local function Start()
  running=true; GroundProbeDB.running=true; known={}; casterHazards={}; panel:Show(); Log("=== START B2 HYBRID ==="); Chat("B2 双模式扫描开始：Dynamic + Caster。") ; Poll()
end
local function Stop() running=false; GroundProbeDB.running=false; Log("=== STOP ==="); Chat("扫描停止。") end

F:SetScript("OnEvent",function()
  if event=="VARIABLES_LOADED" then
    EnsureDefaults()
    range=tonumber(GroundProbeDB.range) or 120
    if GroundProbeDB.includeGO~=nil then includeGO=GroundProbeDB.includeGO and true or false end
  elseif event=="PLAYER_ENTERING_WORLD" then if GroundProbeDB.running then Start() end
  elseif event=="PLAYER_LEAVING_WORLD" then known={}; casterHazards={}
  elseif event=="UNIT_CASTEVENT" then
    local kind=tostring(arg3 or ""); local spell=tonumber(arg4) or 0
    table.insert(casts,{t=GetTime(),caster=arg1,target=arg2,kind=kind,spell=spell,duration=arg5})
    while table.getn(casts)>100 do table.remove(casts,1) end
    if kind=="START" or kind=="CAST" or kind=="CHANNEL" then
      Log(string.format("CAST spell=%d type=%s caster=%s target=%s castdur=%s",spell,kind,tostring(arg1),tostring(arg2),tostring(arg5)))
      ActivateCaster(spell,arg1,kind)
    elseif kind=="FAIL" then
      Log(string.format("CASTFAIL spell=%d caster=%s",spell,tostring(arg1)))
      RemoveCaster(spell,arg1,"FAIL")
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
  elseif msg=="clear" then logs={}; known={}; casts={}; casterHazards={}; Chat("日志已清空。")
  elseif msg=="dump" then
    local first=table.getn(logs)-29; if first<1 then first=1 end
    local i; for i=first,table.getn(logs) do Chat(logs[i]) end
  elseif msg=="export" then
    if type(ExportFile)=="function" then
      local ok,err=pcall(ExportFile,"GroundProbe-B2.txt",table.concat(logs,"\r\n")); Chat(ok and "已导出 GroundProbe-B2.txt" or ("导出失败: "..tostring(err)))
    else Chat("没有 ExportFile()；请确认 SuperWoW + SuperAPI。") end
  elseif string.find(msg,"^range%s+") then
    local n=tonumber(string.gsub(msg,"^range%s+","")); if n and n>=10 and n<=300 then range=n; GroundProbeDB.range=n; Chat("扫描半径="..n) else Chat("用法 /gprobe range 120") end
  elseif string.find(msg,"^z%s+") then
    local n=tonumber(string.gsub(msg,"^z%s+","")); if n and n>=0 and n<=50 then zTolerance=n; GroundProbeDB.zTolerance=n; Chat("Z高度容差="..n) else Chat("用法 /gprobe z 4") end
  elseif string.find(msg,"^caster%s+") then
    local _,_,sid,rad,dur=string.find(msg,"^caster%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)$")
    sid=tonumber(sid); rad=tonumber(rad); dur=tonumber(dur)
    if sid and rad and dur and rad>0 and rad<=100 and dur>0 and dur<=120 then
      GroundProbeDB.casterSkills=GroundProbeDB.casterSkills or {}; GroundProbeDB.casterSkills[sid]={radius=rad,duration=dur,name="",provisional=false}; casterSkills=GroundProbeDB.casterSkills
      Chat(string.format("Caster技能 %d：半径 %.2f，持续 %.2f 秒",sid,rad,dur))
    else Chat("用法 /gprobe caster 技能ID 半径 持续秒，例如 /gprobe caster 24018 10 10") end
  elseif string.find(msg,"^casteroff%s+") then
    local sid=tonumber(string.gsub(msg,"^casteroff%s+","")); if sid and casterSkills[sid] then casterSkills[sid]=nil; GroundProbeDB.casterSkills=casterSkills; Chat("已移除 Caster 技能 "..sid) else Chat("用法 /gprobe casteroff 24018") end
  elseif msg=="skills" then
    local sid,cfg; for sid,cfg in pairs(casterSkills) do Chat(string.format("C %d %s r=%.2f duration=%.2f%s",sid,SkillName(sid,cfg),tonumber(cfg.radius) or 0,tonumber(cfg.duration) or 0,cfg.provisional and " [TEST]" or "")) end
  elseif msg=="go" then includeGO=not includeGO; GroundProbeDB.includeGO=includeGO; Chat("GameObject="..tostring(includeGO))
  elseif msg=="status" then
    panel:Show(); if type(UnitXP)=="function" then local a,b,c=UnitXP("GroundProbe.Status"); Chat("DLL="..tostring(a).." code="..tostring(b).." "..tostring(c)) end
    Chat("B2 running="..tostring(running).." range="..range.." zTol="..zTolerance.." SuperWoW="..tostring(SUPERWOW_VERSION or "?")); Poll()
  else Chat("/gprobe start|stop|show|hide|status|dump|export|clear|range 120|z 4|go|skills|caster ID R D|casteroff ID") end
end