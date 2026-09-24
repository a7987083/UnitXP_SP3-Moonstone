# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.2 Immediate Chain V2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.2-immediate-chain-v2`
- CI-validated product head: `2456f6ba4dfb659e3480db2e677452dad8516153`
- Final CI run: `35939364930` — success
- Job: `107443621364` — success
- Artifact ID: `10784551336`
- Artifact ZIP SHA256: `334c56df627ff2a18cd8cf0572afd9848433808d1d9816d2c4c7c1c29a15dd3c`
- Dylib size: `1304480`
- Dylib SHA256: `84a9ff17e66ddb50c42893603b45123457d31ff3986655f07bc12748efef9d87`
- Format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device verification.

Current M5.2 state:

- source implemented: YES
- committed to GitHub: YES
- arm64 CI compile/link/sign: YES
- binary marker verification: YES
- artifact upload + independent ZIP/dylib hash check: YES
- customer silent-success behavior on device: PENDING
- Immediate Chain V2 real-game behavior: PENDING
- System.String real-game decode: PENDING
- 3+ level managed receiver continuity: PENDING
- full regression: NO

## Customer Runtime UX inherited from M5.1 Silent

Customer-facing generated menu behavior:

```text
success -> silent
failure -> 执行失败 alert
```

This applies to Runtime actions and Immediate Chain execution. Builder / Method Finder test execution remains a developer/debug surface and keeps return/debug information.

## Immediate Chain V2 execution model

Versioned metadata uses `immediateChain = { version:2, atomic:true, nodes:[...] }`.

Execution:

```text
Root Runtime Action
  -> managed return
  -> Chain Node 1 /0-/8
  -> managed return
  -> Chain Node 2 /0-/8
  -> ...
```

The entire chain executes in one transaction. There is no UI round-trip between levels and no persisted temporary object address/GCHandle.

Each node stores stable managed identity data:

```text
Assembly
Namespace
Class
Method
Parameter Types
argument values
token (when available)
return type (when available)
```

`MethodInfo*` and `MethodPointer` are current-process diagnostics only; do not serialize them as cross-launch identities because ASLR makes absolute addresses unstable.

## Reused lower layers

M5.2 intentionally delegates each node through existing layers:

- M4.6 Full Signature resolver: exact overload resolution / fail closed
- M4.7 typed invoke: `/0-/8`, primitive/String/basic supported value types; numeric zero uses real typed storage address
- M4.8 Return Capture: primitive boxed return decoding
- M5.0 Managed Return Chaining: GCHandle lifetime + compatible receiver injection
- M5.1 per-argument control authoring and customer runtime controls
- M5.1 Silent Customer Execution

## M5.2 additions

- up to 8 additional nodes after root
- per-node `/0-/8` arguments
- exact signature preflight before each node
- token check when `il2cpp_method_get_token` exists
- return-type guard when available
- null/non-managed previous-return stop
- best-effort managed exception class/message/stack detail
- per-level trace/log with receiver/args/return/runtime pointers
- System.String decode using `il2cpp_string_length` + `il2cpp_string_chars`

## Authoring flow

`链式调用` remains directly below `创建方法`.

For the current target scenario:

```text
Root: yo::wB()/0

Level 1:
Class: yy
Method: DY
Parameter Types: K
Args: 0

Level 2:
Class: ee
Method: ToString
Parameter Types: <blank>
Args: <blank>
```

Repeat `DY` argument `1` for the second currency path. The actual returned values must be treated as device evidence only; no value is considered verified until observed on device.

## Runtime Action ABI invariants

`ZNRuntimeMethodCallEntry == 64` bytes and version remains 1.

```text
reserved[0] legacy /1 argument0
reserved[1] Full Parameter Signature
reserved[2] argument vector JSON
reserved[3] M5.1 per-argument control JSON
reserved[4] M5.1/M5.2 Immediate Chain JSON
reserved[5] free
```

Static Patch entry remains `128` bytes.

## Generated binary naming

Final generated Mach-O output remains the original filename (`UnityFramework` etc.). Static Builder may use `.znpatched` internally only as a staging name.

## Immediate device checklist

1. Confirm customer successful Button/Runtime action execution shows no completion alert.
2. Force an invalid Runtime action and confirm only `执行失败` remains visible.
3. Confirm Builder/Method Finder test execution still displays return/debug data.
4. Create the 3-level `yo::wB() -> yy::DY(0) -> ee::ToString()` chain.
5. Confirm Level 1 receives the root managed object automatically; customer never handles a raw address.
6. Confirm final System.String is decoded as text, not only `object 0x...`.
7. Repeat with `DY(1)`.
8. Test null return: chain must stop before the next call without crash.
9. Test a deliberately wrong signature/class and confirm fail-closed behavior.
10. Regress Static Offset, Runtime `/0-/8`, per-argument controls, Immediate Chain V1 compatibility, and suffixless generated output.

## Known scope limits

- Enum execution is typed by underlying primitive, but enum member-name dropdown authoring is not implemented.
- Chain node editor currently uses CSV for Parameter Types/Args; argument strings containing commas are not a good fit for this V2 editor.
- Arbitrary object arguments sourced from `Level N return` are not implemented; chaining currently uses previous managed return as receiver.
- Generic object-reference args (other than existing String path), ref/out, pointer, and broad custom ValueType marshaling remain fail-closed according to existing ABI safety rules.
- Real device proof for GCHandle lifetime across multiple levels is still required.
