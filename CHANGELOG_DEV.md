# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-15 — v0.5.8-dev Method Finder V3 Milestone 2

Product source head: `69b546edd0ed83a5699805951304aa3371a0bc30`

实际修改：

- 从已真机通过的 V3 M1 独立切出 `feature/runtime-patch-menu-v0.5.8-method-finder-v3-m2`。
- 新增 `ZNIL2CPPMethodFinderM2.mm`，作为 M1 之后的增量层，不重写 Named Offset / M1 detail / Builder 语义。
- 裸方法名新增大小写不敏感宽泛搜索，优先级为 `exact > prefix > suffix > contains`。
- 结构化表达式继续 exact；RVA 反查继续 exact。
- 搜索移到后台 user-initiated queue；加入 UUID cancel token、分片进度与 Cancel UI。
- 首次宽泛搜索按 12,000-class shard 建立完整紧凑本地索引；取消时不保存半成品。
- 索引绑定 UnityFramework `LC_UUID + file size`，并以 binary plist 保存到 Cache。
- 索引只保存 Assembly/Namespace/Class/Method/argumentCount/RVA，不保存 Runtime VA/MethodInfo/Method Pointer。
- 使用去重字符串表 + 32-byte fixed record。
- 第二次宽泛搜索优先读索引，再通过已验证 M1 resolver 恢复当前 launch 的 MethodInfo/Pointer/Runtime VA。
- RVA 反查有索引时可用索引，无索引时回退到 M1 已真机验证路径。
- 为 M2 bridge 的 Objective-C category dependency 声明临时加入 `-Wno-incomplete-implementation`；运行时逻辑不变，封板前需清理。

CI / Build：

- Workflow: `Build Method Finder V3 via Main`
- Run: `34881764073`
- Result: `success`
- Artifact ID: `10363436049`
- Artifact ZIP SHA256: `f4cc5d6bdf1549cd0f35c7dd7341f355e1907c208bc8a6e4ae1ee7a694b9161e`
- Dylib SHA256: `77d1cd3fe30c403c5f5db35ee35fbce8fa4da5f62352be04474bbabe52f24784`
- Mach-O: thin arm64 dylib
- `__init_offsets == 4`: PASS
- M2 markers (`m2-wide-index`, `m2-wide-build`, `built-and-saved`): PASS
- Independent post-download ZIP/dylib hash + Mach-O constructor recheck: PASS

验证边界：

- M2: source implemented / CI compiled / binary verified.
- M2: 尚未真机验证。

## 2026-09-15 — v0.5.8-dev Method Finder V3 Milestone 1 device acceptance

- M1 user real-device acceptance passed.
- `get_TotalCashReward` candidate list works.
- Known target `Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0` detail resolves RVA `0x2DA9E10`.
- `0x2DA9E10` reverse lookup works.
- Qualified lookup works.
- Candidate detail/copy flow works.
- `Create Patch` preserves the selected full canonical expression instead of the ambiguous original bare query.
- M1 tested paths are DEVICE-VERIFIED; M1 is not marked sealed/release.

## 2026-09-13 — v0.5.1 Static RVA Protection V1

Runtime code head: `7360f72c8e27b6e3da5c70f6394f2fac17cd6ba5`

实际修改：

- 新建分支 `feature/runtime-patch-menu-protection-v1`。
- 新增 `ZNStaticRVAProtection.h/.mm`。
- `ZN44StaticHeader` 新增 `ZN44_STATIC_HEADER_FLAG_RVA_PROTECTION_V1`；不改变 64-byte Header / 128-byte Entry ABI。
- generated Mach-O 的 `siteRVA / offRVA / onRVA` 在 ZNF1 之后、签名前使用每输出随机 nonce 编码。
- header `reserved[0..3]` 在 Protection flag 下用于 nonce / integrity tag / marker / seal。
- Runtime 支持 protected 与 legacy 两种格式；protected entry 按需解码，不回写明文 RVA。
- Runtime 在接受 protected header 前进行完整性校验，编码字段被篡改时拒绝该 header。
- `setEnabled` 使用 Runtime record 中已解码的 transient RVA，不再直接读取 protected Static Entry 的 `offRVA/onRVA`。
- 普通 Static Dispatch 日志和 diagnostics 去掉直接 RVA 输出。
- `build_report.json` 新增 `generatedBinaryProtection`，声明 protected fields、nonce、integrity check 和 runtime decode 行为。
- Compact UI subtitle 更新为 `0.5.1`；此前的 `开/关`、ZNF1、opaque plist key 和旧 Registry 清理保持不变。

CI / Build：

- Workflow: `Build Runtime Patch Menu Protection V1`
- Final run: `34711600783`
- Result: `success`
- Artifact id: `10303452675`
- Artifact digest: `sha256:93ddde469ef412ace612b73899b4a7f3f6b35a3383c3648a202b964bd55c4d36`
- Dylib SHA256: `ccc458c3697bddb2e66831a0e92dcc5e8dd10a2e1ded1fe5697e06807732764d`

验证：

- Source assertions: PASS。
- Feature metadata codec tests: PASS。
- Static RVA Protection tests: PASS。
- Theos build: PASS。
- Binary verify: PASS。
- Artifact upload: PASS。
- RVA protection test 已覆盖：128-byte ABI、shared site、编码后字段不等于明文、精确 round-trip、legacy passthrough、tamper detection。
- 实机生成 `.znpatched` 与运行行为：尚待验证。

安全边界：

- Protection V1 是静态分析成本层，不宣称客户端秘密不可提取。
- Patch Variant 仍位于 `__ZNTEXT`，本阶段没有对 Patch payload 本体做加密/变换保护。
- 动态调试环境仍可能观察 Runtime 解码后的地址。

## 2026-09-13 — Compact Public UI + plist privacy cleanup

- Public UI 默认 Compact；按钮显示 `开 / 关`。
- 废弃并启动清除 `zonoe.feature-name-registry.v1`。
- Feature 状态仅保存为 `zn.f.%016llx.enabled -> BOOL`。
- CI run `34708549712` success。

## 2026-09-12 — FeatureID metadata stage

- 引入 ZNF1 Feature metadata codec。
- generated Mach-O 以 FeatureID + encoded display name 保存显示信息，保留 128-byte Static Entry ABI。
- UI 优先从 ZNF1 解码功能名。

## 2026-09-12 — v0.5.0 Privacy UI Test

- Public Feature UI 收敛为显示名称 + 开关。
- 初版 NSUserDefaults Feature Name Registry 已由 ZNF1 取代并在当前版本停用/清理。
