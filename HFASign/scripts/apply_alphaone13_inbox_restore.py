#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path("HFASignBuild")


def require(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(message)


def clean(path: Path) -> None:
    text = path.read_text()
    path.write_text("\n".join(line.rstrip() for line in text.splitlines()) + "\n")


# 1. Restore the existing zonoe callback section in global Signing Options.
# ConfigurationView already binds this view to OptionsManager.shared.options and persists changes,
# so this is the same Options.zonoeUDIDCallbackEnabled used by SigningView.
options_path = ROOT / "Ksign/Views/Signing/Shared/SigningOptionsView.swift"
options = options_path.read_text()
section = "\t\tZonoeUDIDCallbackSection(isEnabled: $options.zonoeUDIDCallbackEnabled)\n\n"
if section not in options:
    match = re.search(r"(\n\s*var body: some View \{\n)", options, flags=re.S)
    require(match is not None, "alphaone13 inbox restore: SigningOptionsView body marker missing")
    insert_at = match.end()
    options = options[:insert_at] + section + options[insert_at:]
options_path.write_text(options)


# 2. Give SharedImportCoordinator success/failure completion semantics and Inbox recovery.
coordinator_path = ROOT / "Ksign/Utilities/SharedImportCoordinator.swift"
coordinator = coordinator_path.read_text()

property_marker = "    private let progress = OperationProgressManager.shared\n    private var lastImport: (path: String, date: Date)?\n"
property_replacement = '''    private let progress = OperationProgressManager.shared
    private let importStateQueue = DispatchQueue(label: "zonoe.shared-import.state")
    private let supportedIncomingExtensions: Set<String> = [
        "ipa", "tipa", "zip", "dylib", "framework", "bundle", "deb",
        "p12", "pfx", "mobileprovision", "provisionprofile"
    ]
    private var inFlightImportWaiters: [String: [(Bool) -> Void]] = [:]
    private var recentlyCompletedImports: [String: Date] = [:]
    private let recentCompletionTTL: TimeInterval = 600
'''
require(property_marker in coordinator, "alphaone13 inbox restore: SharedImportCoordinator property marker missing")
coordinator = coordinator.replace(property_marker, property_replacement, 1)

receive_pattern = re.compile(
    r"    func receive\(_ url: URL\) \{.*?\n    private func stageIncomingURL",
    re.S,
)
receive_replacement = r'''    func receive(_ url: URL) {
        receive(url, completion: nil)
    }

    /// Replays files that iOS has already copied into Documents/Inbox.
    /// The Inbox source is removed only after the existing import pipeline reports success.
    func recoverInboxIfNeeded() {
        let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            let ext = item.pathExtension.lowercased()
            guard isDirectory || supportedIncomingExtensions.contains(ext) else { continue }

            receive(item) { success in
                guard success, self.fileManager.fileExists(atPath: item.path) else { return }
                do {
                    try self.fileManager.removeItem(at: item)
                } catch {
                    // Leave it in Inbox so the next activation can retry cleanup without re-importing.
                    print("zonoe Inbox cleanup failed for \(item.lastPathComponent): \(error)")
                }
            }
        }
    }

    private func receive(_ url: URL, completion: ((Bool) -> Void)?) {
        let accessed = url.startAccessingSecurityScopedResource()
        let identity = importIdentity(for: url)
        guard beginImport(identity: identity, completion: completion) else {
            if accessed { url.stopAccessingSecurityScopedResource() }
            return
        }

        let finish: (Bool) -> Void = { success in
            self.finishImport(identity: identity, success: success)
        }

        // URLs received from Files and other apps can become invalid as soon as
        // the open/share callback returns. Coordinate the read and immediately
        // stage it inside our own container before doing any asynchronous work.
        let stagedURL: URL
        do {
            stagedURL = try stageIncomingURL(url)
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            progress.fail("导入失败：\(error.localizedDescription)")
            finish(false)
            return
        }
        if accessed { url.stopAccessingSecurityScopedResource() }

        let ext = stagedURL.pathExtension.lowercased()
        if ext == "zip", importCertificateArchiveIfPresent(stagedURL, completion: finish) {
            return
        }

        if ext == "ipa" || ext == "tipa" {
            progress.begin("正在导入 IPA", detail: stagedURL.lastPathComponent)
            let id = "HFASignImport_\(UUID().uuidString)"
            let download = DownloadManager.shared.startArchive(from: stagedURL, id: id)
            DownloadManager.shared.handlePachageFile(url: stagedURL, dl: download) { error in
                try? self.fileManager.removeItem(at: stagedURL.deletingLastPathComponent())
                if let error {
                    self.progress.fail("导入失败：\(error.localizedDescription)")
                    finish(false)
                } else {
                    self.progress.finish(detail: "导入完成")
                    finish(true)
                }
            }
            return
        }

        let values = try? stagedURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        guard supportedIncomingExtensions.contains(ext) || isDirectory else {
            try? fileManager.removeItem(at: stagedURL.deletingLastPathComponent())
            progress.fail("暂不支持此文件类型")
            finish(false)
            return
        }

        let isTweak = ["dylib", "framework", "deb", "bundle"].contains(ext)
        let destinationDirectory = isTweak ? fileManager.tweaks : fileManager.zipFiles
        try? fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(stagedURL.lastPathComponent, isDirectory: isDirectory)
        resolveConflict(for: destination) { choice in
            guard let choice else {
                try? self.fileManager.removeItem(at: stagedURL.deletingLastPathComponent())
                finish(false)
                return
            }
            self.copy(stagedURL, to: choice) { success in
                try? self.fileManager.removeItem(at: stagedURL.deletingLastPathComponent())
                finish(success)
            }
        }
    }

    private func stageIncomingURL'''
coordinator, receive_count = receive_pattern.subn(receive_replacement, coordinator, count=1)
require(receive_count == 1, f"alphaone13 inbox restore: receive replacement count={receive_count}")

certificate_pattern = re.compile(
    r"\tprivate func importCertificateArchiveIfPresent\(_ archiveURL: URL\) -> Bool \{.*?\n    private func resolveConflict",
    re.S,
)
certificate_replacement = r'''\tprivate func importCertificateArchiveIfPresent(_ archiveURL: URL, completion: @escaping (Bool) -> Void) -> Bool {
\t\tlet extractionRoot = archiveURL.deletingLastPathComponent().appendingPathComponent("certificate", isDirectory: true)
\t\tdo {
\t\t\ttry fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
\t\t\tlet archive = try ZIPFoundation.Archive(url: archiveURL, accessMode: .read)
\t\t\tfor entry in archive {
\t\t\t\tlet output = extractionRoot.appendingPathComponent(entry.path)
\t\t\t\tguard output.standardizedFileURL.path.hasPrefix(extractionRoot.standardizedFileURL.path) else { continue }
\t\t\t\ttry fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
\t\t\t\t_ = try archive.extract(entry, to: output)
\t\t\t}
\t\t\tlet files = (fileManager.enumerator(at: extractionRoot, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
\t\t\tguard let p12 = files.first(where: { ["p12", "pfx"].contains($0.pathExtension.lowercased()) }),
\t\t\t\t  let provision = files.first(where: { ["mobileprovision", "provisionprofile"].contains($0.pathExtension.lowercased()) }) else {
\t\t\t\ttry? fileManager.removeItem(at: extractionRoot)
\t\t\t\treturn false
\t\t\t}

\t\t\tDispatchQueue.main.async {
\t\t\t\tlet alert = UIAlertController(
\t\t\t\t\ttitle: "导入证书",
\t\t\t\t\tmessage: "请输入证书密码，无密码可留空。",
\t\t\t\t\tpreferredStyle: .alert
\t\t\t\t)
\t\t\t\talert.addTextField { field in field.placeholder = "密码" }
\t\t\t\talert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
\t\t\t\t\ttry? self.fileManager.removeItem(at: archiveURL.deletingLastPathComponent())
\t\t\t\t\tcompletion(false)
\t\t\t\t})
\t\t\t\talert.addAction(UIAlertAction(title: "导入", style: .default) { _ in
\t\t\t\t\tlet password = alert.textFields?.first?.text ?? ""
\t\t\t\t\tguard FR.checkPasswordForCertificate(for: p12, with: password, using: provision) else {
\t\t\t\t\t\ttry? self.fileManager.removeItem(at: archiveURL.deletingLastPathComponent())
\t\t\t\t\t\tUIAlertController.showAlertWithOk(title: "导入失败", message: "证书密码不正确。")
\t\t\t\t\t\tcompletion(false)
\t\t\t\t\t\treturn
\t\t\t\t\t}
\t\t\t\t\tFR.handleCertificateFiles(
\t\t\t\t\t\tp12URL: p12,
\t\t\t\t\t\tprovisionURL: provision,
\t\t\t\t\t\tp12Password: password,
\t\t\t\t\t\tcertificateName: p12.deletingPathExtension().lastPathComponent
\t\t\t\t\t) { error in
\t\t\t\t\t\ttry? self.fileManager.removeItem(at: archiveURL.deletingLastPathComponent())
\t\t\t\t\t\tDispatchQueue.main.async {
\t\t\t\t\t\t\tif let error {
\t\t\t\t\t\t\t\tUIAlertController.showAlertWithOk(title: "导入失败", message: error.localizedDescription)
\t\t\t\t\t\t\t\tcompletion(false)
\t\t\t\t\t\t\t} else {
\t\t\t\t\t\t\t\tUIAlertController.showAlertWithOk(title: "导入成功", message: "证书已添加。")
\t\t\t\t\t\t\t\tcompletion(true)
\t\t\t\t\t\t\t}
\t\t\t\t\t\t}
\t\t\t\t\t}
\t\t\t\t})
\t\t\t\tguard let presenter = UIApplication.topViewController() else {
\t\t\t\t\ttry? self.fileManager.removeItem(at: archiveURL.deletingLastPathComponent())
\t\t\t\t\tcompletion(false)
\t\t\t\t\treturn
\t\t\t\t}
\t\t\t\tpresenter.present(alert, animated: true)
\t\t\t}
\t\t\treturn true
\t\t} catch {
\t\t\ttry? fileManager.removeItem(at: extractionRoot)
\t\t\treturn false
\t\t}
\t}

    private func resolveConflict'''
coordinator, cert_count = certificate_pattern.subn(certificate_replacement, coordinator, count=1)
require(cert_count == 1, f"alphaone13 inbox restore: certificate function replacement count={cert_count}")

conflict_pattern = re.compile(
    r"    private func resolveConflict\(for destination: URL, completion: @escaping \(URL\?\) -> Void\) \{.*?\n    private func copy",
    re.S,
)
conflict_replacement = r'''    private func resolveConflict(for destination: URL, completion: @escaping (URL?) -> Void) {
        guard fileManager.fileExists(atPath: destination.path) else {
            completion(destination)
            return
        }
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "文件已存在",
                message: "“\(destination.lastPathComponent)”已存在，是否覆盖？",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "覆盖", style: .destructive) { _ in
                do {
                    try self.fileManager.removeItem(at: destination)
                    completion(destination)
                } catch {
                    self.progress.fail("覆盖失败：\(error.localizedDescription)")
                    completion(nil)
                }
            })
            alert.addAction(UIAlertAction(title: "重命名", style: .default) { _ in
                completion(self.uniqueURL(for: destination))
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                completion(nil)
            })
            guard let presenter = UIApplication.topViewController() else {
                completion(nil)
                return
            }
            presenter.present(alert, animated: true)
        }
    }

    private func copy'''
coordinator, conflict_count = conflict_pattern.subn(conflict_replacement, coordinator, count=1)
require(conflict_count == 1, f"alphaone13 inbox restore: conflict function replacement count={conflict_count}")

copy_pattern = re.compile(
    r"    private func copy\(_ source: URL, to destination: URL, completion: @escaping \(\) -> Void\) \{.*?\n    private func copyFileWithProgress",
    re.S,
)
copy_replacement = r'''    private func copy(_ source: URL, to destination: URL, completion: @escaping (Bool) -> Void) {
        progress.begin("正在导入文件", detail: source.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sourceIsDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if sourceIsDirectory {
                    try self.fileManager.copyItem(at: source, to: destination)
                } else {
                    try self.copyFileWithProgress(source, to: destination)
                }
                let location = ["dylib", "framework", "deb", "bundle"].contains(source.pathExtension.lowercased())
                    ? "插件目录"
                    : "App/ZipFile"
                self.progress.finish(detail: "已保存到\(location)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didImportNotification, object: destination)
                }
                completion(true)
            } catch {
                self.progress.fail("导入失败：\(error.localizedDescription)")
                try? self.fileManager.removeItem(at: destination)
                completion(false)
            }
        }
    }

    private func copyFileWithProgress'''
coordinator, copy_count = copy_pattern.subn(copy_replacement, coordinator, count=1)
require(copy_count == 1, f"alphaone13 inbox restore: copy function replacement count={copy_count}")

helper_marker = "    private func uniqueURL(for url: URL) -> URL {"
require(helper_marker in coordinator, "alphaone13 inbox restore: uniqueURL marker missing")
helpers = r'''    private func importIdentity(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            return "dir|\(standardized.lastPathComponent.lowercased())|\(standardized.path)"
        }

        let size = values?.fileSize ?? -1
        var hash: UInt64 = 1469598103934665603
        if let handle = try? FileHandle(forReadingFrom: standardized) {
            let data = handle.readData(ofLength: 64 * 1024)
            handle.closeFile()
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
        }
        return "file|\(standardized.lastPathComponent.lowercased())|\(size)|\(String(hash, radix: 16))"
    }

    private func beginImport(identity: String, completion: ((Bool) -> Void)?) -> Bool {
        var shouldStart = false
        var alreadyCompleted = false
        importStateQueue.sync {
            let now = Date()
            recentlyCompletedImports = recentlyCompletedImports.filter {
                now.timeIntervalSince($0.value) < recentCompletionTTL
            }
            if recentlyCompletedImports[identity] != nil {
                alreadyCompleted = true
                return
            }
            if inFlightImportWaiters[identity] != nil {
                if let completion { inFlightImportWaiters[identity, default: []].append(completion) }
                return
            }
            inFlightImportWaiters[identity] = completion.map { [$0] } ?? []
            shouldStart = true
        }
        if alreadyCompleted, let completion {
            DispatchQueue.main.async { completion(true) }
        }
        return shouldStart
    }

    private func finishImport(identity: String, success: Bool) {
        var waiters: [(Bool) -> Void] = []
        importStateQueue.sync {
            waiters = inFlightImportWaiters.removeValue(forKey: identity) ?? []
            if success { recentlyCompletedImports[identity] = Date() }
        }
        guard !waiters.isEmpty else { return }
        DispatchQueue.main.async {
            waiters.forEach { $0(success) }
        }
    }

'''
coordinator = coordinator.replace(helper_marker, helpers + helper_marker, 1)
coordinator_path.write_text(coordinator)


# 3. Scan Inbox whenever UIKit reports the app becoming active.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = app_path.read_text()
active_method = '''    func applicationDidBecomeActive(_ application: UIApplication) {
        SharedImportCoordinator.shared.recoverInboxIfNeeded()
    }

'''
if active_method not in app:
    marker = "    private func _initializeBuiltInSources() {"
    require(marker in app, "alphaone13 inbox restore: AppDelegate insertion marker missing")
    app = app.replace(marker, active_method + marker, 1)
app_path.write_text(app)


# Reconstruction-time invariants. These run before Xcode and catch transform drift.
checks = {
    "settings uses shared zonoe option": 'ZonoeUDIDCallbackSection(isEnabled: $options.zonoeUDIDCallbackEnabled)' in options,
    "inbox recovery entrypoint": 'func recoverInboxIfNeeded()' in coordinator,
    "success-only inbox delete": 'guard success, self.fileManager.fileExists(atPath: item.path)' in coordinator,
    "concurrent dedup state": 'inFlightImportWaiters' in coordinator and 'importStateQueue.sync' in coordinator,
    "failed import not cached": 'if success { recentlyCompletedImports[identity] = Date() }' in coordinator,
    "foreground recovery": 'SharedImportCoordinator.shared.recoverInboxIfNeeded()' in app,
    "certificate cancel completes false": 'completion(false)' in coordinator and 'title: "取消"' in coordinator,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("alphaone13 inbox/signing settings invariant failure: " + ", ".join(failed))

for path in (options_path, coordinator_path, app_path):
    clean(path)

print("alphaone13 signing settings + Inbox recovery transform applied")
