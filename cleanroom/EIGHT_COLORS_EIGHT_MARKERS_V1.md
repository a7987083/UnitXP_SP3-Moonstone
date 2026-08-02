# MoonMarker native M2: eight colors and eight markers

This stage expands the confirmed native white MoonBeam implementation into eight
independent native color slots and adds a fixed-size marker above each beam.

## Colors

`red`, `orange`, `yellow`, `green`, `cyan`, `blue`, `purple`, `white`

## Markers

`star`, `circle`, `diamond`, `triangle`, `moon`, `square`, `cross`, `skull`

Colors and markers are independent, providing 64 combinations.

## Lua API

```lua
-- Mouse-ground placement. Returns x, y, z, normalizedColor, normalizedMarker.
UnitXP("MoonMarker.Place", "red", "skull")
UnitXP("2DMark", "blue", "square")

-- Team-received placement. The sixth argument is optional for compatibility.
UnitXP("MoonMarker.Remote", "green", x, y, z, "triangle")

UnitXP("ClearAllMarks")
```

## Rendering design

- The beam remains `Spells\\MoonBeam_Impact_Base.mdx` in the client's native M2 scene.
- One native M2 instance is maintained per color, matching the original one-marker-per-color behavior.
- The DLL applies the selected RGB value through the client's model color method.
- The marker is procedural Direct3D geometry cached during `sceneEnd` and rendered
  immediately before `Present`; no Lua `PlayerModel`, custom MPQ, or binary texture is required.
- Marker size is fixed in screen pixels and remains readable at distance.
- Old team messages without a marker are accepted and use the color's default marker.

## First runtime validation

1. Install the DLL and packaged MoonMarker addon on two clients.
2. Place all eight colors with different markers.
3. Confirm all eight beams coexist and moving one color replaces only that color.
4. Confirm each marker remains attached above its beam while rotating the camera.
5. Confirm team synchronization preserves color, marker and coordinates.
6. Confirm `/mmclear` removes all sixteen visual objects (eight beams and markers).
7. Check whether all MoonBeam particles accept runtime color multiplication. If a
   particle remains white, the next stage must use color-specific model assets or
   a material-level hook rather than claiming full beam recoloring.
