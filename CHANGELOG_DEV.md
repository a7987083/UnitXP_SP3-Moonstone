# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-26 — M5.8 Control Architecture Cleanup Phase 1

### 真机反馈

- M5.7 Runtime Slider 仍在“未点执行、仅拖动”时卡死。
- 因此可排除 Execute 按钮本身是唯一触发点，重新审计整个 UI/control ownership。

### 重新审计结果

确认至少 7 类重复/叠层问题：Runtime control 多代实现、Slider 热路径副作用、Static/Runtime 两套 control framework、Builder 多层 renderer wrapper、Method Finder 历史层未物理清理、legacy control 文件仍编译、Runtime-only 判定分散。

### 实际修改

- 新增 `ZNM58UnifiedControlRuntime.mm`：Runtime customer Number/Slider/Switch/Button 由单一 renderer 创建，控件不再绑定 M5.1/M5.5/M5.7 历史 handler。
- Runtime Slider 创建时一次性绑定 `ValueChanged` 与 release target；`ValueChanged` 函数体零副作用，release 才量化并 Invoke 一次。
- Runtime Number Return/Done 只 `resignFirstResponder`；执行仅由卡片 `执行` 触发。
- Runtime silent-success/failure-visible 逻辑并入 M5.8 execute，不再依赖 `ZNM51SilentCustomerExecution` constructor swizzle。
- `ZNM55TypedControlBinding.mm` 删除 Runtime Number/Slider swizzle，只保留 Builder Value Type / Range authoring。
- Runtime-only build-button gate合并进 M5.5 authoring decorator，移除独立 `ZNM57RuntimeOnlyBuilderGate` wrapper。
- `ZNFeatureRuntimeControlsV2.mm`：Static Slider 的 `ValueChanged` 改成 no-op；旧路径中的 Static runtime refresh、NSUserDefaults write、slider.value rewrite 全部移动到 release commit。
- Makefile 物理移除 8 个 legacy control/UI owner：`ZNRuntimeMethodCallFeatureUI`、`ZNM51SilentCustomerExecution`、`ZNM53ControlBinding`、`ZNM55StaticTypedBinding`、`ZNM551RuntimeSliderStability`、`ZNM562SliderIsolation`、`ZNM57UnifiedRuntimeControls`、`ZNM57RuntimeOnlyBuilderGate`。
- Static RW Value Cell backend 保留；128-byte Static Entry / 64-byte Runtime Action ABI 不变。

### CI / Artifact

- Workflow `Build Runtime Patch Menu v0.5.8 M5.8 Control Cleanup`
- Run `36232977858` / Job `108379494581`: Source Contract、Dobby arm64、Build M5.8、Binary Verify、Artifact Upload 全部 SUCCESS。
- Artifact ID `10903556469`。
- ZIP SHA256 `d3431040c47df6d6322566f4139604d6a1d82fae03e4914df0f2ea842b260f0d`。
- Dylib size `1404720` bytes。
- Dylib SHA256 `b0cbfae1b253c97714affa14deb5cd29b9ce48ee996f054ab080e81e2a70c827`。
- Mach-O thin arm64；独立 ZIP/dylib hash 校验通过。

### 验证边界

- Source/build/binary/artifact: PASS。
- Runtime Slider zero-side-effect drag: DEVICE PENDING。
- Runtime Slider single release commit: DEVICE PENDING。
- Runtime Number Return-dismiss/manual Execute: DEVICE PENDING。
- Static Slider zero-side-effect drag / single RW-cell release commit: DEVICE PENDING。
- Runtime-only suffixless generation final UI status: DEVICE PENDING。
- Builder renderer/Method Finder 进一步物理清理：Phase 2，尚未完成。

## Historical anchors

- M5.7 Unified Control Runtime: Run `36019982680`.
- M5.6.2 Runtime/Static Recovery: Run `36012593002`.
- M5.5.1 Recovery: Run `36002343325`.
- M5.4 Unified Method Finder: Run `35964757740`.
- M5.2 Chain V2: `2456f6ba4dfb659e3480db2e677452dad8516153`.
