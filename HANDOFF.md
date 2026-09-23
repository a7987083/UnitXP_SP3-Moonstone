# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.1 Runtime Arg Controls + Immediate Chain V1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.1-runtime-arg-controls-immediate-chain-v1`
- CI-validated product head: `c24b77ee709cec477a5a94b8a35f98c38a459f97`
- Final CI run: `35932826187` — success
- Job: `107423107248` — success
- Artifact ID: `10781652685`
- Artifact ZIP SHA256: `76f812e245aa2bd45084f732485737df9a781af55bfc95d19f8e3aa468588ac8`
- Dylib size: `1287760`
- Dylib SHA256: `b0ec99af081edbd1612d27aa2a6cdadb83451dc6301f4097fb2555735ef1544e`
- Format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device verification.

Current M5.1 state:

- source implemented: YES
- committed to GitHub: YES
- arm64 CI compile/link/sign: YES
- binary marker verification: YES
- artifact upload + independent ZIP/dylib hash check: YES
- per-argument customer controls on device: PENDING
- Immediate Chain on device: PENDING
- actual generated suffixless UnityFramework on device/fixture: PENDING
- full regression: NO

## M5.1 authoring model

Static Offset entries keep the existing behavior.

Runtime Method entries use the Runtime Action authoring model:

```text
Method identity
arg[0] value [☐/☑] [Fixed/Switch/Button/Number/Slider]
arg[1] value [☐/☑] [Fixed/Switch/Button/Number/Slider]
...
```

Unchecked arguments remain fixed and are not shown in the customer menu. Checked arguments are rendered with the selected control family. The customer-side invocation vector is assembled from fixed authoring values plus current exposed-control values.

M5.1 Slider authoring currently has no min/max/step UI; defaults are `0 / 100 / 1`.

## Immediate Chain V1

Finder result order is:

```text
[测试执行]
[创建方法]
[链式调用]
```

Immediate Chain is only offered for managed-reference/ObjectReference primary returns. The chain descriptor stores assembly/namespace/class/method/argc/arguments; no returned object pointer or GCHandle is serialized.

V1 second hop currently uses `argc=0`. Execution is:

```text
Primary action
→ M4.8 return decode
→ M5.0 managed-reference capture / GCHandle / class validation
→ M5.1 second action
→ M5.0 injects latest compatible managed return as receiver
→ second-hop result returned to UI
```

Example:

```text
yy::DY(0)
→ ee*
→ ee::ToString()/0
→ System.String
```

## Runtime Action ABI invariants

`ZNRuntimeMethodCallEntry == 64` bytes and version remains 1.

```text
reserved[0] legacy /1 argument0
reserved[1] Full Parameter Signature
reserved[2] argument vector JSON
reserved[3] M5.1 per-argument control JSON
reserved[4] M5.1 Immediate Chain JSON
reserved[5] free
```

Static Patch entry remains `128` bytes. Runtime Action ABI remains separate from Static Patch ABI.

## Generated binary naming

Final generated Mach-O output uses the original binary filename, e.g. `UnityFramework`.

- Runtime-only Builder writes the original filename directly.
- Static Builder may internally stage as `UnityFramework.znpatched` while existing patch/protection/signing logic runs, then final postprocess renames it to `UnityFramework`.
- Source Contract + compilation validate the code path, but a real generated fixture/device export is still required before calling suffixless output device-verified.

## Immediate device checklist

1. Find a `/3` method and create it. Builder must show 3 parameter rows.
2. Leave arg0/arg2 fixed; enable arg1 and select Number.
3. Generate a binary; final output filename should be `UnityFramework`, not `.znpatched`.
4. Customer runtime menu should expose only arg1. Change it and execute; arg0/arg2 must remain fixed.
5. Repeat with Switch, Button and Slider where the parameter ABI makes sense.
6. Find a method with managed-reference return; confirm `链式调用` is directly below `创建方法`.
7. Configure target `Class::Method/0` such as `ee::ToString()/0` and execute generated action. Confirm second-hop result is returned without exposing the raw object address.
8. Regress ordinary Offset patches and older Runtime `/0-/8` calls.

## Known scope limits

- Immediate Chain V1 second hop is `/0` only.
- Slider authoring bounds UI is not implemented yet; defaults are 0/100/1.
- ObjectReference/ref/out/pointer/complex ValueType arguments are not generally solved by the per-argument control UI; existing ABI safety rules still apply.
- M5.0/M5.1 managed-object lifetime and receiver behavior remains device-validation dependent.
