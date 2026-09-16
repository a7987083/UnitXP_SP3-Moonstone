# HANDOFF

Current target: JSONCapture g4 Chinese UI + on-device JSON recovery.

Base/device evidence:
- g3 base commit: `d0c10fc1d4df1ab0e8151f4a91ae3bca050242f3`.
- g2/g3 capture path previously device-verified for ENCM -> Lua 5.3 compile success.
- g3 persistence previously device-verified across relaunch with 10,168 unchanged index entries seeded/skipped.

Current g4 architecture:
1. g3/g2 remains capture core.
2. Chinese floating UI reads core counters directly because g4 includes g3 in the same translation unit.
3. Historical re-decrypt and static JSON recovery use serial background queues.
4. `JCG4CaptureBusy()` blocks/yields low-priority work while disk capture is active or queued disk bundle work remains.
5. On-device recovery writes `recovered_json`, `recovered_partial`, `MobileRecovery.report.json`, `MobileRecovery.status.json`, `MobileRecovery.index.json`, and `MobileDecrypt.index.json`.
6. Dynamic Lua business logic is not executed; only the static data-construction allow-list is interpreted.

Validated build:
- Source/artifact commit: `e1ab528ad2eadfd22fef56be48eb5baa06988081`.
- GitHub Actions run `35134708046`: success.
- Artifact ID `10463042415`.
- GitHub artifact digest: `sha256:3aa00f467d013c1c11f21ee9301513dec8cb6cbcf8e2116dc736b37c946da890`.
- Dylib SHA256: `9a6c48526c0fbd8a2bb0333edc97f9e4b904f4e472b56af608eb23c76b76970c`.
- Release ZIP SHA256: `c994666cca1cedfc22ee07e55a00b815117ec26cd5de9764d06f3c55aff019d0`.

Validation distinction:
- Source implementation: complete for g4 initial version.
- CI compile/package: passed.
- Artifact hash/format: checked.
- Real-device g4 UI/recovery: NOT yet validated; user must install/test.
- The g3 capture core still performs its already validated lightweight ENCM decode + compile-only check inline. The new historical re-decrypt and JSON reconstruction are queued/yielding. A full raw-only P0 refactor belongs to g4.1 only if profiling shows the inline path affects capture.
