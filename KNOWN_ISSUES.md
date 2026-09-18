# KNOWN_ISSUES

## v0.8.0 Page Dependency Capture

1. **The first new UI after arming is the Mode 1 root anchor.** This fixes the earlier risk of missing initial requests, but the target game must be checked to ensure a transient/loading overlay does not load as the first new `UI*.lua` before the intended root page.
2. **Do not arm after the target page has already finished opening for the baseline test.** Correct flow is previous page -> `Mode1预备→打开页面` -> target page. Arming after navigation can no longer be assumed to recover already-finished request traffic.
3. **Config evidence is conservative but not semantic proof.** A primary config requires runtime TAB observation after arming plus whitelist match. Device validation is still required to prove the page materially reads that config rather than merely loading it nearby.
4. **Model/Cache mapping is candidate evidence only.** `models_observed` uses runtime Lua chunk names containing Cache/Model; it must not be treated as a proven data-flow dependency without stronger runtime/static evidence.
5. **Completion means observed-set stability, not omniscience.** The 1.8 s quiet window reports that no new primary dependency was observed. Late server responses or data triggered only by user interaction can still exist.
6. **Unmatched PUSH stays candidate-only in Mode 1.** This intentionally reduces pollution, but a page-specific push with no request pair may require later promotion after real-device evidence.
7. **Mode 2 is intentionally conservative.** `page_deny` and `active_call_deny` are explicit buckets but are not auto-filled in the initial version. `unknown` is never actively invoked.
8. **Real-device v0.8.0 validation is pending.** Source/CI/binary validation passed, but attribution quality, first-UI anchoring, and document-picker behavior still require device testing.
9. Existing v0.7.1 child-UI stable-parent heuristics remain available in the legacy snapshot output for comparison; v0.8.0 Mode 1 should be judged against that baseline rather than assumed superior before device evidence.

## Older retained risks

- The capture/recovery stack still contains historical static Lua recovery behavior that intentionally stops on dynamic opcodes such as CALL/CLOSURE; partial output is retained instead of executing business logic.
- Overlay presentation and file-picker behavior can vary with the target app/window/iOS environment and must be validated on the actual device.
