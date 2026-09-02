# HFAPatchMenu v0.1

HFAPatch 数据驱动通用菜单核心。面向 TrollStore 或越狱/AppSync 环境，不处理 P12 和描述文件。

## 当前功能

- 外部配置优先：`Documents/HFAPatch/config.json`
- 包内配置回退：`Game.app/HFAPatch/default.hfapatch.json`
- 精确校验 BundleID、版本、Build、架构、主程序/模块 UUID
- 仅接受目标模块已加载且 RVA 位于有效 Mach-O Segment 内的 Patch
- 写入前严格核对 Original/Enabled Bytes
- 单功能支持一个或多个 Patch
- 多 Patch 事务写入，失败时回滚本次已修改部分
- 关闭功能时恢复配置声明的 Original Bytes
- 记录开关状态并在下次启动时重新应用
- 外部配置可在菜单内重新读取
- 日志：`Documents/HFAPatch/HFAPatchMenu.log`

## 配置格式

正式 Schema：`schema/hfapatch-v1.schema.json`

核心字段：

```json
{
  "schema": "com.hfa.patch/v1",
  "package": {
    "bundleIdentifier": "com.example.game",
    "shortVersion": "1.0",
    "buildVersion": "100",
    "architectures": ["arm64", "arm64e"]
  },
  "targets": {
    "main": {
      "image": "@main",
      "uuid": "00112233-4455-6677-8899-AABBCCDDEEFF"
    }
  },
  "features": [
    {
      "id": "currency.freeze",
      "title": "Freeze Currencies",
      "group": "Currency",
      "patches": [
        {
          "target": "main",
          "offset": "0x1007DA74C",
          "original": "00008052",
          "enabled": "C0035FD6"
        }
      ]
    }
  ]
}
```

`offset` 是目标已加载 Mach-O Header 起点的 RVA，不是文件偏移或进程绝对地址。

## 本地检查

```sh
python3 tools/validate_hfapatch.py examples/example.hfapatch.json
```

## 构建

```sh
export THEOS=/path/to/theos
make clean
make FINALPACKAGE=1
```

输出 `.theos/obj/HFAPatchMenu.dylib`，包含 arm64 和 arm64e Slice。
