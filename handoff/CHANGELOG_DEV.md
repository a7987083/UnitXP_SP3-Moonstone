# CHANGELOG_DEV

## 2026-09-15 — Lua 5.3 static recovery v0.1

### Added

- `tools/lua53_static_recover.py`
  - parses Lua 5.3 official-layout chunks;
  - accepts observed `LUAC_FORMAT=1` without mutating originals;
  - parses Proto / Code / Constants / Upvalues / child protos / debug sections;
  - executes an allow-listed static table construction opcode subset;
  - reconstructs `TAB_*[-1]` schema plus table records;
  - emits `.recovered.lua`, `.recovered.json`, `.recovered.meta.json` and format-0 copy.

### Recovered and run-validated

- `TAB_Recharge`: 947 records / 13201 instructions.
- `TAB_Drop`: 2001 records / 23925 instructions.
- `TAB_Monster`: 2001 records / 104480 instructions.
- `TAB_MonsterEX`: 2001 records / 175009 instructions.

All four:

- parsed to EOF with `trailing_bytes=0`;
- executed without unsupported opcode;
- normalized copy differs from original only at byte offset `0x05` (`1 -> 0`);
- original and normalized reconstruction produce identical canonical semantic hashes.

### Historical regression check

`Recharge.test_channel_21825.json`:

- 295/307 rows exact-match recovered content when ignoring id;
- 307/307 match business fields when ignoring id/channel/des;
- 12 remaining exact mismatches correspond to historical `TEST-Pandora-21825` test-channel entries.

### Not run

- No native `lua5.3/luac5.3` loader execution in current container: executable unavailable and outbound DNS unavailable.
- No server deployment performed.
- No new dylib build or device test was required in this phase; runtime capture baseline remains v0.4.1.
