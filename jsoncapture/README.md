# JSONCapture v0.4

Runtime collector/analyzer for the current HFAMap Unity iOS target.

## Output root

`Documents/JSONCapture/`

Important outputs:

- `JSONCapture.log` — v0.1 network/Foundation/decrypt capture.
- `IL2CPP_v0.4.log` — TextAsset / AssetBundle hook status and capture events.
- `LuaLoader_v0.3.log` — Lua VM loader input capture retained from v0.3.
- `textasset/` — raw TextAsset payloads.
- `lua_loader/` — loader input captured by v0.3.
- `lua53_analysis/` — v0.4 Lua 5.3 extraction and structural analysis.

## v0.4: Lua 5.3 format-1 analyzer

The verified runtime sample `TAB_Drop_1.lua` enters `tolua_loadbuffer` with header:

`1B 4C 75 61 53 01 19 93 0D 0A 1A 0A 04 04 04 08 08 78 56 ...`

This is Lua 5.3 (`0x53`) with format byte `1`. The observed header still contains five size fields (`sizeof(int)`, `sizeof(size_t)`, `sizeof(Instruction)`, `sizeof(lua_Integer)`, `sizeof(lua_Number)`), so v0.4 does **not** assume Tencent/xLua's `LUAC_COMPATIBLE_FORMAT` layout. It detects both layouts and reports which one actually matches the captured chunk.

For TextAsset payloads, v0.4 scans the first 32 bytes for an embedded `\x1bLua\x53` signature. This covers the verified `TAB_*` case where the raw TextAsset is four bytes larger than the Lua VM input.

For every unique clean Lua 5.3 chunk, `lua53_analysis/` receives:

- `<chunk>_<sha>.luac` — wrapper-stripped chunk, byte-for-byte from the detected Lua signature.
- `<chunk>_<sha>.analysis.json` — header/layout, endian, sizes, parse status, function/instruction/constant counts, opcode histogram, trailing bytes and wrapper offset.
- `<chunk>_<sha>.strings.txt` — unique UTF-8 strings recovered while parsing Lua prototypes/constants/debug data.

The parser understands standard Lua 5.3 prototype layout and supports the observed format-1 + official-size-field header as well as the xLua-compatible four-size-field variant.

## Opcode validation boundary

v0.4 checks that 32-bit instructions use opcode numbers in the stock Lua 5.3 range `0..46` and records a histogram. This is only a structural check. A zero `opcode_out_of_range_0_46` value does **not** prove that opcode meanings/order were not customized.

## Capture layers retained

- NSURLSession / NSURLConnection and Foundation JSON capture.
- `AesHelper.CustomDecryptString` / `CustomDecryptBytes` optional hooks.
- `UnityEngine.TextAsset::get_text` / `get_bytes`.
- `AssetBundle::LoadAsset` / `LoadAssetAsync` request logging.
- `LuaStatePtr::LuaLoadBuffer`, `tolua_loadbuffer`, `luaL_loadbuffer`, `luaL_loadbufferx` from v0.3.

## Safety / limits

Capture is read/copy only. It does not replace game data or redirect connections. TextAsset/Lua buffers are capped to avoid unbounded in-process copies. Runtime hook availability still depends on the injected environment.
