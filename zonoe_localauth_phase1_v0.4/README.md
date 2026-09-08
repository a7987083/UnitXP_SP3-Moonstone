# Zonoe LocalAuth Phase1 v0.4 — Deep Auth Route Probe

v0.3 proved that the SDK login callback completes successfully while no request is observed at the base `NSURLSession` / `NSURLConnection` hooks. The likely causes are private `NSURLSession` subclasses overriding task creation, delegate-based task APIs, or an SDK-specific networking layer.

## v0.4 changes

- Keeps the original SDK UI and original login behavior unchanged.
- Hooks every currently loaded subclass of `NSURLSession`, not only the public base class.
- Covers both completion-handler and delegate-style `dataTask` APIs plus common upload APIs.
- Re-scans subclasses when `SMPCQuickChannel -login` begins and again after 0.5s / 2s.
- Inventories Objective-C classes/selectors from Pandora/QuickSDK images for method names containing login/auth/account/user/register/password/http/request/session/token/network.
- Logs only sanitized route metadata and caller image/RVA; never logs request bodies, passwords, cookies, or token values.

## Test

Inject only `ZonoeLocalAuth_Phase1_v0.4.dylib`.

1. Start the game.
2. Let the original SDK login UI appear.
3. Perform one normal login attempt.
4. Optionally open Register and Forgot Password once if those flows will also be migrated.
5. Quit and send `Documents/ZonoeLocalAuth_Phase1_v0.4.log`.

Important tags:

- `[HOOK]` concrete NSURLSession subclass hooks
- `[SCAN]` subclass scan passes
- `[OBJC]` Pandora/QuickSDK candidate classes and selectors
- `[HTTP]` sanitized request route
- `[AUTH]` SDK login window boundaries
