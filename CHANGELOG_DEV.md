# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.6.2 Runtime/Static Recovery

### 真机反馈

- Static Number/Auto 仍出现 `恢复 RX 权限失败 errno=13 (Permission denied)`。
- Runtime Slider 仍然一拖就卡死/闪退。
- 新建 Static Number，Auto 解析为 F32 后，客户端无论怎么改都一直表现为 0。
- Runtime-only（无完整 Offset Patch）存在误走 Static/Mixed 后处理的风险。

### 审计纠正

- 审计当前分支确认：此前所谓 M5.6 RW Value Cell 并未真正成为最终唯一运行路径；后续 `M5.6.1-regression` 又恢复了 M5.3 executable-page typed writer，并停用了 value-cell runtime owner/postprocess。
- 因此此前“M5.6 已完整切换 RW cell”的结论不成立；M5.6.2 重新完成生成端和运行端的闭环。

### 实际修改

- `ZNStaticBinaryPipeline.mm`：Runtime-only 判定从 `workspace.filledCount == 0` 改为完整 Static 行计数（Offset 与 Enabled 同时存在）。半填/残留行不再改变 Runtime-only 模式。
- `ZNGeneratedBinaryPostprocess.mm`：恢复 `ZNF1 -> RW Value Cell V1 -> RVA Protection -> Ad-hoc Sign` 顺序。
- `ZNStaticValueCellV1.mm`：Static Number/Slider 在构建期把 MOVZ(+MOVK) / scalar FMOV 参数化为 LDR W/X/S/D + owned `__ZNDATA` RW cell。
- `ZNIL2CPPMethodFinderMenuBinding.mm`：安装 M5.3 后显式移除 `ZNM53StaticControlBinder` / `ZNM55StaticTypedBinder` observer，再安装 `ZNM56StaticValueCellBinder`，确保 Static Number/Slider 单一 owner。
- `ZNM562SliderIsolation.mm`：最终替换 `zn51_runtimeSliderChanged:`。拖动只更新/整数化 UISlider，不 refresh、不 render、不 Invoke、不追加 release target。
- M5.6.2 的 Runtime Slider 暂时改为“拖动只改值，用户点 Runtime 卡片右上 `执行` 才调用”，用于隔离 Slider UI 与 Runtime F32 Invoke。
- 版本更新为 `0.5.8 · M5.6.2`。

### CI / Artifact

- Run `36012593002` / Job `107676813892`: Source Contract、Dobby arm64、Build M5.6.2、Binary Verify、Artifact Upload 全部 SUCCESS。
- Artifact ID `10812584568`。
- ZIP SHA256 `48662e7ffdc798d18358b443a6996214e3eb37e2a9fc005232e7afd7ab533aeb`。
- Dylib size `1421392` bytes。
- Dylib SHA256 `d6657fdc723b1b1ca68637dac63ec66f3f95d3a0cade6f5066361215dd6588c7`。
- Mach-O: thin arm64 dylib。
- 独立下载 ZIP hash 与 GitHub digest 一致；dylib hash 已本地复核。

### 验证边界

- source/build/binary/artifact: PASS。
- Runtime Slider UI-only drag: device PENDING。
- Runtime Slider explicit Execute using current slider value: device PENDING。
- Runtime-only generation without complete Static row: device PENDING。
- Static MOV Number RW-cell behavior: device PENDING，必须重新生成目标二进制。
- Static F32/F64 value-cell behavior: device PENDING，必须重新生成目标二进制。

## 2026-09-24 — M5.6 Initial Attempt

- Run `36004751812` compiled and uploaded successfully, but later audit/device evidence showed the intended RW-cell architecture was not the final active runtime path because a regression path restored M5.3 executable writes. Treat this build as superseded by M5.6.2.

## 2026-09-24 — M5.5.1 Recovery

- 恢复 M5.4 Builder 基线、调整删除按钮间距、增加 Runtime authoring 持久化 `zonoe.m5.5.authoring-actions.v1`。
- Run `36002343325` / Job `107641806291` SUCCESS。
- Dylib SHA256 `bf3ffc1c75c27bae19a6d03a7e6dc93d5e23c9953143fb024267f8705d679453`。

## Historical anchors

- M5.5 Typed Control initial: Run `35996840472`, dylib `0dacef0f731d0a6b59e1446b08977d69a6eeb732096c761a9ed321be0214375a`.
- M5.4 Unified: Run `35964757740`, head `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845`.
- M5.3 Control Binding: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`.
- M5.2 Chain V2: `2456f6ba4dfb659e3480db2e677452dad8516153`.
