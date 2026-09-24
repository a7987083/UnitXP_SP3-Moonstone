# ROADMAP

## Current milestone — M5.5 Typed Control Binding V2

Branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`

CI-validated head: `3548cbc655f4347e03947d9dba0fb501f15b137e`  
Product-code head before final CI-only contract commit: `d4f8da77a7fef8db72bcd9d19a2323a39fd577d1`

### Public control model

Customer-facing controls remain deliberately simple and backend-independent:

- Switch
- Button
- Number
- Slider

Numeric Value Type is a separate axis:

- Auto
- I32
- U32
- I64
- U64
- F32
- F64

Runtime numeric configs additionally carry `Default / Min / Max / Step`.

### Implemented in M5.5

- Added `ZNValueTypeModel` as the shared Runtime/Static type vocabulary.
- Runtime `Auto` resolves from IL2CPP managed parameter names (`Int32/UInt32/Int64/UInt64/Single/Double`).
- Runtime Builder now has an independent Value Type button; `Auto` displays the resolved ABI recommendation when known.
- Long-press Runtime Value Type opens the range editor for Default / Min / Max / Step.
- Runtime Slider quantizes to configured `step` before the existing M5.3 release-to-invoke path. Default Slider policy is `1..10 / step 1`, including F32/F64 controls.
- Runtime Number canonicalizes input using the selected/resolved Value Type before invocation.
- Runtime action JSON control configs persist `valueType/default/min/max/step` without changing the 64-byte Runtime Action Entry ABI.
- Static Builder now exposes `[Control Type] + [Value Type]` independently.
- Static Value Type is encoded into unused entry.flags bits 11..13; legacy zero bits decode as Auto. Static Entry remains exactly 128 bytes.
- Static Number preserves exact authored text (`valueText`) so U64 does not require a double round-trip before encoding.
- Static Slider now uses integer customer values `1..10`, `step 1`.
- Added `ZNM55StaticTypedBinding` and replaced the old M5.3 Static MOV-only notification observer while retaining M5.3 Runtime auto-execute behavior.
- Static typed adapters:
  - verified `MOVZ(+MOVK)` -> I32/U32/I64/U64;
  - verified scalar `FMOV S,#imm` -> F32;
  - verified scalar `FMOV D,#imm` -> F64;
  - Auto chooses only from the verified instruction family;
  - type/instruction mismatches fail closed;
  - FMOV values not exactly representable by scalar immediate fail closed.
- Scalar FMOV integer values 1..31 were independently checked against the immediate expansion; the current public Slider intentionally defaults to 1..10.
- M5.4 Unified Method Finder and visible search history remain underneath M5.5.

### ABI

- `ZN44StaticEntry`: 128 bytes, unchanged.
- `ZNRuntimeMethodCallEntry`: 64 bytes, unchanged.
- Static control type remains flags bits 8..10.
- Static Value Type uses flags bits 11..13.
- Runtime typed/range configuration remains JSON through existing Runtime Action reserved[3].

### Final CI / artifact

- Workflow: `Build Runtime Patch Menu v0.5.8 M5.5 Typed Control Binding V2`
- Run: `35996840472`
- Job: `107623672455`
- Result: SUCCESS
- Artifact: `ZonoPatch-v0.5.8-M5.5-Typed-Control-Binding-V2`
- Artifact ID: `10806284095`
- ZIP SHA256: `9ec1d6ab1a484572b16c1eff57eb90a7d54836b9717ed9748296fcc66a4b86e9`
- Dylib: `ZonoPatch_v0.5.8_M5.5_Typed_Control_Binding_V2.dylib`
- Dylib size: `1404656` bytes
- Dylib SHA256: `0dacef0f731d0a6b59e1446b08977d69a6eeb732096c761a9ed321be0214375a`
- Mach-O: thin arm64 dylib
- Independent downloaded ZIP/dylib hash verification: PASS

### Device acceptance required

1. Static Builder: verify Control Type and Value Type cycle independently through the expected options.
2. Generate a Static I32/U32 MOVZ-compatible Number and confirm integer value changes the generated ON variant safely.
3. Generate I64/U64 cases with sufficient MOVK halfword slots and verify exact large values; unsupported slot layouts must fail closed.
4. Generate `FMOV S,#1.0` and `FMOV D,#1.0` compatible variants; select F32/F64 Slider and test integer values 1..10.
5. Confirm unsupported FMOV values/type mismatches show `执行失败` and do not corrupt the variant.
6. Runtime Method: confirm Auto resolves I32/U32/I64/U64/F32/F64 from the managed signature.
7. Runtime Number: verify typed bounds and end-edit invoke.
8. Runtime Slider: verify UI lands only on integer step values and release invokes once.
9. Long-press Runtime Value Type and verify Default/Min/Max/Step survive Builder rendering and generated action export.
10. Regress M5.4 Unified history, candidate binding, receiver capture, 创建方法 and Chain V2.

### Next engineering work after device evidence

- Add persistent Static custom Range metadata if product testing shows fixed type defaults / Slider 1..10 are insufficient. Do not enlarge the 128-byte entry casually; use an owned metadata extension/table.
- If target signing prevents executable-page RX→RW changes, move dynamic Static values to generated parameterized stubs + RW value cells.
- After M5.4/M5.5 device regression, physically split legacy mixed UI/backend installers and remove obsolete Method Finder renderer sources from the build.
