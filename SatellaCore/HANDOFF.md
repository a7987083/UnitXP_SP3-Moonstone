# HANDOFF

## Architecture
`SatellaCore` is a pure Objective-C source component intended to be compiled directly into an app-owned Objective-C target. It has no constructor, `+load`, standalone start routine, Swift dependency, Jinx dependency, or built-in UI.

## Public surface
- `SatellaCore.h` — configuration, feature state, status, diagnostics, preference reload/persist.
- `SJConfiguration.h` — complete test configuration.
- `SJPreferences.h` — original `tella_*` preference-key compatibility.
- `SJStoreKitMock.h` — mock product compatibility helpers.
- `SJStoreKitTestEngine.h` — product delegate, transaction observer, canMakePayments, price, transaction and verification test seams.
- `SJReceiptModels.h` — old/new receipt, renewal and response Objective-C models.
- `SJReceiptGenerator.h` — LocalTest receipt/verification data generation.
- `SJRuntimeTestAdapter.h` — dyld-concealment decision simulation for testing app-owned detection code.

See `MIGRATION_MATRIX.md` for the upstream Swift-to-Objective-C mapping.

## Behaviour boundary
The goal is behavioural coverage for an app the tester owns. StoreKit/URL/dyld-sensitive behaviour is exposed as explicit test APIs so the app can exercise the same trust boundaries without installing global production hooks. Receipt signatures are unmistakable LocalTest markers rather than Apple production signatures.

## Validated implementation baseline
- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `kkkkbuy`
- Implementation commit: `2f68b48907887bad20d4e9935c99ae039369beb6`
- Implementation CI Run: `35480212352`
- Source/API audit: PASS
- macOS `-Werror` compile + runtime tests: PASS
- Thread Sanitizer: PASS
- iPhoneOS arm64 `-Werror` compile: PASS
- Binary dependency/symbol audit: PASS
- Xcode: 16.4
- iPhoneOS SDK: 18.5
- Minimum iOS target: 12.0

The delivery commit may be newer only because validation metadata was updated. CI is re-run on that delivery commit before an artifact is handed off.

## Remaining external validation
Add all Internal `.m` files to the real consumer Objective-C target, expose `Sources/Public`, compile the actual target, and perform device-level integration testing. Do not label CI validation as physical-device validation.
