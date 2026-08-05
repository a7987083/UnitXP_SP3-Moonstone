# DreamAvatar · 梦境化身

DreamAvatar 是基于 `MoonMarker Hook Safety Stable` 的本地角色模型替换诊断模块。

## v0.1 Diagnostic 范围

- 只解析并修改 `UnitGUID("player")` 对应的本地玩家对象；
- 读取当前、原生和已保存的 Display ID；
- 应用数值 Display ID；
- 使用客户端已有的单位 Disable/Enable 流程刷新角色显示；
- 一键恢复进入游戏时保存的原始 Display ID；
- 可选自动维护：服务器把外观字段重置后，仅对本地玩家重新应用；
- 不接受目标 GUID，不修改队友、目标或其他单位；
- 不通过团队、工会或插件频道同步；
- 不重新引入 Creature DBC / Generated Creature / `SetDisplayInfo` 实验。

## 命令

- `/dreamavatar` 或 `/da`：打开或关闭界面；
- `/da 12345`：对自己应用 Display ID 12345；
- `/da restore`：恢复原模型；
- `/da status`：打开界面并刷新状态。

原生命令统一使用：

```text
MoonMarker.DreamAvatar.Status
MoonMarker.DreamAvatar.GetOriginal
MoonMarker.DreamAvatar.Apply
MoonMarker.DreamAvatar.Restore
MoonMarker.DreamAvatar.Refresh
MoonMarker.DreamAvatar.Maintain
MoonMarker.DreamAvatar.SetAutoMaintain
```

## GitHub Actions 命名

工作流：

```text
DreamAvatar · Build x86 DLL + AddOn Test Package
```

单次运行：

```text
DreamAvatar v0.1 Diagnostic · x86 DLL + AddOn · #运行编号
```

构建产物：

```text
DreamAvatar-v0.1-Diagnostic-x86-DLL-and-Addon-运行编号
```

这是诊断测试版，GitHub Actions 通过只能证明源码、Lua 5.1 与 PE32 x86 构建检查通过，仍需在 WoW 1.12.1.5875 / 乌龟服客户端实机验证。替换 DLL 前必须保留旧 DLL。
