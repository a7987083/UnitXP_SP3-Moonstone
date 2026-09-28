# UI Architecture Contract — Single Renderer Only

This rule is mandatory for all future ZonoPatch Runtime Patch Menu work.

## Hard invariant

The customer Feature surface MUST have exactly one renderer owner.

Prohibited:

- stacked/nested/multi-layer renderers for the same customer Feature surface;
- multiple swizzles of the same Feature rendering selector such as `zn51_renderRuntime:` or its successor;
- rendering a card and then letting a later layer move/hide/relabel/rebuild that same card;
- creating a second `contentView`, second Feature `UIScrollView`, second Feature controller, overlay Feature hierarchy, or delayed UI installer that post-processes the canonical Feature surface;
- adding a new M5.x/M6.x UI layer to patch the output of an earlier UI layer.

Required:

- one canonical Feature renderer owns creation, layout and final text of customer Feature cards;
- Runtime, Offset/Static compatibility records and future UnifiedFeature records are normalized as data before rendering;
- all visual changes must be made in the canonical renderer itself;
- legacy UI source files may remain for history/compatibility only if they are not active render layers for the customer Feature surface;
- Method Finder or other separate pages may have their own UI, but they must not stack another renderer on the customer Feature surface.

## CI gate

`iosruntimepatchmenu/tools/validate_single_ui_renderer.py` is a release-blocking check.

A build MUST fail before compilation when any of the following is true:

1. more than one compiled source owns/swizzles the protected customer Feature render selectors;
2. a protected Feature render selector is swizzled outside the one canonical renderer owner;
3. the compiled source set has no explicitly marked canonical Feature renderer;
4. more than one compiled source is marked as the canonical Feature renderer.

The canonical source must contain the exact marker:

`ZN_UI_CANONICAL_FEATURE_RENDERER`

There is no exception for hotfixes. A UI hotfix that requires another renderer/post-processing layer is architecturally invalid and must not pass CI.

## Protected customer Feature selectors

At minimum the validator protects:

- `zn51_renderRuntime:`
- `zn50b_renderOther`
- `renderPage`

The validator may expand this list as the unified renderer evolves.

## Migration note

M6.2 still contains historical stacked Runtime render swizzles. Under this contract it is intentionally non-compliant. M6.3 must first collapse the active customer Feature UI into one canonical renderer before any further UI feature work can be accepted.
