# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M51-001 — Per-argument Runtime Controls 尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M5.1 已实现开发者逐参数 `☐/☑`，并复用 `开关 / 按钮 / 数值 / 滑块` 四类客户控件。需要真机证明：只暴露勾选参数、固定参数不变、最终 invoke vector 正确。

## KI-M51-002 — Immediate Chain V1 尚未真机验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

链式调用按钮位于 `创建方法` 下方。主返回必须为 managed-reference；第二跳当前仅 `/0`。实现依赖 M5.0 managed return capture + class-compatible receiver injection，需要真机验证对象生命周期、兼容性和实际第二跳结果。

## KI-M51-003 — Immediate Chain 第二跳当前只支持 argc=0

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

后续需要为第二跳加入 exact parameter signature、typed argument values 和 per-argument control authoring，不能简单复用 legacy `Method/N` 猜测重载。

## KI-M51-004 — Slider 范围配置 UI 未实现

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

当前 Slider 元数据结构已有 `min/max/step`，但 Builder 尚无编辑 UI；默认 `0 / 100 / 1`。不要把默认值描述成开发者已可配置。

## KI-M51-005 — Suffixless generated binary 缺真实生成物验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

Runtime-only Builder 已直接输出原始 Mach-O 文件名；Static Builder 保持 `.znpatched` 内部 staging，完成保护/签名后最终重命名为原始文件名。CI 已检查源码契约并编译通过，但没有真实 UnityFramework fixture 执行 Builder，所以不能宣称最终生成物已真机验证。

## KI-M51-006 — M5.0/M5.1 managed object lifetime 仍需设备证据

Severity: `HIGH`  
Status: `DEVICE VERIFICATION PENDING`

M5.0 使用 IL2CPP GCHandle 保活 managed-reference，并在第二次实例调用前验证 class compatibility；M5.1 Immediate Chain 复用此路径。不同 Unity/IL2CPP 版本的 GC 行为仍需实机确认。

## KI-M51-007 — 复杂参数仍受 ABI 安全边界限制

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL CLOSED`

Per-argument UI 不等于 ABI 已支持全部参数类型。普通 object reference、ref/out、pointer、复杂自定义 ValueType、部分 generic/shared generic 仍应按现有 ABI 校验 fail closed，不能仅因为选了 Number/Switch 就强行执行。

## Legacy open validation gaps

- Protection V1 / V2 仍需要真实 `.znpatched` staging → final IPA 冷启动证据；M5.1 只是把最终导出名改为 suffixless。
- M4.4/M4.5 Instance Resolver、地址归属、搜索回归等历史设备验证缺口仍未因 M5.1 自动关闭。
- Generated binary 最终替回 IPA 后仍需要正常整包签名/安装/冷启动验证。
