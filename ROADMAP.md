# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-method-finder-v3-m2.1-cancel-ux`
- Stage: `Method Finder V3 Milestone 2.1 — visible cancel UX on top of async wide search/index`
- M2 core product source: `69b546edd0ed83a5699805951304aa3371a0bc30`
- M2.1 product source: `47d186730ffdf28c2c4bc8fc2992c938c3f1e2b5`
- CI run: `34885020233` — `success`
- Artifact ID: `10364618234`
- M2 wide-search device observation: `PARTIAL PASS`
- M2.1 cancel UX device validation: `PENDING`

## Baselines

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a` — never modify directly.
- v0.5.7 Named Offset baseline: `8300cf41589bf8aa9a690152d4dab3dd6333073c`.
- V2 device-verified Method Finder/zero-vmaddr baseline: `4377d4a4c6e325e54299e3055346240f4963940f`.
- V3 M1 product source: `ef98a090e1df5b69df3fbb86adb905008285d82c`.
- V3 M1 device acceptance: PASS for the agreed candidate/detail/RVA/Builder paths.

## Completed — V3 Milestone 1

- Multiple candidate result list.
- Qualified lookup and RVA reverse lookup.
- Detail page with RVA / Preferred VA / Runtime VA / MethodInfo / Method Pointer.
- First 16-byte code preview and copy controls.
- Exact selected candidate -> Builder canonical expression bridge.
- Known target `Cash::get_TotalCashReward/0` device-verified at RVA `0x2DA9E10`.

## Implemented — V3 Milestone 2

- Bare-name wide search, case-insensitive.
- Ranking: `exact > prefix > suffix > contains`.
- Structured expressions remain exact.
- RVA reverse remains exact.
- Background search execution; UI thread is no longer responsible for full metadata scanning.
- Cooperative Cancel engine.
- 12,000-class shard progress updates.
- Compact local IL2CPP index built on first broad search.
- Index fingerprint: UnityFramework Mach-O UUID + file size.
- Binary plist persistence with deduplicated Assembly/Namespace/Class/Method tables and fixed 32-byte records.
- Persist only Assembly/Namespace/Class/Method/argCount/RVA; never persist launch-specific MethodInfo/Method Pointer/Runtime VA.
- Subsequent broad searches use index first and re-resolve live runtime candidates.
- Assembly-CSharp-first ordering preserved.

## M2 real-device evidence

Broad query `cash` on the real target:

- first run: `423.1 ms`
- second run: `147 ms`
- later runs: approximately `150 ms`

This is enough to mark the broad-search path as real-device observed and performant on the current target. The repeat-query reduction is consistent with index reuse, but the `index=hit` UI/log marker itself was not separately reported and remains unconfirmed.

The original bottom-of-page Cancel control was not observed. At these durations, especially ~150 ms repeats, asking the user to manually race the search is not a useful acceptance criterion.

## Implemented — M2.1 cancel UX

- Search/cancel engine remains unchanged.
- While an active M2 token exists, the primary top `搜索` button changes to `取消`.
- Primary action target switches to `zn61m2_cancelSearch:`.
- Old temporary bottom Cancel card is removed while active.
- Completion clears token and normal re-render restores `搜索`.
- Accessibility marker: `ZNMethodFinderPrimaryCancel`.
- Production search is not intentionally slowed for testing.

## CI gate — M2.1 passed

Run `34885020233`:

- source assertions: PASS
- Named Offset parser: PASS
- static protection tests: PASS
- Theos arm64 compile/link/sign: PASS
- M2.1 source compile: PASS
- binary verify: PASS
- exported API symbols: PASS
- M1/M2/M2.1 binary markers: PASS
- `__init_offsets == 4`: PASS
- artifact upload: PASS

Artifact:

- `ZonoPatch-v0.5.8-MethodFinder-V3-M2.1`
- ID `10364618234`
- ZIP SHA256 `f0dc1779dbb129bca51b9a4221aa76e0f02756c832022171df6d50038ed54637`
- dylib SHA256 `f6778203804b2d28c90b201a2de7cf8b141a31d2d215f5d0ed3dfb5e99a86ba6`
- dylib size `751232` bytes

## Next — M2.1 physical-device acceptance

Status: `NEXT`

1. Install M2.1 and run `cash` once; confirm the top action changes from `搜索` to `取消` for whatever portion of the search duration is visually observable.
2. Do not require a successful manual tap on a 147–423 ms search. Cancellation behavior should be exercised later on a naturally slower/larger target if needed.
3. Confirm broad search still completes normally and remains near the current performance profile.
4. If visible in results/log, confirm `m2-wide-index` / `index=hit` on a repeat query.
5. Regress known target detail to RVA `0x2DA9E10`.
6. Regress full qualified expression and exact RVA reverse lookup.
7. Regress copy controls and Create Patch canonical handoff.

## After M2.1 acceptance

- Clean Objective-C category dependency declarations and remove the temporary `-Wno-incomplete-implementation` suppression before sealing.
- Decide whether ~150 ms indexed lookup is already sufficient. Only optimize further if real UX needs it, because part of that time is deliberate current-launch MethodInfo/Method Pointer re-resolution.
- Add stale-index cache cleanup.
- Improve generic / inflated / shared native-pointer classification.
- Then proceed to IL2CPP signature/ABI metadata, Return Override, jailbreak Hook/Replace, call trace, and unified Runtime Modification management.

Do not start Hook/Replace work until M2.1 search/index behavior has device evidence and M1 regressions remain green.
