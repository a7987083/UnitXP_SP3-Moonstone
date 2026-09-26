# ROADMAP

## Current milestone — M5.8 Control Architecture Cleanup

Branch: `refactor/m5.8-control-architecture-cleanup`

CI-validated product head: `ddc77b5803fdb1093bf0e89d246ed97d0d406d75`

### Why M5.8

M5.7 device testing still showed Runtime Slider freezing during drag before Execute. A fresh audit confirmed the control stack still contained multiple historical implementations and renderer wrappers. M5.8 is a deletion/consolidation milestone, not a feature expansion.

### M5.8 Phase 1 completed

- Added `ZNM58UnifiedControlRuntime.mm` as the sole Runtime customer control renderer for Number / Slider / Switch / Button.
- Runtime Slider `ValueChanged` is intentionally zero-side-effect: no value rewrite, no target mutation, no Runtime refresh, no persistence, no render, no IL2CPP invoke.
- Slider release targets are attached exactly once when the UISlider is created; release quantizes and commits once.
- Runtime Number Return/Done only dismisses the keyboard; explicit `执行` commits.
- Runtime success remains silent and failure remains visible, now inside the M5.8 execute path instead of a constructor swizzle.
- `ZNM55TypedControlBinding` is Builder-only; it no longer swizzles Runtime Number/Slider.
- Runtime-only build-button gate was merged into the same Builder authoring decorator; standalone M5.7 gate wrapper removed.
- Static Slider `ValueChanged` is also zero-side-effect. Its previous hot path called `ZNStaticDispatchRuntime refresh`, wrote NSUserDefaults and rewrote slider.value on every drag event; all of that now occurs only on release.
- Static typed backend remains `ZNM56StaticValueCellBinder` / RW `__ZNDATA` value cells.

### Legacy modules physically removed from final dylib

The following are no longer present in the M5.8 Makefile:

- `ZNRuntimeMethodCallFeatureUI.mm`
- `ZNM51SilentCustomerExecution.mm`
- `ZNM53ControlBinding.mm`
- `ZNM55StaticTypedBinding.mm`
- `ZNM551RuntimeSliderStability.mm`
- `ZNM562SliderIsolation.mm`
- `ZNM57UnifiedRuntimeControls.mm`
- `ZNM57RuntimeOnlyBuilderGate.mm`

### CI / artifact

- Workflow: `Build Runtime Patch Menu v0.5.8 M5.8 Control Cleanup`
- Run: `36232977858`
- Job: `108379494581`
- Result: SUCCESS
- Artifact ID: `10903556469`
- ZIP SHA256: `d3431040c47df6d6322566f4139604d6a1d82fae03e4914df0f2ea842b260f0d`
- Dylib: `ZonoPatch_v0.5.8_M5.8_Control_Architecture_Cleanup.dylib`
- Dylib size: `1404720` bytes
- Dylib SHA256: `b0cbfae1b253c97714affa14deb5cd29b9ce48ee996f054ab080e81e2a70c827`
- Mach-O: thin arm64 dynamically linked shared library
- Independent ZIP/dylib hash verification: PASS

### Immediate device acceptance

1. Footer shows `0.5.8 · M5.8`.
2. Runtime Slider: drag continuously before release; it must not freeze/crash. Release should invoke once.
3. Runtime Number: Return closes keyboard and does not invoke; `执行` invokes once.
4. Static Slider on an M5.8-regenerated target: drag must remain responsive; release commits once through RW value cell.
5. Runtime-only generation with zero complete Static rows must report success.
6. Verify only one Runtime customer card/control surface is visible.

### M5.8 Phase 2 — still pending

- Physically consolidate remaining Builder renderer chain (`RuntimeMethodCallBuilderUI -> M5.1 arg decorator -> M5.5 authoring decorator`) into one base renderer.
- Continue Method Finder historical installer cleanup while preserving backend-only behavior decorators.
- Do not claim Phase 2 complete until device acceptance of Phase 1 is obtained.
