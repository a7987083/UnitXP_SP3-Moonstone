# ROADMAP

## 当前基线

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.0`
- Stage: `FeatureID Embedded Metadata Test`
- Branch: `feature/runtime-patch-menu-feature-id-map`
- Runtime code baseline: `908e27a36fa55a3e63e1ab55db5968fb5da12fde`
- FeatureID implementation CI baseline: `118a12c1febf3d693e5cb8e18b8e21cf6b008f01`
- Previous stage baseline: `121cc7c098b2d6f122a9c91a411a442edd3eaf68`
- CI: GitHub Actions run `34705353421` — `success`
- Artifact: `ZonoPatch-v0.5.0-FeatureIDMap-Test`

历史 `908e27a...` 继续保留为 v0.5.0 Privacy UI Runtime 基线，不 rewrite。FeatureID 修复在独立后继分支开发和验证。

## 阶段目标与状态

### Phase A — v0.5.0 Consolidated

Status: `COMPLETED / CI VALIDATED`

已完成 generated Mach-O builder、Static Dispatch、generated binary signing / CodeDirectory rebuild 等基础链路。稳定点：`121cc7c098b2d6f122a9c91a411a442edd3eaf68`。

### Phase B — v0.5.0 Privacy UI Test

Status: `COMPLETED AS BASELINE / DESIGN ISSUE FOUND`

已完成公共“功能”页收敛、title/group 明文清理和 Host-side Registry 方案。后续发现真实功能名称以 `NSUserDefaults` Registry 为主要来源时，重新安装/更换 App Container 后存在名称丢失并退化到泛化名称的设计缺口。

### Phase C — Embedded FeatureID Metadata

Status: `CURRENT / CI + CODEC TEST VALIDATED`

目标：

- 不增加外部 FeatureMap 文件。
- 不要求针对每套功能重新编译 ZonoPatch dylib。
- Generated target Mach-O 内不保存普通 UTF-8 功能名明文。
- 每个 Static Entry 保存稳定 `FeatureID` + ZNF1 编码显示名。
- Runtime 直接从 generated Mach-O 解码名称；重新签名/重新安装后不依赖旧 App Container。
- `NSUserDefaults` Registry 降级为旧版兼容 fallback，不再是新产物的唯一真实名称来源。
- 保持 `ZN44StaticEntry` 128-byte ABI、Shared Site tail 和 Runtime Patch 执行路径不变。

当前实现：

- 新增 `ZNFeatureMetadataCodec.h/.mm`。
- 复用 `title[48] + group[24]` 共 72 字节作为 ZNF1 opaque metadata，不扩大 Static Entry。
- `title[0]` / `group[0]` 保持为 0，使旧 Runtime 不会把编码字节当 C-string 显示。
- Explicit Feature group 使用标准化功能名生成稳定 64-bit FeatureID；同名 Feature 跨 Patch/跨 target 保持同一 ID。
- Legacy/no-group Patch 将 target + RVA + patchID 纳入 ID，避免偶然同名导致错误合并。
- Public Feature UI 优先解码 embedded ZNF1，并按 FeatureID 聚合；旧 Registry 和 legacy entry 仅作 fallback。
- Metadata 后处理在 ad-hoc resign 前完成编码，然后重新校验签名。

当前验证：

- Source assertions: PASS。
- ZNF1 codec unit tests: PASS。
- 单测覆盖：round-trip、同 Feature 多 Patch ID 一致、legacy Patch 不误合并、中文 UTF-8、raw 72-byte metadata 不包含测试功能名明文。
- Theos arm64 dylib build: PASS。
- dylib symbol/string verification: PASS。
- GitHub Actions run `34705353421`: SUCCESS。
- 真实 generated `.znpatched` 目标二进制：尚未完成设备侧验证。
- 重新打 IPA / 重签 / 重装后的菜单名称：尚未完成设备侧验证。

### Phase D — Real Generated Binary + Device Validation

Status: `NEXT`

目标：

- 使用真实功能名生成一份 `.znpatched`。
- 解析 `__ZNDATA`，确认 header flag 与每个 entry 的 ZNF1 marker / FeatureID 正确。
- 对 generated target 执行 `strings` / raw byte 检查，确认真实功能名不以普通明文存在。
- 替换回 IPA、最终整包重签、重新安装。
- 验证菜单显示原始功能名，而非 `功能` / `功能 #N`。
- 验证同一 Feature 多 Patch 聚合、ON/OFF/MIXED、Shared Site、rollback。
- 如果 ZNF1 解码出的名字本身就是泛化“功能”，继续向上追踪 JSON Import / Feature Builder 的 name/group provenance，而不是修改解码 fallback 猜名字。

### Phase E — Production Hardening / Release

Status: `PLANNED`

进入条件：

- Phase D 真实生成与实机重装验证通过。
- `KNOWN_ISSUES.md` 无 High severity 未关闭项。
- Production CI 有真实 builder fixture 或等价 generated Mach-O 校验。
- Release artifact / hash / provenance 可重复。

## Next Task

在目标 App 上用当前 FeatureID 分支生成一份包含多个明确不同功能名（至少一个中文、一个英文、一个多 Patch Feature）的 `.znpatched`，保留 `build_report.json`；随后检查 ZNF1 metadata、明文字符串、最终 IPA 重装后的菜单名称。若仍全部显示“功能”，优先检查导入/编辑阶段的 `row.title` / `row.group` 是否在编码前已经被污染为同一值。
