# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.0-managed-return-chaining-v1`
- CI-validated product source head: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`
- Stage: `M5.0 Managed-reference Return Chaining V1`
- Final product CI run: `35927940785` — `success`
- Artifact: `ZonoPatch-v0.5.8-M5.0-Managed-Return-Chaining-V1`
- Artifact ID: `10779609055`
- Artifact ZIP size: `563220`
- Artifact digest: `sha256:31d49ef89513677ce8b566f066c679f45010ee4905af062fa3216f9190a396fe`
- Dylib: `ZonoPatch_v0.5.8_M5.0_Managed_Return_Chaining_V1.dylib`
- Dylib size: `1254432`
- Dylib SHA256: `a75e30a9400bafdf7bfcf8e59c65a7f651a422522cd5e1d529f84eb06b4e9cd7`
- Validation boundary: source + CI + binary + downloaded artifact hash verified; physical-device M5.0 acceptance pending.

## Baselines that must not regress

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`.
- Method Finder V3 M2.2 device-accepted: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`; user device-confirmed `/0` create/test/generated-binary.
- M4.4.2 Search Restore: `fe8655444420bc9445ee741e2d3c4cffbaead066`.
- M4.5 Owning Method V1 CI head: `fa2f9db21b507da64feb6ffe0acc6a29d71aff2e`.
- M4.7 receiver + multi-arg stable head: `0bc5909b1714aa49002c758dc3c88f945da2adf3`.
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
- A chained object is injected only after existing instance validation proves compatibility with the target action class.

## Implemented inheritance

### M4.7 Receiver + Multi-Arg

- runtime receiver capture for proven paths;
- `/2-/8` Generic Invoke primitive/string/common supported ABI path;
- exact full-signature resolution when available.

### M4.8 Return Capture

- explicit `il2cpp_runtime_invoke` result decoding;
- object reference, bool, integer, float/double, pointer and raw complex value-type reporting;
- user device-positive evidence for explicit `System.Int32` return decode;
- natural game-call return capture remains unimplemented.

### M4.9 Generic Invoke + Runtime Editable Args

- generated Runtime Method Actions render an `执行` surface;
- `/1-/8` Runtime execution can edit arguments before one-shot invoke;
- same method/signature may author multiple Runtime buttons;
- button identity is independent from method identity.

## Implemented — M5.0 Managed-reference Return Chaining V1

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

- only non-null `managed reference / GPR64` returns enter the chain;
- strong non-pinned `il2cpp_gchandle_new` is preferred;
- `il2cpp_gchandle_get_target` refreshes the current object address before reuse;
- stripped/older targets without a complete GCHandle export set retain a process-session raw fallback, but validation still gates injection;
- previous selected receiver receives a temporary keepalive handle before chain injection and is restored after the call;
- incompatible chained objects are ignored and existing receiver resolution remains unchanged;
- no Runtime Action or Static Patch ABI bump.

## Current validation boundary

M5.0 is **CI/binary verified but not device-verified**.

Required physical-device evidence:

1. Execute a Runtime method returning a non-null managed object reference.
2. Confirm `[m5.0-chain] captured ...`.
3. Execute an instance method whose declaring class is compatible with that object.
4. Confirm `[m5.0-chain] receiver injected ...` and that the method acts on the returned object.
5. Verify an incompatible next method does not consume the chain.
6. Verify primitive return (`System.Int32`, etc.) does not create/replace the managed chain.
7. Verify a previously manually selected receiver is restored afterward.
8. Regress M4.9 Runtime buttons/editable args, M4.8 return display, M4.7 receiver/multi-arg and M4 `/0` generated-binary path.

## Next planned engineering stage

After M5.0 device acceptance:

### M5.1 Object / Collection Inspector foundation

- consume chained managed object as inspection root;
- inspect runtime class and fields;
- decode System.String / primitive / enum fields;
- recursive depth/cycle guard;
- Array/List/Dictionary recognition.

### M5.2 Collection export

- Array/List/Dictionary traversal;
- JSON/TXT export;
- per-element runtime type/address metadata;
- cycle detection and element limits.

### Later

- natural-call full tuple: receiver + args + return;
- Address -> Object containment/back-reference resolver;
- Runtime tuple -> offset/patch correlation;
- complex ValueType metadata-driven marshaling;
- ref/out support where ABI-safe.
