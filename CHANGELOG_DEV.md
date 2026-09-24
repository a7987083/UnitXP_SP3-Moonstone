# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.3 M4.3 Search History UI Fix

Branch: `feature/runtime-patch-menu-v0.5.8-m5.3-control-binding-v1`

CI-validated product head: `064d535918cacd0f40a220521af7cad18a3d42d9`

实际修改：

- 修复 M5.3 真机 M4.3 方法查找页“搜索历史存在但看不到”的布局问题。
- 根因：`ZNM52MethodSearchHistory.mm` 旧实现使用 `maxY(contentView)+8` 放置历史卡片；`contentView` 同时包含更靠下的 footer/其他视图，因此历史被追加到可视 Finder 区域之后。
- 新实现使用 M4.3 已确认的固定搜索页几何：主搜索卡 `y=9 / h=170`，历史卡固定插入 `y=187`，原状态卡及其后的主内容整体向下位移。
- 搜索历史继续使用 NSUserDefaults 持久化，最多 50 条、最新置顶、大小写不敏感去重、一行一个、独立滚动。
- 历史点击交互按最新要求修改：点击只把历史值写回 Finder query model 和可见方法名输入框（V3/M4.3 query field tag `603001`），不再自动调用 `znm43_startSearch:`。
- 用户仍需手动点击右侧 `搜索` 才执行查询。
- 未修改 M5.3 Runtime Control Binding、Static Dynamic MOV、Immediate Chain V2 逻辑。

CI：

- Run `35960360188` / Job `107507414304`：Source Contract、Dobby arm64、Build M5.3、Binary Verify、Artifact Upload 全部 SUCCESS。

最终制品：

- Artifact: `ZonoPatch-v0.5.8-M5.3-Control-Binding-V1`
- Artifact ID: `10792097181`
- Artifact ZIP size: `610491`
- Artifact ZIP SHA256: `48a8eae15b567f10ec889861c89f1c03c1d6a79b72e43479abcbfbbe6c084acf`
- Dylib: `ZonoPatch_v0.5.8_M5.3_Control_Binding_V1.dylib`
- Dylib size: `1337776`
- Dylib SHA256: `bd7ca8773dca7e26ef989821c3aea3a5454cffc94d6cf0039ddb35cbb7dff1dc`
- Mach-O: thin arm64 dynamically linked shared library
- 独立下载后 ZIP digest 与 GitHub Artifact digest 一致，dylib hash 与 CI `SHA256.txt` 一致。

验证边界：

- source implemented: YES
- GitHub committed: YES
- arm64 compile/link/sign: YES
- Binary Verify: YES
- artifact independent hash verification: YES
- M4.3 历史卡片新位置真机验证: PENDING
- 历史点击仅回填、不自动搜索真机验证: PENDING
- Runtime 四控件自动执行真机验证: PENDING
- Static Button / MOVZ+MOVK 动态值真机验证: PENDING
- full regression: NO

## 2026-09-24 — v0.5.8-dev M5.3 Control Binding V1

- 基线：M5.2 HistoryFix `88ee27688ac5db067caded06da2feefb77323340`。
- 新增 `ZNM53ControlBinding.mm`。
- Runtime Button/Switch/Number/Slider 完成真实 invoke 绑定；成功静默、失败可见。
- Static Button 绑定固定 Enabled；Static Number/Slider V1 对 Protection V2 ON variant 的 ARM64 MOVZ(+MOVK) immediate 做 fail-closed 动态绑定。
- 初始绿色产品 HEAD：`b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`；Run `35951498398` / Job `107480818078`。

## Historical anchors

- M5.2 HistoryFix baseline: `88ee27688ac5db067caded06da2feefb77323340`.
- M5.2 core multi-level chain: `2456f6ba4dfb659e3480db2e677452dad8516153`.
- M5.1 Silent Customer Execution: `29c33d9246fd9842107c443d3254aff23effd59e`.
- M5.0 Managed-reference Return Chaining: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`.
