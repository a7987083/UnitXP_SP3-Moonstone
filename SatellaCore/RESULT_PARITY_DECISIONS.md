# Result-parity decisions (1–26)

Baseline: `Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e`.

The project now separates **UpstreamParity** (results should follow the Swift baseline) from **ExtendedTesting** (OC-only controls retained for isolated testing). OC-only controls must not alter fixed upstream results while UpstreamParity is active.

| # | Decision | 1.3.0 status | Notes |
|---:|---|---|---|
| 1 | Keep controllable OC test model, but prefer real object path for final parity | Partial | Mock model retained; real transparent StoreKit object path is not implemented in this revision. |
| 2 | Preserve `invalidProductIdentifiers` | Done | Full response overload added; non-empty upstream response retains invalid IDs. |
| 3 | Match Swift product object identity | Done for model path | Fallback cache and mock lookup return the cached object rather than copies. |
| 4 | Disabled receipt behaviour -> Swift pass-through | Done for model path | `nil + no error` means no synthetic replacement. |
| 5 | Core Delegate/Transaction/CanPay behaviour -> Swift | Done in UpstreamParity | OC-only disable switches do not alter these always-installed upstream behaviours. |
| 6 | Price override -> Swift literal `0.01` | Done in UpstreamParity | `testPrice` only affects ExtendedTesting. |
| 7 | Receipt environment -> Swift `Production` | Done in UpstreamParity | `testEnvironment` only affects ExtendedTesting. |
| 8 | Keep current multi-product last-item semantics | Kept | Still inherits unordered-set ambiguity; not normalized in UpstreamParity. |
| 9 | URLSession task semantics -> Swift | Pending | No transparent global URLSession interception in this revision. |
| 10 | URLResponse semantics -> Swift | Pending | Requires real transport callback path. |
| 11 | Network error semantics -> Swift | Pending | Requires real transport callback path. |
| 12 | Callback timing/thread -> Swift | Pending | Requires real transport callback path. |
| 13 | Task cancel/resume/state -> Swift | Pending | Requires real URLSession task path. |
| 14 | dyld behaviour -> Swift | Pending | No live concealment implementation in this revision. |
| 15 | Keep integration/startup decision | Kept for current source | No constructor or `+load` has been added. Final no-explicit-call parity remains unresolved. |
| 16 | Product response identity -> Swift | Partial | Same synthetic response object is fanned out; real `SKProductsResponse` identity requires real StoreKit path. |
| 17 | Unmodified transaction properties -> Swift | Pending | Mock object cannot equal a real `SKPaymentTransaction`. |
| 18 | Keep reset facility | Kept | Extended test utility; not an upstream lifecycle guarantee. |
| 19 | Keep observer removal facility | Kept | Extended test utility. |
| 20 | Keep dynamic configuration unless unsafe | Kept, isolated | UpstreamParity ignores OC-only overrides where Swift has fixed semantics; ExtendedTesting keeps them. |
| 21 | Keep semantic `latest_receipt` comparison | Kept | Raw Base64 may differ because JSON encoders differ. |
| 22 | Keep semantic JSON comparison | Kept | Raw JSON byte order is not treated as a parity invariant. |
| 23 | Receipt time generation -> Swift | Done | Millisecond and textual values evaluate separate `Date()` equivalents in upstream order. |
| 24 | Keep OC RNG | Kept | Range/semantic parity, not random-sequence parity. |
| 25 | Shared-state synchronization -> Swift | Done for migrated result path | UpstreamParity does not add OC-only locks around product/delegate/observer state; ExtendedTesting remains synchronized. |
| 26 | Runtime bundle/device context -> Swift | Partial | Uses real `NSBundle` and iOS `UIDevice.identifierForVendor` when available; physical-device validation is still required. |

## Acceptance rule

A row marked **Done** is only source/regression-level done until macOS/iPhoneOS CI passes. Rows requiring real StoreKit/URLSession/dyld runtime behaviour must not be reported as equivalent while they remain Pending/Partial.
