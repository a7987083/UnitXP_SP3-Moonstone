# HANDOFF

## Current target

JSONCapture `v0.8.0 Page Dependency Capture`.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/network-capture-v0.8.0-page-dependency`
- Stable baseline: `feature/network-capture-v0.7.1-snapshot-completeness`
- Baseline commit: `521431ace1adc0067d28d690355f15c818c9e25a`
- Final compiled source/workflow commit: `e36faaa1233f10c4272859601f7309fc565738e7`
- Target: Unity 2019.4.33f1 / IL2CPP / ToLua / Lua 5.3.5

## Why v0.8.0 exists

v0.7.1 can recover rich page/protobuf snapshots, but page attribution still depends on recent UI/TAB context. This can produce cross-page contamination when unrelated traffic arrives under stale/recent context.

v0.8.0 does not replace v0.7.1. It adds an independent dependency-evidence layer so the two outputs can be compared on the same device.

## Architecture

### Mode 1 — whitelist + manual passive capture

Correct usage order is important:

1. Import the whitelist TXT.
2. Stay on the previous page.
3. Tap `Mode1预备→打开页面`.
4. Manually open exactly one target page.
5. The first new `UI*.lua` observed after arming becomes the page anchor.
6. Wait for completion without pressing action buttons during the passive baseline capture.

This pre-navigation arming was added because anchoring only after a page was already open could miss the page's initial request burst.

Evidence rules:
- A config becomes primary only when a runtime `TAB_*.lua` observation occurred after arming, is close to the anchored UI, and matches the imported whitelist.
- Protobuf requests from the anchored UI are primary.
- Matched responses inherit the request page and are primary.
- Unmatched PUSH/ambiguous messages go to `protocol_candidates`, not primary `protocols`.
- Runtime Lua chunks containing Cache/Model are stored under `models_observed` as candidates only.
- Mode 1 never consults Mode 2 policy.

### Runtime Completion Detector

- Runs on the existing serial capture queue.
- Every new primary dependency increments the generation and restarts a 1.8 s quiet window.
- A non-empty unchanged dependency set for 1.8 s is marked `complete`.
- This means “observed dependency set stabilized”; it does not prove the server has no undispatched/interaction-triggered data.
- If later primary evidence arrives while the session remains active, the detector returns to collecting and starts a new quiet window.

### Mode 2 — passive policy learner

Buckets:
- `global_background`
- `page_allow`
- `page_deny`
- `active_call_deny`
- `unknown`

Current v0.8.0 behavior is deliberately conservative:
- request or matched response with a page -> `page_allow`
- no page -> `global_background`
- unmatched/ambiguous with a page -> `unknown`
- `page_deny` and `active_call_deny` remain explicit buckets but are not auto-filled without stronger evidence
- `unknown` is never promoted to active invocation
- v0.8.0 contains no active request execution path

## Output paths

Under `Documents/JSONCapture/ManualV05/runtime_page_dependency/`:

- `whitelist.json`
- `mode1_manual/*__dependency.json`
- `mode1_manual/dependency_graph.json`
- `mode2_auto/*__dependency.json`
- `mode2_auto/dependency_graph.json`
- `mode2_auto/policy.json`

Existing v0.7.1 outputs such as `runtime_page_snapshot/`, `runtime_protobuf_events.jsonl`, and `runtime_page_network_map.json` remain enabled.

## Final build evidence

GitHub Actions:
- Run: `35294784256`
- Job: `105444977167`
- Result: success
- Head: `e36faaa1233f10c4272859601f7309fc565738e7`
- Artifact: `10527791132`
- Artifact digest: `sha256:da619c74950a80ea79f929a8bee8b41586c5153126ce3cb89dc84741f5b18fdf`

Independent local verification:
- Dylib SHA256: `25897607cd2cd23740e1db648d88ed7c6a0ef84557b883ad8857c8ef8789c9d9`
- Release ZIP SHA256: `0e1b9b6e2b4fd310dbbb0f490a9127cd07eb8c7083f7acef8fb6f823923b4a78`
- Outer downloaded Artifact SHA256 reproduces the GitHub Artifact digest exactly.
- Mach-O: 64-bit arm64 dynamically linked shared library.
- v0.8.0 `mode1 armed`, `mode1-policy-isolated`, and `unknown-never-active` markers are present in the built dylib.

## Validation boundary

- Source implementation: complete for v0.8.0 initial version.
- Static/source contract including pre-navigation arming: passed.
- CI arm64 compile/package: passed.
- Binary invariants/hash verification: passed.
- Real-device Mode 1: NOT YET VALIDATED.
- Real-device Mode 2: NOT YET VALIDATED.
- Regression vs v0.7.1 device behavior: NOT YET VALIDATED.

## Next validation

Use Mode 1 first. Import the real whitelist, remain on the previous page, tap `Mode1预备→打开页面`, then manually open `UIShopCentre` or `UIDaily`. Do not press claim/refresh/purchase buttons during the baseline run. Wait for the actual UI anchor and completion state, then export the Mode 1 dependency JSON plus `ManualV05.log`. Do not tune Mode 2 policy until Mode 1 false-positive/false-negative behavior is measured.
