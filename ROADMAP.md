# ROADMAP

## 当前基线

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.0`
- Stage: `Privacy UI Test`
- Branch: `feature/runtime-patch-menu-privacy-ui`
- Runtime code baseline: `908e27a36fa55a3e63e1ab55db5968fb5da12fde`
- Previous stage baseline: `121cc7c098b2d6f122a9c91a411a442edd3eaf68`
- CI: GitHub Actions run `34688640962` — `success`
- Artifact: `ZonoPatch-v0.5.0-PrivacyUI-Test`

当前分支相对 `121cc7c...` 前进 9 个 Commit。`908e27a...` 作为当前 Runtime 代码基线保留，不改写历史。

## 阶段目标与状态

### Phase A — v0.5.0 Consolidated

Status: `COMPLETED / CI VALIDATED`

目标：

- Consolidate Runtime Patch Menu v0.5.0。
- 完成 generated Mach-O builder / signing 路径。
- 重建并校验 generated binary CodeDirectory。
- 保持现有 Static Dispatch ABI。

已知稳定点：`121cc7c098b2d6f122a9c91a411a442edd3eaf68`。

### Phase B — v0.5.0 Privacy UI Test

Status: `CURRENT / CI VALIDATED`

范围：

- 公共“功能”页仅展示功能名和开关，不显示 Target/RVA/Original/Enabled/Shared Site/Owner/Variant 等技术字段。
- 功能显示名优先从 Host-side `ZNFeatureNameRegistry` 解析。
- Generated target Mach-O 的 `__ZNDATA` Static Dispatch entries 中 `title/group` 清零。
- 清理后重建 ad-hoc CodeDirectory，并记录 machine-readable build report。
- Feature group 开关保持事务式失败回滚。

当前验证：

- 源码断言：已在 CI 执行。
- Theos 编译：已通过。
- dylib 静态符号/字符串检查：已通过。
- GitHub Artifact：已生成。
- 实机加载 / Runtime 行为 / 完整 IPA 回归：尚无已记录验证结果。

### Phase C — Production Hardening

Status: `NEXT`

目标：

- 以 `908e27a...` 为只读代码基线继续，不修改历史 Commit。
- 对实际 generated `.znpatched` Mach-O 做生成前/后静态对比，确认 `title/group` 明文真实清除且 ABI 未变化。
- 实机验证 Feature Registry 命中、旧二进制 fallback、ON/OFF/MIXED、失败回滚。
- 验证 scrub -> ad-hoc resign -> 替换回 IPA -> 最终整包重签的完整链路。
- 固化 Production CI，避免只检查 marker string 而未检查真实隐私结果。
- 补充失败样本、日志和回归证据。

### Phase D — Production / Release

Status: `PLANNED`

进入条件：

- Phase C 所有阻塞项关闭。
- CI + 实机 + 最终 IPA 重签链路均通过。
- Release artifact 可重复生成并具备 hash / build provenance。
- `KNOWN_ISSUES.md` 无 High severity 未关闭项。

## Next Task

从 `908e27a36fa55a3e63e1ab55db5968fb5da12fde` 建立 Production Hardening 后继阶段；第一项任务是对真实 generated `.znpatched` Mach-O 做 `__ZNDATA`、Static Entry、CodeDirectory 和明文字符串的前后对比，并完成一次实机 Runtime 验证。未完成这些验证前，不把当前状态标记为 Production。
