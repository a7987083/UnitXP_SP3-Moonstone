# HANDOFF

## Architecture
`SatellaCore` is a source component intended to be compiled directly into an Objective-C target. It has no constructor, `+load`, standalone start routine, Swift dependency, or built-in UI. Callers use class methods on `SatellaCore` and the local mock helpers in `SJStoreKitMock`.

## Public surface
- `SatellaCore.h`
- `SJConfiguration.h`
- `SJStoreKitMock.h`

Primary APIs cover feature enable/disable state, configuration snapshots/application, capability/status queries, diagnostics, mock product catalogs, transaction fixtures, and LocalTest receipt fixtures.

## Boundary
The StoreKit layer is local test/mock data only. It does not hook or intercept live StoreKit, modify App Store transactions, or forge production receipts.

## Stable validation baseline
- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `kkkkbuy`
- Validated source commit: `efe15c8722013479af9e02acc33158d0be95b0d7`
- CI Run: `35469833912`
- macOS compile/runtime tests: PASS
- iPhoneOS arm64 compile: PASS
- Minimum iOS compile target: 12.0
- Xcode in CI: 16.4
- iPhoneOS SDK in CI: 18.5
- Static library class symbol: verified

## Remaining validation
The next engineer should add the `.m` files to the real consumer Objective-C target, expose `Sources/Public` in the header search path, compile that target, and then perform device-level integration testing. Do not treat the existing CI as physical-device validation.
