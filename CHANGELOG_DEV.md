# CHANGELOG_DEV

## 2026-09-18 — v0.8.0 Page Dependency Capture

Branch: `feature/network-capture-v0.8.0-page-dependency`  
Baseline: `521431ace1adc0067d28d690355f15c818c9e25a` (`v0.7.1 Snapshot Completeness`)  
Final compiled source/workflow commit: `e36faaa1233f10c4272859601f7309fc565738e7`

Added:
- `jsoncapture/scripts/apply_v080_page_dependency.py`.
- TXT whitelist import through `UIDocumentPickerViewController`.
- Mode 1 manual/passive page dependency capture.
- Mode 1 pre-navigation arming so initial page request traffic is not intentionally skipped.
- First new `UI*.lua` after arming becomes the page anchor; the already-current UI is ignored as the initial anchor.
- Mode 2 passive policy learning with independent storage and policy state.
- Runtime Completion Detector using a 1.8 s dependency-stability quiet window.
- New output root `runtime_page_dependency/` with `mode1_manual/` and `mode2_auto/`.
- Per-page dependency graph for configs, TABs, observed Model/Cache candidates, primary protocols, protocol candidates, and JSON endpoints.
- Conservative protocol attribution: page request and request-correlated response are primary; unmatched PUSH/ambiguous observations remain candidates.
- Conservative Mode 2 rule: `unknown` is never actively invoked.

Architecture/safety:
- Reuses the existing `gJCG5CaptureQueue`; no new dispatch queue.
- No new native hook target.
- No new constructor or `+load`.
- No TLS/TLV.
- No polling thread.
- No active request invocation path added.
- Mode 1 does not read Mode 2 policy.
- Existing v0.7.1 page/protobuf snapshot output remains enabled for A/B comparison.

Commits:
- `20c2ffbda93035c903418a2e5a81b63bf191135d` — add v0.8.0 page dependency patch.
- `7e97c4277a930c6a895dc61fd8eed5a6233466a1` — wire v0.8.0 patch into Makefile.
- `0a298ef851fb8f96842a7e72d0b8202afcb5ba1c` — remove implicit math dependency.
- `947c453dcf686cddd71fa2737ea12e3dd5b3b1f7` — add dedicated v0.8.0 CI build/invariant workflow.
- `4f625f735fff3d489eb94934b80d03c41f422268` — fix Mode 1 timing by arming before target-page navigation.
- `e36faaa1233f10c4272859601f7309fc565738e7` — add CI/source contract checks and package guidance for pre-navigation arming.

Validation:
- Initial build run `35294375167` passed but was superseded by the Mode 1 arming fix.
- Final source patch chain/contract checks: passed.
- Final Theos arm64 compile/link/sign: passed.
- Final GitHub Actions run: `35294784256` — success.
- Final GitHub Actions job: `105444977167` — success.
- Final Artifact ID: `10527791132`.
- Final Artifact digest: `sha256:da619c74950a80ea79f929a8bee8b41586c5153126ce3cb89dc84741f5b18fdf`.
- Final Dylib SHA256: `25897607cd2cd23740e1db648d88ed7c6a0ef84557b883ad8857c8ef8789c9d9`.
- Final Release ZIP SHA256: `0e1b9b6e2b4fd310dbbb0f490a9127cd07eb8c7083f7acef8fb6f823923b4a78`.
- Downloaded Artifact digest independently reproduced locally.
- Mach-O independently checked as 64-bit arm64 dylib.
- v0.8.0 arming/readiness strings independently confirmed in the built dylib.
- Real-device v0.8.0 validation: pending.
- Regression/device parity against v0.7.1: pending.

## 2026-09-17 — g4 Chinese UI + on-device JSON recovery

Branch: `feature/json-capture-v0.4.2-g4-chinese-ui-recovery`
Base: `d0c10fc1d4df1ab0e8151f4a91ae3bca050242f3` (g3 persistent incremental)

Added:
- `GenericG4ChineseUI.m`: Chinese compact floating overlay and control surface.
- `OnDeviceLuaRecovery.h/.m`: native ENCM re-decrypt + static Lua 5.3 -> JSON recovery.
- Capture-priority scheduling for historical re-decrypt and JSON recovery.
- Persistent mobile recovery/decrypt index, report and status files.
- Complete and partial JSON output directories.
- UI actions for scan control, force scan, re-decrypt, re-recover, incremental recovery, JSON directory, report export and index management.

Build fixes:
- Typed the UI label dictionary so keyed subscripting produces `UILabel *`.
- Suppressed one intentional unused helper warning that Theos promoted to an error.
- CI binary validation now uses ASCII markers; Chinese NSString literals are validated at source-contract stage.

Validation:
- Source contract: passed.
- Theos arm64 compile/link/sign: passed.
- GitHub Actions run: `35134708046` — success.
- Artifact source commit: `e1ab528ad2eadfd22fef56be48eb5baa06988081`.
- Dylib SHA256: `9a6c48526c0fbd8a2bb0333edc97f9e4b904f4e472b56af608eb23c76b76970c`.
- Release ZIP SHA256: `c994666cca1cedfc22ee07e55a00b815117ec26cd5de9764d06f3c55aff019d0`.
- Real-device g4 UI/recovery: pending.

Compatibility/safety:
- Keeps g3/g2 capture core and no game-specific fixed RVAs.
- Static recovery only; dynamic opcodes are classified rather than executed.
- Existing raw/decoded captures are never deleted by recovery-index operations.
