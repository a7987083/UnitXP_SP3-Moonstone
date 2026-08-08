#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else "autorange-addon/AutoRange.lua")
if not path.is_file():
    raise SystemExit(f"missing {path}")
text = path.read_text(encoding="utf-8")

text = text.replace("-- AutoRange B3 - Turtle WoW 1.12", "-- AutoRange B3.1 - Turtle WoW 1.12", 1)
text = text.replace("AutoRange B3  ·  自动技能范围 + patch-O 随机视觉", "AutoRange B3.1  ·  自动技能范围 + patch-O 随机视觉", 1)

needle = '  elseif msg=="status" then panel:Show(); AutoRangeDB.hidden=false; if type(UnitXP)=="function" then local ok,s=pcall(UnitXP,"AutoRange.Status"); dbcStatus=(ok and s) or "STATUS_FAIL" end; Chat("DBC="..tostring(dbcStatus).." running="..tostring(running).." visual="..tostring(visualEnabled)); Render()\n'
if needle not in text:
    raise SystemExit("status command marker missing")
insert = '''  elseif msg=="vtest" then
    panel:Show(); AutoRangeDB.hidden=false
    if type(UnitXP)~="function" then Chat("vtest失败：没有UnitXP")
    elseif type(CursorPosition)~="function" then Chat("vtest失败：没有CursorPosition()，确认SuperWoW 2.2 + SuperAPI")
    else
      local ok,x,y,z=pcall(CursorPosition)
      if not ok or not x or not y or not z then Chat("vtest失败：鼠标世界坐标不可用")
      else
        local v=visualPool[1]
        pcall(UnitXP,"AutoRange.VisualClear","__VTEST__")
        local ok2,created,normalized,stage=pcall(UnitXP,"AutoRange.VisualSet","__VTEST__",v.path,x,y,z+0.03,0.5,0)
        if ok2 and created then Chat("vtest成功：鼠标位置创建5码测试圈 "..tostring(normalized or v.path))
        else Chat("vtest失败："..tostring(stage or normalized or created or "CREATE_FAIL")) end
      end
    end
  elseif msg=="vclear" then
    if type(UnitXP)=="function" then pcall(UnitXP,"AutoRange.VisualClear","__VTEST__") end
    Chat("vtest测试圈已清除")
'''
text = text.replace(needle, insert + needle, 1)

old_help = 'else Chat("/arange start|stop|show|hide|status|clear|visual on|off|hostile on|off|resolve 24018|ztol 4|export") end'
new_help = 'else Chat("/arange start|stop|show|hide|status|clear|visual on|off|vtest|vclear|hostile on|off|resolve 24018|ztol 4|export") end'
if old_help not in text:
    raise SystemExit("help marker missing")
text = text.replace(old_help, new_help, 1)

path.write_text(text, encoding="utf-8", newline="\n")
for n in ("AutoRange B3.1", 'msg=="vtest"', 'AutoRange.VisualSet","__VTEST__'):
    if n not in text:
        raise SystemExit(f"postcondition missing: {n}")
print("AutoRange B3.1 Lua visual self-test patch: OK")
