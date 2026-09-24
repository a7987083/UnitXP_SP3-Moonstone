# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M57-001 — Runtime Slider 多 owner / 双 UI 已在 M5.7 收敛，真机待验收

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

审计确认历史上同时存在多层 Runtime Slider handler（M5.1/M5.3/M5.5/M5.5.1/M5.6.2）以及独立 Static Feature Slider `ValueChanged` 通知路径；同时旧 `ZNRuntimeMethodCallFeatureUI` 和 M5.1 typed Runtime cards 构成两套客户 Runtime UI。M5.7 停止安装 M5.3/M5.5.1/M5.6.2 control owner 和旧 Runtime Feature UI，最终 Runtime 事件只由 `ZNM57UnifiedRuntimeControls` 拥有。需要真机确认拖动不再卡死/闪退且 release 只执行一次。

## KI-M57-002 — Number 统一为 Return 收键盘、手动 Execute

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

Runtime 与 Static/Offset Number 均已改为输入只更新值；Return/Done 保存并 `resignFirstResponder`，不得因此执行。Runtime 使用卡片 `执行`；Static/Offset Number 使用 inline `执行`。需真机确认 Return 确实收起键盘且功能在 Execute 前不生效。

## KI-M57-003 — Runtime-only 实际生成但 UI 报失败

Severity: `HIGH`  
Status: `ROOT CAUSE FIXED / DEVICE PENDING`

Runtime-only 从 M5.1 起保持原始 Mach-O 文件名，无 `.znpatched` 后缀；旧 `ZNM462RuntimeOnlyVerifier` 仍只扫描 `.znpatched`，导致 Mach-O 实际生成成功后 verifier 返回“没有输出”。M5.7 改为按 thin Mach-O magic/内容识别 suffixless 输出。同时新增 Runtime-only Builder gate，使 Runtime Actions + 0 完整 Static 行时无需普通 Offset 即可启用生成。需真机确认最终 UI 报告成功。

## KI-M57-004 — Static Number/Slider RW Value Cell 仍需当前版本重生成后真机验收

Severity: `HIGH`  
Status: `CI/BINARY VERIFIED / DEVICE PENDING`

Static typed backend 保持 `ZNF1 -> RW Value Cell -> RVA Protection -> Sign`。Number 只在 inline Execute 提交；Slider 只在 release 提交。旧 M5.5/M5.6.1 generated target 不是有效测试对象，必须使用当前 Builder 重生成。

## KI-M57-005 — Static Auto->F32 历史 value=0 问题待 M5.7 重生成验证

Severity: `HIGH`  
Status: `PATH FIXED / DEVICE PENDING`

此前 Auto->F32 UI/metadata 与最终 backend 不一致，客户端数值始终表现为 0。当前路径要求 FMOV build-time parameterization -> LDR S/D -> F32/F64 RW cell，且只有 M5.6 value-cell binder 是 Static typed backend owner。需用 M5.7 重生成目标并测试 1/5/10。

## KI-M56-004 — Value Cell LDR literal ±1MB 距离限制

Severity: `MEDIUM`  
Status: `FAIL-CLOSED BY DESIGN`

ARM64 LDR literal 使用 imm19*4。Builder 若 source fragment 到 owned `__ZNDATA` cell 超出 ±1MB，会生成失败，不回退到 executable-page runtime write。

## KI-M551-001 — M5.5.1 前 Runtime authoring 历史丢失不可自动恢复

Severity: `MEDIUM`  
Status: `FUTURE LOSS FIXED / HISTORICAL LOSS NOT AUTO-RECOVERABLE`

M5.5.1 起使用 `zonoe.m5.5.authoring-actions.v1` 持久化；修复前已经丢失且无序列化源/日志/action table 的条目无法可靠恢复。

## KI-M54-003 — Unified Search History 完整交互验收未完成

Severity: `MEDIUM`  
Status: `VISIBLE ON DEVICE / INTERACTION PENDING`

Unified/search-history 已真机可见；历史点击仅回填、手动搜索、持久化/去重/50 条淘汰仍需完整验收。

## KI-M54-004 — Unified Results 行为装饰器需完整回归

Severity: `HIGH`  
Status: `DEVICE REGRESSION PENDING`

需继续验证 `/0-/8`、candidate binding、Test/捕获、receiver long-press、创建方法和 Chain 状态机。

## KI-M52-001 — Immediate Chain V2 Level 0 返回问题仍开放

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

此前一次 `执行链` 在 Level 1 前停止：`previous managed return is null`。仍需区分 Root 方法真实返回 null 与 receiver/return propagation 问题。
