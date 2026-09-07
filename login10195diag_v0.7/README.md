# Login10195Diag v0.7 — SDK / Account / Pay Probe

Purpose: diagnose two remaining private-server issues without modifying game behavior:

1. QuickSDK/account state: init, login, logout, user/session transitions, SDK network request starts, and game bridge callbacks.
2. Recharge/UI capability: `isFunctionTypeSupported:`, plugin manager state, pay entry/callbacks, and channel pay callbacks.

This build intentionally avoids the v0.5 Lua VM hot-path instrumentation.

## Main log tags

- `[SDK]` QuickSDK init/login/logout/pay results
- `[STATE]` snapshots of init/login/user/session/plugin state
- `[CAP]` function capability checks and initial capability map
- `[PLUG]` plugin manager lifecycle
- `[CHANNEL]` channel login/logout callbacks
- `[CHANNELCOOP]` channel cooperater result callbacks
- `[GAMEBRIDGE]` game-side QuickSDK callbacks
- `[PAY]` pay/recharge path
- `[ACCOUNT]` logout/account state path
- `[NETSDK]` QuickSDK network request starts

Sensitive session/token values are masked in state snapshots.

Log file:

`Documents/Login10195Diag_v0.7.log`

Recommended tests:

A. Fresh launch -> SDK login -> enter game -> open any screen where recharge buttons should normally appear.

B. If possible, while the game is running, delete/disable the test SDK account on the external SDK side and observe whether `[ACCOUNT]`, `[NETSDK]`, `[STATE]`, or game bridge callbacks change. If the deletion only takes effect on next launch, relaunch once and keep the same log file.

Read-only diagnostic build: no capability result is forced and no login/pay/account state is modified.
