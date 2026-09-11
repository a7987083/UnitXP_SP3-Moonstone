#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("HFASignBuild")

# 1) Source announcement: alphaone11 only read repository subtitle/description.
# alphaone12 also treats explicit notice/announcement app rows as announcement content,
# and preserves every non-empty text fragment in source order.
source_view = ROOT / "Ksign/Views/Sources/Apps/SourceAppsView.swift"
text = source_view.read_text()
old_helper = '''    private func repositoryNotice(for loaded: [LoadedSource]) -> String? {
        guard loaded.count == 1 else { return nil }
        let repository = loaded[0].repository
        var parts: [String] = []
        for value in [repository.subtitle, repository.description] {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !parts.contains(trimmed) { parts.append(trimmed) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\\n\\n")
    }

'''
new_helper = '''    private func repositoryNotice(for loaded: [LoadedSource]) -> String? {
        var parts: [String] = []

        func append(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !parts.contains(trimmed) else { return }
            parts.append(trimmed)
        }

        for loadedSource in loaded {
            let repository = loadedSource.repository

            // Some compatible sources publish their announcement as a normal app row.
            // If its title says 公告 / notice / announcement, surface all textual content.
            for app in repository.apps {
                let name = app.currentName
                let key = name.lowercased()
                guard name.contains("公告") || key.contains("notice") || key.contains("announcement") else { continue }
                append(name)
                append(app.subtitle)
                append(app.localizedDescription)
                append(app.description)
                append(app.versionDescription)
            }

            // Standard AltStore-style repository announcement fields.
            append(repository.subtitle)
            append(repository.description)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\\n\\n")
    }

'''
if text.count(old_helper) != 1:
    raise SystemExit(f"alphaone12 source notice helper: expected one alphaone11 helper, found {text.count(old_helper)}")
source_view.write_text(text.replace(old_helper, new_helper, 1))

# 2) Remove bookmark URL Scheme route, but preserve addsource/web/source/download/install/UDID.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = app_path.read_text()
bookmark_block = '''\n\t\t\tif action == "bookmark", let value = queryValue("url", from: url), isHTTPURL(value) {\n\t\t\t\tvar bookmarks = UserDefaults.standard.stringArray(forKey: "zonoe.webBookmarks") ?? []\n\t\t\t\tbookmarks.removeAll { $0 == value }\n\t\t\t\tbookmarks.insert(value, at: 0)\n\t\t\t\tUserDefaults.standard.set(Array(bookmarks.prefix(100)), forKey: "zonoe.webBookmarks")\n\t\t\t\tUINotificationFeedbackGenerator().notificationOccurred(.success)\n\t\t\t\treturn\n\t\t\t}\n'''
if app.count(bookmark_block) != 1:
    raise SystemExit(f"alphaone12 bookmark route: expected one alphaone11 block, found {app.count(bookmark_block)}")
app_path.write_text(app.replace(bookmark_block, "", 1))

# 3) URL Scheme documentation: remove bookmark UI/storage completely.
scheme_path = ROOT / "Ksign/Views/Settings/URLSchemeView.swift"
scheme_path.write_text(r'''import SwiftUI
import UIKit

struct URLSchemeView: View {
    var body: some View {
        List {
            Section("快速添加软件源") {
                endpoint("zonoe://addsource?url=https%3A%2F%2Fexample.com%2Frepo.json")
                Text("浏览器或其他 App 唤起 zonoe。未添加的软件源会走现有添加流程；已存在的软件源保持现有行为。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("兼容的软件源入口") {
                endpoint("zonoe://source/https%3A%2F%2Fexample.com%2Frepo.json")
                Text("保留旧版 source 路由，兼容已经生成或发布的链接。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("App 内打开网页") {
                endpoint("zonoe://web?url=https%3A%2F%2Fexample.com")
                Text("在 zonoe 内使用 Safari View 打开 HTTP/HTTPS 网页；无法展示时回退系统浏览器。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("下载 / 导入 IPA") {
                endpoint("zonoe://download/https%3A%2F%2Fexample.com%2Fapp.ipa")
                endpoint("zonoe://install/https%3A%2F%2Fexample.com%2Fapp.ipa")
                Text("调用现有 DownloadManager 下载 HTTP/HTTPS 地址；download 与 install 当前均进入 zonoe 下载/导入链。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("UDID Provider") {
                endpoint("zonoe://udid?callback=example%3A%2F%2Fcallback")
                Text("供其他 App 请求 zonoe 已保存的 UDID。callback 使用 URL 编码；nonce bridge 继续使用固定 127.0.0.1:14302 协议。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("参数规则") {
                Text("url / callback 参数建议完整进行 Percent-Encoding。addsource 与 web 仅接受 HTTP/HTTPS 目标地址。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("URL Scheme")
    }

    @ViewBuilder
    private func endpoint(_ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc")
            }
        }
    }
}
''')

# 4) Downloads page: put 下载设置 immediately before the existing + action.
# Locate the toolbar containing the existing plus button instead of depending on
# whitespace/localization changed by the historical patch stack.
downloader_path = ROOT / "Ksign/Views/Downloader/DownloaderView.swift"
downloader = downloader_path.read_text()
plus_pos = downloader.find('systemImage: "plus"')
if plus_pos < 0:
    raise SystemExit("alphaone12 downloader toolbar: existing plus button not found")
toolbar_pos = downloader.rfind(".toolbar {", 0, plus_pos)
if toolbar_pos < 0:
    raise SystemExit("alphaone12 downloader toolbar: toolbar containing plus button not found")
line_end = downloader.find("\n", toolbar_pos)
if line_end < 0:
    raise SystemExit("alphaone12 downloader toolbar: malformed toolbar line")
line_start = downloader.rfind("\n", 0, toolbar_pos) + 1
indent = downloader[line_start:toolbar_pos]
item_indent = indent + "    "
body_indent = item_indent + "    "
insert = (
    f'{item_indent}ToolbarItem(placement: .topBarTrailing) {{\n'
    f'{body_indent}NavigationLink {{\n'
    f'{body_indent}    ZonoeDownloadSettingsView()\n'
    f'{body_indent}}} label: {{\n'
    f'{body_indent}    Text("下载设置")\n'
    f'{body_indent}}}\n'
    f'{item_indent}}}\n'
)
downloader = downloader[:line_end + 1] + insert + downloader[line_end + 1:]

settings_marker = "// MARK: - Alert & Sheet Content"
settings_pos = downloader.find(settings_marker)
if settings_pos < 0:
    raise SystemExit("alphaone12 downloader settings insertion: marker not found")
settings_line_start = downloader.rfind("\n", 0, settings_pos) + 1
settings_view = r'''private struct ZonoeDownloadSettingsView: View {
    @AppStorage("zonoe.downloadAutoImport") private var autoImport = true
    @AppStorage("zonoe.downloadDeleteAfterImport") private var deleteAfterImport = true
    @AppStorage("zonoe.downloadRenameImport") private var renameImport = true

    var body: some View {
        List {
            Section {
                Text("开启此项会自动导入已下载的IPA文件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("下载完成自动导入", isOn: $autoImport)
            }

            Section {
                Text("开启此项导入完成后会自动从已下载中删除")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("导入后自动删除", isOn: $deleteAfterImport)
            }

            Section {
                Text("开启此项如遇相同文件名的IPA文件将自动重命名导入")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("改名导入", isOn: $renameImport)
            }
        }
        .navigationTitle("下载设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

'''
downloader = downloader[:settings_line_start] + settings_view + downloader[settings_line_start:]
downloader_path.write_text(downloader)

# 5) Make the three download settings functional for the direct IPA downloader.
manager_path = ROOT / "Ksign/Views/Downloader/ViewModels/IPADownloadManager.swift"
manager = manager_path.read_text()
destination_anchor = '''        let destinationURL = downloadDirectory.appendingPathComponent(filename)\n        let item = DownloadItem(\n            title: filename,\n'''
destination_replacement = '''        let requestedURL = downloadDirectory.appendingPathComponent(filename)\n        let destinationURL = resolvedDownloadURL(for: requestedURL)\n        let item = DownloadItem(\n            title: destinationURL.lastPathComponent,\n'''
if manager.count(destination_anchor) != 1:
    raise SystemExit(f"alphaone12 download rename: expected one destination block, found {manager.count(destination_anchor)}")
manager = manager.replace(destination_anchor, destination_replacement, 1)

cancel_anchor = '''    func cancelDownload(_ item: DownloadItem) {\n'''
manager_helpers = r'''    private func preference(_ key: String, default defaultValue: Bool = true) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func resolvedDownloadURL(for requestedURL: URL) -> URL {
        guard preference("zonoe.downloadRenameImport") else { return requestedURL }

        func occupied(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
                || downloadItems.contains(where: { $0.localPath == url })
        }

        guard occupied(requestedURL) else { return requestedURL }
        let directory = requestedURL.deletingLastPathComponent()
        let fileExtension = requestedURL.pathExtension
        let baseName = requestedURL.deletingPathExtension().lastPathComponent
        var index = 1

        while true {
            let filename = fileExtension.isEmpty
                ? "\(baseName) (\(index))"
                : "\(baseName) (\(index)).\(fileExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !occupied(candidate) { return candidate }
            index += 1
        }
    }

    private func autoImportIfNeeded(_ item: DownloadItem) {
        guard preference("zonoe.downloadAutoImport") else { return }

        let libraryManager = DownloadManager.shared
        let archive = libraryManager.startArchive(
            from: item.localPath,
            id: "ZonoeAutoImport_\(UUID().uuidString)"
        )
        libraryManager.handlePachageFile(url: item.localPath, dl: archive) { [weak self] error in
            guard error == nil else { return }
            guard self?.preference("zonoe.downloadDeleteAfterImport") == true else { return }

            try? FileManager.default.removeItem(at: item.localPath)
            DispatchQueue.main.async {
                self?.downloadItems.removeAll { $0.id == item.id }
            }
        }
    }

'''
if manager.count(cancel_anchor) != 1:
    raise SystemExit(f"alphaone12 download helpers: expected one cancel marker, found {manager.count(cancel_anchor)}")
manager = manager.replace(cancel_anchor, manager_helpers + cancel_anchor, 1)

finish_anchor = '''                if index < self.downloadItems.count {\n                    self.downloadItems[index] = updatedItem\n                }\n                self.activeDownloads.removeValue(forKey: downloadTask.taskIdentifier)\n'''
finish_replacement = finish_anchor + '''                self.autoImportIfNeeded(updatedItem)\n'''
if manager.count(finish_anchor) != 1:
    raise SystemExit(f"alphaone12 auto import: expected one finish block, found {manager.count(finish_anchor)}")
manager = manager.replace(finish_anchor, finish_replacement, 1)
manager_path.write_text(manager)

# 6) Build identity: alphaone12 must not overwrite alphaone11.
project_path = ROOT / "Ksign.xcodeproj/project.pbxproj"
project = project_path.read_text()
if project.count("CURRENT_PROJECT_VERSION = 111;") != 2:
    raise SystemExit("alphaone12 build identity: expected two CURRENT_PROJECT_VERSION = 111 entries")
project_path.write_text(project.replace("CURRENT_PROJECT_VERSION = 111;", "CURRENT_PROJECT_VERSION = 112;"))

plist_path = ROOT / "Ksign/Resources/Info.plist"
plist = plist_path.read_text()
if plist.count("<string>v3.0.0-alphaone11</string>") != 1:
    raise SystemExit("alphaone12 release identity: alphaone11 marker not unique")
plist_path.write_text(plist.replace("<string>v3.0.0-alphaone11</string>", "<string>v3.0.0-alphaone12</string>", 1))

print("alphaone12 notice/download settings/bookmark-removal transform applied")
