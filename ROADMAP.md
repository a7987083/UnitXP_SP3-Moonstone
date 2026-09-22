# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `fix/runtime-patch-menu-v0.5.8-m4.1-ui-ux-v2`
- Runtime product source head: `4d3f62bd5ae645493e3af10e179402d9cc47e889`
- CI validated branch head: `911dec0c56234387820fbec5daf996e396f86294`
- Stage: `M4.1 UI/UX V2 — Runtime Method Call usability + binary target selection + touch/scroll repair`
- CI run: `35704458522` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.1-UIUX-V2`
- Artifact ID: `10683409230`
- Artifact ZIP SHA256: `f9d88f62a923a4adc9797d686ad601198761af14d4f27d4919906ba97dc83450`
- Dylib: `ZonoPatch_v0.5.8_M4.1_UIUX_V2.dylib`
- Dylib SHA256: `4ad03fdd759cb7218cb3aeb22a12f1bca75ff6ccf12a10532f47e5bf516574ae`
- Current device validation: `PENDING` for the M4.1 UX additions.

## Baselines

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not rewrite.
- Method Finder V3 M2.2 device-accepted product: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1 CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`.
- M4 Runtime Method Call V1 CI run: `35689545606` — success.
- M4 Runtime Method Call V1 artifact ID: `10678476991`.
- M4 Runtime Method Call V1 dylib SHA256: `53bc795e7c9fbefb7443da12d5ea9598b5eba9f0a2b51a453ad9445d93f50651`.
- M4 Runtime Method Call V1 device evidence: user confirmed `创建方法按钮`, `测试执行`, and the generated binary all work on device. Treat those paths as device-verified, not as a full regression pass.

## Completed — Offset Resolver V2

- Exact dyld image identity.
- Accepts preferred/unslid VA and historical RVA forms and normalizes internally.
- Preserves author input while maintaining canonical RVA internally.
- Offset Resolver V2 core file remains unchanged by M4.1.

## Completed — M4 Runtime Method Call V1

- Added independent Runtime Action ABI instead of changing the legacy Static Patch ABI.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action table is embedded separately from `ZN44StaticEntry`.
- Method Finder can create Runtime Method Call authoring actions.
- Zero-argument static IL2CPP methods can be test-invoked through `il2cpp_runtime_invoke`.
- Instance methods fail closed instead of invoking with a null instance.
- Builder embeds Runtime Actions into generated binaries.
- `ZN44StaticEntry` remains 128 bytes.
- Device acceptance received for create button, test execution, and generated-binary use.

## Implemented — M4.1 UI/UX V2

### Binary target discovery and selection

- Default target policy: prefer loaded `UnityFramework`; if unavailable, use the main executable.
- Do not persist `/var/containers/Bundle/Application/<UUID>/...` absolute paths.
- `其他 -> 二进制` becomes a selector rather than requiring manual typing.
- `App Libraries` picker enumerates app-bundle loaded images and lets the user select the main executable, `UnityFramework`, app `.dylib`, or framework executables.
- Internal target identity and real file path remain separate concepts.

### Menu touch passthrough

- M4.1 adds an outer UX repair layer around the existing menu shell.
- Goal: menu controls remain interactive while touches outside the menu panel continue to the game.
- The repair uses a child-controller/passthrough shell rather than disabling interaction on the menu.
- This requires real-device regression because presentation ownership previously affected Translate stability.

### Scroll position preservation

- Same-page actions preserve `UIScrollView.contentOffset` across `renderPage` rebuilds.
- Category switches may still intentionally return to the top.
- Add/delete/type/runtime-authoring actions should no longer jump the current page to offset zero.

### Direct binary generation

- `生成新二进制` no longer requires the user to manually press `读取验证` first.
- Build performs the required preflight automatically before Static Builder work.
- Required Original/length/relocation/Mach-O safety checks are not removed; only the manual prerequisite is removed.
- `读取验证` remains available as an explicit test/debug action.

### Runtime Method Call display-name editing

- Runtime action display `title` is editable independently from `methodName`.
- Renaming a menu button does not change the canonical IL2CPP method identity.
- Existing Runtime Action ABI already has independent `titleOffset` and `methodOffset`, so no entry-size change is required.

## CI gate — M4.1 passed

Run `35704458522` passed:

- checkout;
- source contract assertions;
- dependency/Theos install;
- arm64 Theos build;
- binary verification;
- artifact upload.

CI also asserts that these Offset/Static core files are unchanged relative to Offset Resolver V2:

- `iosruntimepatchmenu/src/ZonoeRuntimeMenu.mm`
- `iosruntimepatchmenu/src/ZNOffsetResolverV2.mm`
- `iosruntimepatchmenu/src/ZNStaticPatchFormat.h`

Binary verification includes M4.1 markers for `App Libraries`, Runtime Action authoring rename, direct-build preflight, touch passthrough shell, `il2cpp_runtime_invoke`, `Unslid VA`, and one constructor (`__init_offsets == 4`).

## Next — M4.1 physical-device acceptance

Status: `NEXT`

1. Confirm opening the menu no longer blocks gameplay touches outside the menu panel.
2. Regress Translate/system text presentation to ensure the previous modal stability is preserved.
3. Confirm `其他 -> 二进制` automatically selects `UnityFramework` in Unity games and falls back to the main executable when UnityFramework is absent.
4. Confirm tapping the binary field opens App Libraries and selecting another app image changes the target without manual input.
5. Confirm same-page buttons no longer jump the Builder page back to the top.
6. Rename a Runtime Method Call display title, build, reload, and confirm the renamed title is retained while the same method is invoked.
7. Without pressing `读取验证`, fill a valid patch and press `生成新二进制`; confirm automatic preflight + generation succeeds.
8. Regress M4 V1 device-verified paths: create method button, test execution, and generated binary usability.

## After M4.1 acceptance

- Record per-item device results in `CHANGELOG_DEV.md` and `PROJECT_STATE.json`.
- If touch passthrough is stable, keep the M4.1 shell as the interaction baseline; otherwise fix that layer only without changing Offset Resolver V2 or Runtime Action ABI.
- Continue parameter/instance Runtime Method Call work only after M4.1 regression is accepted.
- Keep all future milestones on new branches; do not rewrite accepted historical product commits.
