# Lua 5.3 Static Table Recovery Validation — 2026-09-15

## Result

`Recharge / Drop / Monster / MonsterEX` 已完成确定性离线恢复。

- 原始 `.luac` 未修改。
- 四个 chunk 均完整解析到 EOF，`trailing_bytes=0`。
- 静态 VM 执行未遇到 unsupported opcode。
- `format=1 -> format=0` 标准化副本仅修改 zero-based offset `5`。
- 每个原始 chunk 与对应标准化副本恢复出的 canonical semantic JSON SHA-256 完全一致。

## Results

| Table | Records | Instructions | Original SHA-256 | Normalized SHA-256 | Semantic SHA-256 |
|---|---:|---:|---|---|---|
| Recharge | 947 | 13201 | `f4ba8c5f902e2e0886e04a1046d27886c886140fa9537a5189c6b94b6ef134bc` | `e510c2abbc04c2f5f495a54c3440eef2e256b6af06c8db1d11f164e44dac05a3` | `9ab193847112623967b18c9258ea5bfd1e526fdc9b5b450282abbb2840dbc930` |
| Drop | 2001 | 23925 | `a3fe7f8952d3871252a2c3e8d00603e1965b21617eb81cc77378d14e192f3584` | `87761d94c498178dbe4b281dfad6bb9ad239471f760b653cfc9e046ba470ac04` | `73aecca81e87993c0281b2f2064f937c36b39c93db5b53289add62e76ae3778d` |
| Monster | 2001 | 104480 | `55d2f749f17b1657457fa474cadf422489b9d09dc4d09f512c75d5452a484008` | `273b2261d3c9c2fdf69004efbe817746f8fee0916ac223f9af86c87cd2eaa5f7` | `3fc148cc353bbb11b0e8f115a1c3149f8e5fcd79f490c94df1b7f8748f16c8c3` |
| MonsterEX | 2001 | 175009 | `1d2aa62a45f619da98c9759b0e6692a0adced0fd7b6e5ccb6e3863f1d627698b` | `e55238179920b4ac70801c3ebaf5c63194df43a1f1e2449aac9d60a1a95d6500` | `c489caf90bad9c250693ed0c876992721109e9f4f81a3ae7d82738a56399bb22` |

## Recharge historical cross-check

历史 `Recharge.test_channel_21825.json` 有 307 条：

- 忽略 `id`：295/307 与 recovered 数据内容完全一致。
- 忽略 `id/channel/des`：307/307 业务字段一致。
- 12 条 exact-content mismatch 均来自历史 `TEST-Pandora-21825` 测试渠道记录。

因此旧服务器文件可以解释为 recovered 客户端静态表的子集/运营修改版本，而不是恢复器随机生成的相似数据。

## Native Lua 5.3 loader status

**未执行。** 当前容器没有 `lua5.3/luac5.3`，同时外网 DNS 不可用。

当前已经验证的是：Lua 5.3 official-layout 结构、完整 EOF 解析、白名单 opcode 静态执行、format byte 单字节归一化、原始/归一化 semantic equality。后续如具备 Lua 5.3 环境，可对 `*.normalized-format0.luac` 再执行官方 loader / `luac -l` 作为额外验证。

## Tool

`tools/lua53_static_recover.py`
