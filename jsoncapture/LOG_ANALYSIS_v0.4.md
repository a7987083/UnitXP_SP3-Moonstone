# JSONCapture v0.4 runtime validation

Runtime test on 2026-09-15 proved the IL2CPP hooks are healthy but exposed an analyzer integration bug:

- TextAsset::get_text = 1
- TextAsset::get_bytes = 1
- AssetBundle::LoadAsset = 1
- AssetBundle::LoadAssetAsync = 1
- Object::get_name = 1
- TAB_Drop_1.lua, TAB_Monster_1.lua, TAB_Recharge_1.lua and TAB_MonsterEX_1.lua were captured as raw TextAsset payloads.
- No raw TextAsset payload was classified as `luacwrap` and no `LUA53-DETECTED` event appeared in IL2CPP_v0.4.log.

Conclusion: the earlier assumption that the VM-ready `\x1bLua\x53` chunk is embedded verbatim at raw TextAsset offset +4 is false for this build. The 4-byte size delta observed between raw TextAsset and `tolua_loadbuffer` input does not imply byte-for-byte prefix stripping.

Fix direction for v0.4.1: run `Lua53Analyzer` on the verified VM-ready buffer inside the Lua loader capture path (`tolua_loadbuffer` / `luaL_loadbuffer[x]` / managed LuaLoadBuffer), while keeping the TextAsset scan as an opportunistic path only.
