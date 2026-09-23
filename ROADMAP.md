# ROADMAP

## Current milestone — M5.1 Runtime Arg Controls + Immediate Chain V1

Branch: `feature/runtime-patch-menu-v0.5.8-m5.1-runtime-arg-controls-immediate-chain-v1`

CI-validated product head: `c24b77ee709cec477a5a94b8a35f98c38a459f97`

Implemented:

- Runtime Method Builder reuses the existing authoring surface. Static Offset behavior remains unchanged.
- Runtime `/1-/8` actions expose one row per argument. Each argument may stay fixed or be marked Runtime-editable.
- Editable arguments reuse the four existing customer control families: `开关 / 按钮 / 数值 / 滑块`.
- Generated runtime menu only exposes arguments explicitly enabled by the author; all other arguments keep their authored fixed values.
- Method Finder result cards add `链式调用` directly below `创建方法`.
- Immediate Chain V1 stores only the second-hop method descriptor. Returned object addresses / GCHandles are not serialized or shown to customers.
- Immediate Chain V1 currently supports a second-hop target with `argc=0`; it reuses the M5.0 managed-reference capture + validated receiver injection path.
- Runtime Action ABI remains version 1 / 64-byte entries. `reserved[3]` stores argument-control JSON; `reserved[4]` stores Immediate Chain JSON; `reserved[1]` Full Signature is preserved.
- Runtime-only and Static generated binaries now export with the original Mach-O filename. Static Builder may use `.znpatched` only as an internal staging name; final export is suffixless.

CI/build status:

- Run `35932826187`: SUCCESS
- Job `107423107248`: SUCCESS
- Artifact `10781652685`
- Dylib SHA256 `b0ec99af081edbd1612d27aa2a6cdadb83451dc6301f4097fb2555735ef1544e`
- Dylib size `1287760` bytes

Device acceptance still required:

1. Create a `/3` method and confirm three Builder parameter rows.
2. Mark only one parameter Runtime-editable and choose Number; generated menu must expose only that parameter.
3. Change the customer-side value and confirm fixed parameters are retained in the final invoke vector.
4. Verify Switch/Button/Slider customer controls independently.
5. Verify `链式调用` is directly below `创建方法`, and `ObjectReference -> target /0` returns the expected second-hop result without exposing an address.
6. Generate both Runtime-only and Static binaries and confirm final filenames are original names such as `UnityFramework`, not `UnityFramework.znpatched`.

Next engineering work after device evidence:

- Add authoring UI for Slider min/max/step (M5.1 currently uses defaults 0/100/1).
- Extend Immediate Chain target arguments beyond `/0` with exact signature + typed argument authoring.
- Add fixture/device verification for suffixless generated Mach-O output and final IPA replacement/signing.
