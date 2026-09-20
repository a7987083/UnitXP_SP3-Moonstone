# KNOWN_ISSUES

## Open validation items
- Consumer-project integration and physical-device validation are still pending.
- The test engine intentionally uses explicit app-owned API seams instead of globally intercepting live StoreKit or URLSession.
- `DyldHook.swift` decision semantics are available through `SJRuntimeTestAdapter`, but no live dyld interception/concealment is installed.
- Test receipt signatures are LocalTest markers, not Apple production signatures.

## Fixed from v1.0.0-dev audit
- `resetConfiguration` now performs configuration/session clearing as one state transition before notifications are posted.
- Configuration, product catalog, delegate/observer registries, seen transactions and diagnostics share one synchronization domain.
- `status` collects one coherent snapshot under that synchronization domain.
- `setProducts:nil` is rejected instead of silently clearing the catalog.
- Product-catalog / transaction dependency is validated.
- Disabled feature errors are distinct from unavailable feature errors.
- Diagnostics copy caller strings.
- Source audit recognizes `@import`, constructor variants and common Objective-C runtime mutation APIs.
