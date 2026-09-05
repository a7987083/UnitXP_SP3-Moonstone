# RuntimeConfig v0.1

Jailbreak/runtime test dylib for the current IL2CPP test game.

## Modes

- **Mode 0 — RuntimeConfig.js**
  - Hooks `AesHelper.CustomDecryptString` after the game decrypts its original startup config.
  - On the first matched startup JSON, exports the original plaintext to `Documents/RuntimeConfig.js` if the file does not exist.
  - On later launches, validates and returns the text from `RuntimeConfig.js` at runtime.
  - Invalid/missing file falls back to the original decrypted string.

- **Mode 1 — Original config + connect redirect**
  - Does not alter decrypted startup JSON.
  - Redirects original `118.145.146.208` connections to the configured target IPv4.
  - Entry ports `80/81/10008` map to target port `81`; `10003` and `7000-7010` preserve their port.

- **Mode 2 — LOGIN_HOST only**
  - Does not modify the IPA or encrypted blob.
  - After original decryption, changes only JSON key `LOGIN_HOST` to the configured target IPv4.
  - Other JSON fields come from the original decrypted config.

Default target: `43.242.203.214`.
Default mode: Mode 0.

## Known build-specific RVAs

Current dump.cs:

- `AesHelper.CustomDecryptString(string)` = `0x186A4B8`
- `AesHelper.CustomDecryptString(byte[])` = `0x186FA64`

The runtime hook resolves `MSHookFunction` first and `DobbyHook` as fallback. If neither hook API exists in the jailbreak environment, Mode 2/Mode 0 override will fall back to the original config and the RC menu/log will show the hook failure.

## Files

- `Documents/RuntimeConfig.js`
- `Documents/RuntimeConfig_v0.1.log`

`RuntimeConfig.js` uses JSON text even though the extension is `.js`; this keeps it directly editable while allowing strict validation through `NSJSONSerialization`.

Mode or target IP changes are persisted with `NSUserDefaults`; restart the game after changing modes for a clean A/B run.
