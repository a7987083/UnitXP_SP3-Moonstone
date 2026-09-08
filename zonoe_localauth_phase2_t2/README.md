# Zonoe LocalAuth Phase2 T2

Purpose: verify that the client-side Pandora login boundary can reach the user's own Auth Gateway endpoint and map its response back into the existing SDK UI.

Target endpoint:

`POST http://43.242.203.214/auth/login`

T2 deliberately does **not** forward the SDK username/password request body because the endpoint is currently plain HTTP. It sends only a fixed probe body and expects JSON such as:

```json
{"ok":false,"message":"ZONOE_T2_SERVER_OK"}
```

The dylib maps `message` into the SDK-compatible failure callback so the existing Pandora login UI should display `ZONOE_T2_SERVER_OK`.

Log:

`Documents/ZonoeLocalAuth_Phase2_T2.log`

Test steps:
1. Inject only `ZonoeLocalAuth_Phase2_T2.dylib`.
2. Open the SDK login UI.
3. Enter any throwaway test values and tap Login once.
4. Expected UI message: `ZONOE_T2_SERVER_OK`.
5. Send the T2 log for verification.

No credential, token, or original request-body values are logged or forwarded in this route-only test.
