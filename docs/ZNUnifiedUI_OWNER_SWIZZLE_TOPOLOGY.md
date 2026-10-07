# ZNUnifiedUI.mm Owner / Swizzle Topology Audit

Baseline:

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `refactor/m6.13.3-znunifiedui-audit-v1`
- HEAD audited: `1aa8bbe6b1ef0b001493b3b8a39fb70995425222`
- File: `iosruntimepatchmenu/src/ZNUnifiedUI.mm`
- Lines: 18,584
- `@implementation`: 80
- Category implementations: 71
- `method_exchangeImplementations` call sites: 62
- `method_setImplementation` call sites: 8
- `dispatch_once` call sites: 58

> Counts above describe syntax/call sites in the audited file. One exchange helper can be invoked multiple times; the selector-edge graph is therefore larger than the raw exchange call-site count.

## 1. Root ownership model

The file is still physically a "single UI owner", but runtime behavior is not single-owner.

The dominant runtime class is:

`ZNRuntimeMenuControllerV040`

Most historical layers are Objective-C categories on this same class. They do not form independent renderers; they mutate the same selector table at runtime.

Other real owners still present in this translation unit include:

- `ZNRuntimeMenuModalViewController`
- `ZNUXOverlayController`
- `ZN50FeatureToggleControl`
- `ZNM53StaticControlBinder`
- `ZNStaticBinaryBuilder`
- `ZNM56StaticValueCellBinder`

The important distinction for refactoring is:

- **physical owner** = class/category that contains the implementation;
- **runtime owner** = selector whose IMP is active after all installers have run;
- **chain node** = historical selector retained only so an exchanged implementation can call the previous layer.

Do not split a category only because it has a unique name. A category is safe to move only when its methods are not part of an active exchange/set-IMP chain, or when the entire chain contract moves with it.

## 2. Actual bootstrap order

`ZNDeferredBootstrap.mm` owns activation.

Cold activation stage:

```text
SharedSiteExecutionProbeV3
-> PublicCompactLayout
-> RuntimeExecutorV041
-> RuntimeDiagnosticsV042
-> StaticDispatchPrepare
```

Menu prewarm stage:

```text
RuntimeMenuV055
-> FeatureGroupUI
-> PublicCompactDefaults
-> IL2CPPNamedOffsetWorkspace
-> FeatureBuilderUI
-> RuntimeMethodCallBuilderUI
-> MethodFinderUnifiedUI
-> M630HardCutUI
-> ZonoePatchStart
```

The large nested legacy install graph is entered from the menu/runtime installer family. In particular,
`ZNInstallIL2CPPMethodFinderMenuBindingDeferred` expands into many M4x/M5x/M6x deferred installers.

## 3. High-risk selector chains

### makeUI:

The base selector is repeatedly exchanged in historical order:

```text
makeUI:
<-> zn40_makeUI:
<-> zn401_makeUI:
<-> zn402_makeUI:
<-> zn42_makeUI:
<-> zn43_makeUI:
<-> zn44_makeUI:
<-> zn48_makeUI:
<-> zn49_makeUI:
<-> zn53_makeUI:
```

This is a classic nested-swizzle chain. Each replacement may call its own selector name to reach the prior IMP.

**Rule:** do not delete, rename, or move one node independently until the final IMP and all predecessor calls are proven.

### tick:

```text
tick:
<-> zn40_tick:
<-> zn43_tick:
<-> zn44_tick:
<-> zn48_tick:
<-> zn49_tick:
<-> zn53_tick:
<-> znm47_tick:
```

This chain is directly related to historical UI refresh / polling behavior. It must be treated as one lifecycle chain, not as independent version patches.

### renderPage

```text
renderPage
<-> zn402_renderPage
<-> zn53_renderPage
<-> zn63m22_renderPage
<-> znm461_renderPage
```

The exact active IMP depends on install order because all exchanges target the same base selector.

### renderFullPage

Observed exchange edges:

```text
renderFullPage <-> zn40_renderFullPage
renderFullPage <-> zn44_renderFullPage
renderFullPage <-> zn53_renderFullPage
renderFullPage <-> zn50_renderFullPage
renderFullPage <-> zn57mf_renderFullPage
```

M6.30 then changes the ownership model:

```text
renderFullPage
  -> method_setImplementation(ZNM630HardCutFullPage)
```

Before replacement, M6.30 captures the previous active IMP in:

`gZNM630PreviousFullPageIMP`

and calls it for every category except `功能`.

Therefore **M6.30 is the final owner of `renderFullPage` for the feature page path**, while the captured predecessor remains part of the live chain for non-feature pages.

### renderCompactPage

```text
renderCompactPage <-> zn50_renderCompactPage
renderCompactPage -> method_setImplementation(znm630_hardCutRenderCompactPage)
```

Unlike full-page rendering, M6.30 compact mode does not keep an explicit previous-IMP fallback at the final replacement point.

### layoutPanel / layoutSidebar

```text
layoutPanel <-> znpublic_layoutPanel
layoutPanel -> method_setImplementation(znm584_layoutPanel)

layoutSidebar -> method_setImplementation(znm584_layoutSidebar)
```

The M6.584 Scheme-A layer is the final explicit IMP owner for these layout selectors in the audited source.

### Runtime feature renderer

```text
zn51_renderRuntime:
  -> set IMP znm584_renderRuntime:
  -> set IMP znm58_renderRuntime:
  <-> znm600_renderRuntime:
```

This is a mixed **set-IMP + exchange** chain. It is higher risk than a pure swizzle chain because the earlier IMP relationship is no longer recoverable by assuming normal exchange symmetry.

### Builder UI

Two historical roots coexist:

`zn50b_renderOther` receives multiple exchange layers:

```text
zn50b_renderOther
<-> zn64fb_renderOther
<-> znrmc_renderOther
<-> znm47b_renderOther
<-> zn51_builderRender
<-> znm55_builderRender
<-> znm57_renderOtherWithRuntimeOnlyGate
```

Separately, `zn64fb_renderOther` is also used as an exchange anchor by later layers:

```text
zn64fb_renderOther
<-> znm585_renderOther
<-> znm590_renderOther
<-> znm591_renderOther
```

This is not safe to reason about as a simple linear chain without install order. It is a shared anchor graph.

### Method Finder

Search renderer:

```text
zn60v3_renderSearchAtWidth:
<-> zn61m2_renderSearchAtWidth:
<-> zn62m21_renderSearchAtWidth:
<-> znm43_renderSearchAtWidth:
<-> znm43p_renderSearchAtWidth:
<-> znm441_renderSearchAtWidth:
<-> znm442_renderSearchAtWidth:
<-> znm54_renderSearchAtWidth:
```

Results renderer is the densest live chain:

```text
zn60v3_renderResultsAtWidth:
<-> znm42_renderResultsAtWidth:
<-> znm43_renderResultsAtWidth:
<-> znm43p_renderResultsAtWidth:
<-> znm441_renderResultsAtWidth:
<-> znm45_renderResultsAtWidth:
<-> znm46_renderResultsAtWidth:
<-> znm461_renderResultsAtWidth:
<-> znm462_renderResultsAtWidth:
<-> znm47_renderResultsAtWidth:
<-> znm47ma_renderResultsAtWidth:
<-> znm54_renderResultsAtWidth:
<-> zn51_finderRender:
<-> zn52x_renderResultsAtWidth:
```

Detail renderer:

```text
zn60v3_renderDetailAtWidth:
<-> zn65abi_renderDetailAtWidth:
<-> znrmc_renderDetailAtWidth:
<-> znm43_renderDetailAtWidth:
<-> znm45_renderDetailAtWidth:
<-> znm54_renderDetailAtWidth:
```

These three chains should be considered one Method Finder ownership domain when the controller is eventually split.

## 4. Final-IMP overrides found

The audited file contains eight `method_setImplementation` call sites.

The important final-ownership overrides are:

- `zn51_runtimeSliderChanged:` -> `znm562_sliderChangedIsolated:`
- `layoutPanel` -> `znm584_layoutPanel`
- `layoutSidebar` -> `znm584_layoutSidebar`
- `zn51_renderRuntime:` -> `znm584_renderRuntime:`, later -> `znm58_renderRuntime:`
- `renderFullPage` -> `ZNM630HardCutFullPage`
- `renderCompactPage` -> `znm630_hardCutRenderCompactPage`

Any cleanup that follows only exchange pairs and ignores these replacements will calculate the wrong final owner.

## 5. Safe extraction classes

Already extracted before this audit and still structurally valid:

- `ZNRangeControl.mm`
- `ZNM55StaticTypedBinding.mm`
- `ZNM56StaticValueCellBinding.mm`
- `ZNDeferredBootstrap.mm`

These are the correct pattern: unique owner, no live UI selector takeover chain, no hidden constructor/swizzle dependency moved independently.

For the next extractions, prefer classes/helpers with all of the following:

- unique Objective-C owner;
- no `method_exchangeImplementations`;
- no `method_setImplementation`;
- no installer that mutates `ZNRuntimeMenuControllerV040`;
- no selector used as a historical swizzle anchor;
- no constructor;
- caller/import dependency can be moved without changing activation order.

## 6. Do-not-split-yet domains

Until selector-final-IMP tests exist, keep these together:

- `makeUI:` lifecycle chain
- `tick:` lifecycle chain
- `renderPage` chain
- `renderFullPage` / `renderCompactPage` including M6.30 hard-cut
- `layoutPanel` / `layoutSidebar`
- Builder render graph around `zn50b_renderOther` and `zn64fb_renderOther`
- Method Finder Search / Results / Detail render graph
- Runtime feature renderer around `zn51_renderRuntime:`

These are the current technical-debt core; moving them piecemeal is more likely to alter behavior than reduce risk.

## 7. Required contract before deleting a historical swizzle

For each selector, record:

```text
selector
base implementation
installer order
exchange/set-IMP edges
final active IMP
previous-IMP fallback (if any)
replacement selector self-call behavior
```

Then validate:

1. selector final-IMP identity before/after refactor;
2. predecessor-call topology before/after;
3. installer order unchanged;
4. no duplicate install;
5. full build;
6. real-device behavior for the affected UI domain.

Only after these contracts pass should a historical swizzle be deleted rather than merely moved.

## 8. Immediate conclusion

The file is ready for **continued extraction of independent owners**, but not yet for broad swizzle deletion.

The biggest structural debt is concentrated in `ZNRuntimeMenuControllerV040` categories, not in the already-extracted helper/control owners.

The safe refactor order remains:

```text
independent owner extraction
-> freeze final selector/IMP map
-> split controller by functional domain
-> delete historical swizzles one chain at a time
```

Do not reverse this order.
