# Method Finder V3 — v0.5.8-dev

## Baseline

- Branch: `feature/runtime-patch-menu-v0.5.8-method-finder-v3`
- Parent device-verified V2 baseline: `4377d4a4c6e325e54299e3055346240f4963940f`
- Current compiled V3 source commit: `ef98a090e1df5b69df3fbb86adb905008285d82c`
- V2 bare-name search, qualified lookup, RVA reverse lookup, and zero-`__TEXT.vmaddr` compatibility are preserved.

## Milestone 1 scope

Implemented in source:

- Interactive multi-candidate search API (`ZNIL2CPPMethodFinderSearchV3`).
- Candidate-list modes for bare name, qualified class, and RVA reverse lookup.
- Candidate limit 8/16/32/64 (default 32).
- Search result page instead of treating multiple matches as an interactive-search error.
- Method detail page with RVA, Preferred VA, Runtime VA, MethodInfo, Method Pointer, pointer source/type.
- Safe first-16-byte native code preview via `vm_read_overwrite`.
- Per-address/raw-byte copy actions.
- `Create Patch` continues to reuse the existing Builder + Runtime Validator chain; V3 does not bypass validation.
- Candidate -> Builder bridge forces the selected candidate's canonical expression into the new Builder row, so an ambiguous original query such as a bare method name cannot lose the user's exact selection.
- The Finder restores the user's original search text after the Builder row has been created.
- V2 remains authoritative for Named Offset single-result resolution.

Not implemented yet:

- asynchronous shard scheduling/progress/cancellation;
- persistent local IL2CPP index;
- full return/parameter type and generic/shared ABI metadata;
- Return Override backend;
- jailbreak inline Hook/Replace backend and original trampoline;
- call trace / argument / return logging;
- unified Runtime Modification management page.

## CI recovery and Milestone 1 build

Feature-branch pushes had been routed to a synthetic GitHub Actions entry (`BuildFailed`, workflow id `358009564`) and failed with `startup_failure` before any job was created. A default-branch health workflow proved GitHub-hosted runners were healthy.

The build is now performed through a workflow registered on `main` that checks out the exact V3 source commit. This avoids the broken feature-branch workflow registration without changing V3 product source semantics.

Successful Milestone 1 build:

- Source commit: `ef98a090e1df5b69df3fbb86adb905008285d82c`
- Workflow: `Build Method Finder V3 via Main`
- Run: `34878983443`
- Result: success
- Source assertions: success
- Named Offset parser tests: success
- Static protection tests: success
- clang/Theos build/link/sign: success
- Binary verification: success
- Artifact upload: success
- Artifact id: `10361858260`
- Artifact name: `ZonoPatch-v0.5.8-MethodFinder-V3-M1`
- Artifact archive digest: `sha256:a8726474677cc4f2b3caa583820806e10df1841c6b096621cb5c10cecfd4a92d`
- Dylib: `ZonoPatch_v0.5.8_MethodFinderV3.dylib`
- Dylib size: `717488` bytes
- Dylib SHA256: `1b05fcd88ad2b80915bb5668442f8523604ad81567b2a16e78013f1781faad6e`
- Mach-O: thin arm64 dynamic library
- `__init_offsets` size: 4 bytes (one cold-launch constructor)
- ASCII binary markers `v3-candidate-list` and `v3-reverse-rva`: present

The earlier verification failure was a CI-script false negative caused by using the standard `strings` tool to assert a Chinese UTF-8 UI literal. The product binary had already compiled successfully. The fragile Unicode assertion was removed; product source was not changed for that issue.

## Validation boundary

Milestone 1 is now **source-reviewed + CI-compiled + binary-verified**.

It is **not yet device-verified**. Do not mark v0.5.8 as sealed/release until the device acceptance checks below pass.

## Device acceptance target for Milestone 1

1. `get_TotalCashReward` opens a result list and includes the known `Cash::get_TotalCashReward/0` target.
2. Selecting that candidate shows RVA `0x2DA9E10` and the detailed address/raw-byte page.
3. `0x2DA9E10` produces an RVA reverse-result list and preserves multiple MethodInfo aliases if present.
4. `Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0` uses qualified candidate mode and returns the known target.
5. Copy actions behave correctly.
6. Selecting one candidate and pressing `Create Patch` creates an unvalidated Builder row whose `offsetText` is that candidate's canonical expression, not the possibly ambiguous original search text.
7. Runtime Validator/rollback semantics remain unchanged.
