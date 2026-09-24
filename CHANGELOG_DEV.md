# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.6 Stable Runtime Slider + Static RW Value Cell V1

### 真机根因

- Static Number/Auto 真机失败：`恢复 RX 权限失败 errno=13 (Permission denied)`。确认旧 M5.5 运行时修改 ON variant executable page 的方案在当前环境不可用。
- Runtime Slider 一拖即卡死/闪退。源码确认 M5.5 typed wrapper 在每次 `UIControlEventValueChanged` 都执行 `ZNRuntimeActionRuntime refresh`；旧 M5.1 仅缓存，M5.3 原设计本应只在松手执行。

### 实际修改

- 新增 `ZNM551RuntimeSliderStability.mm`：拖动只走轻量 cache；TouchUp/Cancel 时 refresh 一次、量化一次、缓存一次、Invoke 一次。
- 新增 `ZNStaticValueCellV1.mm/.h`：构建期把 Number/Slider 的 MOVZ(+MOVK) / scalar FMOV ON variant 参数化为 LDR W/X/S/D，从 owned `__ZNDATA` RW cell 取值。
- 新增 `ZNM56StaticValueCellBinding.mm`：运行时只 atomic store RW value cell，再通过原 Static Dispatch `selectedTarget` 启用 ON variant。
- M5.6 runtime 不再通过 `ZNRuntimePatchExecutor` 修改 Static typed executable instructions。
- Value Cell postprocess 顺序：ZNF1 -> RW Value Cell -> RVA Protection -> Ad-hoc Sign -> Suffixless Export。
- 新增 Header/Entry value-cell flags；Static Entry 仍为 128 bytes，Runtime Action Entry 仍为 64 bytes。
- 版本改为 `0.5.8 · M5.6` / `Stable Runtime Slider · Static RW Value Cell V1`。

### CI / Artifact

- Run `36004751812` / Job `107649917061`: Source Contract、Dobby arm64、Build M5.6、Binary Verify、Artifact Upload 全部 SUCCESS。
- Artifact ID `10809323261`。
- ZIP SHA256 `fc1f0596f2f603a993d2249e9ab1c965e5ff38019fcda3d5d4a75a189ecf2c03`。
- Dylib size `1421376` bytes。
- Dylib SHA256 `191c93dea1fc43d504860abcfd047fcf15391c6ad74c39be383f299eaa7cf54c`。
- 独立下载 ZIP digest 与 GitHub digest 一致；Artifact `SHA256.txt` 与 dylib 本地 hash 一致。

### 验证边界

- arm64 source/build/binary/artifact: PASS。
- Runtime Slider 真机修复：PENDING。
- Static RW Value Cell 真机修复：PENDING；必须用 M5.6 重新生成目标二进制，旧 M5.5 生成物没有 cell，不能作为此项测试对象。

## 2026-09-24 — M5.5.1 Recovery

- 恢复 M5.4 Builder 基线、调整删除按钮间距、增加 Runtime authoring 持久化 `zonoe.m5.5.authoring-actions.v1`。
- Run `36002343325` / Job `107641806291` SUCCESS。
- Dylib SHA256 `bf3ffc1c75c27bae19a6d03a7e6dc93d5e23c9953143fb024267f8705d679453`。

## Historical anchors

- M5.5 Typed Control initial: Run `35996840472`, dylib `0dacef0f731d0a6b59e1446b08977d69a6eeb732096c761a9ed321be0214375a`.
- M5.4 Unified: Run `35964757740`, head `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845`.
- M5.3 Control Binding: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`.
- M5.2 Chain V2: `2456f6ba4dfb659e3480db2e677452dad8516153`.
