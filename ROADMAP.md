# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.3.1-instance-resolver-polish-v1`
- Runtime product source head: `7e34d4edd905ea8de1328323ae39143b98601fba`
- CI validated branch head: `f702e27bb0f138b6f54f4f6460c3307807c215b9`
- Stage: `M4.3.1 Instance Resolver Polish V1`
- CI run: `35751054253` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.3.1-InstanceResolverPolish-V1`
- Artifact ID: `10705387042`
- Artifact ZIP SHA256: `698923e8cd03228fa86a3fc9920c4c6fae6363cbd5668bf82e42488c16459a84`
- Dylib: `ZonoPatch_v0.5.8_M4.3.1_InstanceResolverPolish_V1.dylib`
- Dylib size: `985472`
- Dylib SHA256: `04384aaadeb9a21ba8b494bfb9d2adf4ac201e5125f2d79a7ae5acefd66574dd`
- Current device validation: `PENDING` for M4.1 UX, M4.2 typed `/1`, and all new M4.3/M4.3.1 instance-resolution/search behavior.

## Baselines

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not rewrite.
- Method Finder V3 M2.2 device-accepted product: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1 device evidence: CI head `d53c75dfbb7510e31a60e49f202532ad2f5e099e`; user confirmed `/0` create/test/generated-binary paths.
- M4.1 UI/UX V2 CI head: `911dec0c56234387820fbec5daf996e396f86294`.
- M4.2 Typed Args CI head: `e7c81172b04e162f74b3652048dcaf499d753aa4`.
- M4.3 Instance Resolver V1 CI head: `3618dee3a1669b1709ecb39627b3cabf7e8b5e8b`.

## Stable architecture constraints

- Exact dyld image identity and Offset Resolver V2 behavior remain unchanged.
- `ZN44StaticEntry == 128` bytes.
- Runtime Action remains independent from Static Patch ABI.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- `/1` argument persistence continues to use `ZNRuntimeActionFlagArgument0Text + reserved[0]` and the existing string pool.
- `/2+`, complex structs, ref/out, pointer and ordinary object parameters continue to fail closed.

## Implemented — M4.1 UI/UX V2

- Automatic binary target: prefer `UnityFramework`, otherwise main executable.
- `其他 -> 二进制` picker instead of mandatory manual input.
- Menu outside-panel touch passthrough layer.
- Same-page scroll preservation.
- Direct build runs required preflight internally; manual `读取验证` is optional.
- Runtime Method Call display title editable independently from method identity.
- App Libraries compact display shows only the final module name.

## Implemented — M4.2 Typed Arguments UI V1

- Dynamic arity filter: `全部` plus only arities present in the current returned candidate set.
- Compact results hide Namespace/RVA; full metadata remains in Details.
- `/1` inline argument input and direct `测试执行` / `创建方法`.
- Supported `/1` primitive ABI: bool, signed/unsigned 32/64, float, double, enum primitive ABI and `System.String`.
- `System.String` through `il2cpp_string_new`; invoke through `il2cpp_runtime_invoke`.
- Runtime Action persists one argument value without changing the 64-byte Runtime Method Call entry.

## Implemented — M4.3 / M4.3.1

### Assembly/search UX

- Search page has an Assembly picker using the same action-sheet interaction model as App Libraries.
- Default Assembly is `Assembly-CSharp`; `全部 Assembly` remains available.
- Search is scoped to the selected Assembly without requiring manual `Assembly!Method` text.
- Maximum search result count is user-editable, range `1–1024`; backend hard limit is also `1024`, so values above 64 are real rather than cosmetic.
- Search remains subject to the existing wall-clock budget; a high limit does not guarantee that many candidates if the time budget is reached first.

### Result cards

- `/0`: Method/arity + Class + direct test/create.
- `/1`: Method/arity + Class + argument input on a separate lower row + direct test/create.
- Result cards do **not** display Assembly, Namespace or RVA; Assembly remains part of candidate identity and is still visible in Details.
- `/1` input uses a keyboard with `Done`; `Done` dismisses the keyboard instead of inserting a newline.
- Details no longer adds a duplicate Runtime Method Call test/create panel; it is information-only for this workflow.

### Instance Resolver V1

- Non-static `/0` and `/1` methods can execute only when exactly one live instance of the target Class is resolved.
- Preferred path matches current `frida-il2cpp-bridge gc.choose()` behavior: legacy `il2cpp_unity_liveness_calculation_begin -> from_statics -> end` when available.
- Fallback path uses `allocate_struct -> from_statics -> finalize -> free_struct`, wrapped by `il2cpp_stop_gc_world` / `il2cpp_start_gc_world`.
- If available, returned objects are revalidated through `il2cpp_object_get_class` and `il2cpp_class_is_assignable_from`.
- Zero instances fail closed.
- Multiple instances fail closed with `FAILED_INSTANCE_AMBIGUOUS`; M4.3.1 never guesses which object is correct.

## CI gate — M4.3.1 passed

Workflow: `Build Runtime Patch Menu v0.5.8 M4.3.1 Instance Resolver Polish V1`

Run `35751054253` passed:

- Checkout;
- source contract assertions;
- dependency/Theos install;
- arm64 compile/link/sign;
- binary verification;
- artifact upload.

Independent artifact verification confirms:

- ZIP SHA256: `698923e8cd03228fa86a3fc9920c4c6fae6363cbd5668bf82e42488c16459a84`.
- Dylib: thin arm64 Mach-O, `985472` bytes.
- Dylib SHA256: `04384aaadeb9a21ba8b494bfb9d2adf4ac201e5125f2d79a7ae5acefd66574dd`.
- Binary markers include `[m4.3.1-ui]`, `[instance-resolver]`, `il2cpp_stop_gc_world`, `il2cpp_start_gc_world`, `znm43_testCandidate:`, `znm43_createCandidate:`.

## Next — physical-device acceptance

Status: `NEXT`

1. Regress M4.1 touch passthrough, Translate, binary picker, scroll preservation, title editing and direct-build preflight.
2. Verify Assembly picker changes the actual search scope.
3. Set maximum results above 64 (for example 128/256), search a broad safe method name and confirm the returned limit is no longer clamped to 64.
4. Verify `[全部] [0] [1] ...` only shows arities present in returned candidates.
5. Verify result cards hide Assembly/Namespace/RVA and Details still shows all three.
6. Verify `/1` input is below Method/Class and keyboard `Done` dismisses correctly.
7. Test one known safe static `/1` primitive method.
8. Test one safe instance `/0` or `/1` method where exactly one live instance exists; record resolver diagnostics and result.
9. Test zero-instance and multi-instance targets; both must fail closed and must not crash.
10. Regress M4 V1 `/0` create/test/generated-binary behavior.

## After acceptance

- If unique-instance invoke passes, add an explicit instance-selection / runtime-capture workflow for Classes with multiple live objects before attempting automatic selection.
- Extend the ABI-driven marshaler to `/2+` only after M4.3.1 device evidence; do not create separate hard-coded `/2`, `/3`, etc. engines.
- Vector2/Vector3/Quaternion/custom structs require dedicated ABI-aware editors/serialization.
