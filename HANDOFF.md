# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.6.2 Runtime/Static Recovery**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `fix/m5.6.2-runtime-slider-static-valuecell`
- CI-validated head: `690ee9eb9af2f2431f8d8909fa9c1dd558ae77aa`
- Run: `36012593002` — SUCCESS
- Job: `107676813892`
- Artifact ID: `10812584568`
- ZIP SHA256: `48662e7ffdc798d18358b443a6996214e3eb37e2a9fc005232e7afd7ab533aeb`
- Dylib size: `1421392`
- Dylib SHA256: `d6657fdc723b1b1ca68637dac63ec66f3f95d3a0cade6f5066361215dd6588c7`

## Why M5.6.2 exists

Device evidence after the first M5.6 attempt showed three unresolved failures:

1. Static Number/Auto still hit `RX permission denied`.
2. Runtime Slider still froze/crashed on drag.
3. Static Number Auto->F32 remained at effective value 0 regardless of customer edits.

Audit then found a later regression path had restored the M5.3 executable-page Static writer and stopped using RW Value Cell as the final owner. This invalidated the earlier assumption that M5.6 had fully switched to RW cells.

## M5.6.2 architecture

### Runtime-only builder mode

`workspace.filledCount` is no longer authoritative. Runtime-only is chosen when Runtime Actions exist and there are **zero complete Static rows** (`Offset && Enabled`). Partial/stale Offset rows are ignored for mode selection and logged.

### Static typed values

```text
Static Builder V3
  -> ZNF1 metadata / Control + Value Type flags
  -> RW Value Cell V1 build-time parameterization
  -> Static RVA Protection V1
  -> Ad-hoc signing
```

Runtime:

```text
Customer Number/Slider
  -> ZNM56StaticValueCellBinder (single owner)
  -> atomic store into owned __ZNDATA RW cell
  -> normal selectedTarget dispatch
```

`ZNM53StaticControlBinder` and `ZNM55StaticTypedBinder` observers are explicitly removed before the M5.6 binder is installed. Runtime executable-page typed writes are not allowed in the M5.6.2 acceptance path.

### Runtime Slider isolation

Final public `zn51_runtimeSliderChanged:` is replaced by `ZNM562SliderIsolation`.

- drag: UI-only, integer quantize/clamp;
- no Runtime Action refresh;
- no render;
- no auto Invoke;
- no release target attachment;
- explicit Runtime card `执行` button reads the visible slider value and invokes once.

This is intentional diagnostic isolation. Do not re-enable auto-invoke until device evidence proves the crash is not in the underlying F32/receiver/Invoke path.

## Immediate device checklist

1. Footer must show `0.5.8 · M5.6.2`.
2. Runtime Slider: drag repeatedly without pressing `执行`. It must not freeze/crash.
3. Then press `执行` once. If this crashes, the fault is Runtime Invoke/receiver/ABI, not Slider ValueChanged.
4. Runtime-only: create Runtime Actions with no complete Offset+Enabled row and generate. Partial Offset drafts must not force Static/Mixed mode.
5. Static MOV Number: regenerate target with M5.6.2 and change value; no RX permission error is acceptable.
6. Static Auto->F32/FMOV: regenerate target with M5.6.2; changing client value must change the RW cell-backed value instead of remaining 0.
7. Regress M5.5.1 authoring persistence/Builder layout and M5.4 Unified Method Finder.

## Compatibility boundaries

- Old M5.5/M5.6.1 generated Static targets are not valid RW-cell test artifacts; regenerate with M5.6.2.
- LDR literal value-cell parameterization is ±1MB and fails closed if the owned-data layout cannot satisfy it.
- Static Entry ABI remains 128 bytes; Runtime Action Entry ABI remains 64 bytes.
- M5.2 Chain Level 0 null-return investigation remains separate.
