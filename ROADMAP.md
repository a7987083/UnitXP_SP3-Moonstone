# ROADMAP

## 当前阶段

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.0`
- Branch: `feature/runtime-patch-menu-feature-id-map`
- Stage: `FeatureID Map + Compact Public UI`
- Runtime code head: `a0ea2edb71b6b8b37f57ab98e8dc2233b2eb0ffc`
- CI: GitHub Actions run `34708549712` — `success`
- Artifact: `ZonoPatch-v0.5.0-FeatureIDMap-Test`

## 已完成

- ZNF1：generated Mach-O 内保存 FeatureID + 编码显示名，不再依赖 App Container 才能恢复名称。
- Public UI 默认迁移为 Compact 布局：`ZN` 顶栏、隐藏侧栏/底栏、直接展示功能列表；原扩展按钮仍可进入完整界面。
- 功能按钮显示文案：`ON -> 开`，`OFF -> 关`；`MIXED` 保持原语义。
- 删除 Runtime 构建中的 `ZNFeatureNameRegistry`，Signing Bridge 不再写 `Target/RVA/patchID -> title/group` 到 NSUserDefaults。
- 每次启动主动清除历史 `zonoe.feature-name-registry.v1`。
- 新功能状态偏好仅使用 `zn.f.<opaque-feature-id>.enabled`，不含 Target、RVA、Patch bytes 或显示名称。
- CI 增加 Registry 禁用、Compact UI、中文状态文案、opaque preference 和 ZNF1 编解码验证。

## 下一阶段 — Protection / Device Validation

Status: `NEXT`

目标：

- 实机确认升级后默认进入紧凑菜单，功能列表、滚动、展开/关闭行为正常。
- 实机确认 plist 中旧 `zonoe.feature-name-registry.v1` 被删除，不再出现 RVA -> 名称映射。
- 验证 `zn.f.<feature-id>.enabled` 的开关状态恢复行为。
- 对真实 `.znpatched` 检查 ZNF1、CodeDirectory、明文功能名以及 Static Dispatch 数据完整性。
- 继续评估并提高 `siteRVA / onRVA / Patch Variant` 的静态提取成本。

## Next Task

安装本次 CI Artifact 到目标 IPA，做一次冷启动和重新安装测试；截图/导出 plist，并验证菜单默认 Compact、`开/关` 文案、旧 Registry 清理和功能状态恢复。完成后再进入 Offset/Patch Protection Phase。
