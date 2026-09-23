# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.0-managed-return-chaining-v1`
- Current source head: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`
- Stage: `M5.0 Managed-reference Return Chaining V1`
- CI workflow: `Build Runtime Patch Menu v0.5.8 M5.0 Managed Return Chaining V1`
- Current CI run: `35927940785`
- Validation boundary: source implemented; CI/build/binary verification running; physical-device acceptance pending.

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
- M4.5 Owning Method V1 CI head: `fa2f9db21b507da64feb6ffe0acc6a29d71aff2e`.
- M4.6 Full Signature / later M4.6.x stability layers must remain intact.
- M4.7 receiver + multi-arg stable product head: `0bc5909b1714aa49002c758dc3c88f945da2adf3`.
- M4.8 Return Capture hotfix head: `7cbc583f65f49eeb3b4a6fd64181046ea10c08c0`.
- M4.9 Runtime Editable Args / duplicate-button fixes are inherited by M5.0.

## Stable architecture constraints

- Exact dyld image identity and Offset Resolver V2 remain unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- Raw `Il2CppObject *` addresses are never serialized into generated Runtime Action data.
- Managed-reference chaining is process-session only.
- Only IL2CPP managed-reference return values are chainable; boxed primitive/value-type returns are never treated as receivers.
- A chained object is only injected when existing instance validation proves compatibility with the target action class.

## Implemented inheritance

### M4.7 Receiver + Multi-Arg

- Runtime receiver capture for proven paths.
- `/2-/8` Generic Invoke primitive/string/common supported ABI path.
- Exact full-signature resolution used when available.

### M4.8 Return Capture

- `il2cpp_runtime_invoke` result decoding.
- object reference, bool, integer, float/double, pointer and raw complex value-type reporting.
- device-positive evidence exists for explicit `System.Int32` return decoding.
- natural game-call return capture is still not implemented.

### M4.9 Generic Invoke + Runtime Editable Args

- generated Runtime Method Actions render their own `执行` surface.
- `/1-/8` Runtime execution can edit arguments before one-shot invoke.
- same method/signature may author multiple Runtime buttons.
- button identity is independent from method identity.

## Implemented — M5.0 Managed-reference Return Chaining V1

Flow:

```text
Runtime Action A
  -> il2cpp_runtime_invoke
  -> M4.8 decodes return ABI
  -> returnKind == managed reference
  -> M5.0 retains object with GCHandle
  -> Runtime Action B starts
  -> validate chained object against B target class
  -> compatible: temporarily use chained object as receiver
  -> invoke B
  -> restore previous explicit receiver selection
  -> if B returns another managed reference, chain advances
```

Implementation rules:

- only non-null `managed reference / GPR64` return values enter the chain;
- strong non-pinned `il2cpp_gchandle_new` is preferred;
- `il2cpp_gchandle_get_target` resolves the current address before reuse;
- stripped/older targets without all GCHandle exports retain a process-lifetime raw fallback, but validation still runs before injection;
- previous selected receiver gets a temporary keepalive handle before temporary chain injection, then is restored after the call;
- incompatible chained objects are ignored and the existing receiver resolver continues unchanged;
- no generated-binary ABI bump.

## Current validation boundary

M5.0 is **not device-verified yet**. CI success alone must not be promoted to device acceptance.

Required device evidence:

1. Execute a Runtime method that returns a non-null managed object reference.
2. Confirm log contains `[m5.0-chain] captured ...`.
3. Execute an instance method whose declaring class is compatible with that returned object.
4. Confirm log contains `[m5.0-chain] receiver injected ...` and the method acts on the returned object.
5. Verify an incompatible next method does not consume the chain and falls back to normal receiver selection.
6. Verify primitive return (`System.Int32`, etc.) does not create a chain.
7. Verify an existing manually selected receiver is restored after a chained call.
8. Regress M4.9 Runtime buttons, editable args, M4.8 return display, M4.7 receiver/multi-arg and M4 `/0` generated-binary path.

## Next planned engineering stage

After M5.0 device acceptance:

### M5.1 Object / Collection Inspector foundation

- consume chained managed object directly;
- inspect runtime class and fields;
- decode System.String / primitive / enum fields;
- recursive depth guard;
- Array/List/Dictionary recognition.

### M5.2 Collection export

- array/list/dictionary traversal;
- JSON/TXT export;
- per-element runtime type/address metadata;
- cycle detection and element limits.

### Later

- natural-call full tuple: receiver + args + return;
- Address -> Object containment/back-reference resolver;
- Runtime tuple -> offset/patch correlation;
- complex ValueType metadata-driven marshaling;
- ref/out support where ABI-safe.
