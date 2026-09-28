# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.8.2 Single Runtime UI + Runtime Value Persistence**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `fix/m5.8.2-single-runtime-ui-persistence`
- Baseline: M5.8.1 `bdda071fe30b8b18dec1f791ad9f65cca402e4a3`
- Implementation CI anchor: `a8ffddf8eaee32a74d0be10dcae2cff6801b3e39`
- Run: `36361545700` — SUCCESS
- Job: `108739561193`
- Artifact ID: `10945494700`
- ZIP SHA256: `ec8deb778aee9431e7ddb903443f23fd2ea6423db649e378f17413ae82028239`
- Dylib: `ZonoPatch_v0.5.8_M5.8.2_SingleRuntimeUI_Persistence.dylib`
- Dylib size: `1404800`
- Dylib SHA256: `93cab80c56ada110f08f4f536633f0e1087f8132b9a7d830c182d3a4bc697572`

## Why M5.8.2

M5.8.1 device screenshot showed duplicated same-method cards, fixed-value actions without Execute, Slider without a visible current value, and no runtime-only customer-value persistence across restarts. The persistence gap is distinct from M5.5.1 authoring persistence: generated Runtime records are parsed from loaded dylib `__ZNDATA`, not from `ZNRuntimeActionStore`.

## Runtime customer architecture

`ZNM58UnifiedControlRuntime` remains the only Runtime customer renderer. M5.8.2 does not add another controller or nested renderer.

- duplicate visible cards collapse by `title + canonicalIdentity`;
- richer exposed-control record wins when duplicates exist;
- execution tags retain original `runtime.records` indexes;
- `exposed == 0` fixed-value actions show `执行`;
- Slider has one in-row current-value label;
- `ZNRangeControl` sends ValueChanged while tracking;
- ValueChanged only updates/quantizes the visible value and never invokes;
- release (`PrimaryActionTriggered`) invokes once;
- current Runtime argument values persist under `zonoe.m5.8.2.runtime-values.v1` keyed by `actionID + canonicalIdentity`;
- saved values restore when the menu is rendered again/restarted.

## Immediate device checklist

1. Footer shows `0.5.8 · M5.8.2`.
2. Verify duplicate `set_MoveSpeed` / `CheatSetExp` cards collapse to one visible card each where title+method identity match.
3. Verify fixed-value cards expose `执行`.
4. Drag Slider continuously: current value label must track the quantized value; no freeze/crash; release commits once.
5. Change Slider/Number/Switch, commit/execute, restart app, and verify the last value is restored.
6. Regress Runtime-only generation and confirm M5.5.1 authoring persistence is unaffected.
7. Regress M5.4 Unified Method Finder and M5.8 regenerated Static controls.

## Open boundaries

- Device validation is still pending; CI success is not device success.
- Display-level duplicate collapse intentionally uses title+canonical identity. Different titles for the same method remain separate actions.
- Static Number/Slider behavior still requires an M5.8+ regenerated target.
- M5.8 Phase 2 Builder/Method Finder architecture cleanup remains open; do not add another renderer layer.
