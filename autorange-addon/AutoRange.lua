-- AutoRange B3.6 OneM2 Sources - Turtle WoW 1.12 / SuperWoW 2.2 / TRUE 8x8 UnitXP_SP3
-- Automatically resolves radius from the client's active DBCs. One hazard owns
-- exactly one M2 instance: VisualSet once, VisualMove thereafter, VisualClear on end.
-- Enemy/friendly-player filtering and totem owner filtering are DLL-backed.

AutoRangeDB = AutoRangeDB or {}

local F = CreateFrame("Frame", "AutoRangeEventFrame")
F:RegisterEvent("VARIABLES_LOADED")
F:RegisterEvent("PLAYER_ENTERING_WORLD")
F:RegisterEvent("PLAYER_LEAVING_WORLD")
F:RegisterEvent("UNIT_CASTEVENT")

local running = true
local visualEnabled = true
local enemyCircle = true
local friendCircle = false
local totemMode = "SELF"
local totemLastMode = "SELF"
local scanRange = 140
local elapsed = 0
local totemElapsed = 0
local hazards = {}
local order = {}
local logs = {}
local dynamicMeta = {}
local totemRangeCache = {}
local totemNoRadiusLogged = {}
local dbcStatus = "未读取"

local visualPool = {
  {path="Spells\\DangerZone_W10_S30.m2"},
  {path="Spells\\DangerZone_W10_S30_White.m2"},
  {path="Spells\\DangerZone_W10_S30_Flame.m2"},
  {path="Spells\\DangerZone_W12_S30_Jagged.m2"},
  {path="Spells\\DangerZone_W12_S30_JaggedG.m2"},
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

local function RelationInfo(guid)
  if type(UnitXP) ~= "function" then return "UNKNOWN",-1,"NO_UNITXP",nil end
  local ok,text=pcall(UnitXP,"AutoRange.RelationByGuid",tostring(guid or ""))
  if not ok or type(text)~="string" then return "UNKNOWN",-1,"RELATION_CALL",text end
  local a=Split(text)
  if a[1]~="R" then return "UNKNOWN",-1,"RELATION_FORMAT",text end
  return tostring(a[2] or "UNKNOWN"),tonumber(a[5]) or -1,tostring(a[7] or "?"),text
end

local function GroupScope(guid)
  if type(UnitXP)~="function" then return "UNKNOWN" end
  local ok,text=pcall(UnitXP,"GroundProbe.ScopeByGuid",tostring(guid or ""))
  if not ok or type(text)~="string" then return "UNKNOWN" end
  local a=Split(text)
  if a[1]~="G" then return "UNKNOWN" end
  return tostring(a[2] or "UNKNOWN")
end

local function CasterSourceAllowed(guid)
  local relation,objType,reason,raw=RelationInfo(guid)
  if relation=="HOSTILE" then
    return enemyCircle,"ENEMY",relation,nil,raw
  end
  if relation=="UNKNOWN" then
    -- Fail-safe rule: relation failures follow the enemy switch so real danger is not hidden.
    return enemyCircle,"UNKNOWN",relation,nil,raw
  end
  if relation=="FRIENDLY" then
    -- Friendly NPCs are intentionally not treated as "teammates".
    if objType~=4 then return false,"FRIEND_NPC",relation,nil,raw end
    local scope=GroupScope(guid)
    if scope=="PARTY" or scope=="RAID" then
      return friendCircle,"FRIEND",relation,scope,raw
    end
    -- SELF and friendly strangers stay filtered. Totems have their own independent path.
    return false,(scope=="SELF" and "SELF" or "FRIEND_OTHER"),relation,scope,raw
  end
  return enemyCircle,"UNKNOWN",relation,nil,raw
end

local function Resolve(spell)
  if type(UnitXP) ~= "function" then return nil, "NO_UNITXP" end
  local ok, text = pcall(UnitXP, "AutoRange.Resolve", tonumber(spell) or 0)
  if not ok or type(text) ~= "string" then return nil, "RESOLVE_CALL" end
  local a = Split(text)
  if a[1] ~= "A" then return nil, text end
  return {
    geomSpell=tonumber(a[3]) or spell,
    radius=tonumber(a[4]) or 0,
    durationMs=tonumber(a[5]) or 0,
    mode=a[6] or "UNKNOWN",
    raw=text,
  }, nil
end

local function ParseUnit(text)
  local a = Split(text)
  if a[1] ~= "U" then return nil end
  return {
    x=tonumber(a[5]) or 0, y=tonumber(a[6]) or 0, z=tonumber(a[7]) or 0
  }
end

local function CasterPosition(guid)
  if type(UnitXP) ~= "function" then return nil end
  local ok, text = pcall(UnitXP, "GroundProbe.UnitByGuid", tostring(guid or ""))
  if not ok or type(text) ~= "string" then return nil end
  return ParseUnit(text)
end

local function DynamicSnapshot()
  local list, seen = {}, {}
  if type(UnitXP) ~= "function" then return list end
  local now=GetTime()
  local ok, raw = pcall(UnitXP, "GroundProbe.Snapshot", scanRange, false)
  if not ok or type(raw) ~= "string" then return list end
  Lines(raw, function(line)
    local a = Split(line)
    if a[1] == "D" then
      local guid=NormGuid(a[2])
      if guid~="0" and not seen[guid] then
        seen[guid]=true
        local m=dynamicMeta[guid]
        if not m then m={firstSeen=now,lastSeen=now}; dynamicMeta[guid]=m else m.lastSeen=now end
        table.insert(list, {guid=guid, caster=a[3], spell=tonumber(a[4]) or 0,
          radius=tonumber(a[5]) or 0, x=tonumber(a[6]) or 0, y=tonumber(a[7]) or 0,
          z=tonumber(a[8]) or 0, firstSeen=m.firstSeen})
      end
    end
  end)
  local k,m
  for k,m in pairs(dynamicMeta) do
    if now-(m.lastSeen or now)>8.0 then dynamicMeta[k]=nil end
  end
  return list
end

local function FindDynamic(h, dynamics)
  local i
  if h.dynamicGuid then
    local wanted=NormGuid(h.dynamicGuid)
    for i=1,table.getn(dynamics) do
      if NormGuid(dynamics[i].guid)==wanted then return dynamics[i] end
    end
  end

  -- Exact spell + caster is authoritative.
  for i=1,table.getn(dynamics) do
    local d=dynamics[i]
    local spellMatch=(d.spell==h.spell or d.spell==h.geomSpell)
    local casterMatch=(NormGuid(d.caster)==NormGuid(h.caster))
    if spellMatch and casterMatch then return d end
  end

  -- Some DynamicObjects expose a trigger-child spell or no caster. During the
  -- short creation window accept a UNIQUE exact-spell object.
  local now=GetTime()
  local found=nil
  if now-(h.started or 0)<=1.50 then
    for i=1,table.getn(dynamics) do
      local d=dynamics[i]
      if (d.spell==h.spell or d.spell==h.geomSpell)
          and (d.firstSeen or now)>=(h.started or now)-0.20 then
        if found then found=nil; break end
        found=d
      end
    end
    if found then return found end

    found=nil
    for i=1,table.getn(dynamics) do
      local d=dynamics[i]
      if NormGuid(d.caster)==NormGuid(h.caster)
          and (d.firstSeen or now)>=(h.started or now)-0.20 then
        if found then found=nil; break end
        found=d
      end
    end
    if found then return found end
  end
  return nil
end

local function ModelDiameterYards(path)
  local _,_,w=string.find(tostring(path or ""), "_W([0-9]+)_")
  local n=tonumber(w)
  if n and n>0 then return n end
  return nil
end

local function WorldRadiusScale(radiusYards, modelPath)
  local r=tonumber(radiusYards) or 0
  if r<=0 then return nil,nil,nil,"INVALID_WORLD_RADIUS" end
  local modelDiameter=ModelDiameterYards(modelPath)
  if not modelDiameter then return nil,nil,nil,"MODEL_DIAMETER_UNKNOWN" end
  local targetDiameter=r*2
  local scale=targetDiameter/modelDiameter
  return scale,modelDiameter,targetDiameter,nil
end

local function HashStartIndex(h)
  local n=(tonumber(h.spell) or 0)*131 + math.floor((h.started or GetTime())*1000)
  local s=tostring(h.caster or "")
  local i
  for i=1,string.len(s) do n=n+string.byte(s,i)*i end
  local count=table.getn(visualPool)
  if count<=0 then return 1 end
  return math.mod(n,count)+1
end

local function PickVisual(h)
  local count=table.getn(visualPool)
  if count<=0 then return nil,nil end
  if not h.visualIndex then h.visualIndex=HashStartIndex(h) end
  if not h.visual then h.visual=visualPool[h.visualIndex] end
  return h.visual,h.visualIndex
end

local function ClearVisual(h)
  if not h or not h.visualCreated then return end
  if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClear",h.key) end
  h.visualCreated=false
  h.visualIndex=nil
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
  if h.modeNow~="CASTER" and h.modeNow~="DYNAMIC" and h.modeNow~="TOTEM" then return end

  local v,visualIndex=PickVisual(h)
  if not v then return end

  local scale,modelDiameter,targetDiameter=WorldRadiusScale(h.radius,v.path)
  if not scale then return end
  if scale<0.05 or scale>20.00 then return end

  local z=(h.z or 0)+0.03
  if not h.visualCreated then
    local ok, created=pcall(UnitXP,"AutoRange.VisualSet",h.key,v.path,h.x,h.y,z,scale,0)
    if ok and created then
      h.visualCreated=true
      h.visualIndex=visualIndex
      Log(string.format(
        "VISUAL SET spell=%d r=%.2f idx=%d model=%s scale=%.3f TargetD=%.2f ModelW=%.2f",
        h.spell,h.radius,visualIndex,v.path,scale,targetDiameter,modelDiameter
      ))
    end
  else
    pcall(UnitXP,"AutoRange.VisualMove",h.key,h.x,h.y,z,scale,0)
  end
end

local function UpdateHazard(h, dynamics, claimed)
  local now=GetTime()
  local d=FindDynamic(h,dynamics)
  if d then
    h.modeNow="DYNAMIC"; h.x=d.x; h.y=d.y; h.z=d.z
    h.dynamicGuid=NormGuid(d.guid)
    if claimed then claimed[h.dynamicGuid]=h.key end
    if d.radius and d.radius>0 then h.radius=d.radius end
    h.lastDynamic=now
    if h.expires<now+0.50 then h.expires=now+0.50 end
  elseif h.dynamicGuid and h.lastDynamic and now-h.lastDynamic<=0.35 then
    h.modeNow="DYNAMIC"
  elseif h.dynamicOnly then
    h.modeNow="DYNAMIC?"
    if h.expires>now+0.35 then h.expires=now+0.35 end
  elseif h.modeHint=="CASTER" then
    local u=CasterPosition(h.caster)
    if u then
      h.modeNow="CASTER"; h.x=u.x; h.y=u.y; h.z=u.z
    else h.modeNow="CASTER?" end
  elseif h.modeHint=="CONE" then
    h.modeNow="CONE"
  elseif h.modeHint=="GROUND" then
    h.modeNow="GROUND?"
  else
    h.modeNow="UNKNOWN"
  end
  SetVisual(h)
end

local function NewDynamicHazard(d)
  local guid=NormGuid(d.guid)
  local key="D:"..guid
  if hazards[key] then return hazards[key] end

  local sourceType="UNKNOWN"
  if NormGuid(d.caster)=="0" then
    if not enemyCircle then return nil end
  else
    local allowed,src=CasterSourceAllowed(d.caster)
    if not allowed then return nil end
    sourceType=src or "UNKNOWN"
  end

  local now=GetTime()
  local h={key=key,caster=d.caster,spell=d.spell,geomSpell=d.spell,
    started=d.firstSeen or now,radius=d.radius or 0,modeHint="DYNAMIC",modeNow="DYNAMIC",
    durationSec=0.5,expires=now+0.5,dynamicOnly=true,dynamicGuid=guid,
    sourceType=sourceType,x=d.x,y=d.y,z=d.z}
  hazards[key]=h; table.insert(order,key)
  Log(string.format("DYNAMIC NEW guid=%s spell=%d r=%.2f src=%s",guid,d.spell,d.radius or 0,sourceType))
  return h
end

local function SyncDynamicOnly(dynamics, claimed)
  local i
  for i=1,table.getn(dynamics) do
    local d=dynamics[i]
    local guid=NormGuid(d.guid)
    if not claimed[guid] then
      local h=NewDynamicHazard(d)
      if h then
        h.x=d.x; h.y=d.y; h.z=d.z
        h.radius=d.radius or h.radius; h.lastDynamic=GetTime(); h.expires=GetTime()+0.50
      end
    end
  end
end

local function CsvSpellIds(csv)
  local out={}
  local p=1
  csv=tostring(csv or "")
  while p<=string.len(csv) do
    local q=string.find(csv,",",p,true)
    local part
    if q then part=string.sub(csv,p,q-1); p=q+1
    else part=string.sub(csv,p); p=string.len(csv)+1 end
    local id=tonumber(part)
    if id and id>0 then table.insert(out,id) end
  end
  return out
end

local function ResolveTotemRange(entry,createdSpell,auraCsv)
  local cacheKey=tostring(entry or 0)..":"..tostring(createdSpell or 0)..":"..tostring(auraCsv or "")
  local cached=totemRangeCache[cacheKey]
  if cached then return cached.radius,cached.spell,cached.mode,cached.raw end

  local best=nil
  local ids=CsvSpellIds(auraCsv)
  local i
  for i=1,table.getn(ids) do
    local r=Resolve(ids[i])
    if r and r.radius and r.radius>0 then
      local modeBonus=(r.mode=="CASTER" and 3) or (r.mode=="UNKNOWN" and 2) or 1
      if not best or modeBonus>best.modeBonus
          or (modeBonus==best.modeBonus and r.radius>best.radius) then
        best={radius=r.radius,spell=ids[i],mode=r.mode,raw=r.raw,modeBonus=modeBonus}
      end
    end
  end

  if not best and createdSpell and createdSpell>0 then
    local r=Resolve(createdSpell)
    if r and r.radius and r.radius>0 then
      best={radius=r.radius,spell=createdSpell,mode=r.mode,raw=r.raw,modeBonus=0}
    end
  end

  if best then
    totemRangeCache[cacheKey]=best
    return best.radius,best.spell,best.mode,best.raw
  end
  return nil,nil,nil,nil
end

local function TotemSnapshot()
  if type(UnitXP)~="function" or totemMode=="OFF" then return nil,false end
  local ok,raw=pcall(UnitXP,"GroundProbe.TotemSnapshot",totemMode,scanRange)
  if not ok or type(raw)~="string" then return nil,false end
  return raw,true
end

local function SyncTotems()
  if not running then return end
  if totemMode=="OFF" then return end

  local raw,ok=TotemSnapshot()
  if not ok then return end

  local now=GetTime()
  local seen={}
  local validSnapshot=false

  Lines(raw,function(line)
    local a=Split(line)
    if a[1]=="T" then
      local guid=NormGuid(a[2])
      if guid~="0" then
        seen[guid]=true
        local key="T:"..guid
        local entry=tonumber(a[3]) or 0
        local owner=a[4] or "0"
        local scope=a[5] or "UNKNOWN"
        local createdSpell=tonumber(a[6]) or 0
        local x=tonumber(a[7]); local y=tonumber(a[8]); local z=tonumber(a[9])
        local auraCsv=a[12] or ""
        local h=hazards[key]

        if not h then
          local radius,rangeSpell,rangeMode,rangeRaw=ResolveTotemRange(entry,createdSpell,auraCsv)
          if radius and radius>0 and x and y and z then
            h={key=key,caster=owner,spell=rangeSpell or createdSpell,geomSpell=rangeSpell or createdSpell,
              started=now,radius=radius,modeHint="TOTEM",modeNow="TOTEM",
              durationSec=1.0,expires=now+1.0,totemOnly=true,sourceType="TOTEM",
              entry=entry,owner=owner,ownerScope=scope,createdSpell=createdSpell,
              auraCsv=auraCsv,x=x,y=y,z=z,lastTotem=now}
            hazards[key]=h; table.insert(order,key)
            Log(string.format("TOTEM NEW guid=%s entry=%d owner=%s scope=%s spell=%d r=%.2f",
              guid,entry,tostring(owner),tostring(scope),h.spell or 0,radius))
            if rangeRaw then Log("TOTEM RESOLVE "..rangeRaw) end
          elseif not totemNoRadiusLogged[guid] then
            totemNoRadiusLogged[guid]=true
            Log(string.format("TOTEM WAIT_RANGE guid=%s entry=%d created=%d auras=%s",
              guid,entry,createdSpell,tostring(auraCsv)))
          end
        else
          h.x=x or h.x; h.y=y or h.y; h.z=z or h.z
          h.owner=owner; h.ownerScope=scope; h.lastTotem=now; h.expires=now+1.0
          if h.auraCsv~=auraCsv or h.createdSpell~=createdSpell then
            local radius,rangeSpell=ResolveTotemRange(entry,createdSpell,auraCsv)
            if radius and radius>0 then
              h.radius=radius; h.spell=rangeSpell or h.spell; h.geomSpell=h.spell
            end
            h.auraCsv=auraCsv; h.createdSpell=createdSpell
          end
        end

        if h then SetVisual(h) end
      end
    elseif a[1]=="S" then
      validSnapshot=true
    end
  end)

  if not validSnapshot then return end

  local remove={}
  local i
  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and h.totemOnly then
      local guid=string.gsub(key,"^T:","")
      if not seen[guid] and now-(h.lastTotem or 0)>0.65 then table.insert(remove,key) end
    end
  end
  for i=1,table.getn(remove) do RemoveHazard(remove[i],"totem_gone") end
end

local function RemoveSource(sourceA,sourceB)
  local remove={}
  local i
  for i=1,table.getn(order) do
    local h=hazards[order[i]]
    if h and (h.sourceType==sourceA or (sourceB and h.sourceType==sourceB)) then
      table.insert(remove,h.key)
    end
  end
  for i=1,table.getn(remove) do RemoveHazard(remove[i],"source_disabled") end
end

local totemModes={"SELF","PARTY","PARTY_ONLY","RAID","ALL"}
local totemModeText={
  OFF="关闭",
  SELF="仅自己",
  PARTY="小队(含自己)",
  PARTY_ONLY="仅小队队友",
  RAID="团队",
  ALL="全部",
}

local function SetEnemyCircle(on,announce)
  enemyCircle=on and true or false
  AutoRangeDB.enemyCircle=enemyCircle
  if not enemyCircle then RemoveSource("ENEMY","UNKNOWN") end
  if announce then Chat("敌人圈："..(enemyCircle and "开启" or "关闭")) end
end

local function SetFriendCircle(on,announce)
  friendCircle=on and true or false
  AutoRangeDB.friendCircle=friendCircle
  if not friendCircle then RemoveSource("FRIEND") end
  if announce then Chat("队友圈："..(friendCircle and "开启" or "关闭")) end
end

local function SetTotemMode(mode,announce)
  mode=string.upper(tostring(mode or "OFF"))
  if mode=="PARTYONLY" then mode="PARTY_ONLY" end
  local valid=(mode=="OFF" or mode=="SELF" or mode=="PARTY" or mode=="PARTY_ONLY" or mode=="RAID" or mode=="ALL")
  if not valid then return false end
  totemMode=mode
  AutoRangeDB.totemMode=mode
  if mode~="OFF" then totemLastMode=mode; AutoRangeDB.totemLastMode=mode
  else RemoveSource("TOTEM") end
  if announce then Chat("图腾圈来源："..tostring(totemModeText[mode] or mode)) end
  return true
end

local function CycleTotemMode()
  local current=totemMode
  if current=="OFF" then current=totemLastMode or "SELF" end
  local i
  for i=1,table.getn(totemModes) do
    if totemModes[i]==current then
      local nextIndex=i+1
      if nextIndex>table.getn(totemModes) then nextIndex=1 end
      SetTotemMode(totemModes[nextIndex],true)
      return
    end
  end
  SetTotemMode("SELF",true)
end

local Render

local panel=CreateFrame("Frame","AutoRangePanel",UIParent)
panel:SetWidth(360); panel:SetHeight(176)
panel:SetPoint("TOP",UIParent,"TOP",0,-105)
panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
panel:SetBackdropColor(0.03,0.04,0.06,0.94)
panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart",function() this:StartMoving() end)
panel:SetScript("OnDragStop",function() this:StopMovingOrSizing() end)

local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
title:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-11)
title:SetText("AutoRange  ·  自动危险圈")

local signature=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
signature:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-34,-12)
signature:SetText("|cffd8b45b工会 · 太阳神殿|r")

local closeBtn=CreateFrame("Button",nil,panel,"UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT",panel,"TOPRIGHT",2,2)
closeBtn:SetScript("OnClick",function()
  panel:Hide(); AutoRangeDB.hidden=true
end)

local enableCheck=CreateFrame("CheckButton","AutoRangeEnableCheck",panel,"UICheckButtonTemplate")
enableCheck:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-39)
local enableCheckText=getglobal and getglobal("AutoRangeEnableCheckText") or nil
if enableCheckText then enableCheckText:SetText("自动危险圈") end
enableCheck:SetScript("OnClick",function()
  local on=this:GetChecked() and true or false
  if type(AutoRange_SetEnabled)=="function" then AutoRange_SetEnabled(on,true) end
end)

local stateText=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
stateText:SetPoint("LEFT",enableCheck,"RIGHT",128,0)
stateText:SetJustifyH("RIGHT")

local enemyCheck=CreateFrame("CheckButton","AutoRangeEnemyCheck",panel,"UICheckButtonTemplate")
enemyCheck:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-70)
local enemyCheckText=getglobal and getglobal("AutoRangeEnemyCheckText") or nil
if enemyCheckText then enemyCheckText:SetText("敌人圈") end
enemyCheck:SetScript("OnClick",function()
  SetEnemyCircle(this:GetChecked() and true or false,true)
  if type(Render)=="function" then Render() end
end)

local friendCheck=CreateFrame("CheckButton","AutoRangeFriendCheck",panel,"UICheckButtonTemplate")
friendCheck:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-100)
local friendCheckText=getglobal and getglobal("AutoRangeFriendCheckText") or nil
if friendCheckText then friendCheckText:SetText("队友圈") end
friendCheck:SetScript("OnClick",function()
  SetFriendCircle(this:GetChecked() and true or false,true)
  if type(Render)=="function" then Render() end
end)

local totemCheck=CreateFrame("CheckButton","AutoRangeTotemCheck",panel,"UICheckButtonTemplate")
totemCheck:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-130)
local totemCheckText=getglobal and getglobal("AutoRangeTotemCheckText") or nil
if totemCheckText then totemCheckText:SetText("图腾圈") end
totemCheck:SetScript("OnClick",function()
  if this:GetChecked() then SetTotemMode(totemLastMode or "SELF",true)
  else SetTotemMode("OFF",true) end
  if type(Render)=="function" then Render() end
end)

local totemModeBtn=CreateFrame("Button","AutoRangeTotemModeButton",panel,"UIPanelButtonTemplate")
totemModeBtn:SetWidth(142); totemModeBtn:SetHeight(22)
totemModeBtn:SetPoint("LEFT",totemCheck,"RIGHT",112,0)
totemModeBtn:SetScript("OnClick",function()
  CycleTotemMode()
  if type(Render)=="function" then Render() end
end)

AutoRange_TogglePanel=function()
  if panel:IsVisible() then panel:Hide(); AutoRangeDB.hidden=true
  else panel:Show(); AutoRangeDB.hidden=false end
end

AutoRange_IsEnabled=function()
  return (running and visualEnabled) and true or false
end

Render=function()
  local enabled=(running and visualEnabled) and true or false
  if enableCheck then enableCheck:SetChecked(enabled) end
  if enemyCheck then enemyCheck:SetChecked(enemyCircle) end
  if friendCheck then friendCheck:SetChecked(friendCircle) end
  if totemCheck then totemCheck:SetChecked(totemMode~="OFF") end
  if totemModeBtn then
    local label=totemModeText[totemMode] or totemMode
    if totemMode=="OFF" then label=totemModeText[totemLastMode] or "仅自己" end
    totemModeBtn:SetText("来源："..tostring(label))
  end
  if stateText then
    if enabled then stateText:SetText("|cff55ff77已开启|r")
    else stateText:SetText("|cffff6666已关闭|r") end
  end
  if AutoRange_FuBarEntry and type(AutoRange_FuBarEntry.UpdateText)=="function" then
    pcall(AutoRange_FuBarEntry.UpdateText,AutoRange_FuBarEntry)
  end
end

local function AddOrRefreshCast(caster,spell)
  if not running or not spell or spell<=0 or not caster then return end
  local allowed,sourceType,relation,scope,relationRaw=CasterSourceAllowed(caster)
  if not allowed then return end

  local key=NormGuid(caster)..":"..tostring(spell); local now=GetTime(); local existing=hazards[key]
  if existing then
    existing.expires=now+math.max(existing.durationSec or 0.75,0.75)
    return
  end

  local r,err=Resolve(spell)
  local h={key=key,caster=caster,spell=spell,geomSpell=spell,started=now,radius=0,
    modeHint="UNKNOWN",modeNow="PENDING",durationSec=0.75,expires=now+0.75,
    sourceType=sourceType or "UNKNOWN",relation=relation,groupScope=scope}
  if r then
    h.geomSpell=r.geomSpell; h.radius=r.radius; h.modeHint=r.mode; h.modeNow=r.mode
    h.durationSec=(r.durationMs>0 and r.durationMs/1000 or 2.0); h.expires=now+math.max(h.durationSec,0.75)
    Log("RESOLVE "..r.raw)
  else
    h.durationSec=1.2; h.expires=now+1.2; Log("RESOLVE_FAIL spell="..spell.." "..tostring(err))
  end
  if relationRaw then Log("RELATION "..tostring(relationRaw)) end
  hazards[key]=h; table.insert(order,key)
end

local function ClearAll(reason)
  if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClearAll") end
  hazards={}; order={}; dynamicMeta={}; totemNoRadiusLogged={}; Log("CLEAR_ALL "..tostring(reason or ""))
end

AutoRange_SetEnabled=function(enabled,announce)
  local on=enabled and true or false
  running=on
  visualEnabled=on
  AutoRangeDB.running=on
  AutoRangeDB.visualEnabled=on
  if not on then ClearAll("toggle_off") end
  if announce then Chat(on and "自动危险圈已开启。" or "自动危险圈已关闭。") end
  Render()
end

AutoRange_ToggleEnabled=function(announce)
  local on=not ((running and visualEnabled) and true or false)
  AutoRange_SetEnabled(on,announce)
  return on
end

local function Poll()
  if not running then Render(); return end
  local dynamics=DynamicSnapshot(); local now=GetTime(); local claimed={}; local remove={}; local i

  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and not h.dynamicOnly and not h.totemOnly then UpdateHazard(h,dynamics,claimed) end
  end

  local guid,owner
  for guid,owner in pairs(claimed) do
    local orphanKey="D:"..guid
    if hazards[orphanKey] and orphanKey~=owner then RemoveHazard(orphanKey,"merged_into_cast") end
  end

  SyncDynamicOnly(dynamics,claimed)

  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and h.dynamicOnly then UpdateHazard(h,dynamics,claimed) end
  end

  now=GetTime()
  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and not h.totemOnly and now>(h.expires or now) and (not h.lastDynamic or now-h.lastDynamic>0.35) then table.insert(remove,key) end
  end
  for i=1,table.getn(remove) do RemoveHazard(remove[i],"expired") end
  Render()
end

F:SetScript("OnEvent",function()
  if event=="VARIABLES_LOADED" then
    if AutoRangeDB.running==nil then AutoRangeDB.running=true end
    if AutoRangeDB.visualEnabled==nil then AutoRangeDB.visualEnabled=true end
    if AutoRangeDB.enemyCircle==nil then AutoRangeDB.enemyCircle=true end
    if AutoRangeDB.friendCircle==nil then AutoRangeDB.friendCircle=false end
    if AutoRangeDB.totemMode==nil then AutoRangeDB.totemMode="SELF" end
    if AutoRangeDB.totemLastMode==nil then AutoRangeDB.totemLastMode="SELF" end

    running=AutoRangeDB.running and true or false
    visualEnabled=AutoRangeDB.visualEnabled and true or false
    enemyCircle=AutoRangeDB.enemyCircle and true or false
    friendCircle=AutoRangeDB.friendCircle and true or false
    totemMode=string.upper(tostring(AutoRangeDB.totemMode or "SELF"))
    totemLastMode=string.upper(tostring(AutoRangeDB.totemLastMode or "SELF"))
    if totemLastMode=="OFF" then totemLastMode="SELF" end

    if type(UnitXP)=="function" then
      local ok,s=pcall(UnitXP,"AutoRange.Status")
      dbcStatus=(ok and type(s)=="string") and s or "STATUS_FAIL"
    end
    if AutoRangeDB.hidden then panel:Hide() else panel:Show() end
    Render()
  elseif event=="PLAYER_ENTERING_WORLD" then
    ClearAll("enter_world")
    if running then Poll(); SyncTotems() end
  elseif event=="PLAYER_LEAVING_WORLD" then
    ClearAll("leave_world")
  elseif event=="UNIT_CASTEVENT" then
    local kind=string.upper(tostring(arg3 or "")); local spell=tonumber(arg4) or 0
    if kind=="START" or kind=="CAST" or kind=="CHANNEL" then AddOrRefreshCast(arg1,spell)
    elseif kind=="FAIL" then RemoveHazard(NormGuid(arg1)..":"..tostring(spell),"cast_fail") end
  end
end)

F:SetScript("OnUpdate",function()
  local dt=arg1 or 0
  elapsed=elapsed+dt
  totemElapsed=totemElapsed+dt
  if elapsed>=0.15 then elapsed=0; Poll() end
  if totemElapsed>=0.50 then totemElapsed=0; SyncTotems() end
end)

local function ResetNativeVisualFlags()
  local i
  for i=1,table.getn(order) do
    local h=hazards[order[i]]
    if h then h.visualCreated=false end
  end
end

SLASH_AUTORANGE1="/arange"
SlashCmdList["AUTORANGE"]=function(msg)
  msg=string.lower(tostring(msg or "")); msg=string.gsub(msg,"^%s+",""); msg=string.gsub(msg,"%s+$","")
  if msg=="start" or msg=="on" then
    AutoRange_SetEnabled(true,true); panel:Show(); AutoRangeDB.hidden=false
  elseif msg=="stop" or msg=="off" then
    AutoRange_SetEnabled(false,true)
  elseif msg=="show" then
    panel:Show(); AutoRangeDB.hidden=false
  elseif msg=="hide" then
    panel:Hide(); AutoRangeDB.hidden=true
  elseif msg=="visual on" then
    visualEnabled=true; AutoRangeDB.visualEnabled=true; Chat("危险圈视觉：开启"); Render()
  elseif msg=="visual off" then
    visualEnabled=false; AutoRangeDB.visualEnabled=false
    if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClearAll") end
    ResetNativeVisualFlags()
    Chat("危险圈视觉：关闭"); Render()
  elseif msg=="enemy on" or msg=="hostile on" then
    SetEnemyCircle(true,true); Render()
  elseif msg=="enemy off" or msg=="hostile off" then
    SetEnemyCircle(false,true); Render()
  elseif msg=="friend on" then
    SetFriendCircle(true,true); Render()
  elseif msg=="friend off" then
    SetFriendCircle(false,true); Render()
  elseif string.find(msg,"^totem%s+") then
    local mode=string.gsub(msg,"^totem%s+","")
    mode=string.upper(mode)
    if mode=="PARTYONLY" then mode="PARTY_ONLY" end
    if not SetTotemMode(mode,true) then
      Chat("图腾模式：off | self | party | partyonly | raid | all")
    end
    Render()
  elseif msg=="totemraw" then
    if type(UnitXP)~="function" then Chat("没有 UnitXP")
    else
      local mode=totemMode~="OFF" and totemMode or (totemLastMode or "SELF")
      local ok,raw=pcall(UnitXP,"GroundProbe.TotemSnapshot",mode,scanRange)
      Chat(ok and tostring(raw) or "TotemSnapshot 调用失败")
    end
  elseif msg=="clear" then
    ClearAll("command")
  elseif msg=="vtest" or string.find(msg,"^vtest%s+") then
    panel:Show(); AutoRangeDB.hidden=false
    local radius=5
    if msg~="vtest" then local raw=string.gsub(msg,"^vtest%s+",""); radius=tonumber(raw) or 5 end
    if radius<=0 or radius>100 then Chat("vtest半径需为 0~100 码")
    elseif type(UnitXP)~="function" then Chat("vtest失败：没有UnitXP")
    elseif type(CursorPosition)~="function" then Chat("vtest失败：没有CursorPosition()，确认SuperWoW 2.2 + SuperAPI")
    else
      local ok,x,y,z=pcall(CursorPosition)
      if not ok or not x or not y or not z then Chat("vtest失败：鼠标世界坐标不可用")
      else
        local v=visualPool[1]
        local scale,modelDiameter,targetDiameter,scaleErr=WorldRadiusScale(radius,v.path)
        pcall(UnitXP,"AutoRange.VisualClear","__VTEST__")
        if not scale then Chat("vtest失败："..tostring(scaleErr))
        else
          local ok2,created,normalized,stage=pcall(UnitXP,"AutoRange.VisualSet","__VTEST__",v.path,x,y,z+0.03,scale,0)
          if ok2 and created then Chat(string.format("vtest成功：WorldR=%.2f码 TargetD=%.2f码 ModelW=%.0f Scale=%.3f",radius,targetDiameter,modelDiameter,scale))
          else Chat("vtest失败："..tostring(stage or normalized or created or "CREATE_FAIL")) end
        end
      end
    end
  elseif msg=="vclear" then
    if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClear","__VTEST__") end
    Chat("vtest测试圈已清除")
  elseif msg=="status" then
    panel:Show(); AutoRangeDB.hidden=false
    if type(UnitXP)=="function" then
      local ok,s=pcall(UnitXP,"AutoRange.Status"); dbcStatus=(ok and s) or "STATUS_FAIL"
    end
    Chat("DBC="..tostring(dbcStatus)
      .." running="..tostring(running)
      .." visual="..tostring(visualEnabled)
      .." enemy="..tostring(enemyCircle)
      .." friend="..tostring(friendCircle)
      .." totem="..tostring(totemMode))
    Render()
  elseif string.find(msg,"^resolve%s+") then
    local raw=string.gsub(msg,"^resolve%s+",""); local id=tonumber(raw)
    if id then local r,e=Resolve(id); Chat(r and r.raw or tostring(e))
    else Chat("用法 /arange resolve 24018") end
  elseif msg=="export" then
    if type(ExportFile)=="function" then
      local ok,err=pcall(ExportFile,"AutoRange.txt",table.concat(logs,"\r\n"))
      Chat(ok and "已导出 AutoRange.txt" or ("导出失败: "..tostring(err)))
    else Chat("没有 ExportFile()；确认 SuperWoW 2.2 + SuperAPI。") end
  else
    Chat("/arange on|off|show|hide|status|clear | enemy on|off | friend on|off | totem off|self|party|partyonly|raid|all | totemraw | vtest [半径] | resolve ID | export")
  end
end
