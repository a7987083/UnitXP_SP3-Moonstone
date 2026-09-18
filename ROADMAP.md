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
- [x] Mode 1 pre-navigation arming: arm on the previous page, then the first new `UI*.lua` becomes the target page anchor.
- [x] Mode 1 never consults Mode 2 policy.
- [x] Runtime Completion Detector using dependency-set changes + 1.8 s quiet window.
- [x] UI -> TAB/Config evidence: runtime TAB observation after arming + whitelist match.
- [x] UI -> MSGID evidence: request + request-correlated response become primary protocols.
- [x] Unmatched PUSH/ambiguous protocols remain candidates and do not pollute primary dependencies.
- [x] Runtime Cache/Model Lua names are retained as observed candidates, not claimed as proven semantic dependencies.
- [x] Mode 2 passive policy learner with `global_background`, `page_allow`, `page_deny`, `active_call_deny`, `unknown`.
- [x] `unknown` is observation-only and is never promoted to active invocation.
- [x] No new native hook, constructor, polling thread, or dispatch queue; existing serial capture queue is reused.
- [x] arm64 Theos CI compile/package and Mach-O invariant validation.
- [x] Final Artifact downloaded and independently hash-verified.

Pending:
- [ ] Real-device Mode 1 validation on representative pages such as `UIShopCentre` and `UIDaily`.
- [ ] Confirm the first new UI anchor is the intended root UI rather than a transient overlay on the target game.
- [ ] Compare v0.8.0 dependency pollution against v0.7.1 page snapshots.
- [ ] Validate Runtime Completion Detector timing on slow/late server responses.
- [ ] Validate Model/Cache candidates against actual runtime reads before promoting any stronger semantic mapping.
- [ ] Real-device Mode 2 policy-learning validation.
- [ ] Regression validation for existing v0.7.1 protobuf/page snapshot outputs.

Next task:
1. Install the final v0.8.0 artifact.
2. Import the whitelist TXT.
3. Stay on the previous page and tap `Mode1预备→打开页面`.
4. Manually open exactly one target page; do not press claim/refresh/purchase buttons.
5. Wait for the status to change from `已预备/等待新 UI 锚点` to the real UI and then `✅ 已抓取完成`.
6. Export `Documents/JSONCapture/ManualV05/runtime_page_dependency/mode1_manual/` plus `ManualV05.log`.
7. Compare primary configs/protocols against the v0.7.1 polluted baseline before changing classification rules.
