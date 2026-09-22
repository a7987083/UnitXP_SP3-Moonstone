# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-22 — v0.5.8-dev M4.4 Instance Resolver V2

分支：`feature/runtime-patch-menu-v0.5.8-m4.4-instance-resolver-v2`

CI validated head：`21775c3e0320399784a5a5b87131ab96cb9a80d5`

实际修改：

- 在 M4.3 IL2CPP liveness 实例枚举之上新增 process-session instance selection store。
- selection key 为 `assembly|namespace|class`；同一 Class 的 Finder 测试与 Runtime Action 执行可复用当前进程内选择。
- 新增 `ZNIL2CPPInstanceSelectionV2.h/.mm`：支持读取、选择、清除、验证当前 session instance。
- 选择地址在使用前通过 `il2cpp_object_get_class` + `il2cpp_class_is_assignable_from` 验证；验证失败会清除 stale selection，不继续调用旧指针。
- `resolveUniqueInstance...` 外层现在先使用已验证的 session selection；没有 selection 时继续使用 M4.3 原 unique-instance resolver。
- 新增 `ZNInstanceSelectionV2UI.mm`，包裹 Finder `测试执行` 与 public Runtime Action `执行`。
- instance 方法执行前：1 个活实例自动选择；多个活实例弹出 `选择实例 · Class` action sheet，明确让用户选择；0 个实例继续 fail closed。
- 多实例选择仅在当前进程有效；没有把 `Il2CppObject *` 原始地址写入生成二进制或 Runtime Action ABI。
- M4.4 没有修改 Static Patch ABI、Runtime Action Entry 大小、Offset Resolver V2 或 consolidated `ZonoeRuntimeMenu.mm` 核心。
- receiver/`this` inline-hook capture **没有在本版伪装为已完成**；当前仓库仍没有任意 native 地址 hook backend。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.4 Instance Resolver V2`
- 首次 Run: `35751621067` — failure
  - Source contract: PASS
  - Build: FAIL
  - 根因：`ZNIL2CPPInstanceSelectionV2.h` category 未直接 import `ZNIL2CPPInstanceResolver.h`，编译器无法看到 resolver interface。
- 修复 commit: `21775c3e0320399784a5a5b87131ab96cb9a80d5`
- 最终 Run: `35751669688` — success
- Source contract: PASS
- arm64 compile/link/sign: PASS
- Binary Verify: PASS
- Artifact Upload: PASS
- Artifact: `ZonoPatch-v0.5.8-M4.4-InstanceResolver-V2`
- Artifact ID: `10704773628`
- Artifact ZIP size: `450731`
- Artifact ZIP SHA256: `798661433fca94d5ee256746b1c37091b0246d24175a206a47bfda0e48ea123d`
- Dylib: `ZonoPatch_v0.5.8_M4.4_InstanceResolver_V2.dylib`
- Dylib size: `1002176`
- Dylib SHA256: `30fc5f2c584931dcfced0b2e321e821a4b2c3f9d7476f014143d9b6fa31adeea`
- Mach-O: thin arm64 dynamically linked shared library
- Independent strings confirmed: `[instance-resolver]`, `[instance-selection-v2]`, `selected-session-instance`, `znm44_testCandidate:`, `znm44_executeAction:`, `[m4.3-ui]`.

验证边界：

- M4.4 当前状态：源码完成 / GitHub 已提交 / arm64 CI 编译通过 / 二进制验证通过 / Artifact 已生成。
- 多实例 action sheet、session reuse、stale-instance rejection 尚未真机验证。
- receiver capture / inline-hook fallback 尚未实现。

## 2026-09-22 — v0.5.8-dev M4.3 Instance Resolver V1 + Finder UX

最终 CI head：`a5688b3f42f53aa50366f349813be069ef0e5418`

分支：`feature/runtime-patch-menu-v0.5.8-m4.3-instance-resolver-v1`

实际修改：

- 新增 `ZNIL2CPPInstanceResolver.h/.mm`，通过 Unity/IL2CPP liveness API 枚举指定 Class 的活实例。
- legacy 路径优先：`il2cpp_unity_liveness_calculation_begin` → `from_statics` → `end`。
- modern fallback：`allocate_struct` → `from_statics` → `finalize` → `free_struct`，并要求 `il2cpp_stop_gc_world` / `il2cpp_start_gc_world` 时序。
- liveness 结果再通过 `il2cpp_object_get_class` / `il2cpp_class_is_assignable_from` 做 Class 验证。
- instance `/0`、`/1` 在“恰好一个活实例”时可把该对象作为 `this` 交给 `il2cpp_runtime_invoke`；0 个或多个实例仍 fail closed。
- 搜索页新增 Assembly picker，默认 `Assembly-CSharp`，可选其他运行时 Assembly 或 `全部 Assembly`。
- 搜索最大结果由原 64 hard limit 升到可输入，UI/backend hard max `1024`。
- `/1` 参数输入框移到方法名/Class 下方，避免长方法名被压缩。
- 参数输入与最大结果输入的 Return 行为统一为 `完成`/dismiss。
- Details 页去掉重复 Runtime 测试/创建动作；测试/创建统一留在搜索结果卡。
- 单一 Assembly 已在上一页选定时，结果卡隐藏重复 Assembly 名；选择 `全部 Assembly` 时保留 Assembly 以区分候选。
- Namespace/RVA 仍只在 Details 中显示。

CI / Build：

- Final workflow run: `35750846250`
- Result: `success`
- Source contract, arm64 compile, binary verify, artifact upload: PASS
- 该阶段仍未获得真机实例调用证据。

## 2026-09-22 — v0.5.8-dev M4.2 Typed Arguments UI V1

分支：`feature/runtime-patch-menu-v0.5.8-m4.2-typed-args-ui-v1`

- 保留 M4 `/0` static Runtime Method Call 路径，新增 `/1` typed static invoke。
- `/1` 执行前通过 `ZNIL2CPPDescribeMethodABI` 读取真实 IL2CPP 参数 ABI。
- 支持 bool、signed/unsigned 32/64-bit integer、float、double、primitive-backed enum、`System.String`。
- `System.String` 使用 `il2cpp_string_new`；值类型以 typed local storage 地址组成 `void **params` 交给 `il2cpp_runtime_invoke`。
- `/2+`、ref/out、pointer、复杂 struct、普通 object reference、unknown ABI、generic definition fail closed。
- Runtime Action Model 新增 `argumentValues`；Builder 可编辑 `/1` 保存值；生成二进制通过现有 string pool 持久化参数文本。
- Method Finder 增加动态 `[全部][0][1]...` 本地 arity filter。
- compact result 隐藏 Namespace/RVA，右侧直接 `测试执行` / `创建方法`。
- App Libraries 改为只显示最终模块名。
- Final CI run `35742172120`: success。
- Artifact ID `10699772622`; dylib SHA256 `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`。
- `/1` 仍待真机验证。

## 2026-09-22 — v0.5.8-dev M4.1 UI/UX V2

分支：`fix/runtime-patch-menu-v0.5.8-m4.1-ui-ux-v2`

- 自动二进制目标：UnityFramework 优先，主程序 fallback。
- App Libraries 选择器。
- 菜单 panel 外触摸穿透。
- 同页滚动位置保持。
- 生成二进制无需先手工点 `读取验证`；内部仍执行 required preflight。
- Runtime Method Call title 可编辑，与 method identity 分离。
- CI run `35704458522`: success。
- 新 UX 仍待真机验收。

## 2026-09-22 — v0.5.8-dev M4 Runtime Method Call V1 device evidence

分支：`feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`

- Runtime Action ABI 独立于 Static Patch ABI。
- `ZNRuntimeActionHeader == 64`, `ZNRuntimeMethodCallEntry == 64`, `ZN44StaticEntry == 128`。
- V1 通过 `il2cpp_runtime_invoke` 支持 zero-argument static methods。
- CI run `35689545606`: success；dylib SHA256 `53bc795e7c9fbefb7443da12d5ea9598b5eba9f0a2b51a453ad9445d93f50651`。
- 用户明确真机确认：`创建方法按钮`、`测试执行`、生成后二进制可用。仅这些路径标记 device-verified。

## 2026-09-15 — Method Finder V3 M2.2 device acceptance

- Product source: `19b912c840e7223adbc2c26ef80185c32b8eb77a`。
- Builder Feature/Patch delete；Toggle/Number/Action/Slider controls；Static ABI 128-byte Entry。
- CI run `34893082122`: success。
- 用户反馈：`目前没问题了。`

## Historical anchors

- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`。
- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`。
- Method Finder V3 M2 broad search 设备观测：第一次 `423.1 ms`，后续约 `147–150 ms`。
- v0.5.1 Static RVA Protection V1 的真实 `.znpatched` 验证缺口继续记录于 `KNOWN_ISSUES.md`。
