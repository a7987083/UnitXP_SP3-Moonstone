# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-28 — M5.8.2 Single Runtime UI + Runtime Value Persistence

### 真机反馈

- M5.8.1 截图显示同名 Runtime action 出现重复卡片，例如 `set_MoveSpeed` / `CheatSetExp`。
- 固定参数 action（argumentCount>0 但无 exposed control）没有 `执行` 按钮。
- Runtime Slider 没有显示拖动后的当前值。
- Runtime-only 客户控件当前值没有独立运行时持久化；M5.5.1 的 authoring persistence 只覆盖 Builder store，不能覆盖从生成 dylib `__ZNDATA` 解析出的 Runtime records。

### 实际修改

- 新分支 `fix/m5.8.2-single-runtime-ui-persistence`，基线 `bdda071fe30b8b18dec1f791ad9f65cca402e4a3`。
- 继续沿用唯一的 `ZNM58UnifiedControlRuntime` renderer，不新增第二套 Runtime UI/controller。
- Runtime 卡片按 `title + canonicalIdentity` 做显示层折叠，重复条目优先保留 exposed controls 更完整的一条；执行 tag 仍指向原始 `runtime.records` index，避免过滤后索引错位。
- `exposed == 0` 的固定参数 action 强制显示 `执行` 按钮。
- `ZNRangeControl` 在 begin/continue/end tracking 发送 `UIControlEventValueChanged`；M5.8.2 只用它更新同一 row 的数值 label，不触发 Invoke。
- Slider row 新增实时当前值 label；release 仍通过 `UIControlEventPrimaryActionTriggered` 单次执行。
- 新增 Runtime-only 客户值持久化 key `zonoe.m5.8.2.runtime-values.v1`，按 `actionID + canonicalIdentity` 保存 argumentValues；重新打开菜单时优先恢复持久化值。
- Switch/Slider/Number/Fixed 在真正执行前统一保存当前 argumentValues；不修改 Runtime Action 64-byte ABI。
- Footer 版本更新为 `0.5.8 · M5.8.2`。

### CI / Artifact

- Workflow `Build Runtime Patch Menu v0.5.8 M5.8.2 Single Runtime UI Persistence`
- Run `36361545700` / Job `108739561193`: Source Contract、Dobby arm64、Build、Binary Verify、Artifact Upload 全部 SUCCESS。
- HEAD `a8ffddf8eaee32a74d0be10dcae2cff6801b3e39`。
- Artifact ID `10945494700`。
- ZIP SHA256 `ec8deb778aee9431e7ddb903443f23fd2ea6423db649e378f17413ae82028239`。
- Dylib `ZonoPatch_v0.5.8_M5.8.2_SingleRuntimeUI_Persistence.dylib`，size `1404800` bytes，SHA256 `93cab80c56ada110f08f4f536633f0e1087f8132b9a7d830c182d3a4bc697572`。

### 验证边界

- Source/build/binary/artifact: PASS。
- 仅一套 Runtime UI、重复卡片折叠、固定项执行按钮、Slider 实时数值、重启恢复值：DEVICE PENDING。
- M5.8.1/M5.8 的历史 Runtime Slider 稳定性仍需本版真机回归。

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
