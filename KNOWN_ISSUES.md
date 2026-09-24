# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M56-001 — Static M5.5 executable-page typed update 已被真机否定

Severity: `HIGH`  
Status: `ROOT CAUSE CONFIRMED / ARCHITECTURE REPLACED / M5.6 DEVICE VALIDATION PENDING`

真机 Static Number/Auto 返回：`写入完成但恢复 RX 权限失败: errno=13 (Permission denied)`。因此旧 M5.5 运行时修改 ON variant executable page 的方案不再视为可接受路径。M5.6 已替换为 build-time LDR parameterization + owned `__ZNDATA` RW value cell；运行时只写数据页。需要重新生成目标二进制后真机验收。

## KI-M56-002 — Runtime Slider M5.5 拖动卡死/闪退

Severity: `HIGH`  
Status: `ROOT CAUSE FIXED IN SOURCE/CI / DEVICE VALIDATION PENDING`

M5.5 typed wrapper 在每次 Slider `ValueChanged` 中执行 `ZNRuntimeActionRuntime refresh`，拖动时高频触发。M5.6 将拖动热路径改回 cache-only，并在松手时只做一次 refresh + quantize + cache + invoke。需真机确认不再卡死/闪退且不会重复调用。

## KI-M56-003 — M5.6 Static value cell 需要重新生成目标二进制

Severity: `HIGH`  
Status: `EXPECTED MIGRATION BOUNDARY`

旧 M5.5 生成物的 ON variant 仍是 MOV/FMOV 指令，没有 LDR-to-cell 参数化。仅替换 M5.6 dylib 不会自动改造旧 UnityFramework。Static Number/Slider 验收必须使用 M5.6 Builder 重新生成并替回 IPA。

## KI-M56-004 — Value Cell LDR literal 有 ±1MB 距离约束

Severity: `MEDIUM`  
Status: `FAIL-CLOSED BY DESIGN`

ARM64 LDR literal 只有 imm19*4 距离。M5.6 Builder 如果 generated source fragment 到 owned `__ZNDATA` cell 超出 ±1MB，会直接生成失败，不回退到 runtime executable write。

## KI-M551-001 — 旧 Runtime authoring 条目在 M5.5.1 前未持久化

Severity: `MEDIUM`  
Status: `FUTURE LOSS FIXED / HISTORICAL LOSS NOT AUTO-RECOVERABLE`

M5.5.1 起通过 `zonoe.m5.5.authoring-actions.v1` 持久化。修复前已经丢失且没有旧序列化源/日志/action table 的条目无法可靠恢复。

## KI-M551-002 — Builder Recovery 仍需完整真机回归

Severity: `MEDIUM`  
Status: `CI VERIFIED / DEVICE REGRESSION PENDING`

需继续确认 M5.4 Builder 基线、删除按钮间距、Runtime authoring 重启恢复在 M5.6 没有回归。

## KI-M54-003 — Unified Search History 交互仍待完整验收

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
