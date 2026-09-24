# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.7 Unified Control Runtime**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `refactor/m5.7-unified-control-runtime`
- CI-validated product head: `a31816422f3390a1e0b209bd0fe55e8f4b281710`
- Run: `36019982680` — SUCCESS
- Job: `107702118932`
- Artifact ID: `10815968483`
- ZIP SHA256: `a369397db62835a98e5e1d66a2ca4dec7cc54d24137c3ffca7cc2449655fafd1`
- Dylib size: `1438080`
- Dylib SHA256: `252610a6bca9b09d8db2d52ac15607b5b977f69c1c726a986034e4b5b423ce8b`

## M5.7 control architecture

Customer controls have one interaction contract for both Static/Offset and Runtime Method backends:

```text
Switch  -> change commits immediately
Button  -> click commits immediately
Number  -> typing only saves; Return/Done saves + dismisses keyboard; Execute commits
Slider  -> drag only updates value; TouchUp commits exactly once
```

### Runtime Method

- Final event owner: `ZNM57UnifiedRuntimeControls`.
- M5.3 auto-execute, M5.5.1 slider release handler and M5.6.2 isolation are not installed.
- The historical M4.2 `ZNRuntimeMethodCallFeatureUI` is not installed; M5.1/M5.7 typed Runtime cards are the sole customer Runtime UI.
- Number `执行` and Slider release both reuse the existing silent customer execution path, which reads the currently visible control value before invoking IL2CPP.

### Static / Offset

- UI owner: `ZNFeatureRuntimeControlsV2` with M5.7 semantics.
- Backend owner: `ZNM56StaticValueCellBinder` only.
- Number input no longer posts apply notifications on keyboard confirmation; inline `执行` posts one commit.
- Slider `ValueChanged` only stores/quantizes; release posts one commit.
- Generated typed variants remain RW-value-cell based; runtime executable-page writes are not part of the accepted path.

## Runtime-only build correction

Two historical bugs were independent:

1. Builder UI required `workspace.filledCount > 0`, effectively requiring a Static row before `生成新二进制` could be enabled.
2. Runtime-only output has been suffixless since M5.1, but the verifier still skipped anything without `.znpatched`, so the Mach-O could be successfully generated and then falsely reported as failed.

M5.7 adds `ZNM57RuntimeOnlyBuilderGate` and verifies actual Mach-O files by magic/content. Runtime Actions with zero complete Static rows are a first-class build mode; partial Offset drafts do not block it.

## Immediate device checklist

1. Footer: `0.5.8 · M5.7`.
2. Runtime-only with zero complete Offset+Enabled rows: build button available and final result reports success.
3. Runtime Number: type value -> Return closes keyboard -> no effect yet -> tap `执行` -> effect once.
4. Runtime Slider: drag repeatedly -> no freeze/crash -> release automatically invokes once.
5. Verify only one Runtime customer card set exists.
6. Regenerate a Static Number target with M5.7: type -> Return closes keyboard/no apply -> inline `执行` applies once through RW cell.
7. Regenerate a Static Slider target: dragging is UI-only; release applies once through RW cell.
8. Regress M5.5.1 authoring persistence and M5.4 Unified Method Finder.

## Compatibility boundaries

- Static Number/Slider acceptance must use a target regenerated with the current RW-value-cell Builder.
- Value-cell LDR literal remains ±1MB and fails closed when layout cannot satisfy it.
- Static Entry ABI remains 128 bytes; Runtime Action Entry ABI remains 64 bytes.
- M5.2 Chain Level 0 null-return investigation remains separate.
