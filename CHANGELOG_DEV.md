# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.2 Finder UX closure

Branch: `feature/runtime-patch-menu-v0.5.8-m5.2-immediate-chain-v2`

CI-validated product head: `2d36ffcc333936e41809039e161baf52e24abba9`

实际修改：

- 修复 Chain V2 创建后的 UI 断链：此前 `完成链` 只保存 metadata + render，没有后续 `执行链` 操作入口。
- 新增 `ZNM52ChainExecuteButton.mm`。
- Finder 当前方法未有 V2 chain 时保持 `链式调用`；存在已保存 V2 chain 时原按钮原位变为 `执行链`。
- 单击 `执行链` 调用现有 M5.2 原子执行器并在开发/测试侧展示最终 return + chainTrace。
- 长按 `执行链` 清空当前 action 的 Immediate Chain，并立即重新进入该方法的链式调用编辑器。
- 新增 `ZNM52MethodSearchHistory.mm`。
- 方法搜索关键词通过 NSUserDefaults 持久化；最多 50 条；大小写不敏感去重；最新置顶；超限删除最旧。
- 搜索历史直接显示在搜索框下面；一行一条；独立 UIScrollView；点击历史项直接回填并重新搜索。
- Makefile 和 Method Finder deferred install 顺序已接入两个新模块。

CI 历史：

- Run `35944059425` / Job `107458000802`：Source Contract 通过；Build 在新 category selector 声明位置触发 `-Werror,-Wobjc-protocol-method-implementation`，已定位并修复。
- Final Run `35944304515` / Job `107458736244`：Source Contract、arm64 Build、Binary Verify、Artifact Upload 全部 SUCCESS。

最终制品：

- Artifact: `ZonoPatch-v0.5.8-M5.2-Immediate-Chain-V2`
- Artifact ID: `10785804614`
- Artifact ZIP size: `602942`
- Artifact ZIP SHA256: `6596398f82a733fbe901be42e18960da3c4d212f479e7f73cf8253be7fbf210f`
- Dylib: `ZonoPatch_v0.5.8_M5.2_Immediate_Chain_V2.dylib`
- Dylib size: `1321136`
- Dylib SHA256: `44eb45dd5643c8256bc0393c0117dc56a5b8836d2ef0a019a28cafb6a97d68d7`
- Mach-O: thin arm64 dynamically linked shared library
- Downloaded ZIP hash matches GitHub Artifact digest; dylib hash matches CI `SHA256.txt`.

验证边界：

- source implemented: YES
- GitHub committed: YES
- arm64 compile/link/sign: YES
- Binary Verify: YES
- artifact independent hash verification: YES
- `链式调用 -> 执行链` 真机状态切换: PENDING
- 单击执行链 / 长按重建链: PENDING
- 50 条持久化搜索历史 UI: PENDING
- full regression: NO

## Historical anchors

- M5.2 core multi-level-chain green product head: `2456f6ba4dfb659e3480db2e677452dad8516153`.
- M5.1 Silent Customer Execution green product head: `29c33d9246fd9842107c443d3254aff23effd59e`.
- M5.0 Managed-reference Return Chaining product head: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`.
- Method Finder V3 M2.2 device-accepted anchor: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
