# HANDOFF

## Current work line

ZonoPatch Runtime Patch Menu `v0.5.8-dev` — **M5.3 Control Binding V1 + M4.3 Search History UI Fix**.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `feature/runtime-patch-menu-v0.5.8-m5.3-control-binding-v1`
- CI-validated product head: `064d535918cacd0f40a220521af7cad18a3d42d9`
- CI Run: `35960360188` — success
- Job: `107507414304` — success
- Artifact ID: `10792097181`
- Artifact ZIP SHA256: `48a8eae15b567f10ec889861c89f1c03c1d6a79b72e43479abcbfbbe6c084acf`
- Dylib size: `1337776`
- Dylib SHA256: `bd7ca8773dca7e26ef989821c3aea3a5454cffc94d6cf0039ddb35cbb7dff1dc`
- Format: thin arm64 Mach-O dylib

## Search history current UX

The device uses `IL2CPP 方法查找 · M4.3`. The corrected history path is intentionally tied to that page:

```text
M4.3 main search card (y=9, h=170)
↓
搜索记录 · n/50   (insert y=187)
query A
query B
...
↓
M4.3 status card / later content
```

Rules:

- history persists via NSUserDefaults
- maximum 50 entries
- newest first
- case-insensitive dedupe
- one row per query
- independent vertical scrolling
- repeated query moves to top
- oldest is dropped after 50
- **tap history row = autofill 方法名 only**
- tapping a row does **not** run a search
- user manually presses `搜索` after autofill

The old placement bug came from using `maxY(contentView)`, which included footer/other later views and could push the history below the visible Finder area. The current implementation inserts at the known M4.3 boundary and shifts subsequent main-content views down.

## M5.3 Runtime Method controls

```text
Button  -> tap -> invoke now
Switch  -> change -> invoke now
Number  -> finish editing -> invoke now
Slider  -> drag updates value -> release -> invoke once
```

- Hidden/fixed arguments remain fixed.
- Existing typed `/0-/8`, full-signature resolver, receiver selection, Return Capture and Immediate Chain remain underneath.
- Customer success remains silent; failures still surface `执行失败`.

## M5.3 Static Offset controls

- Switch: existing Static Dispatch OFF/ON.
- Button: enable fixed Enabled variant.
- Number/Slider V1: dynamic only for safely recognized ARM64 `MOVZ` + compatible `MOVK` generated ON instructions.
- Unknown or unsupported encodings fail closed.
- Runtime dynamic write uses expected-byte validation/read-back/rollback.
- Targets that prohibit RX→RW executable-page mutation may reject Static Number/Slider V1; ordinary Static Switch/Button remain separate.

## M5.2 features retained

- Immediate Chain V2, root + up to 8 nodes
- `链式调用 -> 执行链`; tap execute; long-press rebuild
- System.String decode, per-level trace, exact signatures
- suffixless generated binaries

## Immediate device checklist

1. On M4.3 search page, search two different names and return to search; confirm history is visible immediately below the main search card.
2. Tap one history row; confirm only the 方法名 field changes and no search starts.
3. Press `搜索`; confirm the autofilled query now searches normally.
4. Restart/reopen menu; confirm history persists and dedupe/max-50 behavior remains.
5. Regress Runtime Switch/Number/Slider/Button automatic execution.
6. Regress Static Button and compatible MOVZ/MOVK dynamic Number/Slider.
7. Regress Chain V2 and ordinary Static Switch.

## Pending evidence

- Corrected M4.3 history placement: source/CI/binary/artifact verified; device pending.
- History tap autofill-only behavior: source/CI/binary/artifact verified; device pending.
- Runtime control auto-execute: source/CI/binary verified; device pending.
- Static Button binding: source/CI/binary verified; device pending.
- Static dynamic MOVZ/MOVK: source/CI/binary verified; device pending.
- M5.2 chain Level 0 `yo::wB()/0` previously produced `previous managed return is null`; receiver/real-null distinction remains open.
