# Integration

Add all `.m` files under `Sources/Internal/` to the Objective-C target and expose `Sources/Public/` in the header search path. ARC is required. The component remains Foundation-only at link time; the receipt generator discovers `UIDevice.identifierForVendor` dynamically when UIKit is present and otherwise uses the upstream UUID fallback.

There is no `start`, constructor, `+load`, Swift runtime, or internal UI lifecycle. Integrate at an app-owned security-test seam and call the public API explicitly.

Recommended parity test flow:

1. `resetConfiguration`.
2. Load or apply the desired feature configuration.
3. Route product-request results through `SJStoreKitTestEngine`; empty upstream results use the one-time `0.01` fallback cache, while non-empty results remain pass-through data.
4. Build `SJMockTransaction` values through `makePurchasedTransactionForProductIdentifier:error:`. Transaction simulation is independent from the fallback-product cache, matching `TransactionHook.swift`.
5. When observer simulation is enabled, route transaction batches through `publishTransactions:error:`. Original object identity and duplicate-abort semantics are preserved.
6. Enable receipt simulation and use `oldReceiptDataForProductIdentifier:` / `verificationResponseDataForURL:`. `shouldReplaceVerificationResponseForURL:` distinguishes replacement from pass-through.
7. Inspect `status` and `recentDiagnostics` from your UI or test harness.

The explicit API model still differs from the Swift tweak's global interception. Test the actual consumer call sites rather than assuming an API-only fixture proves live StoreKit hook behaviour.
