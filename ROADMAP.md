# ROADMAP

## Current — JSONCapture v0.5.3 Runtime Capture 2

Baseline: `feature/json-capture-v0.5-manual-task-engine` @ `6e34d986e535ab548bcae28cdc3776bc8cf399bc` (v0.5.2).
Current branch: `feature/json-capture-v0.5.3-runtime-capture2`.

- [x] Create an independent branch from the exact v0.5.2 HEAD; no history rewrite.
- [x] Keep the original Runtime Capture (ToLua/Lua loader capture) and v0.5.2 persistent MD5/SHA256 dedupe unchanged.
- [x] Add Runtime Capture 2 using exported Lua 5.3 `lua_pushlstring` as the capture boundary.
- [x] Accept only complete JSON object/array payloads that pass `NSJSONSerialization` parsing; ignore non-JSON strings.
- [x] Store Runtime Capture 2 output independently under `Documents/JSONCapture/ManualV05/runtime_json/`.
- [x] Add independent persistent MD5/SHA256 duplicate cache and manifest for Runtime Capture 2.
- [x] Add `运行时抓取二` immediately below the original runtime-capture status with matching status/count/cache/latest semantics.
- [x] Share the existing master capture switch: master OFF disables Runtime Capture and Runtime Capture 2.
- [x] Avoid fixed game RVAs for Runtime Capture 2; resolve exported `lua_pushlstring` dynamically.
- [x] GitHub Actions source-contract validation, arm64 Theos compile/link/sign, binary marker verification and release packaging.
- [x] CI run `35163998939` passed on artifact source commit `0f4a4e500d796562d914fda17a86fd58fccb535c`.
- [ ] Real-device validation: confirm both runtime rows show Hook ready and the shared switch disables both immediately.
- [ ] Real-device validation: trigger a known `GameHttp` request and confirm the complete response body appears in `runtime_json/` byte-for-byte.
- [ ] Regression: verify v0.5.2 Lua capture, manual scan, decrypt and JSON recovery remain unchanged on device.

### Next Task

Install the v0.5.3 artifact on the target game, capture one known `GameHttp` request, then collect `ManualV05/runtime_json/`, `runtime_json_manifest.jsonl`, `RuntimeCapture2.log` and a menu screenshot for device-level verification.

## Historical — g4 Chinese UI + On-device JSON Recovery

The older g4 recovery line remains historical context only. Its device validation state does not imply validation of v0.5.3 Runtime Capture 2.
