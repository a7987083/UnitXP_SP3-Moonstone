# ROADMAP

## Current milestone — M5.4 Unified Method Finder

Branch: `refactor/method-finder-ui-consolidation-m5.4`

CI-validated head: `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845`  
Product-code head before CI-only verification change: `eff4f4d86c1851558e703addb89ed86578259a64`

### Why M5.4 exists

Device testing showed that repeated M5.2/M5.3 search-history fixes compiled and installed but were not reliably visible. Architecture audit confirmed that Method Finder had accumulated multiple UI generations on one `ZNRuntimeMenuControllerV040`, with repeated `method_exchangeImplementations`, post-render view walking, title-based button discovery, and target rebinding. Runtime behavior depended on install order.

The detailed audit is in `METHOD_FINDER_UI_AUDIT.md`.

### Implemented

- Added `ZNMethodFinderUnifiedUI.mm` as the single final Search / Results / Detail renderer.
- Unified renderer intentionally does **not** call the previous renderer implementation, cutting the legacy renderer chain at runtime.
- V3 query/candidate/page/limit/status state and existing resolver/invoke backends are retained.
- Old M4.3/M4.4/M4.7 render wrappers remain compiled only for compatibility/backends but are buried below the Unified renderer and no longer own the final base layout.
- Narrow post-render behavior decorators remain after Unified where required:
  - M4.6.2 candidate binding for Test actions.
  - M4.7 receiver-capture long press.
  - M5.1/M5.2 chain create/execute/restart behavior.
- Old `ZNInstallM52MethodSearchHistoryDeferred()` is no longer installed.
- Search history is now part of the Unified Search renderer itself:
  - same persistent key `zonoe.m52.method-search-history.v1`;
  - maximum 50;
  - newest first;
  - case-insensitive dedupe;
  - one row per query;
  - independently scrollable;
  - tapping a row only fills the 方法名 field and does not execute search.
- Unified Results directly renders typed `/0-/8` argument rows rather than rendering older `/0-/1` cards and mutating them afterward.
- Unified Detail directly renders method/ABI/ownership information.
- M5.3 Runtime Control Binding, Static Control Binding, M5.2 Chain V2, Return Capture and customer silent-success behavior are retained below/around the new UI path.
- Static Entry ABI remains 128 bytes; Runtime Action ABI remains 64 bytes.

### CI history

- Run `35964177732`: first compile failed in `ZNIL2CPPMethodFinderMenuBinding.mm` because the new install-graph log referenced `ZNRuntimeLogger` without importing `ZNPatchCore.h`; fixed without architecture change.
- Run `35964480222`: arm64 Build/Link/Sign succeeded; Binary Verify failed only because `strings -a` cannot reliably match Chinese Objective-C CFString constants.
- Final Run `35964757740` / Job `107520782444`: Source Contract, arm64 Build, Binary Verify and Artifact Upload all SUCCESS.

### Final artifact

- Artifact: `ZonoPatch-v0.5.8-M5.4-Unified-Method-Finder`
- Artifact ID: `10793662459`
- Artifact ZIP SHA256: `b607318f0225a2b4e1203ca30a151913c22eeb79e13a0519f42b1f13d769af6b`
- Dylib: `ZonoPatch_v0.5.8_M5.4_Unified_Method_Finder.dylib`
- Dylib size: `1354480` bytes
- Dylib SHA256: `6804ca2f2a242337f8a81eb20125e5b0867bd59add02b9df0e28a35656f37ca2`
- Mach-O: thin arm64 dynamically linked shared library
- Independent downloaded ZIP/dylib hash verification: PASS
- Previous M5.3 HistoryFix was `1337776` bytes / `bd7ca8773dca7e26ef989821c3aea3a5454cffc94d6cf0039ddb35cbb7dff1dc`; M5.4 is a different binary.

### Device acceptance status

- Initial device evidence received on 2026-09-24: the previously missing Unified/search-history UI is now visible on device.
- This closes the specific blocker that motivated M5.4: the final Unified renderer is now reaching the real device UI and the history surface is no longer hidden behind the legacy renderer chain.
- Remaining interaction/regression items below are **not** yet marked passed from this evidence alone.

### Remaining device acceptance

1. Tap a history row; confirm only 方法名 is filled and no automatic search occurs.
2. Manually press 搜索 and confirm the autofilled query executes normally.
3. Confirm `/0-/8` candidates render argument rows correctly and overload filtering still works.
4. Test/捕获 must still target the selected candidate; long-press receiver capture must remain functional.
5. 创建方法 must still add the correct Runtime Action.
6. Chain flow must regress cleanly: 链式调用 -> 完成链 -> 执行链; long-press 执行链 restarts authoring.
7. Regress M5.3 Runtime Button/Switch/Number/Slider behavior and Static controls.
8. Regress detail page, Return Capture, customer silent success/failure alert, and suffixless generated binary flow.

### Next engineering step after device evidence

- Continue the interaction/regression checklist above.
- After the Unified path is accepted beyond visibility, split mixed legacy installer files into explicit backend modules vs deprecated renderer modules and stop compiling obsolete renderer implementations in a later cleanup milestone.
- Do not add any new Method Finder base-renderer swizzle. New features must be state/backend methods, explicit Unified renderer code, or narrowly scoped behavior decorators.
