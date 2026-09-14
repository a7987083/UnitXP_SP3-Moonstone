# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **Method Finder V3 Milestone 2**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-method-finder-v3-m2`
- Sealed predecessor: `86edac4d70ef467e9a58912768b6c6c72077842a` — do not modify
- Device-verified V2 baseline: `4377d4a4c6e325e54299e3055346240f4963940f`
- M1 product source: `ef98a090e1df5b69df3fbb86adb905008285d82c`
- M1 state head: `92f64c9dc6e208904228ada6059cea7ba102972d`
- M2 compiled product source: `69b546edd0ed83a5699805951304aa3371a0bc30`
- M2 CI run: `34881764073` — success
- M2 artifact: `ZonoPatch-v0.5.8-MethodFinder-V3-M2`
- Artifact ID: `10363436049`
- Artifact ZIP SHA256: `f4cc5d6bdf1549cd0f35c7dd7341f355e1907c208bc8a6e4ae1ee7a694b9161e`
- Dylib SHA256: `77d1cd3fe30c403c5f5db35ee35fbce8fa4da5f62352be04474bbabe52f24784`
- M2 validation: CI/binary verified, device pending

Docs/state commits after the product build do not change the built dylib. Always distinguish product source SHA `69b546e...` from later docs-only branch HEADs.

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

Do not regress those paths in M2.

## M2 implementation

New file: `iosruntimepatchmenu/src/ZNIL2CPPMethodFinderM2.mm`.

M2 is layered after V2 + V3 M1 and does not replace Named Offset semantics.

### Wide bare-name search

Bare method names are case-insensitive and ranked:

`exact > prefix > suffix > contains`

Example: `cash` is intended to match names including `CashReward`, `GetCash`, `SetCash`, `get_TotalCashReward`, subject to actual target metadata.

Structured expressions (`Class::Method`, namespace/full assembly forms) remain exact. `0xRVA` remains exact.

### Async / cancellation

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
- First bare search builds the full compact index while collecting ranked matches.
- Later searches query index first, then re-resolve candidates through the proven M1 path.
- RVA reverse uses the index if present; without an index it falls back to M1 reverse lookup.

## CI evidence

Run `34881764073` passed:

- source assertions;
- Named Offset parser test;
- static protection tests;
- Theos arm64 compile/link/sign;
- binary marker verification;
- exported API symbol verification;
- one-constructor check (`__init_offsets == 4`);
- artifact upload.

Independent post-download verification also matched:

- ZIP SHA256 `f4cc5d6bdf1549cd0f35c7dd7341f355e1907c208bc8a6e4ae1ee7a694b9161e`
- dylib SHA256 `77d1cd3fe30c403c5f5db35ee35fbce8fa4da5f62352be04474bbabe52f24784`
- thin arm64 Mach-O dylib
- `__TEXT,__init_offsets` size 4
- markers `m2-wide-index`, `m2-wide-build`, `built-and-saved` present.

## CI routing note

Feature-branch Actions registration still has a GitHub-side synthetic `BuildFailed / startup_failure / 0 jobs` issue. This is not a source compile failure.

Working route: workflow registered on `main`, checkout pinned to the exact feature source SHA. Do not use `main` product source as the build input by accident.

## Technical debt / open validation

- First full index build resolves native pointer/RVA for every method; real-device duration/thermal impact unknown.
- Binary plist is not mmap/SQLite-backed.
- Old fingerprinted index files are not proactively garbage-collected.
- generic/inflated/shared method classification is incomplete.
- `-Wno-incomplete-implementation` currently suppresses a category dependency declaration warning; clean the declarations before sealing.
- M2 has not yet been device-verified.

## Next device test

1. First `cash` search: verify UI stays responsive and progress changes.
2. Cancel once during the first index build; verify clean stop/no crash and no partial-index reuse.
3. Run `cash` again and let indexing finish; inspect broad matches and ranking.
4. Search `cash` once more; confirm status/log uses `m2-wide-index` / `index=hit` and is materially faster.
5. Regress known `get_TotalCashReward` detail to RVA `0x2DA9E10`.
6. Regress full qualified expression and `0x2DA9E10` reverse lookup.
7. Regress detail-copy and Create Patch canonical handoff.

Only after those pass should M2 be marked device-verified or considered for sealing.
