# Login10195Diag v0.3

Purpose: trace the real outbound path for protocol messages 10003 (0x2713) and 10195 (0x27D3), while retaining the v0.2 QuickSDK diagnostics.

## Log

`Documents/Login10195Diag_v0.3.log`

## Hooks

Business/SDK hooks retained from v0.2:

- UnityFramework + `0x005A6914` — static 10195 candidate
- UnityFramework + `0x0107FEBC` — `-[SDKCooperater beginQuickSDKInit]`
- UnityFramework + `0x01085044` — `-[DCNetworkInterface addSyncHttpRequest2:param:method:]`
- UnityFramework + `0x0109BFBC` — `-[SDKNetworkManager updateServerListWithChannelParams:handler:]`

Socket-level hooks added in v0.3:

- `write`
- `writev`
- `send`
- `sendto`
- `sendmsg`

The tracer scans outbound buffers for the protocol framing observed in the packet captures. When it sees 0x2713 or 0x27D3 it records:

- API name and fd
- peer address
- message id, body length, sequence
- buffer preview
- immediate caller
- symbolized backtrace with UnityFramework RVAs when available

## Test

Run one failed mainland-direct login and one successful proxy login. Compare all `[SOCKET]`, `[SOCKET-10003]`, `[SOCKET-10195]`, `[HTTP2]`, `[ServerList]`, and `[10195]` lines.
