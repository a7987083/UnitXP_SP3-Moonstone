# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M3.1 IL2CPP Signature / ABI + Return Override Foundation**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m3.1-il2cpp-abi-return-foundation`
- Sealed predecessor: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not modify
- Device-accepted M2.2 runtime baseline: `19b912c840e7223adbc2c26ef80185c32b8eb77a`
- M3.1 runtime product / CI validated source: `81a9cf9291bd95e300106e708e9dc492d74a778f`
- CI run: `34898345483` — success
- Artifact: `ZonoPatch-v0.5.8-M3.1-ABI-ReturnFoundation`
- Artifact ID: `10369996035`
- ZIP SHA256: `9938d7e7f061fd0d09e9690abdcdac616eb3af378bd99e5e2e5f4d242dd6c8ab`
- Dylib SHA256: `00e3aa4e3d638ba184c51f2b31c7374a172a12796b831b8b8a04c3cd73340079`
- Dylib size: `801376` bytes
- Validation: source assertions + Named Offset parser + ABI classifier + static protection tests + Theos arm64 compile/link/sign + binary verification passed; **device validation pending**.

Documentation commits after `81a9cf9...` do not change the delivered dylib. Always distinguish product source from later docs-only branch HEADs.

## Previous accepted baseline

M2.2 was installed on the real target and the user reported `目前没问题了。` Treat `19b912c...` as the current device-accepted runtime baseline. The report was aggregate rather than an itemized full regression, so `full_regression_verified` remains false.

Known Method Finder target:

`Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0`

Known device-verified RVA: `0x2DA9E10`.

Earlier proven behavior that M3.1 must not regress:

- V3 candidate list / detail / address-copy flow;
- qualified lookup and `0xRVA` reverse lookup;
- selected candidate -> Builder canonical expression;
- broad bare-name matching `exact > prefix > suffix > contains`;
- real-device broad query `cash`: first `423.1 ms`, second `147 ms`, later ~`150 ms`;
- Feature/Patch delete and generic Toggle/Number/Action/Slider authoring from M2.2.

## M3.1 implementation

New files:

- `iosruntimepatchmenu/src/ZNIL2CPPABIMetadata.h`
- `iosruntimepatchmenu/src/ZNIL2CPPABIMetadata.mm`
- `iosruntimepatchmenu/src/ZNIL2CPPABIDetailUI.mm`
- `iosruntimepatchmenu/tests/il2cpp_abi_classifier_test.mm`

Modified integration:

- `iosruntimepatchmenu/Makefile`
- `iosruntimepatchmenu/src/ZNIL2CPPMethodFinderMenuBinding.mm`

### Runtime metadata discovery

M3.1 dynamically resolves IL2CPP exports from loaded UnityFramework / `RTLD_DEFAULT`, including when available:

- `il2cpp_method_get_return_type`
- `il2cpp_method_get_param`
- `il2cpp_method_get_param_count`
- `il2cpp_method_get_param_name`
- `il2cpp_method_is_generic`
- `il2cpp_method_is_inflated`
- `il2cpp_method_is_instance`
- `il2cpp_type_get_name`
- pointer/byref helpers
- class-from-type / value-type / enum helpers
- `il2cpp_free`

The implementation fails closed when required signature exports are unavailable; it does not infer a safe hook ABI from the method name alone.

### ABI classes

M3.1 describes:

- void
- bool / GPR32
- signed <=32 / GPR32
- unsigned <=32 / GPR32
- signed64 / GPR64
- unsigned64 / GPR64
- float / FP32
- double / FP64
- raw pointer / GPR64
- managed reference / GPR64
- complex value type
- unknown

Enums are reduced through the enum base type when the required IL2CPP APIs are present.

### Conservative Return Override foundation

`ZNIL2CPPBuildReturnOverridePlan(...)` validates and normalizes a future override value but **does not apply it**.

Automatic foundation readiness is limited to conservative scalar/raw-pointer returns and requires a valid Method Pointer. It blocks:

- void;
- byref returns;
- managed object returns until GC/object-lifetime semantics are defined;
- complex struct/value-type returns;
- generic definitions;
- inflated/shared generic methods;
- unknown/unresolved ABI.

Generated plan explicitly says:

- `foundationOnly = YES`
- `applied = NO`
- `requiresHookBackend = YES`
- `backendState = pending-m3.2-hook-backend`

M3.1 installs **no Hook**, rewrites **no function entry**, and mutates **no target memory**.

The hidden MethodInfo native argument is deliberately recorded as an expectation requiring backend validation, not as a universal ABI fact.

## M3.1 detail UI

The existing V3 detail page is preserved and M3.1 appends an ABI card showing:

- managed signature;
- return managed type + ABI kind;
- instance/static state when available;
- generic/inflated state;
- parameter ABI summary;
- `Return Override: Foundation Ready` or `Blocked` with reason;
- `复制 ABI`.

The UI explicitly states this build does not install a hook.

## CI history / evidence

First M3.1 run `34897881824` failed in the standalone ABI test compile because the new header used invalid `FOUNDATION_EXPORT nullable ...` syntax. It was fixed to pointer `_Nullable` at product source `81a9cf9...`.

Second run `34898021121`:

- tests passed;
- full Theos compile/link/sign passed;
- verify stopped only on an unreliable Unicode `strings` assertion for the UI title.

No product-source change was made for that verifier issue. The workflow assertion was replaced with ASCII binary markers.

Final run `34898345483` passed:

- source assertions;
- Named Offset parser test;
- IL2CPP ABI classifier test;
- Static Payload Protection test;
- Static RVA Protection test;
- Theos arm64 compile/link/sign;
- API exports;
- M1/M2/M3.1 ASCII binary markers;
- one-constructor check (`__TEXT,__init_offsets == 4`);
- artifact upload.

Independent artifact verification matched GitHub:

- ZIP SHA256 `9938d7e7f061fd0d09e9690abdcdac616eb3af378bd99e5e2e5f4d242dd6c8ab`
- dylib SHA256 `00e3aa4e3d638ba184c51f2b31c7374a172a12796b831b8b8a04c3cd73340079`
- size `801376`
- thin arm64 Mach-O dylib
- `__TEXT,__init_offsets` size `4`
- markers present: `v3-candidate-list`, `m2-wide-index`, `pending-m3.2-hook-backend`, `expected-by-generated-IL2CPP-code`, `signed64 / GPR64`, `il2cpp_method_get_return_type`.

## CI routing

Feature-branch Actions registration previously produced synthetic `BuildFailed / startup_failure / 0 jobs`. Continue using the workflow registered on `main` with checkout pinned to the exact feature source SHA. Do not confuse the main workflow commit with product source.

## Next device acceptance

Install the M3.1 artifact and use the known target:

`Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0`

Expected acceptance work is to **observe**, not assume:

1. Confirm the normal M2.2 search/detail flow still works and RVA remains `0x2DA9E10`.
2. Confirm a new `IL2CPP Signature / ABI · M3.1` card appears.
3. Report the exact managed return type shown.
4. Report `instance` vs `static`.
5. Report `generic` / `inflated` values.
6. Confirm parameter list/count.
7. Report whether Return Override says `Foundation Ready` or `Blocked` and its exact reason.
8. Test `复制 ABI`.

Do not start M3.2 Hook/Return Override application until those runtime metadata values are confirmed on the real device.
