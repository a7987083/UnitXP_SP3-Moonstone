# ROADMAP

## JSONCapture v0.8.0 — Page Dependency Capture

Baseline:
- Stable source baseline: `v0.7.1 Snapshot Completeness`.
- Baseline branch: `feature/network-capture-v0.7.1-snapshot-completeness`.
- Baseline commit: `521431ace1adc0067d28d690355f15c818c9e25a`.
- Development branch: `feature/network-capture-v0.8.0-page-dependency`.

Completed:
- [x] Import UTF-8 TXT whitelist, one `.json` filename per line, normalized and deduplicated.
- [x] Physically and logically separate Mode 1 and Mode 2 outputs/policy.
- [x] Mode 1 manual page anchor; Mode 2 policy is never consulted by Mode 1.
- [x] Runtime Completion Detector using dependency-set changes + 1.8 s quiet window.
- [x] UI -> TAB/Config evidence: runtime TAB observation + whitelist match.
- [x] UI -> MSGID evidence: request + request-correlated response become primary protocols.
- [x] Unmatched PUSH/ambiguous protocols remain candidates and do not pollute primary dependencies.
- [x] Runtime Cache/Model Lua names are retained as observed candidates, not claimed as proven semantic dependencies.
- [x] Mode 2 passive policy learner with `global_background`, `page_allow`, `page_deny`, `active_call_deny`, `unknown`.
- [x] `unknown` is observation-only and is never promoted to active invocation.
- [x] No new native hook, constructor, polling thread, or dispatch queue; existing serial capture queue is reused.
- [x] arm64 Theos CI compile/package and Mach-O invariant validation.
- [x] Artifact downloaded and independently hash-verified.

Pending:
- [ ] Real-device Mode 1 validation on representative pages such as `UIShopCentre` and `UIDaily`.
- [ ] Compare v0.8.0 dependency pollution against v0.7.1 page snapshots.
- [ ] Validate Runtime Completion Detector timing on slow/late server responses.
- [ ] Validate Model/Cache candidates against actual runtime reads before promoting any stronger semantic mapping.
- [ ] Real-device Mode 2 policy-learning validation.
- [ ] Regression validation for existing v0.7.1 protobuf/page snapshot outputs.

Next task:
1. Install the v0.8.0 artifact.
2. Import the whitelist TXT.
3. Select Mode 1, manually open one target page, start capture, avoid action buttons, and wait for `✅ 已抓取完成`.
4. Export `Documents/JSONCapture/ManualV05/runtime_page_dependency/mode1_manual/` plus `ManualV05.log`.
5. Compare primary configs/protocols against the v0.7.1 polluted baseline before changing classification rules.
