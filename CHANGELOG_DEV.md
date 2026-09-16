# CHANGELOG_DEV

## 2026-09-17 — v0.5.3 Runtime Capture 2

Branch: `feature/json-capture-v0.5.3-runtime-capture2`
Base: `6e34d986e535ab548bcae28cdc3776bc8cf399bc` (v0.5.2)
Artifact source commit: `0f4a4e500d796562d914fda17a86fd58fccb535c`

Implemented:
- Added `JCG53RuntimeCapture2.h/.m`.
- Runtime Capture 2 hooks exported Lua 5.3 `lua_pushlstring`; it does not depend on NSURLSession or a fixed Cocos/Unity RVA.
- Fast prefix filter accepts only candidate `{` / `[` strings; full validation requires `NSJSONSerialization` to parse a complete dictionary/array.
- Original JSON bytes are written unchanged to `Documents/JSONCapture/ManualV05/runtime_json/`.
- Added `runtime_json_manifest.jsonl`, `RuntimeCapture2.cache.jsonl` and `RuntimeCapture2.log`.
- Added independent persistent MD5/SHA256 dedupe; already-seen valid JSON is skipped across launches.
- Added `JCG53RuntimeCapture2UI.m`; menu displays `运行时抓取二` below the first runtime-capture status with matching new/skip/cache/latest fields.
- Existing `抓取：开/关` remains the single master switch; Runtime Capture 2 follows the same state.
- Existing v0.5.2 Runtime Capture, scroll/drag UI, manual scan/decrypt/recovery and runtime Lua cache are retained.

Evidence used for the hook boundary:
- Cocos2d-x `cc.XMLHttpRequest` `responseText` and `response` push `getDataStr()` with `getDataSize()` through `lua_pushlstring`.
- Previously captured target `GameHttp` Lua bytecode reads `xhr.response` and passes it to `json.decode`.

Validation:
- Source contract: passed.
- Theos arm64 compile/link/strip/sign: passed.
- GitHub Actions run: `35163998939` — success.
- Built dylib: Mach-O 64-bit arm64.
- Dylib SHA256: `d4598db460df236df287c2b71764fd6b3feff23c488f80cf440b681eb872e17e`.
- Release ZIP SHA256: `c278a6ee8a0b4591d83a386bb1012120a06e1f8d020aa8ab4a164c993715ba5d`.
- GitHub artifact ID: `10474680075`; artifact digest: `sha256:b443be2e68bf8964bf1854d9ebe20bb4866f43e1c7a480bfb3ff31c698c0f359`.
- Real-device Runtime Capture 2: **not yet validated**.

## 2026-09-17 — g4 Chinese UI + on-device JSON recovery

Branch: `feature/json-capture-v0.4.2-g4-chinese-ui-recovery`
Base: `d0c10fc1d4df1ab0e8151f4a91ae3bca050242f3` (g3 persistent incremental)

Added:
- `GenericG4ChineseUI.m`: Chinese compact floating overlay and control surface.
- `OnDeviceLuaRecovery.h/.m`: native ENCM re-decrypt + static Lua 5.3 -> JSON recovery.
- Capture-priority scheduling for historical re-decrypt and JSON recovery.
- Persistent mobile recovery/decrypt index, report and status files.
- Complete and partial JSON output directories.
- UI actions for scan control, force scan, re-decrypt, re-recover, incremental recovery, JSON directory, report export and index management.

Build fixes:
- Typed the UI label dictionary so keyed subscripting produces `UILabel *`.
- Suppressed one intentional unused helper warning that Theos promoted to an error.
- CI binary validation now uses ASCII markers; Chinese NSString literals are validated at source-contract stage.

Validation:
- Source contract: passed.
- Theos arm64 compile/link/sign: passed.
- GitHub Actions run: `35134708046` — success.
- Artifact source commit: `e1ab528ad2eadfd22fef56be48eb5baa06988081`.
- Dylib SHA256: `9a6c48526c0fbd8a2bb0333edc97f9e4b904f4e472b56af608eb23c76b76970c`.
- Release ZIP SHA256: `c994666cca1cedfc22ee07e55a00b815117ec26cd5de9764d06f3c55aff019d0`.
- Real-device g4 UI/recovery: pending.
