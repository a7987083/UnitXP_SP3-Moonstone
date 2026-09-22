# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.4.1 Hotfix on top of M4.4 multi-instance selection + M4.3 Finder/Instance Resolver + M4.2 typed `/1` + M4.1 UX + Offset Resolver V2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `fix/runtime-patch-menu-v0.5.8-m4.4.1-keyboard-search-route`
- CI validated product head: `0025556b8f3a2a20466b7344120ca82f9db7f921`
- Final CI run: `35789261862` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.4.1-Hotfix`
- Artifact ID: `10721074579`
- ZIP SHA256: `5008897e16957231938f03a7a663d72395c500ef00801ce23ccf306ed70d14ee`
- Dylib: `ZonoPatch_v0.5.8_M4.4.1_Hotfix.dylib`
- Dylib size: `1018832`
- Dylib SHA256: `2f41f35a1bce9e07af766d2026ca8a76a6e6bf3f1919940bcdad77b80cc51549`
- Format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device verification.

### Device-verified predecessor only

M4 Runtime Method Call V1 has explicit user device evidence for `/0` create, `/0` test execute and generated binary usable. This is not a full regression pass.

### Current M4.4.1 state

- source implemented: YES;
- committed to GitHub: YES;
- arm64 CI compile/link/sign: YES;
- binary verification: YES;
- artifact upload + independent hash check: YES;
- keyboard/button Search device validation: PENDING;
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

## Finder UX / search routing

Current search page:

```text
方法名      [ SetSpeed____________ ]   [搜索]
Assembly    [ Assembly-CSharp      › ]
最大结果    [ 128 ]
```

M4.4.1 fixes the previous split between the visible button and keyboard Return/Search. Both controls are rebound after rendering to:

```text
znm441_submitSearch:
```

That handler performs the same selected-Assembly scope, max-result handling, query normalization and V3 candidate search for either trigger.

### Accepted method/address input

Method-name forms continue to work normally. Address-like input is normalized as follows:

```text
38064A8       -> rva:0x38064A8
0x38064A8     -> rva:0x38064A8
rva:38064A8   -> rva:0x38064A8
rva:0x38064A8 -> rva:0x38064A8
va:0x...      -> loaded UnityFramework Runtime VA -> RVA -> reverse lookup
```

Address queries bypass the selected Assembly prefix and use the existing V3 reverse-RVA backend.

Bare HEX detection is intentionally address-like, not a general method-name transformation. If a real method identifier is ambiguous with a bare hex-looking token, use the explicit method identity or `rva:` prefix for addresses.

## Patch Offset normalization

The Patch validator already accepted both `0x...` and bare hexadecimal input. M4.4.1 makes the UI consistent:

```text
38064A8
```

on `完成` becomes:

```text
0x38064A8
```

The normalized text is written back into `ZNBinaryPatchWorkspace`; normal read/validate/build safety checks remain unchanged.

## `/1` behavior

Primitive/string support inherited from M4.2:

- bool;
- signed/unsigned 32-bit integer;
- signed/unsigned 64-bit integer;
- float/double;
- primitive-backed enum;
- `System.String`.

M4.4.1 additionally handles four exact Unity value types:

```text
Vector2      1,2
Vector3      1,2,3
Quaternion   0,0,0,1
Color        1,0,0,1
```

Comma, Chinese comma, semicolon and whitespace separators are accepted. The Runtime Action stores the source text as one `/1` value; invoke-time marshaling creates the corresponding float struct.

Unsupported `/1` inputs now retain a visible type/reason instead of only looking disabled. Ordinary object references, custom structs, ref/out and pointers are still intentionally fail closed.

## M4.3 / M4.4 instance behavior retained

- M4.3 enumerates live instances through IL2CPP liveness APIs and validates Class identity.
- One live instance can be auto-used as `this`.
- M4.4 adds process-session explicit selection for multiple same-Class instances.
- Selection key is `assembly|namespace|class`.
- Selected object is revalidated before reuse; stale selection is cleared.
- Raw object pointers are not serialized and are resolved again after restart.

## Build history

M4.4.1 first CI run `35789012451` failed at compile because the new translation unit did not have the V3 Search category declaration visible. No runtime conclusion was drawn from that run.

After exposing `ZNIL2CPPMethodFinderSearchV3.h`, product head `0025556b8f3a2a20466b7344120ca82f9db7f921` passed run `35789261862`:

```text
Source Contract  PASS
arm64 Build      PASS
Binary Verify    PASS
Artifact Upload  PASS
```

Independent downloaded artifact verification:

```text
Mach-O 64-bit arm64 dynamically linked shared library
ZIP SHA256   5008897e16957231938f03a7a663d72395c500ef00801ce23ccf306ed70d14ee
Dylib SHA256 2f41f35a1bce9e07af766d2026ca8a76a6e6bf3f1919940bcdad77b80cc51549
```

## Receiver capture boundary

`receiver/this` capture through temporary native-method instrumentation remains **not implemented**. If liveness + explicit selection proves insufficient on device, use a pinned mature arm64/iOS instrumentation backend; do not invent a fixed-size ARM64 trampoline.

## Immediate device checklist

1. Search the same method by visible `搜索` and keyboard Search; verify identical candidates with the same Assembly/max-result settings.
2. Reverse-lookup one known RVA using bare HEX, `0x`, `rva:` and explicit `rva:0x` forms.
3. If available, test a `va:` Runtime VA for the same method.
4. Enter a bare Patch Offset and press `完成`; verify automatic `0x` normalization followed by normal validation.
5. Check an unsupported `/1`; it should state the parameter type/reason.
6. Test safe `/1` Vector2/Vector3/Quaternion/Color methods if available, including create method and Builder persistence.
7. Regress primitive/string `/1`, unique instance resolution, multi-instance selection/reuse and stale-selection rejection.
8. Regress the user-confirmed M4 `/0` create/test/generated-binary paths and M4.1 UX.

## Next engineering action

Do not expand `/2+` or add an inline-hook receiver backend before M4.4.1 device evidence. First validate search routing, address normalization, Patch Offset normalization, common struct marshaling and M4.4 instance behavior on a real device.
