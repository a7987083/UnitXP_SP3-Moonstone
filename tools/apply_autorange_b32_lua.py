#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else "autorange-addon/AutoRange.lua")
if not path.is_file():
    raise SystemExit(f"missing {path}")
text = path.read_text(encoding="utf-8")

# This patch runs after apply_autorange_b31_lua_fix.py.
text = text.replace("-- AutoRange B3.1 - Turtle WoW 1.12", "-- AutoRange B3.2 - Turtle WoW 1.12", 1)
text = text.replace("AutoRange B3.1  ·  自动技能范围 + patch-O 随机视觉", "AutoRange B3.2  ·  Caster + DynamicObject 自动范围", 1)

marker = 'local logs = {}\n'
if marker not in text:
    raise SystemExit("logs marker missing")
text = text.replace(marker, marker + 'local dynamicMeta = {}\n', 1)

old_resolve_tail = '''    durationArchive=a[14] or "?",
    raw=text,
'''
new_resolve_tail = '''    durationArchive=a[14] or "?",
    effect=tonumber(a[15]) or 0,
    effectIndex=tonumber(a[16]) or 0,
    geometryScore=tonumber(a[17]) or 0,
    raw=text,
'''
if old_resolve_tail not in text:
    raise SystemExit("Resolve tail marker missing")
text = text.replace(old_resolve_tail, new_resolve_tail, 1)

start = text.find('local function DynamicSnapshot()')
end = text.find('\nlocal function HashChoice(h)', start)
if start < 0 or end < 0:
    raise SystemExit("DynamicSnapshot/FindDynamic block markers missing")
new_dynamic_block = r'''local function DynamicSnapshot()
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
          z=tonumber(a[8]) or 0, dist=tonumber(a[9]) or 0, zdiff=tonumber(a[10]) or 0,
          firstSeen=m.firstSeen})
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

  -- Some DynamicObjects expose a trigger-child spell or no caster.  During the
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

    -- Last fallback: a UNIQUE newly-created DynamicObject from the same caster.
    -- This handles parent cast -> trigger child -> DynamicObject chains without
    -- guessing when several ground objects are spawned at once.
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
'''
text = text[:start] + new_dynamic_block + text[end:]

start = text.find('local function UpdateHazard(h, dynamics)')
end = text.find('\nlocal panel=CreateFrame', start)
if start < 0 or end < 0:
    raise SystemExit("UpdateHazard block marker missing")
new_update = r'''local function UpdateHazard(h, dynamics, claimed)
  local now=GetTime()
  local d=FindDynamic(h,dynamics)
  if d then
    h.modeNow="DYNAMIC"; h.x=d.x; h.y=d.y; h.z=d.z; h.dist=d.dist; h.zdiff=d.zdiff
    h.dynamicGuid=NormGuid(d.guid); h.dynamicSpell=d.spell
    if claimed then claimed[h.dynamicGuid]=h.key end
    if d.radius and d.radius>0 then h.radius=d.radius; h.radiusSourceNow="DYNAMICOBJECT" end
    h.lastDynamic=now; h.positionError=nil
    if h.expires<now+0.50 then h.expires=now+0.50 end
  elseif h.dynamicGuid and h.lastDynamic and now-h.lastDynamic<=0.35 then
    -- Avoid one-frame CASTER snap-back while the object manager is removing D.
    h.modeNow="DYNAMIC"
  elseif h.dynamicOnly then
    h.modeNow="DYNAMIC?"; h.positionError="DYNAMIC_GONE"
    if h.expires>now+0.35 then h.expires=now+0.35 end
  elseif h.modeHint=="CASTER" then
    local u=CasterPosition(h.caster)
    if u then
      h.modeNow="CASTER"; h.entry=u.entry; h.x=u.x; h.y=u.y; h.z=u.z; h.dist=u.dist; h.zdiff=u.zdiff; h.positionError=nil
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

local function NewDynamicHazard(d)
  local guid=NormGuid(d.guid)
  local key="D:"..guid
  if hazards[key] then return hazards[key] end
  if hostileOnly and NormGuid(d.caster)~="0" and not IsHostileCaster(d.caster) then return nil end
  local now=GetTime()
  local h={key=key,caster=d.caster,spell=d.spell,geomSpell=d.spell,name=SpellName(d.spell),
    started=d.firstSeen or now,radius=d.radius or 0,modeHint="DYNAMIC",modeNow="DYNAMIC",
    radiusSource="DYNAMICOBJECT",radiusSourceNow="DYNAMICOBJECT",durationSec=0.5,expires=now+0.5,
    depth=0,targetA=0,targetB=0,lastEvent="DYNAMIC",dynamicOnly=true,dynamicGuid=guid,
    dynamicSpell=d.spell,x=d.x,y=d.y,z=d.z,dist=d.dist,zdiff=d.zdiff,effect=0,effectIndex=0,geometryScore=999}
  hazards[key]=h; table.insert(order,key)
  Log(string.format("DYNAMIC NEW guid=%s spell=%d r=%.2f",guid,d.spell,d.radius or 0))
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
        h.x=d.x; h.y=d.y; h.z=d.z; h.dist=d.dist; h.zdiff=d.zdiff
        h.radius=d.radius or h.radius; h.lastDynamic=GetTime(); h.expires=GetTime()+0.50
      end
    end
  end
end
'''
text = text[:start] + new_update + text[end:]

old_render_line = '''      table.insert(out,string.format("    RadiusSrc=%s/%s depth=%d  target=%d,%d  entry=%s  Visual=%s x%.3f%s",tostring(h.radiusSourceNow or h.radiusSource),tostring(h.radiusSource),h.depth or 0,h.targetA or 0,h.targetB or 0,tostring(h.entry or "?"),ShortModel(h.visualPath or (h.visual and h.visual.path)),h.visualScale or 0,h.visualError and ("  ERR="..h.visualError) or ""))
'''
new_render_line = '''      table.insert(out,string.format("    RadiusSrc=%s/%s depth=%d target=%d,%d effect=%d#%d score=%d entry=%s D=%s Visual=%s x%.3f%s",tostring(h.radiusSourceNow or h.radiusSource),tostring(h.radiusSource),h.depth or 0,h.targetA or 0,h.targetB or 0,h.effect or 0,h.effectIndex or 0,h.geometryScore or 0,tostring(h.entry or "?"),tostring(h.dynamicGuid or "-"),ShortModel(h.visualPath or (h.visual and h.visual.path)),h.visualScale or 0,h.visualError and ("  ERR="..h.visualError) or ""))
'''
if old_render_line not in text:
    raise SystemExit("render detail marker missing")
text = text.replace(old_render_line, new_render_line, 1)

old_assign = '''    h.targetA=r.targetA; h.targetB=r.targetB; h.radiusIndex=r.radiusIndex; h.spellArchive=r.spellArchive; h.radiusArchive=r.radiusArchive; h.durationArchive=r.durationArchive
'''
new_assign = '''    h.targetA=r.targetA; h.targetB=r.targetB; h.radiusIndex=r.radiusIndex; h.spellArchive=r.spellArchive; h.radiusArchive=r.radiusArchive; h.durationArchive=r.durationArchive
    h.effect=r.effect; h.effectIndex=r.effectIndex; h.geometryScore=r.geometryScore
'''
if old_assign not in text:
    raise SystemExit("resolved hazard assignment marker missing")
text = text.replace(old_assign, new_assign, 1)

old_clear = '''  hazards={}; order={}; Log("CLEAR_ALL "..tostring(reason or ""))
'''
new_clear = '''  hazards={}; order={}; dynamicMeta={}; Log("CLEAR_ALL "..tostring(reason or ""))
'''
if old_clear not in text:
    raise SystemExit("ClearAll marker missing")
text = text.replace(old_clear, new_clear, 1)

start = text.find('local function Poll()')
end = text.find('\nF:SetScript("OnEvent"', start)
if start < 0 or end < 0:
    raise SystemExit("Poll block marker missing")
new_poll = r'''local function Poll()
  if not running then Render(); return end
  local dynamics=DynamicSnapshot(); local now=GetTime(); local claimed={}; local remove={}; local i

  -- Pass 1: cast-derived hazards get first claim on matching DynamicObjects.
  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and not h.dynamicOnly then UpdateHazard(h,dynamics,claimed) end
  end

  -- If a previously orphaned DynamicObject is now claimed by its cast hazard,
  -- remove the orphan visual before the cast hazard continues owning the object.
  local guid,owner
  for guid,owner in pairs(claimed) do
    local orphanKey="D:"..guid
    if hazards[orphanKey] and orphanKey~=owner then RemoveHazard(orphanKey,"merged_into_cast") end
  end

  -- Every unclaimed DynamicObject is still a first-class exact hazard.  This
  -- covers missing UNIT_CASTEVENTs and server-triggered ground effects.
  SyncDynamicOnly(dynamics,claimed)

  -- Pass 2: update Dynamic-only hazards by GUID and refresh their visuals.
  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and h.dynamicOnly then UpdateHazard(h,dynamics,claimed) end
  end

  now=GetTime()
  for i=1,table.getn(order) do
    local key=order[i]; local h=hazards[key]
    if h and now>(h.expires or now) and (not h.lastDynamic or now-h.lastDynamic>0.35) then table.insert(remove,key) end
  end
  for i=1,table.getn(remove) do RemoveHazard(remove[i],"expired") end
  Render()
end
'''
text = text[:start] + new_poll + text[end:]

# Lua 5.0/1.12 multi-return compatibility: gsub returns (string,count), and the
# count must NOT leak into tonumber's optional base argument.
old_resolve_cmd = 'elseif string.find(msg,"^resolve%s+") then local id=tonumber(string.gsub(msg,"^resolve%s+","")); if id then local r,e=Resolve(id); Chat(r and r.raw or tostring(e)) else Chat("用法 /arange resolve 24018") end'
new_resolve_cmd = 'elseif string.find(msg,"^resolve%s+") then local raw=string.gsub(msg,"^resolve%s+",""); local id=tonumber(raw); if id then local r,e=Resolve(id); Chat(r and r.raw or tostring(e)) else Chat("用法 /arange resolve 24018") end'
if old_resolve_cmd in text:
    text = text.replace(old_resolve_cmd, new_resolve_cmd, 1)

old_ztol_cmd = 'elseif string.find(msg,"^ztol%s+") then local n=tonumber(string.gsub(msg,"^ztol%s+","")); if n and n>=0 and n<=30 then zTol=n; AutoRangeDB.zTol=n; Chat("Z容差="..n) else Chat("用法 /arange ztol 4") end'
new_ztol_cmd = 'elseif string.find(msg,"^ztol%s+") then local raw=string.gsub(msg,"^ztol%s+",""); local n=tonumber(raw); if n and n>=0 and n<=30 then zTol=n; AutoRangeDB.zTol=n; Chat("Z容差="..n) else Chat("用法 /arange ztol 4") end'
if old_ztol_cmd in text:
    text = text.replace(old_ztol_cmd, new_ztol_cmd, 1)

path.write_text(text, encoding="utf-8", newline="\n")
final=path.read_text(encoding="utf-8")
for needle in ("AutoRange B3.2", "dynamicMeta", "DYNAMICOBJECT", "NewDynamicHazard", "merged_into_cast", "geometryScore"):
    if needle not in final:
        raise SystemExit(f"postcondition missing: {needle}")
print("AutoRange B3.2 Lua DynamicObject takeover/orphan handling: OK")
