#!/usr/bin/env python3
from pathlib import Path
import re

root = Path("HFASignBuild")
pbx_path = root / "Ksign.xcodeproj/project.pbxproj"
pbx = pbx_path.read_text()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"rork-usbmux compat: {label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


# Replace the local IDeviceKit products with the pinned local RorkUsbmux package.
pbx = replace_once(
    pbx,
    '''\t\tC42CC1AD2F4370F20064A4A2 /* IDevice in Frameworks */ = {isa = PBXBuildFile; productRef = C42CC1AC2F4370F20064A4A2 /* IDevice */; };
\t\tC42CC1AF2F4370F20064A4A2 /* IDeviceSwift in Frameworks */ = {isa = PBXBuildFile; productRef = C42CC1AE2F4370F20064A4A2 /* IDeviceSwift */; };
''',
    '''\t\tA79870830000000000000003 /* RorkUsbmux in Frameworks */ = {isa = PBXBuildFile; productRef = A79870830000000000000002 /* RorkUsbmux */; };
''',
    "PBXBuildFile products",
)

pbx = replace_once(
    pbx,
    '''\t\t\t\tC42CC1AF2F4370F20064A4A2 /* IDeviceSwift in Frameworks */,
''',
    '''\t\t\t\tA79870830000000000000003 /* RorkUsbmux in Frameworks */,
''',
    "IDeviceSwift framework entry",
)
pbx = replace_once(
    pbx,
    '''\t\t\t\tC42CC1AD2F4370F20064A4A2 /* IDevice in Frameworks */,
''',
    "",
    "IDevice framework entry",
)

pbx = replace_once(
    pbx,
    '''\t\t\t\tC42CC1AC2F4370F20064A4A2 /* IDevice */,
\t\t\t\tC42CC1AE2F4370F20064A4A2 /* IDeviceSwift */,
''',
    '''\t\t\t\tA79870830000000000000002 /* RorkUsbmux */,
''',
    "target package product dependencies",
)

pbx = replace_once(
    pbx,
    '''\t\t\t\tC42CC1AB2F4370F20064A4A2 /* XCLocalSwiftPackageReference "IDeviceKit" */,
''',
    '''\t\t\t\tA79870830000000000000001 /* XCLocalSwiftPackageReference "RorkUsbmux" */,
''',
    "project local package reference",
)

pbx = replace_once(
    pbx,
    '''\t\tC42CC1AB2F4370F20064A4A2 /* XCLocalSwiftPackageReference "IDeviceKit" */ = {
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = IDeviceKit;
\t\t};
''',
    '''\t\tA79870830000000000000001 /* XCLocalSwiftPackageReference "RorkUsbmux" */ = {
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = RorkUsbmux;
\t\t};
''',
    "local package definition",
)

pbx = replace_once(
    pbx,
    '''\t\tC42CC1AC2F4370F20064A4A2 /* IDevice */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = IDevice;
\t\t};
\t\tC42CC1AE2F4370F20064A4A2 /* IDeviceSwift */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = IDeviceSwift;
\t\t};
''',
    '''\t\tA79870830000000000000002 /* RorkUsbmux */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = RorkUsbmux;
\t\t};
''',
    "Swift package product definitions",
)

pbx_path.write_text(pbx)

# AltSourceKit is source-only and its current manifest floor is the next unrelated
# iOS 13 blocker. Its existing iOS 17 Color.resolve use is already availability-guarded.
alt_package_path = root / "AltSourceKit/Package.swift"
alt_package = alt_package_path.read_text()
alt_package = replace_once(
    alt_package,
    "\t\t.iOS(.v14),",
    "\t\t.iOS(.v13),",
    "AltSourceKit iOS deployment target",
)
alt_package_path.write_text(alt_package)

# IDeviceSwift supplied three app-visible types. Keep the Zonoe API/UI shape and
# replace only the implementation underneath it.
import_count = 0
for path in (root / "Ksign").rglob("*.swift"):
    text = path.read_text()
    count = text.count("import IDeviceSwift\n")
    if count:
        import_count += count
        path.write_text(text.replace("import IDeviceSwift\n", ""))
if import_count < 7:
    raise SystemExit(f"rork-usbmux compat: expected >=7 IDeviceSwift imports, found {import_count}")

status_path = root / "Ksign/Backend/Observable/InstallerStatusViewModel.swift"
status_text = status_path.read_text()
if "public class InstallerStatusViewModel: ObservableObject" not in status_text:
    marker = "extension InstallerStatusViewModel {"
    if marker not in status_text:
        raise SystemExit("rork-usbmux compat: InstallerStatusViewModel extension marker missing")
    status_class = '''public class InstallerStatusViewModel: ObservableObject {
\t@Published public var status: InstallerStatus
\t@Published public var uploadProgress: Double = 0.0
\t@Published public var packageProgress: Double = 0.0
\t@Published public var installProgress: Double = 0.0

\tpublic var isIDevice: Bool

\tpublic var overallProgress: Double {
\t\tif isIDevice {
\t\t\treturn (installProgress + uploadProgress + packageProgress) / 3.0
\t\t}
\t\treturn (installProgress + packageProgress) / 2.0
\t}

\tpublic var isCompleted: Bool {
\t\tif case .completed = status { return true }
\t\treturn false
\t}

\tpublic init(
\t\tstatus: InstallerStatus = .none,
\t\tisIdevice: Bool = true
\t) {
\t\tself.status = status
\t\tself.isIDevice = isIdevice
\t}
}

'''
    status_text = status_text.replace(marker, status_class + marker, 1)
status_path.write_text(status_text)

# Pass the already-known app bundle identifier into the Rork staging path.
call_count = 0
for path in [
    root / "Ksign/Views/Library/Install/InstallPreviewView.swift",
    root / "Ksign/Views/Library/Install/BulkInstallProgressView.swift",
]:
    text = path.read_text()
    count = text.count("InstallationProxy(viewModel: viewModel)")
    if count:
        call_count += count
        text = text.replace(
            "InstallationProxy(viewModel: viewModel)",
            "InstallationProxy(viewModel: viewModel, bundleIdentifier: app.identifier)",
        )
        path.write_text(text)
if call_count != 2:
    raise SystemExit(f"rork-usbmux compat: expected 2 InstallationProxy call sites, found {call_count}")

bridge_path = root / "Ksign/Backend/Device/RorkDeviceBridge.swift"
bridge_path.parent.mkdir(parents=True, exist_ok=True)
bridge_path.write_text(r'''import Foundation
import SwiftUI
import UIKit
import RorkUsbmux

extension Notification.Name {
    static let heartbeat = Notification.Name("FR.heartBeat")
}

private struct RorkDeviceBridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class HeartbeatManager {
    static let shared = HeartbeatManager()

    private let stateLock = NSLock()
    private var didStart = false
    private var pulseTimer: DispatchSourceTimer?
    private var foregroundObserver: NSObjectProtocol?

    private init() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.start(false)
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        pulseTimer?.cancel()
    }

    static func pairingFile() -> String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("pairingFile.plist")
            .path
    }

    func start(_ forceRestart: Bool = false) {
        do {
            let pairingFile = try normalizedPairingFile()
            let alreadyStarted: Bool

            stateLock.lock()
            alreadyStarted = didStart || RorkUsbmuxMuxer.started
            if !alreadyStarted {
                didStart = true
            }
            stateLock.unlock()

            if alreadyStarted {
                if forceRestart {
                    _ = RorkUsbmuxNetworkObserver.stop()
                    _ = RorkUsbmuxNetworkObserver.start()
                }
                RorkUsbmux.retargetUsbmuxdAddress()
                RorkUsbmuxNetworkObserver.refreshEndpoint()
                startPulseMonitorIfNeeded()
                return
            }

            do {
                try RorkUsbmux.startWithLogger(
                    pairingFile: pairingFile,
                    logPath: FileManager.default.temporaryDirectory.path,
                    isConsoleLoggingEnabled: false
                )
                RorkUsbmux.retargetUsbmuxdAddress()
                _ = RorkUsbmuxNetworkObserver.start()
                RorkUsbmuxNetworkObserver.refreshEndpoint()
                startPulseMonitorIfNeeded()
            } catch {
                stateLock.lock()
                didStart = false
                stateLock.unlock()
                throw error
            }
        } catch {
            print("RorkUsbmux start failed: \(error.localizedDescription)")
        }
    }

    func checkSocketConnection(timeoutInSeconds: Double = 2.0) -> (isConnected: Bool, error: String?) {
        start(false)
        RorkUsbmuxNetworkObserver.refreshEndpoint()

        let deadline = Date().addingTimeInterval(max(0.1, timeoutInSeconds))
        repeat {
            if RorkUsbmux.ready() {
                return (true, nil)
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        return (false, "RorkUsbmux tunnel/pairing/heartbeat is not ready")
    }

    func ensureReady(timeoutInSeconds: Double = 8.0) async throws {
        guard FileManager.default.fileExists(atPath: Self.pairingFile()) else {
            throw RorkDeviceBridgeError(message: "Missing Pairing")
        }

        start(false)
        let deadline = Date().addingTimeInterval(timeoutInSeconds)
        while Date() < deadline {
            RorkUsbmuxNetworkObserver.refreshEndpoint()
            if RorkUsbmux.ready() {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw RorkDeviceBridgeError(message: "Device tunnel/pairing/heartbeat is not ready")
    }

    private func normalizedPairingFile() throws -> String {
        let url = URL(fileURLWithPath: Self.pairingFile())
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let xml = try PropertyListSerialization.data(
            fromPropertyList: object,
            format: .xml,
            options: 0
        )
        guard let string = String(data: xml, encoding: .utf8) else {
            throw RorkDeviceBridgeError(message: "Invalid pairing plist")
        }
        return string
    }

    private func startPulseMonitorIfNeeded() {
        stateLock.lock()
        if pulseTimer != nil {
            stateLock.unlock()
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        pulseTimer = timer
        stateLock.unlock()

        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler {
            guard RorkUsbmuxHeartbeat.lastBeatSuccessful else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .heartbeat, object: nil)
            }
        }
        timer.resume()
    }
}

final class InstallationProxy {
    private let heartbeat = HeartbeatManager.shared
    private let bundleIdentifier: String?
    private let viewModel: InstallerStatusViewModel

    init(viewModel: InstallerStatusViewModel, bundleIdentifier: String? = nil) {
        self.viewModel = viewModel
        self.bundleIdentifier = bundleIdentifier
    }

    func install(at url: URL, suspend: Bool = false) async throws {
        do {
            guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
                throw RorkDeviceBridgeError(message: "Missing bundle identifier")
            }

            try await heartbeat.ensureReady()

            await MainActor.run {
                viewModel.status = .sendingPayload
                viewModel.uploadProgress = 0.0
            }

            let ipaBytes = try Data(contentsOf: url, options: [.mappedIfSafe])
            try RorkUsbmux.stageApp(
                bundleId: bundleIdentifier,
                ipaBytes: ipaBytes
            )

            await MainActor.run {
                viewModel.uploadProgress = 1.0
                viewModel.status = .installing
            }

            if suspend {
                DispatchQueue.main.async {
                    UIApplication.shared.perform(Selector(("suspend")))
                }
            }

            try RorkUsbmux.installApp(bundleId: bundleIdentifier)

            await MainActor.run {
                viewModel.installProgress = 1.0
                viewModel.status = .completed(.success(()))
            }
        } catch {
            await MainActor.run {
                viewModel.status = .broken(error)
            }
            throw error
        }
    }
}
''')

# Cold launch should start the bridge when a pairing record already exists.
app_path = root / "Ksign/FeatherApp.swift"
app = app_path.read_text()
if "heartbeat.start(false)" not in app:
    marker = "if logsManager.isCapturing { logsManager.startCapture() }"
    if marker not in app:
        raise SystemExit("rork-usbmux compat: FeatherApp onAppear marker missing")
    app = app.replace(marker, marker + "\n\t\t\t\theartbeat.start(false)", 1)
app_path.write_text(app)

# Invariants: no app source or project link may still require IDeviceSwift.
all_swift = "\n".join(
    path.read_text(errors="ignore")
    for path in (root / "Ksign").rglob("*.swift")
)
checks = {
    "no IDeviceSwift imports": "import IDeviceSwift" not in all_swift,
    "RorkUsbmux project product": "RorkUsbmux in Frameworks" in pbx_path.read_text(),
    "IDeviceKit package removed": 'XCLocalSwiftPackageReference "IDeviceKit"' not in pbx_path.read_text(),
    "Rork local package present": 'relativePath = RorkUsbmux;' in pbx_path.read_text(),
    "local status model restored": "public class InstallerStatusViewModel: ObservableObject" in status_path.read_text(),
    "rork heartbeat bridge": "RorkUsbmuxNetworkObserver.start()" in bridge_path.read_text(),
    "rork direct install": "RorkUsbmux.installApp(bundleId: bundleIdentifier)" in bridge_path.read_text(),
    "bundle identifier wired": call_count == 2,
    "AltSourceKit iOS13": ".iOS(.v13)" in alt_package_path.read_text(),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("rork-usbmux compatibility invariant failure: " + ", ".join(failed))

print(
    "RorkUsbmux iOS13 bridge applied; "
    f"removed {import_count} IDeviceSwift imports and rewired {call_count} installer call sites"
)
