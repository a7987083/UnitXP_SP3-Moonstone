# GroundProbe B2 Hybrid 测试说明

目标：把两类危险区域放在同一个探针里判断。

- **D / DynamicObject**：真实地面对象，直接读取 SpellID、Radius、XYZ。
- **C / Caster**：以施法者为中心，SuperWoW `UNIT_CASTEVENT` 提供 casterGUID，UnitXP 根据 GUID 找到敌对单位并实时读取 XYZ。
- **去重规则**：同一 SpellID + 同一 caster 若已经出现 DynamicObject，则 D 优先，C 显示为 `[C→D]` 并停止重复判断。
- **Z 高度容差**：默认 4 码，可 `/gprobe z 4` 调整，避免楼上/楼下误判。

## 利斧乱舞 24018

B2 预置：

- SpellID: `24018`
- 模式：Caster
- 持续时间：10 秒
- 半径：**10 码 TEST 临时值，仅用于本次校准，不代表已确认真实半径**

可以随时改：

```text
/gprobe caster 24018 10 10
```

格式：`/gprobe caster 技能ID 半径 持续秒`

测试时请重点观察：

```text
[C] 利斧乱舞 spell=24018 r=10.00*TEST dist=... zD=... OUT/INSIDE entry=...
```

确认三件事：

1. 巨魔开始利斧乱舞时是否出现 `[C]`。
2. 巨魔移动时 `[C] xyz=` 是否跟着移动。
3. 玩家靠近/远离时 `dist=` 是否连续变化，进入测试半径后是否变成 `INSIDE`。

如果真实受伤边界不是 10 码，可站在边界附近用 `dist=` 校准，再告诉我实际数据。

## DynamicObject 测试

找一个真实持续地面技能。出现时应看到：

```text
[D] spell=xxxxx r=5.00 dist=... zD=... OUT/INSIDE xyz=...
```

这里的 `r=` 来自客户端 DynamicObject descriptor，不是手工测试值。

## 命令

```text
/gprobe start
/gprobe stop
/gprobe status
/gprobe show
/gprobe hide
/gprobe export
/gprobe dump
/gprobe clear
/gprobe range 120
/gprobe z 4
/gprobe go
/gprobe skills
/gprobe caster 24018 10 10
/gprobe casteroff 24018
```

导出文件：`imports/GroundProbe-B2.txt`

## 安全范围

B2 仍为只读诊断版：

- 不自动移动；
- 不自动施法；
- 不修改目标；
- 不修改 8x8 光柱状态；
- 只读取对象、位置、GUID，并在 Lua 中计算距离。

出现崩溃或异常时，退出游戏并恢复测试包中的 TRUE 8x8 回滚 DLL。