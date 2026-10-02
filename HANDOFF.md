# HANDOFF

## Current work line

ZonoPatch `v0.5.12 / M5.12 OffsetClosure`.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `recovery/m5.12-historical-offset-closure`
- Baseline before this change: `6f4baa44d612551c3a0a25013d960719bc468f06`
- Current task: cross-dylib activation API
- Build/device validation: pending

## Cross-dylib activation

The exported C ABI now includes `ZonoePatchActivate()` in `iosruntimepatchmenu/src/ZonoePatchAPI.h`.

`ZonoePatchActivate()` enters the existing deferred bootstrap path; it does not bypass the Cold/Loading/Ready state machine. When Ready, the existing path calls `ZonoePatchStart()` and `ZonoePatchShow()`.

Caller dylibs should resolve the symbol with `dlsym(RTLD_DEFAULT, "ZonoePatchActivate")`. See `iosruntimepatchmenu/docs/EXTERNAL_API.md`.

## Validation boundary

- Source changed: YES
- Commit: pending until this handoff update is committed
- Compile: NO
- Runtime: NO
- Device: NO

## Existing open work

M5.12 OffsetClosure behavior must remain unchanged by this API addition. The external entry is only an activation bridge; offset parsing, patch validation, runtime action behavior, and existing menu APIs are not reimplemented here.
