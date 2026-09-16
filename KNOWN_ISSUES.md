# KNOWN_ISSUES

1. The device-validated g3 core currently performs its lightweight ENCM XOR decode and Lua compile-only check inline during TextAsset handling. g4 queues historical re-decrypt and JSON reconstruction, which are the heavier new tasks. If device profiling shows inline decode/compile stalls capture, g4.1 should refactor the capture core to raw-only P0 + deferred decode/compile P1.
2. `打开JSON目录` prefers the `filza://` URL scheme. If Filza is absent or its build does not register the scheme, the UI falls back to showing the filesystem path.
3. Static recovery intentionally stops on dynamic Lua opcodes such as CALL/CLOSURE. Already reconstructed tables are retained as partial output; business logic Lua is not executed.
4. The mobile recovery engine is a native port of the Windows static-recovery model, but parity on the user's full dataset requires real-device comparison.
5. Overlay presentation must be validated against the target Unity Metal window on device; UIKit scene-aware window setup is used for iOS 13+ with an iOS 12 fallback.
