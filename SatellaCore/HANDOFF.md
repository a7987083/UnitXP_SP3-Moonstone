# HANDOFF

## Architecture
`SatellaCore` is a source component, not a standalone tweak. There is no constructor or start routine. Public callers use class methods on `SatellaCore` and mock helpers in `SJStoreKitMock`.

## Boundary
The StoreKit layer is local test/mock data only. It does not hook or intercept live StoreKit calls.

## Integration
Copy `Sources/Public` and `Sources/Internal` into an Objective-C target with Foundation and ARC enabled.
