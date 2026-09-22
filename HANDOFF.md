# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M4.1 UI/UX V2 on top of Offset Resolver V2 + Runtime Method Call V1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `fix/runtime-patch-menu-v0.5.8-m4.1-ui-ux-v2`
- Runtime product source head: `4d3f62bd5ae645493e3af10e179402d9cc47e889`
- CI validated branch head: `911dec0c56234387820fbec5daf996e396f86294`
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`
- M4 Runtime Method Call V1 CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`
- M4.1 CI run: `35704458522` — success
- M4.1 artifact: `ZonoPatch-v0.5.8-M4.1-UIUX-V2`
- Artifact ID: `10683409230`
- Artifact ZIP SHA256: `f9d88f62a923a4adc9797d686ad601198761af14d4f27d4919906ba97dc83450`
- Dylib: `ZonoPatch_v0.5.8_M4.1_UIUX_V2.dylib`
- Dylib SHA256: `4ad03fdd759cb7218cb3aeb22a12f1bca75ff6ccf12a10532f47e5bf516574ae`
- Dylib format: thin arm64 Mach-O dylib

## Validation boundary

Do not conflate build/CI/device state.

### Device-verified predecessor paths

For `feature/runtime-patch-menu-v0.5.8-m4-runtime-method-call-v1`, the user explicitly reported:

- `创建方法按钮` works on device;
- `测试执行` works on device;
- generated binary is usable on device.

Therefore those M4 Runtime Method Call V1 paths are device-verified. This is not a full regression pass for every old feature.

### M4.1 current state

M4.1 is:

- source implemented: YES;
- committed to GitHub: YES;
- CI compiled: YES;
- binary verified: YES;
- artifact produced: YES;
- physical-device validation of the new UX changes: PENDING.

## Architecture that must remain stable

### Offset Resolver V2

Do not rewrite it while validating M4.1.

Core baseline behavior:

- exact dyld image identity;
- Unslid/Preferred VA first where appropriate, historical RVA fallback;
- canonical RVA internally;
- author input preserved for UI/diagnostics.

M4.1 CI explicitly checks that these files are unchanged relative to `a3b8db8...`:

- `iosruntimepatchmenu/src/ZonoeRuntimeMenu.mm`
- `iosruntimepatchmenu/src/ZNOffsetResolverV2.mm`
- `iosruntimepatchmenu/src/ZNStaticPatchFormat.h`

### Static Patch ABI

- `ZN44StaticEntry == 128` bytes.
- Do not place Runtime Method Call fields into the old Static Entry.
- Existing generated-binary Static Dispatch compatibility is a hard regression gate.

### Runtime Action ABI

Runtime Method Call is stored separately:

- `ZNRuntimeActionHeader == 64` bytes;
- `ZNRuntimeMethodCallEntry == 64` bytes;
- independent string offsets for display title and method identity;
- zero-argument static invoke is the currently device-verified scope.

## M4.1 actual changes

### 1. Automatic binary target + App Libraries picker

File: `iosruntimepatchmenu/src/ZNUXFixesV2.mm`.

Policy:

1. prefer loaded `UnityFramework`;
2. otherwise use main executable;
3. clicking the binary selector opens an `App Libraries` list;
4. list is based on loaded app-bundle images and supports main executable, app frameworks and app dylibs;
5. do not persist `/var/containers/Bundle/Application/<UUID>/...` absolute paths.

The user specifically wants Unity games to default to `Frameworks/UnityFramework.framework/UnityFramework`, while non-Unity games default to the executable in the `.app` root.

### 2. Touch passthrough

Problem reported by user: when the menu is open, gameplay cannot be operated.

M4.1 adds an outer interaction shell so menu controls remain interactive while touches outside the panel can pass to the game.

Important risk: previous Translate stability depended on real UIViewController presentation ownership. Therefore this change is not device-accepted until both touch passthrough and Translate/system text presentation are tested together.

### 3. Scroll preservation

Problem reported by user: pressing Builder buttons causes the page to jump to the top.

M4.1 preserves `contentScroll.contentOffset` for same-page render cycles. Explicit category changes may still reset to top.

### 4. Direct build preflight

Problem reported by user: `生成新二进制` was disabled unless every patch had first gone through manual `读取验证`.

New behavior:

- user may press build directly;
- required validation/preflight is performed automatically before Builder work;
- safety checks needed for Original bytes, patch length, RVA/file mapping, Mach-O and relocation are retained;
- manual `读取验证` remains available but is no longer a required human step.

### 5. Editable Runtime Method Call display title

Problem reported by user: Runtime-created buttons defaulted to `methodName` and could not be renamed.

New behavior:

- `ZNRuntimeMethodAction.title` is editable in Builder UI;
- rename updates only display title;
- canonical identity / `methodName` does not change;
- Runtime Action entry ABI does not change because `titleOffset` and `methodOffset` were already separate.

## CI evidence

Workflow: `Build Runtime Patch Menu v0.5.8 M4.1 UI UX V2`

Run: `35704458522`

Result: `success`.

Passed steps:

- Checkout
- Source contract assertions
- Install dependencies
- Install Theos
- Build M4.1 UI UX V2
- Verify binary
- Upload artifact

Binary markers checked by CI include:

- `[offset-v2]`
- `[runtime-method-call]`
- `[ux-v2]`
- `App Libraries`
- Runtime Action `authoring rename`
- `direct build: manual validate skipped`
- `child-controller passthrough shell shown`
- `il2cpp_runtime_invoke`
- `Unslid VA`
- one constructor: `__init_offsets == 4`

Independent post-download verification also confirmed ZIP SHA256 and dylib SHA256 above.

## Immediate device acceptance checklist

1. Open the menu and operate the game outside the menu panel; touches must reach the game.
2. Interact with menu controls; controls must still respond normally.
3. Re-test Translate/system text presentation; no second-use crash/regression.
4. Open `其他`; Unity game should default to `UnityFramework`.
5. Tap the binary target; `App Libraries` picker should open and allow selecting main executable / UnityFramework / app dylibs/frameworks without typing.
6. Scroll down in Builder, press add/delete/type/runtime action operations, and confirm the page stays near the same scroll position.
7. Rename a Runtime Method Call title, generate the binary, reload it, and confirm the custom title remains while the same IL2CPP method is called.
8. Fill a valid Static Patch and press `生成新二进制` without first pressing `读取验证`; automatic preflight should run and generation should succeed.
9. Regress the already device-verified M4 paths: create method button, test execution, generated binary usable.

## Next action after user feedback

- If all M4.1 checks pass: record device acceptance in all five long-term state files and use M4.1 as the next baseline.
- If one M4.1 UX item fails: fix only the responsible UX layer; do not rewrite Offset Resolver V2, Static ABI, or the already working Runtime Method Call core.
- Do not label M4.1 `device_verified` until the user explicitly reports the new M4.1 behaviors working.
