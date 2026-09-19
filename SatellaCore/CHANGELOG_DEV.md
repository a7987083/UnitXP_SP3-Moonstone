# CHANGELOG_DEV

## 1.0.0-dev

### Implemented
- Added a pure Objective-C public API with no constructor, +load, start/bootstrap API, internal UI, Swift runtime, SwiftUI, Combine, or Jinx dependency.
- Added thread-safe lazy configuration state and feature status queries.
- Added local StoreKit test/mock helpers for product catalog data, transaction fixtures, and LocalTest receipt fixtures.
- Added diagnostics and JSON status APIs.
- Added source policy auditing, Objective-C runtime tests, iPhoneOS arm64 compile verification, static-library symbol verification, and delivery artifact generation.

### Commits
- `7b85da4f7571abbfac2f21020e2231d0f3f1c6d2` — initial Objective-C SatellaCore API.
- `7538d43bbba0f306ee2bfb0855be4fc6d6c22705` — fixed the first real compiler error: `SJDiagostics` -> `SJDiagnostics`.
- `efe15c8722013479af9e02acc33158d0be95b0d7` — fixed CI archive-verification path typo.

### Verified CI
GitHub Actions Run `35469833912` on source commit `efe15c8722013479af9e02acc33158d0be95b0d7` passed all validation gates.

- Source policy/API audit: PASS.
- macOS Objective-C compile with `-Wall -Wextra -Werror`: PASS.
- macOS API executable runtime test: PASS; log reported `SatellaCore tests passed`.
- iPhoneOS arm64 compile: PASS using Xcode 16.4 / iPhoneOS 18.5 SDK / minimum iOS 12.0.
- `libSatellaCore.a` creation: PASS.
- Exported Objective-C class symbol `_OBJC_CLASS_$_SatellaCore`: verified.
- Source/static-library artifact upload: PASS.
- Source ZIP SHA256: `3cfad67b47b8694013462f49f76b499d46f9a396fab4ae2b56cd860ad4157ffb`.
- arm64 static library SHA256: `90b88474d4d1dd0ed681f2a070c8e3880eb146f1b042b5addd087bfba098fb9b`.
- Uploaded GitHub artifact digest: `sha256:427ac74339c4bee10810874a6bdf966cbb15070743809810901bb23c72ed7af1`.

### Validation boundary
No physical-device or consumer-project integration test has been performed yet.
