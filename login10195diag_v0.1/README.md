# Login10195Diag v0.1

用于授权私有测试项目的 **只读登录链路诊断**。目标是比较“正常设备”和“看不到区服的设备”为何在 `7001 / 10003` 之后出现分叉。

## 已确认的 dump.cs RVA

- `SDKInterface.onLoginSuccess` `0x2A674D4`
- `SDKInterface.GetAppInfoMessage` `0x2A67980`
- `SDKInterface.GetBuildVersionString` `0x2A683A4`
- `SDKInterface.GetVersionString` `0x2A68540`
- `SDKInterface.GetChannelID` `0x2A68CBC`
- `SDKInterface.onInitSuccess` `0x2A68E50`
- `SDKInterface.SDKLogin` `0x2A68F4C`
- `SDKInterface.IsSdkInit` `0x2A69078`
- `TcpNetwork.DoConnect` `0x1CC96B4`
- `TcpNetwork.SendMessage(byte[])` `0x1CCA124`

## 故意不 Hook 的入口

以下 RVA 虽然在 dump.cs 中存在，但 v0.1 不直接 Hook：

- `NetworkBase.SetHostPort` `0x1CC80D8`：与下一个函数只间隔 12 字节，直接 inline hook 风险偏高；改由 `TcpNetwork.DoConnect` 读取 `mIp +0x48 / mPort +0x50`。
- `NetworkBase.SendMessage` `0x1CC9204`：下一个函数位于 `0x1CC9208`，该方法仅 4 字节，属于高风险 tiny stub。
- `SDKInterface.onLoginFailed` `0x2A68860`：下一个方法位于 `0x2A68864`，同样是 4 字节 tiny stub。
- `NetworkBase.UpdateNetwork`：高频调用，对当前定位 10195 没有必要，避免制造大量日志和性能干扰。

## 诊断内容

日志文件：

```text
Documents/Login10195Diag.log
```

记录：

- SDKLogin 调用顺序
- IsSdkInit 返回值
- onInitSuccess / onLoginSuccess
- GetAppInfoMessage / GetChannelID / GetVersionString / GetBuildVersionString
- TcpNetwork.DoConnect 的 IP/端口
- TcpNetwork.SendMessage 的长度、协议 ID、seq、body 长度、前 128 字节 hex
- 命中 `10195` 时的 LR + backtrace，并输出 UnityFramework RVA

字符串记录同时输出长度和 FNV64，用于比较两台设备是否相同；preview 仅截取前 256 个 UTF-16 字符。

## 10195 帧识别

根据正常设备已抓到的真实帧，帧头为：

```text
[0..3]  body length, big-endian
[4..5]  message id, big-endian
[6..9]  sequence, big-endian
[10..]  protobuf body
```

正常 `10195` 示例对应：

```text
00 00 01 17 27 D3 00 00 00 03 ...
              ^^^^^ 0x27D3 = 10195
```

v0.1 只在 `byte[]` 满足该帧结构时报告 msgId；不会修改 payload，也不会强制发送 10195。

## 使用方式

把 dylib 注入待测 IPA，并分别在：

1. 正常设备启动到出现区服；
2. 异常设备启动到区服列表为空；

之后导出各自的 `Documents/Login10195Diag.log` 做差异比较。

## 构建

GitHub Actions 会在 macOS runner 上：

1. clone Dobby；
2. 用 iPhoneOS / arm64 配置 CMake；
3. 静态链接 Dobby；
4. 输出 `Login10195Diag_v0.1.dylib`；
5. 校验 Mach-O 架构；
6. 打包 ZIP artifact。
