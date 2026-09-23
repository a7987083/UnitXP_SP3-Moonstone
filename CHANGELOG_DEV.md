# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — v0.5.8-dev M5.1 Runtime Arg Controls + Immediate Chain V1

Branch: `feature/runtime-patch-menu-v0.5.8-m5.1-runtime-arg-controls-immediate-chain-v1`

CI-validated product head: `c24b77ee709cec477a5a94b8a35f98c38a459f97`

实际修改：

- Runtime Method Builder 参数从“客户执行时全部弹窗编辑”改为“开发者逐参数决定是否暴露”。
- `/1-/8` 每个参数新增 Runtime enable 状态；未启用参数继续使用固定值。
- 启用参数复用现有四类控件：Switch / Button / Number / Slider。
- Runtime Action model 新增 `argumentControlConfigs` 与 `immediateChain`。
- Runtime Action ABI 保持 64 bytes/version 1；`reserved[3]` 为参数控件 JSON，`reserved[4]` 为 Immediate Chain JSON，`reserved[1]` Full Parameter Signature 保持不变。
- Runtime parser / generated menu 已读取参数控件元数据；客户侧只渲染被启用参数。
- Method Finder 每个结果的 `创建方法` 下方新增 `链式调用`。
- Immediate Chain V1：主方法返回 managed-reference 后，立即复用 M5.0 receiver chain 执行第二跳 `/0` 方法；不持久化返回对象地址或 GCHandle。
- Runtime-only Builder 最终输出改为原 Mach-O 文件名，无 `.znpatched` 后缀。
- Static Builder 保持 `.znpatched` 内部 staging 逻辑，后处理/保护/签名完成后再重命名为原 Mach-O 文件名，避免破坏稳定 Builder。
- M5.1 版本标识更新为 `Runtime Arg Controls + Immediate Chain`。

CI 历史：

- Run `35932002733`：首次编译在新 M5.1 UI 的 Objective-C `id` 类型推断处失败，已修复。
- Run `35932508611`：产品代码编译/链接/签名通过；Binary Verify 因 `strings` 对中文断言不可靠而失败，已改为 ASCII marker。
- Final Run `35932826187` / Job `107423107248`：Source Contract、arm64 Build、Binary Verify、Artifact Upload 全部 SUCCESS。

最终制品：

- Artifact: `ZonoPatch-v0.5.8-M5.1-Runtime-Arg-Controls-Immediate-Chain-V1`
- Artifact ID: `10781652685`
- Artifact ZIP size: `581621`
- Artifact ZIP SHA256: `76f812e245aa2bd45084f732485737df9a781af55bfc95d19f8e3aa468588ac8`
- Dylib: `ZonoPatch_v0.5.8_M5.1_Runtime_Arg_Controls_Immediate_Chain_V1.dylib`
- Dylib size: `1287760`
- Dylib SHA256: `b0ec99af081edbd1612d27aa2a6cdadb83451dc6301f4097fb2555735ef1544e`
- Mach-O: thin arm64 dynamically linked shared library
- Downloaded artifact ZIP/dylib hashes independently matched GitHub/CI.

验证边界：

- Source implemented: YES
- GitHub committed: YES
- arm64 compile/link/sign: YES
- binary marker verification: YES
- artifact downloaded + independent hash verification: YES
- real-device Runtime argument-control behavior: PENDING
- real-device Immediate Chain behavior: PENDING
- actual generated suffixless `UnityFramework` fixture/device verification: PENDING
- full regression: NO

## Historical anchors

- M5.0 Managed-reference Return Chaining product head: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`.
- M4.8 Return Capture has user device evidence for `System.Int32 = 1` boxed return decoding.
- M4 Runtime Method Call V1 has user device evidence for `/0` create/test/generated-binary basic path.
- Method Finder V3 M2.2 device-accepted anchor: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- v0.5.6.2 sealed baseline: `86edac4d70ef467e9a58912768b6c6c72077842a`.
