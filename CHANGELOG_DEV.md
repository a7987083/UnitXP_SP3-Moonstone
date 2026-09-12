# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-12 — Project state documentation

实际修改：

- 新增 `ROADMAP.md`。
- 新增 `CHANGELOG_DEV.md`。
- 新增 `HANDOFF.md`。
- 新增 `PROJECT_STATE.json`。
- 新增 `KNOWN_ISSUES.md`。
- 明确 `908e27a...` 是 Runtime code baseline，后续文档 Commit 不改变该代码基线定义。

验证：

- 仅文档/状态文件修改；不改变 Runtime 源码、Makefile 或构建逻辑。

## 2026-09-12 — v0.5.0 Privacy UI Test

Runtime code baseline: `908e27a36fa55a3e63e1ab55db5968fb5da12fde`

相对 Consolidated baseline `121cc7c098b2d6f122a9c91a411a442edd3eaf68`：

- 关系：`ahead`
- Commit 数：9
- 新增 `.github/workflows/build-runtime-patch-menu-privacy-ui.yml`。
- 修改 `iosruntimepatchmenu/Makefile`。
- 修改 `iosruntimepatchmenu/src/ZNFeatureGroupUI.mm`。
- 新增 `ZNFeatureNameRegistry.h/.mm`。
- 修改 `ZNStaticBinarySigningBridge.mm`。
- 新增 `ZNStaticMetadataPrivacy.h/.mm`。

实际实现：

- Public Feature UI 收敛为“显示名称 + 开关”。
- UI 显示名优先走 Host-side Feature Name Registry，并保留旧生成二进制的 metadata fallback。
- Generated binary 后处理会在 `__ZNDATA` 中寻找 Static Dispatch metadata，并将每个 entry 的 `title/group` 清零。
- 隐私清理成功后执行 ad-hoc Mach-O 重签；所有输出成功后才提交 Feature Name Registry，避免失败构建留下 stale registry entry。
- `build_report.json` 增加 `generatedBinarySignature` 与 `generatedBinaryPrivacy` 证据字段。
- Feature group toggle 支持 ON/OFF/MIXED；批量切换失败时按已修改记录逆序回滚。

CI / Build：

- Workflow: `Build Runtime Patch Menu Privacy UI`
- Run: `34688640962`
- Result: `success`
- Artifact: `ZonoPatch-v0.5.0-PrivacyUI-Test`
- Artifact id: `10296920465`
- Artifact digest: `sha256:14093c8c04a6027fca1c2d92465f7c1874a9e7d705cd902a9691ec3cf4523b63`
- Artifact expired: `false` at capture time

验证等级：

- 已修改：YES
- 已编译：YES（GitHub Actions / Theos）
- 已做 CI 静态验证：YES
- 已运行：CI build/verify steps only
- 已实机验证：NOT RECORDED
- 已完整回归验证：NOT RECORDED

## 2026-09-12 — v0.5.0 Consolidated baseline

Stable point: `121cc7c098b2d6f122a9c91a411a442edd3eaf68`

已确认 CI 成功阶段包含 generated binary signer / CodeDirectory rebuild / sign-and-verify 路径。该 Commit 作为 Privacy UI 阶段的前置稳定基线，不改写。
