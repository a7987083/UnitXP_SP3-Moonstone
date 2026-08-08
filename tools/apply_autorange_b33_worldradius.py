#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else "autorange-addon/AutoRange.lua")
if not path.is_file():
    raise SystemExit(f"missing {path}")
text = path.read_text(encoding="utf-8")

# This patch runs after B3.2 Lua generation.  Skill radius always stays in
# world yards.  The visual model's nominal diameter is derived from its
# authoritative patch-O filename (DangerZone_W{diameter}_...).
text = text.replace("-- AutoRange B3.2 - Turtle WoW 1.12", "-- AutoRange B3.3 - Turtle WoW 1.12", 1)
text = text.replace("AutoRange B3.2  ·  Caster + DynamicObject 自动范围", "AutoRange B3.3  ·  WorldRadius 游戏码数渲染", 1)

old_pool = '''local visualPool = {\n  {path="Spells\\\\DangerZone_W10_S30.m2",        base=10, tag="标准"},\n  {path="Spells\\\\DangerZone_W10_S30_White.m2",  base=10, tag="白色"},\n  {path="Spells\\\\DangerZone_W10_S30_Flame.m2",  base=10, tag="火焰"},\n  {path="Spells\\\\DangerZone_W12_S30_Jagged.m2", base=12, tag="锯齿"},\n  {path="Spells\\\\DangerZone_W12_S30_JaggedG.m2",base=12, tag="绿色锯齿"},\n}\n'''
# Also accept the B3.2 source form without the B3.2a explanatory comment.
if old_pool not in text:
    start = text.find('local visualPool = {')
    end = text.find('\n}\n', start)
    if start < 0 or end < 0:
        raise SystemExit("visualPool block missing")
    end += 3
    pool = '''local visualPool = {\n  {path="Spells\\\\DangerZone_W10_S30.m2",         tag="标准"},\n  {path="Spells\\\\DangerZone_W10_S30_White.m2",   tag="白色"},\n  {path="Spells\\\\DangerZone_W10_S30_Flame.m2",   tag="火焰"},\n  {path="Spells\\\\DangerZone_W12_S30_Jagged.m2",  tag="锯齿"},\n  {path="Spells\\\\DangerZone_W12_S30_JaggedG.m2", tag="绿色锯齿"},\n}\n'''
    text = text[:start] + pool + text[end:]
else:
    pool = '''local visualPool = {\n  {path="Spells\\\\DangerZone_W10_S30.m2",         tag="标准"},\n  {path="Spells\\\\DangerZone_W10_S30_White.m2",   tag="白色"},\n  {path="Spells\\\\DangerZone_W10_S30_Flame.m2",   tag="火焰"},\n  {path="Spells\\\\DangerZone_W12_S30_Jagged.m2",  tag="锯齿"},\n  {path="Spells\\\\DangerZone_W12_S30_JaggedG.m2", tag="绿色锯齿"},\n}\n'''
    text = text.replace(old_pool, pool, 1)

marker = 'local function HashChoice(h)\n'
if marker not in text:
    raise SystemExit("HashChoice marker missing")
helpers = r'''local function ModelDiameterYards(path)
  -- patch-O's create_zone.py names models W{diameter}; W10 means a 10-yard
  -- quad diameter.  Derive it from the filename so there is no per-skill or
  -- per-model numeric table to maintain.
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

'''
text = text.replace(marker, helpers + marker, 1)

# PickVisual must not precompute a scale using a stored base.
old_pick = '''local function PickVisual(h)\n  if h.visual then return h.visual end\n  h.visual=HashChoice(h)\n  h.visualScale=h.radius>0 and (h.radius/h.visual.base) or 1\n  return h.visual\nend\n'''
if old_pick not in text:
    old_pick = '''local function PickVisual(h)\n  if h.visual then return h.visual end\n  h.visual=HashChoice(h)\n  h.visualScale=h.radius>0 and ((h.radius*2)/h.visual.base) or 1\n  return h.visual\nend\n'''
new_pick = '''local function PickVisual(h)\n  if h.visual then return h.visual end\n  h.visual=HashChoice(h)\n  return h.visual\nend\n'''
if old_pick not in text:
    raise SystemExit("PickVisual block missing")
text = text.replace(old_pick, new_pick, 1)

# Replace SetVisual's old base arithmetic with a single WorldRadius conversion.
old_scale = '''  local v=PickVisual(h)\n  local scale=h.radius/v.base\n  h.visualScale=scale\n  if scale<0.10 or scale>5.00 then h.visualError="SCALE_OUT_OF_RANGE"; return end\n'''
if old_scale not in text:
    old_scale = '''  local v=PickVisual(h)\n  local scale=(h.radius*2)/v.base\n  h.visualScale=scale\n  if scale<0.10 or scale>5.00 then h.visualError="SCALE_OUT_OF_RANGE"; return end\n'''
new_scale = '''  local v=PickVisual(h)\n  local scale,modelDiameter,targetDiameter,scaleErr=WorldRadiusScale(h.radius,v.path)\n  h.visualScale=scale or 0\n  h.modelDiameter=modelDiameter\n  h.targetDiameter=targetDiameter\n  if not scale then h.visualError=scaleErr or "WORLD_RADIUS_SCALE_FAIL"; return end\n  if scale<0.05 or scale>20.00 then h.visualError="SCALE_OUT_OF_RANGE"; return end\n'''
if old_scale not in text:
    raise SystemExit("SetVisual scale block missing")
text = text.replace(old_scale, new_scale, 1)

# Make the UI prove what the renderer used: game radius -> target diameter -> model W -> scale.
old_detail = 'tostring(h.dynamicGuid or "-"),ShortModel(h.visualPath or (h.visual and h.visual.path)),h.visualScale or 0,h.visualError and ("  ERR="..h.visualError) or ""))'
new_detail = 'tostring(h.dynamicGuid or "-"),ShortModel(h.visualPath or (h.visual and h.visual.path)),h.visualScale or 0,("  WorldR="..string.format("%.2f",h.radius or 0).." TargetD="..string.format("%.2f",h.targetDiameter or 0).." ModelW="..tostring(h.modelDiameter or "?"))..(h.visualError and ("  ERR="..h.visualError) or "")))'
if old_detail not in text:
    raise SystemExit("render detail suffix missing")
text = text.replace(old_detail, new_detail, 1)

# Upgrade /arange vtest to accept a world radius; default remains 5 yards.
start = text.find('  elseif msg=="vtest" then')
if start < 0:
    raise SystemExit("vtest block missing")
end = text.find('  elseif msg=="vclear" then', start)
if end < 0:
    raise SystemExit("vclear marker missing")
new_vtest = r'''  elseif msg=="vtest" or string.find(msg,"^vtest%s+") then
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
'''
text = text[:start] + new_vtest + text[end:]

text = text.replace('/arange start|stop|show|hide|status|clear|visual on|off|vtest|vclear|hostile on|off|resolve 24018|ztol 4|export',
                    '/arange start|stop|show|hide|status|clear|visual on|off|vtest [半径]|vclear|hostile on|off|resolve 24018|ztol 4|export')

path.write_text(text, encoding="utf-8", newline="\n")
final = path.read_text(encoding="utf-8")
for needle in ("AutoRange B3.3", "ModelDiameterYards", "WorldRadiusScale", "TargetD=", "ModelW=", "vtest [半径]"):
    if needle not in final:
        raise SystemExit(f"postcondition missing: {needle}")
if "base=" in final:
    raise SystemExit("legacy visual base hardcoding remains")
print("AutoRange B3.3 WorldRadius renderer: OK")
