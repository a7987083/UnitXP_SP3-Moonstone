# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.2-typed-args-ui-v1`
- Runtime product source head: `d775db7015a2290e508ab8de8aeeae7ce0723c7a`
- CI validated branch head: `e7c81172b04e162f74b3652048dcaf499d753aa4`
- Stage: `M4.2 Typed Arguments UI V1 — /0 preserved + typed /1 static invoke + arity-filtered Method Finder`
- CI run: `35742172120` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.2-TypedArgsUI-V1`
- Artifact ID: `10699772622`
- Artifact ZIP SHA256: `abdde87ce011b96e0f31472973addc8147ff9d2e389f5124d3713b457a451626`
- Dylib: `ZonoPatch_v0.5.8_M4.2_TypedArgsUI_V1.dylib`
- Dylib SHA256: `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`
- Current device validation: `PENDING` for M4.1 UX additions and all new M4.2 `/1` behavior.

## Baselines

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not rewrite.
- Method Finder V3 M2.2 device-accepted product: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1 CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`.
- M4 Runtime Method Call V1 CI run: `35689545606` — success.
- M4 Runtime Method Call V1 artifact ID: `10678476991`.
- M4 Runtime Method Call V1 dylib SHA256: `53bc795e7c9fbefb7443da12d5ea9598b5eba9f0a2b51a453ad9445d93f50651`.
- M4 Runtime Method Call V1 device evidence: user confirmed `创建方法按钮`, `测试执行`, and generated binary use on device. Treat only those paths as device-verified.
- M4.1 UI/UX V2 CI head: `911dec0c56234387820fbec5daf996e396f86294`, run `35704458522` success; new M4.1 UX remains device-validation pending.

## Stable architecture constraints

- Exact dyld image identity and Offset Resolver V2 behavior remain unchanged.
- `ZN44StaticEntry == 128` bytes.
- Runtime Action remains independent from Static Patch ABI.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- M4.2 reuses `flags + reserved[0]` for the `/1` textual argument offset; Runtime Method Call entry size remains 64 bytes.
- M4.2 keeps existing `/0` invoke behavior and still fails closed on instance methods without an object instance.

## Implemented — M4.1 UI/UX V2

- Automatic binary target: prefer `UnityFramework`, otherwise main executable.
- `其他 -> 二进制` is a picker instead of mandatory manual input.
- Menu outside-panel touch passthrough layer.
- Same-page scroll position preservation across `renderPage` rebuilds.
- `生成新二进制` performs required validation/preflight internally; manual `读取验证` is optional.
- Runtime Method Call display title is editable independently from method identity.
- These M4.1 behaviors are still pending physical-device acceptance.

## Implemented — M4.2 Typed Arguments UI V1

### Method Finder result UI

- Search results no longer show Namespace or RVA in the compact list; those values remain available in Details.
- Compact result shows method/arity, Class, and Assembly.
- Right side has direct `测试执行` and `创建方法` actions.
- Left information area opens Details.
- Dynamic arity filter is generated from the current result set: `全部`, then only arities actually present (`0`, `1`, `2`, ...).
- Filtering is local over the already returned candidate set; it does not rescan IL2CPP.
- `/1` result cards include an inline argument input; value is preserved while switching arity filters/rendering the result page.
- `/2+` candidates remain visible/filterable but are intentionally non-executable in M4.2 V1.

### `/1` typed invoke

- Existing `/0` static invoke path is preserved.
- M4.2 V1 accepts exactly one explicit argument for `/1` static methods.
- Runtime resolves the real IL2CPP parameter ABI before invoke; it does not infer a type from the typed text alone.
- Supported first-stage argument classes: bool, signed/unsigned 32-bit integer, signed/unsigned 64-bit integer, float, double, enums whose ABI metadata resolves to a supported primitive, and `System.String`.
- `System.String` is created through `il2cpp_string_new`.
- Value arguments are passed to `il2cpp_runtime_invoke` through `void **params` using typed storage addresses.
- Fail closed: instance methods, `/2+`, object references other than String, complex value types/structs, ref/out, pointers, unsupported/unknown ABI, and generic definitions.

### Runtime Action persistence

- `ZNRuntimeMethodAction` now carries `argumentValues`.
- Builder allows editing the saved `/1` argument after creating the action.
- Generated Runtime Action table persists the `/1` textual argument in the existing string pool.
- `ZNRuntimeMethodCallEntry` remains 64 bytes: flag `ZNRuntimeActionFlagArgument0Text` marks `reserved[0]` as the argument string-pool offset.
- Runtime loader restores that argument and typed invoke resolves the current method signature again before execution.

### App Libraries display

- Picker behavior remains app-local only, but M4.2 compact display shows only the final module name (for example `UnityFramework`, `XPHero`, `XPHero.dylib`) rather than `name · relative/path`.
- Internal module identity/path resolution remains separate from what the user sees.

## CI gate — M4.2 passed

Workflow: `Build Runtime Patch Menu v0.5.8 M4.2 Typed Args UI V1`

Run `35742172120` passed:

- Checkout;
- source contract assertions;
- dependency/Theos install;
- arm64 Theos build;
- binary verification;
- artifact upload.

The first run `35741898563` compiled successfully but binary verification failed because macOS `strings` mangled UTF-8 Chinese before grep. Verification was corrected to assert ASCII Objective-C selectors (`znm42_testCandidate:` / `znm42_createCandidate:`); no product compile fix was required for that failure.

Binary verification confirms M4.2 markers, typed `/1` capability, direct test/create selectors, App Libraries, `il2cpp_runtime_invoke`, `il2cpp_string_new`, Offset Resolver V2 marker, UX V2 marker, and one constructor (`__init_offsets == 4`).

Independent post-download verification:

- ZIP SHA256 matches Artifact digest: `abdde87ce011b96e0f31472973addc8147ff9d2e389f5124d3713b457a451626`.
- Dylib is thin arm64 Mach-O.
- Dylib SHA256: `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`.

## Next — physical-device acceptance

Status: `NEXT`

1. Regress M4.1 touch passthrough, Translate, binary picker, scroll preservation, title editing, and direct-build preflight.
2. Search a method name that returns mixed `/0` and `/1` candidates; verify `[全部] [0] [1] ...` only shows arities actually present and filters instantly.
3. Verify compact cards show Class + Assembly only, with Namespace/RVA still available in Details.
4. Test a known safe static `/1` primitive method: enter a value, `测试执行`, confirm expected effect and no crash.
5. `创建方法`, change its title/argument in Builder, generate the binary, reload, and confirm the persisted action executes the same method with the saved value.
6. Test at least one `System.String` `/1` method if a safe target exists.
7. Confirm instance `/1`, `/2+`, ref/out, pointer, object and complex struct candidates fail closed rather than invoking with guessed ABI.
8. Regress the already device-verified M4 `/0` create/test/generated-binary paths.

## After acceptance

- Record explicit per-item device results in all five long-term state files.
- Promote M4.2 only after `/1` device evidence; CI success alone is not device verification.
- Next typed-argument stage may extend the same marshal loop to `/2+`; do not implement separate hard-coded `/2`, `/3`, etc. invoke engines.
- Complex Unity structs such as Vector2/Vector3/Quaternion must get explicit ABI-aware editors/serialization rather than being treated as multiple primitive arguments.
