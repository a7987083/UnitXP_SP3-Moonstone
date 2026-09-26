# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.8 Control Architecture Cleanup · Phase 1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `refactor/m5.8-control-architecture-cleanup`
- CI-validated product head: `ddc77b5803fdb1093bf0e89d246ed97d0d406d75`
- Run: `36232977858` — SUCCESS
- Job: `108379494581`
- Artifact ID: `10903556469`
- ZIP SHA256: `d3431040c47df6d6322566f4139604d6a1d82fae03e4914df0f2ea842b260f0d`
- Dylib size: `1404720`
- Dylib SHA256: `b0cbfae1b253c97714affa14deb5cd29b9ce48ee996f054ab080e81e2a70c827`

## Why M5.8

M5.7 device testing still showed Runtime Slider freezing during drag before Execute. Re-audit confirmed the problem was architectural rather than one bad Invoke: Runtime controls retained multiple historical implementations, Static had a separate slider hot path, Builder was wrapped repeatedly, and multiple disabled control modules were still linked into the product.

## Phase 1 architecture

### Runtime customer controls

`ZNM58UnifiedControlRuntime` is the sole Runtime customer renderer for Number / Slider / Switch / Button.

- controls created by M5.8 bind only M5.8 selectors;
- Slider `ValueChanged` is intentionally zero-side-effect;
- Slider release targets are attached once at control creation;
- release quantizes once and invokes once;
- Number typing is UI-only;
- Return/Done only dismisses the keyboard;
- Number applies only through explicit `执行`;
- Switch commits immediately;
- customer success is silent; failure remains visible;
- no constructor swizzle is required for silent execution.

### Static / Offset controls

- UI remains `ZNFeatureRuntimeControlsV2` for Phase 1.
- Static Slider `ValueChanged` is now zero-side-effect.
- The historical drag path that refreshed `ZNStaticDispatchRuntime`, iterated records, wrote NSUserDefaults and rewrote `slider.value` on each ValueChanged has been removed.
- Release alone quantizes/saves and posts one commit.
- Static typed backend owner remains `ZNM56StaticValueCellBinder` using RW `__ZNDATA` cells.

### Builder authoring

`ZNM55TypedControlBinding` is Builder-only:

- Value Type / Range authoring retained;
- no Runtime Number/Slider swizzles;
- Runtime-only build-button gate merged into the same decorator;
- standalone `ZNM57RuntimeOnlyBuilderGate` removed from final product.

## Legacy modules physically removed from M5.8 product

- `ZNRuntimeMethodCallFeatureUI.mm`
- `ZNM51SilentCustomerExecution.mm`
- `ZNM53ControlBinding.mm`
- `ZNM55StaticTypedBinding.mm`
- `ZNM551RuntimeSliderStability.mm`
- `ZNM562SliderIsolation.mm`
- `ZNM57UnifiedRuntimeControls.mm`
- `ZNM57RuntimeOnlyBuilderGate.mm`

These modules are not merely uninstalled; they are absent from the M5.8 Makefile/final dylib.

## Immediate device checklist

1. Footer must show `0.5.8 · M5.8`.
2. Runtime Slider: drag continuously before release. It must remain responsive and must not freeze/crash. Release should commit once.
3. Runtime Number: type a value -> Return closes keyboard -> no effect yet -> tap `执行` -> one execution.
4. Verify only one Runtime customer action/control card set is visible.
5. Runtime-only generation with Runtime Actions and zero complete Static rows must end as success.
6. Static Slider/Number acceptance requires a target regenerated with the M5.8 Builder; Slider drag must remain responsive and release commit once via RW cell.
7. Regress authoring persistence and M5.4 Unified Method Finder.

## Phase 2 still open

- Consolidate the remaining Builder renderer chain (`ZNRuntimeMethodCallBuilderUI -> M5.1 argument decorator -> M5.5 authoring/gate`) into one renderer.
- Physically clean remaining historical Method Finder installers while preserving backend-only behavior decorators.
- Do not claim the full architecture cleanup complete until Phase 2 and device acceptance are done.

## Compatibility boundaries

- Static Number/Slider tests must use an M5.8-regenerated target.
- Value-cell LDR literal remains ±1MB and fails closed when layout cannot satisfy it.
- Static Entry ABI remains 128 bytes; Runtime Action Entry ABI remains 64 bytes.
- M5.2 Chain Level 0 null-return investigation remains separate.
