# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M53-006 — M4.3 搜索历史新布局尚未真机验收

Severity: `MEDIUM`  
Status: `FIXED IN SOURCE / CI+BINARY+ARTIFACT VERIFIED / DEVICE VERIFICATION PENDING`

用户真机确认 M5.3 的 M4.3 方法查找页仍看不到搜索历史。根因不是历史保存缺失，而是旧 HistoryFix 使用 `maxY(contentView)` 放置历史卡片；`contentView` 同时包含 footer/其他更靠下视图，导致历史被追加到 Finder 可视区域之后。当前修复固定按 M4.3 几何插入：主搜索卡 `y=9 / h=170`，历史卡从 `y=187` 开始，原状态卡及后续主内容整体下移。需要真机确认历史卡实际可见且无重叠。

## KI-M53-007 — 历史点击已改为仅回填，尚未真机验收

Severity: `MEDIUM`  
Status: `IMPLEMENTED / CI+BINARY+ARTIFACT VERIFIED / DEVICE VERIFICATION PENDING`

历史行点击不再自动触发搜索。当前行为：更新 Finder query model，同时写入可见方法名输入框（field tag `603001`），然后等待用户手动点 `搜索`。需要真机确认点击一行后输入框立即显示对应关键词且页面不自动跳到结果页。

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

普通 Static Dispatch V3 的设计目标是运行期只改 RW `selectedTarget`，不改 executable page。M5.3 Number/Slider V1 为了让已生成 ON variant 的 MOVZ/MOVK 跟随客户数值，会通过 `ZNRuntimePatchExecutor` 对生成的 ON instruction page 做 expected-byte 校验后 RX→RW 写入、read-back、恢复保护。某些非越狱/签名环境可能禁止该操作；此时应 fail closed。若目标部署环境禁止，后续应改成 Static Dynamic V2：构建期参数化 stub + RW value cell。

## KI-M53-004 — Static Slider 当前 UI 范围仍是旧默认 0..10

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

M5.3 绑定了现有 Slider 值，但尚未增加 Builder 侧 min/max/step 的 Static 专用配置。应在动态后端真机可用后再扩展范围/步长元数据。

## KI-M53-005 — Static Button 为“启用固定 Enabled”语义

Severity: `LOW`  
Status: `BY DESIGN V1`

点击 Static Button 当前等价于启用对应固定 Enabled variant，不会自动 OFF。若未来需要 momentary/pulse，应独立定义控制模式。

## KI-M52-001 — M5.2 Immediate Chain V2 真机链路仍有开放问题

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

用户已真机确认 `执行链` 按钮可见并进入 M5.2 执行器；一次执行在 Level 1 前停止：`previous managed return is null`。仍需区分 Root `yo::wB()/0` 真实返回 null 与 Chain 路径 receiver/return 继承丢失。

## KI-M52-009 — Suffixless generated binary 缺真实生成物完整验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

真实 `UnityFramework` Builder 输出、替回 IPA、签名、安装、冷启动仍需设备证据。

## Legacy open validation gaps

- Enum member-name dropdown 尚未实现。
- Chain V2 typed per-node rows、任意 Level-N object arg、ref/out、复杂 ValueType 仍未实现。
- M5.0 managed object lifetime / class compatibility 在不同 Unity/IL2CPP 版本仍需设备证据。
- Protection V1/V2 真实 staging -> final IPA 冷启动证据仍未自动关闭。
