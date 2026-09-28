# ROADMAP

## Current milestone — M5.8.2 Single Runtime UI + Runtime Value Persistence

Branch: `fix/m5.8.2-single-runtime-ui-persistence`

Baseline: M5.8.1 `bdda071fe30b8b18dec1f791ad9f65cca402e4a3`

Implementation CI anchor: `a8ffddf8eaee32a74d0be10dcae2cff6801b3e39` / Run `36361545700` / SUCCESS.

### M5.8.2 completed in source

- Keep `ZNM58UnifiedControlRuntime` as the single Runtime customer renderer; no second Runtime UI/controller was added.
- Collapse duplicate visible Runtime cards by `title + canonicalIdentity`, preferring the record with richer exposed controls while preserving the original runtime record index for execution.
- Fixed-value actions (`argumentCount > 0`, `exposed == 0`) now receive an explicit `执行` button.
- Runtime Slider row now shows its current quantized value in a monospaced label.
- `ZNRangeControl` emits `UIControlEventValueChanged` while dragging; M5.8.2 uses this event only to update the value label. Invoke remains release-only.
- Runtime-only argument values persist in `NSUserDefaults` under `zonoe.m5.8.2.runtime-values.v1`, keyed by `actionID + canonicalIdentity`.
- Re-render/reopen restores persisted Runtime argument values before falling back to values embedded in the generated dylib.
- ABI unchanged: Static Entry 128 bytes; Runtime Action Entry 64 bytes.

### CI / artifact

Implementation commit `a8ffddf8eaee32a74d0be10dcae2cff6801b3e39`:

- Workflow: `Build Runtime Patch Menu v0.5.8 M5.8.2 Single Runtime UI Persistence`
- Run: `36361545700`
- Job: `108739561193`
- Result: SUCCESS
- Artifact ID: `10945494700`
- ZIP SHA256: `ec8deb778aee9431e7ddb903443f23fd2ea6423db649e378f17413ae82028239`
- Dylib: `ZonoPatch_v0.5.8_M5.8.2_SingleRuntimeUI_Persistence.dylib`
- Dylib size: `1404800`
- Dylib SHA256: `93cab80c56ada110f08f4f536633f0e1087f8132b9a7d830c182d3a4bc697572`

### Immediate device acceptance

1. Footer shows `0.5.8 · M5.8.2`.
2. Only one card is visible for duplicated same-title/same-method Runtime actions such as `set_MoveSpeed` / `CheatSetExp`.
3. Fixed-value Runtime actions expose `执行`.
4. Slider value label changes during drag and matches the value actually invoked on release.
5. Slider drag remains responsive; release invokes once.
6. Change Slider/Number/Switch value, execute/commit, restart the app and confirm the Runtime UI restores the last value.
7. Regress Runtime-only generation, M5.5.1 Builder authoring persistence, M5.4 Unified Method Finder, and regenerated Static controls.

### Next phase

Do not start another renderer layer. After M5.8.2 device acceptance, continue the existing M5.8 Phase 2 cleanup: consolidate the remaining Builder renderer chain and clean historical Method Finder installers while keeping backend behavior intact.
