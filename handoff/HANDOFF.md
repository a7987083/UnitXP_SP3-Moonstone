# HANDOFF

下一次对话/交接时先记住：

1. 仓库：`a7987083/UnitXP_SP3-Moonstone`
2. 当前抓取器分支：`feature/json-capture-v0.4.1`
3. v0.4.1 已真机成功，不需要先重做 Hook。
4. Lua VM-ready 输入已确认是 Lua 5.3 bytecode。
5. 四个目标 analysis 均 `parse_ok=true`、`trailing_bytes=0`。
6. 当前格式判断：`Lua 5.3 + format=1 + official-layout`。
7. opcode 编号高度吻合标准 Lua 5.3。
8. 四个目标 `.luac` 已上传过，不要让用户重复上传。
9. 下一步直接离线恢复 `Drop / Monster / Recharge / MonsterEX` 静态表。
10. 若本地容器仍报 `TransportTimeoutError`，只说明阻塞，不要伪造反编译结果。

建议下一次直接从：

`继续解析四个 .luac，先处理 Recharge，再处理 Drop。`

开始。
