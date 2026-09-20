# Integration

Add all `.m` files under `Sources/Internal/` to the Objective-C target and expose `Sources/Public/` in the header search path. ARC is required. Only Foundation is required by the component.

There is no `start`, constructor, `+load`, Swift runtime, or internal UI lifecycle. Integrate at an app-owned security-test seam and call the public API explicitly.

Recommended test flow:

1. `resetConfiguration`.
2. Load or apply the desired test configuration.
3. Route product-request results through `SJStoreKitTestEngine` when exercising fallback behaviour.
4. Use `SJMockTransaction` and observer APIs to test entitlement logic against manipulated transaction properties.
5. Use `SJReceiptGenerator` / verification-response APIs to test client/server trust decisions with clearly marked LocalTest data.
6. Inspect `status` and `recentDiagnostics` from your UI or test harness.
