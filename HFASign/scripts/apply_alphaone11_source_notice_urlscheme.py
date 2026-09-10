#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("HFASignBuild")


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    path.write_text(text.replace(old, new, 1))

# 1) Repository-level notice/header. Keep the existing table/list implementation intact.
source_view = ROOT / "Ksign/Views/Sources/Apps/SourceAppsView.swift"
text = source_view.read_text()
needle = """    var body: some View {\n        ZStack {\n            if let sources, !sources.isEmpty {\n                SourceAppsTableRepresentableView(sources: sources, searchText: $searchText, filter: filter) { selectedRoute = $0 }.ignoresSafeArea()\n            } else { ProgressView() }\n        }\n"""
replacement = """    var body: some View {\n        ZStack {\n            if let sources, !sources.isEmpty {\n                VStack(spacing: 0) {\n                    if let notice = repositoryNotice(for: sources) {\n                        VStack(alignment: .leading, spacing: 8) {\n                            HStack(spacing: 6) {\n                                Image(systemName: \"megaphone.fill\")\n                                Text(\"软件源公告\").font(.headline)\n                            }\n                            Text(notice)\n                                .font(.subheadline)\n                                .foregroundStyle(.secondary)\n                                .textSelection(.enabled)\n                                .fixedSize(horizontal: false, vertical: true)\n                        }\n                        .frame(maxWidth: .infinity, alignment: .leading)\n                        .padding(.horizontal, 16)\n                        .padding(.vertical, 12)\n                        .background(Color(uiColor: .secondarySystemGroupedBackground))\n                        Divider()\n                    }\n                    SourceAppsTableRepresentableView(sources: sources, searchText: $searchText, filter: filter) { selectedRoute = $0 }\n                        .ignoresSafeArea()\n                }\n            } else { ProgressView() }\n        }\n"""
if needle not in text:
    raise SystemExit("SourceAppsView body: final alphaone10 shape not found")
text = text.replace(needle, replacement, 1)

insert_before = "    var body: some View {\n"
helper = """    private func repositoryNotice(for loaded: [LoadedSource]) -> String? {\n        guard loaded.count == 1 else { return nil }\n        let repository = loaded[0].repository\n        let parts = [repository.subtitle, repository.description]\n            .compactMap { value -> String? in\n                guard let value else { return nil }\n                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)\n                return trimmed.isEmpty ? nil : trimmed\n            }\n        guard !parts.isEmpty else { return nil }\n        return Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: \"\\n\\n\")\n    }\n\n"""
if text.count(insert_before) != 1:
    raise SystemExit(f"SourceAppsView helper insertion: expected one body, found {text.count(insert_before)}")
text = text.replace(insert_before, helper + insert_before, 1)
source_view.write_text(text)

# 2) URL Scheme router additions. Preserve source/install/download/UDID routes.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = app_path.read_text()
if "import SafariServices\n" not in app:
    if "import UIKit\n" in app:
        app = app.replace("import UIKit\n", "import UIKit\nimport SafariServices\n", 1)
    else:
        app = app.replace("import SwiftUI\n", "import SwiftUI\nimport SafariServices\n", 1)

router_anchor = """\t\t\tlet action = url.host?.lowercased() ?? \"\"\n\t\t\tlet payload = String(url.absoluteString.dropFirst(\"zonoe://\\(action)/\".count)).removingPercentEncoding ?? \"\"\n"""
router_add = router_anchor + """\n\t\t\tif action == \"addsource\", let value = queryValue(\"url\", from: url), isHTTPURL(value) {\n\t\t\t\tFR.handleSource(value) { }\n\t\t\t\treturn\n\t\t\t}\n\n\t\t\tif action == \"web\", let value = queryValue(\"url\", from: url), let target = URL(string: value), isHTTPURL(value) {\n\t\t\t\tpresentInAppWeb(target)\n\t\t\t\treturn\n\t\t\t}\n\n\t\t\tif action == \"bookmark\", let value = queryValue(\"url\", from: url), isHTTPURL(value) {\n\t\t\t\tvar bookmarks = UserDefaults.standard.stringArray(forKey: \"zonoe.webBookmarks\") ?? []\n\t\t\t\tbookmarks.removeAll { $0 == value }\n\t\t\t\tbookmarks.insert(value, at: 0)\n\t\t\t\tUserDefaults.standard.set(Array(bookmarks.prefix(100)), forKey: \"zonoe.webBookmarks\")\n\t\t\t\tUINotificationFeedbackGenerator().notificationOccurred(.success)\n\t\t\t\treturn\n\t\t\t}\n"""
if app.count(router_anchor) != 1:
    raise SystemExit(f"FeatherApp router anchor: expected one match, found {app.count(router_anchor)}")
app = app.replace(router_anchor, router_add, 1)

udid_anchor = "\tprivate func _handleUDIDRequest(_ url: URL) {\n"
helpers = """\tprivate func queryValue(_ name: String, from url: URL) -> String? {\n\t\tURLComponents(url: url, resolvingAgainstBaseURL: false)?\n\t\t\t.queryItems?\n\t\t\t.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?\n\t\t\t.value?\n\t\t\t.trimmingCharacters(in: .whitespacesAndNewlines)\n\t}\n\n\tprivate func isHTTPURL(_ value: String) -> Bool {\n\t\tguard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }\n\t\treturn scheme == \"http\" || scheme == \"https\"\n\t}\n\n\tprivate func presentInAppWeb(_ url: URL) {\n\t\tDispatchQueue.main.async {\n\t\t\tlet controller = SFSafariViewController(url: url)\n\t\t\tguard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),\n\t\t\t\t  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {\n\t\t\t\tUIApplication.shared.open(url)\n\t\t\t\treturn\n\t\t\t}\n\t\t\tvar top = root\n\t\t\twhile let presented = top.presentedViewController { top = presented }\n\t\t\ttop.present(controller, animated: true)\n\t\t}\n\t}\n\n"""
if app.count(udid_anchor) != 1:
    raise SystemExit(f"FeatherApp UDID anchor: expected one match, found {app.count(udid_anchor)}")
app = app.replace(udid_anchor, helpers + udid_anchor, 1)
app_path.write_text(app)

# 3) Replace Settings -> URL Scheme documentation with complete zonoe documentation + bookmark management.
scheme_path = ROOT / "Ksign/Views/Settings/URLSchemeView.swift"
scheme_path.write_text(r'''import SwiftUI
import UIKit
import SafariServices

struct URLSchemeView: View {
    @AppStorage("zonoe.webBookmarks") private var bookmarkData: Data = Data()
    @State private var bookmarks: [String] = UserDefaults.standard.stringArray(forKey: "zonoe.webBookmarks") ?? []

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

            Section("添加网页书签") {
                endpoint("zonoe://bookmark?url=https%3A%2F%2Fexample.com")
                Text("把网址保存到 zonoe 网页书签。重复地址会移动到最前面，最多保留 100 条。")
                    .font(.footnote).foregroundStyle(.secondary)
                if !bookmarks.isEmpty {
                    ForEach(bookmarks, id: \.self) { value in
                        Button { openWeb(value) } label: {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                Text(value).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .onDelete(perform: deleteBookmarks)
                }
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
                Text("url / callback 参数建议完整进行 Percent-Encoding。仅接受 HTTP/HTTPS 作为 addsource、web、bookmark 的目标地址。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("URL Scheme")
        .onAppear { reloadBookmarks() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in reloadBookmarks() }
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

    private func reloadBookmarks() {
        bookmarks = UserDefaults.standard.stringArray(forKey: "zonoe.webBookmarks") ?? []
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        UserDefaults.standard.set(bookmarks, forKey: "zonoe.webBookmarks")
    }

    private func openWeb(_ value: String) {
        guard let url = URL(string: value), let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        let safari = SFSafariViewController(url: url)
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(safari, animated: true)
    }
}
''')

# 4) Build identity: create a new release so the frozen alphaone10 artifact is never overwritten.
project_path = ROOT / "Ksign.xcodeproj/project.pbxproj"
project = project_path.read_text()
if project.count("CURRENT_PROJECT_VERSION = 110;") != 2:
    raise SystemExit("alphaone11 build identity: expected two CURRENT_PROJECT_VERSION = 110 entries")
project_path.write_text(project.replace("CURRENT_PROJECT_VERSION = 110;", "CURRENT_PROJECT_VERSION = 111;"))

plist_path = ROOT / "Ksign/Resources/Info.plist"
plist = plist_path.read_text()
if plist.count("<string>v3.0.0-alphaone10</string>") != 1:
    raise SystemExit("alphaone11 release identity: alphaone10 marker not unique")
plist_path.write_text(plist.replace("<string>v3.0.0-alphaone10</string>", "<string>v3.0.0-alphaone11</string>", 1))

print("alphaone11 source notice + URL Scheme transform applied")
