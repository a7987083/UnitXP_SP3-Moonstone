# Signing Clean Architecture

This migration is intentionally incremental. `alphaone8` moves only the zonoe UDID callback vertical slice out of `SigningView` / `SigningHandler` while preserving the existing signing flow and plist behavior.

## Folder structure

```text
Ksign/Features/Signing/
├── Domain/
│   └── ZonoeUDIDCallback.swift
├── Application/
│   └── ConfigureZonoeUDIDCallbackUseCase.swift
├── Infrastructure/
│   └── ZonoeUDIDCallbackInfrastructure.swift
└── Presentation/
    └── ZonoeUDIDCallbackSection.swift
```

Regression coverage remains outside the app target:

```text
HFASign/scripts/
└── SigningArchitectureRegressionMain.swift
```

## Responsibilities

- **Domain**: request/configuration value types, metadata constants, and the scheme-generator abstraction. No SwiftUI and no plist mutation.
- **Application**: decides whether the callback exists, resolves custom vs plist Bundle ID, and depends on injected date/nonce providers for deterministic tests.
- **Infrastructure**: implements the legacy-compatible scheme algorithm and the `Info.plist` adapter. It owns Foundation dictionary mutation details.
- **Presentation**: owns only the SwiftUI toggle/description and exposes a `Binding<Bool?>`.
- **SigningHandler bridge**: translates existing `Options` + `Info.plist` into the use-case request, applies the adapter result, and keeps the existing progress log.

## Dependency direction

```text
Presentation ───────┐
                    │
SigningHandler ──> Application ──> Domain
      │                          ▲
      └────────> Infrastructure ─┘
```

Domain does not depend on UI, signing handlers, plist dictionaries, global managers, or concrete generators.

## Migration steps

1. Characterize the alphaone7 behavior before changing it.
2. Extract request/configuration and generator protocol to Domain.
3. Move enabled/Bundle-ID selection into Application.
4. Move scheme formatting and plist mutation into Infrastructure.
5. Extract the main-page toggle into Presentation.
6. Keep `SigningHandler.configureZonoeUDIDCallback` as a compatibility bridge so the signing call chain does not change.
7. Add legacy-parity regression tests with deterministic date/nonce injection.
8. Run the existing source-decoder regression, clean-architecture regression, full iOS Release build, packaging checks, and structural checks.

## No-break regression matrix

The automated signing architecture regression checks:

- disabled callback returns no configuration and does not invoke the generator;
- custom Bundle ID wins and is trimmed;
- blank custom Bundle ID falls back to plist Bundle ID;
- missing Bundle ID preserves `unknown` fallback;
- enabling writes the same URL type / metadata keys;
- unrelated URL types are preserved;
- previous zonoe marker and previous-scheme entries are removed;
- repeated enable is idempotent and does not duplicate URL types;
- disabling removes zonoe metadata and removes empty `CFBundleURLTypes` exactly as before;
- default scheme generator preserves lowercase/sanitization/nonce behavior;
- a legacy-reference implementation and the refactored implementation produce equal plist dictionaries for enabled/custom, enabled/fallback, disabled/cleanup, and disabled/empty scenarios.

The normal workflow additionally verifies existing navigation, keyboard bridge, App Store detail, source import, certificate UI, UDID settings, advanced signing entry, product metadata, packaging, SHA256, and GitHub Release creation.
