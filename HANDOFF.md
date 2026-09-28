# HANDOFF

## NON-NEGOTIABLE UI ARCHITECTURE RULE

The customer Feature surface MUST use exactly one canonical renderer.

- No stacked/nested/multi-layer Feature renderers.
- No multiple swizzles of the same customer Feature render selector.
- No "render first, then later layer moves/hides/renames/rebuilds the same cards" pattern.
- No second Feature `contentView`, second Feature scroll view, second Feature controller, overlay hierarchy, or delayed post-processing UI installer.
- Runtime / Offset / legacy Static compatibility data must be normalized before rendering and then rendered once.
- Legacy UI source may remain only when it is inactive for the customer Feature surface.
- Any UI hotfix that needs another renderer layer is invalid.

This is enforced by `iosruntimepatchmenu/tools/validate_single_ui_renderer.py` and documented in `iosruntimepatchmenu/docs/UI_ARCHITECTURE_CONTRACT.md`. CI must fail before compilation when this contract is violated. There is no hotfix exception.

Current M6.2 source is known to violate this rule because historical Runtime UI swizzles remain active. M6.3 must first collapse them into one canonical renderer marked exactly `ZN_UI_CANONICAL_FEATURE_RENDERER`; only then may the build pass the UI architecture gate.

## Current work line

ZonoPatch Runtime Patch Menu — moving from M6.2 to **M6.3 Single Unified Renderer**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch at contract introduction: `feature/m6.2-unified-authoring-ui`
- M6.2 device feedback: Description authoring changed, but customer menu still displayed duplicate parameter text because the final customer Feature surface still had multiple historical renderer/swizzle layers.
- Product decision: remove new-authoring raw ARM64 HEX Patch/Enabled entry; preserve legacy Static binary read/compatibility only.

## Preserved behavior

- Runtime Action semantics remain canonical.
- Offset that resolves to an exact IL2CPP method should converge to the Runtime backend.
- Slider authored max semantics remain `min=0`, `max=<authored value>`, `step=1`.
- Runtime and Static binary ABI compatibility must remain readable unless explicitly migrated.

## Immediate next phase

M6.3 — Single Unified Renderer:

1. Remove/disable historical customer Feature UI layers from the active install chain.
2. Introduce exactly one canonical Feature renderer owner.
3. Normalize Runtime + compatible legacy Static records into one presentation model before rendering.
4. Render customer cards directly as `功能名 + 说明 + 控件`; do not create parameter labels and hide them later.
5. Remove new-authoring raw Patch/Enabled UI while keeping legacy Static binary compatibility.
6. Make the single-renderer CI gate pass before build, binary verification, artifact publication, or device release.
