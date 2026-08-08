# GroundProbe B1 — TRUE 8×8 DynamicObject 坐标探针

目的：只验证 Turtle WoW / WoW 1.12.1 客户端里，Boss/怪物的地面技能是否生成可读取的 DynamicObject / GameObject，以及是否能得到真实世界坐标。

## 本版不会做的事

- 不会自动提示“离开”。
- 不会修改 MoonMarker 8×8 光柱的放置、同步、槽位或模型逻辑。
- 不会写入或删除游戏世界对象。

## Native 新接口

- `UnitXP("GroundProbe.Status")`
- `UnitXP("GroundProbe.Snapshot", range, includeGameObjects)`

Snapshot 包含：

- 玩家 XYZ；
- DynamicObject：GUID、Caster GUID、SpellID、Radius、XYZ、XY 距离、Z 高差；
- GameObject：GUID、Entry、XYZ、XY 距离、Z 高差；
- 扫描数量。

DynamicObject 字段使用 WoW 1.12.1 build 5875 UpdateFields：SpellID=0x009、Radius=0x00A、XYZ=0x00B/0x00C/0x00D。

## 安装

1. 完全退出游戏。
2. 备份当前已经确认正常的 TRUE 8×8 `UnitXP_SP3.dll`。
3. 用测试包中的 `UnitXP_SP3.dll` 替换当前 DLL。
4. 把 `Interface/AddOns/GroundProbe` 放进游戏对应目录。
5. SuperWoW 使用 2.2，并同步更新其 SuperAPI。
6. 原来的 `MoonMarker` 和 `DreamAvatar` 插件不要删除；本包不替换它们。

## 实机测试

进入游戏：

`/gprobe status`

应看到 DLL 状态 READY。然后：

`/gprobe start`

探针窗口会显示玩家 XYZ、DynamicObject 数量、GameObject 数量。

测试重点：找一个会在地面留下黑水、火圈、毒圈等持续区域的怪/Boss。在技能出现前后观察：

1. `Dynamic` 是否从 0 变为 1 或更多；
2. 是否出现 `D spell=xxxx r=x.xx dist=x.xx xyz=...`；
3. 走向技能圈时 `dist` 是否连续下降；走开时是否连续上升；
4. 地面效果消失时，聊天是否出现 `GONE D ...`；
5. 如果 SuperWoW `UNIT_CASTEVENT` 正常，`NEW D` 后面是否出现 `<= CAST spell=...` 关联。

测试完：

`/gprobe export`

如果 SuperWoW 的 `ExportFile()` 可用，会导出 `GroundProbe.txt`。也可以使用：

`/gprobe dump`

把最近日志输出到聊天窗口。

其他命令：

- `/gprobe stop`
- `/gprobe show`
- `/gprobe hide`
- `/gprobe clear`
- `/gprobe range 120`
- `/gprobe go`（切换是否同时扫描 GameObject）

## 通过标准

只要某个真实地面技能出现时能稳定得到：

`SpellID + Radius + Ground XYZ`

并且玩家移动时与该 XYZ 的距离变化正确，B 方案的核心就验证通过。下一版即可增加：

`XY距离 <= Radius && Z高差 <= 容差 -> 立即提示离开`
