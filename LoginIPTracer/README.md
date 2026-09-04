# LoginIPTracer

Standalone arm64 iOS dylib for authorized diagnostics of the user's own app.

## Captures

- `getaddrinfo()` hostname/service lookups and numeric results
- `connect()` final numeric IPv4/IPv6 endpoint and port
- common `NSURLSession` request URLs
- selected loaded Unity/framework image names

## Runtime log

`<App Sandbox>/Documents/LoginIPTrace.log`

The same records are also emitted through `NSLog` with the `[LOGINTRACE]` prefix.

## Injection

Inject `LoginIPTracer.dylib` into the test IPA using the existing IPA patch/sign pipeline, re-sign the IPA, install it, launch normally, then reproduce startup/login/server-selection. Copy `Documents/LoginIPTrace.log` out of the app container for analysis.

No Frida, Substrate, ElleKit, or jailbreak runtime dependency is required by the dylib itself.
