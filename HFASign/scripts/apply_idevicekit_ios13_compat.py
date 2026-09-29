#!/usr/bin/env python3
from pathlib import Path

root = Path("HFASignBuild/IDeviceKit")
manifest = root / "Package.swift"
logger = root / "Sources/IDeviceSwift/Extensions/Logger++.swift"
uttype = root / "Sources/IDeviceSwift/Extensions/UTType++.swift"
heartbeat = root / "Sources/IDeviceSwift/Heartbeat/Heartbeat+start.swift"

for path in (manifest, logger, uttype, heartbeat):
    if not path.exists():
        raise SystemExit(f"IDeviceKit iOS13 compat: missing {path}")

manifest_text = manifest.read_text()
old_target = ".iOS(.v15)"
if manifest_text.count(old_target) != 1:
    raise SystemExit(
        f"IDeviceKit iOS13 compat: expected one {old_target}, "
        f"found {manifest_text.count(old_target)}"
    )
manifest.write_text(manifest_text.replace(old_target, ".iOS(.v13)", 1))

# OSLog.Logger and OSLogMessage require iOS 14. Heartbeat logging is diagnostic
# only, so provide a tiny String-based logger that keeps the same call sites
# functional on iOS 13 without changing heartbeat behavior.
logger.write_text('''// Generated compatibility shim for zonoe iOS 13 builds.\n\nimport Foundation\n\nenum IDeviceHeartbeatLogger {\n    static func debug(_ message: @autoclosure () -> String) { emit("debug", message()) }\n    static func info(_ message: @autoclosure () -> String) { emit("info", message()) }\n    static func error(_ message: @autoclosure () -> String) { emit("error", message()) }\n\n    private static func emit(_ level: String, _ message: String) {\n        print("[IDevice][Heartbeat][\\(level)] \\(message)")\n    }\n}\n''')

heartbeat_text = heartbeat.read_text()
if "import OSLog\n" not in heartbeat_text:
    raise SystemExit("IDeviceKit iOS13 compat: Heartbeat+start.swift OSLog import not found")
heartbeat_text = heartbeat_text.replace("import OSLog\n", "", 1)
replacements = {
    "Logger.heartbeat.debug(": "IDeviceHeartbeatLogger.debug(",
    "Logger.heartbeat.info(": "IDeviceHeartbeatLogger.info(",
    "Logger.heartbeat.error(": "IDeviceHeartbeatLogger.error(",
}
changed = 0
for old, new in replacements.items():
    count = heartbeat_text.count(old)
    changed += count
    heartbeat_text = heartbeat_text.replace(old, new)
if changed == 0 or "Logger.heartbeat" in heartbeat_text:
    raise SystemExit("IDeviceKit iOS13 compat: heartbeat logger replacement incomplete")
heartbeat.write_text(heartbeat_text)

# This extension only exports convenience UTTypes and has no consumers inside
# IDeviceSwift. UniformTypeIdentifiers' UTType API is iOS 14+, while Ksign owns
# its separate app-level UTType helpers. Remove only this unused wrapper helper.
uttype.write_text('''// Intentionally empty for zonoe iOS 13 compatibility.\n// Ksign provides its own app-level UTType helpers.\n''')

print(f"IDeviceKit iOS13 compat applied; heartbeat log call sites replaced: {changed}")
