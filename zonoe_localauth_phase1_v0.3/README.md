# Zonoe LocalAuth Phase1 v0.3 — Auth Route Probe

Purpose: locate the real network boundary used by the Pandora/SDK login UI before replacing the account backend with the local test database.

## Design

- Keeps the original SDK login UI and original authentication behavior unchanged.
- Opens a short diagnostic capture window when `SMPCQuickChannel -login` is entered.
- Observes Foundation networking entry points (`NSURLSession` / `NSURLConnection`) only while that authentication window is active.
- Logs request method, host/path, query parameter names, body length, content type, and the first useful caller image/RVA.
- Never logs request bodies, passwords, token values, cookie values, or full credential material.
- Closes the capture window after the original `SMPCQuickChannel -loginCallBack:` completes.

## Why this probe

Phase1 v0.2 proved that the game can enter the original account through the original `SMPCQuickChannel -> SDKCooperater -> checklogin -> game` chain without showing Pandora login again. The next migration target is therefore the account-provider request made after the SDK UI accepts login/register/recovery input.

## Test

1. Remove Phase1 v0.2 and inject only `ZonoeLocalAuth_Phase1_v0.3.dylib`.
2. Launch the game and let the SDK login UI appear normally.
3. Perform one login attempt. A failed-password test account is sufficient if you only want to identify the login endpoint.
4. Optionally enter Register / Forgot Password once if those flows also need to be migrated.
5. Fully quit the app and send:

`Documents/ZonoeLocalAuth_Phase1_v0.3.log`

Important log tags:

- `[IMAGE]` loaded Pandora/QuickSDK images
- `[AUTH]` authentication window start/end
- `[HTTP]` sanitized request route + caller image/RVA
- `[READY]` probe installation complete

This version is diagnostic only. It does not redirect traffic and does not write account data to either SDK or local databases.
