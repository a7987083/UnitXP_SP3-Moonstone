# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M52-001 — M5.2 Immediate Chain V2 尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY+ARTIFACT VERIFIED / DEVICE VERIFICATION PENDING`

M5.2 已实现 version=2 多级原子链、每级 `/0-/8` typed args、exact signature、token/return-type guard、System.String decode、逐级 trace/log，并复用 M5.0 managed-reference GCHandle/receiver injection。需要真机证明真实对象生命周期、跨 3+ level receiver 连续性和目标 Unity/IL2CPP 版本导出兼容性。

## KI-M52-002 — Customer Silent Execution 尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

客户侧成功 Runtime / Button / Immediate Chain 执行应完全静默；失败仍弹 `执行失败`；Builder / Method Finder 测试执行保留返回值与调试信息。CI 证明代码已编译进二进制，但仍需要设备 UI 证据。

## KI-M52-003 — System.String decode 依赖目标 IL2CPP exports

Severity: `MEDIUM`  
Status: `BEST-EFFORT / DEVICE VERIFICATION PENDING`

M5.2 使用 `il2cpp_string_length` + `il2cpp_string_chars` 将最终 managed `System.String` 从 UTF-16 解为 NSString。若目标构建没有导出这些 API，当前会保留原 Return Capture 表示而不是伪造字符串结果。需要目标游戏实测。

## KI-M52-004 — Enum 已 typed，但名称/值下拉 UI 未实现

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

ABI metadata 已能通过 `il2cpp_class_is_enum` / `il2cpp_class_enum_basetype` 得到 underlying primitive，Chain V2 可按数值传参；Builder 尚未自动枚举 `K` 等 enum 的成员名和值。当前需要填写数值，例如 `0` / `1`。

## KI-M52-005 — Chain V2 参数编辑器当前为 CSV

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

当前每个链节点用 `Parameter Types` 与 `Args` 两个英文逗号分隔输入框。普通 primitive/enum 当前够用，但参数字符串本身含逗号时不适合。后续应改成按 argc 自动展开的逐参数 typed rows，并复用 M5.1 控件作者界面。

## KI-M52-006 — 任意 Level 返回对象作为参数尚未实现

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

当前链语义是“上一层 managed return 自动成为下一层 receiver”。尚不支持 `arg[n] = Level 0 return`、`arg[n] = Level 2 return`、captured runtime object 等对象参数来源。

## KI-M52-007 — ref/out / pointer / 通用 ObjectReference / 复杂 ValueType 仍受 ABI 安全边界限制

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL CLOSED`

M5.2 没有绕过已有安全检查。普通 object reference（String 之外）、ref/out、pointer、部分 custom ValueType、generic/shared generic 不会因为进入 Chain V2 就被强行调用。需要以后基于 metadata-driven marshaling 单独实现和验证。

## KI-M52-008 — Token / return-type guard 为“可用时”校验

Severity: `MEDIUM`  
Status: `BY DESIGN`

节点始终先按完整参数签名 exact-resolve。若 `il2cpp_method_get_token` / return-type exports 可用，则额外比较持久化 token / return type。MethodInfo* / MethodPointer 只用于当前进程日志，不作为持久化 identity，以避免 ASLR 导致跨启动地址失效。

## KI-M52-009 — Suffixless generated binary 缺真实生成物验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

Runtime-only 最终输出和 Static 后处理仍按 M5.1 规则导出原 Mach-O 文件名；Static 内部可使用 `.znpatched` staging。真实 `UnityFramework` Builder 输出、替回 IPA、签名、安装、冷启动仍需设备证据。

## Legacy open validation gaps

- M5.1 per-argument Switch/Button/Number/Slider 仍缺完整真机矩阵验证。
- M5.0 managed object lifetime / class compatibility 在不同 Unity/IL2CPP 版本仍需设备证据。
- Protection V1/V2 的真实 staging -> final IPA 冷启动证据仍未自动关闭。
- M4.4/M4.5 Instance Resolver、地址归属、搜索回归等历史设备验证缺口仍存在。
