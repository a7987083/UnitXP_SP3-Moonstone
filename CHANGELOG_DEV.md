# CHANGELOG_DEV

## 2026-09-17 — g4 Chinese UI + on-device JSON recovery

Branch: `feature/json-capture-v0.4.2-g4-chinese-ui-recovery`
Base: `d0c10fc1d4df1ab0e8151f4a91ae3bca050242f3` (g3 persistent incremental)

Added:
- `GenericG4ChineseUI.m`: Chinese compact floating overlay and control surface.
- `OnDeviceLuaRecovery.h/.m`: native ENCM re-decrypt + static Lua 5.3 -> JSON recovery.
- Capture-priority scheduling for historical re-decrypt and JSON recovery.
- Persistent mobile recovery/decrypt index, report and status files.
- Complete and partial JSON output directories.
- UI actions for scan control, force scan, re-decrypt, re-recover, incremental recovery, JSON directory, report export and index management.

Build fixes:
- Typed the UI label dictionary so keyed subscripting produces `UILabel *`.
- Suppressed one intentional unused helper warning that Theos promoted to an error.
- CI binary validation now uses ASCII markers; Chinese NSString literals are validated at source-contract stage.

Validation:
- Source contract: passed.
- Theos arm64 compile/link/sign: passed.
- GitHub Actions run: `35134708046` — success.
- Artifact source commit: `e1ab528ad2eadfd22fef56be48eb5baa06988081`.
- Dylib SHA256: `9a6c48526c0fbd8a2bb0333edc97f9e4b904f4e472b56af608eb23c76b76970c`.
- Release ZIP SHA256: `c994666cca1cedfc22ee07e55a00b815117ec26cd5de9764d06f3c55aff019d0`.
- Real-device g4 UI/recovery: pending.

Compatibility/safety:
- Keeps g3/g2 capture core and no game-specific fixed RVAs.
- Static recovery only; dynamic opcodes are classified rather than executed.
- Existing raw/decoded captures are never deleted by recovery-index operations.
