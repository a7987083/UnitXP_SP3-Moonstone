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

封板前应整理专用接口/协议，减少 category dependency declaration 技术债。M4.4.1 首轮 CI 因新 translation unit 缺少 V3 Search category 可见声明而失败，进一步证明此项应在封板前整理。

## KI-011 — Feature-branch Actions 历史 startup_failure

Severity: `LOW`  
Status: `WORKAROUND / MONITOR`

M4–M4.5 专用 workflow 已能正常创建 runner 并实际编译；若再出现 startup failure，应与产品编译错误分开判断。

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

## KI-018 — M4.2/M4.4.1 `/1` typed invoke 尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

基础支持：bool、signed/unsigned 32/64、float、double、primitive-backed enum、`System.String`。M4.4.1 追加 exact `Vector2/Vector3/Quaternion/Color`。仍需真机验证输入值 -> 测试执行 -> 创建方法 -> Builder 保存 -> 再执行。

## KI-019 — instance 方法原“完全不支持”限制已被 M4.3/M4.4 部分解除

Severity: `HIGH`  
Status: `SUPERSEDED / PARTIALLY RESOLVED`

M4.3 liveness 可枚举 Class 活实例；恰好 1 个可作为 `this`。M4.4 多候选可显式选择，并在当前进程 session 内复用。

## KI-020 — `/2+`、自定义 struct 与普通 object reference 仍不执行

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION / FAIL CLOSED`

仍 fail closed：`/2+`、custom complex struct/value type、普通 managed object reference（System.String 除外）、ref/out、pointer、未知 ABI / 不安全 generic path。

## KI-021 — arity filter 只代表当前候选集

Severity: `LOW`  
Status: `BY DESIGN / UI DISCLOSURE`

`[全部][0][1]...` 只基于当前已返回候选。如果结果被 max-count/time budget 截断，不代表全游戏完整 arity 统计。

## KI-022 — M4.3 liveness Instance Resolver 尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

不同 Unity 导出情况、GC 时序、对象生命周期只能通过真机证明。

## KI-023 — M4.4 多实例选择尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

预期：1 个候选自动选择；多个候选弹 `选择实例`；session reuse；使用前 Class 验证；stale selection 清除。

## KI-024 — 当前 instance selection 是 Class 级、session-only

Severity: `MEDIUM`  
Status: `BY DESIGN / NEXT RESOLUTION PROBLEM`

同一 Class 多方法共享选择；重启后必须重新解析/选择。必要时后续加入候选字段描述或 receiver capture。

## KI-025 — receiver/`this` capture fallback 尚未实现

Severity: `HIGH`  
Status: `PLANNED / NOT IMPLEMENTED`

当 liveness 为 0 或多个对象无法人工区分时，理想 fallback 是临时观察 native method 的真实调用并捕获 ARM64 `x0`。当前仓库没有成熟 arbitrary-address hook backend，不要手写固定长度 trampoline。

## KI-026 — M4.4 session object validation 极端 stale-pointer 窗口

Severity: `MEDIUM`  
Status: `HARDENING CANDIDATE`

Class API 前可进一步评估 readable mapped-region probe。

## KI-027 — M4.3/M4.4 搜索与实例 UI 尚未完整验收

Severity: `MEDIUM`  
Status: `DEVICE VERIFICATION PENDING`

Assembly picker、自定义 max result、result card 去重、`/1` 布局、Details cleanup、instance picker 仍需真机回归。

## KI-028 — Search 路由差异与 M4.4.1 回归

Severity: `HIGH`  
Status: `M4.4.2 FIX IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

用户实机先发现页面 Search 可用、键盘 Search 不可用；M4.4.1 将两边统一后，两边都可能提示找不到 IL2CPP 方法。根因是 M4.3 selector swap 使页面按钮实际使用旧 V3，而 M4.4.1 绕开了该真机可用路径。M4.4.2 将两种触发重新委托给 post-swap `znm43_startSearch:`（原始 V3 implementation）。必须用同一历史查询真机复测后才能关闭。

## KI-029 — Finder 地址输入规范化待真机验证

Severity: `MEDIUM`  
Status: `M4.5 EXTENDED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

接受 `38064A8 / 0x38064A8 / rva:38064A8 / rva:0x38064A8 / va:0x...`。M4.5 不再仅要求地址等于方法入口，还支持方法内部 ARM64 instruction RVA -> owning method。

## KI-030 — Patch Offset 自动 `0x` 规范化待真机验证

Severity: `LOW`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

输入裸 HEX 后按 `完成` 应显示/保存为 `0x...`，随后继续原 Validator/Builder 链。

## KI-031 — Common Unity struct `/1` 仅覆盖四种已知 layout

Severity: `MEDIUM`  
Status: `LIMITED SUPPORT / DEVICE VERIFICATION PENDING`

仅 exact `Vector2/Vector3/Quaternion/Color`。Matrix、Bounds、Ray、Nullable、自定义 struct 等仍需 metadata/layout 驱动方案。

## KI-032 — Assembly-CSharp 视觉默认不能等同严格过滤

Severity: `HIGH`  
Status: `M4.4.2 FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

未手工点选 Assembly 时应全局搜索、Assembly-CSharp first；只有明确点选某 Assembly 后才严格 scoped search。当前只完成源码/CI/Binary Verify，待真机确认。

## KI-033 — M4.5 Interior Owning Method 依赖完整上界扫描

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M4.5 对方法内部 instruction 的归属规则是 `methodStart <= targetRVA < nextKnownMethodStart`。为了避免“最近前一方法”误判，如果 live IL2CPP 方法扫描达到 6 秒预算，或找不到 `nextKnownMethodStart`，interior lookup 会 fail closed。大型游戏上可能需要后续做可缓存的排序 Method Index。

## KI-034 — Shared/generic native code 会产生多 MethodInfo 候选

Severity: `MEDIUM`  
Status: `BY DESIGN / NEEDS DEVICE OBSERVATION`

IL2CPP generic sharing 等情况可能让多个 MethodInfo 共用同一个 native code pointer。M4.5 不猜测，返回同一 methodStart 的多个候选。后续 Full Method Signature milestone 应把参数/返回类型纳入 identity，降低歧义。

## KI-035 — Unsupported `/1` 灰色输入框改为 reason label 待真机验收

Severity: `LOW`  
Status: `M4.5 FIX IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M4.4.1 仅把 reason 放进 disabled UITextField placeholder，所以仍显示灰色输入框。M4.5 会移除该 disabled field 并显示正常颜色的 `类型 · 原因` label；Test/Create 继续禁用，不假装可执行。
