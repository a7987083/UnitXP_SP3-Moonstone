# Development changelog

## v3.0.0-alphaone4

- Replaced the optional-object/Boolean SigningView destination with a stable UUID-based `NavigationPath` route.
- Deferred the signing route append until the IPA action dialog has completed dismissal.
- Restored global keyboard dismissal; its window recognizer is enabled only while the keyboard is visible and never cancels control touches.
- Build 104; workflow run 34149749914 succeeded.

## v3.0.0-alphaone3

- Removed the global window tap recognizer that blocked SwiftUI navigation.
- Restored SigningView child-page navigation.
- Enabled native Apple App Store product details on iOS 16 and later.
- Close and reset the clipboard source prompt after a successful import.
- Build 103; workflow run 34133291093 succeeded.

## v3.0.0-alphaone2

- Source add and clipboard-import state feedback.
- UDID copy confirmation.
- Certificate import filename state and Chinese certificate information.
- Build 102; workflow run 34124709373 succeeded.
