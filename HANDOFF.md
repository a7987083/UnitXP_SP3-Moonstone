# HANDOFF

## 当前上下文

当前工作线：ZonoPatch Runtime Patch Menu `v0.5.1 Static RVA Protection V1`。

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/runtime-patch-menu-protection-v1`
- Runtime code head: `7360f72c8e27b6e3da5c70f6394f2fac17cd6ba5`
- CI run: `34711600783` / `success`
- Artifact id: `10303452675`
- Artifact digest: `sha256:93ddde469ef412ace612b73899b4a7f3f6b35a3383c3648a202b964bd55c4d36`
- Dylib SHA256: `ccc458c3697bddb2e66831a0e92dcc5e8dd10a2e1ded1fe5697e06807732764d`

## 关键实现

### ZNF1 display metadata

功能名继续由 `ZNFeatureMetadataCodec` 以 FeatureID + encoded UTF-8 payload 存进原有 title/group 区域；Runtime 恢复显示名。旧 `zonoe.feature-name-registry.v1` 不再读写，并在启动时清理。

### Static RVA Protection V1

`ZNStaticRVAProtection.h/.mm` 对 generated target Mach-O 的 `siteRVA / offRVA / onRVA` 做原地可逆编码：

- 每个生成输出使用随机 nonce。
- key 派生同时绑定 entry index、patchID、physicalID、canonicalIndex、flags、window/enabled length。
- header reserved 区保存 nonce / plaintext-derived integrity tag / marker / seal。
- `ZN44StaticEntry` 保持 128 bytes，旧格式无 Protection flag 时仍按原值读取。
- Runtime 用 `ZN55DecodeEntryRVAs()` 按需解码，并将 transient 值放进 Runtime record；不会把明文 RVA 写回 Static Entry。
- protected header 完整性验证失败时 Runtime 忽略该 header。

### Signing / generation 顺序

当前后处理：

`Builder V3 -> ZNF1 -> Static RVA Protection V1 -> ad-hoc CodeDirectory rebuild/verify -> final IPA resign required`

### Public UI / plist

- Compact Public UI 默认开启，subtitle `0.5.1`。
- UI 状态：全开=`开`、全关=`关`、部分开启=`MIXED`。
- Feature 状态 key：`zn.f.%016llx.enabled`，value 为 BOOL。
- 不在 Preferences 中保存 Target/RVA/Patch bytes/显示名称映射。

## CI 已验证

Run `34711600783`：source assertions、ZNF1 codec tests、Static RVA Protection tests、Theos build、binary verify、artifact upload 全部成功。

Protection 单测覆盖：shared site、编码字段不等于明文、精确 round-trip、legacy passthrough 和 tamper detection。

## 接手注意事项

- Protection V1 不是密码学秘密方案；它的目标是破坏“直接按 Static Entry 结构批量读 RVA”的低成本路径。
- 仓库当前是公开的，因此确定性分析者可以研究编码逻辑；不要声称 RVAs 绝对不可恢复。
- `__ZNTEXT` 中的 relocated Original/ON Variant 仍是下一阶段 Patch Payload Protection 范围。
- 动态调试仍可能看到 Runtime 已解码地址；客户端侧无法保证绝对不可观察。
- ZNF1 FeatureID 当前仍可由名称推导，不是随机稳定 128-bit authoring ID。
- Generated binary 仍需最终 IPA 整包重签。
- 目前 Protection V1 只有 CI/单元测试证据，还没有真实目标 `.znpatched` 与实机证据。

## Next Task

用 v0.5.1 dylib 重新生成真实目标 `.znpatched`，同时取得 `build_report.json`。检查 Static Entry 的三个 RVA 字段确实不再等于真实地址，并做 Shared Site、开关、冷启动与最终 IPA 重签验证。通过后进入 Patch Payload Protection V2。
