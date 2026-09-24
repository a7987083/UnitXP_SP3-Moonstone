# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M52-001 — M5.2 Immediate Chain V2 尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY+ARTIFACT VERIFIED / DEVICE VERIFICATION PENDING`

多级原子链、typed args、exact signature、GCHandle receiver、System.String decode、逐级 trace 已完成；真实对象生命周期和目标 Unity/IL2CPP 兼容性仍需真机证据。

## KI-M52-010 — 完成链后的 `执行链` 状态机尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

旧 M5.2 的 `完成链` 仅保存 metadata 并 render，没有可见执行入口。现已新增 Finder 原位状态机：无链时 `链式调用`，存在已保存 V2 chain 时显示 `执行链`；单击执行整条链；长按清空旧链并立即重新进入链式调用。需要真机验证按钮状态、tap target、long-press gesture 与页面重绘链路。

## KI-M52-011 — 方法搜索历史尚未真机验收

Severity: `MEDIUM`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

方法搜索关键词已通过 NSUserDefaults 持久化，并在搜索框下方显示独立滚动列表：一行一个、最多 50 条、最新置顶、大小写不敏感去重、点击重搜。需要真机验证布局、滚动、重启持久化以及第 51 条淘汰最旧记录。

## KI-M52-012 — Finder 已保存链匹配根身份尚未使用完整参数类型

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

`执行链` 按钮当前用 root Assembly + Namespace + Class + Method + argc 查找最近保存的 V2 action。Chain 节点真正执行仍使用完整参数签名 exact-resolve，但如果根方法存在“同名 + 同 argc”的多个重载，Finder 按钮可能需要进一步用 root parameterTypeNames 消歧。设备测试时应覆盖同 argc 重载场景。

## KI-M52-013 — 搜索历史面板位置依赖当前 V3 搜索页几何

Severity: `LOW`  
Status: `KNOWN MAINTENANCE COUPLING`

历史面板插入在当前 V3 搜索卡与搜索选项卡之间，并移动后续视图。如果未来重构 Method Finder Search 页固定几何，需要同步复核插入位置。

## KI-M52-002 — Customer Silent Execution 尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

客户侧成功 Runtime / Button / Immediate Chain 执行应静默；失败仍显示 `执行失败`；Builder / Method Finder 测试执行保留返回与调试信息。

## KI-M52-003 — System.String decode 依赖目标 IL2CPP exports

Severity: `MEDIUM`  
Status: `BEST-EFFORT / DEVICE VERIFICATION PENDING`

依赖 `il2cpp_string_length` + `il2cpp_string_chars`；若目标没有对应 exports，保持原 Return Capture 表示而不是伪造字符串。

## KI-M52-004 — Enum 名称/值下拉 UI 未实现

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

enum 已按 underlying primitive typed invoke；当前仍需要填写数值。

## KI-M52-005 — Chain V2 参数编辑器当前为 CSV

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

后续应改成按 argc 自动展开的逐参数 typed rows。

## KI-M52-006 — 任意 Level 返回对象作为参数尚未实现

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

当前上一层 managed return 自动成为下一层 receiver；尚不支持 `arg[n] = Level N return`。

## KI-M52-007 — ref/out / pointer / 通用 ObjectReference / 复杂 ValueType 仍 fail closed

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL CLOSED`

需要后续基于 metadata-driven marshaling 单独实现和验证。

## KI-M52-009 — Suffixless generated binary 缺真实生成物验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

真实 `UnityFramework` Builder 输出、替回 IPA、签名、安装、冷启动仍需设备证据。

## Legacy open validation gaps

- M5.1 per-argument Switch/Button/Number/Slider 仍缺完整真机矩阵验证。
- M5.0 managed object lifetime / class compatibility 在不同 Unity/IL2CPP 版本仍需设备证据。
- Protection V1/V2 真实 staging -> final IPA 冷启动证据仍未自动关闭。
