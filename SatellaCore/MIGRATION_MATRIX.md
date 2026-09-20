# SatellaJailed Swift -> Objective-C parity matrix

Upstream baseline: `Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e`.

| Upstream | Objective-C equivalent | Current parity state |
|---|---|---|
| `Helpers/Preferences.swift` | `SJPreferences` + `tella_*` keys | Implemented; OC supports explicit reload/persist |
| `Helpers/Delegate.swift` | `SJProductsResponse` + fallback product cache | Corrected: one-time cache, literal `0.01`, same response object to delegates |
| `Hooks/DelegateHook.swift` | explicit delegate registration/delivery seam | Behavioural seam only; no global `setDelegate:` hook |
| `Helpers/Observer.swift` | `SJTransactionTestObserver` + pointer-identity dedup | Corrected: original transaction objects forwarded; duplicate abort preserved |
| `Hooks/ObserverHook.swift` | explicit observer registration seam | Behavioural seam only; no global `addTransactionObserver:` hook |
| `Hooks/CanPayHook.swift` | `canMakePaymentsWithSystemValue:` | Implemented |
| `Hooks/ProductHook.swift` | `effectivePriceForProduct:` | Corrected: default override is `0.01` like upstream; explicit `testPrice` remains a test-only extension |
| `Hooks/TransactionHook.swift` | `SJMockTransaction` | Corrected: independent of product cache; purchased/nil-error/current-date/dynamic UUID getter semantics |
| `Hooks/ReceiptHook.swift` | `oldReceiptDataForProductIdentifier:` | Corrected to upstream payload semantics |
| `Receipt/OldReceipt*.swift` | `SJOldReceipt` / `SJOldReceiptInfo` | Implemented |
| `Receipt/Receipt*.swift` | `SJReceipt`, `SJReceiptInfo`, `SJReceiptResponse`, `SJRenewalInfo` | Implemented; upstream field quirks retained |
| `Receipt/ReceiptGenerator.swift` | `SJReceiptGenerator` | Corrected: upstream signature bytes, default Production environment, fallback IDs, vendor ID behaviour, timestamp/range semantics |
| `Hooks/URLHook.swift` | `shouldReplaceVerificationResponseForURL:` + response generator | Corrected pass-through/replacement decision; no global URLSession hook |
| `Hooks/DyldHook.swift` | `SJRuntimeTestAdapter` | Decision simulation only; no live dyld interception |
| `Hooks/WindowHook.swift` + `Views/*` | None | Removed per requirement: no internal UI |
| `Tweak.swift` + `load.s` | Public API calls | Removed per requirement: no constructor, `+load`, or startup entry |

The objective is data/decision parity at explicit app-owned seams. Global runtime interception is intentionally outside this source component's current integration model.
