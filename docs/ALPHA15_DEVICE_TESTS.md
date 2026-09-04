# zonoe v3.0.0-alpha15 真机回归清单

## P0：发布阻断

- [ ] 资源页 App / ZIP / 动态库可跟随手指连续移动，松手后吸附。
- [ ] 从 App 页打开 SigningView 后，证书、包内文件、插件、第三方库和高级选项均可轻点立即进入。
- [ ] SigningView 根页仅从屏幕左缘右滑时返回资源页；普通横向操作不误触返回。
- [ ] SigningView 子页使用系统左缘返回 SigningView，不直接关闭 SigningView。
- [ ] 使用 alpha11 已验证证书签名成功；失败时不生成成品 IPA。
- [ ] 成品包含非空 `Payload/*.app/embedded.mobileprovision`。
- [ ] 成品包含非空 `Payload/*.app/_CodeSignature/CodeResources`，主程序带有效签名。
- [ ] profile 的 TeamIdentifier、application-identifier 与最终 Bundle ID 匹配。
- [ ] TrollStore 安装成功并能启动。

## ZIP 与导入

- [ ] UTF-8 flag ZIP 的中文目录和文件名在预览、解压后完全一致。
- [ ] 未设置 UTF-8 flag 的 UTF-8 ZIP 在预览、解压后完全一致。
- [ ] GBK / CP936 / GB18030 ZIP 在预览、解压后完全一致。
- [ ] 带 Info-ZIP Unicode Path (0x7075) 的 ZIP 使用校验通过的 Unicode 名称。
- [ ] 中文路径中的 IPA、dylib、framework、p12 均可从预览直接导入。
- [ ] framework 没有显式目录 entry 时仍能识别并完整提取。
- [ ] `../`、绝对路径和符号链接不会写出临时提取目录。
- [ ] ZIP/IPA/动态库导入完成后，当前资源列表立即刷新。

## 软件源解锁

- [ ] `payURL` 与 `news.pay` 均能打开购买地址。
- [ ] `unlockURL` 与 `news.url` 均以 POST form 请求；卡密首尾空格被移除。
- [ ] 无 UDID 时点击“使用解锁码”不会显示可提交输入框，而是启动 UDID 流程。
- [ ] 获得 UDID 回到 zonoe 后，自动恢复到原软件源、原 App 的卡密输入。
- [ ] 输入框显示“取消 / 确定”；验证时显示“验证中…”且不能重复提交。
- [ ] 存在 `news.key` 时，仅 MD5(key + udid) 匹配才通过；伪造成功 msg 仍失败。
- [ ] 无 `news.key` 时，响应 msg 不单独授权；仅同 UDID 重取原 Source 后目标 App 出现下载 URL 才通过。
- [ ] 两个相同 repository.id、不同 URL 的 Source 不串锁；切换 UDID 不复用旧缓存。

## UDID 闭环

- [ ] 描述文件安装成功后 `/udid` 返回 302，并进入本地 `/done`。
- [ ] `/done` 的 JS、meta refresh 或“返回 zonoe”按钮至少一种能唤醒 `zonoe://udid-complete`。
- [ ] 系统阻止自动唤醒时，手动回到 zonoe 也会立即结束等待状态。
- [ ] 设置页主动获取 UDID 与软件源触发的获取流程都能完成。
