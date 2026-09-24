# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M55-001 — Typed Control Binding V2 尚未真机验收

Severity: `HIGH`  
Status: `SOURCE / CI / BINARY / ARTIFACT VERIFIED / DEVICE PENDING`

M5.5 已实现统一 Value Type：`Auto/I32/U32/I64/U64/F32/F64`，Runtime 与 Static 共用同一公共类型模型；arm64 构建、Binary Verify 和 Artifact 独立 hash 均通过。仍需真机验证 Builder 交互、Runtime invoke 和 Static 编码后端。

## KI-M55-002 — Static F32/F64 仅支持可精确编码的 scalar FMOV immediate

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL-CLOSED`

M5.5 可识别 scalar `FMOV S,#imm` 与 `FMOV D,#imm` 并分别绑定 F32/F64，但不会近似任意 float/double。目标值若不在 scalar FMOV immediate 可表达集合中，直接 `执行失败`，不会盲改。当前 Slider 默认 `1..10 / step 1`；这些整数属于可精确表示的常用范围。

## KI-M55-003 — Static 大整数依赖 MOVK 槽位

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL-CLOSED`

I32/U32/I64/U64 使用已生成 Protection V2 ON variant 内的 `MOVZ(+MOVK)` 序列。若目标值需要某个 16-bit halfword，但原 Enabled 序列没有对应 MOVK 槽位，则拒绝执行。不会自行覆盖后续 RET/其他指令来“凑”常量。

## KI-M55-004 — Static 自定义 Range 尚未进入生成物 metadata

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

Runtime 已支持 Default/Min/Max/Step 编辑和 JSON 导出；Static 目前只持久化 Control Type + Value Type。Static Slider 采用固定产品默认 `1..10 / step 1`，Number 使用 Value Type 默认范围。若需要每个 Static Feature 自定义 Range，应增加 owned metadata extension/table，而不是随意扩大或破坏 128-byte Static Entry ABI。

## KI-M55-005 — Static dynamic 仍涉及 executable-page runtime write

Severity: `HIGH`  
Status: `ARCHITECTURAL LIMIT / DEVICE VERIFICATION REQUIRED`

M5.5 typed adapter 仍通过 `ZNRuntimePatchExecutor` 修改生成的 ON variant 指令，并使用 expected-byte/read-back/rollback。某些签名/设备模型可能禁止 RX→RW executable-page mutation；此时必须 fail closed。若真实目标环境阻止，应迁移到 build-time parameterized stub + RW value cell。

## KI-M55-006 — Runtime 手工 Value Type 不改变真实 IL2CPP 方法 ABI

Severity: `MEDIUM`  
Status: `SEMANTIC BOUNDARY`

Runtime Action 的真实调用 ABI 仍来自方法签名。`Auto` 是推荐路径；手工选择 I32/U32/I64/U64/F32/F64 目前负责客户值校验/范围语义，并不会把 `System.Int32` 方法参数重新解释成 `System.Single`。真机验收时应优先使用 Auto 或与方法签名一致的显式类型。

## KI-M54-002 — 旧 Method Finder UI 源码仍在编译

Severity: `MEDIUM`  
Status: `INTENTIONAL TRANSITION BOUNDARY`

M5.4 已切断旧 base renderer 最终 UI 路径，但若干历史 installer 同时混有 backend/action 行为，所以旧源文件仍部分编译。M5.4/M5.5 完整回归后再拆 mixed installer 并物理删除 obsolete renderer。

## KI-M54-003 — Unified Search History 交互仍待真机验收

Severity: `MEDIUM`  
Status: `VISIBLE ON DEVICE / INTERACTION PENDING`

用户已确认 Unified/search-history UI 真机可见。仍需验证：点击历史仅回填方法名、不自动搜索；手动搜索；重启持久化；去重；最大 50 条。

## KI-M54-004 — Unified Results 行为装饰器需完整回归

Severity: `HIGH`  
Status: `DEVICE REGRESSION PENDING`

需继续验证 `/0-/8`、candidate binding、Test/捕获、receiver long-press、创建方法、链按钮状态机。

## KI-M52-001 — Immediate Chain V2 Level 0 返回问题仍开放

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

此前一次 `执行链` 在 Level 1 前停止：`previous managed return is null`。仍需区分 Root 方法真实返回 null 与 receiver/return propagation 问题。

## KI-M52-009 — Suffixless generated binary 缺完整真机验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

真实 UnityFramework Builder 输出、替回 IPA、签名、安装、冷启动仍需完整设备证据。
