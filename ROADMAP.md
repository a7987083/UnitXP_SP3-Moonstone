# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.5-address-owning-method-v1`
- CI validated product head: `fa2f9db21b507da64feb6ffe0acc6a29d71aff2e`
- Stage: `M4.5 Address → Owning Method Resolver V1`
- Final CI run: `35795001139` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.5-OwningMethod-V1`
- Artifact ID: `10723682927`
- ZIP SHA256: `7d3070974665d4cf2962f7e4bb5283bff0c03b938bc05ce57b8f1f943545c250`
- Dylib: `ZonoPatch_v0.5.8_M4.5_OwningMethod_V1.dylib`
- Dylib size: `1052128`
- Dylib SHA256: `faa43520ac6e7086a0d6f6719a0c7076578a12d8ba493088cc114b0748ff7fa1`
- Current validation boundary: source + CI + binary verified; M4.5 requires physical-device acceptance.

## Baselines that must not regress

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`.
- Method Finder V3 M2.2 device-accepted: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`; user device-confirmed `/0` create/test/generated-binary.
- M4.1 UI/UX V2: `911dec0c56234387820fbec5daf996e396f86294`.
- M4.2 Typed Args: `e7c81172b04e162f74b3652048dcaf499d753aa4`.
- M4.3 Instance Resolver V1: `a5688b3f42f53aa50366f349813be069ef0e5418`.
- M4.4 Instance Resolver V2: `21775c3e0320399784a5a5b87131ab96cb9a80d5`.
- M4.4.1 Hotfix: `0025556b8f3a2a20466b7344120ca82f9db7f921`.
- M4.4.2 Search Restore: `fe8655444420bc9445ee741e2d3c4cffbaead066`.

## Stable architecture constraints

- Exact dyld image identity and Offset Resolver V2 remain unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- Raw `Il2CppObject *` addresses are never serialized.
- M4.5 changes discovery/UI only; no Static Patch or Runtime Action ABI version bump.
- Normal named method search must remain on M4.4.2's proven V3 execution route.

## Implemented inheritance

### M4.1 UI/UX V2

- UnityFramework-first automatic binary target with fallback.
- App Libraries picker, touch passthrough, scroll preservation, direct-build preflight, editable Runtime Action title.

### M4.2 Typed Arguments UI V1

- `/0` retained.
- `/1`: bool, signed/unsigned 32/64, float, double, primitive-backed enum, `System.String`.
- Dynamic arity filter and compact result cards.
- `/2+` remains visible but not executable.

### M4.3 / M4.4 Instance Resolver

- Runtime Assembly picker and custom result limit up to `1024`.
- IL2CPP liveness instance enumeration.
- One instance auto-use; multiple instances explicit picker; session selection revalidated before reuse.
- No raw object pointer persistence.

### M4.4.1 Finder/Input Hotfix

- Bare HEX / `0x` / `rva:` / `va:` input normalization.
- Patch Offset bare HEX -> `0x...` normalization.
- `/1` support for exact `Vector2`, `Vector3`, `Quaternion`, `Color` layouts.
- Unsupported argument reason text added.

### M4.4.2 Search Restore

- Restored original device-proven V3 named search route after M4.4.1 regression.
- Default untouched Assembly state is global search with `Assembly-CSharp` first, displayed as `Assembly-CSharp · 优先`.
- Explicit picker selection creates a strict Assembly filter.

## Implemented — M4.5 Address → Owning Method Resolver V1

H5GG 1.9.6 documents using an instruction offset to locate cached method information. M4.5 adopts the useful goal but uses a stricter interval rule instead of suffix partial matching.

- Added `ZNIL2CPPOwningMethodResolver.h/.mm`.
- Added `ZNM45AddressOwningMethodUI.mm` as the outer Finder address layer.
- Named method queries are not reimplemented; they delegate unchanged to M4.4.2 proven-V3.
- Address forms accepted: bare HEX, `0x...`, `rva:...`, `rva:0x...`, `va:0x...`.
- Exact method entry lookup remains supported.
- Interior ARM64 instruction lookup now resolves with:

```text
methodStart <= targetRVA < nextKnownMethodStart
```

- Interior lookup fails closed if the 6-second live scan budget is reached or a safe next-method upper bound is unavailable.
- Shared/generic native entry pointers return multiple MethodInfo candidates rather than guessing.
- Candidate keeps both original query RVA and method-start RVA, plus next method RVA and `+intraMethodOffset`.
- Details adds an `地址归属（M4.5）` card showing query RVA, owning method start, next method start and ownership kind.
- For an interior-address candidate, canonical identity includes `+0x...`, so existing V3 Patch bridge/Offset Resolver can preserve the original instruction offset when creating Patch.
- Unsupported `/1` arguments no longer show a gray fake input. They are replaced by a normal reason label; `测试执行/创建方法` stay disabled until marshaling exists.
- Static Patch ABI and Runtime Action ABI are unchanged.
- Final CI run `35795001139`: Source Contract / arm64 Build / Binary Verify / Artifact Upload all passed.
- Downloaded artifact independently verified as thin arm64; ZIP and dylib hashes match CI/GitHub.

## Next planned engineering stage

### M4.6 Full Method Signature Identity

After M4.5 device acceptance, replace `method + argumentCount` as the primary identity with a full signature descriptor:

```text
Assembly + Namespace + Class + Method + ParameterType[] + ReturnType
```

Goals:

- exact overload disambiguation;
- signature-driven UI;
- foundation for generic `/2+` marshaling;
- safer Runtime Action persistence and re-resolution.

### Later: Generic Invoke / Object Inspector

- Generic `ParameterDescriptor[] -> params[N] -> il2cpp_runtime_invoke`.
- Runtime Object/Field Inspector.
- ValueType metadata-driven access.
- Array/List/Dictionary navigation and export.
- Address -> Object containment/back-reference resolver.

## Immediate physical-device acceptance

1. Regress the same normal method-name search through visible `搜索` and keyboard Search; M4.5 must not break M4.4.2.
2. Enter a known method-entry RVA and verify result reports `+0x0` / exact entry.
3. Enter a known ARM64 instruction RVA inside that same method and verify it returns the same method with correct `+0x...` method-relative offset.
4. Open Details and verify `查询 RVA / 方法入口 / 下一方法入口 / 判定`.
5. Create Patch from the interior-address result; Builder must keep the original queried instruction offset, not collapse to method start.
6. Check an unsupported `/1`: no gray fake input; a normal type/reason label should appear, while Test/Create remain disabled.
7. Regress Patch Offset normalization, supported `/1`, M4.4 instance selection and M4 `/0` paths.

## Promotion rule

Do not mark M4.5 device-verified from CI alone. Promote only after exact-entry and interior-instruction address lookups are verified on a real target and normal named search is confirmed not to regress.
