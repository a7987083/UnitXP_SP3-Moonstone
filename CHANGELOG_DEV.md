# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.4 Unified Method Finder

Branch: `refactor/method-finder-ui-consolidation-m5.4`

CI-validated head: `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845`  
Product-code head: `eff4f4d86c1851558e703addb89ed86578259a64`

### Architecture audit

- Added `METHOD_FINDER_UI_AUDIT.md`.
- Confirmed multiple Method Finder generations were installed simultaneously on `ZNRuntimeMenuControllerV040`.
- Confirmed repeated swizzles of `zn60v3_renderSearchAtWidth:`, `zn60v3_startSearch:`, `zn60v3_renderResultsAtWidth:` and `zn60v3_renderDetailAtWidth:`.
- Confirmed M4.4.1 performs view-tree search + `removeTarget:nil action:NULL` + target rebinding.
- Confirmed later layers depended on the post-swizzle meaning of earlier selector aliases.
- Confirmed some installers mix backend behavior and UI mutation, so whole-module disable would remove required runtime functionality.

### Refactor implemented

- Added `iosruntimepatchmenu/src/ZNMethodFinderUnifiedUI.mm`.
- Added one final non-chaining Search / Results / Detail renderer.
- Reordered `ZNIL2CPPMethodFinderMenuBinding.mm` so backend/state layers install first, Unified installs after them, and only narrow behavior decorators install outside Unified.
- Removed `ZNInstallM52MethodSearchHistoryDeferred()` from the runtime install path; its file remains compiled for compatibility but is inactive.
- Search history moved into Unified Search renderer itself; max 50, persistent, newest-first, case-insensitive dedupe, independently scrollable.
- History row tap now only updates Finder query + visible 方法名 field; no automatic search.
- Unified Search retains Assembly selection and editable result limit and routes submit through existing M4.4.2/M4.5-compatible search backend.
- Unified Results directly renders `/0-/8` argument rows from ABI metadata and preserves existing argument-store key conventions.
- Unified Results keeps visible `测试执行` / `创建方法` controls so M4.6.2 candidate binding, receiver capture and M5.1/M5.2 chain behavior remain compatible.
- Unified Detail renders canonical method metadata, ABI return/parameter information and owning-method metadata when present.
- Updated Makefile and version marker to `0.5.8 · M5.4` / `Unified Method Finder · Single Renderer · History 50`.
- Added dedicated workflow `.github/workflows/build-runtime-patch-menu-v0.5.8-m5.4-unified-method-finder.yml`.

### CI history

- Run `35964177732`: Build failed because new install-graph logging used `ZNRuntimeLogger` without importing `ZNPatchCore.h`; fixed by import only.
- Run `35964480222`: Build/Link/Sign SUCCESS; Verify failed on Chinese CFString `strings -a` assertion. Product dylib was generated; failure was CI verification-only.
- Run `35964757740` / Job `107520782444`: Source Contract, dependencies, Dobby arm64, Build M5.4, Binary Verify and Artifact Upload all SUCCESS.

### Final artifact

- Artifact: `ZonoPatch-v0.5.8-M5.4-Unified-Method-Finder`
- Artifact ID: `10793662459`
- Artifact ZIP SHA256: `b607318f0225a2b4e1203ca30a151913c22eeb79e13a0519f42b1f13d769af6b`
- Dylib: `ZonoPatch_v0.5.8_M5.4_Unified_Method_Finder.dylib`
- Dylib size: `1354480` bytes
- Dylib SHA256: `6804ca2f2a242337f8a81eb20125e5b0867bd59add02b9df0e28a35656f37ca2`
- Mach-O: thin arm64 dynamically linked shared library
- Downloaded ZIP digest matches GitHub Artifact digest; dylib hash matches Artifact `SHA256.txt`.
- This differs from the previous M5.3 HistoryFix (`1337776` bytes / `bd7ca8773dca7e26ef989821c3aea3a5454cffc94d6cf0039ddb35cbb7dff1dc`).

### Validation boundary

- architecture audit: DONE
- source refactor: DONE
- GitHub committed: YES
- arm64 compile/link/sign: YES
- Binary Verify: YES
- artifact independent hash verification: YES
- device confirms Unified title/page: PENDING
- Unified search history visible/autofill-only: PENDING
- `/0-/8` result rows regression: PENDING
- Test/candidate binding + receiver capture regression: PENDING
- Chain create/execute/long-press regression: PENDING
- M5.3 controls regression: PENDING
- full regression: NO

## Historical anchors

- M5.3 HistoryFix device-reported failure: product `064d535918cacd0f40a220521af7cad18a3d42d9`, dylib SHA `bd7ca8773dca7e26ef989821c3aea3a5454cffc94d6cf0039ddb35cbb7dff1dc`.
- M5.3 Control Binding initial green: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`.
- M5.2 core multi-level chain: `2456f6ba4dfb659e3480db2e677452dad8516153`.
- M5.1 Silent Customer Execution: `29c33d9246fd9842107c443d3254aff23effd59e`.
- M5.0 Managed-reference Return Chaining: `ec6ed852c24684cb92dbfc927afe16797eccbc0d`.
