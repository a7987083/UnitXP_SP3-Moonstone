# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — Protection V1 尚未真实 `.znpatched` / 最终 IPA 验证

Severity: `HIGH`  
Status: `OPEN`

CI 已确认 codec / build / binary verify，但仍缺真实目标 `.znpatched + build_report.json + 冷启动` 证据。

## KI-002 — FeatureID 仍是可推导 ID

Severity: `MEDIUM`  
Status: `OPEN / HARDENING`

当前 FeatureID 仍可由 normalized display name 推导；后续可评估随机稳定 authoring identity。

## KI-003 — Patch payload / Variant 尚未进入 Protection V2

Severity: `HIGH`  
Status: `OPEN / HARDENING`

RVA 字段已增加静态恢复成本，但 relocated Original / ON Variant 仍可被进一步分析。

## KI-004 — Protection 是分析成本层，不是客户端秘密

Severity: `MEDIUM`  
Status: `BY DESIGN`

Runtime 最终必须恢复真实地址；公开客户端不能保证地址不可恢复。

## KI-005 — Generated binary 后处理仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`  
Status: `OPEN / KNOWN LIMITATION`

未来 FAT/universal 需要按 slice 解析。

## KI-006 — Feature 状态恢复时机仍需真实多 Feature 验证

Severity: `MEDIUM`  
Status: `OPEN / BEHAVIOR TO VALIDATE`

Shared Site、多 Feature 同时恢复、失败回滚仍缺完整实机回归。

## KI-007 — Generated binary ad-hoc 重签不能替代最终 IPA 签名

Severity: `MEDIUM`  
Status: `OPEN / RELEASE REQUIREMENT`

最终仍需整包重签、安装、冷启动验证。

## KI-008 — Method Finder indexed lookup 仍包含 live re-resolution 成本

Severity: `LOW`  
Status: `MEASURED / OPTIONAL OPTIMIZATION`

旧设备观测：首次约 `423.1 ms`，后续约 `147–150 ms`。

## KI-009 — Method Finder 索引缓存缺少主动垃圾回收

Severity: `LOW`  
Status: `OPEN / CLEANUP`

fingerprint 防止错误复用，但旧缓存暂不主动删除。

## KI-010 — 部分 Objective-C bridge declaration 仍依赖 warning suppression

Severity: `LOW`  
Status: `OPEN / PRE-SEAL CLEANUP`

封板前应整理专用接口/协议，减少 category dependency declaration 技术债。

## KI-011 — Feature-branch Actions 历史 startup_failure

Severity: `LOW`  
Status: `WORKAROUND / MONITOR`

M4–M4.4 专用 workflow 已能正常创建 runner 并实际编译；若再出现 startup failure，应与产品编译错误分开判断。

## KI-012 — M2 Cancel UX 缺少单独视觉验收

Severity: `LOW`  
Status: `LEGACY VALIDATION GAP`

不影响当前 M4.x 主线，但未获得单独 UI 证据。

## KI-013 — M4.1 菜单触摸穿透尚未真机验证

Severity: `HIGH`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

必须验证：panel 外可操作游戏、panel 内控件正常、Translate 第二次打开不闪退、悬浮球流程不回归。

## KI-014 — M4.1 自动二进制 / App Libraries 尚未真机验证

Severity: `MEDIUM`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

UnityFramework 优先、非 Unity fallback、简单模块名显示以及逻辑 identity 解析都需要真机确认。

## KI-015 — M4.1 direct-build auto preflight 尚未真机验证

Severity: `MEDIUM`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

用户不需先手工点 `读取验证`，但 Original/长度/RVA-file mapping/Mach-O/relocation 等安全检查仍在内部执行。

## KI-016 — Runtime Method Call 自定义 title 尚未真机验证

Severity: `MEDIUM`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

需确认生成后显示名改变而 canonical identity / methodName / 调用目标不变。

## KI-017 — M4.1 同页滚动位置保持尚未真机验证

Severity: `LOW`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

需要覆盖增加/删除 Patch、Runtime Action 改名/参数编辑等 renderPage 重建场景。

## KI-018 — M4.2 `/1` typed invoke 尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

支持 bool、signed/unsigned 32/64、float、double、primitive-backed enum、`System.String`。至少需一个副作用明确且安全的 `/1` 方法验证输入值 -> 测试执行 -> 预期效果 -> 无异常。

## KI-019 — instance 方法原“完全不支持”限制已被 M4.3/M4.4 部分解除

Severity: `HIGH`  
Status: `SUPERSEDED / PARTIALLY RESOLVED`

M4.2 的 `FAILED_INSTANCE_REQUIRED` 限制已经不是当前完整状态：

- M4.3 能通过 IL2CPP liveness 枚举 Class 活实例；
- 恰好 1 个候选时可自动作为 `this`；
- M4.4 对多个候选提供显式 instance picker，并在当前进程 session 内复用选择。

仍未解决的部分转入 KI-022 / KI-023 / KI-024。

## KI-020 — `/2+` 与复杂参数仍只显示/筛选，不执行

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION / FAIL CLOSED`

当前 Runtime Invoke 仍只支持 `/0`、`/1`。ref/out、pointer、普通 object reference、complex struct/value type、generic definition 仍 fail closed。

Vector2/Vector3/Quaternion 即使是 `/1` 也属于一个复杂 struct 参数，不能把它误当成多个独立 float。

## KI-021 — arity filter 只代表当前候选集

Severity: `LOW`  
Status: `BY DESIGN / UI DISCLOSURE`

`[全部][0][1]...` 只基于当前搜索已经返回的候选。如果结果被 max-count 或 time budget 截断，它不是全游戏完整 arity 统计。

## KI-022 — M4.3 liveness Instance Resolver 尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

当前实现：

- legacy `il2cpp_unity_liveness_calculation_begin/from_statics/end` 优先；
- modern `allocate_struct/from_statics/finalize/free_struct` fallback；
- modern path 要求 `il2cpp_stop_gc_world/start_gc_world`；
- candidate 通过 `il2cpp_object_get_class` / `il2cpp_class_is_assignable_from` 二次验证。

风险：不同 Unity 版本导出情况、GC 时序以及真实游戏对象生命周期只能通过真机证明。

M4.3 final CI run `35750846250` success 只证明编译/二进制契约，不证明游戏运行时安全。

## KI-023 — M4.4 多实例选择尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M4.4 final CI run `35751669688` success；Artifact ID `10704773628`。

预期：

- 1 个候选 -> 自动选择；
- 多个候选 -> `选择实例` action sheet；
- 选择按 `assembly|namespace|class` 在当前进程复用；
- 使用前验证 Class；
- invalid/stale selection 清除，不继续 Runtime Invoke。

需要特别验证：同一 Class 存在本地玩家/远端玩家/预览对象等多个实例时，用户能否稳定选择正确对象。

## KI-024 — 当前 instance selection 是 Class 级、session-only，不等于“自动识别正确对象”

Severity: `MEDIUM`  
Status: `BY DESIGN / NEXT RESOLUTION PROBLEM`

M4.4 不保存 raw object pointer 到生成二进制；重启后必须重新解析/选择，这是正确的生命周期边界。

同时，Class 级 selection 意味着同一 Class 的多个方法共享选择。如果一个 Class 同时存在不同业务角色实例，单靠地址列表不能自动判断“哪个才是本地玩家”。必要时后续要加入更强的候选描述或 receiver capture。

## KI-025 — receiver/`this` capture fallback 尚未实现

Severity: `HIGH`  
Status: `PLANNED / NOT IMPLEMENTED`

当 liveness 返回 0 个或多个无法人工判断的实例时，理想 fallback 是临时观察目标 native method 的真实调用并捕获 ARM64 `x0` receiver，再验证其 IL2CPP Class。

当前仓库没有成熟的 arbitrary-address ARM64 inline-hook/instrumentation backend。不要手写固定长度 trampoline 去猜 PC-relative relocation。

若真机证明确有必要，应接入**固定版本、可审计、可卸载**的成熟 arm64/iOS instrumentation backend；capture 完成后立即 disable/destroy probe。

## KI-026 — M4.4 session object validation 在极端 stale-pointer 窗口仍需加强

Severity: `MEDIUM`  
Status: `HARDENING CANDIDATE`

当前已在 reuse 前调用 `il2cpp_object_get_class` + assignability 验证，但如果地址已经变成完全不可读的 unmapped/stale pointer，直接交给 IL2CPP object API 的防御性仍需真机评估。

后续可在 Class API 前增加 readable mapped-region 检查（例如 Mach VM region/readability probe），再进入 IL2CPP validation，进一步降低 stale-pointer crash 风险。

## KI-027 — M4.3/M4.4 搜索与实例 UI 新交互尚未完整验收

Severity: `MEDIUM`  
Status: `DEVICE VERIFICATION PENDING`

仍需确认：

- Assembly picker 与 `全部 Assembly`；
- max result 输入 64/128/256 等；
- selected Assembly 的 result card 不重复显示 `Assembly-CSharp`；
- all-Assembly result 保留 Assembly 区分；
- `/1` 输入框位于方法名下方；
- 键盘右下角 `完成` 能正确 dismiss；
- Details 不再出现重复 test/create 区。
