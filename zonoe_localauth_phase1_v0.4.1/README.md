# Zonoe LocalAuth Phase1 v0.4.1 — Safe Auth Route Probe

Purpose: fix the startup crash seen in v0.4 while continuing to locate the Pandora/QuickSDK authentication request boundary.

## Root cause addressed

v0.4 installed NSURLSession hooks globally during dylib initialization and also added replacement methods to subclasses that only inherited those selectors. Depending on class enumeration order, a subclass could store an already-replaced inherited IMP as its "original" implementation, causing recursive re-entry when Foundation networking ran. Because this happened during startup, the app could crash immediately after injection.

## v0.4.1 changes

- No NSURLSession swizzling during the constructor/startup phase.
- Only `SMPCQuickChannel -login` and `-loginCallBack:` are installed at startup.
- Network hooks are installed only after the user starts the SDK login flow.
- Only methods actually declared by each NSURLSession class are replaced; inherited methods are never added to subclasses.
- Replacement IMPs are never stored as originals.
- Pandora/QuickSDK selector inventory remains diagnostic-only.
- Request bodies, passwords, cookies, and token values are never logged.

## Test

1. Remove v0.4 and inject only `ZonoeLocalAuth_Phase1_v0.4.1.dylib`.
2. First verify the app reaches the normal game/SDK login UI without crashing.
3. Perform one SDK login attempt.
4. Send `Documents/ZonoeLocalAuth_Phase1_v0.4.1.log`.

Expected tags: `[READY]`, `[AUTH]`, `[SCAN]`, `[OBJC]`, and, if the route is covered, `[HTTP]`.
