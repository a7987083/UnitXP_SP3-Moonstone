# ROADMAP

## Current stage

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.8-dev`
- Active branch: `fix/runtime-patch-menu-v0.5.8-m4.4.2-search-restore`
- CI validated product head: `fe8655444420bc9445ee741e2d3c4cffbaead066`
- Stage: `M4.4.2 Search Restore — restore device-proven V3 search engine + preserve explicit Assembly scoping`
- Final CI run: `35791561620` — `success`
- Artifact: `ZonoPatch-v0.5.8-M4.4.2-SearchRestore`
- Artifact ID: `10722211742`
- ZIP SHA256: `c420ab0af09943be5bf05f10cf358514071b9b00982fb242f4573a1a5b94578c`
- Dylib: `ZonoPatch_v0.5.8_M4.4.2_SearchRestore.dylib`
- Dylib size: `1018880`
- Dylib SHA256: `4497d04f3583a4bc447e3cdd692c2bf99479d87440221c2b85554210b251b84b`
- Current validation boundary: source + CI + binary verified; M4.4.2 search-route correction still requires physical-device acceptance.

## Baselines that must not regress

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`.
- Method Finder V3 M2.2 device-accepted product: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- M4 Runtime Method Call V1 CI head: `d53c75dfbb7510e31a60e49f202532ad2f5e099e`; user device-confirmed `/0` create/test/generated-binary paths.
- M4.1 UI/UX V2 CI head: `911dec0c56234387820fbec5daf996e396f86294`.
- M4.2 Typed Args UI V1 CI head: `e7c81172b04e162f74b3652048dcaf499d753aa4`.
- M4.3 Instance Resolver V1 final CI head: `a5688b3f42f53aa50366f349813be069ef0e5418`.
- M4.4 Instance Resolver V2 final CI head: `21775c3e0320399784a5a5b87131ab96cb9a80d5`.
- M4.4.1 Hotfix CI head: `0025556b8f3a2a20466b7344120ca82f9db7f921`.

## Stable architecture constraints

- Exact dyld image identity and Offset Resolver V2 behavior stay unchanged.
- `ZN44StaticEntry == 128` bytes.
- `ZNRuntimeActionHeader == 64` bytes.
- `ZNRuntimeMethodCallEntry == 64` bytes.
- Runtime Action ABI remains independent from Static Patch ABI.
- `/1` text argument still uses the existing Runtime Action string pool via `ZNRuntimeActionFlagArgument0Text + reserved[0]`.
- M4.4.1 common struct values remain one textual `/1` argument and are marshaled only at invoke time; no Runtime Action ABI version bump.
- Raw `Il2CppObject *` addresses must never be serialized into generated binaries.
- M4.4.2 changes search routing only; it does not alter Static Patch ABI, Runtime Action ABI, Instance Resolver ABI or typed-argument storage.

## Implemented inheritance

### M4.1 UI/UX V2

- Automatic binary target: UnityFramework first, main executable fallback.
- App Libraries picker; displayed module names only, no install-UUID path persistence.
- Outside-panel touch passthrough layer.
- Same-page scroll preservation.
- Direct build performs required preflight internally.
- Runtime Method Call title editing is independent from method identity.

### M4.2 Typed Arguments UI V1

- `/0` path retained.
- Typed `/1` invoke for bool, signed/unsigned 32/64, float, double, primitive-backed enum and `System.String`.
- ABI is resolved from IL2CPP metadata before invoke; unsupported ref/out/pointer/object/struct/generic paths fail closed.
- Dynamic `[全部] [0] [1] ...` filter only shows arities present in the returned candidate set.
- Result cards hide Namespace/RVA; Details retains full metadata.
- `/1` value persists into Runtime Action string pool and can be edited in Builder.
- `/2+` stays visible/filterable but not executable.

### M4.3 Instance Resolver V1 / Finder UX

- Search page Assembly picker with `Assembly-CSharp` visual default and `全部 Assembly` option.
- Search maximum result count is user-editable; backend and UI hard maximum are `1024` instead of `64`.
- `/1` parameter input moved below method/class rows so long method names remain readable.
- Argument/result-limit input return action is `完成` and dismisses the keyboard.
- Detail page no longer duplicates Runtime test/create controls; those actions live in the result card.
- When one Assembly is selected, result cards suppress the redundant Assembly label; all-Assembly search keeps it for disambiguation.
- Instance Resolver V1 enumerates live class instances through IL2CPP liveness APIs.
- Exactly one live instance can be automatically supplied as `this` for instance `/0` or `/1` invocation.

### M4.4 Instance Resolver V2

- Adds a process-session instance selection store keyed by `assembly|namespace|class`.
- Selected addresses are validated through `il2cpp_object_get_class` + `il2cpp_class_is_assignable_from` before reuse.
- Invalid/stale selection is cleared instead of being invoked.
- If liveness returns one instance it is auto-selected; if it returns multiple instances the UI presents an explicit `选择实例` action sheet.
- Runtime Action public `执行` uses the same selected class instance within the current process.
- Selection is deliberately not persisted to generated Runtime Action data because object addresses are launch-specific.
- Final M4.4 CI run `35751669688`: success.

## Implemented — M4.4.1 Hotfix

- Finder address input accepts and canonicalizes `38064A8`, `0x38064A8`, `rva:38064A8`, `rva:0x38064A8`.
- Adds explicit `va:...` Runtime VA reverse lookup by converting current UnityFramework Runtime VA to RVA before entering V3 reverse-RVA search.
- Patch Offset accepts bare HEX or `0x` input and normalizes valid values to `0x...` when editing completes.
- Unsupported `/1` fields expose a reason rather than only appearing disabled.
- Adds ABI-aware `/1` marshaling for `UnityEngine.Vector2`, `Vector3`, `Quaternion` and `Color`.
- Custom structs, ordinary object references, ref/out, pointer and `/2+` remain fail closed.
- Final M4.4.1 CI run `35789261862`: success.
- Device feedback then exposed a search regression: after both controls were rebound to the new M4.4.1 handler, queries that previously worked via the visible Search button could return `找不到 IL2CPP 方法` from both keyboard and button.

## Implemented — M4.4.2 Search Restore

- Device feedback proved the pre-M4.4.1 visible Search button was the valid reference behavior.
- Root cause: M4.3 swaps `zn60v3_startSearch:` and `znm43_startSearch:`. Therefore the visible M4.3 button bound to `znm43_startSearch:` was actually executing the original V3 search implementation, while the keyboard path bound to `zn60v3_startSearch:` executed the newer M4.3 implementation.
- M4.4.1 incorrectly replaced both with a third search implementation, losing the only device-proven path.
- Added `ZNM442SearchRestore.mm` as the outermost layer. Both keyboard Search and visible Search now normalize input and delegate execution back to the original V3 implementation through the post-swap `znm43_startSearch:` selector.
- Restores original default scope semantics: before the user explicitly selects an Assembly, search is global with `Assembly-CSharp` first priority instead of strict `Assembly-CSharp`-only filtering.
- The visible default label is annotated `Assembly-CSharp · 优先` to distinguish priority from strict selection.
- Once the user explicitly selects an Assembly in the picker, that selection is recorded and becomes a strict Assembly filter. Explicit `全部 Assembly` remains global.
- Temporary `Assembly!query` qualification is not leaked back into the visible method-name field.
- M4.4.1 address normalization, Patch Offset normalization, Unity struct `/1`, M4.4 instance selection and all earlier ABI constraints remain unchanged.
- Product/CI head: `fe8655444420bc9445ee741e2d3c4cffbaead066`.
- CI run `35791561620`: source assertions, arm64 build, binary verify and artifact upload all passed.
- Independent artifact verification confirmed thin arm64 dylib SHA256 `4497d04f3583a4bc447e3cdd692c2bf99479d87440221c2b85554210b251b84b`.

## Not implemented yet

### Receiver/`this` capture fallback

Status: `NEXT AFTER DEVICE FEEDBACK`

Liveness enumeration can still be ambiguous or return no suitable instance. A receiver-capture fallback should observe the target native method when the game naturally calls it and capture/validate the real ARM64 receiver (`x0`).

Do **not** implement a home-grown fixed-size ARM64 trampoline. If this path is needed after device tests, use a pinned mature arm64/iOS instrumentation backend and keep capture temporary/removable.

### `/2+` typed invoke and broader object/struct marshaling

Current engine still accepts at most one explicit argument. M4.4.1 only adds four known Unity float structs to `/1`; custom structs and managed object references still need explicit ABI/lifetime designs. Future `/2+` support should use one ABI-driven marshaling loop rather than separate hard-coded engines.

## Immediate physical-device acceptance

1. Re-run the exact method query that worked before M4.4.1. Visible `搜索` and keyboard Search must now both return the same candidates.
2. Without touching the Assembly picker, confirm the `Assembly-CSharp · 优先` state still allows methods from other loaded Assemblies to be found.
3. Explicitly select a non-default Assembly and confirm search becomes strictly scoped to that Assembly.
4. Reverse lookup the same known method with `38064A8`, `0x38064A8`, `rva:38064A8` and `rva:0x38064A8`.
5. If a Runtime VA is available, verify `va:0x...` maps to the same method.
6. Enter a bare Patch Offset such as `38064A8`, press `完成`, and confirm the field becomes `0x38064A8` before normal validation.
7. Confirm unsupported `/1` types visibly explain why they cannot be edited/executed.
8. Test safe `/1` Vector2, Vector3, Quaternion and Color methods where available; verify input -> test execution -> create method -> Builder persistence.
9. Regress primitive/string `/1`, M4.4 unique/multi-instance selection, and the user-confirmed M4 `/0` create/test/generated-binary paths.

## Promotion rule

Do not mark M4.4.2 device-verified from CI alone. Promote only after the exact previously failing real-device method query succeeds through both visible Search and keyboard Search, then record explicit Assembly-scoping behavior and the retained M4.4.1 paths.
