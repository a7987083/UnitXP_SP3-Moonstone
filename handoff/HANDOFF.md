# HANDOFF

下一次对话/交接先确认以下真实状态：

1. 仓库：`a7987083/UnitXP_SP3-Moonstone`
2. 真机抓取器分支：`feature/json-capture-v0.4.1`；v0.4.1 已真机验证，不要先重做 Hook。
3. 当前恢复开发分支：`feature/lua53-static-recovery-v0.1`。
4. 离线恢复工具：`tools/lua53_static_recover.py`。
5. 四个 Lua 5.3 format=1 / official-layout 静态表均已确定性恢复：
   - Recharge：947 records
   - Drop：2001 records
   - Monster：2001 records
   - MonsterEX：2001 records
6. 四个原始 chunk 均解析到 EOF，`trailing_bytes=0`，恢复执行未遇到不支持 opcode。
7. 对每个原始 chunk 的副本仅修改 offset `0x05`：`LUAC_FORMAT 1 -> 0`；原始与标准化副本重建出的 canonical semantic JSON 完全一致。
8. 原始 `.luac` 未修改，Library 中已有四份原件，无需让用户重新上传。
9. Recharge 与历史 `Recharge.test_channel_21825.json` 交叉验证：忽略 id 后 295/307 完全一致；再忽略 channel/des 后业务字段 307/307 一致；其余 12 条是历史 `TEST-Pandora-21825` 测试渠道数据。
10. 尚未执行原生 `lua5.3/luac5.3` loader：当前容器没有 Lua 5.3 可执行文件且外网 DNS 不可用。该项是附加验证，不再阻塞四表恢复结果。

下一任务：

**从服务器恢复出的权威 `Recharge.json / Drop.json / Monster.json / MonsterEX.json` 与本次 recovered JSON 做逐 id / 字段 diff，区分历史人工渠道改动与真正版本差异，然后确定最终服务器落盘文件。**

重点服务器路径：

- `/home/ubuntu/runtime/json`
- `/home/ubuntu/runtime/wjson`
- `/home/ubuntu/runtime/www/def/Ios_json.txt`
- `/home/ubuntu/runtime/www/master/GM/tmp_process/resource_json.txt`
- `adv_gm.tt_update`
- `adv_gm.gm_resource`
