# NEXT_STEPS

## P0：恢复四个静态数据表

已有文件：

- `@src_datazb_TAB_Drop_1.lua_a3fe7f8952d3.luac`
- `@src_datazb_TAB_Monster_1.lua_55d2f749f17b.luac`
- `@src_datazb_TAB_Recharge_1.lua_f4ba8c5f902e.luac`
- `@src_datazb_TAB_MonsterEX_1.lua_1d2aa62a45f6.luac`

执行顺序：

1. 读取并确认 33-byte Lua 5.3 header。
2. 对副本测试 `LUAC_FORMAT 1 -> 0`。
3. 重新解析完整 Proto / Code / Constants / Upvalues / child protos。
4. 按 Lua 5.3 标准解码 A/B/C/Bx/Ax/sBx。
5. 验证 `LOADK / NEWTABLE / SETTABLE / SETLIST / RETURN` 等语义。
6. 重建静态 table。
7. 输出 `.lua`。
8. 再序列化为 `.json`。
9. 后续与服务器恢复出的旧 `Recharge.json / Monster.json / MonsterEX.json / Drop.json` 对比。

## P1：确认 format=1 的本质

当前证据：chunk layout 是标准 Lua 5.3 official-layout，opcode 编号也高度吻合标准 Lua 5.3。下一步只需通过副本验证标准 Lua 5.3 loader / parser 是否在仅修改 format byte 后完整接受。

## P2：服务器恢复继续排查

重点路径：

- `/home/ubuntu/runtime/json`
- `/home/ubuntu/runtime/wjson`
- `/home/ubuntu/runtime/www/def/Ios_json.txt`
- `/home/ubuntu/runtime/www/master/GM/tmp_process/resource_json.txt`
- `adv_gm.tt_update`
- `adv_gm.gm_resource`

## 当前阻塞

本地 container 最近持续 `TransportTimeoutError`。容器恢复后无需重新上传四份 `.luac`，直接继续。
