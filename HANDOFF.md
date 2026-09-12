# HANDOFF

## 当前上下文

当前工作线：ZonoPatch Runtime Patch Menu `v0.5.0 FeatureID Map + Compact Public UI`。

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/runtime-patch-menu-feature-id-map`
- Runtime code head: `a0ea2edb71b6b8b37f57ab98e8dc2233b2eb0ffc`
- CI run: `34708549712` / `success`
- Artifact id: `10302263658`

## 关键实现

### ZNF1 display metadata

`ZNFeatureMetadataCodec.mm` 将功能显示名转换为 FeatureID + encoded UTF-8 payload，存入 `ZN44StaticEntry` 原有 title/group 72-byte 区域，不扩大 128-byte ABI。Runtime UI 用 `ZNFeatureMetadataDecodeEntry()` 恢复显示名。

### plist / NSUserDefaults

旧方案 `zonoe.feature-name-registry.v1` 已废弃，因为 key 直接包含 normalized Target + siteRVA + patchID，value 又保存 title/group，构成明显信息泄露。

当前行为：

- `ZNStaticBinarySigningBridge.mm` 不再写 Feature Name Registry。
- `ZNFeatureGroupUI.mm` 不再读取 Feature Name Registry。
- `ZNFeatureNameRegistry.mm` 不再参与 Makefile 编译。
- `ZNPublicCompactUI.mm` 每次启动删除旧 `zonoe.feature-name-registry.v1`。
- 新功能开关偏好 key：`zn.f.%016llx.enabled`，只关联 opaque FeatureID 与 BOOL。
- 没有 FeatureID 的 legacy records 不写该偏好。

### Compact Public UI

`ZNPublicCompactUI.mm` 复用既有 Compact 布局：隐藏 sidebar/footer，顶部保留 `ZN`、扩展按钮、关闭按钮。升级后第一次运行会将 `ZonoePatch.CompactMode` 设为 YES，并选择分类 0（功能）；用户仍可通过现有 mode button 展开完整菜单。

### 开关显示

`ZNFeatureGroupUI.mm`：

- 全开 -> `开`
- 全关 -> `关`
- Shared/多 Patch 部分开启 -> `MIXED`（按要求未改变）

内部日志仍可使用 ON/OFF，不影响 UI。

## CI 已验证

Run `34708549712`：source assertions、ZNF1 codec tests、Theos build、binary verify、artifact upload 均成功。构建产物不再导出 `ZNFeatureNameRegistryStore/Lookup`。

## 接手注意事项

- 不要恢复 Target/RVA/title/group 的 NSUserDefaults Registry。
- ZNF1 当前 FeatureID 对明确 Feature group 仍由 normalized display name 推导；它不是密码学随机 ID，存在字典猜测风险。
- Static Dispatch 的 `siteRVA/onRVA/offRVA` 仍属于后续 Protection Phase 范围，本次未改变。
- 开关状态恢复在 Feature 页首次渲染时执行；若 stored BOOL=YES，会调用现有事务式 Feature toggle 路径。
- generated binary 仍需 ad-hoc CodeDirectory rebuild；替换回 IPA 后仍需最终整包重签。
- 当前只有 CI 证据，没有本次 Compact/plist migration 的实机证据。

## Next Task

安装 Artifact，验证：默认 Compact UI、`开/关` 文案、plist 旧 Registry 被清除、opaque FeatureID 状态 key、状态恢复，以及完整 IPA 重签/冷启动。之后进入 Offset/Patch Protection。
