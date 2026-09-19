# KNOWN_ISSUES

## Open
- Physical-device validation has not been performed.
- The source has not yet been compiled inside the real consumer Objective-C project, so consumer-target build settings/header-search-path integration remain to be verified there.
- The current StoreKit component is intentionally a local test/mock harness; live StoreKit interception is not implemented.

## Resolved during CI
- Fixed `SJDiagostics` class-name typo found by the first real `-Werror` compiler run.
- Fixed the CI `/tmp/satellla-core-ios` verification-path typo after iPhoneOS source compilation and static-library creation had already succeeded.
