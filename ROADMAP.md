# ROADMAP

## 当前阶段

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.1`
- Branch: `feature/runtime-patch-menu-protection-v1`
- Stage: `Static RVA Protection V1`
- Runtime code head: `7360f72c8e27b6e3da5c70f6394f2fac17cd6ba5`
- CI: GitHub Actions run `34711600783` — `success`
- Artifact: `ZonoPatch-v0.5.1-ProtectionV1-Test`

## 已完成

- 保留 v0.5.0 的 ZNF1、Compact Public UI、`开/关` 文案和 plist 隐私清理。
- 新增 `Static RVA Protection V1`，对 generated Mach-O 的 `siteRVA / offRVA / onRVA` 做每输出 nonce 的可逆编码。
- Runtime 按需解码，不把明文 RVA 写回 `ZN44StaticEntry`。
- 保持 `ZN44StaticEntry` 128-byte ABI 不变；旧无 Protection flag 的 `.znpatched` 仍兼容读取。
- Protected header 增加完整性 tag / marker / seal，篡改编码字段会导致 Runtime 拒绝该 header。
- 普通 runtime 日志/diagnostic 不再直接输出 siteRVA。
- Signing Bridge 顺序为：ZNF1 -> RVA Protection V1 -> ad-hoc CodeDirectory rebuild/verify。
- CI 增加 RVA round-trip、legacy passthrough、shared-site 和 tamper-detection 单元测试。

## 下一阶段 — Device Validation + Patch Payload Protection V2

Status: `NEXT`

目标：

- 用 v0.5.1 实机生成新的 `.znpatched`，确认原始 `siteRVA/offRVA/onRVA` 不再能直接从 Static Entry 读取。
- 验证菜单功能、Shared Site、冷启动状态恢复和最终 IPA 重签不回归。
- 检查 `build_report.json` 的 `generatedBinaryProtection` 证据。
- 继续处理 `__ZNTEXT` 中 Patch Variant 的静态恢复成本；V1 尚未保护 Patch payload 本体。
- 评估把名称派生的 FeatureID 升级为随机稳定 authoring identity。

## Next Task

安装 `ZonoPatch_v0.5.1_ProtectionV1_Test.dylib`，重新生成目标 `.znpatched`。把 `.znpatched` 与 `build_report.json` 发回检查 Static Entry 编码、Shared Site、CodeDirectory 和运行时切换；通过后进入 Patch Payload Protection V2。
