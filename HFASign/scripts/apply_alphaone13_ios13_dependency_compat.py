#!/usr/bin/env python3
from pathlib import Path

root = Path("HFASignBuild/IDeviceKit")

package = root / "Package.swift"
text = package.read_text()
old = "\t\t.iOS(.v15),"
new = "\t\t.iOS(.v13),"
count = text.count(old)
if count != 1:
    raise SystemExit(f"iOS13 dependency compat: expected one IDeviceKit iOS 15 platform declaration, found {count}")
package.write_text(text.replace(old, new, 1))

logger_path = root / "Sources/IDeviceSwift/Extensions/Logger++.swift"
logger_path.write_text("""//
//  Logger++.swift
//  iOS 13 compatibility shim
//

import Foundation
import os.log

enum IDeviceCompatLogger {
    private static let heartbeat = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "IDeviceKit",
        category: "Heartbeat"
    )

    static func debug(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: heartbeat, type: .debug, message())
    }

    static func info(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: heartbeat, type: .info, message())
    }

    static func error(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: heartbeat, type: .error, message())
    }
}
""")

heartbeat_path = root / "Sources/IDeviceSwift/Heartbeat/Heartbeat+start.swift"
heartbeat = heartbeat_path.read_text()
if "Logger.heartbeat." not in heartbeat:
    raise SystemExit("iOS13 dependency compat: Logger.heartbeat call sites not found")
heartbeat = heartbeat.replace("Logger.heartbeat.", "IDeviceCompatLogger.")
heartbeat = heartbeat.replace("import OSLog\n", "")
heartbeat_path.write_text(heartbeat)

uttype_path = root / "Sources/IDeviceSwift/Extensions/UTType++.swift"
uttype = uttype_path.read_text()
old_extension = "extension UTType {"
if old_extension not in uttype:
    raise SystemExit("iOS13 dependency compat: IDeviceKit UTType extension not found")
uttype = uttype.replace(old_extension, "@available(iOS 14.0, *)\nextension UTType {", 1)
uttype_path.write_text(uttype)

checks = {
    "package target": ".iOS(.v13)" in package.read_text(),
    "legacy os_log shim": "IDeviceCompatLogger" in logger_path.read_text(),
    "no Logger heartbeat calls": "Logger.heartbeat." not in heartbeat_path.read_text(),
    "UTType availability guard": "@available(iOS 14.0, *)" in uttype_path.read_text(),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("iOS13 dependency compat invariant failure: " + ", ".join(failed))

print("iOS13 dependency compat applied: IDeviceKit platform + OSLog/UTType back-deployment")
