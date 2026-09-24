# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.6 Stable Runtime Slider + Static RW Value Cell V1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`
- CI-validated head: `2d6351ac7e2652ae76e2ba2542118cc0beb2338e`
- Run: `36004751812` — SUCCESS
- Job: `107649917061`
- Artifact ID: `10809323261`
- ZIP SHA256: `fc1f0596f2f603a993d2249e9ab1c965e5ff38019fcda3d5d4a75a189ecf2c03`
- Dylib size: `1421376`
- Dylib SHA256: `191c93dea1fc43d504860abcfd047fcf15391c6ad74c39be383f299eaa7cf54c`

## Device evidence / root causes

### Static Number/Slider

M5.5 device error:
`写入完成但恢复 RX 权限失败: errno=13 (Permission denied)`.

Conclusion: runtime executable mutation is not supported on the current target environment. Do not reintroduce an RX->RW->RX typed-value path.

M5.6 architecture:

```text
Builder
MOVZ/MOVK or FMOV immediate
        ↓ build-time rewrite
LDR W/X/S/D from owned __ZNDATA value cell
        ↓
final signed binary
        ↓ runtime
atomic store to RW value cell only
        ↓
normal Static selectedTarget dispatch
```

Old M5.5-generated target binaries must be rebuilt with M5.6; the dylib cannot retrofit cells into already-installed executable code.

### Runtime Slider

M5.5 performed Runtime Action `refresh` on every `ValueChanged`; dragging can emit many events and caused device freeze/crash.

M5.6:
- drag: lightweight M5.1 cache only;
- release/cancel: one refresh, one step quantization, one cache, one invoke;
- no render during drag.

## Retained architecture

- M5.5.1 Builder baseline recovery.
- Runtime authoring persistence key `zonoe.m5.5.authoring-actions.v1`.
- Control Types: Switch / Button / Number / Slider.
- Value Types: Auto / I32 / U32 / I64 / U64 / F32 / F64.
- M5.4 Unified Method Finder remains final Search/Results/Detail renderer.
- Static Entry ABI 128 bytes; Runtime Action Entry ABI 64 bytes.

## Immediate device checklist

1. Install M5.6 dylib; footer must show `0.5.8 · M5.6`.
2. Runtime Slider: drag 1->10 repeatedly; no freeze/crash. Release should execute only once.
3. Rebuild the Offset/Static test using M5.6 Builder.
4. Use the same MOV-style Number/Auto case; changing Number should no longer report RX permission errors.
5. Test FMOV Slider after regenerating with M5.6; values should be sourced from RW cells.
6. Verify M5.5.1 authoring persistence and Builder spacing remain intact.

## Open boundaries

- M5.6 RW value-cell behavior is CI/binary verified but not yet device accepted.
- Generated LDR literal requires cell within ±1MB; Builder fails closed if layout cannot satisfy it.
- M5.2 Chain Level 0 null-return investigation remains separate.
