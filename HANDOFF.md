# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.4.2 Search Restore on top of M4.4.1 input/typed-struct hotfix + M4.4 multi-instance selection + M4.3 Finder/Instance Resolver + M4.2 typed `/1` + M4.1 UX + Offset Resolver V2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `fix/runtime-patch-menu-v0.5.8-m4.4.2-search-restore`
- CI validated product head: `fe8655444420bc9445ee741e2d3c4cffbaead066`
- Final CI run: `35791561620` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.4.2-SearchRestore`
- Artifact ID: `10722211742`
- ZIP SHA256: `c420ab0af09943be5bf05f10cf358514071b9b00982fb242f4573a1a5b94578c`
- Dylib: `ZonoPatch_v0.5.8_M4.4.2_SearchRestore.dylib`
- Dylib size: `1018880`
- Dylib SHA256: `4497d04f3583a4bc447e3cdd692c2bf99479d87440221c2b85554210b251b84b`
- Format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device verification.

### Device-verified predecessor only

M4 Runtime Method Call V1 has explicit user device evidence for `/0` create, `/0` test execute and generated binary usable. This is not a full regression pass.

### Current M4.4.2 state

- source implemented: YES;
- committed to GitHub: YES;
- arm64 CI compile/link/sign: YES;
- binary verification: YES;
- artifact upload + independent hash check: YES;
- restored Finder search route device validation: PENDING;
- explicit Assembly strict-filter device validation: PENDING;
- HEX/RVA/VA reverse lookup device validation: PENDING;
- Patch Offset normalization device validation: PENDING;
- common Unity struct `/1` device validation: PENDING;
- M4.4 multi-instance selection device validation: PENDING;
- receiver/`this` hook capture backend: NOT IMPLEMENTED;
- full regression: NO.

## Architecture invariants

- Offset Resolver V2 exact image identity/canonical RVA behavior stays unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- `/1` text argument uses the existing string pool + `ZNRuntimeActionFlagArgument0Text / reserved[0]`.
- Common Unity struct values are still one text argument; conversion to typed struct happens only immediately before `il2cpp_runtime_invoke`.
- Do not persist `/var/containers/Bundle/Application/<UUID>/...` paths.
- Do not persist raw `Il2CppObject *` addresses in generated Runtime Actions.
- M4.4.2 is search routing only; no ABI version/entry-size changes.

## Critical search-routing history

M4.3 performs:

```text
zn60v3_startSearch:  <->  znm43_startSearch:
```

via `method_exchangeImplementations`.

That means after installation:

```text
selector znm43_startSearch:
→ original V3 search implementation

selector zn60v3_startSearch:
→ M4.3 search implementation
```

This matters because the M4.3 visible Search button was bound to `znm43_startSearch:` and was therefore using the original V3 engine that the user confirmed worked on device. The keyboard Search target was `zn60v3_startSearch:` and used the M4.3 implementation.

M4.4.1 attempted to make them consistent by rebinding both controls to `znm441_submitSearch:`. Device feedback then showed a regression: both controls became consistent, but both could return `找不到 IL2CPP 方法` for a query that the earlier visible Search button could find.

M4.4.2 fixes this by adding `ZNM442SearchRestore.mm` as the outermost route layer. Both keyboard and visible Search now perform normalization, then delegate actual search execution to post-swap `znm43_startSearch:`, i.e. the original device-proven V3 implementation.

## Assembly semantics

Before M4.4.2, the M4.3/M4.4.1 path treated the visual `Assembly-CSharp` default as a strict search filter by forming:

```text
Assembly-CSharp.dll!Method
```

This was a regression from original V3 behavior. Original V3 behavior with no explicit Assembly is:

```text
scan all loaded Assemblies
Assembly-CSharp first
then remaining Assemblies
```

M4.4.2 restores that behavior until the user explicitly chooses an Assembly.

Current rules:

```text
Default / untouched Assembly button
→ Assembly-CSharp · 优先
→ global V3 search, Assembly-CSharp-first

User explicitly chooses Assembly-CSharp
→ strict Assembly-CSharp search

User explicitly chooses another Assembly
→ strict selected-Assembly search

User chooses 全部 Assembly
→ global search
```

The explicit-selection state is process/UI-session state only. Temporary `Assembly!query` qualification is used for execution but is not left in the visible method-name field.

## Accepted method/address input

M4.4.1 input normalization is retained:

```text
38064A8       -> rva:0x38064A8
0x38064A8     -> rva:0x38064A8
rva:38064A8   -> rva:0x38064A8
rva:0x38064A8 -> rva:0x38064A8
va:0x...      -> loaded UnityFramework Runtime VA -> RVA -> reverse lookup
```

Address queries bypass Assembly filtering and use V3 reverse-RVA search.

## Patch Offset normalization

The validator/workspace already accepts bare HEX and `0x`. M4.4.1 UI normalization remains active:

```text
38064A8
```

press `完成`:

```text
0x38064A8
```

Normal read/validate/build safety checks remain unchanged.

## `/1` behavior retained

Primitive/string support inherited from M4.2:

- bool;
- signed/unsigned 32-bit integer;
- signed/unsigned 64-bit integer;
- float/double;
- primitive-backed enum;
- `System.String`.

M4.4.1 additionally handles exact Unity value types:

```text
Vector2      1,2
Vector3      1,2,3
Quaternion   0,0,0,1
Color        1,0,0,1
```

Unsupported `/1` parameters expose a visible type/reason. Custom struct, ordinary managed object reference, ref/out, pointer and `/2+` still fail closed.

## M4.3 / M4.4 instance behavior retained

- M4.3 enumerates live instances through IL2CPP liveness APIs and validates Class identity.
- One live instance can be auto-used as `this`.
- M4.4 adds process-session explicit selection for multiple same-Class instances.
- Selection key is `assembly|namespace|class`.
- Selected object is revalidated before reuse; stale selection is cleared.
- Raw object pointers are not serialized and are resolved again after restart.

## Build result

M4.4.2 product/CI head:

```text
fe8655444420bc9445ee741e2d3c4cffbaead066
```

CI run `35791561620`:

```text
Source Contract  PASS
arm64 Build      PASS
Binary Verify    PASS
Artifact Upload  PASS
```

Independent artifact check:

```text
Mach-O 64-bit arm64 dynamically linked shared library
ZIP SHA256   c420ab0af09943be5bf05f10cf358514071b9b00982fb242f4573a1a5b94578c
Dylib SHA256 4497d04f3583a4bc447e3cdd692c2bf99479d87440221c2b85554210b251b84b
```

## Receiver capture boundary

`receiver/this` capture through temporary native-method instrumentation remains **not implemented**. If liveness + explicit selection proves insufficient on device, use a pinned mature arm64/iOS instrumentation backend; do not invent a fixed-size ARM64 trampoline.

## Immediate device checklist

1. Re-test the exact method name that worked before M4.4.1 and then failed in M4.4.1.
2. Test once by visible `搜索`, once by keyboard Search; candidate sets should match.
3. Do not touch Assembly picker first; `Assembly-CSharp · 优先` should still find a method located in another loaded Assembly because default scope is global.
4. Explicitly choose an Assembly; then verify results are strictly scoped to it.
5. Regress bare HEX / `0x` / `rva:` / `va:` reverse lookup.
6. Regress Patch Offset bare HEX -> `0x` normalization.
7. Regress supported and unsupported `/1` UI, common Unity structs, M4.4 instance selection and M4 `/0` create/test/generated-binary.

## Next engineering action

Do not expand `/2+` or add receiver inline-hook capture before M4.4.2 real-device search evidence. The first acceptance gate is the exact previously regressed query: it must work through both Search triggers again.
