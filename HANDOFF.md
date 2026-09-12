# HANDOFF

## 当前上下文

当前工作线为 ZonoPatch Runtime Patch Menu `v0.5.0 Privacy UI Test`。

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/runtime-patch-menu-privacy-ui`
- Runtime code baseline: `908e27a36fa55a3e63e1ab55db5968fb5da12fde`
- Previous stable stage: `121cc7c098b2d6f122a9c91a411a442edd3eaf68`
- Relation: `908e27a...` is 9 commits ahead of `121cc7c...`
- CI run: `34688640962` / `success`
- Artifact: `ZonoPatch-v0.5.0-PrivacyUI-Test`

`908e27a...` 是当前 Runtime 代码基线。后续只新增 Commit，不 rewrite / amend / force-replace 该历史点。

## 关键实现与调用链

### 1. Generated binary privacy + signing

`ZNStaticBinarySigningBridge.mm`

调用逻辑：

`ZNStaticBinaryBuilder buildWorkspace` -> delayed class-method swizzle wrapper -> 原 V3 builder -> 收集 workspace 中 title/group -> 遍历 `.znpatched` 输出 -> `ZNScrubStaticDisplayMetadataAtPath` -> `ZNAdhocResignMachOAtPath` -> 全部成功后写入 `ZNFeatureNameRegistry` -> 更新 `build_report.json`。

关键约束：

- Bridge 在 `+load` 中延迟一个 main-queue turn 安装 swizzle，目的是包住 V3 最终 builder implementation。
- Registry 只有在所有 generated binary 完成 scrub + signature verification 后才提交。
- Generated binary 自身 ad-hoc 重签不等于最终 IPA 签名；替换回 IPA 后仍要求正常整包重签。

### 2. Static metadata scrub

`ZNStaticMetadataPrivacy.mm`

- 当前仅接受 `MH_MAGIC_64` thin 64-bit Mach-O。
- 遍历 Load Commands，定位 `LC_SEGMENT_64` / `__ZNDATA`。
- 8-byte 对齐扫描 `ZN44StaticHeader`。
- 接受 Static Format V1/V2，校验 `entrySize/count/range`。
- 对每个 `ZN44StaticEntry` 执行 `memset(title, 0)` 与 `memset(group, 0)`。
- `msync(MS_SYNC)` 后返回 scrubbed entry count。

### 3. Feature name registry

`ZNFeatureNameRegistry.mm`

- 存储后端：`NSUserDefaults`。
- Defaults key: `zonoe.feature-name-registry.v1`。
- Entry key: normalized target + siteRVA + patchID。
- Value: `title/group`。
- Signing bridge 同时存 logical target 和 runtime basename alias，降低 dyld image name 差异导致的 lookup miss。

### 4. Public Feature UI

`ZNFeatureGroupUI.mm`

显示名解析：

`ZN50DisplayMetadata` -> `ZNFeatureNameRegistryLookup` -> 若无 Registry 数据则 fallback 到 record.title/group -> 最终 fallback `功能 #<patchID>` / `Imported`。

Feature grouping：

- 非 `Imported` group：按 lowercase group 合并。
- 无明确 group 的 legacy entry：按 target + patchID 独立显示。

Toggle：

- 全开：ON。
- 部分开：MIXED。
- 全关：OFF。
- OFF/MIXED 点击目标为 ON；ON 点击目标为 OFF。
- 任一 Patch 切换失败时，对本次已修改记录逆序 rollback。

## CI 当前实际验证内容

Workflow: `.github/workflows/build-runtime-patch-menu-privacy-ui.yml`

- macOS 15 runner。
- 安装 `ldid` 与 Theos。
- grep 源码断言，确认 Privacy UI / Registry / Metadata Privacy 已接入。
- `make clean && make FINALPACKAGE=1`。
- 输出 `ZonoPatch_v0.5.0_PrivacyUI_Test.dylib` 与 `SHA256.txt`。
- `file`、`nm -gU` 和 `strings` 做静态检查。
- 上传 GitHub Artifact。

注意：上述 CI 不能替代真实 generated target Mach-O 检查，也不能替代实机 Runtime / 最终 IPA 回归。

## 风险与接手注意事项

- 不要把“CI success”写成“实机验证通过”。当前没有已记录的实机验证证据。
- 不要直接复用旧 Offset / RVA；目标二进制版本变化时必须重新定位。
- `ZNScrubStaticDisplayMetadataAtPath` 当前明确只支持 thin 64-bit Mach-O。
- 修改 signing/privacy 链路前先保持处理顺序：builder -> scrub -> re-sign -> verify -> registry commit。
- 不要在失败路径提前写 Registry；否则会制造 stale display metadata。
- Swizzle 安装依赖 V3 builder 的加载顺序假设，后续若重构 builder 必须重新验证 active IMP。
- Public Feature UI 的简化不代表技术字段被删除；诊断/Debug 能力应保持与用户页解耦。
- 最终交付产物替换回 IPA 后仍需整包正常重签。

## 下一步接手

以 `908e27a...` 为基线进入 Production Hardening。先验证真实 `.znpatched` 输出：Mach-O Header/Load Commands、`__ZNDATA`、Static Entry、明文 title/group、CodeDirectory、签名前后 page hashes；然后做实机 Registry/UI/toggle/rollback 验证。验证完成后再增加 Production/Release workflow。
