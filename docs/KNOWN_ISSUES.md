# zonoe / HFASign v3 已知问题与验证状态

## 状态定义

- **CI 已验证**：GitHub Actions Release build/打包成功。
- **静态已验证**：代码与补丁路径已检查，未代表真机行为。
- **需真机验证**：iOS 生命周期、签名、安装或第三方服务行为无法仅靠 CI 证明。

## 当前问题

| 优先级 | 问题 | 当前判断 | 相关位置 | 状态 |
|---|---|---|---|---|
| P0 | 签名 IPA 在特定证书/设备组合下可能无法安装 | 需要区分 provisioning、entitlements、设备 UDID、证书类型与安装通道 | `SigningHandler.swift`、`ZsignHandler.swift`、安装模块 | 需真机验证 |
| P0 | UDID Done 后私有设置 URL 可能只打开设置首页 | `prefs:` / `App-Prefs:` 是非公开入口，iOS 版本间不稳定；已有手动 fallback | `UDIDService.openProfileSettings()` | 需真机验证 |
| P0 | App 进入设置后 localhost server 可能被 iOS 挂起 | Profile Service POST 依赖 `127.0.0.1:14302`；普通后台执行时间不保证 | `UDIDService`、background task 配置 | 需真机验证 |
| P0 | ZIP 临时目录可能过早删除 | `SharedImportCoordinator.receive()` 若异步读取，调用后立即删除 root 可能竞争 | `LibraryView.ZipContentsView.extractAndImport` | 需真机验证/可能修复 |
| P1 | 两个相同 repository.id 的源可能共享错误解锁 URL | alpha13 已移除 repository ID 反查，列表、详情和下载按钮显式携带原始 Source URL | `SourceAppsView`、`SourceAppsTableRepresentableView`、`DownloadButtonView` | 静态已修，待真机双源回归 |
| P1 | 不同第三方 App 分享导入兼容性不一致 | 已扩展 document type 和统一导入入口，但来源 App 的 security-scoped/URL 生命周期不同 | `SharedImportCoordinator`、`FR`、`FeatherApp` | 需来源矩阵 |
| P1 | 解锁服务响应 schema 不统一 | 当前兼容 bool success 和文本 success/ok/成功，其他字段需按实际服务器响应适配 | `SourceUnlockService.unlock` | 需实服验证 |
| P1 | 高级 Plist 规则复杂类型边界 | Array/Dictionary/Data 的输入解析、数组下标和错误 key path 尚无完整真机测试矩阵 | `SigningHandler.applyPlistRule`、`AdvancedRuleViews` | CI 已编译，待验收 |
| P2 | `BUILD_ERROR.txt` 留在成功分支 | 这是历史失败诊断，不代表 alpha12 当前失败 | `HFASign/BUILD_ERROR.txt` | 文档说明即可 |
| P2 | 源树可能存在未加入 target 的重复定义文件 | 有旧 `SourceImportCoordinator.swift` 和历史 UDID Safari 文件；当前成功构建证明 target 未同时编译冲突定义 | project membership / patch stack | 清理前先确认 |

## 已确认结果

### CI / 产物

- `macos-26` GitHub Actions Run 33810234557：成功。
- Release iphoneos generic build：成功。
- ldid 处理 App 主二进制和 Frameworks：成功。
- TrollStore IPA 打包：成功。
- 元数据检查通过：显示名 `zonoe`、Bundle ID `com.hfa.sign`、版本 `3.0.0`、文件导入 UTI `public.data`。
- IPA SHA-256：`1542128d46df495652c4dd93a9318c42754f746f607e756a49af3ec36dd93559`。

### 尚不能宣称的结果

- 不能仅凭 CI 宣称所有真实证书签名出的 IPA 均可安装。
- 不能宣称私有 Settings URL 在所有 iOS 16～26 都直达描述文件安装页。
- 不能宣称 App 被挂起后 localhost 一定持续在线。
- 不能宣称所有第三方全能签服务器都使用相同解锁响应格式。
- 不能宣称 alpha12 所有高级签名组合已经真机逐项通过。

## 历史失败构建与原因

| 提交/阶段 | 失败点 | 修复 |
|---|---|---|
| alpha12 首轮 | `DownloadButtonView` 增加 `source` 后，详情页仍用旧初始化参数 | `241b3ed` 在 `SourceAppsDetailView` 传入 source |
| alpha12 retry | Source metadata 映射、SwiftUI 类型推断和表达式存在编译错误 | `6bfc29e` 拆分表达式并补全 source mapping |
| alpha12 retry 3 | `AdvancedRuleViews` 的 `List/Section` view builder 闭合错误 | `2425a6f` 补齐闭合，拆开 footer section |
| alpha12 retry 4 前 | 资源文件列表高阶链式推断导致编译不稳定/失败 | `7d97fd9` 改为显式 roots/allowedExtensions/循环/sort |
| 最终 | merge commit `6570b90` 触发 Run #46 | 构建成功并由 `af52f2a` 发布 IPA |

## 回归时日志要求

发生问题时至少保留：

- iOS 版本、设备型号、安装方式；
- 使用的证书类型、profile 类型和是否包含设备 UDID；
- zonoe 日志页完整内容；
- SourceRepositoryLoader 的具体 LoaderError/codingPath，不能只报“格式不支持”；
- ZIP entry 原始 path、正规化 path、选中的 prefix；
- UDID server 的 GET/POST 时间点以及 App 当时前台/后台状态；
- 崩溃日志或系统安装错误原文。
