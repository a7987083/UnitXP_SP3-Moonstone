# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.3.1 Instance Resolver Polish V1 on top of M4.2 typed `/1`, M4.1 UX, Offset Resolver V2 and Runtime Method Call V1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.3.1-instance-resolver-polish-v1`
- Runtime product source head: `7e34d4edd905ea8de1328323ae39143b98601fba`
- CI validated head: `f702e27bb0f138b6f54f4f6460c3307807c215b9`
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`
- M4 V1 device-verified CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`
- M4.3.1 CI run: `35751054253` — success
- Artifact: `ZonoPatch-v0.5.8-M4.3.1-InstanceResolverPolish-V1`
- Artifact ID: `10705387042`
- ZIP SHA256: `698923e8cd03228fa86a3fc9920c4c6fae6363cbd5668bf82e42488c16459a84`
- Dylib: `ZonoPatch_v0.5.8_M4.3.1_InstanceResolverPolish_V1.dylib`
- Dylib size: `985472`
- Dylib SHA256: `04384aaadeb9a21ba8b494bfb9d2adf4ac201e5125f2d79a7ae5acefd66574dd`
- Dylib format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device validation.

### Device-verified predecessor

For `feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`, the user explicitly reported:

- `/0` `创建方法按钮` works on device;
- `/0` `测试执行` works on device;
- generated binary is usable on device.

Those paths are device-verified. M4.1, M4.2, M4.3 and M4.3.1 additions remain device-validation pending until the user explicitly reports them working.

### Current M4.3.1 state

- source implemented: YES;
- committed to GitHub: YES;
- arm64 CI compiled/linked/signed: YES;
- binary verified: YES;
- artifact produced and independently hash-checked: YES;
- physical-device verification: PENDING;
- full regression: NO.

## Architecture that must remain stable

### Offset Resolver V2

Do not rewrite while validating M4.3.1. CI continues to assert these stay unchanged relative to the Offset Resolver V2 baseline:

- `iosruntimepatchmenu/src/ZonoeRuntimeMenu.mm`
- `iosruntimepatchmenu/src/ZNOffsetResolverV2.mm`
- `iosruntimepatchmenu/src/ZNStaticPatchFormat.h`

### Binary ABIs

- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Actions remain separate from Static Patch ABI.
- `/1` saved argument still uses `ZNRuntimeActionFlagArgument0Text + reserved[0]` and the existing string pool.

## Current Method Finder UX

Search page:

```text
方法名      [ SetSpeed____________ ]   [搜索]
Assembly    [ Assembly-CSharp      › ]
最大结果    [ 128 ]
```

Rules:

- Assembly button opens an action-sheet list of current IL2CPP assemblies, matching the App Libraries picker interaction style.
- Default is `Assembly-CSharp`; `全部 Assembly` is available.
- Maximum result count is editable from `1` to `1024`; backend hard limit is also 1024.
- A large requested count is still subject to the existing search wall-clock budget.

Result page:

```text
[全部] [0] [1] [2] ...

SetSpeed/1                 测试执行
Player                     创建方法
[ 2.5 ]
```

Compact-result rules:

- Method/arity is visible.
- Class is visible.
- `/1` argument input is on its own lower row.
- Assembly is intentionally hidden here because it was selected on the previous page.
- Namespace and RVA are also hidden.
- Assembly/Namespace/RVA/VA/MethodInfo remain available in Details.
- Details no longer adds a duplicate Runtime test/create panel; test/create live on the result card.
- `/1` and maximum-result editors use `Done` to dismiss the keyboard.

## Typed argument scope

M4.3.1 inherits M4.2 typed `/1` behavior:

- `/0` and `/1` only;
- bool;
- signed/unsigned 32-bit integer;
- signed/unsigned 64-bit integer;
- float;
- double;
- enum when metadata resolves to a supported primitive ABI;
- `System.String` via `il2cpp_string_new`.

Still fail closed:

- `/2+`;
- ref/out;
- pointer;
- ordinary object-reference argument;
- complex value type / struct;
- unknown ABI;
- generic definition.

## Instance Resolver M4.3.1

For non-static `/0` and `/1` methods, the Invoke Engine asks `ZNIL2CPPInstanceResolver` for a live target object.

Resolution policy:

1. Resolve the exact Assembly/Namespace/Class.
2. Prefer legacy Unity liveness APIs when available:
   `il2cpp_unity_liveness_calculation_begin -> from_statics -> end`.
3. If legacy APIs are unavailable, use modern:
   `il2cpp_stop_gc_world -> allocate_struct -> from_statics -> finalize -> il2cpp_start_gc_world -> free_struct`.
4. When available, verify candidates using `il2cpp_object_get_class` and `il2cpp_class_is_assignable_from`.
5. Exactly one candidate: invoke with that object as `this`.
6. Zero candidates: fail closed.
7. More than one candidate: fail closed with `FAILED_INSTANCE_AMBIGUOUS`; never choose arbitrarily.

This implementation follows the same high-level liveness ordering used by current `frida-il2cpp-bridge gc.choose()` but is implemented natively in the dylib.

## CI evidence

Workflow: `Build Runtime Patch Menu v0.5.8 M4.3.1 Instance Resolver Polish V1`

Run `35751054253` — `success`.

Passed steps:

- Checkout
- Source contract assertions
- Install dependencies
- Install Theos
- Build M4.3.1 Instance Resolver Polish V1
- Verify binary
- Upload artifact

Independent artifact verification confirmed:

- ZIP SHA256 `698923e8cd03228fa86a3fc9920c4c6fae6363cbd5668bf82e42488c16459a84`;
- dylib SHA256 `04384aaadeb9a21ba8b494bfb9d2adf4ac201e5125f2d79a7ae5acefd66574dd`;
- thin arm64 Mach-O;
- strings include `[m4.3.1-ui]`, `[instance-resolver]`, `il2cpp_stop_gc_world`, `il2cpp_start_gc_world`, `znm43_testCandidate:`, `znm43_createCandidate:`.

## Immediate physical-device checklist

1. Regress M4.1 touch passthrough, Translate, App Libraries, scroll retention, title editing and direct build.
2. Open Assembly picker, select `Assembly-CSharp` and at least one other Assembly; verify search scope changes.
3. Enter a maximum result count above 64, such as 128/256; confirm the backend no longer clamps to 64.
4. Search a method with mixed arities and verify `[全部] [0] [1] ...` only contains arities present in the returned set.
5. Confirm result cards hide Assembly/Namespace/RVA but Details still shows them.
6. Confirm `/1` argument field sits under Method/Class and keyboard `Done` dismisses without a newline.
7. Test one safe static `/1` primitive method.
8. Test one safe instance `/0` or `/1` method where exactly one live object exists.
9. Test a class with zero live objects and a class with multiple live objects; both must fail closed without a crash.
10. Regress M4 V1 `/0` create/test/generated-binary paths.

## Next action after device feedback

- If unique-instance execution works, record exact method/Class/arity/result and resolver diagnostics in all five long-term files.
- If a target has multiple instances, the next feature should be explicit instance selection or short runtime receiver capture; do not auto-pick the first object.
- Do not extend to `/2+` until M4.3.1 instance and `/1` paths have real device evidence.
