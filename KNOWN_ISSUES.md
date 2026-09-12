# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — 缺少已记录的实机 Runtime / reinstall 回归

Severity: `HIGH`

Status: `OPEN`

现状：FeatureID 分支已通过编译、静态检查和独立 codec unit test，但还没有真实目标 App 中生成 `.znpatched`、最终 IPA 重签、卸载/重装后的名称恢复与 Patch 行为记录。

风险：CI success 不能证明 dyld/runtime、真实 generated target、最终签名或 App Container 重建后的行为。

下一步：按 `ROADMAP.md` Phase D 完成真实设备端生成与 reinstall 回归。

## KI-002 — Metadata post-process 仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`

Status: `OPEN / KNOWN LIMITATION`

位置：`iosruntimepatchmenu/src/ZNStaticMetadataPrivacy.mm`

现状：入口要求 `MH_MAGIC_64`，不支持 FAT/universal 或其他 Mach-O magic。

下一步：Production 阶段确认所有目标输出格式；若需要 FAT，按 slice 分别处理，不能直接复用当前 offsets。

## KI-003 — 尚未对真实 generated target 验证 ZNF1 与明文消失

Severity: `HIGH`

Status: `OPEN / TEST GAP`

现状：`feature_metadata_codec_test.mm` 已对 synthetic `ZN44StaticEntry` 验证 English/Chinese round-trip、FeatureID 稳定性、legacy 不误合并以及 raw 72-byte metadata 不含测试功能名明文；但 CI 还没有真实可执行 target fixture 走完整 Builder V3 -> ZNF1 -> resign 流程。

风险：单元测试无法覆盖真实 `__ZNDATA` 扫描、Header flag、Builder entry 顺序、CodeDirectory 后处理和目标 Mach-O 字符串残留。

下一步：对真实 `.znpatched` 做结构解析、`strings`、ZNF1 decode、签名和重装检查；之后再考虑把真实 fixture 固化进 CI。

## KI-004 — Builder swizzle 存在加载顺序假设

Severity: `MEDIUM`

Status: `OPEN / RISK`

位置：`iosruntimepatchmenu/src/ZNStaticBinarySigningBridge.mm`

现状：Bridge 在 `+load` 中延迟一个 main-queue turn，依赖 V3 builder swizzle 已完成，再包住最终 implementation。

风险：未来修改初始化顺序、线程模型或 builder category 后，wrapper 可能包错 IMP。

下一步：Production Hardening 增加 active IMP / selector 断言或改成更显式的 builder pipeline。

## KI-005 — Legacy Feature Name Registry 仍有 stale entry 风险

Severity: `LOW`

Status: `OPEN / COMPATIBILITY ONLY`

位置：`iosruntimepatchmenu/src/ZNFeatureNameRegistry.mm`

现状：Registry 仍保存在 `NSUserDefaults`，key 为 normalized target + siteRVA + patchID。新 ZNF1 output 不再依赖它；它只为首版 Privacy output 提供 fallback。

风险：旧 output 或 ZNF1 decode 失败时，理论上仍可能命中 stale registry entry。

下一步：实机验证新 output 始终优先 embedded metadata；Production 可增加 build/version namespace 或迁移策略。

## KI-006 — Generated binary ad-hoc 重签不是最终 IPA 签名

Severity: `MEDIUM`

Status: `OPEN / RELEASE REQUIREMENT`

现状：Generated binary 后处理会重建并校验 CodeDirectory，但替换回 IPA 后仍必须正常整包重签。

下一步：Production/Release workflow 必须把“替换 generated binary -> 最终 IPA resign -> install/launch validation”作为独立 gate。

## KI-007 — ZNF1 display name 最大 57 UTF-8 bytes

Severity: `LOW`

Status: `OPEN / KNOWN LIMITATION`

现状：为了不改变 128-byte Static Entry ABI，ZNF1 使用原 `title[48] + group[24]` 72-byte 区域；扣除 marker/FeatureID/length/sentinel 后最多保存 57 UTF-8 bytes。超长名称会截断到合法 UTF-8 前缀。

风险：非常长的功能名称在 Public UI 中会被截短。

下一步：实机确认实际名称长度分布；如确有需求，再设计 versioned side table，而不是扩大现有 Entry 破坏 ABI。

## KI-008 — 上游名称如果已经变成“功能”，ZNF1 无法恢复原名

Severity: `HIGH`

Status: `OPEN / ROOT-CAUSE CHECK REQUIRED`

现状：ZNF1 解决的是“名称跟随 generated binary 持久化”和“明文隐藏”。它会忠实编码 Builder 给出的 display name。如果 `ZNPatchJSONImporter` / `ZNFeatureBuilderUI` 在编码前已经把多个 Feature 的 `row.title` / `row.group` 统一成 `功能`，最终 Runtime 仍会正确解出错误的 `功能`。

相关风险点：当前 JSON Importer 会把 `title/name/label/featuretitle` 视为 title 并沿父节点递归继承；Feature Builder 对 `Imported` row 可能将 title 提升为 group。因此 generic container name 有可能污染 Feature identity。

下一步：用用户真实输入生成一次 output，同时记录编码前每个 row 的 target/RVA/title/group。若 ZNF1 decode 与编码前输入一致但输入已全部为“功能”，根因转到 JSON importer / Feature Builder provenance，需单独修复，不应在 Runtime decoder 中硬猜名称。
