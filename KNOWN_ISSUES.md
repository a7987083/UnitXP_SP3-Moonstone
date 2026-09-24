# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M551-001 — 旧 Runtime authoring 条目在 M5.5.1 前未持久化

Severity: `HIGH`  
Status: `ROOT CAUSE FIXED FOR FUTURE DATA / HISTORICAL LOSS NOT AUTO-RECOVERABLE`

历史 `ZNRuntimeActionStore` 仅使用进程内 `NSMutableArray`。换 dylib、杀进程、重启会丢失制作页 Runtime Method Call authoring 条目。M5.5.1 新增 `zonoe.m5.5.authoring-actions.v1` 持久化并在 Store 为空时启动恢复。已经在修复前丢失、且没有旧序列化源/日志/生成 action table 的条目无法可靠自动复原。

## KI-M551-002 — M5.5.1 Builder 恢复仍待真机确认

Severity: `HIGH`  
Status: `SOURCE / CI / BINARY / ARTIFACT VERIFIED / DEVICE PENDING`

M5.5.1 已恢复 M5.4 Builder 基础布局，并把 Runtime Method Call `删除` 移到标题行右上，参数区下移并增加卡片间距。需要真机确认原 Builder 内容重新出现、控件不重叠、滚动高度正确。

## KI-M551-003 — Static Value Type authoring UI 暂缓重新叠加

Severity: `MEDIUM`  
Status: `INTENTIONAL RECOVERY BOUNDARY`

为避免再次破坏制作页基线，M5.5.1 先恢复 M5.4 Builder 几何。Static typed backend 仍保留，但 Static Value Type 的制作页入口应在恢复版真机接受后以非破坏性 overlay/long-press 方式重新加入，不再把原三列布局直接替换成四列。

## KI-M55-002 — Static F32/F64 仅支持可精确编码的 scalar FMOV immediate

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL-CLOSED`

scalar `FMOV S,#imm` / `FMOV D,#imm` 只接受可精确编码值，不做近似。当前默认整数 Slider `1..10 / step 1` 属于可精确表示的常用范围。

## KI-M55-003 — Static 大整数依赖 MOVK 槽位

Severity: `MEDIUM`  
Status: `BY DESIGN / FAIL-CLOSED`

I32/U32/I64/U64 使用原 Enabled ON variant 内已有 `MOVZ(+MOVK)` 槽位。缺少所需 halfword 槽位时拒绝执行，不覆盖未知后续指令。

## KI-M55-005 — Static dynamic 仍涉及 executable-page runtime write

Severity: `HIGH`  
Status: `ARCHITECTURAL LIMIT / DEVICE VERIFICATION REQUIRED`

typed adapter 仍通过 transactional RX→RW 写入生成 ON variant。受限设备/签名模型可能拒绝；若真实环境阻止，应迁移 build-time parameterized stub + RW value cell。

## KI-M54-003 — Unified Search History 交互仍待真机验收

Severity: `MEDIUM`  
Status: `VISIBLE ON DEVICE / INTERACTION PENDING`

Unified/search-history 已真机可见；点击历史仅回填、不自动搜索、持久化/去重/50 条淘汰仍需完整验收。

## KI-M54-004 — Unified Results 行为装饰器需完整回归

Severity: `HIGH`  
Status: `DEVICE REGRESSION PENDING`

需继续验证 `/0-/8`、candidate binding、Test/捕获、receiver long-press、创建方法和 Chain 状态机。

## KI-M52-001 — Immediate Chain V2 Level 0 返回问题仍开放

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

此前一次 `执行链` 在 Level 1 前停止：`previous managed return is null`。仍需区分 Root 方法真实返回 null 与 receiver/return propagation 问题。
