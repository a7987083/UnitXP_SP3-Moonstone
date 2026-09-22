# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.4-instance-resolver-v2`
- CI validated head: `21775c3e0320399784a5a5b87131ab96cb9a80d5`
- Stage: `M4.4 Instance Resolver V2 — M4.3 liveness resolver + explicit multi-instance selection`
- Final CI run: `35751669688` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.4-InstanceResolver-V2`
- Artifact ID: `10704773628`
- ZIP SHA256: `798661433fca94d5ee256746b1c37091b0246d24175a206a47bfda0e48ea123d`
- Dylib: `ZonoPatch_v0.5.8_M4.4_InstanceResolver_V2.dylib`
- Dylib size: `1002176`
- Dylib SHA256: `30fc5f2c584931dcfced0b2e321e821a4b2c3f9d7476f014143d9b6fa31adeea`
- Current validation boundary: source + CI + binary verified; M4.1–M4.4 additions still require physical-device acceptance.

## Baselines that must not regress

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`.
- Method Finder V3 M2.2 device-accepted product: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1 CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`; user device-confirmed `/0` create/test/generated-binary paths.
- M4.1 UI/UX V2 CI head: `911dec0c56234387820fbec5daf996e396f86294`.
- M4.2 Typed Args UI V1 CI head: `e7c81172b04e162f74b3652048dcaf499d753aa4`.
- M4.3 Instance Resolver V1 final CI head: `a5688b3f42f53aa50366f349813be069ef0e5418`, run `35750846250` success.

## Stable architecture constraints

- Exact dyld image identity and Offset Resolver V2 behavior stay unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- `/1` text argument still uses the existing Runtime Action string pool via `ZNRuntimeActionFlagArgument0Text + reserved[0]`.
- Raw `Il2CppObject *` addresses must never be serialized into generated binaries.

## Implemented inheritance

### M4.1 UI/UX V2

- Automatic binary target: UnityFramework first, main executable fallback.
- App Libraries picker; displayed module names only, no install-UUID path persistence.
- Outside-panel touch passthrough layer.
- Same-page scroll preservation.
- Direct build performs required preflight internally.
- Runtime Method Call title editing is independent from method identity.

### M4.2 Typed Arguments UI V1

- `/0` path retained.
- Typed `/1` static invoke for bool, signed/unsigned 32/64, float, double, primitive-backed enum and `System.String`.
- ABI is resolved from IL2CPP metadata before invoke; unsupported ref/out/pointer/object/struct/generic paths fail closed.
- Dynamic `[全部] [0] [1] ...` filter only shows arities present in the returned candidate set.
- Result cards hide Namespace/RVA; Details retains full metadata.
- `/1` value persists into Runtime Action string pool and can be edited in Builder.
- `/2+` stays visible/filterable but not executable.

## Implemented — M4.3 Instance Resolver V1 / Finder UX

- Search page Assembly picker with `Assembly-CSharp` default and `全部 Assembly` option.
- Search maximum result count is user-editable; backend and UI hard maximum are `1024` instead of `64`.
- `/1` parameter input moved below method/class rows so long method names remain readable.
- Argument/result-limit input return action is `完成` and dismisses the keyboard.
- Detail page no longer duplicates Runtime test/create controls; those actions live in the result card.
- When one Assembly is selected on the search page, the result card suppresses the redundant Assembly label; all-Assembly search keeps it for disambiguation.
- Instance Resolver V1 enumerates live class instances through IL2CPP liveness APIs.
- Legacy `calculation_begin/end` is preferred when available.
- Modern `allocate_struct/finalize/free` fallback requires `stop_gc_world/start_gc_world` sequencing.
- Exactly one live instance can be automatically supplied as `this` for instance `/0` or `/1` invocation.
- M4.3 final CI run `35750846250`: success.

## Implemented — M4.4 Instance Resolver V2

- Adds a process-session instance selection store keyed by `assembly|namespace|class`.
- Selected addresses are validated through `il2cpp_object_get_class` + `il2cpp_class_is_assignable_from` before reuse.
- Invalid/stale selection is cleared instead of being invoked.
- Finder `测试执行` now detects instance methods before execution.
- If liveness returns one instance, it is auto-selected and execution continues.
- If liveness returns multiple instances, the UI presents an explicit `选择实例` action sheet rather than returning `FAILED_INSTANCE_AMBIGUOUS` immediately.
- Runtime Action public `执行` uses the same selected class instance within the current process.
- Selection is deliberately not persisted to generated Runtime Action data because object addresses are launch-specific.
- First M4.4 CI run `35751621067` failed at compile because the selection category header did not directly import the resolver interface; fixed at `21775c3e...`.
- Final M4.4 CI run `35751669688`: source assertions, arm64 build, binary verify and artifact upload all passed.
- Independent artifact verification confirmed thin arm64 dylib and matching ZIP/dylib SHA256 values above.

## Not implemented yet

### Receiver/`this` capture fallback

Status: `NEXT AFTER DEVICE FEEDBACK`

Liveness enumeration can still be ambiguous or return no suitable instance. A receiver-capture fallback should observe the target native method when the game naturally calls it and capture/validate the real ARM64 receiver (`x0`).

Do **not** implement a home-grown fixed-size ARM64 trampoline. The repository currently has no arbitrary-address hook backend. If this path is needed after device tests, use a pinned mature arm64/iOS instrumentation backend and keep capture temporary/removable.

### `/2+` typed invoke

Keep using one ABI-driven marshaling loop when expanded; do not create separate hard-coded `/2`, `/3`, etc. engines. Complex Unity structs such as Vector2/Vector3/Quaternion require explicit ABI-aware editors and storage.

## Immediate physical-device acceptance

1. Regress M4.1 touch passthrough, Translate, binary picker, scroll preservation, title editing and direct-build preflight.
2. Verify M4.3 Assembly picker and custom result count (`64`, `128`, `256`, etc.).
3. Confirm selected-Assembly result cards do not repeat `Assembly-CSharp`; all-Assembly results still identify their Assembly.
4. Confirm `/1` input is below the method name and keyboard `完成` dismisses correctly.
5. Test a safe static `/1` primitive method to retain M4.2 regression evidence.
6. Test a safe instance `/0` or `/1` whose class has exactly one live object; confirm automatic instance resolution and invoke.
7. Test a class with multiple live objects; confirm `选择实例` appears, selection executes the requested instance, and later actions reuse it in the same process.
8. Force an object lifecycle change if practical; stale selection must fail validation/clear instead of calling the old pointer.
9. Regress M4 V1 `/0` create/test/generated-binary paths.

## Promotion rule

Do not mark M4.3 or M4.4 device-verified from CI alone. Promote only after explicit physical-device evidence for the tested path, and record that evidence in all five long-term files.
