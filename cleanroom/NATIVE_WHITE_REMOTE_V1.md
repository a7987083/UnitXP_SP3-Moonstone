# Native white team synchronization v1

This stage connects the verified native white MoonBeam to the existing addon
team-message path. It intentionally changes only white `RemoteMark` behavior.

## Behavior

- `UnitXP("RemoteMark", "white", x, y, z)` and
  `UnitXP("MoonMarker.Remote", "white", x, y, z)` create the native world M2 at
  the received coordinate with the same `+0.05` Z offset as local placement.
- The received white slot remains visible to `QueryMarks`, while the old PNG
  overlay stays disabled.
- A later white placement replaces the previous native white instance.
- If native creation fails, the received white record is removed and the API
  returns `false`; it does not leave a misleading PNG fallback behind.
- Addon messages sent by the local player are ignored on receipt, preventing the
  sender from recreating and restarting its own native model.
- The existing leader/assistant/party-leader send restriction is unchanged.
- Synchronized `CLEAR` removes the native model and all marker records.

## Deliberately unchanged

- Red, yellow, green, blue, purple and orange still use the 2D fallback.
- This stage still supports only one native white instance.
- There is no periodic authoritative resynchronization yet, so a player joining
  after placement will not receive the existing white marker until it is placed
  again.
- Native model scale, animation, materials and particles are unchanged.

## Two-client in-game test

Both clients must install the DLL and the packaged MoonMarker addon.

1. Form a party or raid and let the leader/assistant place white.
2. Confirm both clients show one native beam at the same world coordinate and
   neither client shows the old PNG beam.
3. On both clients, run `UnitXP("QueryMarks")`; expect one white record.
4. Run `/mmstatus`; with only white active, expect `record=1` and `projected=0`.
5. Move white to a second position and confirm the old instance disappears on
   both clients.
6. Clear from the leader/assistant and confirm both clients remove the model.
7. Confirm an ordinary group member cannot broadcast placement through the
   toolbar or slash command.

This stage is not considered runtime-confirmed until the two-client checks pass.
