# HANDOFF

## Current target

`1.3.0-result-parity` compares Objective-C result semantics against `Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e` while preserving useful OC-only test controls behind a separate ExtendedTesting mode.

## Default parity profile

`SJBehaviorModeUpstreamParity` is the default. In this mode:

- CanPay behaves as the upstream always-installed hook.
- Empty product responses use the one-time fallback cache even if the OC-only fallback toggle is changed.
- Product fallback objects retain identity across subsequent empty responses.
- Non-empty responses preserve invalid product identifiers.
- Transaction simulation remains independent from product fallback and its replaced getters are dynamic.
- Price override returns literal `0.01`.
- Receipt environment remains `Production`.
- Disabled conditional receipt/observer behaviour is pass-through/no synthetic output rather than a `FeatureDisabled` business error.
- Receipt time values follow the Swift source evaluation order.
- Product/delegate/observer state does not receive extra OC locking in the strict parity path.

## Extended testing profile

`SJBehaviorModeExtendedTesting` retains OC-only controls such as custom price/environment and synchronized shared-state management. It is useful for isolated security tests but must not be presented as Swift result parity.

## Remaining hard gaps

Real StoreKit object classes, transparent URLSession task semantics, live dyld behaviour, and physical-device runtime equivalence remain unresolved. Do not label those rows complete based on model tests.
