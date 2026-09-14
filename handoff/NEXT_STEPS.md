# NEXT_STEPS

## P0：恢复四个静态数据表 — DONE

已完成确定性离线恢复：

| Table | Records | Instructions | Status |
|---|---:|---:|---|
| Recharge | 947 | 13201 | recovered |
| Drop | 2001 | 23925 | recovered |
| Monster | 2001 | 104480 | recovered |
| MonsterEX | 2001 | 175009 | recovered |

共同验证：

- Lua 5.3 official-layout；原始 `LUAC_FORMAT=1`。
- 原始 chunk 全部解析到 EOF，`trailing_bytes=0`。
- 静态恢复执行无 unsupported opcode。
- format-0 副本只修改 zero-based offset `5`。
- 原始 format-1 与 format-0 副本恢复后的 canonical semantic JSON 完全一致。
- 原始 `.luac` 保持不变。

工具：`tools/lua53_static_recover.py`

## P1：服务器权威文件对比 — NEXT

拿到服务器恢复出的旧文件后：

1. 检查 `/home/ubuntu/runtime/json` 与 `/home/ubuntu/runtime/wjson`。
2. 定位 `Recharge.json / Drop.json / Monster.json / MonsterEX.json`。
3. 对 recovered JSON 做按 `id`、字段、记录增删的结构化 diff。
4. 把渠道/运营人工修改与客户端静态表版本变化分开。
5. 确认最终应部署到服务器的权威版本，并生成可审计 diff。
6. 再检查：
   - `/home/ubuntu/runtime/www/def/Ios_json.txt`
   - `/home/ubuntu/runtime/www/master/GM/tmp_process/resource_json.txt`
   - `adv_gm.tt_update`
   - `adv_gm.gm_resource`

## P2：原生 Lua 5.3 loader 验证 — OPTIONAL

官方 Lua 5.3 loader 会校验 `LUAC_FORMAT`。当前容器没有 `lua5.3/luac5.3` 可执行文件且外网 DNS 不可用，因此尚未执行原生 loader 测试。

这不阻塞已完成的数据恢复；若之后有 Lua 5.3 环境，只需对 `*.normalized-format0.luac` 执行原生加载/`luac -l` 作为额外一致性验证。
