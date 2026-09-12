# HANDOFF

## 当前上下文

当前工作线为 ZonoPatch Runtime Patch Menu `v0.5.0 FeatureID Embedded Metadata Test`。

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/runtime-patch-menu-feature-id-map`
- Privacy UI Runtime baseline: `908e27a36fa55a3e63e1ab55db5968fb5da12fde`
- FeatureID implementation CI baseline: `118a12c1febf3d693e5cb8e18b8e21cf6b008f01`
- Previous stable stage: `121cc7c098b2d6f122a9c91a411a442edd3eaf68`
- CI run: `34705353421` / `success`
- Artifact: `ZonoPatch-v0.5.0-FeatureIDMap-Test`

不要 rewrite `908e27a...`。FeatureID 修复是独立后继分支。

## 为什么做这次修改

首版 Privacy UI 把 generated target Mach-O 的 `title/group` 明文清零，再把真实名称放到 Host-side `NSUserDefaults` Registry。这个设计在生成设备/当前 Container 内可工作，但重新打 IPA、重新安装或 App Container 重建后 Registry 可能不存在，Runtime 只能退化为 `功能 #N` 等 fallback。

新设计参考成熟菜单“磁盘不放普通明文、运行时恢复 label”的思路，但考虑 ZonoPatch 的功能名是运行时导入/编辑后才确定，不能预编译进固定菜单 dylib。因此选择把 FeatureID + 编码后的显示名写进每个 generated target Static Entry 自身。

## 当前关键实现

### 1. ZNF1 metadata codec

文件：`iosruntimepatchmenu/src/ZNFeatureMetadataCodec.h/.mm`

复用 `ZN44StaticEntry` 中原来的 72 字节：

`title[48] + group[24]`

布局：

- byte 0: `0`，legacy title sentinel。
- byte 1..2: marker `A5 5A`。
- byte 3: codec version `1`。
- byte 4: flags；bit0 表示 explicit Feature group。
- byte 5..12: little-endian 64-bit FeatureID。
- byte 13: UTF-8 display-name byte length。
- byte 14..47: encoded payload 前 34 字节。
- byte 48: `0`，legacy group sentinel。
- byte 49..71: encoded payload 后 23 字节。

最大 display-name payload：57 UTF-8 bytes。

编码不是密码学加密；目标是消除普通 `strings` 可见的功能名明文，同时让名称跟 generated Mach-O 生命周期绑定。

### 2. FeatureID 规则

Explicit Feature group：

- identity 基于标准化后的 Feature/group 名称。
- 不纳入 target / RVA / patchID。
- 目的：Patch 重排、RVA 不同、跨 target 时仍能聚合成同一 Feature。

Legacy/no-group Patch：

- identity 纳入 target + siteRVA + patchID + 标准化 label。
- 目的：避免两个偶然同名 legacy Patch 被错误合并。

当前 hash 为稳定 64-bit deterministic hash；不是安全标识或权限边界。

### 3. Generated binary post-process

调用链：

`ZNStaticBinaryBuilder V3` -> 生成普通 Static Entry -> `ZNStaticBinarySigningBridge` -> `ZNScrubStaticDisplayMetadataAtPath` -> ZNF1 encode -> `ZNAdhocResignMachOAtPath` -> signature verification -> build report。

`ZNScrubStaticDisplayMetadataAtPath` 名称为了兼容调用链没有改，但行为已经从“全部置零”升级为“移除明文并转换成 ZNF1”。

Header 会设置：

`ZN44_STATIC_HEADER_FLAG_FEATURE_METADATA_V1`

Static Entry 仍为 128 bytes；Shared Site tail 不变。

### 4. Public Feature UI

`ZNFeatureGroupUI.mm` 显示名优先级：

1. `ZNFeatureMetadataDecodeEntry(record.entry)` — 新产物 authoritative path。
2. `ZNFeatureNameRegistryLookup(...)` — 首版 Privacy output compatibility。
3. legacy `record.title/group`。
4. `功能 #N` fallback。

如果有 FeatureID，UI 直接按 `id:%016llx` 聚合，不再依赖 target + patchID 猜 Feature 身份。

### 5. NSUserDefaults Registry 当前角色

`ZNFeatureNameRegistry` 暂时保留，但只作为旧产物兼容缓存。新 ZNF1 generated binary 即使 Registry 因重装消失，也应该能从自身 metadata 恢复功能名。

## CI 与验证证据

Workflow: `.github/workflows/build-runtime-patch-menu-feature-id-map.yml`

Run `34705353421`: SUCCESS。

验证内容：

- Source assertions。
- 独立 macOS Foundation codec unit test。
- 同 Feature 多 Patch/跨 target FeatureID 稳定性。
- legacy/no-group 不误合并。
- English + Chinese UTF-8 encode/decode round-trip。
- raw 72-byte metadata 不包含测试名称明文。
- Theos arm64 build。
- `nm` 确认 Encode/Decode symbols。
- Artifact upload。

Artifact id: `10301438907`

Artifact digest: `sha256:e226fb1e3e3fcaa3aadb224ca518a99159d10df02cfee322aa4b21b04b13b6a5`

注意：这仍然不是实机 generated-target 证明。

## 风险与接手注意事项

- 如果编码前 `row.group` / `entry.group` 本身就已经全部是“功能”，ZNF1 会忠实保存这个错误输入；不能靠 decoder 恢复不存在的信息。
- 因此用户当前问题需要下一步用真实生成输出区分：是旧 Registry 丢失，还是 JSON Import / Feature Builder 上游已经把名称归一成“功能”。
- 最大 display name 为 57 UTF-8 bytes，超出会截断到合法 UTF-8 前缀。
- Codec 是 obfuscation，不应描述成加密或安全存储。
- Metadata post-process 目前只支持 thin 64-bit Mach-O。
- Builder swizzle 仍依赖加载顺序假设。
- Generated binary ad-hoc resign 不等于最终 IPA resign。
- 不要把 CI success 写成 device verified。

## 下一步接手

用该分支 dylib 在目标 App 中导入一组明确功能名，生成真实 `.znpatched` + `build_report.json`。保留生成前输入名称，然后：

1. 检查 `__ZNDATA` header flag 和 ZNF1 entry。
2. 对 generated target 做 `strings`，确认输入功能名不以普通 UTF-8 明文出现。
3. 解码 entry，确认名称与编码前输入一致。
4. 替换回 IPA并最终整包重签。
5. 卸载/重新安装，确认菜单仍显示原始名称。
6. 若解码出来就已经是“功能”，回查 `ZNPatchJSONImporter` / `ZNFeatureBuilderUI` 的 title/group provenance。
