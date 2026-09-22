# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

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
- `ZNRuntimeActionModel` 增加 title 更新能力；Runtime Action ABI 不变。
- M4.1 没有修改 `ZNOffsetResolverV2.mm`、`ZNStaticPatchFormat.h` 和 consolidated `ZonoeRuntimeMenu.mm` 核心。

CI / Build：

- Workflow: `Build Runtime Patch Menu v0.5.8 M4.1 UI UX V2`
- Run: `35704458522`
- Result: `success`
- Artifact: `ZonoPatch-v0.5.8-M4.1-UIUX-V2`
- Artifact ID: `10683409230`
- Artifact ZIP SHA256: `f9d88f62a923a4adc9797d686ad601198761af14d4f27d4919906ba97dc83450`
- Dylib: `ZonoPatch_v0.5.8_M4.1_UIUX_V2.dylib`
- Dylib SHA256: `4ad03fdd759cb7218cb3aeb22a12f1bca75ff6ccf12a10532f47e5bf516574ae`
- Mach-O: thin arm64 dylib
- `__init_offsets == 4`: PASS
- Source contract assertions: PASS
- Binary marker verification: PASS
- Artifact upload: PASS
- Independent post-download ZIP/dylib SHA256 recheck: PASS

验证边界：

- 当前 M4.1 仅能标为：源码完成 / 已提交 / CI 编译通过 / 二进制验证通过 / Artifact 已生成。
- 新增的触摸穿透、App Libraries、滚动位置保持、Runtime title 改名、无需手工读取验证直接生成，均待真机验证。
- 不得把 M4.1 标成 device-verified，直到用户反馈这些新行为。

## 2026-09-22 — v0.5.8-dev M4 Runtime Method Call V1 device evidence

CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`

分支：`feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`

实际修改：

- 在 Offset Resolver V2 上增加独立 Runtime Action 模型和二进制格式。
- `ZNRuntimeActionHeader == 64` bytes。
- `ZNRuntimeMethodCallEntry == 64` bytes。
- 保持 `ZN44StaticEntry == 128` bytes，不把 Runtime Method Call 字段塞入旧 Static Patch ABI。
- Method Finder 增加 `创建方法按钮` 和 `测试执行`。
- 首版 Runtime Method Call 支持 0 参数 static IL2CPP 方法。
- 使用 `il2cpp_runtime_invoke` 执行，实例方法无有效 instance 时 fail closed。
- Builder 能把 Runtime Action table 嵌入生成后的 Mach-O。

CI / Build：

- Run: `35689545606`
- Result: `success`
- Artifact ID: `10678476991`
- Dylib SHA256: `53bc795e7c9fbefb7443da12d5ea9598b5eba9f0a2b51a453ad9445d93f50651`
- Source contract / Runtime Action format / Static ABI regression / Theos build / binary verify / upload: PASS

真机反馈：

用户明确确认：

- `创建方法按钮`：没问题；
- `测试执行`：没问题；
- 制作出的二进制：可以用。

因此上述 3 个路径可标记为 device-verified。不要扩展解释成所有旧功能均完成 full regression。

## 2026-09-15 — v0.5.8-dev Method Finder V3 M2.2 device acceptance

Product source: `19b912c840e7223adbc2c26ef80185c32b8eb77a`

- Builder 增加 Feature/Patch 删除能力。
- Generic controls: Toggle / Number / Action / Slider。
- Static ABI 仍为 128-byte Entry。
- Search/Cancel UI 改为稳定更新，避免进度刷新导致整页闪动。
- CI run `34893082122` success。
- 用户真机反馈：`目前没问题了。`
- 该反馈记为当前 exercised build device accepted，但不是逐项 full regression。

## 2026-09-15 — v0.5.8-dev Method Finder V3 M2.1 Cancel UX

Product source: `47d186730ffdf28c2c4bc8fc2992c938c3f1e2b5`

- active token 时顶部主按钮 `搜索 -> 取消`。
- 去掉底部临时 Cancel 卡片。
- 不人为降低生产搜索速度。
- CI run `34885020233` success。
- Artifact ID `10364618234`。
- M2 宽泛搜索真实设备数据：首轮 `423.1 ms`，第二轮 `147 ms`，后续约 `150 ms`。

## 2026-09-15 — v0.5.8-dev Method Finder V3 M2

Product source: `69b546edd0ed83a5699805951304aa3371a0bc30`

- 裸方法名大小写不敏感宽泛搜索：`exact > prefix > suffix > contains`。
- 结构化表达式 / RVA 继续 exact。
- 后台搜索、cooperative cancel、分片进度。
- UnityFramework UUID + file size 指纹索引。
- 索引不保存 launch-specific MethodInfo / Method Pointer / Runtime VA。
- CI run `34881764073` success。

## 2026-09-15 — Method Finder V3 M1 device acceptance

- 多候选结果列表。
- Qualified lookup / RVA reverse lookup。
- Detail 显示 RVA / Preferred VA / Runtime VA / MethodInfo / Method Pointer。
- Candidate -> Builder canonical expression。
- 已知目标 `Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0` 真机 RVA `0x2DA9E10`。

## 2026-09-13 — v0.5.1 Static RVA Protection V1

Runtime code head: `7360f72c8e27b6e3da5c70f6394f2fac17cd6ba5`

- Static Entry RVA protection / integrity check。
- 保持 64-byte Header / 128-byte Entry ABI。
- generated Mach-O 后处理、CodeDirectory 校验。
- CI run `34711600783` success。
- Protection 真实 `.znpatched` 行为仍有历史验证缺口，详见 `KNOWN_ISSUES.md`。

## 2026-09-13 — Compact Public UI + plist privacy cleanup

- Public UI 默认 Compact；按钮显示 `开 / 关`。
- 废弃旧 Feature Name Registry。
- Feature 状态改为 opaque Feature ID key。
- CI run `34708549712` success。

## 2026-09-12 — FeatureID metadata stage

- 引入 ZNF1 Feature metadata codec。
- generated Mach-O 以 FeatureID + encoded display name 保存显示信息。
- 保持 Static Entry 128-byte ABI。
