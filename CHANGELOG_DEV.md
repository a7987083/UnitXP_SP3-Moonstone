# CHANGELOG_DEV

## 2026-09-17 — g4 development started

Branch: `feature/json-capture-v0.4.2-g4-chinese-ui-recovery`
Base: `d0c10fc1d4df1ab0e8151f4a91ae3bca050242f3` (g3 persistent incremental)

Added:
- `GenericG4ChineseUI.m`: Chinese compact overlay UI and control surface.
- `OnDeviceLuaRecovery.h/.m`: native ENCM re-decrypt + static Lua 5.3 -> JSON recovery.
- Capture-priority background scheduling for re-decrypt/recovery.
- Persistent mobile recovery index/report/status.
- Complete and partial JSON output directories.

Compatibility/safety:
- Keeps g3/g2 capture core and no game-specific fixed RVAs.
- Static recovery only; dynamic opcodes are classified rather than executed.
- Existing raw/decoded captures are never deleted by recovery-index operations.
