# zonoe / HFASign handoff

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `work/hfapatchipa-ksign-v3`
- Current version: `v3.0.0-alphaone3` (build 103)
- Stable reconstruction baseline: Ksign `03a3a9c86897d79f9faf8106037b9971841d56a0`
- Code commit: `5ee8ce6d98b7f93b6d775dea0ccde2fe375280dd`
- Published artifact commit: `316645e5a996639e38748584392ca5252a5449f4`
- GitHub Actions run: `34133291093` (`success`)
- IPA: `HFASign/dist/zonoe_v3.0.0-alphaone3_TrollStore.ipa`
- SHA256: `facd82e07fcb9f87f900287cfa3e70fd419b10247a5440ad4d518409e5f32c9a`

The authoritative build is `.github/workflows/hfasign-build.yml`. It reconstructs the app from the pinned Ksign commit and the ordered patch stack. Historical patches are immutable; alphaone3 adds `0049-zonoe-alphaone3-fix-navigation-and-clipboard-completion.patch`.

## alphaone3 changes

- Removed the window-level keyboard dismissal tap recognizer that intercepted SwiftUI navigation rows.
- Preserved interactive keyboard dismissal through `scrollDismissesKeyboard` without a global touch recognizer.
- Changed Apple App Store results to native `NavigationLink` destinations, including iOS 16.
- Clipboard source import now clears candidates and closes the prompt only after storage succeeds.

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
- Signing child navigation, Apple App Store detail navigation and clipboard prompt dismissal require device regression.

See `docs/PROJECT_HANDOFF.md`, `docs/BUILD.md`, and `docs/KNOWN_ISSUES.md` for older architecture and risks.
