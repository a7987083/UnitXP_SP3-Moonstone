# HANDOFF

Current target: JSONCapture g4 Chinese UI + on-device JSON recovery.

Base branch/device evidence:
- g3 base commit: `d0c10fc1d4df1ab0e8151f4a91ae3bca050242f3`.
- g2/g3 capture path previously device-verified for ENCM -> Lua 5.3 compile success.
- g3 persistence previously device-verified across relaunch with 10,168 unchanged index entries seeded/skipped.

Current g4 architecture:
1. g3/g2 remains capture core.
2. Chinese floating UI reads core counters directly because g4 includes g3 in the same translation unit.
3. Re-decrypt and static JSON recovery use serial background queues.
4. `JCG4CaptureBusy()` blocks/yields low-priority work while disk capture is active or queued disk bundle work remains.
5. On-device recovery writes `recovered_json`, `recovered_partial`, `MobileRecovery.report.json`, `MobileRecovery.status.json`, and `MobileRecovery.index.json`.

Important validation distinction:
- Source implementation: in progress/completed per commit.
- CI compile: must be checked before calling build valid.
- Real-device UI/recovery: not validated until user installs/tests the g4 artifact.
