# ROADMAP

## Current milestone — M5.3 Control Binding V1

Branch: `feature/runtime-patch-menu-v0.5.8-m5.3-control-binding-v1`

CI-validated product head: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`

Implemented:

- M5.2 Immediate Chain V2, `执行链` state machine, 50-entry M4.3 Finder search history and customer silent-success behavior are retained.
- Runtime per-argument controls are now behavior-bound instead of requiring a separate top Execute action:
  - Button: tap invokes immediately.
  - Switch: value change invokes immediately.
  - Number: editing completion invokes immediately.
  - Slider: drag keeps updating the value; touch release commits one invoke.
- Runtime invoke still composes exposed values with hidden fixed arguments and uses the existing typed `/0-/8` + full-signature path.
- Successful customer Runtime execution stays silent; failures still show `执行失败`; Builder/Finder test surfaces keep return/debug output.
- Static Button is now bound to the existing fixed Enabled variant instead of only publishing an event.
- Static Number/Slider V1 now binds a customer value to generated Static Dispatch ON variants when the Enabled prefix is a verified ARM64 `MOVZ` followed by compatible `MOVK` instructions.
- Protection V2 fragmented ON instructions are followed through their generated branch chain; the matching MOV immediate fields are rewritten transactionally with expected-byte verification/read-back/rollback through `ZNRuntimePatchExecutor`, then the Static variant is enabled.
- Static Number/Slider refuses unsupported Enabled patterns instead of guessing arbitrary bytes. V1 accepts non-negative integer values only; W values are limited by available MOVZ/MOVK halfword slots, X values are limited to exact-double range (`2^53-1`).
- Static Slider updates are debounced before the dynamic write.
- Static Dispatch entry ABI remains 128 bytes; Runtime Action entry ABI remains 64 bytes. No ABI expansion.

CI/build status:

- Run `35951498398`: SUCCESS
- Job `107480818078`: SUCCESS
- Artifact ID `10788349821`
- Artifact ZIP SHA256 `80a2461b89ad5625d03d86407ad8ec5ea9854cde46422485d08e1037232fd777`
- Dylib SHA256 `e4ed0643ed7cf8aceb89f93f06c40f41442f4f12a64b1d8bcd7970765df7b98b`
- Dylib size `1337776` bytes
- Mach-O: thin arm64 dylib
- Independent ZIP/dylib hash verification: PASS

Device acceptance required:

1. Runtime Switch: toggle once and confirm the underlying method is invoked immediately with `true/false`, with no success popup.
2. Runtime Number: edit the value and finish editing; confirm one invoke using the new value.
3. Runtime Slider: drag without repeated invoke spam, then release and confirm one invoke using the final stepped value.
4. Runtime Button: tap and confirm immediate invoke; success remains silent and forced failure remains visible.
5. Static Button: tap and confirm the fixed Enabled variant activates.
6. Static Number/Slider: use a validated Enabled beginning with `MOV W/Xd,#imm` (`MOVZ`, optional `MOVK`) and confirm customer value changes the effective immediate rather than reusing the original fixed value.
7. Static unsupported Enabled: confirm it fails closed with `执行失败` rather than modifying unknown bytes.
8. Regress M5.2 Chain V2, execution-chain UI, M4.3 search history, ordinary Static Switch, Runtime `/0-/8`, and suffixless generated binaries.

Known architectural boundary:

- Static dynamic V1 changes generated executable ON-variant instructions through the existing transactional Runtime Patch executor. On targets that prohibit RX→RW executable-page mutation, this path may fail closed at runtime. A future non-writable-code implementation should move the dynamic scalar into generated RW data and have a build-time parameterized stub consume it.
- Static V1 intentionally does not treat arbitrary Enabled bytes as Int32/Float or guess instruction semantics.

Next engineering work after device evidence:

- If executable-page mutation is blocked on the intended signing/device model, implement Static Dynamic V2 with build-time RW value cells + parameterized generated stubs (no runtime executable-page writes).
- Add explicit signed/float encodings and Builder range/default/step authoring only after V1 device evidence.
- Continue Chain typed-row/enum/object-source work after the control-binding regression matrix is accepted.
