# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.0 Managed-reference Return Chaining V1** on top of M4.9 Generic Invoke + Runtime Editable Args + M4.8 Return Capture + M4.7 Receiver/Multi-Arg.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.0-managed-return-chaining-v1`
- CI-validated product source head: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`
- Final product CI run: `35927940785` — success
- Job: `107407405755`
- Artifact: `ZonoPatch-v0.5.8-M5.0-Managed-Return-Chaining-V1`
- Artifact ID: `10779609055`
- Artifact digest: `sha256:31d49ef89513677ce8b566f066c679f45010ee4905af062fa3216f9190a396fe`
- Dylib: `ZonoPatch_v0.5.8_M5.0_Managed_Return_Chaining_V1.dylib`
- Dylib size: `1254432`
- Dylib SHA256: `a75e30a9400bafdf7bfcf8e59c65a7f651a422522cd5e1d529f84eb06b4e9cd7`
- Source/CI/Binary/Artifact hash: VERIFIED
- Physical-device M5.0 acceptance: PENDING

## Validation boundary

Do not conflate source, CI, binary and device verification.

Inherited device evidence:

- M4 Runtime Method Call V1: `/0` create/test/generated-binary usable.
- M4.7: receiver capture produced a stable live instance in user testing.
- M4.8: explicit Runtime Invoke `System.Int32` return decode displayed the real value (`1`) while raw remained the boxed object pointer.

M5.0 itself has no physical-device acceptance yet.

## What M5.0 does

```text
Action A
 -> il2cpp_runtime_invoke
 -> M4.8 return metadata
 -> managed reference + non-null
 -> M5.0 GCHandle retain

Action B
 -> get latest chained target
 -> validate target against B declaring class
 -> compatible: temporary receiver injection
 -> execute B
 -> restore prior selected receiver
 -> capture B managed-reference return if present
```

### Lifetime model

- preferred: strong non-pinned `il2cpp_gchandle_new`;
- reuse: `il2cpp_gchandle_get_target` refreshes moving-GC address;
- replacement: old chain handle is freed when a new managed return is captured;
- stripped target fallback: raw process-session address only when all GCHandle exports are unavailable; class validation still gates use;
- receiver selected before temporary chaining gets a separate temporary keepalive handle, then is restored after the chained call.

### Compatibility model

M5.0 never injects an arbitrary returned object blindly. Before use it validates against:

```text
Assembly + Namespace + Class
```

If validation fails, M5.0 does nothing and the existing M4.x instance resolver/selection path remains responsible for `this`.

## Important scope boundaries

- Chaining currently applies only to **explicit Runtime Invoke** results decoded by M4.8.
- Natural game-call return capture is not implemented.
- primitive and boxed ValueType returns are not chain receivers.
- complex struct/value-type chaining is not implemented.
- ref/out receiver chaining is not implemented.
- raw managed object pointer is never persisted to generated Runtime Action storage.
- chain is process-session only.

## M4.9 behavior inherited and must not regress

- generated Runtime Method Actions visibly render an `执行` button;
- `/1-/8` execution opens an argument editor populated from saved values;
- editing is one-shot and does not require recreating the button;
- same method/signature can create multiple Runtime buttons;
- button/action identity is independent from method identity;
- M4.8 return display remains available after invoke.

## Architecture invariants

- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI version remains unchanged.
- Static Patch ABI remains unchanged.
- Dobby is statically linked with no external Dobby dylib dependency.
- exact image/RVA behavior from Offset Resolver V2 remains unchanged.

## Files added/changed for M5.0

- `iosruntimepatchmenu/src/ZNM50ManagedReturnChaining.mm`
- `iosruntimepatchmenu/src/ZNIL2CPPMethodFinderMenuBinding.mm`
- `iosruntimepatchmenu/Makefile`
- `iosruntimepatchmenu/src/ZNBuildVersion.h`
- `.github/workflows/build-runtime-patch-menu-v0.5.8-m5.0-managed-return-chaining-v1.yml`

## Device checklist

1. Use a method that returns a known class/object reference, not a primitive.
2. Execute it through Runtime Invoke.
3. Confirm M4.8 return UI still displays the result.
4. Check log for `[m5.0-chain] captured ...`.
5. Execute an instance method belonging to that returned object's class or compatible base class.
6. Check log for `[m5.0-chain] receiver injected ...`.
7. Verify the second call acts on/reads the returned object.
8. Execute an incompatible class method and confirm chain is not injected.
9. Execute a primitive-return method and confirm it does not replace the managed-reference chain.
10. If a manual receiver was selected before chaining, confirm it is restored afterward.
11. Regress M4.9 Runtime `执行` button and editable args.
12. Regress M4 `/0` generated-binary path.

## Next engineering action

After M5.0 physical-device acceptance, proceed to Object/Collection Inspector using the retained managed object as the first inspection root. Array/List/Dictionary traversal and JSON export should be layered after object/class/field inspection is stable.
