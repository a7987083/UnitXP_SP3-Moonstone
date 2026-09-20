# CHANGELOG_DEV

## 1.1.0-testport

### Objective-C security-test migration
- Migrated the non-UI Swift behaviour into explicit Objective-C app-owned test seams.
- Added compatible `tella_*` preferences and defaults.
- Added product delegate fallback behaviour with one-time fallback product caching.
- Added transaction observer forwarding with pointer-identity duplicate suppression.
- Added canMakePayments, product-price and purchased-transaction property simulations.
- Added old receipt, modern receipt, receipt info, renewal info and verification-response Objective-C models.
- Added LocalTest receipt/verification generation. Production Apple signature material is intentionally not reproduced.
- Added URL decision behaviour for the `/verifyReceipt` test seam.
- Added dyld concealment-decision simulation for testing an app's own detection logic without installing a live dyld hook.
- Preserved the API-only integration model: no internal UI, constructor, `+load`, standalone `start`, Swift runtime or Jinx.

### Audit fixes
- Unified mutable runtime state under one synchronization domain.
- Made reset state transitions atomic before notifications are posted.
- Made `status` a coherent snapshot.
- Rejected nil product arrays rather than treating nil as an implicit clear.
- Added product-catalog/transaction dependency validation.
- Separated disabled-feature errors from unavailable-feature errors.
- Copied diagnostics input strings.
- Expanded source policy auditing and binary forbidden-dependency auditing.

### Verified implementation baseline
Implementation commit `2f68b48907887bad20d4e9935c99ae039369beb6` passed GitHub Actions Run `35480212352`:

- Source policy/API audit: PASS.
- macOS Objective-C compile with `-Wall -Wextra -Werror`: PASS.
- Full API/runtime tests: PASS; log reported `SatellaCore full security-test port tests passed`.
- Thread Sanitizer stress run: PASS.
- iPhoneOS arm64 compile with `-Wall -Wextra -Werror`: PASS.
- Xcode 16.4 / iPhoneOS 18.5 SDK / minimum iOS 12.0.
- Static library generation: PASS.
- Binary dependency audit for Swift/Jinx/Substrate/live dyld/StoreKit classes: PASS.
- Exported `SatellaCore`, `SJStoreKitTestEngine`, `SJReceiptGenerator`, and `SJRuntimeTestAdapter` classes: verified.

Run-8 artifact values, retained only as the implementation validation baseline:
- Source ZIP SHA256: `88d17f3741dcc0d320e15086954fa69cb610e06fb74d024f9397718f7cd483d0`.
- arm64 static library SHA256: `51e4daf149ff0c7ad4d3a71df49e3a20bd65b94d53a402f822c52fcb7afac706`.
- Uploaded artifact digest: `sha256:c1eb11e40c148e4339346176ede93d87f0d673990cd615cd28b73dacbcd68b05`.

The final delivery workflow is re-run after documentation-only changes. The authoritative hashes for any delivered archive are the `SHA256.txt` file generated inside that same final CI artifact.

### Validation boundary
Consumer-project integration and physical-device testing have not yet been performed. The component uses explicit app-owned security-test seams rather than silently intercepting live third-party StoreKit/URLSession traffic.
