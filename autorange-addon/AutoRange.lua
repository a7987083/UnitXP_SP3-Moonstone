-- AutoRange B3 - Turtle WoW 1.12 / SuperWoW 2.2 / TRUE 8x8 UnitXP_SP3
-- Automatically resolves radius from the client's active DBCs. DynamicObject
-- positions override caster-centered estimates. patch-O supplies the M2 assets.

AutoRangeDB = AutoRangeDB or {}

local F = CreateFrame("Frame", "AutoRangeEventFrame")
F:RegisterEvent("VARIABLES_LOADED")
F:RegisterEvent("PLAYER_ENTERING_WORLD")
F:RegisterEvent("PLAYER_LEAVING_WORLD")
F:RegisterEvent("UNIT_CASTEVENT")

local running = true
local visualEnabled = true
local hostileOnly = true
local zTol = 4.0
local scanRange = 140
local elapsed = 0
local hazards = {}
local order = {}
local logs = {}
local dbcStatus = "未读取"
local lastEventText = "等待怪物施法..."

local visualPool = {
  {path="Spells\\DangerZone_W10_S30.m2",        base=10, tag="标准"},
  {path="Spells\\DangerZone_W10_S30_White.m2",  base=10, tag="白色"},
  {path="Spells\\DangerZone_W10_S30_Flame.m2",  base=10, tag="火焰"},
  {path="Spells\\DangerZone_W12_S30_Jagged.m2", base=12, tag="锯齿"},
  {path="Spells\\DangerZone_W12_S30_JaggedG.m2",base=12, tag="绿色锯齿"},
}

local function Chat(s)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[AutoRange]|r " .. tostring(s)) end
end

local function Log(s)
  table.insert(logs, string.format("%.3f %s", GetTime(), tostring(s)))
  while table.getn(logs) > 2000 do table.remove(logs, 1) end
end

local function Split(line)
  local t, p = {}, 1
  line = tostring(line or "")
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

local function NormGuid(v)
  local s = string.upper(tostring(v or ""))
  s = string.gsub(s, "^0X", "")
  s = string.gsub(s, "^0+", "")
  if s == "" then s = "0" end
  return s
end

local function SpellName(id)
  if type(SpellInfo) == "function" then
    local ok, a = pcall(SpellInfo, tonumber(id) or 0)
    if ok and a and tostring(a) ~= "" then return tostring(a) end
  end
  return "Spell " .. tostring(id)
end

local function IsHostileCaster(guid)
  local playerGuid = nil
  if type(UnitGUID) == "function" then
    local ok, v = pcall(UnitGUID, "player")
    if ok then playerGuid = v end
  end
  if playerGuid and NormGuid(playerGuid) == NormGuid(guid) then return false end
  if not hostileOnly then return true end
  if type(UnitCanAttack) == "function" then
    local ok, v = pcall(UnitCanAttack, "player", guid)
    if ok then return v and true or false end
  end
  return true
end

local function Resolve(spell)
  if type(UnitXP) ~= "function" then return nil, "NO_UNITXP" end
  local ok, text = pcall(UnitXP, "AutoRange.Resolve", tonumber(spell) or 0)
  if not ok or type(text) ~= "string" then return nil, "RESOLVE_CALL" end
  local a = Split(text)
  if a[1] ~= "A" then return nil, text end
  return {
    castSpell=tonumber(a[2]) or spell,
    geomSpell=tonumber(a[3]) or spell,
    radius=tonumber(a[4]) or 0,
    durationMs=tonumber(a[5]) or 0,
    mode=a[6] or "UNKNOWN",
    radiusSource=a[7] or "?",
    radiusIndex=tonumber(a[8]) or 0,
    targetA=tonumber(a[9]) or 0,
    targetB=tonumber(a[10]) or 0,
    depth=tonumber(a[11]) or 0,
    spellArchive=a[12] or "?",
    radiusArchive=a[13] or "?",
    durationArchive=a[14] or "?",
    raw=text,
  }, nil
end

local function ParseUnit(text)
  local a = Split(text)
  if a[1] ~= "U" then return nil end
  return {guid=a[2], entry=tonumber(a[3]) or 0, objType=tonumber(a[4]) or 0,
    x=tonumber(a[5]) or 0, y=tonumber(a[6]) or 0, z=tonumber(a[7]) or 0,
    dist=tonumber(a[8]) or 0, zdiff=tonumber(a[9]) or 0}
end

local function CasterPosition(guid)
  if type(UnitXP) ~= "function" then return nil end
  local ok, text = pcall(UnitXP, "GroundProbe.UnitByGuid", tostring(guid or ""))
  if not ok or type(text) ~= "string" then return nil end
  return ParseUnit(text)
end

local function DynamicSnapshot()
  local list = {}
  if type(UnitXP) ~= "function" then return list end
  local ok, text = pcall(UnitXP, "GroundProbe.Snapshot", scanRange, false)
  if not ok or type(text) ~= "string" then return list end
  Lines(text, function(line)
    local a = Split(line)
    if a[1] == "D" then
      table.insert(list, {guid=a[2], caster=a[3], spell=tonumber(a[4]) or 0,
        radius=tonumber(a[5]) or 0, x=tonumber(a[6]) or 0, y=tonumber(a[7]) or 0,
        z=tonumber(a[8]) or 0, dist=tonumber(a[9]) or 0, zdiff=tonumber(a[10]) or 0})
    end
  end)
  return list
end

local function FindDynamic(h, dynamics)
  local i
  for i=1,table.getn(dynamics) do
    local d=dynamics[i]
    local spellMatch=(d.spell==h.spell or d.spell==h.geomSpell)
    local casterMatch=(NormGuid(d.caster)==NormGuid(h.caster))
    if spellMatch and (casterMatch or NormGuid(d.caster)=="0") then return d end
  end
  local found=nil
  if GetTime()-(h.started or 0) <= 1.0 then
    for i=1,table.getn(dynamics) do
      local d=dynamics[i]
      if d.spell==h.spell or d.spell==h.geomSpell then
        if found then return nil end
        found=d
      end
    end
  end
  return found
end

local function HashChoice(h)
  local n=(tonumber(h.spell) or 0)*131 + math.floor((h.started or GetTime())*1000)
  local s=tostring(h.caster or "")
  local i
  for i=1,string.len(s) do n=n+string.byte(s,i)*i end
  local count=table.getn(visualPool)
  return visualPool[math.mod(n,count)+1]
end

local function PickVisual(h)
  if h.visual then return h.visual end
  h.visual=HashChoice(h)
  h.visualScale=h.radius>0 and (h.radius/h.visual.base) or 1
  return h.visual
end

local function ClearVisual(h)
  if not h or not h.visualCreated then return end
  if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClear",h.key) end
  h.visualCreated=false
end

local function RemoveHazard(key, reason)
  local h=hazards[key]
  if not h then return end
  ClearVisual(h)
  hazards[key]=nil
  local i
  for i=table.getn(order),1,-1 do if order[i]==key then table.remove(order,i) end end
  Log("REMOVE key="..key.." reason="..tostring(reason or "expired"))
end

local function SetVisual(h)
  if not visualEnabled or h.radius<=0 or not h.x then return end
  if h.modeNow~="CASTER" and h.modeNow~="DYNAMIC" then return end
  local v=PickVisual(h)
  local scale=h.radius/v.base
  h.visualScale=scale
  if scale<0.10 or scale>5.00 then h.visualError="SCALE_OUT_OF_RANGE"; return end
  local z=(h.z or 0)+0.03
  if not h.visualCreated then
    local ok, created, normalized, stage=pcall(UnitXP,"AutoRange.VisualSet",h.key,v.path,h.x,h.y,z,scale,0)
    if ok and created then
      h.visualCreated=true; h.visualPath=normalized or v.path; h.visualError=nil
      Log(string.format("VISUAL SET spell=%d r=%.2f model=%s scale=%.3f",h.spell,h.radius,v.path,scale))
    else h.visualError=tostring(stage or normalized or "CREATE_FAIL") end
  else
    local ok, moved=pcall(UnitXP,"AutoRange.VisualMove",h.key,h.x,h.y,z,scale,0)
    if not ok or not moved then h.visualError="MOVE_FAIL" end
  end
end

local function UpdateInside(h)
  h.inside=(h.radius and h.radius>0 and h.dist and h.zdiff and h.dist<=h.radius and h.zdiff<=zTol) and true or false
end

local function UpdateHazard(h, dynamics)
  local now=GetTime()
  local d=FindDynamic(h,dynamics)
  if d then
    h.modeNow="DYNAMIC"; h.x=d.x; h.y=d.y; h.z=d.z; h.dist=d.dist; h.zdiff=d.zdiff
    if d.radius and d.radius>0 then h.radius=d.radius; h.radiusSourceNow="DYNAMICOBJECT" end
    h.lastDynamic=now
    if h.expires<now+0.45 then h.expires=now+0.45 end
  elseif h.modeHint=="CASTER" then
    local u=CasterPosition(h.caster)
    if u then
      h.modeNow="CASTER"; h.entry=u.entry; h.x=u.x; h.y=u.y; h.z=u.z; h.dist=u.dist; h.zdiff=u.zdiff
    else h.modeNow="CASTER?"; h.positionError="CASTER_NOT_VISIBLE" end
  elseif h.modeHint=="CONE" then
    h.modeNow="CONE"; h.positionError="CONE_UNSUPPORTED"
  elseif h.modeHint=="GROUND" then
    h.modeNow="GROUND?"; h.positionError="WAIT_DYNAMICOBJECT"
  else
    h.modeNow="UNKNOWN"; h.positionError="NO_CENTER"
  end
  UpdateInside(h)
  SetVisual(h)
end

local panel=CreateFrame("Frame","AutoRangePanel",UIParent)
panel:SetWidth(900); panel:SetHeight(285)
panel:SetPoint("TOP",UIParent,"TOP",0,-90)
panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
panel:SetBackdropColor(0,0,0,0.86)
panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart",function() this:StartMoving() end)
panel:SetScript("OnDragStop",function() this:StopMovingOrSizing() end)

local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
title:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-10)
title:SetText("AutoRange B3  ·  自动技能范围 + patch-O 随机视觉")
local statusText=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
statusText:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-7); statusText:SetWidth(870); statusText:SetJustifyH("LEFT")
local body=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
body:SetPoint("TOPLEFT",statusText,"BOTTOMLEFT",0,-7); body:SetWidth(870); body:SetHeight(225); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")

local function ShortModel(path)
  local s=tostring(path or "-"); local p=1
  while true do local q=string.find(s,"\\",p,true); if not q then return string.sub(s,p) end; p=q+1 end
end

local function Render()
  local active=table.getn(order)
  statusText:SetText(string.format("运行=%s  视觉=%s  活动=%d  zTol=%.1f  SuperWoW=%s  DBC=%s",tostring(running),tostring(visualEnabled),active,zTol,tostring(SUPERWOW_VERSION or "?"),tostring(dbcStatus)))
  local out={"最近事件: "..tostring(lastEventText)}
  local shown=0; local i
  for i=table.getn(order),1,-1 do
    local h=hazards[order[i]]
    if h and shown<6 then
      shown=shown+1
      local inside=h.inside and "|cffff3030INSIDE|r" or "|cff55ff77OUT|r"
      local dist=h.dist and string.format("%.2f",h.dist) or "?"
      local r=h.radius and string.format("%.2f",h.radius) or "?"
      local dur=math.max(0,(h.expires or GetTime())-GetTime())
      table.insert(out,string.format("[%s] %s  spell=%d geom=%d  R=%s  dist=%s zD=%s  %s  剩余=%.1fs",tostring(h.modeNow or h.modeHint),tostring(h.name),h.spell,h.geomSpell or h.spell,r,dist,h.zdiff and string.format("%.2f",h.zdiff) or "?",inside,dur))
      table.insert(out,string.format("    RadiusSrc=%s/%s depth=%d  target=%d,%d  entry=%s  Visual=%s x%.3f%s",tostring(h.radiusSourceNow or h.radiusSource),tostring(h.radiusSource),h.depth or 0,h.targetA or 0,h.targetB or 0,tostring(h.entry or "?"),ShortModel(h.visualPath or (h.visual and h.visual.path)),h.visualScale or 0,h.visualError and ("  ERR="..h.visualError) or ""))
    end
  end
  if shown==0 then table.insert(out,"等待怪物施法。检测到圆形/地面范围后会自动显示半径；非圆形 CONE 暂不画圈。") end
  body:SetText(table.concat(out,"\n"))
end

local function AddOrRefreshCast(caster,spell,kind,castMs)
  if not running or not spell or spell<=0 or not caster then return end
  if not IsHostileCaster(caster) then return end
  local key=NormGuid(caster)..":"..tostring(spell); local now=GetTime(); local existing=hazards[key]
  if existing then
    existing.lastEvent=kind; existing.expires=now+math.max(existing.durationSec or 0.75,0.75)
    lastEventText=string.format("%s %d %s (刷新)",kind,spell,existing.name); return
  end
  local r,err=Resolve(spell)
  local h={key=key,caster=caster,spell=spell,geomSpell=spell,name=SpellName(spell),started=now,radius=0,modeHint="UNKNOWN",modeNow="PENDING",radiusSource="NONE",radiusSourceNow=nil,durationSec=0.75,expires=now+0.75,depth=0,targetA=0,targetB=0,lastEvent=kind,resolveError=err}
  if r then
    h.geomSpell=r.geomSpell; h.radius=r.radius; h.modeHint=r.mode; h.modeNow=r.mode; h.radiusSource=r.radiusSource
    h.durationSec=(r.durationMs>0 and r.durationMs/1000 or 2.0); h.expires=now+math.max(h.durationSec,0.75); h.depth=r.depth
    h.targetA=r.targetA; h.targetB=r.targetB; h.radiusIndex=r.radiusIndex; h.spellArchive=r.spellArchive; h.radiusArchive=r.radiusArchive; h.durationArchive=r.durationArchive
    lastEventText=string.format("%s %d %s → AUTO R=%.2f %s/%s",kind,spell,h.name,h.radius,h.modeHint,h.radiusSource); Log("RESOLVE "..r.raw)
  else
    h.durationSec=1.2; h.expires=now+1.2; lastEventText=string.format("%s %d %s → %s",kind,spell,h.name,tostring(err)); Log("RESOLVE_FAIL spell="..spell.." "..tostring(err))
  end
  hazards[key]=h; table.insert(order,key)
end

local function ClearAll(reason)
  if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClearAll") end
  hazards={}; order={}; Log("CLEAR_ALL "..tostring(reason or ""))
end

local function Poll()
  if not running then Render(); return end
  local dynamics=DynamicSnapshot(); local now=GetTime(); local remove={}; local i
  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h then
      UpdateHazard(h,dynamics)
      if now>(h.expires or now) and (not h.lastDynamic or now-h.lastDynamic>0.35) then table.insert(remove,key) end
    end
  end
  for i=1,table.getn(remove) do RemoveHazard(remove[i],"expired") end
  Render()
end

F:SetScript("OnEvent",function()
  if event=="VARIABLES_LOADED" then
    if AutoRangeDB.running==nil then AutoRangeDB.running=true end
    if AutoRangeDB.visualEnabled==nil then AutoRangeDB.visualEnabled=true end
    if AutoRangeDB.hostileOnly==nil then AutoRangeDB.hostileOnly=true end
    running=AutoRangeDB.running and true or false; visualEnabled=AutoRangeDB.visualEnabled and true or false; hostileOnly=AutoRangeDB.hostileOnly and true or false
    zTol=tonumber(AutoRangeDB.zTol) or 4.0
    if type(UnitXP)=="function" then local ok,s=pcall(UnitXP,"AutoRange.Status"); dbcStatus=(ok and type(s)=="string") and s or "STATUS_FAIL" end
    if AutoRangeDB.hidden then panel:Hide() else panel:Show() end
    Render()
  elseif event=="PLAYER_ENTERING_WORLD" then ClearAll("enter_world"); if running then Poll() end
  elseif event=="PLAYER_LEAVING_WORLD" then ClearAll("leave_world")
  elseif event=="UNIT_CASTEVENT" then
    local kind=string.upper(tostring(arg3 or "")); local spell=tonumber(arg4) or 0
    if kind=="START" or kind=="CAST" or kind=="CHANNEL" then AddOrRefreshCast(arg1,spell,kind,tonumber(arg5) or 0)
    elseif kind=="FAIL" then RemoveHazard(NormGuid(arg1)..":"..tostring(spell),"cast_fail") end
  end
end)

F:SetScript("OnUpdate",function()
  elapsed=elapsed+(arg1 or 0)
  if elapsed>=0.15 then elapsed=0; Poll() end
end)

SLASH_AUTORANGE1="/arange"
SlashCmdList["AUTORANGE"]=function(msg)
  msg=string.lower(tostring(msg or "")); msg=string.gsub(msg,"^%s+",""); msg=string.gsub(msg,"%s+$","")
  if msg=="start" or msg=="on" then running=true; AutoRangeDB.running=true; panel:Show(); AutoRangeDB.hidden=false; Chat("自动检测已开启。")
  elseif msg=="stop" or msg=="off" then running=false; AutoRangeDB.running=false; ClearAll("stop"); Chat("自动检测已关闭。")
  elseif msg=="show" then panel:Show(); AutoRangeDB.hidden=false
  elseif msg=="hide" then panel:Hide(); AutoRangeDB.hidden=true
  elseif msg=="visual on" then visualEnabled=true; AutoRangeDB.visualEnabled=true; Chat("patch-O 随机视觉：开启")
  elseif msg=="visual off" then visualEnabled=false; AutoRangeDB.visualEnabled=false; if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClearAll") end; Chat("patch-O 随机视觉：关闭")
  elseif msg=="hostile on" then hostileOnly=true; AutoRangeDB.hostileOnly=true; Chat("仅敌对施法：开启")
  elseif msg=="hostile off" then hostileOnly=false; AutoRangeDB.hostileOnly=false; Chat("仅敌对施法：关闭")
  elseif msg=="clear" then ClearAll("command")
  elseif msg=="status" then panel:Show(); AutoRangeDB.hidden=false; if type(UnitXP)=="function" then local ok,s=pcall(UnitXP,"AutoRange.Status"); dbcStatus=(ok and s) or "STATUS_FAIL" end; Chat("DBC="..tostring(dbcStatus).." running="..tostring(running).." visual="..tostring(visualEnabled)); Render()
  elseif string.find(msg,"^resolve%s+") then local id=tonumber(string.gsub(msg,"^resolve%s+","")); if id then local r,e=Resolve(id); Chat(r and r.raw or tostring(e)) else Chat("用法 /arange resolve 24018") end
  elseif string.find(msg,"^ztol%s+") then local n=tonumber(string.gsub(msg,"^ztol%s+","")); if n and n>=0 and n<=30 then zTol=n; AutoRangeDB.zTol=n; Chat("Z容差="..n) else Chat("用法 /arange ztol 4") end
  elseif msg=="export" then
    if type(ExportFile)=="function" then local ok,err=pcall(ExportFile,"AutoRange.txt",table.concat(logs,"\r\n")); Chat(ok and "已导出 AutoRange.txt" or ("导出失败: "..tostring(err)))
    else Chat("没有 ExportFile()；确认 SuperWoW 2.2 + SuperAPI。") end
  else Chat("/arange start|stop|show|hide|status|clear|visual on|off|hostile on|off|resolve 24018|ztol 4|export") end
end
