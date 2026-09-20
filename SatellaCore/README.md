# SatellaCore Objective-C result-parity port

Pure Objective-C source component for app-owned StoreKit security testing and Swift-vs-Objective-C result comparison. No internal UI, Swift runtime, SwiftUI, Combine, or Jinx dependency is required.

## Upstream baseline

Behavioural baseline: `Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e` (`emt`).

Version `1.3.0-result-parity` introduces two behaviour profiles:

- **`SJBehaviorModeUpstreamParity` (default):** OC-only knobs are prevented from changing results that the Swift baseline fixes. Can-pay behaviour follows the always-installed upstream hook, price override is the literal `0.01`, verification environment is `Production`, cached product identity is preserved, invalid product identifiers are retained on non-empty pass-through responses, disabled conditional hooks mean pass-through/no synthetic result, and receipt timestamps follow the upstream two-`Date()` evaluation order.
- **`SJBehaviorModeExtendedTesting`:** preserves configurable price/environment/core switches and synchronized state for isolated deterministic tests. This mode is not evidence of Swift parity.

See `RESULT_PARITY_DECISIONS.md` for the agreed 1–26 decision matrix.

## Important boundary

This revision improves **result parity at the existing Objective-C model/test layer**. It does not claim transparent runtime equivalence for real `SKProduct`, `SKPaymentTransaction`, `SKProductsResponse`, `NSURLSessionDataTask`, `URLResponse`, network error/timing, or live dyld behaviour. Those rows remain explicitly Partial/Pending in the decision matrix and must not be inferred from passing model tests.

## Source audit policy

`Tests/source_audit.py` no longer treats StoreKit imports, native Objective-C runtime mutation, or dyld image APIs as universally forbidden. If such runtime-sensitive code is introduced, the file must contain an `SJ_RUNTIME_REVIEWED` marker and receive separate review. Swift/Jinx/Substrate dependencies remain prohibited for this Objective-C port.
