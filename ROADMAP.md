# ROADMAP

## JSONCapture g4 — Chinese UI + On-device JSON Recovery

- [x] Branch from device-validated g3 persistent incremental core.
- [x] Chinese floating monitor UI, compact/collapsible, draggable.
- [x] Show Lua / Bundle / persistent index / loader / recovery queue metrics.
- [x] Background re-decrypt queue and static JSON recovery queue.
- [x] Capture-priority yielding: background work pauses when disk capture is active.
- [x] Buttons: pause/resume, force full sweep, re-decrypt, re-recover JSON, recover incremental, open JSON directory, export recovery report, status, clear indexes.
- [x] On-device static Lua 5.3 parser/interpreter; no lua_pcall/lua_call.
- [x] Complete/partial JSON output and persistent recovery report/index.
- [x] GitHub Actions compile/package validation — run 35134708046 passed on source commit e1ab528ad2eadfd22fef56be48eb5baa06988081.
- [x] Artifact downloaded and independently hashed.
- [ ] Real-device UI validation.
- [ ] Real-device recovery parity comparison against Windows v0.3.
- [ ] If profiling shows g3 inline ENCM/compile path materially stalls capture, split the validated capture core into raw-only P0 and deferred P1 decode in a follow-up g4.1.
