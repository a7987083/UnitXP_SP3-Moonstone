# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.5 Address → Owning Method Resolver V1 on top of M4.4.2 Search Restore + M4.4 Instance Resolver + M4.2 typed invoke + M4.1 UX + Offset Resolver V2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.5-address-owning-method-v1`
- CI validated product head: `fa2f9db21b507da64feb6ffe0acc6a29d71aff2e`
- Final CI run: `35795001139` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.5-OwningMethod-V1`
- Artifact ID: `10723682927`
- ZIP SHA256: `7d3070974665d4cf2962f7e4bb5283bff0c03b938bc05ce57b8f1f943545c250`
- Dylib: `ZonoPatch_v0.5.8_M4.5_OwningMethod_V1.dylib`
- Dylib size: `1052128`
- Dylib SHA256: `faa43520ac6e7086a0d6f6719a0c7076578a12d8ba493088cc114b0748ff7fa1`
- Format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device verification.

### Device-verified predecessor only

M4 Runtime Method Call V1 has explicit user device evidence for `/0` create, `/0` test execute and generated binary usable. It is not a full regression pass.

### Current M4.5 state

- source implemented: YES;
- committed to GitHub: YES;
- arm64 CI compile/link/sign: YES;
- binary verification: YES;
- artifact upload + independent hash check: YES;
- exact-entry RVA reverse lookup device validation: PENDING;
- interior-instruction -> owning method device validation: PENDING;
- named-search M4.4.2 regression test: PENDING;
- unsupported `/1` reason-label UI device validation: PENDING;
- M4.4 instance selection device validation: PENDING;
- receiver/`this` hook capture backend: NOT IMPLEMENTED;
- full regression: NO.

## Architecture invariants

- Offset Resolver V2 exact image identity/canonical RVA behavior stays unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- `/1` text arguments continue using the existing Runtime Action string pool.
- Raw `Il2CppObject *` addresses are not persisted.
- M4.5 does not alter ABI or generated-binary entry sizes.

## Named search routing — do not regress

M4.3 previously swapped:

```text
zn60v3_startSearch: <-> znm43_startSearch:
```

M4.4.2 established the current reference behavior: both visible Search and keyboard Search route through normalization and then delegate actual named search to the original device-proven V3 implementation. Untouched Assembly state means global search with Assembly-CSharp first; only an explicit picker choice is strict.

M4.5 is installed outside that route. `znm45_submitSearch:` only consumes address-shaped queries; normal method names immediately delegate back to the M4.4.2 implementation.

## M4.5 address ownership model

Accepted inputs:

```text
38064A8
0x38064A8
rva:38064A8
rva:0x38064A8
va:0x...
```

`va:` is converted using current UnityFramework runtime base.

For an exact method entry:

```text
targetRVA == methodStart
```

M4.5 returns `ownershipKind = exact-method-entry`.

For an instruction inside a method, M4.5 scans live IL2CPP MethodInfo/native pointers and requires:

```text
methodStart <= targetRVA < nextKnownMethodStart
```

Then it records:

```text
queryRVA
methodRVA
nextMethodRVA
intraMethodOffset = queryRVA - methodRVA
ownershipKind = bounded-method-interval
```

Interior resolution fails closed when the scan exceeds the 6-second budget or no safe next-method boundary exists. This is intentional: do not infer ownership from only “closest previous method” when the upper bound is unknown.

Shared/generic native pointers may map multiple MethodInfos to the same method start. Those are returned as multiple candidates; do not silently choose one.

## Patch bridge behavior

M4.5 interior candidate canonical form is:

```text
Assembly!Namespace.Class::Method/N+0xDELTA
```

`ZNIL2CPPResolver.parseNamedOffsetExpression` already parses delta before `/argumentCount`, so the existing V3 Patch bridge can preserve the original instruction address through Builder/Validator. No new Patch ABI or patch engine was introduced.

## `/1` UI cleanup

M4.4.1 appended an unsupported reason into the disabled input placeholder but left the text field `enabled = NO` / alpha reduced. This caused the user to still see a gray input.

M4.5 now post-processes result cards:

```text
supported /1
→ actual editable input remains

unsupported /1
→ disabled gray input removed
→ normal-color type/reason label inserted
→ Test/Create remain disabled
```

This is UI truthfulness only; it does not pretend unsupported ABI kinds are callable.

## Existing typed/instance behavior retained

- Primitive/string `/1`: bool, signed/unsigned integers, float/double, enum, System.String.
- Exact Unity `/1`: Vector2, Vector3, Quaternion, Color.
- `/2+`, custom structs, ordinary managed object refs, ref/out and pointer remain fail closed.
- M4.3 liveness + M4.4 session instance selection remain unchanged.

## Build result

Product/CI head:

```text
fa2f9db21b507da64feb6ffe0acc6a29d71aff2e
```

CI run `35795001139`:

```text
Source Contract  PASS
arm64 Build      PASS
Binary Verify    PASS
Artifact Upload  PASS
```

Independent downloaded artifact verification:

```text
Mach-O 64-bit arm64 dynamically linked shared library
ZIP SHA256   7d3070974665d4cf2962f7e4bb5283bff0c03b938bc05ce57b8f1f943545c250
Dylib SHA256 faa43520ac6e7086a0d6f6719a0c7076578a12d8ba493088cc114b0748ff7fa1
```

## Known M4.5 limitations

- Live owning-method index is rebuilt by scan; very large games may approach the 6-second safety budget.
- Interior ownership deliberately fails closed on timeout/incomplete upper bound.
- Full Method Signature identity is not implemented yet; same-name/same-arity overload ambiguity remains a later task.
- Receiver capture through temporary native instrumentation is still not implemented.
- Current invoke engine still executes at most one explicit argument.

## Immediate device checklist

1. Search the same normal method name with visible Search and keyboard Search; confirm both still work.
2. Enter a known method start RVA; confirm exact method and `+0x0`.
3. Enter an instruction address several ARM64 instructions inside that method; confirm same method and correct `+0x...`.
4. Verify Details shows query RVA, method start, next method start and ownership kind.
5. From the interior result use Create Patch; confirm Builder offset is the original queried instruction RVA.
6. Find unsupported `/1`; confirm the gray fake input is gone and a reason label is shown.
7. Regress Patch Offset normalization, supported `/1`, instance selection and `/0` create/test/generated binary.

## Next engineering action

After real-device acceptance of M4.5, proceed to **M4.6 Full Method Signature Identity**. Do not expand generic `/2+` invocation before overload identity is exact.
