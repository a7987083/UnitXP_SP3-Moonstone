# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-23 — v0.5.8-dev M4.4.1 Finder/Input Hotfix

分支：`fix/runtime-patch-menu-v0.5.8-m4.4.1-keyboard-search-route`

CI validated product head：`0025556b8f3a2a20466b7344120ca82f9db7f921`

实际修改：

- 新增 `ZNM441Hotfix.mm`，作为 M4.4 之后的最外层兼容修复，不修改已锁定的 `ZonoeRuntimeMenu.mm`、`ZNOffsetResolverV2.mm`、`ZNStaticPatchFormat.h`。
- 修复 Method Finder 页面按钮与键盘右下角 Search 因 selector swizzle 最终落到不同 implementation 的问题：两者现在都重新绑定到 `znm441_submitSearch:`。
- 统一搜索入口继续保留当前 Assembly 选择、可输入最大结果数量和 V3 candidate-list backend。
- Method Finder 地址反查输入新增统一规范化：`38064A8`、`0x38064A8`、`rva:38064A8`、`rva:0x38064A8` 均归一化为 RVA 查询。
- 新增 `va:...` Runtime VA 输入：按当前加载的 UnityFramework runtime base 换算为 RVA，再进入现有 V3 reverse-RVA 搜索。
- Patch Offset 继续兼容底层原有裸 HEX / `0x` 解析，并在输入结束时把有效值统一显示/保存为 `0x...`。
- `/1` 不支持输入时不再只显示灰色控件；placeholder 会补充参数类型/不支持原因。
- 新增四种常见 Unity `/1` complex value type 的显式 marshaling：`Vector2`、`Vector3`、`Quaternion`、`Color`。
- 输入格式分别为 `x,y`、`x,y,z`、`x,y,z,w`、`r,g,b,a`；同时接受空格/中英文逗号/分号分隔。
- common struct 值仍以单个 `/1` 文本参数保存到 Runtime Action，调用时才转换为 typed float struct；Runtime Action ABI 没有升级。
- instance common-struct 方法继续复用 M4.3/M4.4 Instance Resolver/selected-session instance；static 方法直接调用。
- custom struct、普通 object reference、ref/out、pointer、generic definition 和 `/2+` 继续 fail closed。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.4.1 Hotfix`
- 首次 Run: `35789012451` — failure
  - Source contract: PASS
  - Build: FAIL
  - 根因：`ZNM441Hotfix.mm` 能调用 V3 search implementation，但编译单元没有可见的 `ZNIL2CPPMethodFinderSearchV3` category 声明。
- 修复 head: `0025556b8f3a2a20466b7344120ca82f9db7f921`
- 最终 Run: `35789261862` — success
- Source contract: PASS
- arm64 compile/link/sign: PASS
- Binary Verify: PASS
- Artifact Upload: PASS
- Artifact: `ZonoPatch-v0.5.8-M4.4.1-Hotfix`
- Artifact ID: `10721074579`
- Artifact ZIP size: `459829`
- Artifact ZIP SHA256: `5008897e16957231938f03a7a663d72395c500ef00801ce23ccf306ed70d14ee`
- Dylib: `ZonoPatch_v0.5.8_M4.4.1_Hotfix.dylib`
- Dylib size: `1018832`
- Dylib SHA256: `2f41f35a1bce9e07af766d2026ca8a76a6e6bf3f1919940bcdad77b80cc51549`
- Mach-O: thin arm64 dynamically linked shared library
- Binary verify confirmed `[m4.4.1-hotfix]`, `[m4.4.1-search]`, `[m4.4.1-struct]`, `znm441_submitSearch:` and `il2cpp_runtime_invoke`.

验证边界：

- M4.4.1 当前状态：源码完成 / GitHub 已提交 / arm64 CI 编译通过 / Binary Verify 通过 / Artifact 已生成。
- 键盘 Search、裸 HEX/RVA/VA 反查、Patch Offset 规范化和四种 Unity struct `/1` 仍待真机验证。
- receiver capture / inline-hook fallback 仍未实现。

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
- 修复 commit: `21775c3e0320399784a5a5b87131ab96cb9a80d5`
- 最终 Run: `35751669688` — success
- Artifact ID: `10704773628`
- Dylib SHA256: `30fc5f2c584931dcfced0b2e321e821a4b2c3f9d7476f014143d9b6fa31adeea`
- M4.4 多实例 action sheet、session reuse、stale-instance rejection 尚未真机验证。

## 2026-09-22 — v0.5.8-dev M4.3 Instance Resolver V1 + Finder UX

最终 CI head：`a5688b3f42f53aa50366f349813be069ef0e5418`

分支：`feature/runtime-patch-menu-v0.5.8-m4.3-instance-resolver-v1`

- 新增 `ZNIL2CPPInstanceResolver.h/.mm`，通过 Unity/IL2CPP liveness API 枚举指定 Class 的活实例。
- legacy 路径优先；modern fallback 要求 `il2cpp_stop_gc_world/start_gc_world` 时序。
- instance `/0`、`/1` 在恰好一个活实例时可把该对象作为 `this` 交给 `il2cpp_runtime_invoke`。
- 搜索页新增 Assembly picker，默认 `Assembly-CSharp`，可选其他运行时 Assembly 或 `全部 Assembly`。
- 搜索最大结果由原 64 hard limit 升到可输入，UI/backend hard max `1024`。
- `/1` 参数输入框移到方法名/Class 下方；Details 页去掉重复 Runtime 测试/创建动作。
- Final workflow run `35750846250`: success。

## 2026-09-22 — v0.5.8-dev M4.2 Typed Arguments UI V1

分支：`feature/runtime-patch-menu-v0.5.8-m4.2-typed-args-ui-v1`

- 保留 M4 `/0` static Runtime Method Call 路径，新增 `/1` typed static invoke。
- 支持 bool、signed/unsigned 32/64-bit integer、float、double、primitive-backed enum、`System.String`。
- `/2+`、ref/out、pointer、复杂 struct、普通 object reference、unknown ABI、generic definition fail closed。
- Runtime Action Model 新增 `argumentValues`；Builder 可编辑 `/1` 保存值。
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
