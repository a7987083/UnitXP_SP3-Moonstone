# ROADMAP

## v1.3.0-result-parity

- [x] Split strict upstream result semantics from OC-only extended controls.
- [x] Preserve invalid IDs and product identity in the model path.
- [x] Make disabled conditional model paths pass-through/no synthetic result.
- [x] Align strict price/environment/time evaluation semantics.
- [x] Align migrated shared-state locking behaviour in UpstreamParity.
- [x] Replace absolute runtime/StoreKit audit bans with explicit review gating.
- [ ] macOS/iPhoneOS CI validation for this revision.
- [ ] Real StoreKit object/runtime parity.
- [ ] Real URLSession task/response/error/callback parity.
- [ ] Physical-device validation.

## v1.2.0-upstream-parity

- [x] Re-audit against `Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e`
- [x] Remove invented transaction/product-catalog dependency
- [x] Restore dynamic TransactionHook getter semantics
- [x] Restore observer object identity and duplicate-abort semantics
- [x] Restore product response identity and literal `0.01` behaviour
- [x] Restore upstream receipt payload/signature/environment/fallback/timestamp semantics
- [x] Restore URLHook pass-through decision semantics
- [x] Expand runtime regression tests
- [x] Add upstream parity source audit and chain it into `source_audit.py`
- [x] Local source policy/parity audit
- [ ] macOS `-Werror` compile and runtime tests for this revision
- [ ] Thread Sanitizer run for this revision
- [ ] iPhoneOS arm64 `-Werror` compile for this revision
- [ ] Binary dependency/symbol audit for this revision
- [ ] Consumer Objective-C project integration
- [ ] Physical-device regression test

## Next task

Run the existing `satella-core-ci.yml` pipeline against this revision, then validate the consumer project's failing cases on device and compare emitted JSON/transaction observations with the Swift baseline.
