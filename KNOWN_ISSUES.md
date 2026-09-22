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

真实设备对宽泛查询 `cash` 的观测：第一次 `423.1 ms`，第二次 `147 ms`，之后约 `150 ms`。重复搜索不是纯字符串索引查找；索引命中后仍会恢复当前 launch 的 MethodInfo / Method Pointer / Runtime VA。

`index=hit` UI 文本尚未被用户单独报告，因此该具体状态标记仍待确认。

## KI-009 — Method Finder M2 索引缓存缺少主动垃圾回收

Severity: `LOW`

Status: `OPEN / CLEANUP`

索引绑定 UnityFramework UUID + file size，因此游戏更新后旧索引不会被错误复用；但旧 fingerprint 的 binary plist 暂时不会被 ZonoPatch 主动删除，只能等待系统清理 Cache。

## KI-010 — M2 Objective-C dependency declarations 暂时依赖 warning suppression

Severity: `LOW`

Status: `OPEN / PRE-SEAL CLEANUP`

M2 bridge 的 category dependency declarations 仍依赖 `-Wno-incomplete-implementation`。这不是当前运行时错误，但封板前应整理到专用接口/协议并移除 suppression。

## KI-011 — Feature-branch GitHub Actions registration 历史异常

Severity: `LOW`

Status: `WORKAROUND / MONITOR`

历史上部分 feature branch push 出现 synthetic `BuildFailed / startup_failure / 0 jobs`。当前 M4/M4.1 专用 workflow 已能够在对应分支正常创建 runner 并成功构建，因此不要把历史基础设施问题误判为当前源码编译失败。

## KI-012 — M2 原 Cancel 控件在快速搜索上不可见/不可操作

Severity: `LOW`

Status: `LEGACY VALIDATION GAP`

M2.1 已把顶部 `搜索` 主按钮在 active token 时切换为 `取消`。后续版本继承该逻辑，但用户没有单独报告这一具体视觉状态，因此仍不要把它标成独立 device-verified 项。

## KI-013 — M4.1 菜单触摸穿透尚未真机验证

Severity: `HIGH`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

用户报告旧菜单打开后会拦截游戏操作。M4.1 新增 child-controller passthrough shell，使菜单控件区域继续接收触摸、面板外区域尝试交回游戏。

风险：此前 Translate/system text 稳定性依赖真实 UIViewController presentation ownership。新的穿透层必须同时验证：

- 面板外可继续操作游戏；
- 面板内按钮/输入框正常；
- Translate 第二次打开不闪退；
- 不破坏悬浮球显示/隐藏流程。

## KI-014 — M4.1 自动二进制选择 / App Libraries 尚未真机验证

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

目标行为：

- Unity 游戏优先 `UnityFramework`；
- 没有 UnityFramework 时回退主程序；
- 点击“二进制”弹出 `App Libraries`，不再要求手工输入；
- 只保存模块 identity，不保存带安装 UUID 的绝对路径。

需要在 Unity 与至少一个非 Unity 目标上分别验证默认选择和手动切换。

## KI-015 — M4.1 直接生成的自动 preflight 尚未真机验证

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

旧 UI 要求 `validatedCount == filledCount` 才允许点击生成；M4.1 取消这个人工前置条件，并在生成时自动执行必要 preflight。

注意：这不是移除 Builder 安全检查。Original、长度、RVA/file mapping、Mach-O、relocation 等必需条件仍必须成立。

需要真机验证：未手动点 `读取验证` 的有效 Patch 可以直接生成；无效输入仍应 fail closed 并给出明确错误。

## KI-016 — Runtime Method Call 自定义显示名称尚未真机验证

Severity: `MEDIUM`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

M4 Runtime Method Call V1 的创建/测试执行/生成后二进制已由用户确认可用；M4.1 新增独立 `title` 编辑入口。

需验证：改名后生成的新二进制显示自定义 title，但 canonical identity / methodName / 实际调用目标保持不变。

## KI-017 — M4.1 同页操作滚动位置保持尚未真机验证

Severity: `LOW`

Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

用户报告按钮操作后页面会跳回顶部。M4.1 在同页 `renderPage` 重建前后保存/恢复 `contentOffset`；侧栏分类切换仍允许主动回顶部。

需要在增加/删除 Patch、Feature 类型切换、Runtime Action 删除/改名等操作中确认没有异常跳动或 offset clamp。
