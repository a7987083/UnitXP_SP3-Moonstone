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

M4–M4.4.2 专用 workflow 已能正常创建 runner 并实际编译；若再出现 startup failure，应与产品编译错误分开判断。

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

基础支持：bool、signed/unsigned 32/64、float、double、primitive-backed enum、`System.String`。

M4.4.1 追加四种 exact Unity value types：`Vector2`、`Vector3`、`Quaternion`、`Color`。这些路径目前只有源码/CI/二进制证据，至少需要安全副作用方法验证输入值 -> 测试执行 -> 预期效果 -> 创建方法 -> Builder 保存 -> 再执行。

## KI-019 — instance 方法原“完全不支持”限制已被 M4.3/M4.4 部分解除

Severity: `HIGH`  
Status: `SUPERSEDED / PARTIALLY RESOLVED`

- M4.3 能通过 IL2CPP liveness 枚举 Class 活实例；
- 恰好 1 个候选时可自动作为 `this`；
- M4.4 对多个候选提供显式 instance picker，并在当前进程 session 内复用选择。

仍未解决的部分转入 KI-022 / KI-023 / KI-024 / KI-025。

## KI-020 — `/2+`、自定义 struct 与普通 object reference 仍不执行

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION / FAIL CLOSED`

当前 Runtime Invoke 仍只支持 `/0`、`/1`。M4.4.1 已经显式支持 `/1` 的 `Vector2/Vector3/Quaternion/Color`，因此旧的“所有 complex struct 均不支持”描述已过时。

仍 fail closed：

- `/2+`；
- custom complex struct/value type；
- 普通 managed object reference（`System.String` 除外）；
- ref/out；
- pointer；
- 未识别 ABI / 不安全 generic path。

## KI-021 — arity filter 只代表当前候选集

Severity: `LOW`  
Status: `BY DESIGN / UI DISCLOSURE`

`[全部][0][1]...` 只基于当前搜索已经返回的候选。如果结果被 max-count 或 time budget 截断，它不是全游戏完整 arity 统计。

## KI-022 — M4.3 liveness Instance Resolver 尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

不同 Unity 版本导出情况、GC 时序以及真实游戏对象生命周期只能通过真机证明。M4.3 CI success 只证明编译/二进制契约，不证明游戏运行时安全。

## KI-023 — M4.4 多实例选择尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

预期：1 个候选自动选择；多个候选弹 `选择实例`；选择按 `assembly|namespace|class` 在当前进程复用；使用前验证 Class；invalid/stale selection 清除。

需要特别验证同一 Class 存在本地玩家/远端玩家/预览对象等多个实例时，用户能否稳定选择正确对象。

## KI-024 — 当前 instance selection 是 Class 级、session-only，不等于“自动识别正确对象”

Severity: `MEDIUM`  
Status: `BY DESIGN / NEXT RESOLUTION PROBLEM`

M4.4 不保存 raw object pointer 到生成二进制；重启后必须重新解析/选择。Class 级 selection 意味着同一 Class 的多个方法共享选择；必要时后续要加入更强的候选描述或 receiver capture。

## KI-025 — receiver/`this` capture fallback 尚未实现

Severity: `HIGH`  
Status: `PLANNED / NOT IMPLEMENTED`

当 liveness 返回 0 个或多个无法人工判断的实例时，理想 fallback 是临时观察目标 native method 的真实调用并捕获 ARM64 `x0` receiver，再验证其 IL2CPP Class。

当前仓库没有成熟的 arbitrary-address ARM64 inline-hook/instrumentation backend。不要手写固定长度 trampoline 去猜 PC-relative relocation。

## KI-026 — M4.4 session object validation 在极端 stale-pointer 窗口仍需加强

Severity: `MEDIUM`  
Status: `HARDENING CANDIDATE`

当前 reuse 前会调用 `il2cpp_object_get_class` + assignability 验证；完全不可读的 stale pointer 仍应评估在 Class API 前增加 readable mapped-region probe。

## KI-027 — M4.3/M4.4 搜索与实例 UI 新交互尚未完整验收

Severity: `MEDIUM`  
Status: `DEVICE VERIFICATION PENDING`

仍需确认 Assembly picker、全部 Assembly、自定义 max result、result card Assembly 去重、`/1` 布局、Details cleanup、instance picker 等真机行为。

## KI-028 — 键盘 Search / 页面 Search 路由差异与 M4.4.1 回归

Severity: `HIGH`  
Status: `M4.4.2 FIX IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

最初用户实机发现：页面 `搜索` 按钮可正常搜索，但键盘右下角 Search 会提示找不到 IL2CPP 方法。

根因第一层：M4.3 的 `method_exchangeImplementations` 让 `zn60v3_startSearch:` 与 `znm43_startSearch:` 的 selector 名称和真实 implementation 发生交换；页面按钮和键盘因此走不同实现。

M4.4.1 将两边都绑到 `znm441_submitSearch:` 后，用户再次实机确认：两边确实一致，但**两边都提示找不到 IL2CPP 方法**，而 M4.4.1 之前页面按钮可正常搜索。说明 M4.4.1 统一到了错误的新路径。

M4.4.2 新增 `ZNM442SearchRestore.mm`，两种触发方式现在只做输入规范化，然后把实际搜索重新委托给 post-swap `znm43_startSearch:`，即此前页面按钮使用、已有真机成功证据的原始 V3 implementation。

M4.4.2 CI run `35791561620` 已通过。必须使用**同一个此前成功、随后回归的方法名**真机复测两种触发方式都成功后才能关闭。

## KI-029 — Finder 裸 HEX / RVA / Runtime VA 反查规范化待真机验证

Severity: `MEDIUM`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M4.4.1/M4.4.2 接受：

```text
38064A8
0x38064A8
rva:38064A8
rva:0x38064A8
va:0x...
```

前四种归一化为 `rva:0x...`；`va:` 先按当前 UnityFramework runtime base 换算 RVA，再进入现有 V3 reverse-RVA backend。

风险：裸 HEX 采用 address-like heuristic。若真实方法名本身恰好是长十六进制样式 token，显式 `rva:` 可消除地址意图歧义。

## KI-030 — Patch Offset 自动 `0x` 规范化待真机验证

Severity: `LOW`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

底层 validator/workspace 原本已经支持裸十六进制。M4.4.1 只统一 UI：输入 `38064A8` 后按 `完成`，应显示并保存为 `0x38064A8`，随后继续走原验证/构建链。

## KI-031 — Common Unity struct `/1` 仅覆盖四种已知 layout

Severity: `MEDIUM`  
Status: `LIMITED SUPPORT / DEVICE VERIFICATION PENDING`

M4.4.1 仅把 exact `Vector2`、`Vector3`、`Quaternion`、`Color` 作为连续 float component struct 处理。不要把这个支持泛化为“所有 complex value type 都可执行”。

自定义 struct、Matrix、Bounds、Ray、Nullable、自定义泛型值类型等仍必须独立分析 ABI/layout 后再开放。

## KI-032 — Assembly-CSharp 视觉默认不能等同严格过滤

Severity: `HIGH`  
Status: `M4.4.2 FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

原始 V3 在未指定 Assembly 时的语义是：扫描全部 loaded Assembly，但把 `Assembly-CSharp` 放在第一优先级。M4.3/M4.4.1 UI 把视觉默认 `Assembly-CSharp` 直接用于 `Assembly-CSharp!Method`，把“优先”错误变成“只搜这个 Assembly”。如果目标方法实际位于其他游戏 Assembly，会出现旧 V3 能搜到、新路径搜不到。

M4.4.2 为 Assembly picker 增加 explicit-selection 状态：用户没有实际点选 Assembly 前，视觉显示 `Assembly-CSharp · 优先`，实际保持全局 V3 搜索；只有用户明确选择某个非空 Assembly 时才执行严格 scoped search。选择 `全部 Assembly` 继续全局搜索。

该行为已通过源码契约/arm64 CI/Binary Verify，但仍需真机验证默认全局行为与手工严格过滤都符合预期。
