# ROADMAP

## Current milestone — M5.5.1 Recovery

Branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`

CI-validated head: `a40979aac1e98df9af84f5c67a09dcb356c62176`

### Recovery scope

- Restore the proven M5.4 Builder base geometry instead of replacing it with a four-column M5.5 layout.
- Move Runtime Method Call `删除` to the title row and increase vertical separation from the parameter-control row.
- Add persistent Runtime Method authoring state using `zonoe.m5.5.authoring-actions.v1`.
- Persist title, method identity, arguments, managed parameter types, signature availability, argument controls, Value Type, Default/Min/Max/Step and Immediate Chain.
- Restore saved authoring actions automatically when the in-memory store is empty at startup.
- Save on create, rename, argument edit, control edit, Value Type/range edit, chain edit, delete and clear.
- Important boundary: actions that had already existed only in memory before M5.5.1 and were lost on process restart cannot be reconstructed automatically without a previous serialized source/log/generated action table.

### Root cause confirmed

`ZNRuntimeActionStore` had historically been an in-memory `NSMutableArray` only. Changing dylib/restarting the process therefore discarded authoring actions. M5.5 inherited that behavior. M5.5.1 adds explicit persistence.

### Recovery CI / artifact

- Workflow: `Build Runtime Patch Menu v0.5.8 M5.5 Typed Control Binding V2`
- Run: `36002343325`
- Job: `107641806291`
- Result: SUCCESS
- Artifact ID: `10808925953`
- ZIP SHA256: `f8c813ae0c9bd10b376c58e510f3767633866e803f55f396040caa9efb02eeac`
- Recovery dylib size: `1404688` bytes
- Recovery dylib SHA256: `bf3ffc1c75c27bae19a6d03a7e6dc93d5e23c9953143fb024267f8705d679453`
- Mach-O: thin arm64 dylib

### Immediate device acceptance

1. Confirm footer reports `0.5.8 · M5.5.1`.
2. Confirm the original M5.4 Builder content appears again before Runtime Method Call.
3. Confirm Runtime Method Call `删除` is on the title row and no longer crowds parameter controls.
4. Create two Runtime Method Calls, change control/value-type/range, kill and relaunch the game, and confirm both actions/configs restore.
5. Delete one action, relaunch, and confirm the deletion persists.
6. Only after recovery acceptance, reintroduce Static Value Type authoring as a non-destructive overlay on the M5.4 Builder baseline.

## M5.5 Typed Control Binding V2 retained backend

- Public controls: Switch / Button / Number / Slider.
- Value Types: Auto / I32 / U32 / I64 / U64 / F32 / F64.
- Runtime Auto resolves from IL2CPP managed signatures.
- Runtime configs carry Default / Min / Max / Step.
- Static backend retains typed MOVZ/MOVK and scalar FMOV S/D adapters with fail-closed behavior.
- Static Entry ABI remains 128 bytes; Runtime Action Entry ABI remains 64 bytes.
- M5.4 Unified Method Finder remains the final Search / Results / Detail renderer.
