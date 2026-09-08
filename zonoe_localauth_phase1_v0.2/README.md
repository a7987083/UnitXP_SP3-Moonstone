# Zonoe LocalAuth Phase1 v0.2 — Channel Provider Replay

Purpose: validate the QuickSDK channel-provider boundary without forging the final game login notification.

## Static basis

The target `SMPCQuickChannel -login` enters Pandora and registers `loginCallBack:` for `kPandoraSDKNotifyLogin`.
The original `loginCallBack:` consumes `username`, `gametoken`, `time`, and `sessid`, rebuilds QuickChannel login state/session, then forwards the original channel result into `SDKCooperater`.

## v0.2 behavior

- Hooks `SMPCQuickChannel -login` instead of `SMPCQuickSDK -login`.
- Hooks `SMPCQuickChannel -loginCallBack:` only to capture the four raw Pandora login fields after a normal login attempt reaches the callback.
- Local replay calls the *original* `SMPCQuickChannel -loginCallBack:` with the cached raw callback.
- `SDKCooperater`, `/v2/users/checklogin`, `PlugManager`, and the game login callback remain original.
- No full token/session value is written to the diagnostic log; only lengths and non-secret flow markers are logged.

## Test

1. Remove Phase1 v0.1 and inject only `ZonoeLocalAuth_Phase1_v0.2.dylib`.
2. First run has no v0.2 raw cache, so it uses the original Pandora/channel login. Complete one successful login.
3. Fully terminate the app and launch again.
4. When the v0.2 chooser appears, select `本地通道回放（测试）`.
5. Expected: Pandora login UI is skipped, while the original channel callback -> SDKCooperater -> checklogin -> game login chain still runs.

Diagnostic log:
`Documents/ZonoeLocalAuth_Phase1_v0.2.log`
