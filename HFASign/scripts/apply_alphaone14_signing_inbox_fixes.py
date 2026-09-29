#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("HFASignBuild")


def require(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(message)


def clean_trailing_whitespace(path: Path) -> None:
    text = path.read_text()
    path.write_text("\n".join(line.rstrip() for line in text.splitlines()) + "\n")


# 1. Restore the existing clean-architecture zonoe UDID callback control to
#    persisted Signing Settings. Keep the per-signing control in SigningView.
settings_path = ROOT / "Ksign/Views/Signing/Shared/SigningOptionsView.swift"
settings = settings_path.read_text()
setting_line = "ZonoeUDIDCallbackSection(isEnabled: $options.zonoeUDIDCallbackEnabled)"
require(setting_line not in settings, "alphaone14: UDID callback already exists in shared signing settings")
experimental = 'NBSection("实验性功能") {'
pos = settings.find(experimental)
require(pos >= 0, "alphaone14: experimental signing section not found")
line_start = settings.rfind("\n", 0, pos) + 1
indent = settings[line_start:pos]
settings = settings[:line_start] + indent + setting_line + "\n\n" + settings[line_start:]
settings_path.write_text(settings)


# 2. Harden the shared-file import coordinator. iOS may first place documents
#    received from another app in Documents/Inbox. Existing code already stages
#    the URL with NSFileCoordinator; alphaone14 additionally recovers Inbox items,
#    prevents concurrent duplicate imports, and consumes the original Inbox item
#    only after the import succeeds.
coordinator_path = ROOT / "Ksign/Utilities/SharedImportCoordinator.swift"
coordinator = coordinator_path.read_text()

state_old = '''    private let fileManager = FileManager.default
    private let progress = OperationProgressManager.shared
    private var lastImport: (path: String, date: Date)?
'''
state_new = '''    private let fileManager = FileManager.default
    private let progress = OperationProgressManager.shared
    private let importStateLock = NSLock()
    private var activeImportSources: Set<String> = []
    private var lastImport: (path: String, date: Date)?
'''
require(coordinator.count(state_old) == 1, "alphaone14: SharedImportCoordinator state anchor mismatch")
coordinator = coordinator.replace(state_old, state_new, 1)

# Claim after the historical certificate-ZIP fast path. That path owns its own
# asynchronous prompt/lifecycle and must not leave our in-flight claim stuck.
ipa_entry = '''        if ext == "ipa" || ext == "tipa" {
'''
ipa_entry_new = '''        guard claimImportSource(url) else {
            try? fileManager.removeItem(at: stagedURL)
            return
        }
        if ext == "ipa" || ext == "tipa" {
'''
require(coordinator.count(ipa_entry) == 1, "alphaone14: IPA entry anchor mismatch")
coordinator = coordinator.replace(ipa_entry, ipa_entry_new, 1)

ipa_callback_old = '''            DownloadManager.shared.handlePachageFile(url: stagedURL, dl: download) { error in
                try? self.fileManager.removeItem(at: stagedURL)
                if let error {
                    self.progress.fail("导入失败：\\(error.localizedDescription)")
                } else {
                    self.progress.finish(detail: "导入完成")
                }
            }
'''
ipa_callback_new = '''            DownloadManager.shared.handlePachageFile(url: stagedURL, dl: download) { error in
                try? self.fileManager.removeItem(at: stagedURL)
                if let error {
                    self.progress.fail("导入失败：\\(error.localizedDescription)")
                } else {
                    self.consumeInboxSourceIfNeeded(url)
                    self.progress.finish(detail: "导入完成")
                }
                self.finishImportSource(url)
            }
'''
require(coordinator.count(ipa_callback_old) == 1, "alphaone14: IPA completion anchor mismatch")
coordinator = coordinator.replace(ipa_callback_old, ipa_callback_new, 1)

unsupported_old = '''        guard supported.contains(ext) || stagedURL.hasDirectoryPath else {
            try? fileManager.removeItem(at: stagedURL)
            progress.fail("暂不支持此文件类型")
            return
        }
'''
unsupported_new = '''        guard supported.contains(ext) || stagedURL.hasDirectoryPath else {
            try? fileManager.removeItem(at: stagedURL)
            finishImportSource(url)
            progress.fail("暂不支持此文件类型")
            return
        }
'''
require(coordinator.count(unsupported_old) == 1, "alphaone14: unsupported-file anchor mismatch")
coordinator = coordinator.replace(unsupported_old, unsupported_new, 1)

copy_call_old = '''        resolveConflict(for: destination) { choice in
            guard let choice else {
                try? self.fileManager.removeItem(at: stagedURL)
                return
            }
            self.copy(stagedURL, to: choice) {
                try? self.fileManager.removeItem(at: stagedURL)
            }
        }
    }
'''
copy_call_new = '''        resolveConflict(for: destination) { choice in
            guard let choice else {
                try? self.fileManager.removeItem(at: stagedURL)
                self.finishImportSource(url)
                return
            }
            self.copy(stagedURL, to: choice) { succeeded in
                try? self.fileManager.removeItem(at: stagedURL)
                if succeeded { self.consumeInboxSourceIfNeeded(url) }
                self.finishImportSource(url)
            }
        }
    }
'''
require(coordinator.count(copy_call_old) == 1, "alphaone14: copied-file completion anchor mismatch")
coordinator = coordinator.replace(copy_call_old, copy_call_new, 1)

# The body of copy() evolved in alpha7 (notification + destination text), so only
# patch the stable control-flow anchors instead of matching the entire function.
copy_start_old = '''    private func copy(_ source: URL, to destination: URL, completion: @escaping () -> Void) {
        progress.begin("正在导入文件", detail: source.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
'''
copy_start_new = '''    private func copy(_ source: URL, to destination: URL, completion: @escaping (Bool) -> Void) {
        progress.begin("正在导入文件", detail: source.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async {
            var succeeded = false
            do {
'''
require(coordinator.count(copy_start_old) == 1, "alphaone14: copy function start anchor mismatch")
coordinator = coordinator.replace(copy_start_old, copy_start_new, 1)

copy_success_old = '''                } else {
                    try self.copyFileWithProgress(source, to: destination)
                }
                let location = ["dylib", "framework", "deb", "bundle"].contains(source.pathExtension.lowercased())
'''
copy_success_new = '''                } else {
                    try self.copyFileWithProgress(source, to: destination)
                }
                succeeded = true
                let location = ["dylib", "framework", "deb", "bundle"].contains(source.pathExtension.lowercased())
'''
require(coordinator.count(copy_success_old) == 1, "alphaone14: copy success anchor mismatch")
coordinator = coordinator.replace(copy_success_old, copy_success_new, 1)

completion_old = "            completion()\n"
require(coordinator.count(completion_old) == 1, "alphaone14: copy completion anchor mismatch")
coordinator = coordinator.replace(completion_old, "            completion(succeeded)\n", 1)

recover_helpers = '''
    func recoverPendingInboxItems() {
        let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items where isRecoverableInboxItem(item) {
            receive(item)
        }
    }

    private func isRecoverableInboxItem(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return true }
        let supported: Set<String> = [
            "ipa", "tipa", "zip", "dylib", "framework", "bundle", "deb",
            "p12", "pfx", "mobileprovision", "provisionprofile"
        ]
        return supported.contains(url.pathExtension.lowercased())
    }

    private func importSourceKey(_ url: URL) -> String {
        url.isFileURL ? url.standardizedFileURL.path : url.absoluteString
    }

    private func claimImportSource(_ url: URL) -> Bool {
        let key = importSourceKey(url)
        importStateLock.lock()
        defer { importStateLock.unlock() }
        guard !activeImportSources.contains(key) else { return false }
        activeImportSources.insert(key)
        return true
    }

    private func finishImportSource(_ url: URL) {
        let key = importSourceKey(url)
        importStateLock.lock()
        activeImportSources.remove(key)
        importStateLock.unlock()
    }

    private func consumeInboxSourceIfNeeded(_ url: URL) {
        guard isInboxItem(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func isInboxItem(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let inbox = URL.documentsDirectory
            .appendingPathComponent("Inbox", isDirectory: true)
            .standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == inbox || candidate.hasPrefix(inbox + "/")
    }

'''
resolve_marker = "    private func resolveConflict(for destination: URL, completion: @escaping (URL?) -> Void) {\n"
require(coordinator.count(resolve_marker) == 1, "alphaone14: resolveConflict marker mismatch")
coordinator = coordinator.replace(resolve_marker, recover_helpers + resolve_marker, 1)
coordinator_path.write_text(coordinator)


# 3. Run Inbox recovery on first appearance and whenever the app returns to the
#    foreground. Normal SwiftUI onOpenURL / UIApplicationDelegate callbacks stay
#    in place; this is a recovery path for documents already deposited in Inbox.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = app_path.read_text()
on_appear_anchor = '''\t\t\t\tif logsManager.isCapturing { logsManager.startCapture() }
'''
on_appear_replacement = on_appear_anchor + '''\t\t\t\tSharedImportCoordinator.shared.recoverPendingInboxItems()
'''
require(app.count(on_appear_anchor) == 1, "alphaone14: FeatherApp onAppear anchor mismatch")
app = app.replace(on_appear_anchor, on_appear_replacement, 1)

open_url_anchor = '''\t\t\t\t\t.onOpenURL(perform: _handleURL)
'''
open_url_replacement = open_url_anchor + '''\t\t\t\t\t.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
\t\t\t\t\t\tSharedImportCoordinator.shared.recoverPendingInboxItems()
\t\t\t\t\t}
'''
require(app.count(open_url_anchor) == 1, "alphaone14: FeatherApp onOpenURL anchor mismatch")
app = app.replace(open_url_anchor, open_url_replacement, 1)
app_path.write_text(app)


# 4. alphaone14 identity.
project_path = ROOT / "Ksign.xcodeproj/project.pbxproj"
project = project_path.read_text()
require(project.count("CURRENT_PROJECT_VERSION = 113;") == 2, "alphaone14: expected two build 113 entries")
project_path.write_text(project.replace("CURRENT_PROJECT_VERSION = 113;", "CURRENT_PROJECT_VERSION = 114;"))

plist_path = ROOT / "Ksign/Resources/Info.plist"
plist = plist_path.read_text()
require(plist.count("<string>v3.0.0-alphaone13</string>") == 1, "alphaone14: alphaone13 marker not unique")
plist_path.write_text(plist.replace("<string>v3.0.0-alphaone13</string>", "<string>v3.0.0-alphaone14</string>", 1))


# 5. Transform-level regression assertions.
require(setting_line in settings_path.read_text(), "alphaone14: shared UDID callback setting missing after transform")
final_coordinator = coordinator_path.read_text()
for needle in (
    "func recoverPendingInboxItems()",
    "private func claimImportSource(_ url: URL) -> Bool",
    "private func consumeInboxSourceIfNeeded(_ url: URL)",
    "completion: @escaping (Bool) -> Void",
):
    require(needle in final_coordinator, f"alphaone14: import recovery missing {needle}")
final_app = app_path.read_text()
require(final_app.count("SharedImportCoordinator.shared.recoverPendingInboxItems()") >= 2,
        "alphaone14: Inbox recovery lifecycle hooks missing")

for path in (settings_path, coordinator_path, app_path, project_path, plist_path):
    clean_trailing_whitespace(path)

print("alphaone14 signing settings + Inbox import recovery transform applied")
