# VALIDATION

## Implementation baseline

`2f68b48907887bad20d4e9935c99ae039369beb6` was validated by GitHub Actions Run `35480212352`.

The run passed source policy/API auditing, macOS Objective-C compilation and runtime tests with warnings-as-errors, a Thread Sanitizer stress run, iPhoneOS arm64 compilation, static-library creation, and binary forbidden-dependency/symbol auditing.

The macOS runtime log reported:

`SatellaCore full security-test port tests passed`

The iPhoneOS build used Xcode 16.4, iPhoneOS 18.5 SDK and a minimum deployment target of iOS 12.0.

## Delivery rule

Documentation-only changes after the implementation baseline must also pass the complete workflow. The final source ZIP and static library must be taken from the artifact produced by the final successful delivery run. Their authoritative hashes are the values in that artifact's `SHA256.txt`.

## What CI does not prove

CI does not prove integration with a separate consumer Xcode project or behaviour on a physical iOS device. Those remain separate validation states.
