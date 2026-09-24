# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.5.1 Recovery

### 根因

- 真机反馈更换 M5.5 后，制作页原有内容/Runtime Method Call 条目缺失。
- 审计确认 `ZNRuntimeActionStore` 历史上只使用进程内 `NSMutableArray`，没有 authoring 持久化；换 dylib、杀进程或重启后旧条目会丢。
- M5.5 同时改写了 Builder 控件布局，增加了恢复风险。

### 实际修复

- `ZNFeatureBuilderControlsV2.mm` 恢复为 M5.4 已验证的 Builder 基础布局，不再用四列 Typed 控件替换基线几何。
- Runtime Method Call 卡片的 `删除` 按钮移到标题行右上角；参数区下移并增加卡片高度/卡片间距。
- 新增 `ZNM551AuthoringPersistence.mm`。
- 持久化 key：`zonoe.m5.5.authoring-actions.v1`。
- 保存字段：title、assembly、namespace、class、method、argc、argumentValues、parameterTypeNames、signatureAvailable、argumentControlConfigs、immediateChain。
- 在 create / rename / argument edit / control edit / Value Type+Range edit / chain edit / delete / clear 后自动写入。
- 启动时仅当内存 Store 为空时自动恢复，避免覆盖同进程已有 authoring state。
- 版本标识改为 `0.5.8 · M5.5.1` / `Recovery · M5.4 Builder Baseline · Persistent Authoring`。

### CI / artifact

- Run `36002343325` / Job `107641806291`: Source Contract、arm64 Build、Binary Verify、Artifact Upload 全部 SUCCESS。
- Artifact ID `10808925953`。
- ZIP SHA256 `f8c813ae0c9bd10b376c58e510f3767633866e803f55f396040caa9efb02eeac`。
- Dylib size `1404688` bytes。
- Dylib SHA256 `bf3ffc1c75c27bae19a6d03a7e6dc93d5e23c9953143fb024267f8705d679453`。
- Mach-O: thin arm64 dylib。

### 边界

- M5.5.1 开始可以防止以后 authoring 数据随进程重启丢失。
- 在 M5.5.1 之前已经只存在内存且已经丢失的条目，没有可靠序列化源时无法自动恢复；不能根据截断截图猜完整方法身份。

## 2026-09-24 — M5.5 Typed Control Binding V2

- 新增 `Auto / I32 / U32 / I64 / U64 / F32 / F64`。
- 控件保持 `Switch / Button / Number / Slider`。
- Runtime Auto 根据 IL2CPP managed signature 推断数值类型；Runtime Range 支持 Default/Min/Max/Step。
- Static 后端支持验证过的 MOVZ(+MOVK) 整数与 scalar FMOV S/D immediate，错误编码 fail closed。
- Final M5.5 Run `35996840472`, dylib SHA256 `0dacef0f731d0a6b59e1446b08977d69a6eeb732096c761a9ed321be0214375a`。

## Historical anchors

- M5.4 Unified CI green: `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845` / Run `35964757740`.
- M5.3 Control Binding initial green: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`.
- M5.2 core multi-level chain: `2456f6ba4dfb659e3480db2e677452dad8516153`.
- M5.1 Silent Customer Execution: `29c33d9246fd9842107c443d3254aff23effd59e`.
