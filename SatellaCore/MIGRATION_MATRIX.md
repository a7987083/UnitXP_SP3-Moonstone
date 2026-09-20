# SatellaJailed Swift -> Objective-C security-test migration matrix

Upstream baseline: `Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e`.

| Upstream | Objective-C security-test equivalent | Status |
|---|---|---|
| `Helpers/Preferences.swift` | `SJPreferences` + compatible `tella_*` keys | Implemented |
| `Helpers/Delegate.swift` | `SJProductsResponse` + `SJProductsRequestTestDelegate` + fallback product cache | Implemented |
| `Hooks/DelegateHook.swift` | Explicit `addProductsDelegate:` / `deliverProducts...` seam | Implemented without global StoreKit interception |
| `Helpers/Observer.swift` | `SJTransactionTestObserver`, pointer-identity dedup, observer fan-out | Implemented |
| `Hooks/ObserverHook.swift` | Explicit observer registration seam | Implemented without global StoreKit interception |
| `Hooks/CanPayHook.swift` | `canMakePaymentsWithSystemValue:` | Implemented |
| `Hooks/ProductHook.swift` | `effectivePriceForProduct:` | Implemented |
| `Hooks/TransactionHook.swift` | `SJMockTransaction` purchased state, IDs, nil error, current date | Implemented |
| `Hooks/ReceiptHook.swift` | `oldReceiptDataForProductIdentifier:` | Implemented as LocalTest data |
| `Receipt/OldReceipt*.swift` | `SJOldReceipt` / `SJOldReceiptInfo` | Implemented |
| `Receipt/Receipt*.swift` | `SJReceipt`, `SJReceiptInfo`, `SJReceiptResponse`, `SJRenewalInfo` | Implemented |
| `Receipt/ReceiptGenerator.swift` | `SJReceiptGenerator` | Implemented; production Apple signature deliberately replaced by a LocalTest marker |
| `Hooks/URLHook.swift` | `verificationResponseDataForURL:productIdentifier:` | Decision/response semantics implemented; no global URLSession interception |
| `Hooks/DyldHook.swift` | `SJRuntimeTestAdapter` concealment-decision simulator | Implemented for detector testing; no live dyld hook |
| `Hooks/WindowHook.swift` + `Views/*` | None | Removed per integration requirement: no internal UI |
| `Tweak.swift` + `load.s` | Public API calls | Removed per integration requirement: no constructor, `+load`, or startup entry |

The Objective-C component is designed to be called from an app-owned test seam, StoreKit Test/Sandbox path, or security-test target. It does not silently alter third-party production StoreKit/URLSession behavior.
