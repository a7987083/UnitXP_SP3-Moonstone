# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M562-001 — Static executable-page writer regression was still active after initial M5.6

Severity: `HIGH`  
Status: `SOURCE/CI FIXED IN M5.6.2 / DEVICE PENDING`

真机仍返回 `写入完成但恢复 RX 权限失败: errno=13 (Permission denied)`。后续审计确认当前分支的 `M5.6.1-regression` 安装链又恢复了 M5.3 executable-page typed writer，并停用了 M5.6 value-cell runtime owner/postprocess。M5.6.2 已恢复 `ZNF1 -> RW Value Cell -> RVA Protection -> Sign`，并显式移除 M5.3/M5.5 Static observers。必须重新生成目标二进制后真机验收。

## KI-M562-002 — Runtime Slider drag crash requires UI-vs-Invoke isolation

Severity: `HIGH`  
Status: `M5.6.2 ISOLATION BUILD READY / DEVICE PENDING`

前一版即使减少 refresh，真机仍报告拖动卡死/闪退。M5.6.2 不再自动执行 Slider：最终 `ValueChanged` 只修改 UISlider 值，不 refresh/render/invoke/add release target。客户必须点 Runtime 卡片 `执行` 才调用。如果纯拖动仍崩，问题在 UI/selector 之外；如果拖动稳定但点执行崩，问题在 Runtime Invoke/receiver/F32 ABI 路径。

## KI-M562-003 — Static Auto->F32 client value stuck at 0

Severity: `HIGH`  
Status: `ROOT CAUSE PATH FIXED IN SOURCE/CI / DEVICE PENDING`

用户新增 Static Number 后 Auto 解析为 F32，但客户端无论修改什么值都表现为 0。审计确认此前 UI/metadata 能显示 F32，但最终 runtime owner 并未使用 value-cell F32 后端。M5.6.2 由 build-time FMOV -> LDR S/D value-cell 参数化写入 resolved type flags，并由 `ZNM56StaticValueCellBinder` 按 F32/F64 bit pattern atomic store RW cell。必须重新生成目标二进制验证。

## KI-M562-004 — Runtime-only builder mode could be polluted by partial Static rows

Severity: `HIGH`  
Status: `SOURCE/CI FIXED / DEVICE PENDING`

旧 mode gate 使用 `workspace.filledCount`；只要 Offset 或 Enabled 任一字段残留就计入 Static。M5.6.2 改为完整行判断：仅 `Offset && Enabled` 同时存在才算 Static intent；partial rows 被记录但不阻止 Runtime-only。

## KI-M562-005 — M5.6.2 Static tests require regenerated targets

Severity: `HIGH`  
Status: `EXPECTED MIGRATION BOUNDARY`

旧 M5.5/M5.6.1 生成物可能仍包含 executable-immediate variants，不能用来判断 M5.6.2 RW Value Cell 是否有效。Static Number/Slider/F32 验收必须由 M5.6.2 Builder 重新生成并替换回 IPA。

## KI-M56-004 — Value Cell LDR literal has ±1MB range limit

Severity: `MEDIUM`  
Status: `FAIL-CLOSED BY DESIGN`

ARM64 LDR literal 使用 imm19*4。Builder 若 source fragment 到 owned `__ZNDATA` cell 超出 ±1MB，会生成失败；不会回退到 runtime executable write。

## KI-M551-001 — Pre-M5.5.1 Runtime authoring historical loss

Severity: `MEDIUM`  
Status: `FUTURE LOSS FIXED / HISTORICAL LOSS NOT AUTO-RECOVERABLE`

M5.5.1 起使用 `zonoe.m5.5.authoring-actions.v1` 持久化。修复前已丢失且没有序列化源/日志/action table 的条目无法可靠恢复。

## KI-M551-002 — Builder Recovery full device regression pending

Severity: `MEDIUM`  
Status: `CI VERIFIED / DEVICE REGRESSION PENDING`

继续确认 M5.4 Builder 基线、删除按钮间距、Runtime authoring 重启恢复在 M5.6.2 无回归。

## KI-M54-003 — Unified Search History interaction acceptance incomplete

Severity: `MEDIUM`  
Status: `VISIBLE ON DEVICE / INTERACTION PENDING`

Unified/search-history 已真机可见；历史点击仅回填、手动搜索、持久化/去重/50 条淘汰仍需完整验收。

## KI-M54-004 — Unified Results decorators need full regression

Severity: `HIGH`  
Status: `DEVICE REGRESSION PENDING`

需继续验证 `/0-/8`、candidate binding、Test/捕获、receiver long-press、创建方法和 Chain 状态机。

## KI-M52-001 — Immediate Chain V2 Level 0 return investigation

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

此前一次 `执行链` 在 Level 1 前停止：`previous managed return is null`。仍需区分 Root 方法真实返回 null 与 receiver/return propagation 问题。
