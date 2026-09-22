# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-23 — v0.5.8-dev M4.5 Address → Owning Method Resolver V1

分支：`feature/runtime-patch-menu-v0.5.8-m4.5-address-owning-method-v1`

CI validated product head：`fa2f9db21b507da64feb6ffe0acc6a29d71aff2e`

实际修改：

- 根据 H5GG Enhanced Menu 1.9.6 的 instruction offset -> method 功能思路，新增 `ZNIL2CPPOwningMethodResolver.h/.mm`。H5GG 文档描述 partial exact matching；本项目采用更严格的 method interval ownership。
- exact entry 仍支持；方法内部地址采用 `methodStart <= targetRVA < nextKnownMethodStart` 判定所属 IL2CPP method。
- live scan 达到 6 秒预算或缺少 next-method 安全上界时，interior lookup fail closed，不按“最近前一方法”猜测。
- generic/shared code 出现多个 MethodInfo 共用 native pointer 时保留多个候选，不自动选一个。
- 新候选记录 `queryRVA / methodRVA / nextMethodRVA / intraMethodOffset / ownershipKind`。
- interior candidate canonical 形如 `Assembly!Namespace.Class::Method/N+0xDELTA`，继续复用既有 Named Offset Parser、V3 Patch Bridge、Builder/Validator；创建 Patch 时保留用户原始 instruction RVA。
- 新增 `ZNM45AddressOwningMethodUI.mm`。只有地址查询进入 M4.5；普通方法名立即委托 M4.4.2 proven-V3，避免再次改坏真机搜索路径。
- Details 增加 `地址归属（M4.5）` 卡片，显示查询 RVA、方法入口、下一方法入口、方法内偏移、判定类型。
- 修复 `/1` unsupported UI：M4.4.1 的 disabled 灰色 UITextField 改为正常颜色的参数类型/原因 label；Test/Create 仍禁用。
- 没有修改 `ZonoeRuntimeMenu.mm`、`ZNOffsetResolverV2.mm`、`ZNStaticPatchFormat.h` 的稳定行为；Static Patch ABI 和 Runtime Action ABI 均未升级。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.5 Owning Method`
- Final Run: `35795001139` — success
- Source Contract: PASS
- arm64 compile/link/sign: PASS
- Binary Verify: PASS
- Artifact Upload: PASS
- Artifact: `ZonoPatch-v0.5.8-M4.5-OwningMethod-V1`
- Artifact ID: `10723682927`
- Artifact ZIP size: `473938`
- Artifact ZIP SHA256: `7d3070974665d4cf2962f7e4bb5283bff0c03b938bc05ce57b8f1f943545c250`
- Dylib: `ZonoPatch_v0.5.8_M4.5_OwningMethod_V1.dylib`
- Dylib size: `1052128`
- Dylib SHA256: `faa43520ac6e7086a0d6f6719a0c7076578a12d8ba493088cc114b0748ff7fa1`
- Mach-O: thin arm64 dynamically linked shared library
- Downloaded artifact hash independently matched GitHub/CI.

验证边界：

- M4.5 当前为源码完成 / CI 编译通过 / Binary Verify 通过 / Artifact 已生成。
- 尚未真机证明 interior instruction RVA 一定映射到预期 MethodInfo。
- 尚未真机证明 interior result -> Create Patch 能保留原 instruction offset。
- M4.4.2 named-search 路径必须一起回归，避免地址层 swizzle 引入搜索回归。

## 2026-09-23 — v0.5.8-dev M4.4.2 Search Restore

分支：`fix/runtime-patch-menu-v0.5.8-m4.4.2-search-restore`

CI validated product head：`fe8655444420bc9445ee741e2d3c4cffbaead066`

实际修改：

- 新增 `ZNM442SearchRestore.mm`，作为 M4.4.1 之后的最终搜索路由层。
- 根据真机反馈修复 M4.4.1 回归：页面 `搜索` 与键盘 Search 虽一致但两者都可能提示 `找不到 IL2CPP 方法`；而此前页面按钮正常。
- 根因：M4.3 对 `zn60v3_startSearch:` 与 `znm43_startSearch:` 做 `method_exchangeImplementations`，页面按钮运行时实际执行旧 V3。
- M4.4.2 不再重写搜索算法，两种触发经过规范化后委托给 post-swap `znm43_startSearch:`，即原真机可用 V3。
- 恢复默认全局 + Assembly-CSharp-first 语义；只有用户明确选择 Assembly 才严格过滤。
- 默认视觉标签为 `Assembly-CSharp · 优先`。
- M4.4.1 地址/Patch Offset 规范化和 Unity struct `/1` 均保留。

CI / Build：

- Run `35791561620`: success
- Artifact ID `10722211742`
- ZIP SHA256 `c420ab0af09943be5bf05f10cf358514071b9b00982fb242f4573a1a5b94578c`
- Dylib SHA256 `4497d04f3583a4bc447e3cdd692c2bf99479d87440221c2b85554210b251b84b`

## 2026-09-23 — v0.5.8-dev M4.4.1 Finder/Input Hotfix

分支：`fix/runtime-patch-menu-v0.5.8-m4.4.1-keyboard-search-route`

CI validated product head：`0025556b8f3a2a20466b7344120ca82f9db7f921`

- Method Finder 地址输入规范化：bare HEX / `0x` / `rva:` / `va:`。
- Patch Offset bare HEX 自动显示/保存 `0x...`。
- `/1` unsupported reason 加入 placeholder。
- 新增 exact Vector2/Vector3/Quaternion/Color `/1` marshaling。
- custom struct/object/ref/out/pointer/`/2+` 继续 fail closed。
- 首轮 CI `35789012451` 因 V3 category declaration 不可见失败；修复后 `35789261862` success。
- Artifact ID `10721074579`; dylib SHA256 `2f41f35a1bce9e07af766d2026ca8a76a6e6bf3f1919940bcdad77b80cc51549`。

## 2026-09-22 — v0.5.8-dev M4.4 Instance Resolver V2

分支：`feature/runtime-patch-menu-v0.5.8-m4.4-instance-resolver-v2`

- 在 M4.3 liveness 上新增 process-session instance selection store，key=`assembly|namespace|class`。
- 使用前 `il2cpp_object_get_class` + assignability 验证；stale selection 自动清除。
- 1 个实例自动选；多个实例 action sheet 显式选择。
- raw object pointer 不写入 generated Runtime Action。
- receiver capture 未实现。
- Final CI `35751669688`: success；Artifact ID `10704773628`; dylib SHA256 `30fc5f2c584931dcfced0b2e321e821a4b2c3f9d7476f014143d9b6fa31adeea`。

## 2026-09-22 — v0.5.8-dev M4.3 Instance Resolver V1 + Finder UX

- CI head `a5688b3f42f53aa50366f349813be069ef0e5418`; run `35750846250` success。
- IL2CPP liveness instance enumeration；unique instance 可作为 `this`。
- Assembly picker、自定义 max result 1024、`/1` 输入布局、Details cleanup。

## 2026-09-22 — v0.5.8-dev M4.2 Typed Arguments UI V1

- CI head `e7c81172b04e162f74b3652048dcaf499d753aa4`; run `35742172120` success。
- `/0` retained；`/1` primitive/enum/string typed invoke；dynamic arity filter；compact result cards。
- Artifact ID `10699772622`; dylib SHA256 `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`。

## 2026-09-22 — v0.5.8-dev M4.1 UI/UX V2

- CI head `911dec0c56234387820fbec5daf996e396f86294`; run `35704458522` success。
- 自动二进制、App Libraries、panel 外触摸穿透、滚动位置保持、direct-build preflight、Runtime Action title editing。

## 2026-09-22 — v0.5.8-dev M4 Runtime Method Call V1 device evidence

- Branch `feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`。
- CI `35689545606` success；dylib SHA256 `53bc795e7c9fbefb7443da12d5ea9598b5eba9f0a2b51a453ad9445d93f50651`。
- 用户真机确认：`/0 创建方法按钮`、`/0 测试执行`、生成后二进制可用。

## 2026-09-15 — Method Finder V3 M2.2 device acceptance

- Product source `19b912c840e7223adbc2c26ef80185c32b8eb77a`。
- CI `34893082122` success。
- 用户反馈：`目前没问题了。`

## Historical anchors

- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`。
- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`。
- Method Finder V3 M2 broad-search device observation: first `423.1 ms`, later about `147–150 ms`。
- Static RVA Protection V1 final real `.znpatched` gap remains in `KNOWN_ISSUES.md`.
