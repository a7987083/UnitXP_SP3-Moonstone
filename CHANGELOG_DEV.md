# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-12 — Embedded FeatureID metadata fix

Branch: `feature/runtime-patch-menu-feature-id-map`

CI baseline: `118a12c1febf3d693e5cb8e18b8e21cf6b008f01`

实际修改：

- 从 `feature/runtime-patch-menu-privacy-ui` 后继状态建立独立开发分支，不改写 `908e27a...` 历史基线。
- 新增 `iosruntimepatchmenu/src/ZNFeatureMetadataCodec.h/.mm`。
- 新增 `ZN44_STATIC_HEADER_FLAG_FEATURE_METADATA_V1`，保持 `ZN44StaticEntry` 128-byte ABI 不变。
- 将 Static Entry 原 `title[48] + group[24]` 72 字节区域改造成 ZNF1 opaque metadata transport：保存 stable FeatureID + 编码后的显示名。
- `title[0]` 和 `group[0]` 固定为 0，使旧 Runtime 读取时安全 fallback，不会把编码数据误当字符串。
- Explicit Feature group 的 FeatureID 对 Patch 顺序、RVA 和 target 不敏感；同名显式 Feature 可跨 target 聚合。
- Legacy/no-group Patch 的 ID 纳入 target/RVA/patchID，避免同名 legacy 条目错误合并。
- `ZNStaticMetadataPrivacy.mm` 从“单纯把 title/group 清零”升级为“将明文转换为 ZNF1 metadata”，并支持对已编码 entry 的幂等校验。
- `ZNFeatureGroupUI.mm` 优先 `ZNFeatureMetadataDecodeEntry`，按 FeatureID 聚合并显示解码名称；旧 `ZNFeatureNameRegistry` 和 legacy entry 仅作兼容 fallback。
- `ZNStaticBinarySigningBridge.mm` 更新 build report：新产物的真实名称来源为 generated Mach-O encoded metadata；`NSUserDefaults` 仅保留旧版兼容缓存。
- `iosruntimepatchmenu/Makefile` 接入 codec。
- 新增 workflow `.github/workflows/build-runtime-patch-menu-feature-id-map.yml`。
- 新增 `iosruntimepatchmenu/tests/feature_metadata_codec_test.mm`。

验证：

- 首轮 workflow run `34705255653`：SUCCESS，确认 Theos 编译、符号和 artifact 输出正常。
- 第二轮 workflow run `34705353421`：SUCCESS。
- Codec unit test：SUCCESS。
- 单测确认 `Unlimited Cash` 编码后 raw 72-byte metadata 中不存在明文；Runtime decode 可恢复原名。
- 单测确认中文 `无限金币` round-trip 正常且 raw metadata 中不存在 UTF-8 明文。
- 单测确认同一 explicit Feature 在不同 target/RVA/patchID 下 FeatureID 一致。
- 单测确认 legacy/no-group 相同 label 的不同 Patch 不会得到同一 FeatureID。
- Theos arm64 build：SUCCESS。
- Artifact: `ZonoPatch-v0.5.0-FeatureIDMap-Test`。
- Run `34705353421` artifact id: `10301438907`。
- Artifact digest: `sha256:e226fb1e3e3fcaa3aadb224ca518a99159d10df02cfee322aa4b21b04b13b6a5`。

尚未验证：

- 真实 App 内 Builder 生成 `.znpatched` 后的 ZNF1 raw metadata。
- 真实 generated target 的 `strings` 明文检查。
- 最终 IPA 重签/重装后功能名称是否稳定恢复。
- 用户当前“全部显示功能”现象是否还包含 JSON Import / Feature Builder 上游名称污染问题。

## 2026-09-12 — Project state documentation

实际修改：

- 新增 `ROADMAP.md`。
- 新增 `CHANGELOG_DEV.md`。
- 新增 `HANDOFF.md`。
- 新增 `PROJECT_STATE.json`。
- 新增 `KNOWN_ISSUES.md`。
- 明确 `908e27a...` 是 Runtime code baseline，后续文档 Commit 不改变该代码基线定义。

验证：仅文档/状态文件修改；不改变当时 Runtime 源码、Makefile 或构建逻辑。

## 2026-09-12 — v0.5.0 Privacy UI Test

Runtime code baseline: `908e27a36fa55a3e63e1ab55db5968fb5da12fde`

实际实现：Public Feature UI 收敛为“显示名称 + 开关”；首次 Privacy 设计将 generated target 的 title/group 清零并把显示名保存到 Host-side `NSUserDefaults` Registry；generated binary 后处理执行 ad-hoc CodeDirectory 重建与校验。

CI：Run `34688640962` / SUCCESS；Artifact `ZonoPatch-v0.5.0-PrivacyUI-Test` / id `10296920465` / digest `sha256:14093c8c04a6027fca1c2d92465f7c1874a9e7d705cd902a9691ec3cf4523b63`。

后续确认该 Registry 方案存在跨 reinstall / App Container 生命周期的设计风险，因此进入 Embedded FeatureID metadata 修复阶段。

## 2026-09-12 — v0.5.0 Consolidated baseline

Stable point: `121cc7c098b2d6f122a9c91a411a442edd3eaf68`。

已确认 CI 成功阶段包含 generated binary signer / CodeDirectory rebuild / sign-and-verify 路径。该 Commit 作为 Privacy UI 阶段的前置稳定基线，不改写。
