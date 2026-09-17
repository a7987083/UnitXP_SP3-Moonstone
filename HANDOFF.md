# HANDOFF

Current target: **JSONCapture v0.5.3-r2 Runtime Capture 2**.

## Repository state

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/json-capture-v0.5.3-runtime-capture2`
- Stable baseline: `feature/json-capture-v0.5-manual-task-engine` @ `6e34d986e535ab548bcae28cdc3776bc8cf399bc` (v0.5.2)
- Artifact source commit: `e111d767347681fb2dbc769c0fcbca532990a1fc`
- Target: Unity 2019.4.33f1 / IL2CPP / ToLua / Lua 5.3.5 / arm64

## Regression record

The first v0.5.3 implementation globally hooked `lua_pushlstring`. It compiled and packaged successfully but failed real-device regression: the user reported an immediate crash after injection. That artifact is invalid for device use and must not be treated as a stable build.

v0.5.3-r2 removes the global `lua_pushlstring` hook completely.

## Architecture

### Runtime Capture 1 — retained from v0.5.2

`tolua_loadbuffer` / `luaL_loadbufferx` -> Lua chunk snapshot -> persistent MD5/SHA256 dedupe -> `ManualV05/lua_loader/`.

### Runtime Capture 2 — v0.5.3-r2

The new path is deliberately narrow:

`tolua_variable` registration -> recognize the exact Cocos `cc.XMLHttpRequest` property sequence -> replace only the registered `responseText` / `response` getter callbacks -> call the original getter -> read the single Lua result with `lua_tolstring(L, -1, &len)` -> JSONCapture-style validation/dedupe/write pipeline.

The Cocos registration sequence used as the discriminator is:

`responseType -> withCredentials -> timeout -> readyState -> status -> statusText -> responseText -> response`

Properties:
- No global `lua_pushlstring` hook.
- No fixed game RVA.
- If `tolua_variable` or `lua_tolstring` cannot be resolved, Capture 2 remains waiting instead of patching an unknown address.
- Only the two Cocos XHR response getters are wrapped after the registration sequence is recognized.
- Original getter runs first; Capture 2 observes its returned Lua value afterward.
- Uses the explicit Lua string length.
- JSON prefix gate (`{` / `[`) before copying/validation.
- Full `NSJSONSerialization` dictionary/array validation.
- MD5/SHA256 duplicate suppression and persistent cache.
- Raw JSON bytes are written asynchronously.
- Non-JSON, invalid JSON and duplicate JSON are skipped.

Outputs:
- `Documents/JSONCapture/ManualV05/runtime_json/`
- `Documents/JSONCapture/ManualV05/runtime_json_manifest.jsonl`
- `Documents/JSONCapture/ManualV05/state/RuntimeCapture2.cache.jsonl`
- `Documents/JSONCapture/ManualV05/RuntimeCapture2.log`

## UI / switch semantics

The compact menu shows `运行时抓取二` directly below `运行时抓取`.

The existing `抓取：开/关` remains the master switch. Capture 2 synchronizes from the actual master-button state after the original toggle executes and on periodic UI refresh; there is no independent Capture 2 switch.

Capture 2 status includes enabled state, hook state (`等待` / `监听` / `就绪`), recognized target getters (`0/2`..`2/2`), new captures, skipped count, cache count, and latest item/status.

## Build validation

GitHub Actions run `35165938481` completed successfully on source commit `e111d767347681fb2dbc769c0fcbca532990a1fc`.

Artifact:
- ID: `10475091794`
- Artifact name: `JSONCapture-v0.5.3-r2-RuntimeCapture2-ToLua535`
- Artifact digest: `sha256:4534b1a2e4b89f23626c32871ed6aef11bf9b94319320100ffcebb909f3fc835`
- Dylib SHA256: `f615df43c9acce677cfd709accfa4120c3e1fe96f786be6e99e497d6f6e72294`
- Release ZIP SHA256: `4c5688d27590f570aded8a6524d2997129e15e5a1f03ad6e022361b1e57e90ed`

Post-build local verification:
- Dylib format: Mach-O 64-bit arm64 shared library.
- Expected markers present: `JSONCapture v0.5.3-r2 Runtime Capture 2`, `tolua_variable`, `lua_tolstring`, `xhr.response`, `xhr.responseText`, RuntimeCapture2 cache/output paths.
- `lua_pushlstring` marker count in the built dylib: **0**.

## Validation boundary

- Source redesign: **complete**.
- CI compile/package: **passed**.
- Artifact format/hash/markers: **checked**.
- First v0.5.3 real-device injection: **failed (crash); superseded by r2**.
- v0.5.3-r2 real-device injection: **not yet validated**.
- v0.5.3-r2 target getter recognition (`2/2`): **not yet validated**.
- v0.5.3-r2 byte-for-byte `xhr.response` capture: **not yet validated**.

## Device acceptance test

Install only the r2 dylib. First confirm the game reaches the menu without crashing. Then check `运行时抓取二`:

- `Hook：监听` means the low-frequency ToLua registration hook installed but the target Cocos getter registration was not observed yet.
- `目标 2/2` means both `responseText` and `response` getters were recognized and wrapped.
- Toggle the existing master capture OFF/ON once and confirm both runtime rows follow it.
- Trigger a known `GameHttp` request and inspect `runtime_json/` plus `RuntimeCapture2.log`.
