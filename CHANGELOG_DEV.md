# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-22 — v0.5.8-dev M4.3.1 Instance Resolver Polish V1

Runtime product source head: `7e34d4edd905ea8de1328323ae39143b98601fba`

CI validated branch head: `f702e27bb0f138b6f54f4f6460c3307807c215b9`

分支：`feature/runtime-patch-menu-v0.5.8-m4.3.1-instance-resolver-polish-v1`

实际修改：

- 在 M4.3 Instance Resolver V1 基础上收紧 IL2CPP liveness 时序，参考当前 `frida-il2cpp-bridge gc.choose()`：优先 legacy `calculation_begin -> from_statics -> end`。
- 仅当 legacy liveness 不可用时回退 modern `allocate_struct -> from_statics -> finalize -> free_struct`。
- modern 路径增加 `il2cpp_stop_gc_world` / `il2cpp_start_gc_world` 包围，避免在 GC world 运行时直接执行 modern liveness。
- modern capability 现在要求 `allocate_struct/from_statics/finalize/free_struct/stop_gc_world/start_gc_world` 全部存在，否则不宣称可用。
- Instance Resolver 继续保持 fail closed：0 个实例不执行；多个实例返回 `FAILED_INSTANCE_AMBIGUOUS`，绝不自动选第一个。
- 当 `il2cpp_object_get_class` 和 `il2cpp_class_is_assignable_from` 可用时继续做 Class 二次验证。
- Method Finder 搜索结果卡片不再显示 Assembly；Assembly 仍完整保留在 candidate identity / Runtime Action / Details / 实际解析链中。
- `/0` 结果卡压缩为 Method/arity + Class + `测试执行/创建方法`。
- `/1` 结果卡显示 Method/arity + Class，参数输入框单独占下一行，避免方法名被输入框挤窄。
- 最大结果输入从 `UIKeyboardTypeNumberPad` 改为 `UIKeyboardTypeNumbersAndPunctuation`，保留 `UIReturnKeyDone`，确保右下角能真正出现“完成”并收起键盘。
- 最大结果范围继续为 `1–1024`，搜索后端 hard limit 同样为 1024，不是只改 UI。
- Assembly 选择器仍位于搜索页，使用与 App Libraries 相同的 action-sheet 选择交互；默认 `Assembly-CSharp`，支持 `全部 Assembly`。
- 详情页仍保留 Assembly / Namespace / RVA / VA / MethodInfo 等完整信息，不再重复 Runtime test/create 操作区。
- Offset Resolver V2、`ZN44StaticEntry == 128`、`ZNRuntimeMethodCallEntry == 64` 和 consolidated `ZonoeRuntimeMenu.mm` 核心未修改。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.3.1 Instance Resolver Polish V1`
- Run: `35751054253`
- Result: `success`
- Source contract assertions: PASS
- arm64 compile/link/sign: PASS
- Verify binary: PASS
- Artifact upload: PASS
- Artifact: `ZonoPatch-v0.5.8-M4.3.1-InstanceResolverPolish-V1`
- Artifact ID: `10705387042`
- Artifact ZIP size: `443364`
- Artifact ZIP SHA256: `698923e8cd03228fa86a3fc9920c4c6fae6363cbd5668bf82e42488c16459a84`
- Dylib: `ZonoPatch_v0.5.8_M4.3.1_InstanceResolverPolish_V1.dylib`
- Dylib size: `985472`
- Dylib SHA256: `04384aaadeb9a21ba8b494bfb9d2adf4ac201e5125f2d79a7ae5acefd66574dd`
- Mach-O: thin arm64 dylib
- Independent post-download ZIP/dylib hash recheck: PASS
- Binary strings independently confirmed: `[m4.3.1-ui]`, `[instance-resolver]`, `il2cpp_stop_gc_world`, `il2cpp_start_gc_world`, `znm43_testCandidate:`, `znm43_createCandidate:`.

验证边界：

- M4.3.1 当前只能标为：源码完成 / GitHub 已提交 / arm64 编译通过 / 二进制验证通过 / Artifact 已生成。
- Assembly 选择器、>64 最大结果、结果卡隐藏 Assembly、`Done` 键、unique-instance invoke 尚未真机验证。
- 只有 M4 V1 用户明确反馈过的 `/0` 创建/测试/生成后二进制路径可继续标记 device-verified。

## 2026-09-22 — v0.5.8-dev M4.2 Typed Arguments UI V1

Runtime product source head: `d775db7015a2290e508ab8de8aeeae7ce0723c7a`

CI validated branch head: `e7c81172b04e162f74b3652048dcaf499d753aa4`

分支：`feature/runtime-patch-menu-v0.5.8-m4.2-typed-args-ui-v1`

实际修改：

- 保留已真机验证过的 `/0` static Runtime Method Call 路径，新增 `/1` typed argument static invoke。
- `ZNIL2CPPInvokeEngine` 在执行 `/1` 前通过 `ZNIL2CPPDescribeMethodABI` 重新读取真实 IL2CPP 参数类型，不根据用户输入文本猜 ABI。
- 首阶段支持 bool、signed/unsigned 32/64-bit integer、float、double、enum primitive ABI、`System.String`。
- `System.String` 使用 `il2cpp_string_new` 创建托管字符串；值类型通过 typed local storage 地址组成 `void **params` 后交给 `il2cpp_runtime_invoke`。
- instance 方法仍 fail closed；`/2+`、ref/out、pointer、复杂 value type/struct、普通 object reference、未知 ABI、generic definition 暂不执行。
- Runtime Action Model 新增 `argumentValues`；Builder 可继续编辑 `/1` 保存值。
- Runtime Action Entry 保持 64 bytes；使用 `ZNRuntimeActionFlagArgument0Text + reserved[0]` 保存 `/1` 参数文本在现有 string pool 中的 offset。
- Runtime loader 能从生成二进制恢复 `/1` 参数文本，并在执行时再次解析当前 IL2CPP 签名。
- Method Finder 搜索结果增加动态 arity 筛选：`全部` + 当前候选实际存在的 `0/1/2/...`；筛选只作用于已返回候选，不重新扫描。
- 紧凑结果不再显示 Namespace / RVA；显示 Method/arity、Class、Assembly，完整 Namespace/RVA/VA/MethodInfo 等仍保留在 Details。
- `/1` 结果卡增加内联输入框；右侧直接 `测试执行` / `创建方法`；左侧信息区域进入 Details。
- `/2+` 仍可显示和筛选，但测试/创建按钮禁用。
- `/1` 输入值在筛选切换和同页 render 之间保留。
- `App Libraries` 弹窗改为只显示最终模块名，不再显示 `name · relative/path`；内部 target identity/path 解析不变。
- 详情页文案升级到 M4.2：`/1` 提示返回搜索结果输入参数，避免详情页出现第二套不同步参数输入。
- Offset Resolver V2、`ZN44StaticEntry == 128` 和 consolidated `ZonoeRuntimeMenu.mm` 核心未修改。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.2 Typed Args UI V1`
- 首次 Run: `35741898563`
  - Source contract: PASS
  - arm64 compile/link/sign: PASS
  - Verify binary: FAIL，仅因为 macOS `strings` 对中文 UTF-8 输出损坏，`grep '测试执行'` 未命中；不是产品编译失败。
- 最终 Run: `35742172120`
- Result: `success`
- Artifact: `ZonoPatch-v0.5.8-M4.2-TypedArgsUI-V1`
- Artifact ID: `10699772622`
- Artifact ZIP size: `423308`
- Artifact ZIP SHA256: `abdde87ce011b96e0f31472973addc8147ff9d2e389f5124d3713b457a451626`
- Dylib: `ZonoPatch_v0.5.8_M4.2_TypedArgsUI_V1.dylib`
- Dylib size: `952080`
- Dylib SHA256: `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`
- Mach-O: thin arm64 dylib
- Source contract assertions: PASS
- Binary marker/selector verification: PASS
- `__init_offsets == 4`: PASS
- Artifact upload: PASS
- Independent post-download ZIP/dylib hash recheck: PASS
- Binary strings independently confirmed: `[m4.2-ui]`, `typedArg1Static`, `znm42_testCandidate:`, `znm42_createCandidate:`, `App Libraries`, `il2cpp_runtime_invoke`, `il2cpp_string_new`.

验证边界：

- M4.2 当前只能标为：源码完成 / GitHub 已提交 / arm64 编译通过 / 二进制验证通过 / Artifact 已生成。
- `/1` typed invoke、arity 筛选、内联参数输入、生成后二进制 `/1` 参数恢复尚未真机验证。
- M4.1 的触摸穿透、App Libraries、滚动保持、title 改名、direct-build preflight 也仍待真机验证。
- 只有 M4 V1 用户明确反馈过的 `/0` 创建/测试/生成后二进制路径可继续标记 device-verified。

## 2026-09-22 — v0.5.8-dev M4.1 UI/UX V2

Runtime product source head: `4d3f62bd5ae645493e3af10e179402d9cc47e889`

CI validated branch head: `911dec0c56234387820fbec5daf996e396f86294`

分支：`fix/runtime-patch-menu-v0.5.8-m4.1-ui-ux-v2`

实际修改：

- 新增 `ZNUXFixesV2.mm`，作为 Offset Resolver V2 / Runtime Method Call 之后的最外层 UX 修复层。
- `其他 -> 二进制` 改为自动识别 + 点击选择：优先 `UnityFramework`，不存在时回退当前 App 主程序。
- 新增 `App Libraries` 选择器，按当前进程已加载且属于 App Bundle 的 Mach-O images 提供主程序、framework、dylib 选择，不再要求手工输入目标名/绝对路径。
- 不持久化 `/var/containers/Bundle/Application/<UUID>/...` 绝对路径；运行时重新解析真实路径。
- 增加菜单面板外触摸穿透 UX，目标是菜单控件可交互、面板外继续操作游戏。
- 同页 `renderPage` 操作增加 `contentOffset` 保存/恢复，修复按钮操作后滚动页跳回顶部的问题。
- `生成新二进制` 不再要求用户先手工点击 `读取验证`；构建流程自动进行必要 preflight。
- 自动 preflight 不删除 Static Builder 的 Original / 长度 / RVA-file 映射 / Mach-O / relocation 安全检查。
- Runtime Method Call Builder 增加自定义 `title` 编辑入口；显示名与 `methodName`/canonical identity 分离。
- M4.1 没有修改 `ZNOffsetResolverV2.mm`、`ZNStaticPatchFormat.h` 和 consolidated `ZonoeRuntimeMenu.mm` 核心。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.1 UI UX V2`
- Run: `35704458522`
- Result: `success`
- Artifact: `ZonoPatch-v0.5.8-M4.1-UIUX-V2`
- Artifact ID: `10683409230`
- Artifact ZIP SHA256: `f9d88f62a923a4adc9797d686ad601198761af14d4f27d4919906ba97dc83450`
- Dylib SHA256: `4ad03fdd759cb7218cb3aeb22a12f1bca75ff6ccf12a10532f47e5bf516574ae`
- M4.1 new UX remains device-validation pending.

## 2026-09-22 — v0.5.8-dev M4 Runtime Method Call V1 device evidence

CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`

分支：`feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`

- Independent Runtime Action ABI added without changing Static Patch ABI.
- `ZNRuntimeActionHeader == 64`, `ZNRuntimeMethodCallEntry == 64`, `ZN44StaticEntry == 128`.
- Method Finder added `创建方法按钮` and `测试执行`.
- V1 supports zero-argument static IL2CPP methods through `il2cpp_runtime_invoke`.
- Instance methods fail closed without a valid instance.
- Builder embeds Runtime Action table into generated Mach-O.
- CI run `35689545606` success; Artifact ID `10678476991`; dylib SHA256 `53bc795e7c9fbefb7443da12d5ea9598b5eba9f0a2b51a453ad9445d93f50651`.
- User explicitly confirmed on device: `创建方法按钮` works, `测试执行` works, and generated binary is usable. This is not a full regression pass.

## 2026-09-15 — v0.5.8-dev Method Finder V3 M2.2 device acceptance

Product source: `19b912c840e7223adbc2c26ef80185c32b8eb77a`

- Builder Feature/Patch delete capability.
- Generic controls: Toggle / Number / Action / Slider.
- Static ABI remains 128-byte Entry.
- Search/Cancel UI stable-update path.
- CI run `34893082122` success.
- User device feedback: `目前没问题了。`

## Historical anchors

- M2.1 Cancel UX: source `47d186730ffdf28c2c4bc8fc2992c938c3f1e2b5`, CI `34885020233` success.
- M2 broad search: source `69b546edd0ed83a5699805951304aa3371a0bc30`, CI `34881764073` success; measured device query first `423.1 ms`, then ~`147–150 ms`.
- Method Finder V3 M1 known target: `Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0`, device RVA `0x2DA9E10`.
- v0.5.1 Static RVA Protection V1 source `7360f72c8e27b6e3da5c70f6394f2fac17cd6ba5`, CI `34711600783` success; real `.znpatched` validation gap remains in `KNOWN_ISSUES.md`.
