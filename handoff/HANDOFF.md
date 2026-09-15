# HANDOFF

下一次对话/交接先确认以下真实状态：

1. 仓库：`a7987083/UnitXP_SP3-Moonstone`
2. 真机抓取器分支：`feature/json-capture-v0.4.1`；v0.4.1 已真机验证，不要先重做 Hook。
3. 当前恢复开发分支：`feature/lua53-static-recovery-v0.1`。
4. 离线恢复核心：`tools/lua53_static_recover.py`。
5. Windows GUI：`tools/lua53_static_recovery_gui.py`，v0.1.0。
6. Windows 构建工作流：`.github/workflows/build-lua53-static-recovery-windows.yml`。
7. GitHub Actions run `34973596147` 已成功完成 Windows x64 构建，source self-test、PyInstaller build、packaged EXE self-test、package/upload 全部 success。
8. 已构建：`Lua53StaticRecovery.exe`
   - PE32+ GUI / AMD64 x86-64
   - size: 12,344,667 bytes
   - SHA-256: `d67e82b070c53e73a856111f54056839151cc85d0f19a1d9e25ef13144fcfc3d`
9. 发布 ZIP：`Lua53StaticRecovery_Windows_x64_v0.1.0.zip`
   - SHA-256: `befaecb454e568d28347f7103544f6127da80c008421dba6627c00c5d693e485`
10. GUI 支持拖放 `.luac/.bin/.bytes`、目录批量加入、输出目录选择、批量恢复、SHA/format/instructions/records/status 展示和日志；原始输入不修改。
11. EXE 未做 Authenticode 签名，Windows SmartScreen 可能显示 unknown publisher；这是当前已知发布限制。
12. 四个 Lua 5.3 format=1 / official-layout 静态表均已确定性恢复：
   - Recharge：947 records
   - Drop：2001 records
   - Monster：2001 records
   - MonsterEX：2001 records
13. 四个原始 chunk 均解析到 EOF，`trailing_bytes=0`，恢复执行未遇到不支持 opcode。
14. 对每个原始 chunk 的副本仅修改 offset `0x05`：`LUAC_FORMAT 1 -> 0`；原始与标准化副本重建出的 canonical semantic JSON 完全一致。
15. 原始 `.luac` 未修改，Library 中已有四份原件，无需让用户重新上传。
16. Recharge 与历史 `Recharge.test_channel_21825.json` 交叉验证：忽略 id 后 295/307 完全一致；再忽略 channel/des 后业务字段 307/307 一致；其余 12 条是历史 `TEST-Pandora-21825` 测试渠道数据。
17. 尚未执行原生 `lua5.3/luac5.3` loader：当前容器没有 Lua 5.3 可执行文件且外网 DNS 不可用。该项是附加验证，不再阻塞四表恢复结果。

下一任务：

**从服务器恢复出的权威 `Recharge.json / Drop.json / Monster.json / MonsterEX.json` 与本次 recovered JSON 做逐 id / 字段 diff，区分历史人工渠道改动与真正版本差异，然后确定最终服务器落盘文件。**

重点服务器路径：

- `/home/ubuntu/runtime/json`
- `/home/ubuntu/runtime/wjson`
- `/home/ubuntu/runtime/www/def/Ios_json.txt`
- `/home/ubuntu/runtime/www/master/GM/tmp_process/resource_json.txt`
- `adv_gm.tt_update`
- `adv_gm.gm_resource`
