# Login10195Diag v0.6 — UnityWebRequest Gate Probe

Purpose: safely locate the startup gate before TX 10195 without instrumenting Lua VM hot-path RVAs.

## What changed from v0.5

v0.5 raw `DobbyInstrument` probes at `0x1137C04/0x1137EA4/0x1138FB0/0x1148A58/0x1148C80` are removed. Those addresses are Lua VM return/mid-instruction points and caused startup instability.

v0.6 instead hooks the concrete Objective-C `UnityWebRequestDelegate` methods present in this UnityFramework:

- `URLSession:dataTask:didReceiveResponse:completionHandler:`
- `handleHTTPResponse:urequest:`
- `URLSession:dataTask:didReceiveData:`
- `URLSession:task:didCompleteWithError:`

It correlates these HTTP events with minimal Agent TCP markers:

- TX 10003 / `0x2713`
- TX 10195 / `0x27D3`
- RX 20003 / `0x4E23`
- RX 20195 / `0x4EE3`

For known startup/login URLs (`login_ing`, `chpy`, `validationRole`, `writNoinfo`, `getresource`, server host), response data gets a short printable preview.

## Test

1. Launch once on direct domestic network until the zone list fails.
2. Fully terminate the game.
3. Launch once with the known-working proxy/Japan route until the zone list succeeds.
4. Send `Documents/Login10195Diag_v0.6.log`.

The useful comparison is the first HTTP request/response/completion that differs before the successful TX 10195.
