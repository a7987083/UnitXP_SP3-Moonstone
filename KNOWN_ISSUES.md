# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M58-001 — Runtime Slider 历史卡死：M5.8 已物理去重，真机待验收

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY CLEANUP COMPLETE / DEVICE PENDING`

M5.7 真机仍在未点执行、仅拖动 Slider 时卡死。M5.8 审计确认历史上 Runtime Slider 经历 M5.1/M5.5/M5.3/M5.5.1/M5.6.2/M5.7 多代 ownership；此外 M5.7 ValueChanged 仍会反写 slider.value 并在事件派发中动态 addTarget。M5.8 改由 `ZNM58UnifiedControlRuntime` 自己创建客户 Runtime 控件；Slider 的 ValueChanged handler 为零副作用，release target 在控件创建时一次性绑定。相关 legacy owner 已从 Makefile 物理移除。需要真机确认拖动不再卡死/闪退。

## KI-M58-002 — Static Slider 旧拖动热路径过重

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

旧 `ZNFeatureRuntimeControlsV2` 在每次 ValueChanged 中调用 `ZN65FeatureGroups()`，继而触发 `ZNStaticDispatchRuntime refresh`、遍历 records、写 NSUserDefaults 并反写 slider.value。M5.8 已将 ValueChanged 改成 no-op；所有量化/持久化/notification/backend commit 移到 release。需使用 M5.8-regenerated target 真机验证。

## KI-M58-003 — Builder renderer 仍有多层包装

Severity: `HIGH`  
Status: `PHASE 2 OPEN`

M5.8 Phase 1 已把 standalone Runtime-only gate 合并进 M5.5 authoring decorator，但 Builder 仍存在 `ZNRuntimeMethodCallBuilderUI -> M5.1 argument decorator -> M5.5 typed/gate decorator` 的历史 renderer 链。下一阶段应重构成一个 Builder renderer + backend data model，而不是继续增加 swizzle。

## KI-M58-004 — Method Finder 历史 installer 尚未物理清理

Severity: `HIGH`  
Status: `PHASE 2 OPEN`

M5.4 Unified renderer 已真机可见，但总安装链仍保留 M4.3/M4.3 Polish/M4.4.x/M4.5/M4.6/M4.7 等历史层，其中部分为必要 backend/behavior decorator，部分 UI 已 superseded。M5.8 Phase 2 需逐一拆分 backend 与 renderer，删除不再需要的 UI ownership；在此之前不得宣称 Method Finder 架构已完全清理。

## KI-M58-005 — Static Number/Slider 验收必须重新生成目标

Severity: `HIGH`  
Status: `EXPECTED MIGRATION BOUNDARY`

Static typed backend继续使用 `ZNF1 -> RW Value Cell -> RVA Protection -> Sign`。旧 M5.5/M5.6.x 生成物不能用于判断 M5.8 Static Slider/Number 行为。必须用 M5.8 Builder 重新生成目标后测试 Number Execute、Slider release 和 Auto->F32。

## KI-M58-006 — Runtime-only 最终 UI 成功状态仍待真机

Severity: `MEDIUM`  
Status: `SOURCE/CI FIXED / DEVICE PENDING`

Runtime-only suffixless verifier 已按 Mach-O 内容识别，Builder gate 已合并进 M5.5 authoring decorator。仍需真机确认在没有完整 Offset+Enabled 行时生成按钮可用且最终 UI 不再“文件已生成但提示失败”。

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
