# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.4 Unified Method Finder**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `refactor/method-finder-ui-consolidation-m5.4`
- CI-validated head: `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845`
- Product-code head: `eff4f4d86c1851558e703addb89ed86578259a64`
- Final CI Run: `35964757740` — success
- Job: `107520782444` — success
- Artifact ID: `10793662459`
- Dylib SHA256: `6804ca2f2a242337f8a81eb20125e5b0867bd59add02b9df0e28a35656f37ca2`
- Device evidence 2026-09-24: Unified/search-history UI is now visible on the real device; the prior hidden-history blocker is closed.

## M5.4 runtime architecture

```text
V3 state/backend
        ↓
resolver / ABI / invoke backends
        ↓
M5.4 Unified Search / Results / Detail renderer
        ↓
behavior decorators only
  candidate binding / receiver capture / chain
```

`ZNMethodFinderUnifiedUI` does not call the previous renderer implementation. Old renderer files remain compiled only because some installers still mix backend and UI responsibilities.

## Device status

Passed from current device evidence:

- M5.4 Unified final UI path is reaching the device.
- Search-history surface that was previously missing is now visible.

Still pending and must be checked separately:

1. History tap fills 方法名 only and does not auto-search.
2. Manual 搜索 after autofill works.
3. `/0-/8` argument rows and overload filtering.
4. Test/candidate binding and receiver-capture long press.
5. 创建方法 adds the correct Runtime Action.
6. 链式调用 -> 完成链 -> 执行链; long-press 执行链 restart.
7. M5.3 Runtime and Static control regressions.
8. Detail / Return Capture / silent-success / suffixless output regression.

## Open issues

- Legacy renderer source is still compiled until behavior regressions pass and mixed installers can be split safely.
- M5.2 chain Level 0 `previous managed return is null` investigation remains separate.
- Static MOVZ/MOVK dynamic path may fail closed where executable-page RX→RW mutation is prohibited.
