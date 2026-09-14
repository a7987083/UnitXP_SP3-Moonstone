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

## KI-008 — Method Finder M2 首次完整索引成本尚未实机量化

Severity: `MEDIUM`

Status: `OPEN / DEVICE VALIDATION`

M2 首次宽泛搜索会在后台枚举 IL2CPP classes/methods，并为每个 method 尝试得到可验证 native pointer/RVA，再写入紧凑索引。UI 线程不会执行完整扫描，并支持取消，但真实游戏上的总耗时、峰值内存和热量影响尚无设备数据。

下一步：真实设备第一次搜索 `cash`，记录 classes/methods/records、完成时间、取消响应和游戏帧率/交互表现；完成后再次搜索同词对比 index-hit 延迟。

## KI-009 — Method Finder M2 索引缓存缺少主动垃圾回收

Severity: `LOW`

Status: `OPEN / CLEANUP`

索引绑定 UnityFramework UUID + file size，因此游戏更新后旧索引不会被错误复用；但旧 fingerprint 的 binary plist 暂时不会被 ZonoPatch 主动删除，只能等待系统清理 Cache。

下一步：M2 实机稳定后增加按 fingerprint/版本保留策略和大小上限。

## KI-010 — M2 Objective-C dependency declarations 暂时依赖 warning suppression

Severity: `LOW`

Status: `OPEN / PRE-SEAL CLEANUP`

M2 bridge 需要声明由主类/M1 category 实现的方法。当前 clang/Theos 会把这些 category dependency declarations 报为 `-Wincomplete-implementation` 并在项目 `-Werror` 策略下终止编译，因此 Makefile 临时加入 `-Wno-incomplete-implementation`。

这不是运行时错误，M2 已真实编译/链接/二进制验证通过，但在封板前应把 dependency declarations 整理到专用接口/协议并移除 suppression。

## KI-011 — Feature-branch GitHub Actions registration 异常

Severity: `LOW`

Status: `OPEN / INFRASTRUCTURE WORKAROUND ACTIVE`

部分 feature branch push 被 GitHub Actions 记录为 synthetic `BuildFailed / startup_failure / 0 jobs`，没有创建 runner。已经通过在默认分支 `main` 注册 workflow、再 checkout 固定 feature source SHA 的方式恢复真实构建。

当前 workaround 已能稳定编译 M1/M2；该问题不得被解释为产品源码编译失败。
