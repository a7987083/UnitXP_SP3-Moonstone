# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M2.2 Builder / Feature Controls / Stable Cancel UX**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m2.2-builder-feature-controls`
- Sealed predecessor: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not modify
- Device-verified V2 baseline: `4377d4a4c6e325e54299e3055346240f4963940f`
- M1 product source: `ef98a090e1df5b69df3fbb86adb905008285d82c` — device verified
- M2 product source: `69b546edd0ed83a5699805951304aa3371a0bc30`
- M2.1 product source: `47d186730ffdf28c2c4bc8fc2992c938c3f1e2b5`
- M2.2 product source / CI validated / device-accepted runtime: `19b912c840e7223adbc2c26ef80185c32b8eb77a`
- M2.2 CI run: `34893082122` — success
- M2.2 artifact: `ZonoPatch-v0.5.8-MethodFinder-V3-M2.2`
- Artifact ID: `10367337459`
- Artifact ZIP SHA256: `4d632a38efb92a53ce492d07b6c6160f06193adffe37cdc3ca4c7d9e00bacaf5`
- Dylib SHA256: `4a42a698af2bcc0926a28413b8f6099215db2a8899747139f1018b284ba40bae`
- Dylib size: `784656` bytes
- Validation: source assertions + parser/protection tests + Theos compile/link/sign + binary verification passed. User then tested the M2.2 build on the real device and reported: `目前没问题了。`

Interpret that report as **M2.2 device accepted for the currently exercised build**, but do not overstate it as a separately itemized full regression pass: the user did not enumerate every acceptance step individually.

Docs-only commits after product source do not change the built dylib. Always distinguish runtime product SHA `19b912c...` from later documentation branch HEADs.

## Device-verified search baseline

Known target:

`Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0`

Known RVA: `0x2DA9E10`.

M1 device-verified paths:

- candidate-list search;
- method detail/address display;
- `0xRVA` reverse lookup;
- full qualified lookup;
- address/detail copy;
- selected candidate -> Builder canonical expression.

M2 broad query `cash` real-device timings:

- first: `423.1 ms`
- second: `147 ms`
- later: approximately `150 ms`

Broad matching remains `exact > prefix > suffix > contains`; structured queries and RVA remain exact.

## Why M2.2 exists

M2.2 addressed three authoring/device issues:

1. Builder had `增加 Patch` but no per-Patch delete and no whole-Feature delete.
2. Feature model needed generic controls, not hardcoded game functions.
3. M2.1 Search/Cancel UX could flash because progress updates rebuilt the Method Finder page repeatedly.

## M2.2 deletion support

Files:

- `src/ZNFeatureControlModel.h/.mm`
- `src/ZNFeatureBuilderControlsV2.mm`

Workspace provides guarded authoring operations:

- `removeFeatureNamed:error:` — removes every Patch row in the logical Feature;
- `removePatchAtGlobalIndex:error:` — removes only the selected Patch and renumbers ordinary `Patch #N` titles;
- operations refuse while Runtime Patch is applied or a build is active.

Expanded Feature authoring row:

`＋ Patch | 类型 · <...> | 删除功能`

Every visible Patch card gets its own `删除` button.

The implementation decorates the existing Builder rather than replacing Offset/Enabled/validation/build behavior.

## Generic Feature Control V2

Do not hardcode `Damage Multiplier`, `Defence Multiplier`, `God Mode`, or `Debug Menu` into the framework.

M2.2 extends the project's existing `ZNFeatureControlType` while preserving historical numeric values:

- Switch / Toggle = 0
- Slider = 1
- Button / Action = 2
- Number = 3

The authoring selector exposes four semantic types:

- 开关 / Toggle
- 数值 / Number
- 按钮 / Action
- 滑杆 / Slider

Static ABI remains unchanged: `ZN44StaticEntry` stays 128 bytes. Control type is encoded in previously unused `entry.flags` bits 8..10. Legacy outputs have those bits zero and remain Toggle.

Runtime generic surfaces:

- Toggle: existing Static Dispatch behavior.
- Number: numeric text field, persistent value, emits `ZNFeatureNumberValueDidChangeNotification`.
- Action: one-shot `执行` button, emits `ZNFeatureActionRequestedNotification` once per tap.
- Slider: runtime slider, persistent value, emits `ZNFeatureSliderValueDidChangeNotification`.

Important boundary: Number/Action/Slider are generic model + UI + event surfaces only in M2.2. They are **not yet bound to arbitrary IL2CPP Hook/Invoke semantics**. Later runtime backends should subscribe/bind to these generic events rather than special-casing game feature names.

## Stable Search -> Cancel fix

File: `src/ZNIL2CPPMethodFinderM22StableCancelUX.mm`.

M2.2 behavior:

- initial search gets one full render, allowing the primary action to enter Cancel state;
- while the M2 token remains active and Method Finder is visible, progress updates modify the existing status label only;
- the complete Method Finder page is not rebuilt on every shard/progress event;
- completion/cancel/navigation performs a normal full render.

Goal: remove visible flashing without intentionally slowing search.

## M2.2 CI evidence

Run `34893082122` passed all steps:

- source assertions;
- Named Offset parser test;
- Static Payload Protection V2 test;
- Static RVA Protection test;
- Theos arm64 build/link/sign;
- binary marker verification;
- one-constructor check (`__TEXT,__init_offsets == 4`);
- artifact upload.

First M2.2 build attempt `34892550447` failed at real clang compile because a new file accidentally redeclared the already-existing `ZNFeatureControlType` with a different underlying type. The error was fixed by extending/reusing the project's original enum instead of redefining it. Successful runtime product source: `19b912c...`.

Independent artifact verification:

- ZIP SHA256: `4d632a38efb92a53ce492d07b6c6160f06193adffe37cdc3ca4c7d9e00bacaf5`
- Dylib SHA256: `4a42a698af2bcc0926a28413b8f6099215db2a8899747139f1018b284ba40bae`
- Dylib size: `784656`
- thin arm64 Mach-O dylib
- `__TEXT,__init_offsets` size `4`
- markers present: `v3-candidate-list`, `m2-wide-index`, `ZNMethodFinderPrimaryCancel`, `ZNFeatureActionRequestedNotification`, `ZNFeatureNumberValueDidChangeNotification`.

## M2.2 device acceptance

After installing/testing the delivered M2.2 build, the user reported on 2026-09-15: `目前没问题了。`

State to carry forward:

- mark M2.2 runtime source `19b912c...` as the current **device-accepted baseline**;
- do not claim every subtest was independently itemized, because the user gave an aggregate acceptance report rather than a per-step checklist;
- `full_regression_verified` remains false until a future explicit full regression is performed;
- do not modify or rewrite the M2.2 product history when starting the next milestone.

## CI routing

Feature-branch Actions registration previously produced synthetic `BuildFailed / startup_failure / 0 jobs` records. Working route is the workflow registered on `main` with checkout pinned to the exact feature source SHA. Do not confuse the `main` workflow commit with product source.

## Next milestone

M2.2 is accepted. Start the next milestone from runtime product `19b912c...` on a new branch rather than piling new runtime behavior onto the accepted branch.

Recommended next scope: bind the generic Number / Action / Slider controls to validated runtime backends, then continue toward the jailbreak IL2CPP debugger roadmap (Return Override / Inline Hook / Trace), while preserving the existing M2.2 Builder and Method Finder behavior.
