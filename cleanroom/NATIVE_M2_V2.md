# Native M2 test v2

This stage keeps the verified 2D marker renderer unchanged and adds an isolated
native-world test API for `Spells\MoonBeam_Impact_Base.mdx`.

## Recovered client chain

The relevant 1.12.1 client path is:

1. `0x00707350(context, path, flags)` creates a `CM2Model` and links it to the
   context's ownership list.
2. `0x00710620(model, matrix)` copies the complete 4x4 world matrix.
3. `0x007121A0(...)` initializes or queues the animation sequence.
4. `0x00710C50(model, 1)` records the model as active for the current scene tick.
5. `0x00710B90(model, 1)` links the model into the context's active render list.
6. `0x00710450(model, requestLoad, recursive)` reports full render-resource
   readiness.
7. `0x007103A0(model)` releases the model; the destructor unlinks it from the
   context lists.

The failed first implementation stopped after step 3. A valid returned model
pointer therefore did not mean the instance had entered the active render list.

## Runtime APIs

- `UnitXP("M2Test")`: creates one white MoonBeam four yards in front of the player.
- `UnitXP("M2Status")`: returns a diagnostic table.
- `UnitXP("M2Clear")`: detaches and releases the test model.

The status table includes context, creation, readiness, render-list, update and
release counters. This code is still a runtime test until an in-game screenshot
confirms that the native M2 is visible.
