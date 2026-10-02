# ROADMAP

## M5.13 — Unified Input Service

### Completed in source/CI

- [x] Custom Offset/address pad.
- [x] Custom Patch HEX pad.
- [x] Custom Runtime numeric/flexible pad.
- [x] No second key UIWindow / no `makeKeyAndVisible` in the custom pad path.
- [x] System-text KeyboardService with bounded responder recovery.
- [x] Normal + ExternalOnly builds.
- [x] Binary verification and artifact upload.

### Device acceptance remaining

- [ ] In the affected game, tapping Offset must open ZonoPatch custom pad without the game's `Send` input overlay.
- [ ] Offset entry must persist into `ZNBinaryPatchWorkspace`.
- [ ] Patch HEX entry must persist and validate.
- [ ] Runtime numeric argument entry must update `ZNRuntimeActionStore`.
- [ ] Name/description system-text fields must remain usable if the game tries to steal responder.
- [ ] Normal and ExternalOnly launch behavior must remain unchanged.

## Current milestone — M5.12 OffsetClosure

Repository: `a7987083/UnitXP_SP3-Moonstone`  
Branch: `recovery/m5.12-historical-offset-closure`  
Baseline before cross-dylib API: `6f4baa44d612551c3a0a25013d960719bc468f06`

### Current change

- Add one stable external activation entry: `ZonoePatchActivate()`.
- Keep the existing deferred bootstrap state machine as the single activation owner.
- Keep `ZonoePatchStart/Show/Hide/IsVisible` behavior unchanged.
- Provide a C header and `dlsym` caller contract for peer dylibs.

### Acceptance

- Build succeeds with `-fvisibility=hidden`.
- Binary export table contains `_ZonoePatchActivate`.
- `dlsym(RTLD_DEFAULT, "ZonoePatchActivate")` resolves from a peer dylib.
- Calling once from Cold enters the existing activation path and shows ZonoPatch.
- Repeated calls while Loading/Ready do not duplicate bootstrap/installers.
- Existing launcher tap still works.
- Existing M5.12 OffsetClosure functions regress cleanly.

### Validation status

- Source: committed.
- CI Run `36961499728`: SUCCESS.
- Normal build: SUCCESS.
- ExternalOnly build: SUCCESS.
- Binary export verification: SUCCESS for both; `_ZonoePatchActivate` is exported.
- Artifact ID: `11208715483`.
- Device acceptance: pending.

### Device acceptance remaining

- Normal: cold launch still shows the ZN launcher and tap activates normally.
- ExternalOnly: cold launch shows no ZN launcher.
- ExternalOnly: peer dylib `dlsym + ZonoePatchActivate()` activates once and shows the menu.
- Repeated activation while Loading/Ready remains idempotent.
