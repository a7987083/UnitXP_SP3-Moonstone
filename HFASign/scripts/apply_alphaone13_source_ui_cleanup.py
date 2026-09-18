#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path("HFASignBuild")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def ensure_import(text: str, module: str) -> str:
    line = f"import {module}\n"
    if line in text:
        return text
    if "import SwiftUI\n" in text:
        return text.replace("import SwiftUI\n", "import SwiftUI\n" + line, 1)
    return line + text


# 1) Remove the alphaone11/12 repository announcement UI completely.
source_view = ROOT / "Ksign/Views/Sources/Apps/SourceAppsView.swift"
source = source_view.read_text()

source, helper_count = re.subn(
    r"\n\s*private func repositoryNotice\(for loaded: \[LoadedSource\]\) -> String\? \{.*?\n\s*\}\n\n(?=\s*var body: some View)",
    "\n",
    source,
    count=1,
    flags=re.S,
)
require(helper_count == 1, f"alphaone13: repositoryNotice helper count={helper_count}")

notice_body_pattern = re.compile(
    r"if let sources, !sources\.isEmpty \{\s*"
    r"VStack\(spacing: 0\) \{\s*"
    r"if let notice = repositoryNotice\(for: sources\) \{.*?\n\s*\}\s*"
    r"SourceAppsTableRepresentableView\(sources: sources, searchText: \$searchText, filter: filter\) \{ selectedRoute = \$0 \}\s*"
    r"\.ignoresSafeArea\(\)\s*"
    r"\}\s*"
    r"\} else \{ ProgressView\(\) \}",
    re.S,
)
source, body_count = notice_body_pattern.subn(
    "if let sources, !sources.isEmpty {\n"
    "                SourceAppsTableRepresentableView(sources: sources, searchText: $searchText, filter: filter) { selectedRoute = $0 }\n"
    "                    .ignoresSafeArea()\n"
    "            } else { ProgressView() }",
    source,
    count=1,
)
require(body_count == 1, f"alphaone13: source notice body count={body_count}")
source_view.write_text(source)


# 2) Disable every automatic software-source recognition path.
#    a) external URL Scheme addsource/source must no longer feed arbitrary links to FR.handleSource.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = app_path.read_text()
app, addsource_count = re.subn(
    r"\n\s*if action == \"addsource\", let value = queryValue\(\"url\", from: url\), isHTTPURL\(value\) \{\s*"
    r"FR\.handleSource\(value\) \{ \}\s*return\s*\}",
    "",
    app,
    count=1,
    flags=re.S,
)
require(addsource_count == 1, f"alphaone13: addsource route count={addsource_count}")

# Historical /source/ route. Keep the scheme router itself, remove only source auto-import.
app, source_route_count = re.subn(
    r"\n\s*if let fullPath = url\.validatedScheme\(after: \"/source/\"\) \{\s*FR\.handleSource\(fullPath\) \{ \}\s*\}",
    "",
    app,
    count=1,
    flags=re.S,
)
if source_route_count == 0:
    # Some historical patches renamed/reformatted the same route; remove the call if still present.
    app = app.replace("FR.handleSource(fullPath) { }", "")
app_path.write_text(app)

#    b) clipboard URL detector/prompt: never raise its presentation flag.
loader_path = ROOT / "Ksign/Backend/Sources/SourceRepositoryLoader.swift"
loader = loader_path.read_text()
clipboard_true_count = loader.count("isShowingClipboardPrompt = true")
loader = loader.replace("isShowingClipboardPrompt = true", "isShowingClipboardPrompt = false")
# Clear candidates whenever the detector runs so stale URLs cannot re-open a prompt later.
if "func finishClipboardImport()" in loader and "func disableClipboardSourceRecognition()" not in loader:
    marker = "\tfunc finishClipboardImport() {\n"
    helper = (
        "\tfunc disableClipboardSourceRecognition() {\n"
        "\t\tclipboardCandidates.removeAll()\n"
        "\t\tisShowingClipboardPrompt = false\n"
        "\t}\n\n"
    )
    loader = loader.replace(marker, helper + marker, 1)
loader_path.write_text(loader)


# 3) Manual Add Source stays available, but use a native UIAlertController instead of a SwiftUI sheet.
sources_view_path = ROOT / "Ksign/Views/Sources/SourcesView.swift"
sources_view = ensure_import(sources_view_path.read_text(), "UIKit")
require("_isAddingPresenting = true" in sources_view, "alphaone13: SourcesView add action not found")
sources_view = sources_view.replace("_isAddingPresenting = true", "presentAddSourceAlert()")

# Remove the old sheet presentation of SourcesAddView.
sources_view, sheet_count = re.subn(
    r"\n\s*\.sheet\(isPresented: \$_isAddingPresenting\) \{\s*SourcesAddView\(\)\s*\.presentationDetents\(\[\.medium\]\)\s*\}",
    "",
    sources_view,
    count=1,
    flags=re.S,
)
require(sheet_count == 1, f"alphaone13: SourcesAddView sheet count={sheet_count}")

add_source_helper = r'''

	@MainActor
	private func presentAddSourceAlert() {
		let alert = UIAlertController(
			title: "添加软件源",
			message: "请输入软件源地址",
			preferredStyle: .alert
		)
		alert.addTextField { field in
			field.placeholder = "https://example.com/repo.json"
			field.keyboardType = .URL
			field.textContentType = .URL
			field.autocapitalizationType = .none
			field.autocorrectionType = .no
			field.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		alert.addAction(UIAlertAction(title: "添加", style: .default) { [weak alert] _ in
			let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard !value.isEmpty else { return }
			FR.handleSource(value) {
				UINotificationFeedbackGenerator().notificationOccurred(.success)
			}
		})
		presentSystemAlert(alert)
	}

	@MainActor
	private func presentSystemAlert(_ alert: UIAlertController) {
		guard let scene = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene })
			.first(where: { $0.activationState == .foregroundActive }),
			let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
		var top = root
		while let presented = top.presentedViewController { top = presented }
		top.present(alert, animated: true)
	}
'''
require("presentAddSourceAlert()" in sources_view, "alphaone13: manual add source trigger missing")
insert_at = sources_view.rfind("\n}")
require(insert_at > 0, "alphaone13: SourcesView closing brace not found")
sources_view = sources_view[:insert_at] + add_source_helper + sources_view[insert_at:]
sources_view_path.write_text(sources_view)


# 4) Source unlock code entry: replace SwiftUI .alert TextField with native UIAlertController.
unlock_path = ROOT / "Ksign/Views/Sources/Apps/DownloadButtonView.swift"
unlock = ensure_import(unlock_path.read_text(), "UIKit")

unlock_alert_pattern = re.compile(
    r"\n\s*\.alert\(\"解锁 \\\(app\.currentName\)\", isPresented: \$showUnlock\) \{.*?\n\s*\} message: \{ Text\(\"输入卡密后将使用本机 UDID 向该软件源验证。\"\) \}",
    re.S,
)
unlock, unlock_alert_count = unlock_alert_pattern.subn(
    "\n\t\t.onChange(of: showUnlock) { value in\n"
    "\t\t\tguard value else { return }\n"
    "\t\t\tshowUnlock = false\n"
    "\t\t\tpresentUnlockAlert()\n"
    "\t\t}",
    unlock,
    count=1,
)
require(unlock_alert_count == 1, f"alphaone13: SwiftUI unlock alert count={unlock_alert_count}")

unlock_helper = r'''
	@MainActor
	private func presentUnlockAlert() {
		let alert = UIAlertController(
			title: "解锁 \(app.currentName)",
			message: "输入卡密后将使用本机 UDID 向该软件源验证。",
			preferredStyle: .alert
		)
		alert.addTextField { field in
			field.placeholder = "请输入卡密"
			field.autocapitalizationType = .none
			field.autocorrectionType = .no
			field.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
			unlockCode = ""
		})
		alert.addAction(UIAlertAction(title: "获取解锁码", style: .default) { _ in
			openPurchase()
		})
		alert.addAction(UIAlertAction(title: "解锁", style: .default) { [weak alert] _ in
			let code = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard !code.isEmpty else {
				UIAlertController.showAlertWithOk(title: "提示", message: "请输入卡密")
				return
			}
			unlockCode = code
			unlock()
		})
		presentSystemAlert(alert)
	}

	@MainActor
	private func presentSystemAlert(_ alert: UIAlertController) {
		guard let scene = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene })
			.first(where: { $0.activationState == .foregroundActive }),
			let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
		var top = root
		while let presented = top.presentedViewController { top = presented }
		top.present(alert, animated: true)
	}

'''
setup_marker = "\tprivate func setupObserver() {\n"
require(setup_marker in unlock, "alphaone13: DownloadButtonView setupObserver marker missing")
unlock = unlock.replace(setup_marker, unlock_helper + setup_marker, 1)
unlock_path.write_text(unlock)


# 5) URL Scheme documentation must no longer advertise automatic source recognition.
scheme_path = ROOT / "Ksign/Views/Settings/URLSchemeView.swift"
scheme_path.write_text(r'''import SwiftUI
import UIKit

struct URLSchemeView: View {
    var body: some View {
        List {
            Section("App 内打开网页") {
                endpoint("zonoe://web?url=https%3A%2F%2Fexample.com")
                Text("在 zonoe 内使用 Safari View 打开 HTTP/HTTPS 网页；无法展示时回退系统浏览器。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("下载 / 导入 IPA") {
                endpoint("zonoe://download/https%3A%2F%2Fexample.com%2Fapp.ipa")
                endpoint("zonoe://install/https%3A%2F%2Fexample.com%2Fapp.ipa")
                Text("download 与 install 继续进入 zonoe 下载/导入链。软件源不再从外部链接自动识别或添加。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("UDID Provider") {
                endpoint("zonoe://udid?callback=example%3A%2F%2Fcallback")
                Text("供其他 App 请求 zonoe 已保存的 UDID。callback 使用 URL 编码；nonce bridge 继续使用固定 127.0.0.1:14302 协议。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("参数规则") {
                Text("url / callback 参数建议完整进行 Percent-Encoding。软件源只能在软件源页面通过 + 按钮手动添加。")
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


# 6) alphaone13 product identity.
project_path = ROOT / "Ksign.xcodeproj/project.pbxproj"
project = project_path.read_text()
require(project.count("CURRENT_PROJECT_VERSION = 112;") == 2,
        "alphaone13: expected two CURRENT_PROJECT_VERSION = 112 entries")
project_path.write_text(project.replace("CURRENT_PROJECT_VERSION = 112;", "CURRENT_PROJECT_VERSION = 113;"))

plist_path = ROOT / "Ksign/Resources/Info.plist"
plist = plist_path.read_text()
require(plist.count("<string>v3.0.0-alphaone12</string>") == 1,
        "alphaone13: alphaone12 release marker not unique")
plist_path.write_text(plist.replace(
    "<string>v3.0.0-alphaone12</string>",
    "<string>v3.0.0-alphaone13</string>",
    1,
))

print(
    "alphaone13 applied: removed source announcements and automatic source recognition; "
    "native system alerts enabled for manual source add and unlock code entry"
)
