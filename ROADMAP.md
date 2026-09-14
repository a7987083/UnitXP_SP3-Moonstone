# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m3.1-il2cpp-abi-return-foundation`
- Stage: `M3.1 — IL2CPP Signature / ABI + Return Override Foundation`
- Device-accepted baseline: M2.2 runtime `19b912c840e7223adbc2c26ef80185c32b8eb77a`
- M3.1 product source: `81a9cf9291bd95e300106e708e9dc492d74a778f`
- CI run: `34898345483` — `success`
- Artifact ID: `10369996035`
- M3.1 validation: `CI/BINARY VERIFIED · DEVICE PENDING`

## Completed baselines

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a` — never modify directly.
- V2 Method Finder / zero-vmaddr: device verified.
- V3 M1 candidate/detail/RVA/Builder path: device verified.
- M2 broad search/index: device observed; `cash` first `423.1 ms`, repeat ~`147–150 ms`.
- M2.2 Builder delete + generic Toggle/Number/Action/Slider + stable cancel rendering: device accepted by aggregate user report.

## Implemented — M3.1

- Dynamic IL2CPP signature API discovery from UnityFramework.
- Managed return type + parameter type/name extraction.
- instance/static metadata when available.
- generic/inflated metadata when available.
- Primitive/raw-pointer ABI classes for ARM64 planning.
- Enum base-type reduction when runtime APIs permit it.
- Conservative guards for byref, managed object, complex value type, generic/inflated and unknown ABI.
- `ZNIL2CPPBuildReturnOverridePlan` data contract for the future hook backend.
- Detail-page ABI card with Copy ABI action.
- M3.1 never installs a hook and never mutates target memory.

## M3.1 validation gate

Run `34898345483` passed:

- source assertions;
- Named Offset parser test;
- IL2CPP ABI classifier test;
- static payload/RVA protection tests;
- Theos arm64 compile/link/sign;
- binary marker verification;
- exported API checks;
- one-constructor check (`__init_offsets == 4`);
- artifact upload.

Artifact:

- `ZonoPatch-v0.5.8-M3.1-ABI-ReturnFoundation`
- ID `10369996035`
- ZIP SHA256 `9938d7e7f061fd0d09e9690abdcdac616eb3af378bd99e5e2e5f4d242dd6c8ab`
- dylib SHA256 `00e3aa4e3d638ba184c51f2b31c7374a172a12796b831b8b8a04c3cd73340079`
- dylib size `801376`
- thin arm64 Mach-O
- single constructor.

## NEXT — M3.1 physical-device acceptance

Use known target:

`Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0`

RVA must remain `0x2DA9E10`.

Confirm the new ABI card's actual runtime values:

- managed return type;
- return ABI class;
- instance/static;
- generic/inflated;
- parameter list/count;
- Return Override Foundation Ready/Blocked + reason;
- Copy ABI.

Do not assume `get_TotalCashReward` is int/instance until the device card confirms it.

## After M3.1 acceptance — M3.2

Implement actual **Return Override backend** on a new branch. Requirements before enabling a hook:

- consume the M3.1 validated ABI descriptor/plan;
- dynamically detect an available jailbreak-native hook backend, with ElleKit / `MSHookFunction`-compatible API as the preferred direction after runtime verification;
- preserve original trampoline;
- enable/disable/restore safely;
- initially support only M3.1-approved scalar/raw-pointer return kinds;
- refuse complex struct/HFA, managed-object, generic/inflated/shared and unresolved ABI;
- bind Number/Slider/Toggle controls generically rather than hardcoding game feature names;
- add transaction/rollback and conflict state to unified Runtime Modification management.

## Later milestones

- M3.3: Inline Hook / Function Replace with ABI-safe templates and original-call support.
- M3.4: Trace/call monitoring, call counts, thread, arguments/return/duration where ABI is known.
- M3.5: unified Runtime Modification page for Instruction Patch / Return Override / Inline Hook.
- Hardening: stale index cleanup, generic/shared classification improvements, remove temporary Objective-C warning suppression before sealing.
