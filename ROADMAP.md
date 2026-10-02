# ROADMAP

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

Source change is being committed. Compile, binary export verification, runtime, and device acceptance are still pending.
