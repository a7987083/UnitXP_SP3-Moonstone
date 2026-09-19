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


def clean_trailing_whitespace(path: Path) -> None:
    text = path.read_text()
    cleaned = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    path.write_text(cleaned)


# 1. Remove alphaone11/12 source-announcement UI.
source_path = ROOT / "Ksign/Views/Sources/Apps/SourceAppsView.swift"
source = source_path.read_text()
source, count = re.subn(
    r"\n\s*private func repositoryNotice\(for loaded: \[LoadedSource\]\) -> String\? \{.*?\n\s*\}\n\n(?=\s*var body: some View)",
    "\n",
    source,
    count=1,
    flags=re.S,
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
    source,
    count=1,
    flags=re.S,
)
require(count == 1, f"alphaone13: announcement body count={count}")
source_path.write_text(source)

# 2. Remove external automatic source recognition routes and rebuild keyboard dismissal.
app_path = ROOT / "Ksign/FeatherApp.swift"
app = ensure_import(app_path.read_text(), "UIKit")
app, count = re.subn(
    r"\n\s*if action == \"addsource\", let value = queryValue\(\"url\", from: url\), isHTTPURL\(value\) \{\s*FR\.handleSource\(value\) \{ \}\s*return\s*\}",
    "",
    app,
    count=1,
    flags=re.S,
)
require(count == 1, f"alphaone13: addsource route count={count}")
app, legacy_count = re.subn(
    r"\n\s*if let fullPath = url\.validatedScheme\(after: \"/source/\"\) \{\s*FR\.handleSource\(fullPath\) \{ \}\s*\}",
    "",
    app,
    count=1,
    flags=re.S,
)
require(legacy_count <= 1, f"alphaone13: legacy source route count={legacy_count}")
app, keyboard_count = re.subn(
    r"private struct ZonoeKeyboardDismissModifier: ViewModifier \{.*?\n\}\n\nprivate extension View \{",
    '''private struct ZonoeKeyboardDismissModifier: ViewModifier {
\tfunc body(content: Content) -> some View {
\t\tcontent
\t\t\t.scrollDismissesKeyboard(.interactively)
\t\t\t.toolbar {
\t\t\t\tToolbarItemGroup(placement: .keyboard) {
\t\t\t\t\tSpacer()
\t\t\t\t\tButton("完成") {
\t\t\t\t\t\tUIApplication.shared.sendAction(
\t\t\t\t\t\t\t#selector(UIResponder.resignFirstResponder),
\t\t\t\t\t\t\tto: nil,
\t\t\t\t\t\t\tfrom: nil,
\t\t\t\t\t\t\tfor: nil
\t\t\t\t\t\t)
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t}
}

private extension View {''',
    app,
    count=1,
    flags=re.S,
)
require(keyboard_count == 1, f"alphaone13: keyboard modifier count={keyboard_count}")
app_path.write_text(app)

# 3. Disable background clipboard source detection/prompt. Clipboard is read only after tapping +.
loader_path = ROOT / "Ksign/Backend/Sources/SourceRepositoryLoader.swift"
loader = loader_path.read_text()
require("isShowingClipboardPrompt" in loader, "alphaone13: clipboard coordinator not found")
loader = loader.replace("isShowingClipboardPrompt = true", "isShowingClipboardPrompt = false")
for needle in ("clipboardCandidates = candidates", "self.clipboardCandidates = candidates"):
    if needle in loader:
        loader = loader.replace(needle, needle + "\n\t\tclipboardCandidates.removeAll()", 1)
        break
loader_path.write_text(loader)

# 4. Keep already-loaded repositories while the source list changes and allow direct cache priming.
view_model_path = ROOT / "Ksign/Views/Sources/SourcesViewModel.swift"
view_model = view_model_path.read_text()
clear_block = '''\n\t\tawait MainActor.run {\n\t\t\tself.sources = [:]\n\t\t}\n'''
require(clear_block in view_model, "alphaone13: source cache clear block not found")
view_model = view_model.replace(clear_block, "\n", 1)
prime_marker = "\t@Published var sources: [AltSource: ASRepository] = [:]\n"
require(prime_marker in view_model, "alphaone13: sources cache marker not found")
view_model = view_model.replace(
    prime_marker,
    prime_marker + '''\n\t@MainActor\n\tfunc prime(_ source: AltSource, repository: ASRepository) {\n\t\tsources[source] = repository\n\t}\n''',
    1,
)
view_model_path.write_text(view_model)

# 5. Manual Add Source -> UIKit alert, + clipboard candidate prompt, loading overlay and first-open cache warmup.
sources_path = ROOT / "Ksign/Views/Sources/SourcesView.swift"
sources = ensure_import(sources_path.read_text(), "UIKit")
sources = ensure_import(sources, "NimbleJSON")
sources = ensure_import(sources, "Foundation")
require("_isAddingPresenting = true" in sources, "alphaone13: manual add trigger not found")
sources = sources.replace("_isAddingPresenting = true", "handleAddSourceTap()")
loading_marker = "if _filteredSources.isEmpty {"
require(loading_marker in sources, "alphaone13: source empty overlay marker not found")
sources = sources.replace(
    loading_marker,
    '''if _addingSourceLoading {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("正在添加软件源")
                                .font(.headline)
                            Text("正在请求并解析软件源…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                } else if _filteredSources.isEmpty {''',
    1,
)
sources, count = re.subn(
    r"\n\s*\.sheet\(isPresented: \$_isAddingPresenting\) \{\s*SourcesAddView\(\)\s*\.presentationDetents\(\[\.medium\]\)\s*\}",
    "",
    sources,
    count=1,
    flags=re.S,
)
require(count == 1, f"alphaone13: add-source sheet count={count}")
helper = r'''

	@MainActor
	private func handleAddSourceTap() {
		guard !_addingSourceLoading else { return }
		let clipboardText = UIPasteboard.general.string ?? ""
		if let url = extractHTTPURL(from: clipboardText, requireSourceSuffix: true) {
			presentClipboardSourceAlert(url)
		} else {
			presentAddSourceAlert()
		}
	}

	@MainActor
	private func presentClipboardSourceAlert(_ url: URL) {
		let alert = UIAlertController(
			title: "剪切板中的网址",
			message: url.absoluteString,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: "添加", style: .default) { _ in
			addSource(url)
		})
		alert.addAction(UIAlertAction(title: "手动添加", style: .default) { _ in
			DispatchQueue.main.async { presentAddSourceAlert() }
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		presentSystemAlert(alert)
	}

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
			field.returnKeyType = .done
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		alert.addAction(UIAlertAction(title: "添加", style: .default) { [weak alert] _ in
			let value = alert?.textFields?.first?.text ?? ""
			guard let url = extractHTTPURL(from: value, requireSourceSuffix: false) else {
				showSourceError("没有找到有效的 HTTP/HTTPS 软件源网址。")
				return
			}
			addSource(url)
		})
		presentSystemAlert(alert)
	}

	private func extractHTTPURL(from text: String, requireSourceSuffix: Bool) -> URL? {
		let range = NSRange(text.startIndex..<text.endIndex, in: text)
		if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
			for match in detector.matches(in: text, options: [], range: range) {
				guard let url = match.url,
					let scheme = url.scheme?.lowercased(),
					["http", "https"].contains(scheme) else { continue }
				if !requireSourceSuffix || isClipboardSourceURL(url) { return url }
			}
		}
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if let url = URL(string: trimmed),
			let scheme = url.scheme?.lowercased(),
			["http", "https"].contains(scheme),
			(!requireSourceSuffix || isClipboardSourceURL(url)) {
			return url
		}
		return nil
	}

	private func isClipboardSourceURL(_ url: URL) -> Bool {
		var path = url.path
		while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
		let last = (path as NSString).lastPathComponent.lowercased()
		return last == "appstore" || last.hasSuffix(".json")
	}

	@MainActor
	private func addSource(_ url: URL) {
		guard !_addingSourceLoading else { return }
		_addingSourceLoading = true
		NBFetchService().fetch(from: url) { (result: Result<ASRepository, Error>) in
			DispatchQueue.main.async {
				switch result {
				case .success(let repository):
					let identifier = repository.id ?? url.absoluteString
					guard !Storage.shared.sourceExists(identifier) else {
						finishAddingSource()
						showSourceError("该软件源已经添加。")
						return
					}
					Storage.shared.addSource(url, repository: repository, id: identifier) { error in
						DispatchQueue.main.async {
							if let error {
								finishAddingSource()
								showSourceError(error.localizedDescription)
								return
							}
							if let savedSource = Storage.shared.getSources().first(where: { $0.identifier == identifier }) {
								viewModel.prime(savedSource, repository: repository)
							}
							finishAddingSource(success: true)
						}
					}
				case .failure(let error):
					finishAddingSource()
					showSourceError(error.localizedDescription)
				}
			}
		}
	}

	@MainActor
	private func finishAddingSource(success: Bool = false) {
		_addingSourceLoading = false
		if success {
			UINotificationFeedbackGenerator().notificationOccurred(.success)
		}
	}

	@MainActor
	private func showSourceError(_ message: String) {
		let alert = UIAlertController(title: "添加软件源失败", message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
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

# 6. Unlock code entry -> UIKit UIAlertController.
unlock_path = ROOT / "Ksign/Views/Sources/Apps/DownloadButtonView.swift"
unlock = ensure_import(unlock_path.read_text(), "UIKit")
require("unlockFlow" in unlock and "unlockPromptPresented" in unlock, "alphaone13: consolidated unlock flow not found")
sheet_pattern = re.compile(
    r"\n\s*\.sheet\(isPresented: unlockPromptPresented\) \{\s*UnlockCodePrompt\(code: \$unlockCode, isValidating: unlockFlow == \.validating, errorMessage: unlockError\) \{.*?\.interactiveDismissDisabled\(unlockFlow == \.validating\)\s*\}",
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
    unlock,
    count=1,
)
require(count == 1, f"alphaone13: unlock sheet count={count}")
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
			field.returnKeyType = .done
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in resetUnlockFlow() })
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
require(marker in unlock, "alphaone13: setupObserver marker missing")
unlock = unlock.replace(marker, unlock_helper + marker, 1)
unlock_path.write_text(unlock)

# 7. Keep URL Scheme docs aligned: no background scanning; clipboard inspection only happens after +.
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
                Text("download 与 install 继续进入 zonoe 下载/导入链。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("UDID Provider") {
                endpoint("zonoe://udid?callback=example%3A%2F%2Fcallback")
                Text("供其他 App 请求 zonoe 已保存的 UDID。nonce bridge 继续使用固定 127.0.0.1:14302 协议。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("软件源") {
                Text("软件源页面只有在主动点击 + 时才读取一次剪切板；仅提示以 appstore 或 .json 结尾的 HTTP/HTTPS 地址，不进行后台自动扫描。")
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

# 8. alphaone13 identity.
project_path = ROOT / "Ksign.xcodeproj/project.pbxproj"
project = project_path.read_text()
require(project.count("CURRENT_PROJECT_VERSION = 112;") == 2, "alphaone13: expected two build 112 entries")
project_path.write_text(project.replace("CURRENT_PROJECT_VERSION = 112;", "CURRENT_PROJECT_VERSION = 113;"))

plist_path = ROOT / "Ksign/Resources/Info.plist"
plist = plist_path.read_text()
require(plist.count("<string>v3.0.0-alphaone12</string>") == 1, "alphaone13: alphaone12 marker not unique")
plist_path.write_text(plist.replace("<string>v3.0.0-alphaone12</string>", "<string>v3.0.0-alphaone13</string>", 1))

for path in (
    source_path, app_path, loader_path, view_model_path, sources_path,
    unlock_path, scheme_path, project_path, plist_path
):
    clean_trailing_whitespace(path)

print("alphaone13 source UX and keyboard transform applied")
