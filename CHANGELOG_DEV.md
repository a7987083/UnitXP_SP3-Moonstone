# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — v0.5.8-dev M5.3 Control Binding V1

Branch: `feature/runtime-patch-menu-v0.5.8-m5.3-control-binding-v1`

CI-validated product head: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`

实际修改：

- 从 M5.2 HistoryFix 绿色基线 `88ee27688ac5db067caded06da2feefb77323340` 创建 M5.3 分支。
- 新增 `ZNM53ControlBinding.mm`，作为最外层 Control Binding。
- Runtime 参数控件行为闭环：
  - Button：原点击路径立即 invoke。
  - Switch：`ValueChanged` 后立即 invoke。
  - Number：编辑期间只更新值，结束编辑后立即 invoke。
  - Slider：拖动期间只更新/量化值，TouchUp/Cancel 时执行一次最终 invoke。
- Runtime 自动执行仍走现有 `zn51_runtimeExecute:`，因此继续复用参数合成、typed invoke、full signature、Immediate Chain 及 M5.1 Silent Customer Execution；成功静默、失败可见。
- Static Button 从“只发 Notification”绑定到真实 `setEnabled:YES` 固定 Enabled variant。
- Static Number/Slider 新增 ARM64 `MOVZ(+MOVK...)` 动态绑定：
  - 从 Static Dispatch record 读取 Protection V2 ON entry；
  - 解析碎片链中的 Enabled 指令地址；
  - 要求首指令为 MOVZ，后续仅接受同宽度/同目标寄存器 MOVK；
  - 按客户整数值改写 imm16 halfword；
  - 缺少所需 MOVK 槽位或不是可识别序列时 fail closed；
  - 通过 `ZNRuntimePatchExecutor` 做 expected-byte 校验、RX→RW、写入、read-back、失败回滚；
  - 写入时临时关闭匹配 Static record，成功后重新启用，减少修改正在执行 ON variant 的风险。
- Static Slider 采用 120ms generation debounce，避免每一个 ValueChanged 都写入。
- Static V1 只接受非负整数；W 最大 UINT32 范围但仍受 MOVK 槽位限制；X 为保证 NSNumber/double 精确性限制到 `2^53-1`。
- 未修改 Static 128-byte Entry ABI，也未修改 Runtime 64-byte Action ABI。
- 版本标识更新为 `0.5.8 · M5.3` / `Control Binding · Runtime Auto Execute · Static Dynamic MOV`。

CI：

- Run `35951498398` / Job `107480818078`：Source Contract、Dobby arm64、Build M5.3、Binary Verify、Artifact Upload 全部 SUCCESS。

最终制品：

- Artifact: `ZonoPatch-v0.5.8-M5.3-Control-Binding-V1`
- Artifact ID: `10788349821`
- Artifact ZIP size: `610100`
- Artifact ZIP SHA256: `80a2461b89ad5625d03d86407ad8ec5ea9854cde46422485d08e1037232fd777`
- Dylib: `ZonoPatch_v0.5.8_M5.3_Control_Binding_V1.dylib`
- Dylib size: `1337776`
- Dylib SHA256: `e4ed0643ed7cf8aceb89f93f06c40f41442f4f12a64b1d8bcd7970765df7b98b`
- Mach-O: thin arm64 dynamically linked shared library
- 独立下载后 ZIP digest 与 GitHub Artifact digest 一致，dylib hash 与 CI `SHA256.txt` 一致。

验证边界：

- source implemented: YES
- GitHub committed: YES
- arm64 compile/link/sign: YES
- Binary Verify: YES
- artifact independent hash verification: YES
- Runtime 四控件自动执行真机验证: PENDING
- Static Button 真机绑定验证: PENDING
- Static MOVZ/MOVK Number/Slider 真机动态值验证: PENDING
- 非越狱/受限签名环境下 executable-page RX→RW 是否允许: PENDING；失败时应 fail closed
- full regression: NO

## Historical anchors

- M5.2 HistoryFix baseline: `88ee27688ac5db067caded06da2feefb77323340`.
- M5.2 core multi-level chain: `2456f6ba4dfb659e3480db2e677452dad8516153`.
- M5.1 Silent Customer Execution: `29c33d9246fd9842107c443d3254aff23effd59e`.
- M5.0 Managed-reference Return Chaining: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`.
