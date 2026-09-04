# zonoe / HFASign v3 待办清单

本清单以 `3.0.0-alpha12` 为基线。优先做验证和缺陷修复，不先扩展新功能。

## P0：发布阻断级

- [ ] 在目标 iPhone/iPad 通过 TrollStore 安装 alpha12，确认启动、资源页、设置页无崩溃。
- [ ] 使用真实 IPA + 真实证书执行普通签名，确认签名产物可安装、可启动。
- [ ] 分别验证 IPA/TIPA 输出、分享和安装按钮。
- [ ] 验证从“文件”及至少 3 个第三方 App 分享 IPA/ZIP/dylib/p12 到 zonoe，记录失败来源和 URL context。
- [ ] 验证 ZIP 根目录、子目录、中文目录 `.dylib` 导入。
- [ ] 验证无显式 directory entry 的 `.framework`/`.bundle` 完整导入。
- [ ] 验证 `../../evil`、绝对路径、盘符、UNC、NUL、symlink 仍被拒绝。
- [ ] 检查 `SharedImportCoordinator.receive()` 与 ZIP 临时目录删除是否存在异步竞争；若有，改成 completion 后清理。
- [ ] 验证 UDID：内置 Safari → Done → 设置 fallback → 安装 profile → POST → UI 更新。
- [ ] 验证外部 `zonoe://udid?callback=...` 无 UDID 时 pending callback 完整闭环。

## P1：alpha12 新功能验收

- [ ] 打包名规则：名称/版本/Bundle ID/证书/时间戳单选与多选组合。
- [ ] 拖动排序、下划线/连字符/空格/无分隔符、预览与实际文件名一致。
- [ ] 手工编辑输出文件名覆盖规则，扩展名不会重复。
- [ ] Info.plist 规则分别测试 String/Bool/Number/Array/Dictionary/Data。
- [ ] 测试点分隔 key path、数组下标、错误路径和非法值的用户提示。
- [ ] 设置默认动态库后，每次签名自动带入并正确注入。
- [ ] 测试自动安装、钥匙串隔离、深色/白色图标修复开关。
- [ ] 确认旧版本保存的 `signing_options` 可升级解码。
- [ ] 测试 App/Zip/动态库原生左右分页、选择状态、刷新与 VoiceOver/大字体。

## P1：软件源与解锁

- [ ] 回归 AltStore、Feather/Ksign、ESign、KravaSign、MapleSign、全能签普通源、DES 加密源。
- [ ] 实测 `app.ioszc.com/appstore`、`app.zonoeios.xyz/appstore`、`qnq.nuosike.cn/appstore`。
- [ ] 测试空 URL、坏 URL、中文 URL、自定义 scheme、截图 URL 数组容错。
- [ ] 测试手动输入、剪贴板自动检测、剪贴板批量、URL Scheme、保存源刷新得到一致结果。
- [ ] 两个不同 Source URL 但相同 repository.identifier 必须同时存在、分别刷新、分别删除。
- [x] 解锁 source 上下文已改为全链路显式传递原始 Source URL，不再使用 `sourceURLByRepositoryID` 反查；仍需真机双源回归。
- [ ] 对真实 payURL/unlockURL 服务测试购买跳转、卡密、错误码、过期/未购买状态。
- [ ] 对 HTTP 源验证 ATS 行为；当前 `NSAllowsArbitraryLoads=true` 仅适合当前分发场景，若上架需重新评估。

## P2：工程维护

- [ ] 把每个 alpha 的 patch 在干净上游基线上做 `git apply --check` 自动验证。
- [ ] 研究是否将 patch stack squash 为一个可维护补丁；只有在新分支完成全量 diff 对比和编译后才能做。
- [ ] 清理未参与 target 的重复 `SourceImportCoordinator.swift` / UDID Safari 文件，前提是先确认 project membership，避免删错有效实现。
- [ ] workflow 成功后自动清理或标记 `BUILD_ERROR.txt` 为历史，避免误判。
- [ ] 增加单元测试：SourceURLIdentity、URL Normalizer、callback URLComponents、safeArchiveRelativePath。
- [ ] 为 SourceRepositoryLoader 加 fixture 测试，包括直接 JSON 与 DES wrapper 的同一 decode path。
- [ ] 给 ZIP on-demand extraction 增加恶意 archive fixture。

## 明确未排入本阶段

- HFAPatch JSON/RVA 功能仍延后。
- 不在没有真机测试的情况下大规模改造架构。
- 不切换到 Ksign 最新 HEAD。
