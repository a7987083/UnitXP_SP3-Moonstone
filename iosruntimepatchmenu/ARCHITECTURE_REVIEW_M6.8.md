# M6.8 Architecture Review & Refactor Plan

Baseline: `b72c2a271c703e494397f680c327a26a6cf275f5`  
Refactor branch: `refactor/m6.8-architecture-cleanup-v1`

## 1. Architecture summary

### Activation
`ZNDeferredBootstrap.mm` owns the cold constructor and activates the menu in deferred stages. The active chain installs the runtime menu, feature UI, named-offset workspace, builder UI, runtime-method builder UI, unified method finder, and M6.3 hard-cut UI before showing the menu.

### Authoring model
There are three independent authoring sources:
1. Static patches: `ZNBinaryPatchWorkspace`
2. Runtime method calls: `ZNRuntimeActionStore`
3. IL2CPP Native Hooks: `ZNNativeHookStore`

The Builder must combine these sources without making one feature type depend on another.

### IL2CPP discovery/execution
`ZNIL2CPPResolver`, `ZNIL2CPPHybridFinder`, ABI metadata, instance resolution, invoke engine, and finder UI resolve managed identity to MethodInfo/methodPointer and expose test/capture workflows.

### Native Hook subsystem
`ZNNativeHookAction` is the persisted authoring model. `ZNNativeHookRuntime` resolves descriptors, owns hook slots/diagnostics, and dispatches template-specific behavior. `ZNNativeHookBackend` isolates Dobby. ARM64 bridges preserve call-state for generic argument/field transforms.

### Binary generation
`ZNStaticBinaryPipeline` selects runtime-only vs static/mixed generation, invokes the appropriate Mach-O builder, embeds Runtime Method/Native Hook records, augments signatures, verifies runtime-only output, and runs signing/post-processing.

### Generated runtime
Generated metadata is embedded in owned `__ZNDATA/__zndata`. Runtime scanners rebuild Static/Runtime/Native-Hook controls from the generated binary; authoring JSON is not required at runtime.

## 2. Priority issues

### P0 — Distributed builder policy
The same concepts (complete static rows, runtime authoring present, native hooks present, runtime-only mode, build readiness) were independently recomputed in:
- `ZNFeatureBuilderUI.mm`
- `ZNRuntimeMethodCallBuilderUI.mm`
- `ZNM57RuntimeOnlyBuilderGate.mm`
- `ZNStaticBinaryPipeline.mm`

This permits UI and pipeline state to disagree.

**Refactor:** centralize in `ZNBuilderPolicy`; preserve separate historical UI and strict-gate semantics explicitly.

### P0 — Implicit UI composition through swizzles
Multiple categories exchange implementations on the same controller. Correct behavior depends on installation order and whether a particular installer is actually called.

`ZNM57RuntimeOnlyBuilderGate.mm` is present in the source tree, but the current `ZNDeferredBootstrap.mm` activation stages do not install it. This is a concrete example of source/runtime drift.

**Plan:** introduce an explicit activation registry with testable stage inventory before changing installer behavior.

### P1 — Large multi-responsibility files
Current large hotspots include:
- `ZonoeRuntimeMenu.mm` (~129 KB)
- `ZNNativeHookRuntime.mm` (~72 KB)
- `ZNM52ChainExecuteButton.mm` (~54 KB)
- `ZNStaticBinaryBuilderV3.mm` (~63 KB)
- `ZNIL2CPPMethodFinderM2.mm` (~52 KB)

They mix policy, state, UIKit, parsing, hook ABI, and diagnostics.

**Plan:** split by stable responsibility, not milestone number.

### P1 — Milestone-named production layers
Many live files are named `ZNM44...`, `ZNM52...`, `ZNM630...`. This records history but obscures current ownership and makes obsolete layers hard to distinguish from active layers.

**Plan:** migrate active responsibilities to stable subsystem names, leave compatibility shims temporarily, then delete dead layers after activation-contract tests exist.

### P1 — State is read directly from multiple singletons
UI renderers independently read workspace/store singletons. A render can therefore use snapshots taken at different moments.

**Plan:** add one immutable authoring snapshot object per render/build operation.

### P1 — Dead/alternate implementation artifacts
The repository contains `ZNArgScaleBridgeArm64.S`, `ZNArgScaleBridgeArm64.s`, and `ZNArgScaleBridgeArm64.mm`; only the ObjC++ bridge is in the Makefile. Alternate files increase maintenance ambiguity.

**Plan:** archive/delete unused variants after binary-equivalence/history check.

### P2 — Full-view rebuilds
Builder/finder UIs commonly remove/recreate view hierarchies on state changes. This is simple but scales poorly and makes post-render mutation fragile.

**Plan:** move to section view-models and update only affected controls once behavior contracts are locked.

### P2 — Tests are strong on low-level contracts, weak on composition
Existing tests cover ABI helpers, metadata codecs, payload protection, and source assertions, but there is no integration-level contract for:
- activation-stage inventory/order,
- Builder readiness across all authoring types,
- authoring -> embed -> generated runtime round-trip,
- Native Hook UI eligibility vs Runtime eligibility.

## 3. Refactor sequence

### Phase A — Policy extraction (this branch)
- Add `ZNBuilderPolicy`.
- Centralize Static-row counting and Runtime/Native-Hook presence.
- Keep main authoring UI readiness and legacy strict-gate readiness as separate named outputs.
- Make `ZNStaticBinaryPipeline` consume the same mode decision.
- Add pure regression tests.

### Phase B — Activation registry
- Replace loose extern/install calls with a table of named activation stages.
- Add a test that lists active installers and catches compiled-but-never-installed modules.
- No swizzle removal yet.

### Phase C — Native Hook decomposition
Split `ZNNativeHookRuntime.mm` into:
- descriptor/ABI resolver,
- hook-slot registry,
- template handlers,
- diagnostics,
- generated-action decoder.

Keep `ZNNativeHookBackend` as the only Dobby-facing layer.

### Phase D — Finder/UI decomposition
Separate candidate analysis, template eligibility, test-session state, and UIKit presentation. UI must consume a view model rather than recomputing eligibility.

### Phase E — Builder pipeline decomposition
Separate:
- mode/readiness policy,
- Mach-O generation,
- runtime-action embedding,
- verification,
- signing/postprocess.

### Phase F — remove historical shims
After activation and round-trip tests exist, remove dead milestone layers and unused bridge source variants.

## 4. Behavior-preservation tests added

`tests/builder_policy_test.mm` locks:
- empty authoring -> disabled,
- Runtime Method-only -> runtime-only + buildable,
- Native Hook-only -> runtime-only + buildable,
- Runtime + Native Hook -> runtime-only,
- partial Static drafts + Native Hook -> still runtime-only,
- complete unvalidated Static -> historical main UI remains buildable while strict legacy gate remains blocked,
- validated Static -> strict gate buildable,
- Static + Runtime/Hook -> static/mixed,
- building/applied workspace -> disabled.

The distinction between `authoringUIReady` and `strictGateReady` is intentional: it records existing semantics rather than silently choosing one during refactor.

## 5. Non-goals for this phase

This branch does not intentionally change:
- Hook ABI,
- Dobby behavior,
- Resolver behavior,
- generated metadata format,
- UI layout,
- signing,
- runtime feature semantics,
- the unresolved Builder-button device symptom.

The first objective is to make future fixes occur in one policy path instead of several competing paths.
