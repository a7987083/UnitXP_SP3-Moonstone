# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.2 Immediate Chain V2 + Finder UX closure**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.2-immediate-chain-v2`
- CI-validated product head: `2d36ffcc333936e41809039e161baf52e24abba9`
- Final CI run: `35944304515` — success
- Job: `107458736244` — success
- Artifact ID: `10785804614`
- Artifact ZIP SHA256: `6596398f82a733fbe901be42e18960da3c4d212f479e7f73cf8253be7fbf210f`
- Dylib size: `1321136`
- Dylib SHA256: `44eb45dd5643c8256bc0393c0117dc56a5b8836d2ef0a019a28cafb6a97d68d7`
- Format: thin arm64 Mach-O dylib

## Current Finder chain UX

The chain action uses one in-place button:

```text
No saved V2 chain:
[链式调用]

After 完成链 + page render:
[执行链]
```

- Tap `执行链`: execute the saved Root -> Level 1 -> ... transaction through the existing M5.2 atomic chain engine. Developer/Method Finder side retains final return + per-level trace.
- Long-press `执行链` (~0.65s): clear the existing Immediate Chain for that Runtime Action, switch the button back to `链式调用`, and immediately reopen chain authoring.
- This developer Finder result dialog does not change the customer-menu rule: generated customer runtime success remains silent; errors remain visible.

## Method search history UX

Search history is persistent and intentionally simple:

```text
[ 方法名 / Class::Method / RVA ] [搜索]

搜索记录 · n/50
query A
query B
query C
...
```

- directly below the search box
- one row per search query
- independent vertical scrolling
- maximum 50 entries
- newest first
- case-insensitive deduplication; repeated query moves to top
- over 50 removes oldest
- persisted in NSUserDefaults
- tapping a row re-runs that query
- only query text is shown; no Class/RVA/result metadata is mixed into this list

## Immediate Chain V2 core retained

- version=2 `nodes[]`
- root + up to 8 additional nodes
- `/0-/8` typed args per node
- exact parameter signatures
- token and return-type guard when exports are available
- M5.0 GCHandle / compatible receiver chaining
- System.String decode via IL2CPP string APIs
- per-level trace/log
- null/non-managed stop
- Runtime Action ABI still 64 bytes/version 1

## Validation boundary

- source implemented: YES
- committed: YES
- arm64 compile/link/sign: YES
- Binary Verify: YES
- artifact + independent hash check: YES
- device verification for button state change: PENDING
- device verification for single-tap execution: PENDING
- device verification for long-press restart: PENDING
- device verification for 50-entry persistent history: PENDING
- full regression: NO

## Immediate device checklist

1. Search a method, create a V2 chain, press `完成链`, return to the result list and confirm its action reads `执行链`.
2. Tap `执行链`; confirm the complete chain runs and developer/test side reports final return and trace.
3. Long-press `执行链`; confirm the old chain is cleared and chain authoring opens immediately.
4. Search at least 3 different method names; confirm history appears directly under the search box, one row each.
5. Tap a history row and confirm that query is run again and moves to the top without duplication.
6. Reopen/restart the menu and confirm history remains.
7. Exceed 50 distinct queries and confirm only the newest 50 remain.
8. Regress customer silent success, failure alert, ordinary Runtime `/0-/8`, per-argument controls and Static Offset.

## Known scope limits

- Finder chain-button matching currently uses the root Assembly/Namespace/Class/Method/argc identity; exact Chain node execution itself still uses full signatures. If multiple root overloads share the same name+argc, device testing should verify the expected action is selected.
- Search-history panel placement follows the current V3 search layout and should be rechecked if that page geometry changes later.
- Enum member-name dropdown, arbitrary Level-N object args, generic ref/out and broad custom ValueType support remain future work.
