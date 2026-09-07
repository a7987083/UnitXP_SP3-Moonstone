# zonoe / HFASign handoff

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `work/hfapatchipa-ksign-v3`
- Current version: `v3.0.0-alphaone2` (build 102)
- Stable reconstruction baseline: Ksign `03a3a9c86897d79f9faf8106037b9971841d56a0`
- Code commit: `b5037ae616d8afb0ab37aa1e62bf8902046dd0d0`
- Published artifact commit: `9bdd336ea532ec911f651aa99180a1880dd38115`
- GitHub Actions run: `34124709373` (`success`)
- IPA: `HFASign/dist/zonoe_v3.0.0-alphaone2_TrollStore.ipa`
- SHA256: `1b13fcd557f5034620ac044895f67d8e06462bd65d9056cf010cbeb37459f968`

The authoritative build is `.github/workflows/hfasign-build.yml`. It reconstructs the app from the pinned Ksign commit and the ordered patch stack. Historical patches are immutable; alphaone2 adds `0048-zonoe-alphaone2-source-certificate-feedback.patch`.

## alphaone2 changes

- Removed the import action from the manual Add Source page.
- Added visible indeterminate progress while a manually entered source is fetched and stored.
- Clipboard candidates appear immediately after paste permission; network validation is deferred until Import.
- Clipboard rows show disabled `已添加` for duplicate hosts and `正在导入…` while importing.
- Copying UDID shows `UDID 复制成功`.
- Selected certificate/profile rows show `已导入：文件名` and remain disabled.
- Certificate status, remaining days and profile metadata labels are Chinese.

## Verification

- Patch stack apply: passed.
- `git diff --check`: passed on reconstructed source.
- Five-source QNQ decoder regression: passed in CI.
- Release iphoneos build, metadata verification, TrollStore packaging and publication: passed.
- The new interaction text/state changes still require device regression.

See `docs/PROJECT_HANDOFF.md`, `docs/BUILD.md`, and `docs/KNOWN_ISSUES.md` for older architecture and risks.
