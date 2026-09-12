# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-13 — Compact Public UI + plist privacy cleanup

Runtime code head: `a0ea2edb71b6b8b37f57ab98e8dc2233b2eb0ffc`

实际修改：

- 新增 `ZNPublicCompactUI.mm`。
- 升级后首次启动默认进入现有 Compact 菜单，并将当前分类置为 `功能`；保留原扩展按钮。
- Compact 顶栏 subtitle 改为 `0.5.0`。
- `ZNFeatureGroupUI.mm` 中 UI 状态文案改为 `开 / 关`；`MIXED` 保持不变。
- Feature group 结果携带 FeatureID；成功切换后将状态保存到 `zn.f.%016llx.enabled`。
- 首次渲染时按 opaque FeatureID 恢复已保存开关状态；没有 FeatureID 的 legacy entry 不持久化。
- 移除 Feature UI 对 `ZNFeatureNameRegistry` 的读取。
- 移除 Signing Bridge 对 `ZNFeatureNameRegistryStore` 的写入。
- Makefile 不再编译 `ZNFeatureNameRegistry.mm`。
- 每次启动删除旧 `zonoe.feature-name-registry.v1`，避免 plist 继续暴露 Target/RVA/名称映射。
- `build_report.json` 标记 `legacyRegistryFallbackWritten=false` 与 `hostPreferencesContainTargetRVANameMap=false`。

CI / Build：

- Workflow: `Build Runtime Patch Menu FeatureID Map`
- Run: `34708549712`
- Result: `success`
- Artifact id: `10302263658`
- Artifact digest: `sha256:19091f04eeb493b94fdedd8ede33e4283d03ea05a7803884b172936ac02054db`
- Dylib SHA256: `e339f66628f8fcf2b8a524990be5e0aef4bb6726cfff8aa8b05bb4ce35694aeb`

验证：

- Source assertions: PASS。
- Feature metadata codec tests: PASS。
- Theos build: PASS。
- Binary verify: PASS。
- `ZNFeatureNameRegistryStore/Lookup` exported symbol: not present in built dylib。
- Artifact upload: PASS。
- 实机 UI / plist migration: 尚待验证。

## 2026-09-12 — FeatureID metadata stage

- 引入 ZNF1 Feature metadata codec。
- generated Mach-O 以 FeatureID + encoded display name 保存显示信息，保留 128-byte Static Entry ABI。
- UI 优先从 ZNF1 解码功能名。
- Feature metadata codec 单元测试覆盖英文/中文 round-trip、无明文和 FeatureID 分组语义。

## 2026-09-12 — v0.5.0 Privacy UI Test

- Public Feature UI 收敛为显示名称 + 开关。
- 初版将 generated Mach-O title/group 清零，并通过 NSUserDefaults Registry 保存显示名。
- 该 Registry 方案现已由 ZNF1 取代，并在当前阶段停用/迁移清理。
