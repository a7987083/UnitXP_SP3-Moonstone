# zonoe / HFASign v3 完整项目交接

> 本文面向完全看不到原聊天记录的新开发者或新 ChatGPT 会话。先完整阅读本文，再阅读 `docs/BUILD.md`、`docs/KNOWN_ISSUES.md` 和 `docs/TODO.md`。不要直接从 Ksign 最新分支重做，也不要重写现有架构。

## 1. 当前基线

| 项目 | 当前值 |
|---|---|
| 产品名称 | zonoe（工程历史名 HFASign v3，基于 Ksign/Feather） |
| 产品版本 | `3.0.0-alpha14` |
| 仓库 | `a7987083/UnitXP_SP3-Moonstone` |
| 开发分支 | `work/hfapatchipa-ksign-v3` |
| 原始交接提交 | `aa0c685d218b8d7b6e9f91dbe9a167aded5265fb` |
| 最后确认可编译的代码基线 | `fb14b5b604eb2dfa513450e89d4a23b095abe036` |
| 成品发布提交 | `d8327d431697a0a97955f30ef70aea914a5f8bfb` |
| 上游 Ksign 固定提交 | `03a3a9c86897d79f9faf8106037b9971841d56a0` |
| App 显示名 | `zonoe` |
| Bundle ID | `com.hfa.sign` |
| URL Scheme | `zonoe://` |
| 最低系统 | iOS 16.0 |
| 许可证 | GPL-3.0（沿用 Ksign/Feather） |

alpha14 保留 alpha12/alpha13 的分页、签名配置和 Source 解锁功能，同时恢复 alpha11 的稳定页面承载方式，并增量修复签名产物校验、Framework 分享、ZIP 导入/刷新/证书识别、解锁入口和 UDID Done 延迟。功能源码和 IPA 分别以 `fb14b5b` / `d8327d4` 为当前基线。

## 2. 最近一次成功构建与产物

- GitHub Actions workflow：`Build HFASign v3 alpha`
- Workflow 文件：`.github/workflows/hfasign-build.yml`
- 成功 Run：[33861862805](https://github.com/a7987083/UnitXP_SP3-Moonstone/actions/runs/33861862805)
- 触发提交：`fb14b5b604eb2dfa513450e89d4a23b095abe036`
- 状态：`completed / success`
- 开始：2026-09-04 10:09:27 UTC
- 完成：2026-09-04 10:20:48 UTC
- Actions Artifact 名称：`zonoe-v3.0.0-alpha14`
- 仓库内 IPA：`HFASign/dist/zonoe_v3.0.0-alpha14_TrollStore.ipa`
- SHA-256：`cea1f6e4ba0342b053d9882ef3b9e64d6601a716e50e604efcf381666670338c`
- 校验文件：`HFASign/dist/SHA256SUMS.txt`

该成功只证明 macOS/Xcode Release 编译、打包、ldid 签名和 workflow 内元数据检查通过，不等于全部功能已经在真机逐项验收。

## 3. 仓库的真实组织方式

本分支不是把完整 Ksign 源码直接提交到仓库，而是保存：

1. 固定的 Ksign 上游 commit；
2. `HFASign/patches/` 下的增量 patch；
3. GitHub Actions 在临时目录 `HFASignBuild/` 克隆并应用 patch；
4. 编译后把 IPA 提交到 `HFASign/dist/`。

因此文档中出现的 `Ksign/...` 路径，是 patch 应用后的临时构建树路径。修改功能时，应在一个固定到上游 commit 的本地 Ksign 工作树中修改，然后重新生成/更新最后的增量 patch，不能只在仓库中寻找 `Ksign/` 目录。

### 3.1 主要目录

| 路径 | 用途 |
|---|---|
| `.github/workflows/hfasign-build.yml` | 唯一权威的 CI 构建、打包、发布流程 |
| `HFASign/patches/0001...0015` | 从 Ksign 固定基线演进到 alpha14 的补丁链 |
| `HFASign/dist/` | 历代 IPA 和当前 SHA256 |
| `HFASign/README.md` | 项目基础说明、上游与许可证 |
| `HFASign/BUILD_ERROR.txt` | 历史失败构建的诊断文件；成功后未自动清空，不代表当前仍失败 |
| `docs/` | 本次新增的完整交接、构建、问题和待办文档 |

### 3.2 补丁应用顺序

Workflow 当前应用：`0001`、`0003`、`0004`、`0005`、`0006`、`0007`、`0008`、`0009`、`0010`、`0011`、`0012`、`0013`、`0014`、`0015`。

`0002-HFASign-alpha2-import-progress-and-Chinese.patch` **故意不应用**。后续补丁已经承接/覆盖相关改动；把 0002 加回会造成上下文冲突或重复修改。除非重新整理整条 patch stack，否则不要改变该顺序。

## 4. 已完成功能与核心源码

下表中的路径均指 patch 应用后的 Ksign 构建树。

### 4.1 品牌、导入、资源与基础签名

| 功能 | 核心文件 / 类型 |
|---|---|
| 品牌改为 zonoe、Bundle ID、版本、URL Scheme、文件类型 | `Ksign/Resources/Info.plist`，`Ksign.xcodeproj/project.pbxproj` |
| 图标替换 | Workflow 的 `Apply zonoe icon` 步骤；构建时下载并替换 AppIcon assets |
| Files/其他 App 分享导入 IPA、ZIP、证书、动态库 | `Ksign/Utilities/SharedImportCoordinator.swift`，`Ksign/Utilities/FR.swift`，`Ksign/FeatherApp.swift` |
| 导入进度与完成状态 | `Ksign/Backend/Observable/OperationProgressManager.swift`，`Ksign/Views/Common/OperationProgressView.swift` |
| 未签名/已签名 IPA 列表、批量选择、分享、删除、签名 | `Ksign/Views/Library/LibraryView.swift`，`LibraryCellView.swift` |
| 证书导入、密码提示、管理和删除 | `Ksign/Views/Settings/Certificates/*`，现有 CertificatePair/Storage 逻辑 |
| 签名过程详情、签名完成后分享/安装 | `Ksign/Views/Signing/SigningProcessView.swift`，`SigningView.swift`，安装相关 view/handler |
| IPA/TIPA 输出 | `SigningView.swift`、Archive/Signing handlers |

### 4.2 资源页与 ZIP / 动态库

| 功能 | 核心实现 |
|---|---|
| App / Zip / 动态库三类资源页 | `Ksign/Views/Library/LibraryView.swift` |
| 三页左右滑动 | alpha14 使用 alpha11 稳定的单页条件承载，加显式横向 `DragGesture`；避免分页 `TabView` 与签名页全屏导航争用事件 |
| ZIP 只读取 central directory，不先完整解压 | `LibraryView.swift` 内 `ZipContentsView.readEntries()` |
| 独立 `isLoading`，空 ZIP 不永久加载 | `ZipContentsView` 的 `isLoading` / `items` / `errorMessage` |
| dylib/deb/IPA/TIPA 点击后单文件按需提取 | `ZipContentsView.extractAndImport(_:)` |
| framework/bundle 合成目录项并按前缀提取整个目录 | `readEntries()`、`ZipPreviewItem.isDirectory`、`extractAndImport(_:)` |
| p12/pfx 证书 | 按需提取并进入证书导入页；同目录存在 mobileprovision/provisionprofile 时自动配对 |
| 中文 ZIP 文件名 | 优先保留 UTF-8；检测到 CP437 乱码特征时尝试 GB18030（兼容 GBK/CP936）解码 |
| Zip Slip 防护 | `safeArchiveRelativePath(_:)`、`safeOutputURL(for:root:)` |
| 拒绝绝对路径、盘符、UNC、NUL、越根路径、symlink | 同上，以及对 `ZIPFoundation.Entry.type == .symlink` 的检查 |
| 动态库导入到 `App/Tweaks` | `SharedImportCoordinator.shared.receive(...)` |
| 动态库依赖查看/修改 | `LibraryView.swift` 内 `StandaloneDylibDependenciesView` 及 Mach-O 工具逻辑 |

重要生命周期注意：当前 `extractAndImport(_:)` 在主线程调用 `SharedImportCoordinator.receive()` 后立即尝试删除临时根目录。虽然当前编译通过，但这是否会与异步复制竞争必须真机验证；如果出现 file-not-found，应让 coordinator 明确回调完成后再清理。

### 4.3 UDID 获取与 Provider URL Scheme

| 功能 | 核心文件 / 函数 |
|---|---|
| 本地服务 `127.0.0.1:14302` | `Ksign/Backend/Server/UDIDService.swift`，`UDIDService.start(completion:)` |
| `GET /profile.mobileconfig` | `UDIDService.profileData()` 动态生成 Profile Service 描述文件 |
| `POST /udid` | `UDIDService.extractUDID(from:)`，保存 `zonoe.deviceUDID` |
| UDID 更新通知 | `Notification.Name.zonoeDidUpdateUDID` / `zonoe.didUpdateUDID` 相关逻辑 |
| 内置 Safari 下载描述文件 | `Ksign/Views/Settings/SettingsView.swift` 内 `UDIDSafariView`（`SFSafariViewControllerRepresentable`） |
| Safari Done 生命周期 | `safariViewControllerDidFinish(_:)`，dismiss 后延迟调用 `UDIDService.openProfileSettings()` |
| 设置页跳转与 fallback | `UDIDService.openProfileSettings()`：依次尝试 `prefs:`/`App-Prefs:` 路径，最后 `UIApplication.openSettingsURLString` 并显示手动路径提示 |
| Provider URL | `zonoe://udid?callback=xxx://callback`，入口在 `Ksign/FeatherApp.swift`/URL 处理扩展 |
| Pending callback | UserDefaults 键 `zonoe.pendingUDIDCallback`；无 UDID 时保存 callback，POST 成功后回调 |
| callback 安全拼接 | `UDIDService.callbackURL(_:udid:)` 使用 `URLComponents`，保留已有 query 并替换/追加 `udid` |
| 设置 UI | `SettingsView` 的“本机 UDID”行和防重复 `_isStartingUDID` |

明确设计：描述文件是运行时动态生成，IPA 中没有也不需要静态 `.mobileconfig`；UDID 获取不需要 `p12`，不得把私钥或签名证书塞进 IPA。

### 4.4 软件源统一加载、兼容与剪贴板

| 功能 | 核心文件 / 类型 |
|---|---|
| 所有入口统一下载与解析 | `Ksign/Backend/Sources/SourceRepositoryLoader.swift`，`SourceRepositoryLoader.fetch(from:)` |
| 手动、剪贴板、URL Scheme、刷新统一导入 | 同文件内有效的 `SourceImportCoordinator`，`FR.handleSource()`，`SourcesAddView`，`SourcesViewModel` |
| 请求临时附加 UDID | `SourceRepositoryLoader.urlWithUDID(_:)`；不改变本地源身份 |
| AltStore / Feather / Ksign 等普通 JSON | `decode(_:sourceURL:)` → normalize → `ASRepository` |
| 全能签普通源 | 同一统一解析路径 |
| 全能签加密源 | `{ "appstore": "..." }`；DES-CBC + PKCS#7，KEY `esign_so`，IV `urce_enc` |
| 宽容 URL Normalizer | `normalizeURLs(_:key:path:)`、`isURLKey(_:)`、`tolerantURLString(_:)`、`repairURLString(_:)` |
| 空/坏 URL 降级 | URL key 空串或不可恢复值变为 `NSNull`；URL 数组中的空项被移除，避免单字段拖垮整个源 |
| 中文和空格 URL 修复 | `repairURLString(_:)` 分组件 percent-encode，避免整串重复编码 `%XX` |
| 缓存 | cache key 使用原始 source URL SHA-256；缓存重新加载同样经过 `decode()`/Normalizer |
| 详细错误分类 | `LoaderError` 区分网络、HTTP、HTML、JSON、Base64、DES、ASRepository codingPath、空 apps |
| Source URL 去重 | `SourceURLIdentity.normalized(_:)`、`localID(for:)`、`Storage.sourceExists(url:)`、`Storage.addSource(_:repository:)` |
| 不再以 repository.identifier 做本地唯一键 | 新增源的 local ID 基于规范化原始 URL；保留 repository ID 仅作内容 metadata |
| 剪贴板普通文字提取 URL | `SourceImportCoordinator.extractURLs(from:)` 使用 `NSDataDetector`，支持多 URL 与尾部标点清理 |
| 剪贴板 changeCount 防重复 | `SourceImportCoordinator.handleForeground()` / FeatherApp scenePhase |
| 验证后提示导入 | 候选 URL 先走 `SourceRepositoryLoader`，普通网页不保存；多个候选由 UI 逐个选择 |

注意：上游还留有旧文件 `Ksign/Backend/Sources/SourceImportCoordinator.swift`，alpha12 实际有效实现位于 `SourceRepositoryLoader.swift` 内并由补丁/project 状态决定。接手前必须用 `xcodebuild` 或 `project.pbxproj` 确认真正参与 target 的文件，不能同时启用两个同名 class。

### 4.5 软件源付费/卡密解锁（alpha12～alpha13）

| 功能 | 核心实现 |
|---|---|
| 解析源根字段 `payURL` / `unlockURL` | `SourceRepositoryLoader.captureMetadata(_:for:)` |
| 普通源和 DES 解密源都捕获 metadata | `decode` 与 `decodeEncrypted` 在 normalize/decode 前调用同一捕获逻辑 |
| 卡密解锁请求 | `SourceUnlockService.unlock(sourceURL:code:completion:)`，自动附加 `udid` 和 `code` |
| 下载地址为空时显示“解锁” | `Ksign/Views/Sources/Apps/DownloadButtonView.swift` |
| 打开购买地址 | `SourcePaySafariView` / `SFSafariViewController` |
| 输入卡密、成功后刷新 | `DownloadButtonView`，通知 `zonoe.sourceUnlocked`；`SourceAppsView` 接收后重新加载 |
| 详情页和列表页传递源上下文 | `SourceAppsCellView.swift`、`SourceAppsDetailView.swift`、`SourceAppsView.swift` |

协议参考是全能签公开源格式：根字段 `payURL`/`unlockURL`，unlock GET 查询 `udid`/`code`。实现没有写死域名。

### 4.6 高级/默认签名配置（alpha11-alpha12）

| 功能 | 核心文件 / 类型 |
|---|---|
| 打包文件名规则，多选、排序、分隔符、预览 | `Ksign/Backend/Observable/OptionsManager.swift` 的 `PackageNameRule`；`Ksign/Views/Signing/Shared/AdvancedRuleViews.swift` 的 `PackageNameRuleView` |
| 支持组成项 | 名称、版本号、Bundle ID、证书名称、时间戳 |
| 手动输出名覆盖本次规则 | `Ksign/Views/Signing/SigningView.swift` |
| 添加/替换 Info.plist | `PlistMutationRule`、`PlistRulesView`、`PlistRuleEditor`；`SigningHandler.applyPlistRule(_:to:)` |
| Plist 类型 | String、Bool、Number、Array、Dictionary、Data；支持点分隔 key path / 数组下标的现有实现范围 |
| 默认自动注入已选择动态库 | `Options.injectionFiles`、`SigningTweaksView`、`SigningOptionsView`、既有 SigningHandler 注入链 |
| 自动安装、钥匙串隔离、图标修复开关 | `Options` 的 optional 字段；`SigningOptionsView`；`SigningView` / `SigningHandler` |
| 旧配置兼容 | 新字段均 optional，旧 UserDefaults `signing_options` 仍可 JSONDecoder 解码 |

## 5. 当前未完成或未充分验收

这些项目不能在交接时写成“已实机稳定”：

1. **完整 alpha14 真机回归**：当前确认的是 CI 编译、IPA 产出和元数据；签名页点击链、真实证书安装、高级签名组合、ZIP 编码与第三方分享仍需逐项测试。
2. **UDID 私有 Settings URL**：`prefs:`/`App-Prefs:` 属于非公开行为，不同 iOS 版本可能只打开设置首页；fallback 已有，但目标页跳转必须在目标 iOS 真机验证。
3. **后台 localhost 存活**：从内置 Safari 到设置安装期间 App 可能挂起，`127.0.0.1:14302` 是否持续接受 POST 受 iOS 生命周期限制，必须真机验证。不能承诺系统一定让普通 App 长期后台运行服务。
4. **软件源卡密解锁协议差异**：当前 success 判定兼容 `success=true`、`success/ok/成功` 文本；不同服务端若返回其他 schema 需基于真实响应增量适配。
5. **同 repository.id 双源回归**：alpha13 已删除 `sourceURLByRepositoryID`，改为 UI 全链路显式携带原始 Source URL；仍需两个同 ID 源的真机回归。
6. **ZIP 临时目录清理时机**：需确认 `SharedImportCoordinator.receive()` 已完成实际复制后再清理，避免异步竞争。
7. **分享导入兼容性**：历史反馈是“某些 App 分享可导入、某些失败”；已做 public.data/document type 和共享入口改造，但尚无覆盖不同来源 App 的完整矩阵。
8. **签名后 IPA 安装失败历史问题**：签名链已经多轮修正并可打包，但证书类型、entitlements、provisioning、设备 UDID 的组合仍需用真实证书/设备验收。

详细内容见 `docs/KNOWN_ISSUES.md`。

## 6. 已失败/已放弃的方案（不要重复踩坑）

1. **浏览 ZIP 时完整解压**：会一直显示“正在读取压缩包”，大包严重阻塞。正确做法是 central directory 枚举，用户点击可导入项后才按需提取。
2. **用 `files.isEmpty && errorMessage == nil` 表示 loading**：空 ZIP 永久 loading。必须保留独立 `isLoading`。
3. **Zip Slip 使用 `path.contains("..")`**：会误伤合法路径和文件名。当前按 path component 栈正规化，再做 root directory 边界验证。
4. **点击安全文件时扫描到无关危险 entry 就让整个导入失败**：不合理。只校验选中的 entry/prefix；危险的无关 entry 不应阻止 `Good.dylib`。
5. **外部 Safari 获取 UDID**：无法收到 Done 生命周期。主流程必须使用 `SFSafariViewControllerDelegate`；外部 Safari只能做下载兼容 fallback。
6. **把 mobileconfig/p12 固定打进 IPA**：不需要且会引入私钥风险。继续运行时动态生成 Profile Service payload。
7. **callback 直接字符串拼 `?udid=`**：会破坏已有 query 和 URL 编码。必须使用 `URLComponents`。
8. **只把 `downloadURL == ""` 转 nil**：其他 URL 或非空坏 URL仍会令整个 ASRepository decode 失败。必须保留递归宽容 Normalizer。
9. **对整个 URL 使用 `.urlQueryAllowed` 编码**：可能破坏 `: / ? & = # %` 或重复编码已有 `%XX`。应按 component 修复。
10. **将所有解析失败覆盖为“不支持的软件源格式”**：丢失网络/HTTP/JSON/codingPath 信息。底层日志必须保留具体 `LoaderError`。
11. **剪贴板整段直接 `URL(string:)`**：无法处理“文字 + URL”。使用 `NSDataDetector`，并要求用户确认。
12. **用 repository.identifier 做本地源去重**：不同 URL 可能返回相同 identifier。新源身份必须来自规范化原始 Source URL，且请求临时追加的 `udid` 不参与身份。
13. **重新启用 patch 0002**：当前 patch stack 会产生重叠/冲突；workflow 故意跳过。
14. **alpha12 早期 SwiftUI 一行超复杂表达式**：造成 type-check/语法闭合失败。已在 `6bfc29e`、`2425a6f` 拆分 view builder 并补齐闭合。
15. **alpha12 资源列表用复杂 `flatMap/filter/sorted` 推断**：Xcode 编译器不稳定/耗时；`7d97fd9` 改成显式循环后成功。
16. **DownloadButtonView 新增 source 参数但详情页未传入**：`241b3ed` 已修复；新增入口时必须继续传 source。

## 7. 关键设计决策与禁止随意重构处

- 保持“固定上游 commit + 顺序 patch + CI 构建”作为可复现基线；不要直接跟随 Ksign HEAD。
- `SourceRepositoryLoader` 是所有软件源网络请求和解析的唯一入口；不要让 `ASDeobfuscator`/`NBFetchService` 再建第二套 Repository decode。
- ASDeobfuscator 仅负责从 ESign/MapleSign/KravaSign 文本中提取 URL。
- 软件源本地身份以规范化原始 Source URL 为主；repository ID 只是远端 metadata。
- UDID 请求时加入的动态 `udid` query 只用于网络请求，不保存回 sourceURL，不参与去重/cache identity。
- URL 宽容处理集中在 Loader，不大规模修改 `ASRepository.App/Version/News` 模型。
- ZIP 浏览不完整解压；Zip Slip 防护不能因误报而关闭。
- framework/bundle 必须按 package prefix 提取完整目录，不能只提取二进制。
- UDID 描述文件运行时生成；不得新增静态 mobileconfig、p12 或私钥。
- Pending callback 是完整 UDID Provider 的必要状态，不能在 UI 重构时丢失。
- 新增 `Options` 字段继续 optional 或提供自定义兼容 decode，避免旧配置升级崩溃。
- 不要把历史 `BUILD_ERROR.txt` 当成当前构建状态；以 Actions conclusion 和 `HFASign/dist` 为准。

## 8. 下一步接手入口

下一次开发不应先添加新功能，而应从 alpha14 真机验收开始：

1. 安装 `HFASign/dist/zonoe_v3.0.0-alpha14_TrollStore.ipa`，按 `docs/TODO.md` P0 矩阵测试。
2. 若高级签名异常，优先检查：
   - `Ksign/Views/Signing/SigningView.swift`
   - `Ksign/Views/Signing/Shared/SigningOptionsView.swift`
   - `Ksign/Views/Signing/Shared/AdvancedRuleViews.swift`
   - `Ksign/Backend/Observable/OptionsManager.swift`
   - `Ksign/Utilities/Handlers/SigningHandler.swift`
3. 若 ZIP 导入异常，检查 `LibraryView.swift` 的 `ZipContentsView.extractAndImport`、`safeArchiveRelativePath`、`safeOutputURL` 与 `SharedImportCoordinator.receive` 生命周期。
4. 若 UDID 异常，检查 `UDIDService.start/profileData/openProfileSettings/handlePendingCallback` 以及 `SettingsView._startUDID` / `UDIDSafariView.Coordinator`。
5. 若软件源异常，统一从 `SourceRepositoryLoader.fetch/decode/normalizeURLs` 跟踪；不要绕过 Loader。
6. 同 identifier 双源的代码修复已进入 alpha13；下一步用两个返回相同 ID、不同 `unlockURL` 的源做真机回归。

## 9. 给新 ChatGPT 的最小接手规则

新会话必须先执行只读检查：

```bash
git fetch origin
git switch work/hfapatchipa-ksign-v3
git pull --ff-only
git log -10 --oneline
sed -n '1,260p' docs/PROJECT_HANDOFF.md
sed -n '1,260p' docs/KNOWN_ISSUES.md
sed -n '1,260p' docs/TODO.md
sed -n '1,260p' docs/BUILD.md
```

然后确认最新 Actions 状态和 alpha14 IPA SHA256。除非用户明确要求，否则不要立即重写架构或开发新功能。
