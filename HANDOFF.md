# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **Method Finder V3 Milestone 2.1 cancel UX**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-method-finder-v3-m2.1-cancel-ux`
- Sealed predecessor: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not modify
- Device-verified V2 baseline: `4377d4a4c6e325e54299e3055346240f4963940f`
- M1 product source: `ef98a090e1df5b69df3fbb86adb905008285d82c`
- M1 state head: `92f64c9dc6e208904228ada6059cea7ba102972d`
- M2 compiled product source: `69b546edd0ed83a5699805951304aa3371a0bc30`
- M2.1 compiled product source: `47d186730ffdf28c2c4bc8fc2992c938c3f1e2b5`
- M2.1 CI run: `34885020233` — success
- M2.1 artifact: `ZonoPatch-v0.5.8-MethodFinder-V3-M2.1`
- Artifact ID: `10364618234`
- Artifact ZIP SHA256: `f0dc1779dbb129bca51b9a4221aa76e0f02756c832022171df6d50038ed54637`
- Dylib SHA256: `f6778203804b2d28c90b201a2de7cf8b141a31d2d215f5d0ed3dfb5e99a86ba6`
- M2.1 validation: CI/binary verified, device pending

Docs/state commits after the product build do not change the built dylib. Always distinguish product source SHA `47d1867...` from later docs-only branch HEADs.

## M1 validation

The user tested M1 on the real jailbreak/IL2CPP target and reported all requested checks passed.

Known target:

`Assembly-CSharp.dll!com.notdoppler.ETDR.Cash::get_TotalCashReward/0`

Expected/verified RVA: `0x2DA9E10`.

Device-verified M1 paths:

- bare exact query opens candidate list;
- selected detail resolves known RVA and runtime metadata;
- RVA reverse lookup works;
- full qualified lookup works;
- address/detail copy workflow works;
- Create Patch preserves selected canonical expression.

Do not regress those paths in M2/M2.1.

## M2 implementation

Core file: `iosruntimepatchmenu/src/ZNIL2CPPMethodFinderM2.mm`.

M2 is layered after V2 + V3 M1 and does not replace Named Offset semantics.

### Wide bare-name search

Bare method names are case-insensitive and ranked:

`exact > prefix > suffix > contains`

Structured expressions (`Class::Method`, namespace/full assembly forms) remain exact. `0xRVA` remains exact.

### Async / cancellation engine

- Search runs off the UI thread on a user-initiated queue.
- Index construction advances in 12,000-class shards.
- Progress is sent back to the menu.
- Each search has a UUID cancellation token.
- Cancelled first-time index builds are not persisted as valid indexes.

### Persistent compact index

- Stored as binary plist under app cache.
- Fingerprint: UnityFramework `LC_UUID + file size`; fallback only if UUID absent.
- Deduplicated tables: Assembly / Namespace / Class / Method.
- Fixed 32-byte records: string-table IDs, argument count, RVA.
- Persisted: Assembly, Namespace, Class, Method, arg count, RVA.
- Never persisted: Runtime VA, MethodInfo, Method Pointer.
- Runtime addresses/pointers are re-resolved each launch.
- First bare search builds the compact index while collecting ranked matches.
- Later searches query index first, then re-resolve candidates through the proven M1 path.
- RVA reverse uses the index if present; without an index it falls back to M1 reverse lookup.

## M2 real-device observation

User tested broad query `cash` on the real target:

- first run: `423.1 ms`
- second run: `147 ms`
- later runs: approximately `150 ms`

This proves the broad search path is usable on-device and shows a repeat-query speed reduction consistent with local-index reuse. The user did not separately report the `index=hit` status text, so do not claim that UI marker as independently device-confirmed yet.

The original M2 Cancel button was not visible on this target. Source review showed why: M2 appended Cancel in a temporary card at the bottom of the search page only while the active-token state existed. At ~423 ms first-run and ~150 ms repeats, that control can disappear before it is meaningfully visible/actionable.

## M2.1 cancel UX fix

New file: `iosruntimepatchmenu/src/ZNIL2CPPMethodFinderM21CancelUX.mm`.

M2.1 does not change the search/cancellation engine. It changes discoverability only:

- while an M2 token is active, the primary `搜索` button becomes `取消` in the same top search-card position;
- the button target is switched from search to `zn61m2_cancelSearch:`;
- the old bottom Cancel card is removed while active;
- after completion and token clear, a fresh render returns the primary action to `搜索`;
- accessibility identifier: `ZNMethodFinderPrimaryCancel`.

Do not intentionally slow production search just to make Cancel easier to press. On a target completing in 147–423 ms, manual cancellation is not a useful acceptance requirement; cancellation should remain available for larger/slower targets.

## M2.1 CI evidence

Run `34885020233` passed:

- source assertions;
- Named Offset parser test;
- static protection tests;
- Theos arm64 compile/link/sign;
- M2.1 source compiled into the target;
- binary marker `ZNMethodFinderPrimaryCancel` present;
- exported API symbol verification;
- one-constructor check (`__init_offsets == 4`);
- artifact upload.

Independent post-download verification matched:

- ZIP SHA256 `f0dc1779dbb129bca51b9a4221aa76e0f02756c832022171df6d50038ed54637`
- dylib SHA256 `f6778203804b2d28c90b201a2de7cf8b141a31d2d215f5d0ed3dfb5e99a86ba6`
- dylib size `751232` bytes
- thin arm64 Mach-O dylib
- `__TEXT,__init_offsets` size 4
- markers `v3-candidate-list`, `m2-wide-index`, `ZNMethodFinderPrimaryCancel` present.

## CI routing note

Feature-branch Actions registration still has a GitHub-side synthetic `BuildFailed / startup_failure / 0 jobs` issue. This is not a source compile failure.

Working route: workflow registered on `main`, checkout pinned to the exact feature source SHA. Do not use `main` product source as the build input by accident.

## Technical debt / open validation

- Repeat indexed search still re-resolves current-launch MethodInfo/Method Pointer, so ~150 ms is not expected to collapse to a pure string-table lookup time.
- Binary plist is not mmap/SQLite-backed.
- Old fingerprinted index files are not proactively garbage-collected.
- generic/inflated/shared method classification is incomplete.
- `-Wno-incomplete-implementation` currently suppresses a category dependency declaration warning; clean the declarations before sealing.
- M2.1 top-position Cancel transition is not yet device-verified.

## Next device test

1. Install the M2.1 artifact.
2. Search `cash`; confirm the primary top action changes from `搜索` to `取消` while the search is active, if the duration is long enough to observe it.
3. Do not require the user to beat the 147–423 ms completion time by tapping Cancel. On this device that is not a meaningful human test.
4. Confirm `cash` broad search still returns normally and keeps roughly the observed performance profile.
5. Regress known `get_TotalCashReward` detail to RVA `0x2DA9E10`.
6. Regress full qualified expression and `0x2DA9E10` reverse lookup.
7. Regress detail-copy and Create Patch canonical handoff.

Only after those pass should the M2.1 UI layer be marked device-verified or considered for sealing.
