# DreamAvatar v0.3.3 · NPC weapon conversion, auto-maintain and party/raid sync

## NPC weapon fix

- NPC `UNIT_VIRTUAL_ITEM_SLOT_DISPLAY[0..2]` values are ItemDisplayInfo IDs.
- Player `PLAYER_VISIBLE_ITEM_*_0` values are Item Entry IDs.
- The client `DBFilesClient\\Item.dbc` is read through the existing SFile functions and the NPC display IDs are reverse-mapped to compatible main-hand, off-hand and ranged Item IDs before filling the player weapon inputs.
- An NPC-only display with no matching Item.dbc row is reported and filled as 0 instead of being written with the wrong ID type.

## Auto-maintain

Character, weapon, enchant-glow and mount pages each have an independent auto-maintain switch. The native layer re-applies only categories and slots that have an active local override. All maintain commands retain the normal DLL guild authorization.

## Compact UI and history

- Window reduced to 720 x 620.
- History shows three records per page.
- The weapon target-summary/footer block was removed.
- Weapon Apply Main/Off/Ranged/All no longer auto-create history. Weapon history is created only through Save Current.

## Party/raid synchronization

- The existing MoonMarker Base64, keyed MAC, sender binding, timestamp, nonce and replay-cache primitives are reused with an independent DreamAvatar packet version and domain.
- Any current party or raid member may send or receive DreamAvatar appearance packets. Leader, assistant and target-guild status are not required for synchronization.
- Manual local character, weapon, glow and mount actions continue to require the existing target-guild authorization in both Lua and the native command dispatcher.
- Incoming packets affect the sending player model seen by the receiver, not the receiver's own character.
- Receive Sync and Send Sync are independent SavedVariables switches.
- Disabling send broadcasts a signed clear snapshot. Disabling receive restores all remote appearances.
- Remote overrides are periodically re-applied while the sender remains in the current party or raid.

## Safety and scope

- Local visuals only; server equipment, enchants, mount and character data are not changed.
- No unit disable/enable calls were introduced.
- DreamAvatar remains independent of a MoonMarker AddOn TOC dependency.
- Synchronization integrity prevents malformed, stale and replayed packets under the existing shared-key model; it is not intended as cryptographic authorization against reverse engineering of the client DLL.
- Successful compilation and static checks do not replace in-game validation on the target Turtle WoW client build.
