# Zonoe LocalAuth Phase2 T1 — Fixed-Failure Route Test

Purpose: verify that the existing Pandora SDK login UI reaches the selected provider boundary and that `/Api/Common/Login` can be handled without contacting the original SDK account service.

## Behavior

- Keeps the original Pandora/QuickSDK login UI unchanged.
- Intercepts only `KCNetworkManager -KCNetworkHandleWithDomain:andBodyStr:andLoad:` when `domain == /Api/Common/Login`.
- Suppresses that original account request.
- Waits until the SDK installs its existing `connectionCallBcak` block, then feeds the SDK a failure dictionary:

```json
{"result":false,"msg":"ZONOE_LOCAL_AUTH_TEST"}
```

- All non-login Pandora requests pass through to the original method.
- Does not log username, password, request body content, token values, or cookies. It logs only route, body length, and test-state markers.

## Expected result

1. Inject only `ZonoeLocalAuth_Phase2_T1.dylib`.
2. Launch the game and open the SDK login UI normally.
3. Enter any test username/password and press Login.
4. The SDK UI should show `ZONOE_LOCAL_AUTH_TEST` instead of completing login.
5. Send `Documents/ZonoeLocalAuth_Phase2_T1.log`.

If the SDK UI shows the marker, T1 is passed: the chosen provider boundary is correct and the original account-service request is no longer required for that test path.
