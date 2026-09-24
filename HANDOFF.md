# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.3 Control Binding V1**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.3-control-binding-v1`
- CI-validated product head: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`
- CI Run: `35951498398` — success
- Job: `107480818078` — success
- Artifact ID: `10788349821`
- Artifact ZIP SHA256: `80a2461b89ad5625d03d86407ad8ec5ea9854cde46422485d08e1037232fd777`
- Dylib size: `1337776`
- Dylib SHA256: `e4ed0643ed7cf8aceb89f93f06c40f41442f4f12a64b1d8bcd7970765df7b98b`
- Format: thin arm64 Mach-O dylib

## M5.3 purpose

M5.3 closes the gap between visible customer controls and their actual execution semantics.

### Runtime Method controls

```text
Button  -> tap -> invoke now
Switch  -> change -> invoke now
Number  -> finish editing -> invoke now
Slider  -> drag updates value -> release -> invoke once
```

- Hidden/fixed arguments remain fixed.
- Exposed argument values are composed into the existing `ZNRuntimeMethodAction`.
- Existing typed `/0-/8`, full-signature resolver, receiver selection, Return Capture and Immediate Chain remain underneath.
- Customer success remains silent via M5.1 Silent Execution; failures still surface `执行失败`.
- Top `执行` remains for backward compatibility; auto-triggering controls no longer require it.

### Static Offset controls

- Switch: unchanged, uses existing Static Dispatch OFF/ON behavior.
- Button: now enables the fixed Enabled variant instead of only emitting a notification.
- Number/Slider V1: dynamic only when the generated ON Enabled prefix is a safely recognized ARM64 wide-immediate sequence:

```text
MOVZ W/Xd, #imm16
MOVK W/Xd, #imm16, LSL #16/#32/#48   (optional, same register/width)
```

The binding follows Protection V2 fragment branches to the actual generated ON instructions, modifies only the immediate fields required by the customer value, uses `ZNRuntimePatchExecutor` expected-byte/read-back/rollback, then activates the Static variant.

Fail-closed rules:

- first Enabled instruction is not MOVZ -> reject
- incompatible/missing MOVK slot for requested high halfword -> reject
- negative/fractional Static V1 value -> reject
- unsupported Protection layout -> reject
- executable page cannot become writable -> reject with visible failure

No arbitrary byte sequence is reinterpreted as Int32/Float.

## Architectural caution

Static Dispatch V3 was designed so normal ON/OFF switching only mutates RW `selectedTarget`, not executable pages. M5.3 Static dynamic V1 necessarily rewrites generated ON-variant instructions. Therefore targets/signing modes that forbid RX→RW mutation may reject Number/Slider V1 even though ordinary Static Switch/Button continues to work.

If that occurs on the intended deployment model, do not weaken protection or blind-write. The next implementation should be **Static Dynamic V2**: generated RW value cells + build-time parameterized executable stubs that read the cell, so customer value changes touch only RW data.

## M5.2 features retained

- Immediate Chain V2, root + up to 8 nodes
- `链式调用 -> 执行链`; tap execute; long-press rebuild
- M4.3 Finder persistent search history, 50 max, one row/query
- System.String decode, per-level trace, exact signatures
- suffixless generated binaries

## Device checklist

1. Runtime Switch: change ON/OFF and verify one immediate method call with the new bool value.
2. Runtime Number: type a different value, finish editing, verify one call using that value.
3. Runtime Slider: move it and verify invocation occurs on release rather than every intermediate ValueChanged.
4. Runtime Button: tap and verify immediate invoke; no success dialog.
5. Force one Runtime failure and verify `执行失败` still appears.
6. Static Button: tap and verify fixed Enabled activates.
7. Static Number: use a validated `MOV W0,#N`/`MOV X0,#N` style patch and change the customer number; verify effect follows customer value.
8. Static Slider: same compatible patch, drag/release and verify final integer value takes effect.
9. Test an unsupported Static Enabled pattern and verify fail-closed without corrupting the patch site.
10. Regress Chain V2, search history, Static Switch, Runtime `/0-/8`, and generated binary naming.

## Pending evidence

- Runtime control auto-execute: source/CI/binary verified; device pending.
- Static Button binding: source/CI/binary verified; device pending.
- Static dynamic MOVZ/MOVK: source/CI/binary verified; device pending.
- executable-page mutation on intended non-jailbreak/signing configuration: unknown until device test.
- M5.2 chain Level 0 `yo::wB()/0` previously produced `previous managed return is null` on device; receiver/real-null distinction remains open.
