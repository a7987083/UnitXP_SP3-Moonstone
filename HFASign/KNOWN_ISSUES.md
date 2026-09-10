# zonoe / HFASign Known Issues

## Stable Baseline
`v3.0.0-alphaone10` at source baseline commit `1bfa241813e71aecebf5b7607a23c3c3f486e172` is the current stable functional baseline.

## Current Known Issues
No blocking issue is currently open for the stable baseline.

## Closed — UDID callback port mismatch
Root cause: alphaone10 reliability work introduced a dynamic local port pool while the no-hook nonce bridge consumer continued reading `127.0.0.1:14302/bridge/result/<nonce>`. This could split Profile POST/result retrieval across different localhost ports.

Resolution: restore fixed port `14302` end-to-end while preserving retry-safe GET/ACK result-store behavior.

Relevant implementation:
- `HFASign/scripts/apply_alphaone10_udid_reliability.py`
- `HFASign/scripts/apply_alphaone10_udid_fixed_port_hotfix.py`
- `HFASign/scripts/reconstruct_alphaone10.sh`

Validation:
- GitHub Actions Run #124 / `34473371221`: success
- Current app confirmed usable by user

## Regression Rule
Any future regression should first be diffed against stable source commit `1bfa241813e71aecebf5b7607a23c3c3f486e172` before adding a workaround.
