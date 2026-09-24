# ROADMAP

## Current milestone — M5.2 Immediate Chain V2 + Finder UX closure

Branch: `feature/runtime-patch-menu-v0.5.8-m5.2-immediate-chain-v2`

CI-validated product head: `2d36ffcc333936e41809039e161baf52e24abba9`

Implemented:

- M5.1 per-argument authored controls retained: fixed / Switch / Button / Number / Slider.
- Customer successful Runtime/Button/Immediate Chain execution stays silent; failures keep `执行失败`; Builder / Method Finder test surfaces keep return/debug information.
- Immediate Chain V2: versioned `nodes[]`, root + up to 8 additional typed `/0-/8` nodes, exact signature preflight, token/return-type guards when available, M5.0 GCHandle/validated receiver reuse, System.String UTF-16 decode, per-level trace and atomic execution.
- Runtime Action ABI remains version 1 / 64-byte entries; V2 chain metadata continues through `reserved[4]`.
- Final generated Runtime-only and Static Mach-O names remain suffixless.
- Finder chain UX is now stateful in-place: before authoring the button is `链式调用`; after `完成链` and re-render the same Finder action becomes `执行链`.
- Single tap `执行链` executes the saved V2 transaction through `ZNIL2CPPInvokeEngine` and keeps final return + level trace on the developer/test surface.
- Long-press `执行链` clears that action's current Immediate Chain and immediately re-enters the chain authoring flow.
- Method-name search history is persistent via NSUserDefaults. It is rendered directly below the search box, one query per row, independently scrollable, newest-first, case-insensitive deduplicated, capped at 50, and a row tap re-runs that query.

CI/build status:

- Final UX-closure Run `35944304515`: SUCCESS
- Job `107458736244`: SUCCESS
- Artifact ID `10785804614`
- Artifact ZIP SHA256 `6596398f82a733fbe901be42e18960da3c4d212f479e7f73cf8253be7fbf210f`
- Dylib SHA256 `44eb45dd5643c8256bc0393c0117dc56a5b8836d2ef0a019a28cafb6a97d68d7`
- Dylib size `1321136` bytes
- Mach-O: thin arm64 dylib
- Independent ZIP/dylib hash verification: PASS

Device acceptance still required:

1. Create a chain from a Finder result and press `完成链`; after returning/re-rendering, confirm the same `链式调用` button becomes `执行链`.
2. Tap `执行链`; confirm the complete Root -> Level 1 -> Level N transaction executes and developer/test UI shows final return/trace.
3. Long-press `执行链`; confirm the previous chain is cleared and the chain editor immediately reopens for that method.
4. Search several method names; confirm records appear directly below the search box as one-row entries and can scroll.
5. Re-open/restart the menu and confirm search history persists.
6. Repeat an existing query and confirm it is deduplicated and moved to the top.
7. Create more than 50 distinct searches and confirm the oldest record is dropped.
8. Regress customer silent-success behavior, Runtime per-argument controls, ordinary Offset, Runtime `/0-/8`, multi-level Chain V2, and suffixless output.

Next engineering work after device evidence:

- Replace Chain V2 CSV argument authoring with typed per-argument rows.
- Add enum member-name enumeration/dropdown.
- Add explicit object-argument sources (`previous return`, `Level N return`, captured object).
- Add safe ref/out and broader custom ValueType support only where metadata-driven marshaling can be verified.
