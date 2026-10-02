# HANDOFF

## Current work line

ZonoPatch `v0.5.12 / M5.12 OffsetClosure`.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Active branch: `recovery/m5.12-historical-offset-closure`
- Cross-dylib API baseline: `047a2fea1e49cde643961c36bb841a44b4ee7161`
- Dual-variant build anchor: `e0fda5a52b786eab11724152068efa5a5da396ce`
- CI Run: `36961499728` — SUCCESS
- Artifact ID: `11208715483`
- Artifact digest: `sha256:78cef02e27d8397be7d825d496cb5b9eab781e573c941e53bab1c1c28f48661a`

## Cross-dylib activation

The exported C ABI includes `ZonoePatchActivate()` in `iosruntimepatchmenu/src/ZonoePatchAPI.h`.

`ZonoePatchActivate()` enters the existing deferred bootstrap path and is idempotent. Caller dylibs can resolve it with `dlsym(RTLD_DEFAULT, "ZonoePatchActivate")`.

## Built variants

- `ZonoPatch_v0.5.12_M5.12_OffsetClosure_Normal.dylib`
  - Original cold-launch behavior: ZN launcher appears.
  - SHA256: `3392522fef7d7abae1fa48596bf90374737881767695c901d93be05c0526dd69`
  - Size: `1402544` bytes.

- `ZonoPatch_v0.5.12_M5.12_OffsetClosure_ExternalOnly.dylib`
  - Cold launch creates no ZN launcher.
  - Waits for `ZonoePatchActivate()` from a peer dylib.
  - Programmatic activation does not create a transient launcher first.
  - SHA256: `f357fa2882cdbbe088b7c6e94acecc2eda5777249bb72b66caa38d5006ff7431`
  - Size: `1402544` bytes.

Both builds use the same source tree; ExternalOnly is selected by `ZN_EXTERNAL_ONLY=1`.

## Validation boundary

- Source changed: YES
- Commit: YES
- Compile: YES
- Binary export verification: YES
- Artifact: YES
- Runtime: NO
- Device: NO

M5.12 OffsetClosure behavior itself was not reimplemented. Device acceptance remains required for launcher behavior and actual peer-dylib activation.
