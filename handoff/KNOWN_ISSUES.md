# KNOWN_ISSUES

## KI-001 — Native Lua 5.3 loader validation not executed

Status: **OPEN / non-blocking**

Condition: current container does not provide `lua5.3` or `luac5.3`; outbound DNS/network fetch from the container is unavailable.

Verified instead:

- Lua 5.3 official-layout parsing;
- complete EOF consumption;
- static opcode execution;
- only byte offset `0x05` changes during format normalization;
- semantic equality between original format-1 and normalized format-0 reconstructions.

Next validation: run official Lua 5.3 loader or `luac -l` on normalized copies when a suitable runtime is available.

## KI-002 — Server authority not yet established

Status: **OPEN / blocking final deployment**

The client-derived static tables are recovered, but server-restored `Recharge.json / Drop.json / Monster.json / MonsterEX.json` may contain intended channel/operator/version-specific edits.

Do not blindly overwrite server files with recovered client data.

Next validation: obtain the restored files from `/home/ubuntu/runtime/json` and `/home/ubuntu/runtime/wjson`, produce a structured diff, classify intended modifications, then select the deployment source.

## KI-003 — Historical Recharge file is modified/subset data

Status: **UNDERSTOOD**

The available 307-row `Recharge.test_channel_21825.json` is not a byte-for-byte baseline for the 947-row recovered client table. It contains historical channel/test edits including 12 `TEST-Pandora-21825` rows.

Use it only as regression evidence, not as the final authoritative full-table source.
