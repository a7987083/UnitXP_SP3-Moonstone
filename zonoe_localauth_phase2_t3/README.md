# Zonoe LocalAuth Phase2 T3

Explicit Auth Adapter for the authorized test project.

## Purpose

The host project calls `ZonoeAuthLogin(username, password, completion)` directly. The adapter sends the supplied credentials to the project's own `/auth/login` endpoint and returns the parsed result to the caller.

This T3 adapter does **not** install runtime interception into Pandora/QuickSDK request paths and does not alter their network methods.

## Endpoint

`POST http://43.242.203.214/auth/login`

JSON request:

```json
{"username":"...","password":"..."}
```

Expected result messages include:

- `AUTH_OK`
- `PASSWORD_INVALID`
- `ACCOUNT_NOT_FOUND`
- `ACCOUNT_DISABLED`

The adapter logs only credential lengths and result metadata; raw usernames/passwords are not written to its log.

## Exported API

```objc
typedef void (^ZonoeAuthCompletion)(BOOL ok, NSString *message, NSDictionary *accountInfo);
void ZonoeAuthLogin(NSString *username, NSString *password, ZonoeAuthCompletion completion);
```

## Scope

T3 validates the explicit client Auth Adapter -> own server -> own DB path. Session issuance and downstream SDK-compatible login state are intentionally deferred to T4.
