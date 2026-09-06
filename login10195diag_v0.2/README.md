# Login10195Diag v0.2

Read-only runtime diagnostics for the supplied arm64 UnityFramework build.

Verified UnityFramework SHA256:

`bb0229411aa0b49d99b23619a97108dc8eea70490f65de444397867e01f411a3`

## Hook targets

- `UnityFramework + 0x005A6914` — constructor/send path that writes message id `0x27D3` / `10195`.
- `UnityFramework + 0x0107FEBC` — `-[SDKCooperater beginQuickSDKInit]`.
- `UnityFramework + 0x01085044` — `-[DCNetworkInterface addSyncHttpRequest2:param:method:]`.
- `UnityFramework + 0x0109BFBC` — `-[SDKNetworkManager updateServerListWithChannelParams:handler:]`.

The Objective-C method type encodings were verified from Mach-O metadata:

- `beginQuickSDKInit`: `v16@0:8`
- `addSyncHttpRequest2:param:method:`: `@40@0:8@16@24@32`
- `updateServerListWithChannelParams:handler:`: `v32@0:8@16@?24`

## Output

The dylib writes:

`Documents/Login10195Diag_v0.2.log`

Expected markers:

- `[QuickInit]`
- `[ServerList]`
- `[HTTP2]`
- `[10195]`

`[10195] CALLER` records the caller image and UnityFramework RVA so the caller-side condition can be reconstructed from a good-vs-bad run.

## Safety

This version is diagnostic only. It does not modify HTTP results, message buffers, IP addresses, QuickSDK state, or 10195 arguments.
