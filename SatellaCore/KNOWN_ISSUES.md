# KNOWN_ISSUES

## Remaining result-parity gaps

- Real transparent StoreKit object/runtime parity is not implemented; model objects remain `SJMock*` classes.
- Real URLSession task/response/error/callback/cancel/resume parity is not implemented.
- Live dyld interception/concealment is not implemented.
- A real non-explicit-call runtime path has not yet been validated; the existing model API is still callable explicitly by tests.
- Multi-product verification still follows the upstream-style last cached product choice and therefore inherits unordered-set ambiguity.
- `latest_receipt` raw Base64 bytes can differ because Objective-C uses `NSJSONSerialization` while Swift uses `JSONEncoder`; compare decoded JSON semantics unless byte identity is a specific requirement.
- Physical-device bundle/IDFV behaviour still requires device validation.

## Fixed in 1.3.0-result-parity

- Preserved `invalidProductIdentifiers` for non-empty pass-through product responses.
- Preserved cached fallback-product object identity instead of returning product copies.
- Added `SJBehaviorModeUpstreamParity` and isolated OC-only result overrides behind `SJBehaviorModeExtendedTesting`.
- UpstreamParity ignores OC-only disable switches for the Swift always-installed Delegate/Transaction/CanPay behaviours.
- UpstreamParity price override is always `0.01`; receipt environment is always `Production`.
- Disabled conditional receipt/observer model paths no longer surface `FeatureDisabled` as an application/business error.
- Receipt `now` milliseconds and textual timestamp are evaluated separately in Swift source order.
- UpstreamParity product/delegate/observer shared-state operations no longer add synchronization absent from the Swift source; ExtendedTesting retains synchronization.
- Source auditing now allows reviewed StoreKit/native runtime/dyld code rather than globally rejecting it.
