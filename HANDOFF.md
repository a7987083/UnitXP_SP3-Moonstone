# HANDOFF

## Current target

JSONCapture `v0.8.0 Page Dependency Capture`.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/network-capture-v0.8.0-page-dependency`
- Stable baseline: `feature/network-capture-v0.7.1-snapshot-completeness`
- Baseline commit: `521431ace1adc0067d28d690355f15c818c9e25a`
- Compiled source commit: `947c453dcf686cddd71fa2737ea12e3dd5b3b1f7`
- Target: Unity 2019.4.33f1 / IL2CPP / ToLua / Lua 5.3.5

## Why v0.8.0 exists

v0.7.1 can recover rich page/protobuf snapshots, but page attribution still depends on recent UI/TAB context. This produced cross-page contamination; for example, an active page could inherit unrelated protobuf activity that arrived while another page context was still considered current.

v0.8.0 does not replace v0.7.1. It adds an independent dependency-evidence layer so the two outputs can be compared on device.

## Architecture

### Mode 1 — whitelist + manual passive capture

- User manually opens a page and starts a capture session.
- Current `UI*.lua` becomes the page anchor.
- A config becomes primary only when a runtime `TAB_*.lua` observation also matches the imported whitelist.
- Protobuf requests from the anchored UI are primary.
- Matched responses inherit the request page and are primary.
- Unmatched PUSH/ambiguous messages are written to `protocol_candidates`, not primary `protocols`.
- Runtime Lua chunks containing Cache/Model are kept under `models_observed` as candidates only.
- Mode 1 never consults Mode 2 policy.

### Runtime Completion Detector

- Runs on the existing serial capture queue.
- Every new primary dependency increments the generation and restarts a 1.8 s quiet window.
- A non-empty unchanged dependency set for 1.8 s is marked `complete`.
- This means “observed dependency set stabilized”; it does not prove the server has no undispatched/interaction-triggered data.

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

Existing v0.7.1 output such as `runtime_page_snapshot/`, `runtime_protobuf_events.jsonl`, and `runtime_page_network_map.json` is retained.

## Build evidence

GitHub Actions:
- Run: `35294375167`
- Job: `105443774129`
- Result: success
- Artifact: `10526374837`
- Artifact digest: `sha256:7bcab43d960d923287b67c1429ba8935492104e0a6675140a206782703742965`

Independent local verification:
- Dylib SHA256: `7f242c041e8f42787244df11302c86a16c4e5c8a04fd63bb429f8d1108745bed`
- Release ZIP SHA256: `cac6d344584307b24f93d604dc7b9d45d5b1b94b1455a0b21f82bbb63468fea6`
- Mach-O: 64-bit arm64 dynamically linked shared library.
- `__mod_init_func` size remains `0x10`.
- v0.8.0 readiness/mode strings are present in the built dylib.

## Validation boundary

- Source implementation: complete for v0.8.0 initial version.
- Static/source contract: passed.
- CI arm64 compile/package: passed.
- Binary invariants/hash verification: passed.
- Real-device Mode 1: NOT YET VALIDATED.
- Real-device Mode 2: NOT YET VALIDATED.
- Regression vs v0.7.1 device behavior: NOT YET VALIDATED.

## Next validation

Use Mode 1 first. Import the real whitelist, manually open `UIShopCentre` or `UIDaily`, start capture without pressing claim/refresh/purchase buttons, wait for completion, then export the Mode 1 dependency JSON and `ManualV05.log`. Do not tune Mode 2 policy until Mode 1 false-positive/false-negative behavior is measured.
