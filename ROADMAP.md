# ROADMAP

## Current milestone — M5.3 Control Binding V1 + M4.3 Search History UI Fix

Branch: `feature/runtime-patch-menu-v0.5.8-m5.3-control-binding-v1`

CI-validated product head: `064d535918cacd0f40a220521af7cad18a3d42d9`

Implemented:

- M5.2 Immediate Chain V2, `执行链` state machine, customer silent-success behavior and 50-entry persistent search-history storage are retained.
- M4.3 search-history display bug fixed: the old implementation used `maxY(contentView)` and could place history below footer/other views. History is now inserted at the known M4.3 boundary immediately below the 170pt search card (`y=187`), and later M4.3 content is shifted down.
- Search history remains newest-first, case-insensitive deduplicated, persistent, one row per query, independently scrollable, capped at 50.
- Tapping a search-history row now **only autofills the 方法名 field**. It updates both the Finder query model and the visible query field (`tag 603001`) and does **not** automatically start a search.
- Runtime per-argument controls are behavior-bound:
  - Button: tap invokes immediately.
  - Switch: value change invokes immediately.
  - Number: editing completion invokes immediately.
  - Slider: drag updates value; touch release commits one invoke.
- Runtime invoke keeps hidden fixed args + exposed live values and reuses typed `/0-/8`, full-signature resolution, receiver handling and Immediate Chain.
- Successful customer Runtime execution stays silent; failures still show `执行失败`; Builder/Finder test surfaces keep return/debug output.
- Static Switch keeps existing Static Dispatch behavior.
- Static Button enables the existing fixed Enabled variant.
- Static Number/Slider V1 binds customer values only for verified ARM64 `MOVZ` + compatible `MOVK` generated ON variants; unknown encodings fail closed.
- Static dynamic writes use expected-byte verification/read-back/rollback through `ZNRuntimePatchExecutor`.
- Static Dispatch Entry ABI remains 128 bytes; Runtime Action Entry ABI remains 64 bytes.

CI/build status:

- History UI Fix Run `35960360188`: SUCCESS
- Job `107507414304`: SUCCESS
- Artifact ID `10792097181`
- Artifact ZIP SHA256 `48a8eae15b567f10ec889861c89f1c03c1d6a79b72e43479abcbfbbe6c084acf`
- Dylib SHA256 `bd7ca8773dca7e26ef989821c3aea3a5454cffc94d6cf0039ddb35cbb7dff1dc`
- Dylib size `1337776` bytes
- Mach-O: thin arm64 dylib
- Independent ZIP/dylib hash verification: PASS

Device acceptance required:

1. Search at least two method names and return to M4.3 search page; confirm `搜索记录 · n/50` appears directly below the main search card and above the status card.
2. Tap a history row; confirm the value is copied into the visible `方法名` field and **no search starts automatically**.
3. Manually press `搜索` after autofill; confirm the selected history query searches normally.
4. Reopen/restart the menu and confirm history persists; repeated queries deduplicate and move to the top; only newest 50 remain.
5. Runtime Switch/Number/Slider/Button auto-execute regression.
6. Static Button and compatible MOVZ/MOVK Number/Slider regression.
7. Regress Chain V2, ordinary Static Switch, Runtime `/0-/8`, and suffixless generated binaries.

Known architectural boundary:

- Static dynamic V1 changes generated executable ON-variant instructions through the transactional Runtime Patch executor. On targets that prohibit RX→RW executable-page mutation, this path may fail closed. Future Static Dynamic V2 should use generated RW value cells + parameterized stubs.
- Static V1 intentionally does not reinterpret arbitrary Enabled bytes as Int32/Float or guess instruction semantics.

Next engineering work after device evidence:

- Accept/reject the corrected M4.3 search-history placement and autofill-only interaction on device.
- If executable-page mutation is blocked, implement Static Dynamic V2 with RW value cells + generated parameterized stubs.
- Continue Chain typed-row/enum/object-source work after the control-binding regression matrix is accepted.
