# HANDOFF

## Current work line

ZonoPatch `v0.5.13 / M5.13 InputService`.

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/m5.13-input-service-v1`
- Build commit: `98c06095e27959d55e4b858a5baecebac91eeb1f`
- Final CI Run: `36978655147` — SUCCESS
- Artifact ID: `11214802305`
- Artifact digest: `sha256:55aaf87c4a047b9d518e61a834d526b5656cb24c411e409d9ff3b048c8e0be3b`

## Input architecture

- Offset address: custom HexAddress pad.
- Patch bytes: custom HexBytes pad.
- Runtime numeric argument: custom NumericFlexible pad.
- Runtime title/description: system UITextField managed by KeyboardService.
- Custom pads are presented from the existing controller hierarchy and do not create/make-key a second UIWindow.
- System-text responder recovery is bounded to two attempts.

## Built variants

- `ZonoPatch_v0.5.13_M5.13_InputService_Normal.dylib`
  - SHA256: `e8b703b04f56a0231820ad49e94d648b21b9676ebfe9af524852a48d1894ded7`
  - Size: `1402848` bytes.

- `ZonoPatch_v0.5.13_M5.13_InputService_ExternalOnly.dylib`
  - SHA256: `c5900d01b6fa72f77cf84be28c37afb38bb472dfd483af8f221de699185f8a34`
  - Size: `1402832` bytes.

## Validation boundary

- Source: YES
- Commit: YES
- Compile: YES
- Binary verify: YES
- Artifact: YES
- Runtime: NO
- Device: NO

Next acceptance test is the problem game shown by the user: custom Offset/Runtime numeric input must work without the game's Send input bridge appearing; system-text fields must be separately tested for responder recovery.
