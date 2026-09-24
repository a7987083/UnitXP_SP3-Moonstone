# ROADMAP

## Current milestone — M5.2 Immediate Chain V2

Branch: `feature/runtime-patch-menu-v0.5.8-m5.2-immediate-chain-v2`

CI-validated product head: `2456f6ba4dfb659e3480db2e677452dad8516153`

Implemented:

- M5.1 per-argument authored controls are retained: fixed / Switch / Button / Number / Slider.
- Customer runtime success is silent. Button/Runtime invoke/Immediate Chain success no longer shows an `执行完成` dialog; failures still show `执行失败`. Builder / Method Finder test return/debug surfaces remain intact.
- Immediate Chain metadata upgraded to version 2 with an ordered `nodes[]` schema while Runtime Action ABI remains version 1 / 64-byte entries.
- A root Runtime Action can atomically execute up to 8 additional chain nodes. Each subsequent node supports `/0-/8` typed argument values and exact parameter signatures.
- Each subsequent node is exact-resolved by Assembly + Namespace + Class + Method + Parameter Types before execution. Saved token is checked when `il2cpp_method_get_token` is available; saved return type is also checked when available.
- Absolute MethodInfo/MethodPointer values are not persisted as stable identities. They are runtime diagnostics only, avoiding ASLR-invalid cross-launch identities.
- Existing typed invoke is reused, so numeric `0` is passed via actual typed storage (`&value`), not treated as a null argument.
- Existing M5.0 managed-reference GCHandle / validated receiver injection is reused between chain levels.
- `System.String` results now have a V2 decode path using `il2cpp_string_length` + `il2cpp_string_chars` (UTF-16 -> NSString) instead of only showing an object address.
- Existing M4.8 primitive unboxing remains the primitive-return decoder.
- Chain V2 emits per-level trace/log data: level, identity, receiver, args, MethodInfo/MethodPointer, return type/kind/value/raw, status.
- Managed exceptions get best-effort class/message/stack enrichment when IL2CPP formatting exports are available.
- Null or non-managed previous returns stop the chain before a next receiver call instead of blindly invoking.
- Runtime-only and Static final generated Mach-O names remain suffixless; `.znpatched` may only exist as Static Builder internal staging.

CI/build status:

- Final Run `35939364930`: SUCCESS
- Job `107443621364`: SUCCESS
- Artifact ID `10784551336`
- Artifact ZIP SHA256 `334c56df627ff2a18cd8cf0572afd9848433808d1d9816d2c4c7c1c29a15dd3c`
- Dylib SHA256 `84a9ff17e66ddb50c42893603b45123457d31ff3986655f07bc12748efef9d87`
- Dylib size `1304480` bytes
- Independent artifact/dylib hash verification: PASS

Device acceptance still required:

1. Verify customer success is silent for Button and Runtime actions; force a failure and verify only failure alerts remain.
2. Verify Builder / Method Finder test execution still displays return/debug information.
3. Build `yo::wB() -> yy::DY(0) -> ee::ToString()` and confirm final decoded string is the actual in-game value, not `object 0x...`.
4. Repeat with `yy::DY(1)`.
5. Confirm each level logs receiver / args / return and does not expose raw temporary object addresses to the customer UI.
6. Verify a null previous managed return terminates safely.
7. Verify an incompatible class/signature/token/return-type mismatch fails closed.
8. Regress ordinary Offset, older Runtime `/0-/8`, per-argument controls, and suffixless generated binary output.

Next engineering work after device evidence:

- Replace Chain V2 CSV argument authoring with one typed row per argument, reusing the Runtime parameter-control authoring UI.
- Add enum member-name enumeration/dropdown; current enum execution is typed by underlying primitive value but the editor accepts numeric values.
- Add explicit chain object-argument sources (`previous return`, `Level N return`, captured object) instead of receiver-only chaining.
- Add safe ref/out and broader custom ValueType support only where metadata-driven marshaling can be verified.
- Add saved chain templates / replay / trace export after the execution model is device-accepted.
