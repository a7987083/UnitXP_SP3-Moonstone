# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — Protection V1 尚未实机 / 真实 `.znpatched` 验证

Severity: `HIGH`

Status: `OPEN`

CI 已确认 Protection codec、编译和 binary verify 通过，但还没有真实目标输出证据确认：生成后的 Static Entry 三个 RVA 字段已编码、Runtime 能正常恢复、Shared Site 与最终 IPA 冷启动不回归。

下一步：用 v0.5.1 生成真实 `.znpatched`，提交 `.znpatched + build_report.json` 做结构检查并上机测试。

## KI-002 — FeatureID 仍是可推导 ID，不是随机稳定 authoring ID

Severity: `MEDIUM`

Status: `OPEN / HARDENING`

当前 ZNF1 对明确 Feature group 的 FeatureID 仍由 normalized display name 推导。了解算法的分析者可对常见名称做字典匹配。

下一步：评估随机稳定 FeatureID / authoring identity，并保持同一 Feature 跨 Patch 的稳定关联。

## KI-003 — Patch payload / Variant 尚未进入 Protection V2

Severity: `HIGH`

Status: `OPEN / HARDENING`

Protection V1 已让 Static Entry 的 `siteRVA/offRVA/onRVA` 不再以直接可读整数存储，但 relocated Original / ON Variant 仍存在于 `__ZNTEXT`。熟悉 ARM64 relocation 和 ZonoPatch 结构的分析者仍可进一步恢复 Patch 内容。

## KI-004 — Protection V1 是可逆静态分析成本层，不是客户端秘密

Severity: `MEDIUM`

Status: `BY DESIGN`

Runtime 必须最终得到真实地址；且当前仓库公开。Protection V1 的目标是增加静态批量恢复成本和完整性检查，而不是保证地址不可恢复。

## KI-005 — Metadata / RVA 后处理仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`

Status: `OPEN / KNOWN LIMITATION`

当前 generated binary 后处理要求 `MH_MAGIC_64`。未来 FAT/universal 需要按 slice 解析。

## KI-006 — Feature 状态恢复发生在 Feature 页首次渲染

Severity: `MEDIUM`

Status: `OPEN / BEHAVIOR TO VALIDATE`

`zn.f.<feature-id>.enabled` 在 Feature UI 第一次渲染时恢复。Shared Site、多 Feature 同时恢复、失败回滚仍需实机验证。

## KI-007 — Generated binary ad-hoc 重签不是最终 IPA 签名

Severity: `MEDIUM`

Status: `OPEN / RELEASE REQUIREMENT`

Generated binary 后处理/CodeDirectory 校验不能替代最终 IPA 整包重签、安装和启动验证。

## KI-008 — Method Finder M2 indexed lookup 仍包含 live re-resolution 成本

Severity: `LOW`

Status: `MEASURED / OPTIMIZATION OPTIONAL`

真实设备宽泛查询观测：第一次 `423.1 ms`，第二次 `147 ms`，之后约 `150 ms`。索引命中后仍恢复当前 launch 的 MethodInfo / Method Pointer / Runtime VA。

## KI-009 — Method Finder M2 索引缓存缺少主动垃圾回收

Severity: `LOW`

Status: `OPEN / CLEANUP`

索引绑定 UnityFramework UUID + file size，旧 fingerprint 不会错误复用，但旧缓存暂不主动删除。

## KI-010 — M2 Objective-C dependency declarations 暂时依赖 warning suppression

Severity: `LOW`

Status: `OPEN / PRE-SEAL CLEANUP`

M2 bridge category dependency declarations 仍依赖 `-Wno-incomplete-implementation`，封板前应整理到专用接口/协议。

## KI-011 — Feature-branch GitHub Actions registration 历史异常

Severity: `LOW`

Status: `WORKAROUND / MONITOR`

历史上部分 feature branch push 出现 synthetic `BuildFailed / startup_failure / 0 jobs`。M4/M4.1/M4.2/M4.3/M4.3.1 专用 workflow 均已能够创建 runner 并实际构建，不应把历史基础设施问题误判为产品编译失败。

## KI-012 — M2 原 Cancel 控件在快速搜索上不可见/不可操作

Severity: `LOW`

Status: `LEGACY VALIDATION GAP`

M2.1 已把顶部 `搜索` 在 active token 时切换为 `取消`，但用户未单独报告该视觉状态。

## KI-013 — M4.1 菜单触摸穿透尚未真机验证

Severity: `HIGH`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

用户报告旧菜单打开后会拦截游戏操作。M4.1 新增 child-controller passthrough shell。必须同时验证：

- 面板外可继续操作游戏；
- 面板内按钮/输入框正常；
- Translate 第二次打开不闪退；
- 不破坏悬浮球显示/隐藏流程。

## KI-014 — M4.1 自动二进制选择 / App Libraries 尚未真机验证

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

目标行为：Unity 游戏优先 `UnityFramework`，无 UnityFramework 回退主程序；点击二进制弹出 App Libraries；只保存 module identity，不保存安装 UUID 绝对路径。

M4.2 又把 Picker 显示精简为仅模块最终名字。Unity 与非 Unity 目标仍都需要真机验证。

## KI-015 — M4.1 直接生成的自动 preflight 尚未真机验证

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

M4.1 取消 `validatedCount == filledCount` 的人工点击前置条件；生成时自动执行必要 preflight。Original、长度、RVA/file mapping、Mach-O、relocation 等安全条件没有被删除。

## KI-016 — Runtime Method Call 自定义显示名称尚未真机验证

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

M4 V1 创建/测试/生成后二进制已由用户确认；M4.1 新增 title 编辑。需验证改名后生成二进制显示自定义 title，但 canonical identity / methodName / 实际调用目标不变。

## KI-017 — M4.1 同页操作滚动位置保持尚未真机验证

Severity: `LOW`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

M4.1 在同页 `renderPage` 重建前后保存/恢复 `contentOffset`；侧栏分类切换仍允许主动回顶部。需要覆盖增加/删除 Patch、类型切换、Runtime Action 删除/改名/参数编辑。

## KI-018 — `/1` typed invoke 尚未真机验证

Severity: `HIGH`

Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M4.2 起已实现 `/1` typed invoke，M4.3.1 继续沿用同一 ABI-driven 参数解析和持久化链。尚无真实游戏方法执行证据。

首阶段支持：bool、signed/unsigned 32/64、float、double、enum primitive ABI、`System.String`。实际执行前会重新解析 IL2CPP method ABI。

需要至少选一个已知安全且副作用明确的 static `/1` primitive 方法，在真机验证：输入值 -> `测试执行` -> 预期效果 -> 无异常/闪退。

## KI-019 — M4.3.1 unique-instance resolver 尚未真机验证，multiple-instance 仍 fail closed

Severity: `HIGH`

Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M4.3/M4.3.1 已不再对所有 instance method 一律返回 `FAILED_INSTANCE_REQUIRED`。当前策略只允许：

- 通过 Unity liveness API 找到目标 Class 的活对象；
- 结果恰好为 1 个；
- 可用时通过 `il2cpp_object_get_class` + `il2cpp_class_is_assignable_from` 二次验证。

M4.3.1 liveness 顺序：优先 legacy `calculation_begin -> from_statics -> end`；legacy 不可用时使用 modern `stop_gc_world -> allocate_struct -> from_statics -> finalize -> start_gc_world -> free_struct`。

风险/边界：

- 0 个实例：fail closed；
- 多个实例：`FAILED_INSTANCE_AMBIGUOUS`，不自动选择；
- liveness API 在不同 Unity 版本导出情况不同；
- 当前没有显式实例列表选择 UI，也没有运行时 receiver capture 兜底。

下一步：先在真机选一个“明确只有一个活实例”的安全 Class 验证 `/0` 或 `/1`；再用多实例 Class 验证必须 fail closed。若通过，再设计显式实例选择 / receiver capture。

## KI-020 — `/2+` 与复杂参数类型只显示/筛选，不执行

Severity: `MEDIUM`

Status: `KNOWN LIMITATION / FAIL CLOSED`

动态 arity filter 可以显示当前结果中实际存在的 `/2 /3 /4 ...`，但当前 Runtime Invoke 仍仅执行 `/0` 和 `/1`。

以下参数仍故意 fail closed：ref/out、pointer、普通 object reference、complex value type/struct、未知 ABI、generic definition。Vector2/Vector3/Quaternion 即便显示为 `/1`，也属于一个复杂 struct 参数，不能拆成多个 float 后猜 ABI。

后续应扩展统一的 ABI-driven marshal loop 到 `/2+`，并为常见 Unity struct 建专用编辑器/序列化器。

## KI-021 — 搜索筛选基于当前候选集，不代表全局 arity 分布

Severity: `LOW`

Status: `BY DESIGN / UI DISCLOSURE`

`[全部] [0] [1] ...` 是当前搜索返回结果的本地筛选。如果搜索受最大结果数量或 wall-clock budget 截断，顶部 arity 按钮只代表已返回候选中的参数数量，不代表整个游戏中所有同名方法的完整 arity 分布。

必须继续显示原搜索的“结果已截断”状态，避免把局部候选筛选误解为全局统计。

## KI-022 — M4.3.1 自定义最大结果 1–1024 仍受搜索时间预算约束

Severity: `LOW`

Status: `IMPLEMENTED / DEVICE VERIFICATION PENDING`

UI 和 backend hard limit 都已从旧的 64 放宽到 1024，输入 128/256/500 不会再被后端静默 clamp 为 64。

但 Method Finder 仍保留 wall-clock budget，因此“最大结果 1024”只是 candidate ceiling，不是保证返回 1024 条。需要真机验证大于 64 的设置确实生效，并观察宽泛搜索对帧率/响应时间的影响。

## KI-023 — M4.3.1 Assembly picker / 紧凑结果隐藏 Assembly 尚未真机验证

Severity: `MEDIUM`

Status: `IMPLEMENTED / DEVICE VERIFICATION PENDING`

搜索页可点击 Assembly 选择器，默认 `Assembly-CSharp`，可切换其它 runtime assemblies 或 `全部 Assembly`。结果卡片不再重复显示 Assembly；Assembly 仍保留在 candidate identity、Runtime Action 和 Details 中。

需要验证：

- 弹窗列出的 Assembly 与当前 IL2CPP domain 一致；
- 切换 Assembly 后实际搜索范围改变；
- 结果页隐藏 Assembly 不影响创建/测试目标身份；
- Details 仍能看到正确 Assembly / Namespace / RVA / VA / MethodInfo。

## KI-024 — M4.3.1 键盘 `Done` / `/1` 新布局尚未真机验证

Severity: `LOW`

Status: `IMPLEMENTED / DEVICE VERIFICATION PENDING`

`/1` 参数输入框已移到 Method/Class 下方；最大结果与 `/1` 输入均配置 `UIReturnKeyDone`，最大结果使用 `UIKeyboardTypeNumbersAndPunctuation` 以确保有 Return/Done 键。

需要验证不同 iOS 版本和系统键盘下右下角确实显示“完成”，点击后仅收起键盘且不插入换行。
