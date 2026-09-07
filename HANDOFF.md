# zonoe / HFASign handoff

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `work/hfapatchipa-ksign-v3`
- Current version: `v3.0.0-alphaone4` (build 104)
- Stable reconstruction baseline: Ksign `03a3a9c86897d79f9faf8106037b9971841d56a0`
- Code commit: `42917ee29dc7f62ce7d40ca9626d6e98af6fa1a1`
- Published artifact commit: `a6cdcd62235022d0313cad38293a5321343aa28e`
- GitHub Actions run: `34149749914` (`success`)
- IPA: `HFASign/dist/zonoe_v3.0.0-alphaone4_TrollStore.ipa`
- SHA256: `cbe2182e7f4a350f594bdfb1b1032d47142f771f7dfcaa0a25301a26fa82a810`

The authoritative build is `.github/workflows/hfasign-build.yml`. It reconstructs the app from the pinned Ksign commit and the ordered patch stack. Historical patches are immutable; alphaone4 adds `0050-zonoe-alphaone4-fix-signing-navigation-and-keyboard-dismissal.patch` and `0051-zonoe-alphaone4-build-identity.patch`.

## alphaone4 changes

- SigningView is now pushed through a stable UUID-based `NavigationPath` route instead of a Boolean destination derived from an optional Core Data object.
- The route is appended after the IPA action dialog dismissal state completes, preventing nested push/pop transaction conflicts.
- Global keyboard dismissal is restored, but the window recognizer remains disabled unless the keyboard is visible and uses `cancelsTouchesInView = false`.

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
- Signing child navigation and keyboard dismissal require device regression; CI verifies construction, compilation and packaging only.

See `docs/PROJECT_HANDOFF.md`, `docs/BUILD.md`, and `docs/KNOWN_ISSUES.md` for older architecture and risks.
