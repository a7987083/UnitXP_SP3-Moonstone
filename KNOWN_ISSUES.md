# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — Compact UI / plist migration 尚未实机验证

Severity: `HIGH`

Status: `OPEN`

CI 已确认源码断言、编译和 binary verify 通过，但还没有目标设备证据确认：升级后默认 Compact、`开/关` 文案、旧 Registry 删除、opaque preference 写入和冷启动状态恢复。

下一步：安装本次 Artifact，导出 plist 并录制/截图 UI 行为。

## KI-002 — FeatureID 仍是可推导 ID，不是随机 128-bit ID

Severity: `MEDIUM`

Status: `OPEN / HARDENING`

当前 ZNF1 对明确 Feature group 的 FeatureID 由 normalized display name 推导。虽然 plist 不再直接包含名称/RVA，但了解算法的分析者可对常见名称做字典匹配。

下一步：Protection Phase 评估随机稳定 FeatureID / authoring identity，避免名称字典猜测，同时保持同一 Feature 跨 Patch 的稳定关联。

## KI-003 — Static Dispatch 仍暴露可解析的 siteRVA/onRVA/offRVA 结构

Severity: `HIGH`

Status: `OPEN / HARDENING`

本次只移除了最明显的 NSUserDefaults Target/RVA/name 明文映射，没有改变 generated target Mach-O 的 Static Dispatch 基础寻址结构。熟悉格式的分析者仍可能解析 Offset 和 Variant。

下一步：设计 Offset/Patch Protection Phase，降低静态批量提取能力，并保留 Runtime 正确性和签名链路。

## KI-004 — Metadata codec / scrub 仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`

Status: `OPEN / KNOWN LIMITATION`

当前 generated binary 后处理要求 `MH_MAGIC_64`。若未来支持 FAT/universal，需要按 slice 解析，不能复用现有 file offsets。

## KI-005 — Feature 状态恢复发生在 Feature 页首次渲染

Severity: `MEDIUM`

Status: `OPEN / BEHAVIOR TO VALIDATE`

`zn.f.<feature-id>.enabled` 在 Feature UI 第一次渲染时恢复。stored `YES` 会通过现有事务式 toggle 路径重新启用该 Feature。

风险：Shared Site、多 Feature 同时恢复、失败回滚需要实机验证。

## KI-006 — Generated binary ad-hoc 重签不是最终 IPA 签名

Severity: `MEDIUM`

Status: `OPEN / RELEASE REQUIREMENT`

Generated binary 会重建并校验 CodeDirectory，但替换回 IPA 后仍必须正常整包重签并验证安装/启动。
