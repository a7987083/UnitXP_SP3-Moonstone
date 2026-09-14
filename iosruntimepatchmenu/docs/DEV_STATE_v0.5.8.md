# Method Finder V3 — v0.5.8-dev

## Baseline

- Branch: `feature/runtime-patch-menu-v0.5.8-method-finder-v3`
- Parent device-verified V2 baseline: `4377d4a4c6e325e54299e3055346240f4963940f`
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
- V2 remains authoritative for Named Offset single-result resolution.

Not implemented yet:

- asynchronous shard scheduling/progress/cancellation;
- persistent local IL2CPP index;
- full return/parameter type and generic/shared ABI metadata;
- Return Override backend;
- jailbreak inline Hook/Replace backend and original trampoline;
- call trace / argument / return logging;
- unified Runtime Modification management page.

## Validation boundary

At this point V3 source is committed, but it is not device-verified. CI must compile and binary-verify the candidate before any dylib is offered for device testing.

Device acceptance target for milestone 1:

1. `get_TotalCashReward` opens a result list and includes the known `Cash::get_TotalCashReward/0` target.
2. Selecting that candidate shows RVA `0x2DA9E10` and the detailed address/raw-byte page.
3. `0x2DA9E10` produces an RVA reverse-result list and preserves multiple MethodInfo aliases if present.
4. `Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0` uses qualified candidate mode and returns the known target.
5. Copy actions and Create Patch entry behave correctly without changing the existing Validator transaction semantics.
