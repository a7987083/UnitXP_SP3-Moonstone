# HANDOFF

Current target: **JSONCapture v0.5.3 Runtime Capture 2**.

## Repository state

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/json-capture-v0.5.3-runtime-capture2`
- Stable baseline: `feature/json-capture-v0.5-manual-task-engine` @ `6e34d986e535ab548bcae28cdc3776bc8cf399bc` (v0.5.2)
- Artifact source commit: `0f4a4e500d796562d914fda17a86fd58fccb535c`
- Target: Unity 2019.4.33f1 / IL2CPP / ToLua / Lua 5.3.5 / arm64

## Architecture

### Runtime Capture 1 — retained from v0.5.2

`tolua_loadbuffer` / `luaL_loadbufferx` -> Lua chunk snapshot -> persistent MD5/SHA256 dedupe -> `ManualV05/lua_loader/`.

Only genuinely new runtime Lua captures preempt manual scan/decrypt/recovery. The v0.5.2 build-time cache patch remains enabled.

### Runtime Capture 2 — new in v0.5.3

Verified design chain:

`Cocos HttpResponse data` -> `cc.XMLHttpRequest.response/responseText` -> `lua_pushlstring(L, data, size)` -> Runtime Capture 2 hook -> `{`/`[` prefix filter -> full `NSJSONSerialization` validation -> MD5/SHA256 dedupe -> raw JSON write.

Important properties:
- No fixed game RVA.
- Does not depend on NSURLSession/Foundation networking.
- Uses the explicit Lua string length; embedded NUL/truncation assumptions are avoided.
- Only complete JSON dictionaries/arrays are stored.
- Non-JSON Lua strings are ignored without disk output.
- Duplicate valid JSON is skipped using an independent cross-launch cache.
- The raw JSON bytes are preserved as received by Lua.

Outputs:
- `Documents/JSONCapture/ManualV05/runtime_json/`
- `Documents/JSONCapture/ManualV05/runtime_json_manifest.jsonl`
- `Documents/JSONCapture/ManualV05/state/RuntimeCapture2.cache.jsonl`
- `Documents/JSONCapture/ManualV05/RuntimeCapture2.log`

## UI / switch semantics

The compact menu now shows `运行时抓取二` directly below the original `运行时抓取` status. Runtime Capture 2 reports state, hook readiness, new captures, skipped duplicates, persistent MD5-cache count and latest item/status using the same display semantics as Runtime Capture 1.

The existing `抓取：开/关` is the master switch. Turning it OFF disables both runtime capture paths; there is intentionally no independent Capture 2 toggle.

## Build validation

GitHub Actions run `35163998939` completed successfully on artifact source commit `0f4a4e500d796562d914fda17a86fd58fccb535c`.

Passed stages:
- source-contract checks;
- Theos arm64 compile;
- link / strip / sign;
- Mach-O and linked-framework inspection;
- binary string checks for both v0.5.2 cache and v0.5.3 Runtime Capture 2 markers;
- release packaging and artifact upload.

Artifact:
- ID: `10474680075`
- Artifact digest: `sha256:b443be2e68bf8964bf1854d9ebe20bb4866f43e1c7a480bfb3ff31c698c0f359`
- Dylib SHA256: `d4598db460df236df287c2b71764fd6b3feff23c488f80cf440b681eb872e17e`
- Release ZIP SHA256: `c278a6ee8a0b4591d83a386bb1012120a06e1f8d020aa8ab4a164c993715ba5d`

## Validation boundary

- Source implementation: **complete**.
- CI compile/package: **passed**.
- Artifact format/hash: **checked**.
- Real-device menu placement: **not yet validated**.
- Real-device `lua_pushlstring` hook readiness: **not yet validated**.
- Real-device byte-for-byte `xhr.response` capture: **not yet validated**.

## Next task

Install the v0.5.3 dylib in the same target where v0.5.2 was tested. Confirm both runtime rows show enabled/Hook-ready, toggle capture OFF/ON once, trigger a known GameHttp request, and return `runtime_json/`, manifest, RuntimeCapture2.log and a menu screenshot for regression verification.
