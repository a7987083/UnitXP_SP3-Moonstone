# CONVERSATION_SUMMARY

## 1. 项目背景

目标是恢复一个 Unity iOS 游戏的客户端/服务器运行链路，并建立可长期维护的运行时抓取工具。服务器原 IP 为 `118.145.146.208`，恢复目标服务器为 `43.242.203.214`。客户端启动配置中已确认：`ResVersion=7.3560.40`、`IOS_CHECK_PACK_VERSION=101`、`PACKAGE=hzflzb2`、`LOGIN_HOST=118.145.146.208`、`DownloadSmallPackage=true`。

## 2. 服务器与更新链

已明确存在两套更新系统，不能混淆。

### 基础/小包系统

客户端 `DownloadSmallPackage=true` 时请求：

`/master/GM/api/getresource?version=7.3560.40&channel=1860`

服务端返回当前版本的资源包，例如：

`7.3560.40_78002_1.zip ... 7.3560.40_78002_17.zip`

注意：query `channel=1860` 与文件名集合 `78002` 不是同一个 ID，不应互换。

### 真正热更新

链路：

`login_ing.php -> get_json(Ios) -> /home/ubuntu/runtime/www/def/Ios_json.txt -> adv_gm.tt_update -> up_packages`

真正的版本增量示例：`7.3560.40 -> 7.3560.41`。

相关服务器路径：

- `/home/ubuntu/runtime/json`
- `/home/ubuntu/runtime/wjson`
- `/home/ubuntu/runtime/www/def/Ios_json.txt`
- `/home/ubuntu/runtime/www/master/GM/tmp_process/resource_json.txt`
- `/home/ubuntu/runtime/regen-hotupdate-cache.py`

## 3. 启动配置加密

已知启动配置格式：

- AES key: `dlESILy2KaVstmJi`
- AES-128-ECB
- zero padding
- Base64
- 封装：`<16-byte ASCII key><Base64 ciphertext>`

## 4. JSONCapture v0.1

v0.1 用于广泛抓 JSON：网络、NSJSONSerialization、文件读取和 AesHelper 解密结果。

已真机证明以下 Hook 能命中：

- `AesHelper.CustomDecryptString`
- `AesHelper.CustomDecryptBytes`

由此抓到启动配置、资源入口 JSON、BundlesBuild 等。

关键 RVA：

- `CustomDecryptString`: `0x186A4B8`
- `CustomDecryptBytes`: `0x186FA64`

## 5. JSONCapture v0.2

v0.2 新增 IL2CPP 动态解析与 Hook：

- `TextAsset::get_text`
- `TextAsset::get_bytes`
- `AssetBundle::LoadAsset`
- `AssetBundle::LoadAssetAsync`
- `Object::get_name`

真机日志证明这些 Hook 全部通过 `MSHookFunction` 安装成功。

v0.2 抓到大量 `.lua.bytes`，包括：

- `TAB_Drop_*`
- `TAB_Monster_*`
- `TAB_MonsterEX_*`
- `TAB_Recharge_1`

在 TextAsset 层它们表现为 `format=bin`。

## 6. JSONCapture v0.3

v0.3 将观察点推进到 Lua loader：

- `LuaStatePtr::LuaLoadBuffer`
- `tolua_loadbuffer`
- `luaL_loadbuffer`
- `luaL_loadbufferx`

关键突破：同一批 TextAsset 二进制在真正进入 Lua VM 前变成：

`1B 4C 75 61 53 01 ...`

即 Lua 5.3 bytecode，`format=1`。

## 7. JSONCapture v0.4 / v0.4.1

v0.4 加入 `Lua53Analyzer`。第一版只在 TextAsset 原始数据上扫描，未命中 `LUA53-DETECTED`，因此确认 TextAsset 到 Lua loader 之间存在实际转换，而不只是机械裁前缀。

v0.4.1 将分析器接到 VM-ready 输入，真机成功：

- `tolua_loadbuffer=1`
- `luaL_loadbufferx=1`
- managed `LuaStatePtr::LuaLoadBuffer/3=1`
- 共抓到 `709` 个唯一 Lua-loader 输入
- `667` 个 `.luac`
- `42` 个可读 `.lua`

单独 `luaL_loadbuffer` 符号不存在，但不影响抓取。

## 8. 四个核心数据表闭环

### Drop
TextAsset: `124098 bytes`
Lua VM: `124094 bytes`
SHA-256: `a3fe7f8952d3871252a2c3e8d00603e1965b21617eb81cc77378d14e192f3584`

### Monster
TextAsset: `495130 bytes`
Lua VM: `495126 bytes`
SHA-256: `55d2f749f17b1657457fa474cadf422489b9d09dc4d09f512c75d5452a484008`

### Recharge
TextAsset: `66949 bytes`
Lua VM: `66945 bytes`
SHA-256: `f4ba8c5f902e2e0886e04a1046d27886c886140fa9537a5189c6b94b6ef134bc`

### MonsterEX
TextAsset: `804144 bytes`
Lua VM: `804140 bytes`
SHA-256: `1d2aa62a45f619da98c9759b0e6692a0adced0fd7b6e5ccb6e3863f1d627698b`

四个目标均稳定少 4 bytes，但由于 TextAsset 原始数据并未直接出现 Lua signature，不能简单断言为“去掉 4-byte prefix”。

## 9. Lua53Analyzer 最终验证

四份 analysis 均：

- `profile = lua53-format1-official-layout`
- `parse_ok = true`
- `trailing_bytes = 0`
- `signature_offset = 0`
- `opcode_out_of_range_0_46 = 0`

结构参数统一：

- header 33 bytes
- int 4
- size_t 4
- Instruction 4
- lua_Integer 8
- lua_Number 8
- little-endian

出现 opcode：`1,6,8,10,11,30,34,38,43`，高度吻合 Lua 5.3 标准 opcode 顺序。

## 10. 当前技术判断

不再把 `format=1` 直接当成 xLua compatible layout。目前证据支持：

`Lua 5.3 official chunk layout + LUAC_FORMAT=1 + 标准 opcode 编号高度吻合`

因此下一阶段不再改 Hook，而是对现有 `.luac` 做离线标准化和静态表重建。

## 11. 下一阶段目标

已有四个目标 `.luac`，下一步：

1. 确认 33-byte header。
2. 在副本上测试 `format 0x01 -> 0x00`。
3. 用 Lua 5.3 标准结构重新解析 Proto / Constants / Instructions。
4. 验证 opcode 语义。
5. 重建静态 Lua table。
6. 输出：
   - `Drop.lua / Drop.json`
   - `Monster.lua / Monster.json`
   - `Recharge.lua / Recharge.json`
   - `MonsterEX.lua / MonsterEX.json`

## 12. 当前阻塞

本地容器最近持续出现 `TransportTimeoutError`，导致无法直接读取/处理二进制 `.luac`。文件已上传，无需重复上传；容器恢复后直接继续离线解析。
