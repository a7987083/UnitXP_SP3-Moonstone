# PROJECT_STATE

## 当前目标

恢复并理解该 Unity iOS 游戏的运行时配置、资源更新与 Lua 数据表链路；同时维护一个可注入的 `JSONCapture` dylib，在真机运行时自动抓取网络 JSON、解密 JSON、TextAsset、AssetBundle 请求、Lua loader 输入以及 Lua 5.3 bytecode。

当前已经从“抓未知二进制”推进到“Lua 5.3 format=1 已完整解析”的阶段。

## 已验证事实

1. v0.1 的 AesHelper 解密 Hook 真机有效。
2. v0.2 的 IL2CPP Hook 真机有效。
3. v0.3 成功在 `tolua_loadbuffer` 抓到真正进入 Lua VM 的内容。
4. v0.4.1 已成功把 VM-ready 输入交给 Lua53Analyzer。
5. `TAB_Drop_1 / TAB_Monster_1 / TAB_Recharge_1 / TAB_MonsterEX_1` 四份 analysis 全部：
   - `parse_ok = true`
   - `trailing_bytes = 0`
   - `profile = lua53-format1-official-layout`
   - `opcode_out_of_range_0_46 = 0`
6. 当前最强格式判断：Lua 5.3、`format=1`、official-layout、opcode 编号高度吻合标准 Lua 5.3。
7. 四份目标 `.luac` 已上传到当前对话。
8. 当前阻塞点：本地容器曾持续 `TransportTimeoutError`，因此尚未完成离线标准化、反编译和静态表重建。

## 四个目标 bytecode

### TAB_Drop_1
- bytes: `124094`
- SHA-256: `a3fe7f8952d3871252a2c3e8d00603e1965b21617eb81cc77378d14e192f3584`
- instructions: `23925`
- constants: `3145`
- strings_unique: `8`

### TAB_Monster_1
- bytes: `495126`
- SHA-256: `55d2f749f17b1657457fa474cadf422489b9d09dc4d09f512c75d5452a484008`
- instructions: `104480`
- constants: `8547`
- strings_unique: `76`

### TAB_Recharge_1
- bytes: `66945`
- SHA-256: `f4ba8c5f902e2e0886e04a1046d27886c886140fa9537a5189c6b94b6ef134bc`
- instructions: `13201`
- constants: `1381`
- strings_unique: `307`

### TAB_MonsterEX_1
- bytes: `804140`
- SHA-256: `1d2aa62a45f619da98c9759b0e6692a0adced0fd7b6e5ccb6e3863f1d627698b`
- instructions: `175009`
- constants: `11546`
- strings_unique: `57`

## Lua 5.3 结构

四份 analysis 一致：

- `header_bytes = 33`
- `lua_version_byte = 83 (0x53)`
- `luac_format = 1`
- little-endian
- `sizeof_int = 4`
- `sizeof_size_t = 4`
- `sizeof_instruction = 4`
- `sizeof_lua_integer = 8`
- `sizeof_lua_number = 8`
- `root_upvalues = 1`

出现 opcode：`1, 6, 8, 10, 11, 30, 34, 38, 43`。

## 当前分支

- repo: `a7987083/UnitXP_SP3-Moonstone`
- 当前抓取器：`feature/json-capture-v0.4.1`
- handoff 分支：`handoff/jsoncapture-20260915`

## 用户固定发布要求

以后本项目所有发布包必须直接包含编译好的 `.dylib`，并在回复中明确 dylib 文件名、SHA-256、架构和下载包。
