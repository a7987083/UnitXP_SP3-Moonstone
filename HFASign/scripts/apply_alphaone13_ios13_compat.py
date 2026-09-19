#!/usr/bin/env python3
from pathlib import Path

root = Path("HFASignBuild")
project = root / "Ksign.xcodeproj/project.pbxproj"
text = project.read_text()
count = text.count("IPHONEOS_DEPLOYMENT_TARGET = 16.0;")
if count == 0:
    raise SystemExit("iOS13 compat: no 16.0 deployment targets found")
text = text.replace("IPHONEOS_DEPLOYMENT_TARGET = 16.0;", "IPHONEOS_DEPLOYMENT_TARGET = 13.0;")
project.write_text(text)

app_path = root / "Ksign/FeatherApp.swift"
app = app_path.read_text()
old = '''\tfunc body(content: Content) -> some View {
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
'''
new = '''\t@ViewBuilder
\tfunc body(content: Content) -> some View {
\t\tif #available(iOS 16.0, *) {
\t\t\tcontent
\t\t\t\t.scrollDismissesKeyboard(.interactively)
\t\t\t\t.toolbar {
\t\t\t\t\tToolbarItemGroup(placement: .keyboard) {
\t\t\t\t\t\tSpacer()
\t\t\t\t\t\tButton("完成") { dismissKeyboard() }
\t\t\t\t\t}
\t\t\t\t}
\t\t} else {
\t\t\tcontent
\t\t}
\t}

\tprivate func dismissKeyboard() {
\t\tUIApplication.shared.sendAction(
\t\t\t#selector(UIResponder.resignFirstResponder),
\t\t\tto: nil,
\t\t\tfrom: nil,
\t\t\tfor: nil
\t\t)
\t}
'''
if old not in app:
    raise SystemExit("iOS13 compat: keyboard modifier block not found")
app = app.replace(old, new, 1)
app_path.write_text(app)

sources_path = root / "Ksign/Views/Sources/SourcesView.swift"
sources = sources_path.read_text()
sources = sources.replace(".controlSize(.large)\n", "")
sources = sources.replace(".foregroundStyle(.secondary)", ".foregroundColor(.secondary)")
sources = sources.replace(".background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))", ".background(Color(UIColor.secondarySystemBackground))\n                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))")
sources_path.write_text(sources)

print(f"iOS13 compat applied; deployment target replacements: {count}")
