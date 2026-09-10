# zonoe / HFASign Handoff

## Repository
- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `work/hfapatchipa-ksign-v3`
- Product: `zonoe`
- Version: `v3.0.0-alphaone10`

## Stable Baseline
- Behavioral/source baseline commit: `1bfa241813e71aecebf5b7607a23c3c3f486e172`
- Release metadata commit produced by CI: `0015366ce891041f61c3fada9385b309346f14c9`
- GitHub Actions run: `34473371221` (`Build HFASign v3 alpha`, Run #124)
- Build result: `success`
- IPA: `zonoe_v3.0.0-alphaone10_TrollStore.ipa`
- IPA SHA256: `09a6def300ddc3a9a332df31b41d60b8bb3d206f2522a8b63ee90f421ee7b403`

## Baseline Status
User has confirmed the current app is usable as the stable baseline. Do not refactor or change stable behavior without a concrete requirement.

## UDID Protocol Constraint
The no-hook UDID bridge is fixed to `127.0.0.1:14302` end-to-end:
- Profile: `http://127.0.0.1:14302/profile.mobileconfig`
- Profile Service callback: `http://127.0.0.1:14302/udid`
- Result store: `http://127.0.0.1:14302/bridge/result/<nonce>`
- ACK: `POST /bridge/ack/<nonce>`

`alphaone10` retry-safe result delivery is preserved, but dynamic fallback ports are disabled because the consumer protocol is fixed to 14302.

## Key Build Chain
`HFASign/scripts/reconstruct_alphaone10.sh`
1. Clone pinned `Nyasami/Ksign` commit `03a3a9c86897d79f9faf8106037b9971841d56a0`
2. Apply canonical patch series from `HFASign/patch-series-alphaone10.txt`
3. Run `apply_alphaone10_udid_reliability.py`
4. Run `apply_alphaone10_udid_fixed_port_hotfix.py`
5. Build via `.github/workflows/hfasign-build.yml`

## Stable Behaviors — Do Not Break
- Existing signing flow and IPA output
- SigningView navigation currently verified usable
- Existing source formats currently usable
- File/ZIP/import/settings flows currently usable
- UDID callback bridge fixed to port 14302
- Historical patches remain immutable; append new patches/scripts only

## Regression Strategy
If a regression appears, compare the problem commit against `1bfa241813e71aecebf5b7607a23c3c3f486e172` first. Prefer root-cause fixes and minimal diffs. Do not perform architecture cleanup unless required by the bug or new feature.

## Next Task
No forced refactor. Continue only from a concrete new feature or regression request. For source compatibility work, preserve existing formats and add protocol-specific logic without cross-format fallback changes unless validated by real samples.
