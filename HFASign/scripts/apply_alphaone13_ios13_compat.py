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

alt_source_manifest = root / "AltSourceKit/Package.swift"
alt_source = alt_source_manifest.read_text()
old_alt_target = ".iOS(.v14)"
new_alt_target = ".iOS(.v13)"
alt_source_count = alt_source.count(old_alt_target)
if alt_source_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one AltSourceKit {old_alt_target}, found {alt_source_count}"
    )
alt_source_manifest.write_text(alt_source.replace(old_alt_target, new_alt_target, 1))

nimble_manifest = root / "NimbleKit/Package.swift"
nimble = nimble_manifest.read_text()
old_nimble_target = ".iOS(.v16)"
new_nimble_target = ".iOS(.v13)"
nimble_target_count = nimble.count(old_nimble_target)
if nimble_target_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one NimbleKit {old_nimble_target}, found {nimble_target_count}"
    )
nimble_manifest.write_text(nimble.replace(old_nimble_target, new_nimble_target, 1))

nimble_date_path = root / "NimbleKit/Sources/NimbleExtensions/Date/Date+timeLeft.swift"
nimble_date = nimble_date_path.read_text()
old_date_default = "from now: Date = .now"
new_date_default = "from now: Date = Date()"
date_default_count = nimble_date.count(old_date_default)
if date_default_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one NimbleKit Date.now default, found {date_default_count}"
    )
nimble_date_path.write_text(nimble_date.replace(old_date_default, new_date_default, 1))

nimble_nav_path = root / "NimbleKit/Sources/NimbleExtensions/View/View+compatNavTransition.swift"
nimble_nav = nimble_nav_path.read_text()
old_nav_extension = "extension View {\n"
new_nav_extension = "@available(iOS 14.0, *)\nextension View {\n"
nav_extension_count = nimble_nav.count(old_nav_extension)
if nav_extension_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one NimbleKit navigation View extension, found {nav_extension_count}"
    )
nimble_nav_path.write_text(nimble_nav.replace(old_nav_extension, new_nav_extension, 1))

nimble_search_path = root / "NimbleKit/Sources/NimbleExtensions/View/View+compatSearchScopes.swift"
nimble_search = nimble_search_path.read_text()
old_search_scope = '''\t\tif #available(iOS 16.4, *) {
\t\t\tself.searchScopes(selection, activation: .onSearchPresentation, content)
\t\t} else {
\t\t\tself.searchScopes(selection, scopes: content)
\t\t}
'''
new_search_scope = '''\t\tif #available(iOS 16.4, *) {
\t\t\tself.searchScopes(selection, activation: .onSearchPresentation, content)
\t\t} else if #available(iOS 16.0, *) {
\t\t\tself.searchScopes(selection, scopes: content)
\t\t} else {
\t\t\tself
\t\t}
'''
search_scope_count = nimble_search.count(old_search_scope)
if search_scope_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one NimbleKit searchScopes compatibility block, found {search_scope_count}"
    )
nimble_search_path.write_text(nimble_search.replace(old_search_scope, new_search_scope, 1))

nimble_search_placement_path = root / "NimbleKit/Sources/NimbleExtensions/View/View+platformDrawerPlacement.swift"
nimble_search_placement = nimble_search_placement_path.read_text()
old_search_placement_extension = "extension SearchFieldPlacement {\n"
new_search_placement_extension = "@available(iOS 15.0, *)\nextension SearchFieldPlacement {\n"
search_placement_count = nimble_search_placement.count(old_search_placement_extension)
if search_placement_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one NimbleKit SearchFieldPlacement extension, found {search_placement_count}"
    )
nimble_search_placement_path.write_text(
    nimble_search_placement.replace(
        old_search_placement_extension,
        new_search_placement_extension,
        1,
    )
)

nimble_exporter_path = root / "NimbleKit/Sources/NimbleViews/UIKit/FileExporterRepresentableView.swift"
nimble_exporter = nimble_exporter_path.read_text()
old_exporter_picker = "        let picker = UIDocumentPickerViewController(forExporting: urlsToExport, asCopy: asCopy)\n"
new_exporter_picker = '''        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forExporting: urlsToExport, asCopy: asCopy)
        } else {
            picker = UIDocumentPickerViewController(
                urls: urlsToExport,
                in: asCopy ? .exportToService : .moveToService
            )
        }
'''
exporter_picker_count = nimble_exporter.count(old_exporter_picker)
if exporter_picker_count != 1:
    raise SystemExit(
        f"iOS13 compat: expected one NimbleKit exporter picker construction, found {exporter_picker_count}"
    )
nimble_exporter_path.write_text(
    nimble_exporter.replace(old_exporter_picker, new_exporter_picker, 1)
)

alt_color_path = root / "AltSourceKit/Sources/AltSourceKit/Extensions/Color/Color+Codable.swift"
alt_color = alt_color_path.read_text()
old_color_components = '''#if canImport(UIKit)
\t\ttypealias NativeColor = UIColor
#elseif canImport(AppKit)
\t\ttypealias NativeColor = NSColor
#endif
\t\t
\t\tvar r: CGFloat = 0
\t\tvar g: CGFloat = 0
\t\tvar b: CGFloat = 0
\t\tvar o: CGFloat = 0
\t\t
\t\tguard NativeColor(self).getRed(&r, green: &g, blue: &b, alpha: &o) else {
\t\t\t// You can handle the failure here as you want
\t\t\treturn (0, 0, 0, 0)
\t\t}
\t\t
\t\treturn (r, g, b, o)
'''
new_color_components = '''\t\tvar r: CGFloat = 0
\t\tvar g: CGFloat = 0
\t\tvar b: CGFloat = 0
\t\tvar o: CGFloat = 0

#if canImport(UIKit)
\t\t// SwiftUI Color -> UIColor is public only from iOS 14.
\t\t// Keep the original conversion where available; iOS 13 needs a
\t\t// compile-safe fallback because SwiftUI exposes no public resolver.
\t\tif #available(iOS 14.0, *) {
\t\t\tguard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &o) else {
\t\t\t\treturn (0, 0, 0, 0)
\t\t\t}
\t\t\treturn (r, g, b, o)
\t\t}
\t\treturn (0, 0, 0, 1)
#elseif canImport(AppKit)
\t\tguard NSColor(self).getRed(&r, green: &g, blue: &b, alpha: &o) else {
\t\t\treturn (0, 0, 0, 0)
\t\t}
\t\treturn (r, g, b, o)
#endif
'''
color_component_count = alt_color.count(old_color_components)
if color_component_count != 1:
    raise SystemExit(
        "iOS13 compat: expected one AltSourceKit Color.components implementation, "
        f"found {color_component_count}"
    )
alt_color_path.write_text(alt_color.replace(old_color_components, new_color_components, 1))

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

print(
    f"iOS13 compat applied; deployment target replacements: {count}; "
    f"AltSourceKit and NimbleKit targets lowered to iOS 13; Date.now, Namespace, search, and file exporter compatibility applied; Color bridge guarded for iOS 14+"
)
