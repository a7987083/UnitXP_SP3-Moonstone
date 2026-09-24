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
- Artifact ZIP SHA256: `b607318f0225a2b4e1203ca30a151913c22eeb79e13a0519f42b1f13d769af6b`
- Dylib: `ZonoPatch_v0.5.8_M5.4_Unified_Method_Finder.dylib`
- Dylib size: `1354480`
- Dylib SHA256: `6804ca2f2a242337f8a81eb20125e5b0867bd59add02b9df0e28a35656f37ca2`
- Format: thin arm64 Mach-O dylib

## Why the refactor was required

Repeated device failures of the search-history UI exposed a broader problem: Method Finder contained multiple generations of base UI and hotfixes installed on the same controller via repeated swizzles. Later layers walked already-rendered views, located buttons by visible title/order, removed targets and rebound events. A source/CI-successful feature could therefore be absent on device because it was not on the final IMP chain.

See `METHOD_FINDER_UI_AUDIT.md` for the selector-level audit.

## M5.4 runtime architecture

```text
V3 state/backend
  query / page / candidates / selected / limit / status
        ↓
legacy resolver / ABI / invoke backends
        ↓
M5.4 Unified Search / Results / Detail renderer
        ↓
narrow behavior decorators only
  M4.6.2 candidate binding
  M4.7 receiver-capture gesture
  M5.1/M5.2 chain create/execute/restart
```

Critical rule: `ZNMethodFinderUnifiedUI` does not call the previous renderer implementation. This cuts the old M4.3/M4.4/M4.7 base-renderer chain. Old modules remain compiled only because some installers also provide required backend/action behavior.

The old M5.2 history installer is intentionally not called.

## Unified Search

The device should now show:

```text
IL2CPP 方法查找 · Unified

方法名      [ ... ] [搜索]
Assembly    [ ... ]
最大结果     [ ... ]

搜索记录 · n/50
query A
query B
...
```

History contract:

- NSUserDefaults key `zonoe.m52.method-search-history.v1`
- maximum 50
- newest first
- case-insensitive dedupe
- one row per query
- independent vertical scroll
- tap row = fill 方法名 only
- tap row does not execute search
- manual 搜索 executes the filled query

If the device still shows `IL2CPP 方法查找 · M4.3`, the M5.4 final renderer is not active and that is a hard failure; do not add another history hook.

## Unified Results

- `/0-/8` typed argument rows are drawn directly from ABI metadata.
- Existing argument-store keys are preserved so Invoke/Builder backends continue to read values.
- `测试执行` remains compatible with the M4.6.2 explicit candidate binding decorator.
- Receiver capture remains a long-press decorator on the bound Test button.
- `创建方法` directly adds the selected candidate to `ZNRuntimeActionStore`.
- M5.1/M5.2 chain decorators append/rebind `链式调用` / `执行链` on the final card.

## Unified Detail

Information-only detail page shows canonical identity, Assembly/Namespace/Class/Method, RVA, MethodInfo, Method Pointer, return type, parameters, and M4.5 owning-method metadata when present.

## Retained product behavior

- M5.2 Immediate Chain V2, execute-chain state machine and long-press rebuild.
- M5.1 customer success silent / failure visible behavior.
- M5.3 Runtime Button/Switch/Number/Slider auto-execute.
- M5.3 Static Switch/Button and fail-closed MOVZ(+MOVK) Number/Slider V1.
- Runtime Action ABI 64 bytes; Static Entry ABI 128 bytes.
- suffixless generated binaries.

## CI history

1. Run `35964177732`: compile error from missing logger declaration import only.
2. Run `35964480222`: product built successfully; binary verify failed only on Chinese CFString `strings -a` assertion.
3. Run `35964757740`: full green, including ASCII selector/defaults-key Binary Verify and Artifact Upload.

## Immediate device checklist

1. Confirm 方法查找 title is `IL2CPP 方法查找 · Unified`.
2. Search 2+ names, return to Search and confirm history is visible.
3. Tap history and confirm it only fills 方法名; no result-page jump.
4. Press 搜索 manually and confirm normal search.
5. Check `/0`, `/1`, `/2+` candidate rows and argument editing.
6. Test/捕获 a candidate and long-press receiver capture.
7. 创建方法 and verify correct Builder action.
8. Verify 链式调用 -> 完成链 -> 执行链 and long-press 执行链 restart.
9. Regress Runtime control auto-execute and Static controls.
10. Check Detail and customer silent-success/failure behavior.

## Open issues

- Device acceptance for the new Unified UI is still pending.
- M5.2 chain test previously stopped before Level 1 with `previous managed return is null`; this remains a separate receiver/real-null investigation.
- Static dynamic MOVZ/MOVK V1 may fail closed on signing/device models that prohibit executable-page RX→RW mutation.
- Legacy renderer source files are still compiled in M5.4 because their installers mix backend and UI responsibilities. After device acceptance, a follow-up cleanup should physically split backend modules and remove obsolete renderer implementations from the build.
