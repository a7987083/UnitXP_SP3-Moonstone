# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M53-001 — Runtime 四控件自动执行尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY+ARTIFACT VERIFIED / DEVICE VERIFICATION PENDING`

M5.3 已把 Runtime 参数控件绑定到真实 invoke：Button 点击、Switch 改值、Number 编辑结束、Slider 松手均会执行当前 Runtime Action。成功继续静默，失败继续弹 `执行失败`。需要真机确认事件触发次数、键盘结束编辑路径、Slider TouchUp 以及 M5.1 Silent swizzle 顺序。

## KI-M53-002 — Static Number/Slider V1 仅支持 MOVZ(+MOVK) 整数常量

Severity: `HIGH`  
Status: `IMPLEMENTED / FAIL-CLOSED OUTSIDE SUPPORTED ENCODING / DEVICE VERIFICATION PENDING`

V1 只处理 Protection V2 ON variant 中首指令为 ARM64 MOVZ、后续为同宽度/同目标寄存器兼容 MOVK 的 Enabled 前缀。客户值按 imm16 halfword 写入。负数、浮点、FMOV、ADD/SUB immediate、ORR immediate、任意 raw bytes 等均不会猜测编码，会直接失败。

## KI-M53-003 — Static dynamic V1 重新引入 executable-page runtime write

Severity: `HIGH`  
Status: `ARCHITECTURAL LIMIT / DEVICE VERIFICATION REQUIRED`

普通 Static Dispatch V3 的设计目标是运行期只改 RW `selectedTarget`，不改 executable page。M5.3 Number/Slider V1 为了让已生成 ON variant 的 MOVZ/MOVK 立即跟随客户数值，会通过现有 `ZNRuntimePatchExecutor` 对生成的 ON instruction page 做 expected-byte 校验后 RX→RW 写入、read-back、恢复保护。某些非越狱/签名环境可能禁止该操作；此时应 fail closed。若目标部署环境确实禁止，后续必须改为 Static Dynamic V2：构建时生成参数化 stub + RW value cell，客户只写 RW 数据。

## KI-M53-004 — Static Slider 当前 UI 范围仍是旧默认 0..10

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

M5.3 绑定了现有 Slider 值，但尚未增加 Builder 侧 min/max/step 的 Static 专用配置。现有 Static slider UI 仍采用旧默认范围。后续应在确认动态后端可用于目标设备后，再持久化范围/步长元数据，避免先扩 ABI/UI 后发现运行模型不适用。

## KI-M53-005 — Static Button 语义为“启用固定 Enabled”，不是脉冲后自动恢复

Severity: `LOW`  
Status: `BY DESIGN V1`

点击 Static Button 当前等价于启用对应固定 Enabled variant，不会自动 OFF。若未来需要 momentary/pulse 语义，应作为独立控制模式定义，不能隐式定时恢复。

## KI-M52-001 — M5.2 Immediate Chain V2 真机链路仍有开放问题

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

用户已真机确认 `执行链` 按钮可见并进入 M5.2 执行器；一次执行在 Level 1 前停止：`previous managed return is null`。当前仍需区分 Root `yo::wB()/0` 真实返回 null 与 Chain 路径 receiver/return 继承丢失。System.String decode、多级 receiver 连续性仍未完整真机验收。

## KI-M52-011 — 方法搜索历史 HistoryFix 尚缺最终真机证据

Severity: `MEDIUM`  
Status: `SOURCE/CI/BINARY VERIFIED / DEVICE CONFIRMATION PENDING`

最初历史模块错误绑定 V3 selector，而当前设备实际显示 `IL2CPP 方法查找 · M4.3`。HistoryFix `88ee2768...` 已改为绑定 `znm43_renderSearchAtWidth:` / `znm43_startSearch:`，最多 50 条、持久化、独立滚动、一行一个。需要真机最终确认显示/点击/重启持久化。

## KI-M52-009 — Suffixless generated binary 缺真实生成物完整验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

真实 `UnityFramework` Builder 输出、替回 IPA、签名、安装、冷启动仍需设备证据。

## Legacy open validation gaps

- Enum member-name dropdown尚未实现。
- Chain V2 typed per-node rows、任意 Level-N object arg、ref/out、复杂 ValueType 仍未实现。
- M5.0 managed object lifetime / class compatibility 在不同 Unity/IL2CPP 版本仍需设备证据。
- Protection V1/V2 真实 staging -> final IPA 冷启动证据仍未自动关闭。
