# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — v0.5.8-dev M5.2 Immediate Chain V2

Branch: `feature/runtime-patch-menu-v0.5.8-m5.2-immediate-chain-v2`

CI-validated product head: `2456f6ba4dfb659e3480db2e677452dad8516153`

实际修改：

- 先完成 M5.1 Customer Silent Execution：客户侧 Runtime 成功执行不再弹 `执行完成`；失败仍显示 `执行失败`；Builder / Method Finder 测试返回与调试信息不变。
- M5.1 Silent 基线最终通过 Run `35938495119`，产品 HEAD `29c33d9246fd9842107c443d3254aff23effd59e`。
- 从该绿色 HEAD 创建 M5.2 分支，不从失败构建继续开发。
- 新增 `ZNM52ImmediateChainV2.mm`：version=2 `nodes[]` 多级链、原子执行、每级 `/0-/8` typed args、exact signature preflight、token/return-type guard、per-level trace/log、null stop、best-effort managed exception detail、System.String UTF-16 解码。
- 新增 `ZNM52ChainStoreV2.mm`：V2 nodes 元数据校验/存储；V1 Immediate Chain 校验路径保持兼容。
- M5.2 每个节点复用现有 `ZNRuntimeMethodAction` + M4.6 Full Signature + M4.7 typed invoke + M4.8 return capture + M5.0 managed-reference GCHandle/receiver injection，不另造不兼容调用 ABI。
- 已确认 typed invoke 对 `0` 使用真实 value storage 地址，不会把 `0` 当成 null/unfilled。
- 已确认 enum ABI metadata 会解析 underlying primitive；本版可按数值 typed invoke，但 enum 名称下拉 UI 尚未实现。
- `System.String` 以前在 ObjectReference 路径只显示 `object 0x...`；M5.2 新增 `il2cpp_string_length` / `il2cpp_string_chars` 解码路径。
- MethodInfo/MethodPointer 只记录在当前执行 trace，不作为跨启动持久化身份；稳定校验使用完整 managed signature + token（可用时）+ return type，避免 ASLR 地址失效。
- Runtime Action ABI 仍为 version 1 / 64 bytes；V2 chain 仍通过 `reserved[4]` JSON 承载，无 ABI 扩容。
- M5.1 参数控件、客户成功静默、suffixless binary 输出均保留。
- 版本标识更新为 `0.5.8 · M5.2` / `Immediate Chain V2 · Multi-Level Typed Chain`。

CI 历史：

- M5.1 Silent 首轮：Build 因新文件漏引入 `ZNRuntimeActionFormat.h` 导致 `ZN_RUNTIME_ACTION_MAX_ARGUMENTS` 未定义；修复后 Run `35938495119` 全绿。
- M5.2 Run `35939148418`：Source Contract + arm64 Build/Link/Sign 成功；Binary Verify 因带 `·` 的 Objective-C feature 常量不能可靠被 `strings -a` 匹配而失败，产品代码未失败。
- M5.2 Final Run `35939364930` / Job `107443621364`：Source Contract、Build、Binary Verify、Artifact Upload 全部 SUCCESS。

最终制品：

- Artifact: `ZonoPatch-v0.5.8-M5.2-Immediate-Chain-V2`
- Artifact ID: `10784551336`
- Artifact ZIP size: `597403`
- Artifact ZIP SHA256: `334c56df627ff2a18cd8cf0572afd9848433808d1d9816d2c4c7c1c29a15dd3c`
- Dylib: `ZonoPatch_v0.5.8_M5.2_Immediate_Chain_V2.dylib`
- Dylib size: `1304480`
- Dylib SHA256: `84a9ff17e66ddb50c42893603b45123457d31ff3986655f07bc12748efef9d87`
- Mach-O: thin arm64 dynamically linked shared library
- Downloaded artifact ZIP/dylib hashes independently matched GitHub/CI.

验证边界：

- source implemented: YES
- GitHub committed: YES
- arm64 compile/link/sign: YES
- binary marker verification: YES
- artifact independent hash verification: YES
- customer silent success behavior on device: PENDING
- multi-level Chain V2 on device: PENDING
- System.String real-game decode: PENDING
- GCHandle/receiver continuity across 3+ chain levels: PENDING
- full regression: NO

## Historical anchors

- M5.1 Silent Customer Execution green product head: `29c33d9246fd9842107c443d3254aff23effd59e`.
- M5.0 Managed-reference Return Chaining product head: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`.
- M4.8 Return Capture has user device evidence for `System.Int32 = 1` boxed return decoding.
- Method Finder V3 M2.2 device-accepted anchor: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- v0.5.6.2 sealed baseline: `86edac4d70ef467e9a58912768b6c6c72077842a`.
