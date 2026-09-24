# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.7 Unified Control Runtime

### 真机反馈 / 根因

- Runtime Slider 在 M5.6.2 仍一拖就卡死/闪退。审计确认 Runtime 控件曾存在 M5.1 -> M5.5 -> M5.3 -> M5.5.1 -> M5.6.2 的多层 selector/event ownership；Static Feature Slider 又有独立的 `ValueChanged -> notification` 路径。
- 发现历史 `ZNRuntimeMethodCallFeatureUI` 与 M5.1 typed Runtime cards 同时存在，客户侧实际存在两套 Runtime action UI。
- Runtime-only 在没有普通 Offset 时，Mach-O 实际已生成但最后提示失败。根因是 `ZNM462RuntimeOnlyVerifier` 仍只接受 `.znpatched`，而 Runtime-only 从 M5.1 起已经保持原始、无后缀 Mach-O 文件名。
- 旧 Builder 的生成按钮条件仍要求 `workspace.filledCount > 0`，使 Runtime-only UI 仍依赖 Static Offset-era 状态。

### 实际修改

- 新增 `ZNM57UnifiedRuntimeControls.mm`，最终直接拥有 Runtime Number/Switch/Slider selectors，不 forward 到历史 M5.3/M5.5/M5.5.1/M5.6.2 控件 handler。
- Runtime Number：输入只保留当前值；Return/Done 收起键盘，不执行；卡片 `执行` 才调用。
- Runtime Slider：拖动仅整数化/更新 UI；TouchUpInside/Outside 自动提交一次，使用现有 silent Execute 读取当前 Slider 值并 Invoke 一次。
- Runtime Switch：切换后立即提交一次。
- `ZNFeatureRuntimeControlsV2.mm`：Static Number 改为输入只保存，Return 收键盘，新增 inline `执行`；Static Slider 的 `ValueChanged` 不再发通知，只在 release 发一次 commit notification。
- `ZNRuntimeMethodCallBootstrap.mm`：停止安装历史 `ZNRuntimeMethodCallFeatureUI`，只保留 Finder/Builder 后端和 M5.1/M5.7 typed Runtime 客户卡。
- `ZNIL2CPPMethodFinderMenuBinding.mm`：不再安装 `ZNInstallM53ControlBindingDeferred`、`ZNInstallM551RuntimeSliderStabilityDeferred`、`ZNInstallM562SliderIsolationDeferred`；Static 仅保留 RW value-cell backend，Runtime 仅保留 M5.7 owner。
- `ZNM462RuntimeOnlyVerifier.mm`：改为按 Mach-O magic/内容识别 suffixless Runtime-only 输出，不再要求 `.znpatched`。
- 新增 `ZNM57RuntimeOnlyBuilderGate.mm`：Runtime Actions > 0 且无完整 Static (`Offset && Enabled`) 时直接允许生成；partial Offset drafts 不阻塞。
- Static `ZNF1 -> RW Value Cell -> RVA Protection -> Ad-hoc Sign` 继续保留。

### CI / Artifact

- Workflow `Build Runtime Patch Menu v0.5.8 M5.7 Unified Control Runtime`
- Run `36019982680` / Job `107702118932`: Source Contract、Dobby arm64、Build M5.7、Binary Verify、Artifact Upload 全部 SUCCESS。
- Artifact ID `10815968483`。
- ZIP SHA256 `a369397db62835a98e5e1d66a2ca4dec7cc54d24137c3ffca7cc2449655fafd1`。
- Dylib size `1438080` bytes。
- Dylib SHA256 `252610a6bca9b09d8db2d52ac15607b5b977f69c1c726a986034e4b5b423ce8b`。
- Mach-O thin arm64；独立 ZIP/dylib hash 校验通过。

### 验证边界

- Source/build/binary/artifact: PASS。
- Runtime-only suffixless generation final UI status: DEVICE PENDING。
- Runtime Number Return-dismiss/manual Execute: DEVICE PENDING。
- Runtime Slider release-only single commit / no freeze: DEVICE PENDING。
- Static Number/Slider unified interaction + RW cell: DEVICE PENDING；需用当前 Builder 重生成目标。

## Superseded attempts

- M5.6.2: Run `36012593002`, artifact `10812584568`; superseded by M5.7 control consolidation.
- M5.6 initial: Run `36004751812`; later audit showed intended RW-cell path was not the only active path.
- M5.5.1 Recovery: Run `36002343325`; authoring persistence remains retained.

## Historical anchors

- M5.5 Typed Control initial: Run `35996840472`.
- M5.4 Unified Method Finder: Run `35964757740`.
- M5.3 Control Binding: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`.
- M5.2 Chain V2: `2456f6ba4dfb659e3480db2e677452dad8516153`.
