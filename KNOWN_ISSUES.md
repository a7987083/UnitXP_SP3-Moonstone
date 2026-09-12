# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — 缺少已记录的实机 Runtime 回归

Severity: `HIGH`

Status: `OPEN`

现状：GitHub Actions 已编译并完成静态检查，但当前仓库证据中没有 `v0.5.0 Privacy UI Test` 的实机加载、菜单交互、Patch enable/disable、rollback 和最终 IPA 回归记录。

风险：CI success 不能证明 dyld/runtime、权限、签名、目标 image 解析和真实 Patch 行为正确。

下一步：在目标设备/目标 App 版本上记录完整运行日志、实际开关行为、失败回滚及崩溃/异常结果。

## KI-002 — Metadata scrub 仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`

Status: `OPEN / KNOWN LIMITATION`

位置：`iosruntimepatchmenu/src/ZNStaticMetadataPrivacy.mm`

现状：入口要求 `MH_MAGIC_64`，不支持 FAT/universal 或其他 Mach-O magic。

风险：若 builder 后续输出格式变化，隐私后处理会直接失败。

下一步：Production 阶段确认所有目标输出格式；如果需要 FAT 支持，按 slice 解析并分别 scrub，不能简单复用当前 file offsets。

## KI-003 — 当前 Privacy CI 没有验证真实 title/group 明文已从 generated target Mach-O 消失

Severity: `HIGH`

Status: `OPEN`

现状：CI 会 grep 源码、构建 ZonoPatch dylib，并检查 `targetMachODisplayNames` / `titleGroupFieldsZeroed` 等 report marker string；但这不等价于对实际生成的 `.znpatched` 目标二进制做前后字符串和 `__ZNDATA` entry 检查。

风险：实现回归时，CI 可能仍为绿色，但 generated target Mach-O 仍残留 display metadata。

下一步：在 Production CI 增加真实 builder fixture，解析输出 Mach-O，验证 Static Entry `title/group` 全零，同时验证 entry size/count/patch data 未被破坏。

## KI-004 — Builder swizzle 存在加载顺序假设

Severity: `MEDIUM`

Status: `OPEN / RISK`

位置：`iosruntimepatchmenu/src/ZNStaticBinarySigningBridge.mm`

现状：Bridge 在 `+load` 中 `dispatch_async` 到 main queue，依赖 V3 builder swizzle 已经安装完成，然后再交换最终 class method implementation。

风险：未来修改初始化顺序、线程模型或 builder category 后，wrapper 可能包错 IMP。

下一步：Production 阶段记录 swizzle 前后 IMP/selector，添加一次构建路径断言，确认 wrapper 实际调用 V3 builder。

## KI-005 — Feature Name Registry 缺少显式生命周期/清理策略

Severity: `LOW`

Status: `OPEN / RISK / NOT REPRODUCED`

位置：`iosruntimepatchmenu/src/ZNFeatureNameRegistry.mm`

现状：Registry 存储在 `NSUserDefaults`，key 为 normalized target + siteRVA + patchID。当前没有显式版本迁移、过期清理或 workspace/build identity。

风险：目标版本变化但 key 偶然复用时，理论上可能显示旧名称。当前未复现。

下一步：实机覆盖多版本/重复生成场景；如确认存在 stale entry，再增加 build identity 或受控清理机制，避免先行过度设计。

## KI-006 — Generated binary ad-hoc 重签不是最终 IPA 签名

Severity: `MEDIUM`

Status: `OPEN / RELEASE REQUIREMENT`

现状：Generated binary 后处理会重建并校验 CodeDirectory，但源码明确要求替换回 IPA 后继续执行正常整包重签。

风险：遗漏最终 resign 会导致安装/加载失败，与 Runtime Patch 逻辑本身无关。

下一步：Production/Release workflow 必须把“替换 generated binary -> 最终 IPA resign -> install/launch validation”作为独立 gate。
