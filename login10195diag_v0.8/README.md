# Login10195Diag v0.8

Focused diagnostic build for the current two blockers:

1. Third-party SDK account lifecycle vs local account lifecycle.
2. Recharge/pay UI gating and payment call path.

Log file:

`Documents/Login10195Diag_v0.8.log`

Key tags:

- `[ACCOUNT]` login/logout/checkLoginResult
- `[NETSDK]` QuickSDK checklogin/logout/order/pay requests
- `[CAP]` `isFunctionTypeSupported:` result
- `[CALLER]` caller image and Unity RVA for capability/pay/account events
- `[PAY]` pay entry/order/recharge flow

This version is diagnostic only. It does not force capability returns, fake login success, suppress logout, or fake payment success.
