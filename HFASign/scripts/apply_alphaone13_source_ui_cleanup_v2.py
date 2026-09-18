#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path("HFASignBuild")


def require(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(message)


def ensure_import(text: str, module: str) -> str:
    line = f"import {module}\n"
    if line in text:
        return text
    if "import SwiftUI\n" in text:
        return text.replace("import SwiftUI\n", "import SwiftUI\n" + line, 1)
    return line + text


# 1) Remove source announcement UI.
source_path = ROOT / "Ksign/Views/Sources/Apps/SourceAppsView.swift"
source = source_path.read_text()
source, count = re.subn(
    r"\n\s*private func repositoryNotice\(for loaded: \[LoadedSource\]\) -> String\? \{.*?\n\s*\}\n\n(?=\s*var body: some View)",
    "\n", source, count=1, flags=re.S,
)
require(count == 1, f"alphaone13: repositoryNotice helper count={count}")
source, count = re.subn(
    r"if let sources, !sources\.isEmpty \{\s*VStack\(spacing: 0\) \{\s*"
    r"if let notice = repositoryNotice\(for: sources\) \{.*?\n\s*\}\s*"
    r"SourceAppsTableRepresentableView\(sources: sources, searchText: \$searchText, filter: filter\) \{ selectedRoute = \$0 \}\s*"
    r"\.ignoresSafeArea\(\)\s*\}\s*\} else \{ ProgressView\(\) \}",
    "if let sources, !sources.isEmpty {\n"
    "                SourceAppsTableRepresentableView(sources: sources, searchText: $searchText, filter: filter) { selectedRoute = $0 }\n"
    "                    .ignoresSafeArea()\n"
    "            } else { ProgressView() }",
    source, count=1, flags=re.S,
)
require(count == 1, f"alphaone13: announcement body count={count}")
source_path.write_text(source)


# 2) Remove external automatic source recognition.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = app_path.read_text()
app, count = re.subn(
    r"\n\s*if action == \"addsource\", let value = queryValue\(\"url\", from: url\), isHTTPURL\(value\) \{\s*"
    r"FR\.handleSource\(value\) \{ \}\s*return\s*\}",
    "", app, count=1, flags=re.S,
)
require(count == 1, f"alphaone13: addsource route count={count}")
app = re.sub(
    r"\n\s*if let fullPath = url\.validatedScheme\(after: \"/source/\"\) \{\s*FR\.handleSource\(fullPath\) \{ \}\s*\}",
    "", app, count=1, flags=re.S,
)
app = app.replace("FR.handleSource(fullPath) { }", "")
app_path.write_text(app)


# 3) Disable clipboard source recognition/prompt.
loader_path = ROOT / "Ksign/Backend/Sources/SourceRepositoryLoader.swift"
loader = loader_path.read_text()
require("isShowingClipboardPrompt" in loader, "alphaone13: clipboard source coordinator not found")
loader = loader.replace("isShowingClipboardPrompt = true", "isShowingClipboardPrompt = false")
for needle in ("clipboardCandidates = candidates", "self.clipboardCandidates = candidates"):
    if needle in loader:
        loader = loader.replace(needle, needle + "\n\t\tclipboardCandidates.removeAll()", 1)
        break
loader_path.write_text(loader)


# 4) Manual Add Source -> UIKit UIAlertController.
sources_path = ROOT / "Ksign/Views/Sources/SourcesView.swift"
sources = ensure_import(sources_path.read_text(), "UIKit")
require("_isAddingPresenting = true" in sources, "alphaone13: manual add trigger not found")
sources = sources.replace("_isAddingPresenting = true", "presentAddSourceAlert()")
sources, count = re.subn(
    r"\n\s*\.sheet\(isPresented: \$_isAddingPresenting\) \{\s*SourcesAddView\(\)\s*\.presentationDetents\(\[\.medium\]\)\s*\}",
    "", sources, count=1, flags=re.S,
)
require(count == 1, f"alphaone13: add-source sheet count={count}")
helper = r'''

	@MainActor
	private func presentAddSourceAlert() {
		let alert = UIAlertController(title: "添加软件源", message: "请输入软件源地址", preferredStyle: .alert)
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
			FR.handleSource(value) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
		})
		presentSystemAlert(alert)
	}

	@MainActor
	private func presentSystemAlert(_ alert: UIAlertController) {
		guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
			.first(where: { $0.activationState == .foregroundActive }),
			let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
		var top = root
		while let presented = top.presentedViewController { top = presented }
		top.present(alert, animated: true)
	}
'''
insert_at = sources.rfind("\n}")
require(insert_at > 0, "alphaone13: SourcesView closing brace not found")
sources = sources[:insert_at] + helper + sources[insert_at:]
sources_path.write_text(sources)


# 5) Unlock card-key input -> UIKit UIAlertController.
# Consolidated baseline uses unlockFlow + unlockPromptPresented, not showUnlockCode.
unlock_path = ROOT / "Ksign/Views/Sources/Apps/DownloadButtonView.swift"
unlock = ensure_import(unlock_path.read_text(), "UIKit")
require("unlockFlow" in unlock and "unlockPromptPresented" in unlock,
        "alphaone13: consolidated unlock flow not found")

sheet_pattern = re.compile(
    r"\n\s*\.sheet\(isPresented: unlockPromptPresented\) \{\s*"
    r"UnlockCodePrompt\(code: \$unlockCode, isValidating: unlockFlow == \.validating, errorMessage: unlockError\) \{.*?"
    r"\.interactiveDismissDisabled\(unlockFlow == \.validating\)\s*\}",
    re.S,
)
unlock, count = sheet_pattern.subn(
    "\n\t\t.onChange(of: unlockFlow) { state in\n"
    "\t\t\tguard state == .showingPrompt else { return }\n"
    "\t\t\tDispatchQueue.main.async {\n"
    "\t\t\t\tguard unlockFlow == .showingPrompt else { return }\n"
    "\t\t\t\tunlockFlow = .idle\n"
    "\t\t\t\tpresentUnlockCodeAlert()\n"
    "\t\t\t}\n"
    "\t\t}",
    unlock, count=1,
)
require(count == 1, f"alphaone13: consolidated unlock sheet count={count}")

unlock_helper = r'''
	@MainActor
	private func presentUnlockCodeAlert() {
		let errorText = unlockError?.trimmingCharacters(in: .whitespacesAndNewlines)
		let message = (errorText?.isEmpty == false)
			? "上次验证失败：\(errorText!)\n\n请输入卡密后重新验证。"
			: "输入卡密后将使用本机 UDID 向该软件源验证。"
		let alert = UIAlertController(title: "使用解锁码", message: message, preferredStyle: .alert)
		alert.addTextField { field in
			field.placeholder = "请输入卡密"
			field.text = unlockCode
			field.autocapitalizationType = .none
			field.autocorrectionType = .no
			field.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
			resetUnlockFlow()
		})
		alert.addAction(UIAlertAction(title: "使用解锁码", style: .default) { [weak alert] _ in
			let code = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard !code.isEmpty else {
				unlockError = "请输入卡密"
				unlockFlow = .showingPrompt
				return
			}
			unlockCode = code
			unlock()
		})
		presentSystemAlert(alert)
	}

	@MainActor
	private func presentSystemAlert(_ alert: UIAlertController) {
		guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
			.first(where: { $0.activationState == .foregroundActive }),
			let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
		var top = root
		while let presented = top.presentedViewController { top = presented }
		top.present(alert, animated: true)
	}

'''
marker = "\tprivate func setupObserver() {\n"
require(marker in unlock, "alphaone13: DownloadButtonView setupObserver marker missing")
unlock = unlock.replace(marker, unlock_helper + marker, 1)
unlock_path.write_text(unlock)


# 6) URL Scheme docs: source auto-recognition endpoints removed.
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
                Text("供其他 App 请求 zonoe 已保存的 UDID。nonce bridge 继续使用固定 127.0.0.1:14302 协议。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("参数规则") {
                Text("软件源只能在软件源页面通过 + 按钮手动添加，不再扫描剪贴板或把外部链接自动识别为软件源。")
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
                Text(value).font(.system(.footnote, design: .monospaced)).foregroundStyle(.primary).textSelection(.enabled)
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc")
            }
        }
    }
}
''')


# 7) alphaone13 identity.
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
    "<string>v3.0.0-alphaone13</string>", 1,
))

print("alphaone13 consolidated cleanup transform applied")
