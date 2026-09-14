# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `feature/runtime-patch-menu-v0.5.8-method-finder-v3-m2`
- Stage: `Method Finder V3 Milestone 2 — async wide search + persistent IL2CPP index`
- M2 product source: `69b546edd0ed83a5699805951304aa3371a0bc30`
- CI run: `34881764073` — `success`
- Artifact ID: `10363436049`
- M2 device validation: `PENDING`

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
- Cooperative Cancel support.
- 12,000-class shard progress updates.
- Full compact local IL2CPP index built on first broad search.
- Index fingerprint: UnityFramework Mach-O UUID + file size.
- Binary plist persistence with deduplicated Assembly/Namespace/Class/Method tables and fixed 32-byte records.
- Persist only Assembly/Namespace/Class/Method/argCount/RVA; never persist launch-specific MethodInfo/Method Pointer/Runtime VA.
- Subsequent broad searches use index first and re-resolve live runtime candidates.
- Assembly-CSharp-first ordering preserved.

## CI gate — M2 passed

Run `34881764073`:

- source assertions: PASS
- Named Offset parser: PASS
- static protection tests: PASS
- Theos arm64 compile/link/sign: PASS
- binary verify: PASS
- exported API symbols: PASS
- M1 + M2 binary markers: PASS
- `__init_offsets == 4`: PASS
- artifact upload: PASS

Artifact:

- `ZonoPatch-v0.5.8-MethodFinder-V3-M2`
- ID `10363436049`
- ZIP SHA256 `f4cc5d6bdf1549cd0f35c7dd7341f355e1907c208bc8a6e4ae1ee7a694b9161e`
- dylib SHA256 `77d1cd3fe30c403c5f5db35ee35fbce8fa4da5f62352be04474bbabe52f24784`

## Next — M2 physical-device acceptance

Status: `NEXT`

1. First `cash` search: verify UI responsiveness and visible progress during index construction.
2. Cancel one first-time index build and verify clean cancellation/no partial-index reuse.
3. Complete a `cash` index build; inspect matches such as `get_TotalCashReward` and ranking order.
4. Repeat `cash`; verify `m2-wide-index` / `index=hit` path and materially lower latency.
5. Regress known target detail to RVA `0x2DA9E10`.
6. Regress full qualified expression and exact RVA reverse lookup.
7. Regress copy controls and Create Patch canonical handoff.
8. Record first-build duration, second-search duration, class/method counts, index record count, and any thermal/memory symptom.

## After M2 device acceptance

- Clean Objective-C category dependency declarations and remove the temporary `-Wno-incomplete-implementation` suppression before sealing.
- Decide whether binary plist performance is sufficient or move index to mmap/SQLite only if device evidence justifies it.
- Add stale-index cache cleanup.
- Improve generic / inflated / shared native-pointer classification.
- Then proceed to IL2CPP signature/ABI metadata, Return Override, jailbreak Hook/Replace, call trace, and unified Runtime Modification management.

Do not start Hook/Replace work until M2 search/index behavior has device evidence and M1 regressions remain green.
