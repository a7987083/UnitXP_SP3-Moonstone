# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — Protection V1 尚未实机 / 真实 `.znpatched` 验证

Severity: `HIGH`

Status: `OPEN`

CI 已确认 Protection codec、编译和 binary verify 通过，但还没有真实目标输出证据确认：生成后的 Static Entry 三个 RVA 字段已编码、Runtime 能正常恢复、Shared Site 与最终 IPA 冷启动不回归。

下一步：用 v0.5.1 生成真实 `.znpatched`，提交 `.znpatched + build_report.json` 做结构检查并上机测试。

## KI-002 — FeatureID 仍是可推导 ID，不是随机稳定 authoring ID

Severity: `MEDIUM`

Status: `OPEN / HARDENING`

当前 ZNF1 对明确 Feature group 的 FeatureID 仍由 normalized display name 推导。了解算法的分析者可对常见名称做字典匹配。

下一步：评估随机稳定 FeatureID / authoring identity，并保持同一 Feature 跨 Patch 的稳定关联。

## KI-003 — Patch payload / Variant 尚未进入 Protection V2

Severity: `HIGH`

Status: `OPEN / HARDENING`

Protection V1 已让 Static Entry 的 `siteRVA/offRVA/onRVA` 不再以直接可读整数存储，但 relocated Original / ON Variant 仍存在于 `__ZNTEXT`。熟悉 ARM64 relocation 和 ZonoPatch 结构的分析者仍可进一步恢复 Patch 内容。

下一步：Patch Payload Protection V2，重点降低对 `__ZNTEXT` Variant 的静态批量恢复能力，同时保持 Stock iOS / No JIT 约束。

## KI-004 — Protection V1 是可逆静态分析成本层，不是客户端秘密

Severity: `MEDIUM`

Status: `BY DESIGN`

Runtime 必须最终得到真实地址；且当前仓库公开，分析者可以研究编码算法。Protection V1 的目标是消除“直接按结构读取 RVA”的低成本路径和增加完整性检查，而不是保证地址不可恢复。动态调试环境仍可观察 Runtime transient 数据。

## KI-005 — Metadata / RVA 后处理仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`

Status: `OPEN / KNOWN LIMITATION`

当前 generated binary 后处理要求 `MH_MAGIC_64`。若未来支持 FAT/universal，需要按 slice 解析，不能复用现有 file offsets。

## KI-006 — Feature 状态恢复发生在 Feature 页首次渲染

Severity: `MEDIUM`

Status: `OPEN / BEHAVIOR TO VALIDATE`

`zn.f.<feature-id>.enabled` 在 Feature UI 第一次渲染时恢复。Shared Site、多 Feature 同时恢复、失败回滚仍需实机验证。

## KI-007 — Generated binary ad-hoc 重签不是最终 IPA 签名

Severity: `MEDIUM`

Status: `OPEN / RELEASE REQUIREMENT`

Generated binary 会在 ZNF1 + RVA Protection 后重建并校验 CodeDirectory，但替换回 IPA 后仍必须正常整包重签并验证安装/启动。

## KI-008 — Method Finder M2 indexed lookup 仍包含 live re-resolution 成本

Severity: `LOW`

Status: `MEASURED / OPTIMIZATION OPTIONAL`

真实设备对宽泛查询 `cash` 的观测：第一次 `423.1 ms`，第二次 `147 ms`，之后约 `150 ms`。这说明当前目标的首次扫描/建索引成本已经很低，重复查询也明显降低。

重复搜索不是纯字符串索引查找：索引命中后仍会为候选恢复当前 launch 的 MethodInfo / Method Pointer / Runtime VA，因此约 150 ms 不应直接视为索引低效。只有后续 UX 证据表明 150 ms 仍影响使用时，才考虑进一步缓存/批量解析。

`index=hit` UI 文本尚未被用户单独报告，因此该具体状态标记仍待确认。

## KI-009 — Method Finder M2 索引缓存缺少主动垃圾回收

Severity: `LOW`

Status: `OPEN / CLEANUP`

索引绑定 UnityFramework UUID + file size，因此游戏更新后旧索引不会被错误复用；但旧 fingerprint 的 binary plist 暂时不会被 ZonoPatch 主动删除，只能等待系统清理 Cache。

下一步：M2 实机稳定后增加按 fingerprint/版本保留策略和大小上限。

## KI-010 — M2 Objective-C dependency declarations 暂时依赖 warning suppression

Severity: `LOW`

Status: `OPEN / PRE-SEAL CLEANUP`

M2 bridge 需要声明由主类/M1 category 实现的方法。当前 clang/Theos 会把这些 category dependency declarations 报为 `-Wincomplete-implementation` 并在项目 `-Werror` 策略下终止编译，因此 Makefile 临时加入 `-Wno-incomplete-implementation`。

这不是运行时错误，M2/M2.1 已真实编译/链接/二进制验证通过，但在封板前应把 dependency declarations 整理到专用接口/协议并移除 suppression。

## KI-011 — Feature-branch GitHub Actions registration 异常

Severity: `LOW`

Status: `OPEN / INFRASTRUCTURE WORKAROUND ACTIVE`

部分 feature branch push 被 GitHub Actions 记录为 synthetic `BuildFailed / startup_failure / 0 jobs`，没有创建 runner。已经通过在默认分支 `main` 注册 workflow、再 checkout 固定 feature source SHA 的方式恢复真实构建。

当前 workaround 已能稳定编译 M1/M2/M2.1；该问题不得被解释为产品源码编译失败。

## KI-012 — M2 原 Cancel 控件在快速搜索上不可见/不可操作

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

M2 把 Cancel 作为 search page 底部的临时卡片，只在 active token 存在时出现。真实目标第一次搜索仅约 423 ms、重复约 150 ms，用户未观察到该按钮，而且即使短暂出现也几乎没有人工点击窗口。

M2.1 已改为 active token 期间把顶部原 `搜索` 主按钮原位切换为 `取消`，并移除底部临时 Cancel 卡片；搜索 engine/cancel token 语义不变。CI run `34885020233` 已通过，待真机确认顶部按钮状态切换。生产搜索不会为了测试 Cancel 人为降速。
