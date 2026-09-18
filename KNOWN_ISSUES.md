# KNOWN_ISSUES

## v0.8.0 Page Dependency Capture

1. **Mode 1 requires a current UI anchor.** Pressing “Mode1开始页面采集” when no current `UI*.lua` is visible is rejected instead of guessing a page.
2. **Config evidence is conservative but not semantic proof.** A primary config requires runtime TAB observation plus whitelist match. Device validation is still required to prove that the page materially reads that config rather than merely loading it nearby.
3. **Model/Cache mapping is candidate evidence only.** `models_observed` currently uses runtime Lua chunk names containing Cache/Model; it must not be treated as a proven data-flow dependency without stronger runtime/static evidence.
4. **Completion means observed-set stability, not omniscience.** The 1.8 s quiet window reports that no new primary dependency was observed. Late server responses or data triggered only by user interaction can still exist.
5. **Unmatched PUSH stays candidate-only in Mode 1.** This intentionally reduces pollution, but a page-specific push with no request pair may require later promotion after real-device evidence.
6. **Mode 2 is intentionally incomplete/conservative.** `page_deny` and `active_call_deny` are explicit buckets but are not auto-filled in the initial version. `unknown` is never actively invoked.
7. **Real-device v0.8.0 validation is pending.** Source/CI/binary validation passed, but attribution quality and UI/document-picker behavior still require device testing.
8. Existing v0.7.1 child-UI stable-parent heuristics remain available in the legacy snapshot output for comparison; v0.8.0 Mode 1 should be judged against that baseline rather than assumed superior before device evidence.

## Older retained risks

- The capture/recovery stack still contains historical static Lua recovery behavior that intentionally stops on dynamic opcodes such as CALL/CLOSURE; partial output is retained instead of executing business logic.
- Overlay presentation and file-picker behavior can vary with the target app/window/iOS environment and must be validated on the actual device.
