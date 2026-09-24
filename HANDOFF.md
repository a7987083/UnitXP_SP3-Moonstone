# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.5 Typed Control Binding V2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`
- CI-validated product head: `3548cbc655f4347e03947d9dba0fb501f15b137e`
- Product-code head before CI-only commit: `d4f8da77a7fef8db72bcd9d19a2323a39fd577d1`
- Final product CI Run: `35996840472` — SUCCESS
- Job: `107623672455`
- Artifact ID: `10806284095`
- ZIP SHA256: `9ec1d6ab1a484572b16c1eff57eb90a7d54836b9717ed9748296fcc66a4b86e9`
- Dylib: `ZonoPatch_v0.5.8_M5.5_Typed_Control_Binding_V2.dylib`
- Dylib size: `1404656`
- Dylib SHA256: `0dacef0f731d0a6b59e1446b08977d69a6eeb732096c761a9ed321be0214375a`

## Control architecture

Public UI is backend-independent:

```text
Control Type:
  Switch / Button / Number / Slider

Value Type:
  Auto / I32 / U32 / I64 / U64 / F32 / F64

Runtime range:
  Default / Min / Max / Step
```

Do not add `MOV`, `FMOV`, `ABI` as public control types. They are backend adapters.

## Runtime behavior

- Auto uses managed parameter type when available.
- Builder Value Type button cycles all seven value types.
- Auto UI may display e.g. `A→I32` / `A→F32`.
- Long-press Value Type opens Default/Min/Max/Step editor.
- Number canonicalizes the value before M5.3 auto invoke.
- Slider quantizes before the old runtime handler caches the value; default is 1..10, step 1.
- M5.3 still owns customer immediate execution: Button tap, Switch change, Number edit-end, Slider release.
- Typed control config is serialized in existing Runtime Action JSON; 64-byte Entry ABI unchanged.

## Static behavior

Value Type is stored in Static Entry flags bits 11..13; old zero bits mean Auto. Entry ABI remains 128 bytes.

Backend selection:

```text
MOVZ(+MOVK), W register -> I32/U32
MOVZ(+MOVK), X register -> I64/U64
scalar FMOV S,#imm      -> F32
scalar FMOV D,#imm      -> F64
Auto                     -> infer only from verified instruction family
```

- Signed/unsigned explicit type must match W/X width.
- Large integer values require the generated Enabled sequence to contain the necessary MOVK halfword slots.
- F32/F64 requires scalar FMOV immediate and exact representability; no approximation.
- Static Number keeps exact `valueText` so large U64 values are not converted through double before integer parsing.
- Static Slider customer surface is currently fixed at `1..10 / step 1`.
- Old M5.3 Static MOV-only observer is removed at M5.5 install; M5.3 Runtime auto-execute remains.

## M5.4 retained

- Unified Method Finder is the final Search / Results / Detail renderer.
- User already confirmed Unified/search-history UI is visible on device.
- Search history max 50, persistent, newest-first, dedupe, row tap intended to autofill only.

## Immediate device checklist

1. Static Builder: cycle Control Type and Value Type; confirm the two axes do not overwrite each other.
2. Static Number + I32/U32 on MOV W; test 1, 100, 2147483647 where instruction slots allow.
3. Static I64/U64 on MOV X; test a multi-halfword value on a variant with sufficient MOVK slots.
4. Static F32 on `FMOV S,#1.0` and F64 on `FMOV D,#1.0`; Slider values 1..10 must apply exactly.
5. Try a type mismatch or non-encodable FMOV value; expect fail-closed `执行失败`.
6. Runtime create Int32/UInt32/Int64/UInt64/Single/Double methods; Auto should show the matching recommendation.
7. Runtime Slider must land on integer steps and invoke once on release.
8. Long-press Runtime Value Type; edit range and confirm it survives rerender/build.
9. Regress Unified history tap/manual search, candidate Test/捕获, receiver long-press, 创建方法 and Chain V2.

## Open boundaries

- Static arbitrary custom Min/Max/Step is not yet embedded into generated Static metadata; public Static Slider currently uses the deliberate 1..10/1 default.
- Static typed values still use transactional executable-page mutation of generated ON variants. Some signing/device models may reject RX→RW; future design should use generated parameterized stubs + RW value cells if necessary.
- Scalar FMOV immediate does not represent arbitrary F32/F64; M5.5 refuses non-exact values rather than approximating.
- M5.2 Chain Level 0 `previous managed return is null` remains a separate backend investigation.
