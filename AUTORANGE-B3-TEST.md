# AutoRange B3 自动范围 + patch-O 随机视觉测试

## 目标
- 不手填半径；从当前客户端 MPQ 的 `Spell.dbc / SpellRadius.dbc / SpellDuration.dbc` 自动解析。
- 若父技能本身没有半径，会递归追 `EffectTriggerSpell`（最多 4 层）。
- DynamicObject 一旦出现，优先采用它自己的真实 XYZ + Radius。
- Caster 型技能使用 SuperWoW 的 casterGUID + UnitXP 可见对象坐标。
- 每个新危险技能随机选一种 patch-O 圆圈 M2，并按 `真实半径 / 素材基础半径` 缩放。

## 安装
1. 完全退出游戏。
2. 备份当前 `UnitXP_SP3.dll`，再换成本包的 DLL。
3. 将 `Interface/AddOns/AutoRange` 复制到游戏对应目录。
4. 保留当前 `patch-O.mpq`（twow-raid-visuals）以及 SuperWoWhook.dll 2.2 + 对应 SuperAPI。
5. 进入游戏。AutoRange 默认自动运行并显示独立窗口。

## 第一验收：祖尔格拉布 24018 利斧乱舞
不需要执行任何 `/arange caster ...` 配置。

先执行：
- `/arange status`
- `/arange resolve 24018`

目标：resolve 输出应自动得到 `R=5`（来源应是 TRIGGER，而不是手工表）。

怪物施放 24018 时，窗口应看到：
- Spell=24018
- Geometry=<触发子技能ID>
- Radius=5.00
- RadiusSrc=TRIGGER
- Mode=CASTER
- dist 随玩家/怪物移动实时变化
- 5码内 INSIDE，5码外 OUT
- 怪脚下出现 patch-O 随机危险圈，技能结束后消失

## 命令
- `/arange start` / `/arange stop`
- `/arange show` / `/arange hide`
- `/arange status`
- `/arange visual on` / `/arange visual off`
- `/arange hostile on` / `/arange hostile off`
- `/arange resolve 24018`
- `/arange ztol 4`
- `/arange clear`
- `/arange export`

## 当前边界
B3 第一版只自动画“圆形范围”。若 DBC 判断为 CONE（锥形/扇形），窗口会标记 CONE_UNSUPPORTED，不会故意用圆圈冒充。直线、环形、服务器脚本特殊判定也可能需要后续单独几何类型。
