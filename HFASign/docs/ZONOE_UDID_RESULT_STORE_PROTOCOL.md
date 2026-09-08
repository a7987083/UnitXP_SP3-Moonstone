# zonoe UDID Result Store protocol

## Goal

Allow an injected dylib to obtain the device UDID without hooking or swizzling the host application's AppDelegate or SceneDelegate URL callbacks.

## Request

The signed application already contains a unique callback URL scheme in its Info.plist:

- `ZonoeUDIDCallbackScheme`
- `ZonoeUDIDCallbackHost`

The dylib generates a cryptographically-random request nonce and opens:

```text
zonoe://udid?callback=<signed-app-callback-url>&nonce=<request-nonce>
```

Nonce requirements in zonoe:

- 16...128 characters
- alphanumeric, `-`, `_`

## New no-hook path

When `nonce` is present and zonoe successfully prepares the bridge result:

1. zonoe stores `nonce -> UDID` in memory.
2. The result expires after 90 seconds.
3. zonoe opens the signed app's callback URL only to wake the app.
4. The wake URL contains neither `udid` nor `nonce`.
5. The dylib observes `UIApplicationDidBecomeActiveNotification`.
6. The dylib consumes the result using:

```text
GET http://127.0.0.1:14302/bridge/result/<nonce>
```

Successful response:

```json
{"nonce":"<request-nonce>","udid":"<device-udid>"}
```

The result is one-shot: the first successful GET removes it from the store. Missing, invalid, expired, or already-consumed nonces return HTTP 404.

The localhost server is kept alive with the existing short iOS background task while the callback switches back to the signed application, then the background task is ended after the result is consumed.

## Compatibility

Existing callers that do not supply `nonce` keep the legacy behavior:

```text
<callback>://udid-callback?udid=<device-udid>
```

If the new bridge cannot be prepared, zonoe falls back to the same legacy callback behavior instead of silently losing the UDID response.

## Dylib integration

The dylib does not need to receive or parse the callback URL. It only needs to:

1. Read the callback scheme/host from the signed app Info.plist.
2. Generate and retain a nonce.
3. Open `zonoe://udid?...&nonce=...`.
4. Observe `UIApplicationDidBecomeActiveNotification`.
5. GET `/bridge/result/<nonce>` from localhost.
6. Parse `udid` from the JSON body and invoke its own completion block.

No runtime method replacement, Objective-C swizzling, Logos hook, fishhook, AppDelegate hook, or SceneDelegate hook is required.
