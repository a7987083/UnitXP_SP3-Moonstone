# Native white cursor marker v1

This stage connects the verified persistent native MoonBeam to the existing
mouse-ground placement API without changing the other six colors.

## Behavior

- `UnitXP("2DMark", "white")` and `UnitXP("MoonMarker.Place", "white")`
  use the already verified game ground-cursor path.
- The returned marker coordinates remain the exact ground hit. The M2 receives
  a `+0.05` Z offset to avoid ground-surface fighting.
- The white slot remains visible to `QueryMarks`, but its old orthographic PNG
  projection is disabled.
- Replacing white releases the previous native instance before creating the new
  one, so only one white native marker can exist.
- `ClearAllMarks`, `MoonMarker.Clear`, `M2Clear`, world leave and DLL shutdown
  remove the native white instance safely.
- `M2Test` remains available and removes any stored white marker before running.

## Deliberately unchanged

- Red, yellow, green, blue, purple and orange still use the verified 2D fallback.
- `RemoteMark` is not converted to native M2 in this stage.
- Team synchronization behavior is not expanded in this stage.
- Native scale, animation, materials and particles remain the client's original
  `Spells\\MoonBeam_Impact_Base.mdx` behavior.

## In-game test

Test alone before testing in a group:

1. Run `UnitXP("2DMark", "white")` or click the white toolbar button.
2. Confirm one native beam appears at the mouse ground position with no PNG
   beam layered over it.
3. Place white at a second position and confirm the first instance disappears.
4. Run `UnitXP("QueryMarks")` and confirm one white entry with the selected
   ground coordinates.
5. Run `UnitXP("ClearAllMarks")` and confirm the model disappears.
6. Confirm camera rotation and mouse-look do not hide the model.

This package is a runtime test until those six checks are confirmed in game.
