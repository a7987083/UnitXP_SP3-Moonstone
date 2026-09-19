#!/usr/bin/env python3
from pathlib import Path

sources_path = Path("HFASignBuild/Ksign/Views/Sources/SourcesView.swift")
sources = sources_path.read_text()
old = "Storage.shared.addSource(url, repository: repository, id: identifier) { error in"
new = "Storage.shared.addSource(url, repository: repository) { error in"
if old not in sources:
    raise SystemExit("alphaone13 compilefix: source add call not found")
sources = sources.replace(old, new, 1)
sources_path.write_text(sources)

view_model = Path("HFASignBuild/Ksign/Views/Sources/SourcesViewModel.swift").read_text()
app = Path("HFASignBuild/Ksign/FeatherApp.swift").read_text()
loader = Path("HFASignBuild/Ksign/Backend/Sources/SourceRepositoryLoader.swift").read_text()

checks = {
    "loading overlay": 'Text("正在添加软件源")' in sources and 'ProgressView()' in sources,
    "clipboard title": 'title: "剪切板中的网址"' in sources,
    "clipboard actions": all(f'title: "{name}"' in sources for name in ("添加", "手动添加", "取消")),
    "clipboard suffix filtering": 'requireSourceSuffix: true' in sources and 'last == "appstore" || last.hasSuffix(".json")' in sources,
    "manual mixed-text URL extraction": 'requireSourceSuffix: false' in sources and 'NSDataDetector' in sources,
    "first-open cache prime": 'viewModel.prime(savedSource, repository: repository)' in sources and 'func prime(_ source: AltSource, repository: ASRepository)' in view_model,
    "no global keyboard bridge": 'ZonoeKeyboardDismissBridge' not in app and 'UITapGestureRecognizer' not in app,
    "native keyboard dismissal": '.scrollDismissesKeyboard(.interactively)' in app and 'ToolbarItemGroup(placement: .keyboard)' in app and 'Button("完成")' in app,
    "background clipboard prompt disabled": 'isShowingClipboardPrompt = true' not in loader,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("alphaone13 invariant failure: " + ", ".join(failed))

print("alphaone13 source UX compilefix + invariants passed")
