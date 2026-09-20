# CHANGELOG_DEV

## 1.3.0-result-parity

- Added UpstreamParity vs ExtendedTesting behaviour isolation.
- Preserved invalid product identifiers on non-empty responses.
- Preserved cached product object identity.
- Changed disabled conditional model paths to pass-through/no synthetic result.
- Fixed strict price/environment results to upstream literals while retaining OC-only overrides in ExtendedTesting.
- Matched separate Swift Date() evaluation order.
- Removed extra synchronization from the strict migrated product/delegate/observer result path while retaining synchronization in ExtendedTesting.
- Reworked source audit: StoreKit/native runtime/dyld usage is review-gated rather than globally forbidden.
- Real StoreKit/URLSession/dyld runtime parity remains explicitly pending.

## 1.2.0-upstream-parity

### Root-cause repair against `Paisseon/SatellaJailed@469e6eb`

- Removed the OC-only dependency that required a cached mock product before creating a purchased transaction. `TransactionHook.swift` is independent from product fallback.
- Changed `SJMockTransaction` hooked-equivalent getters to upstream read-time semantics: purchased state, fresh matching/transaction UUIDs, nil error, current date.
- Stopped deep-copying transactions before observer callbacks; original object identity is now preserved.
- Product delegates receive the same response object within one delivery, matching `SatellaDelegate` fan-out semantics.
- Fallback product price is restored to the upstream literal `0.01`; the default `testPrice` is also `0.01`, while an explicitly changed `testPrice` remains a test-only extension.
- Restored the upstream old-receipt signature byte payload (1667 bytes), default `Production` environment, fallback bundle/product identifiers, vendor-ID behaviour, inclusive receipt-ID range, and timestamp conversion order. An explicitly changed `testEnvironment` remains a test-only extension.
- Preserved the upstream modern-receipt `original_purchase_date_ms = nowDate` behaviour even though the key name suggests milliseconds.
- Added explicit `shouldReplaceVerificationResponseForURL:`. Non-`/verifyReceipt` URLs now mean pass-through (`nil` replacement, no error) rather than invalid input.
- Expanded Objective-C regression tests for dynamic transaction getters, object identity, receipt payload shape, signature length, Production environment, empty-product URLHook edge case, and pass-through URLs.
- Added `Tests/upstream_parity_audit.py` and chained it into `source_audit.py` so existing CI invokes the parity gate without workflow changes.

### Validation performed locally

- Source policy audit: PASS.
- Upstream parity audit: PASS.
- Upstream receipt signature decode: 1667 bytes, SHA-256 `5140ee9463d2f8ac278ff300f0b149bc3bb2d6fa02a74722d1d44a2de6e69a95`.
- Compile/runtime/TSAN/iPhoneOS/CI/device: **not run yet for this revision**.

## 1.1.0-testport

The prior implementation established the API-only Objective-C architecture and previously passed CI at commit `2f68b48907887bad20d4e9935c99ae039369beb6`. Its LocalTest receipt substitution and several behavioural approximations were superseded by the 1.2.0 parity repair above.
