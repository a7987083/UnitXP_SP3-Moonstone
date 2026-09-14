# PROJECT_STATE

## 当前阶段

`JSONCapture` 真机抓取链路保持稳定基线；四个目标 Lua 5.3 静态数据表已完成离线确定性恢复。当前阶段已从 **Lua bytecode reconstruction** 切换到 **服务器权威 JSON 对比与最终落盘确认**。

## 分支

- repo: `a7987083/UnitXP_SP3-Moonstone`
- 真机抓取稳定基线：`feature/json-capture-v0.4.1`
- handoff：`handoff/jsoncapture-20260915`
- 当前工作分支：`feature/lua53-static-recovery-v0.1`

## 已验证

1. v0.4.1 真机运行时抓取已验证，不需要重做 Hook。
2. 四份目标均为 Lua 5.3 / format=1 / official-layout。
3. 四份原始 chunk 均完整解析到 EOF，`trailing_bytes=0`。
4. 离线恢复器仅执行静态表构造所需白名单 opcode；本批四表未遇到 unsupported opcode。
5. 对副本仅修改 byte offset `0x05`：`LUAC_FORMAT 1 -> 0`；四份原始与标准化副本恢复出的 canonical semantic JSON 分别完全一致。
6. 原始 `.luac` 均未修改。
7. Recharge 与历史 307-row `Recharge.test_channel_21825.json` 交叉验证：295/307 在忽略 id 后完全一致；忽略 id/channel/des 后 307/307 业务字段一致；12 条差异为历史测试渠道数据。

## 恢复结果

| Table | Records | Instructions | Original SHA-256 |
|---|---:|---:|---|
| Recharge | 947 | 13201 | `f4ba8c5f902e2e0886e04a1046d27886c886140fa9537a5189c6b94b6ef134bc` |
| Drop | 2001 | 23925 | `a3fe7f8952d3871252a2c3e8d00603e1965b21617eb81cc77378d14e192f3584` |
| Monster | 2001 | 104480 | `55d2f749f17b1657457fa474cadf422489b9d09dc4d09f512c75d5452a484008` |
| MonsterEX | 2001 | 175009 | `1d2aa62a45f619da98c9759b0e6692a0adced0fd7b6e5ccb6e3863f1d627698b` |

恢复工具：`tools/lua53_static_recover.py`

## 尚未验证

当前环境没有 `lua5.3/luac5.3` 可执行文件，且容器外网 DNS 不可用，因此尚未用官方原生 loader 执行 `*.normalized-format0.luac`。这是附加验证项，不阻塞已经完成的静态表恢复和语义一致性验证。

## Next Task

从服务器恢复数据中找到权威：

- `/home/ubuntu/runtime/json/{Recharge,Drop,Monster,MonsterEX}.json`
- `/home/ubuntu/runtime/wjson/{Recharge,Drop,Monster,MonsterEX}.json`

逐 id / 字段 diff 本次 recovered JSON，并继续核查 `Ios_json.txt`、`resource_json.txt`、`adv_gm.tt_update`、`adv_gm.gm_resource`，最终确定服务器应部署的版本。

## 发布要求

所有后续涉及 dylib 的正式发布包必须明确提供：编译产物文件名、SHA-256、架构、下载包，并区分“已编译 / 已运行 / 已真机验证 / 已回归验证”。
