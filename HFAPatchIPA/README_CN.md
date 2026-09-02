# HFAPatchIPA v1.0.0

面向 TrollStore 和越狱/AppSync 设备的无证书 IPA 菜单注入工具。

## 输入

- 用户自行解密的 IPA
- HFAMapUniversal 导出的 `com.hfa.patch/v1` 游戏数据包

## v1.0.0 流程

1. 将 IPA 和 JSON 复制到工具自己的 Documents。
2. 解包 IPA，读取 Info.plist 与主程序。
3. 精确校验 BundleID、游戏版本、Build、架构与目标模块 UUID。
4. 将每条 RVA 转换成对应 Mach-O Slice 的文件偏移。
5. 从解密后的二进制读取并核对 Original Bytes；任何一项不同即停止。
6. 将内置 `HFAPatchMenu_v0.1.0.dylib` 复制到游戏 Frameworks。
7. 写入 `HFAPatch/default.hfapatch.json`。
8. 向游戏主程序注入 `@executable_path/Frameworks/HFAPatchMenu.dylib`。
9. 使用 Zsign Ad-hoc 模式递归 Fake Sign。
10. 重新打包并导出带版本号 IPA 和处理日志。

HFAPatchIPA 不负责寻找功能和地址；HFAMapUniversal 不负责修改 IPA；菜单 dylib 不包含任何固定游戏数据。

## 构建依赖

- XcodeGen
- marmelroy/Zip 2.1.2+
- claration/Zsign-Package Feather 已验证提交 `6ffe703d`
- 内置 HFAPatchMenu v0.1.0

GitHub Actions 输出 `HFAPatchIPA_v1.0.0_TrollStore.ipa`。
