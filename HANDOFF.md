# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.2 Typed Arguments UI V1 on top of M4.1 UX + Offset Resolver V2 + Runtime Method Call V1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m4.2-typed-args-ui-v1`
- Runtime product source head: `d775db7015a2290e508ab8de8aeeae7ce0723c7a`
- CI validated head: `e7c81172b04e162f74b3652048dcaf499d753aa4`
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`
- M4 V1 device-verified CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`
- M4.2 CI run: `35742172120` — success
- Artifact: `ZonoPatch-v0.5.8-M4.2-TypedArgsUI-V1`
- Artifact ID: `10699772622`
- ZIP SHA256: `abdde87ce011b96e0f31472973addc8147ff9d2e389f5124d3713b457a451626`
- Dylib: `ZonoPatch_v0.5.8_M4.2_TypedArgsUI_V1.dylib`
- Dylib SHA256: `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`
- Dylib format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate source, CI, binary and device validation.

### Device-verified predecessor

For `feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`, the user explicitly reported:

- `/0` `创建方法按钮` works on device;
- `/0` `测试执行` works on device;
- generated binary is usable on device.

Those specific M4 V1 paths are device-verified. This is not a full regression pass.

### Current M4.2 state

- source implemented: YES;
- committed to GitHub: YES;
- arm64 CI compiled/linked/signed: YES;
- binary verified: YES;
- artifact produced and independently hash-checked: YES;
- M4.1 new UX physical-device validation: PENDING;
- M4.2 `/1` typed invoke physical-device validation: PENDING;
- full regression: NO.

## Architecture that must remain stable

### Offset Resolver V2

Do not rewrite while validating M4.2. Core behavior remains exact dyld image identity, Preferred/Unslid VA handling, historical RVA fallback, canonical RVA internal representation and author-input preservation.

CI asserts these remain unchanged relative to `a3b8db8...`:

- `iosruntimepatchmenu/src/ZonoeRuntimeMenu.mm`
- `iosruntimepatchmenu/src/ZNOffsetResolverV2.mm`
- `iosruntimepatchmenu/src/ZNStaticPatchFormat.h`

### Binary ABIs

- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Actions stay separate from Static Patch ABI.
- M4.2 `/1` storage uses the existing Runtime Action string pool; `ZNRuntimeActionFlagArgument0Text` marks `reserved[0]` as the argument text offset. Do not enlarge the entry for this milestone.

## M4.1 inherited UX behavior

- Prefer `UnityFramework`, otherwise main executable.
- Binary target is chosen through `App Libraries`, not mandatory free text.
- Do not persist `/var/containers/Bundle/Application/<UUID>/...` paths.
- Menu outside-panel touch passthrough layer.
- Same-page scroll preservation.
- Build can be pressed without prior manual `读取验证`; required preflight still runs.
- Runtime Method Call `title` is editable independently from method identity.

All of the above remain pending explicit device acceptance unless the user separately reports them working.

## M4.2 actual changes

### Method Finder compact results

The result list now targets this interaction:

```text
[全部] [0] [1] [2] ...   // only arities present in current results

SetSpeed/1   [2.5]        测试执行
Player                    创建方法
Assembly-CSharp
```

Rules:

- Namespace is hidden in compact results; Details still shows it.
- RVA is hidden in compact results; Details still shows it.
- Class and Assembly remain visible.
- Left information region opens Details.
- `/1` has an inline value editor.
- right-side actions directly test/create.
- filter is local and does not rescan IL2CPP.
- `/2+` may be filtered/displayed, but direct actions are disabled in V1.
- input values survive filter/render changes within the result page.

### Typed `/1` invoke

The runtime does not infer the argument ABI from the string field. It resolves the method and calls `ZNIL2CPPDescribeMethodABI` first.

Supported V1 argument categories:

- bool;
- signed/unsigned 32-bit integer;
- signed/unsigned 64-bit integer;
- float;
- double;
- enum when metadata resolves to a supported primitive ABI;
- `System.String` via `il2cpp_string_new`.

Fail closed:

- instance methods without an object instance;
- `/2+`;
- ref/out;
- pointer;
- object reference other than String;
- complex value type/struct (including Vector types until explicitly implemented);
- unknown ABI;
- generic definition.

Execution still uses `il2cpp_runtime_invoke`. Value arguments are passed through typed local storage addresses in `void **params`; String is a managed object pointer.

### Runtime Action persistence

- `ZNRuntimeMethodAction.argumentValues` stores authoring values.
- Builder can edit the saved `/1` argument after creation.
- Binary serialization stores the text argument in the existing Runtime Action string pool.
- Runtime parser restores it and the Invoke Engine validates current method ABI again before execution.

### App Libraries display

M4.2 keeps M4.1 discovery/selection logic but displays only the final module name (`UnityFramework`, app executable, `.dylib`, framework executable), not the relative path.

## CI evidence

Final workflow: `Build Runtime Patch Menu v0.5.8 M4.2 Typed Args UI V1`

Final run: `35742172120` — `success`.

Passed steps:

- Checkout
- Source contract assertions
- Install dependencies
- Install Theos
- Build M4.2 Typed Args UI V1
- Verify binary
- Upload artifact

The immediately prior run `35741898563` compiled successfully but Verify Binary failed because macOS `strings` mangled Chinese UTF-8 before grep. The final workflow verifies action selectors (`znm42_testCandidate:` / `znm42_createCandidate:`) instead, while source-contract assertions verify the Chinese labels.

Independent post-download artifact verification confirmed:

- ZIP SHA256 `abdde87ce011b96e0f31472973addc8147ff9d2e389f5124d3713b457a451626`;
- dylib SHA256 `a8c7e86b2b81c48ece1a35d4a4b422f8c8457525e3185f5e360e7dad47527125`;
- thin arm64 Mach-O;
- strings include `[m4.2-ui]`, `typedArg1Static`, `znm42_testCandidate:`, `znm42_createCandidate:`, `App Libraries`, `il2cpp_runtime_invoke`, `il2cpp_string_new`.

## Immediate physical-device checklist

1. M4.1 regression: menu outside touch passthrough + menu controls + Translate second-use stability.
2. `其他 -> 二进制`: Unity default target and simple-name App Libraries picker.
3. Same-page scroll preservation and direct-build auto preflight.
4. Search a method with mixed arities; verify dynamic `[全部] [0] [1] ...` only contains arities actually present.
5. Confirm result cards hide Namespace/RVA but Details retains full metadata.
6. Pick a known safe **static `/1` primitive** method, enter a value and press `测试执行`.
7. Create that method, change title/argument in Builder, generate, reload, execute persisted action.
8. If available, test one safe static `System.String/1` method.
9. Confirm instance `/1`, `/2+`, ref/out/pointer/object/complex types fail closed.
10. Regress M4 V1 `/0` create/test/generated-binary paths.

## Next action after user feedback

- Do not label M4.2 `device_verified` until the user explicitly reports `/1` behavior on device.
- If `/1` primitive path passes, record exact tested method/signature/value/result in all five long-term files.
- Only then extend the same ABI-driven argument marshaler to `/2+`; do not create separate hard-coded engines for each arity.
- Treat Vector2/Vector3/Quaternion and other structs as explicit future typed editors/ABI work, not as multiple primitive parameters.
