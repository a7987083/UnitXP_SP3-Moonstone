# zonoe / HFASign Development Changelog

## 2026-09-10 — Stable baseline closure

### Baseline
- Version: `v3.0.0-alphaone10`
- Stable source commit: `1bfa241813e71aecebf5b7607a23c3c3f486e172`
- CI release metadata commit: `0015366ce891041f61c3fada9385b309346f14c9`
- GitHub Actions: Run #124 / `34473371221`
- Build: success
- IPA SHA256: `09a6def300ddc3a9a332df31b41d60b8bb3d206f2522a8b63ee90f421ee7b403`

### UDID Fix
Closed the alphaone10 callback regression caused by dynamic localhost bridge ports. The protocol is again fixed to `127.0.0.1:14302` for profile download, Profile Service POST, result retrieval and ACK lifecycle.

Preserved:
- retry-safe bridge result lookup
- explicit ACK deletion
- background task lifetime improvements

Removed from effective reconstruction:
- dynamic bridge port pool
- `activePort` callback rewriting
- pre-bind availability probe

### Stability Decision
The user confirmed the current app is usable and this state is now the stable functional baseline. No broad refactor is planned. Future work should be incremental and must preserve current behavior unless a specific requirement says otherwise.
