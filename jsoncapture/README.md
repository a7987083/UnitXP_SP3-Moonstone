# JSONCapture v0.1

Runtime JSON collector for the current HFAMap/Unity iOS target.

## Goal

Open the game and collect JSON that actually enters the process at runtime, without changing the JSON before the game consumes it.

Output root:

`Documents/JSONCapture/`

Subdirectories:

- `network/` — NSURLSession / NSURLConnection response JSON, including delegate and completion-handler paths.
- `parser/` — JSON accepted by `NSJSONSerialization JSONObjectWithData:options:error:`.
- `file/` — JSON loaded through common `NSData` / `NSString` file and URL helpers.
- `decrypt/` — optional output from the known `AesHelper.CustomDecryptString` / `CustomDecryptBytes` RVAs when an available runtime hook API can attach.
- `outgoing/` — JSON produced or sent by the process.

Each new JSON body is saved byte-for-byte as `*.json`, plus a sidecar `*.meta.json` containing source, context, byte size, SHA-256 and capture time.

`JSONCapture.log` records hook status and capture events.

## Deduplication

JSON bodies are deduplicated by SHA-256 for the lifetime of the process. Repeated reads increment the duplicate counter instead of creating another file.

## UI

A movable `JSON` floating button appears after UIKit is ready.

Panel controls:

- `Pause` / `Resume` capture.
- `Clear` captured storage and counters.

The panel shows total captures plus network/parser/file/decrypt counts.

## Current target-specific decrypt probes

These are inherited from the verified RuntimeConfig target mapping for the current UnityFramework build:

- `AesHelper.CustomDecryptString` RVA `0x186A4B8`
- `AesHelper.CustomDecryptBytes` RVA `0x186FA64`

The decrypt layer is optional. It tries `MSHookFunction` first and `DobbyHook` second if either symbol is available. If neither can attach, Foundation/network/file capture remains active.

## Limits / expected blind spots

v0.1 does **not** claim that one launch can copy the server directory `/home/ubuntu/runtime/json`. It captures JSON that actually reaches the iOS process.

Potential blind spots:

- managed/IL2CPP JSON parsers that never cross Foundation APIs;
- custom native HTTP stacks whose plaintext does not pass NSURLSession/NSURLConnection;
- custom binary/AssetBundle config that is not converted to JSON text;
- decrypt functions whose RVA/signature differs from the current target build;
- runtime inline-hook restrictions on jailed iOS.

Network delegate buffering is candidate-based and capped at 128 MiB; individual JSON capture is capped at 256 MiB to avoid turning a large asset download into an in-process memory sink.

## Safety characteristics

- Read/copy only for captured payloads; no replacement of network responses or parser input.
- No connect redirection.
- No mutation of game JSON.
- Internal writes are guarded to avoid recursively capturing JSONCapture's own metadata.
