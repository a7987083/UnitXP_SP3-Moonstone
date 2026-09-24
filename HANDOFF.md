# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.5.1 Recovery**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`
- CI-validated head: `a40979aac1e98df9af84f5c67a09dcb356c62176`
- CI Run: `36002343325` — SUCCESS
- Job: `107641806291`
- Artifact ID: `10808925953`
- ZIP SHA256: `f8c813ae0c9bd10b376c58e510f3767633866e803f55f396040caa9efb02eeac`
- Recovery dylib size: `1404688`
- Recovery dylib SHA256: `bf3ffc1c75c27bae19a6d03a7e6dc93d5e23c9953143fb024267f8705d679453`

## Recovery architecture

- M5.4 Builder base geometry is restored as the authoritative production/authoring page baseline.
- Runtime Method Call cards append after the existing Builder page.
- Runtime Method Call `删除` is now placed in the title row, away from parameter controls.
- Runtime authoring data is persistent from M5.5.1 onward via `NSUserDefaults` key `zonoe.m5.5.authoring-actions.v1`.
- Persistent fields include method identity, arguments, managed signature, control configs, Value Type/Range fields and Immediate Chain.
- Mutations that trigger save: create, rename, argument edit, control edit, chain edit, delete, clear.
- Startup restore runs only if the in-memory store is empty.

## Critical historical boundary

Before M5.5.1, `ZNRuntimeActionStore` was process-memory-only. Authoring actions already lost before this recovery build cannot be reconstructed automatically without a previous serialized artifact/log/action table. Do not infer truncated class/method identities from screenshots.

## Typed Control backend retained

```text
Control Type:
  Switch / Button / Number / Slider

Value Type:
  Auto / I32 / U32 / I64 / U64 / F32 / F64
```

- Runtime Auto resolves from IL2CPP managed parameter types.
- Runtime Range: Default / Min / Max / Step.
- Static backend retains typed MOVZ/MOVK and scalar FMOV S/D adapters with fail-closed semantics.
- Static Entry ABI remains 128 bytes; Runtime Action Entry ABI remains 64 bytes.

## Immediate device checklist

1. Footer must show `0.5.8 · M5.5.1`.
2. Original M5.4 Builder content must be visible again before `Runtime Method Call`.
3. `删除` must be in each Runtime card's title row with clear separation from parameter controls.
4. Create 2 Runtime methods, modify their control/value type/range, kill/relaunch, verify both restore.
5. Delete one, kill/relaunch, verify deletion persists.
6. After recovery acceptance, reintroduce Static Value Type authoring UI only as a non-destructive overlay on the M5.4 baseline.

## Open boundaries

- The already-lost pre-M5.5.1 in-memory authoring items are not automatically recoverable.
- Static custom per-feature Range metadata is still not embedded.
- Static executable-page transactional mutation may be restricted by target signing/device model.
- M5.2 Chain Level 0 null-return investigation remains open.
