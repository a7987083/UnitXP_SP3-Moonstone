# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M582-001 — Runtime 重复卡片已做显示层折叠，真机待验收

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

M5.8.1 真机截图出现同名 `set_MoveSpeed` / `CheatSetExp` 重复卡片。M5.8.2 没有新增第二套 UI，而是在唯一的 `ZNM58UnifiedControlRuntime` 中按 `title + canonicalIdentity` 折叠重复显示，优先保留 exposed controls 更完整的 record。不同 title 的同方法 action 不会被合并。需真机确认没有误合并业务上不同的功能。

## KI-M582-002 — Runtime 固定参数 action 执行入口待真机验收

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

`argumentCount > 0` 但所有 control config 均未 exposed 的 action 在 M5.8.1 不显示 `执行`。M5.8.2 对 `exposed == 0` 强制显示 `执行`；需真机确认固定参数值按生成表执行且无额外 UI 层。

## KI-M582-003 — Runtime Slider 当前值显示与拖动稳定性待真机验收

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

M5.8.2 的 `ZNRangeControl` 在 tracking 中发送 `UIControlEventValueChanged`，Runtime renderer 仅用于量化和更新同一 row 的数值 label，不执行 IL2CPP Invoke；release 仍使用 `UIControlEventPrimaryActionTriggered` 单次执行。需真机确认持续拖动不卡死、label 与实际执行值一致、release 只执行一次。

## KI-M582-004 — Runtime-only 客户值持久化待重启验收

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

M5.5.1 `zonoe.m5.5.authoring-actions.v1` 只覆盖 Builder 的 `ZNRuntimeActionStore`，不能覆盖从生成 dylib `__ZNDATA` 解析出的 Runtime records。M5.8.2 新增独立运行时值 key `zonoe.m5.8.2.runtime-values.v1`，按 `actionID + canonicalIdentity` 保存 argumentValues。需真机验证 Slider/Number/Switch 提交后重启 App 能恢复。

## KI-M58-002 — Static Slider 旧拖动热路径修复仍待真机

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY FIXED / DEVICE PENDING`

Static typed controls 仍需使用 M5.8+ 重新生成目标验证 Slider drag/release 和 Number Execute。

## KI-M58-003 — Builder renderer 仍有多层包装

Severity: `HIGH`  
Status: `PHASE 2 OPEN`

Builder 仍存在 `ZNRuntimeMethodCallBuilderUI -> M5.1 argument decorator -> M5.5 authoring/gate decorator` 历史链。下一阶段必须做 consolidation，禁止继续增加新的 renderer/swizzle 层。

## KI-M58-004 — Method Finder 历史 installer 尚未物理清理

Severity: `HIGH`  
Status: `PHASE 2 OPEN`

M5.4 Unified renderer 已存在，但历史 backend/behavior decorator 仍需逐层审计和清理；必须保持现有行为回归通过后才能删除。

## KI-M56-004 — Value Cell LDR literal ±1MB 距离限制

Severity: `MEDIUM`  
Status: `FAIL-CLOSED BY DESIGN`

ARM64 LDR literal 使用 imm19*4。Builder 若 source fragment 到 owned `__ZNDATA` cell 超出 ±1MB，会生成失败，不回退到 executable-page runtime write。

## KI-M52-001 — Immediate Chain V2 Level 0 返回问题仍开放

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

此前一次 `执行链` 在 Level 1 前停止：`previous managed return is null`。仍需区分 Root 方法真实返回 null 与 receiver/return propagation 问题。
