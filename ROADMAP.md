# ROADMAP

## Current milestone — M5.6 Stable Runtime Slider + Static RW Value Cell V1

Branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`

CI-validated head: `2d6351ac7e2652ae76e2ba2542118cc0beb2338e`

### Device evidence that triggered M5.6

1. Static Number + Auto on a generated Offset patch failed on device with:
   `写入完成但恢复 RX 权限失败: errno=13 (Permission denied)`.
   This proves executable-page runtime mutation is not viable on the current signing/device model.
2. Runtime Slider froze/crashed as soon as it was dragged. Audit found M5.5 calling `ZNRuntimeActionRuntime refresh` on every `UIControlEventValueChanged`.

### M5.6 implemented

- Runtime Slider hot path is cache-only while dragging.
- Slider release performs exactly one Runtime Action refresh, step quantization, final cache write, and one Invoke.
- Added build-time `Static RW Value Cell V1` parameterization.
- Number/Slider generated ON variants are rewritten before signing to load from owned `__ZNDATA` RW cells.
- Runtime Static value changes write only RW data; no `mprotect`, no RX->RW->RX executable-page mutation.
- MOVZ(+MOVK) variants become LDR W/X from cell; compatible trailing MOVK slots are NOPed at build time.
- scalar FMOV S/D variants become LDR S/D from cell.
- Auto resolves backing type from verified source instruction family.
- Existing Static selectedTarget dispatch stays unchanged; enabling still selects the generated ON variant.
- Value-cell metadata uses new flags without changing `ZN44StaticEntry` size (128 bytes).
- Runtime Action ABI remains 64 bytes.
- M5.5.1 Builder baseline recovery and persistent Runtime authoring remain retained.

### Final CI / artifact

- Workflow: `Build Runtime Patch Menu v0.5.8 M5.6 RW Value Cell`
- Run: `36004751812`
- Job: `107649917061`
- Result: SUCCESS
- Artifact ID: `10809323261`
- ZIP SHA256: `fc1f0596f2f603a993d2249e9ab1c965e5ff38019fcda3d5d4a75a189ecf2c03`
- Dylib: `ZonoPatch_v0.5.8_M5.6_RW_Value_Cell.dylib`
- Dylib size: `1421376` bytes
- Dylib SHA256: `191c93dea1fc43d504860abcfd047fcf15391c6ad74c39be383f299eaa7cf54c`
- Mach-O: thin arm64 dylib
- Independent artifact/hash verification: PASS

### Immediate device acceptance

1. Footer must show `0.5.8 · M5.6`.
2. Runtime Slider: drag repeatedly; no freeze/crash during drag. Release should invoke once.
3. Rebuild the Static Offset Number test with M5.6. Old M5.5-generated binaries do not contain RW value cells and must not be reused for this test.
4. Static Number + Auto/MOV W case: changing value must not show RX permission errors.
5. Static Slider FMOV case: integer values 1..10 should update through RW cell without executable-page writes.
6. Regress M5.5.1 Builder layout/persistence and M5.4 Unified Method Finder.

### Important compatibility boundary

M5.6 dylib alone cannot retrofit RW value cells into an already-generated M5.5 UnityFramework. Static Number/Slider must be generated again with the M5.6 Builder/postprocess so the generated ON variant contains the LDR-to-RW-cell parameterization.
