# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.4 Instance Resolver V2 on top of M4.3 Finder/Instance Resolver + M4.2 typed `/1` + M4.1 UX + Offset Resolver V2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.4-instance-resolver-v2`
- CI validated product head: `21775c3e0320399784a5a5b87131ab96cb9a80d5`
- Final CI run: `35751669688` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.4-InstanceResolver-V2`
- Artifact ID: `10704773628`
- ZIP SHA256: `798661433fca94d5ee256746b1c37091b0246d24175a206a47bfda0e48ea123d`
- Dylib: `ZonoPatch_v0.5.8_M4.4_InstanceResolver_V2.dylib`
- Dylib size: `1002176`
- Dylib SHA256: `30fc5f2c584931dcfced0b2e321e821a4b2c3f9d7476f014143d9b6fa31adeea`
- Format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device verification.

### Device-verified predecessor only

M4 Runtime Method Call V1 has explicit user device evidence for:

- `/0` 创建方法；
- `/0` 测试执行；
- generated binary usable.

This is not a full regression pass.

### Current M4.4 state

- source implemented: YES;
- committed to GitHub: YES;
- arm64 CI compile/link/sign: YES;
- binary verification: YES;
- artifact upload + independent hash check: YES;
- M4.1 new UX device validation: PENDING;
- M4.2 `/1` typed invoke device validation: PENDING;
- M4.3 liveness instance resolution device validation: PENDING;
- M4.4 multi-instance selection device validation: PENDING;
- receiver/`this` hook capture backend: NOT IMPLEMENTED;
- full regression: NO.

## Architecture invariants

- Offset Resolver V2 exact image identity/canonical RVA behavior stays unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- `/1` text argument still uses existing string pool + `ZNRuntimeActionFlagArgument0Text / reserved[0]`.
- Do not persist `/var/containers/Bundle/Application/<UUID>/...` paths.
- Do not persist raw `Il2CppObject *` addresses in generated Runtime Actions; instance pointers are launch/session-specific.

## Current Finder UX

Search page:

```text
方法名      [ SetSpeed____________ ]   [搜索]
Assembly    [ Assembly-CSharp      › ]
最大结果    [ 128 ]
```

Rules:

- Assembly is selectable via action sheet; default `Assembly-CSharp`; `全部 Assembly` is available.
- Max result count is user-editable with hard max `1024`.
- Search result arity filter dynamically shows `全部` plus only arities actually present.
- Selected single Assembly is not repeated on every result card; all-Assembly searches retain Assembly labels for disambiguation.
- Compact results hide Namespace and RVA; Details retains full metadata.
- Details no longer duplicates Runtime test/create controls.

Current `/1` card shape:

```text
SetSpeed/1                 测试执行
Player                     创建方法
[ 2.5 ]
```

- input sits below the method/Class rows so the method name gets maximum width;
- input return key is `完成` and dismisses keyboard;
- `/2+` remains visible/filterable but not executable.

## M4.2 typed argument behavior

Supported explicit argument counts: `/0`, `/1`.

Supported first-stage `/1` kinds:

- bool;
- signed/unsigned 32-bit integer;
- signed/unsigned 64-bit integer;
- float/double;
- enum backed by supported primitive ABI;
- `System.String` via `il2cpp_string_new`.

Unsupported/fail-closed explicit argument types still include `/2+`, ref/out, pointer, ordinary object reference, complex struct/value type, unknown ABI and generic definition.

## M4.3 Instance Resolver V1

Core file: `ZNIL2CPPInstanceResolver.mm`.

Behavior:

- resolve Assembly/Namespace/Class to IL2CPP Class;
- enumerate liveness candidates for that Class;
- prefer legacy `il2cpp_unity_liveness_calculation_begin/from_statics/end`;
- modern fallback uses `allocate_struct/from_statics/finalize/free_struct` with `stop_gc_world/start_gc_world`;
- validate candidate Class through `il2cpp_object_get_class` + `il2cpp_class_is_assignable_from`;
- exactly one candidate can be auto-used as the instance `this` for `/0` or `/1` Runtime Invoke;
- zero candidates fail closed;
- M4.3 V1 originally failed closed on multiple candidates.

Final M4.3 CI run: `35750846250` — success, head `a5688b3f42f53aa50366f349813be069ef0e5418`.

## M4.4 Instance Resolver V2

New files:

- `ZNIL2CPPInstanceSelectionV2.h/.mm`
- `ZNInstanceSelectionV2UI.mm`

Behavior:

- explicit process-session instance selection store keyed by `assembly|namespace|class`;
- previously-selected object is validated before reuse;
- invalid/stale selection is cleared;
- Finder `测试执行` wraps M4.3: one instance auto-selects, multiple instances open an explicit selection action sheet;
- public Runtime Action `执行` uses the same class selection in the current process;
- no raw object pointer is serialized to binary;
- if the process restarts, instance selection is intentionally resolved again.

M4.4 first CI run `35751621067` failed only at compile because the category header did not directly import `ZNIL2CPPInstanceResolver.h`. The header was corrected in `21775c3e...`.

M4.4 final run `35751669688` passed Source Contract, arm64 Build, Binary Verify and Artifact Upload.

Independent downloaded-binary verification confirmed:

```text
Mach-O 64-bit arm64 dynamically linked shared library
ZIP SHA256   798661433fca94d5ee256746b1c37091b0246d24175a206a47bfda0e48ea123d
Dylib SHA256 30fc5f2c584931dcfced0b2e321e821a4b2c3f9d7476f014143d9b6fa31adeea
```

Expected binary markers include `[instance-resolver]`, `[instance-selection-v2]`, `selected-session-instance`, `znm44_testCandidate:` and `znm44_executeAction:`.

## Receiver capture boundary

`receiver/this` capture through temporary native-method instrumentation is **not implemented in M4.4 V2 yet**.

Reason: this repository currently has no proven arbitrary-address ARM64 inline-hook backend. Do not invent a fixed-size ARM64 trampoline; method prologues may contain PC-relative instructions and relocation requirements.

If liveness + explicit selection does not solve real-device ambiguity, next capture stage should use a pinned mature arm64/iOS instrumentation backend, capture `x0`, validate it against the expected IL2CPP Class, then immediately remove/disable the temporary probe.

## Immediate device checklist

1. Regress M4.1 touch passthrough, Translate, binary picker, scroll preservation and direct-build preflight.
2. Verify Assembly selector and custom max result count.
3. Verify selected-Assembly result cards no longer repeat `Assembly-CSharp`; all-Assembly search still identifies Assembly.
4. Confirm `/1` value field is below method name and `完成` closes the keyboard.
5. Regress a safe static `/1` method.
6. Test a safe instance `/0` or `/1` Class with one live instance — it should auto-resolve.
7. Test a Class with multiple live instances — a selection popup should appear instead of `FAILED_INSTANCE_AMBIGUOUS`.
8. Choose one instance, execute, then execute another method on the same Class and verify session selection is reused.
9. If object lifecycle changes, verify stale selection fails validation/clears instead of invoking an old address.
10. Regress the user-confirmed M4 `/0` create/test/generated-binary paths.

## Next engineering action

Do not move to `/2+` yet if instance behavior is still unclear on device. First collect M4.3/M4.4 real-device evidence. If liveness cannot identify the intended object reliably, implement temporary receiver capture with a mature pinned hook/instrumentation backend; only after instance resolution is stable should typed argument arity expand further.
