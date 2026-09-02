import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: WorkspaceModel
    @State private var tab = 0
    @State private var category: ResourceKind = .ipa
    @State private var importKind: WorkspaceModel.ImportKind?
    @State private var selectedResource: LocalResource?
    @State private var shareURLs: [URL] = []
    @State private var search = ""

    private let theme = Color(red: 0.22, green: 0.62, blue: 0.93)

    var body: some View {
        TabView(selection: $tab) {
            resources.tag(0).tabItem { Label("资源", systemImage: "archivebox") }
            build.tag(1).tabItem { Label("制作", systemImage: "square.grid.2x2") }
            packages.tag(2).tabItem { Label("数据包", systemImage: "doc.text") }
            outputs.tag(3).tabItem { Label("已生成", systemImage: "arrow.down.to.line") }
            settings.tag(4).tabItem { Label("设置", systemImage: "gearshape") }
        }
        .accentColor(theme)
        .sheet(item: $importKind) { kind in
            DocumentPicker(contentTypes: [.data]) { url in
                importKind = nil
                model.acceptImportedURL(url, kind: kind)
            }
        }
        .sheet(isPresented: Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = [] } })) {
            ActivityView(items: shareURLs)
        }
        .actionSheet(item: $selectedResource) { item in
            ActionSheet(title: Text(item.url.lastPathComponent), buttons: resourceActions(item))
        }
    }

    private var resources: some View {
        VStack(spacing: 0) {
            topBar("资源", trailing: "导入") { importKind = importKindForCategory }
            HStack(spacing: 0) {
                categoryButton("App", .ipa)
                categoryButton("Zip", .output)
                categoryButton("动态库", .dylib)
                categoryButton("数据包", .config)
                categoryButton("已生成", .output)
            }.frame(height: 50).background(theme)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundColor(.secondary)
                TextField("搜索", text: $search).font(.title3)
            }
            .padding(.horizontal, 15).frame(height: 52)
            .background(Color(.secondarySystemGroupedBackground)).cornerRadius(14).padding(12)
            List(filteredResources) { item in
                Button { selectedResource = item } label: { resourceRow(item) }.buttonStyle(.plain)
            }
            .overlay(Group {
                if filteredResources.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: category.icon).font(.system(size: 46)).foregroundColor(.secondary)
                        Text("暂无文件").foregroundColor(.secondary)
                        Button("导入文件") { importKind = importKindForCategory }.buttonStyle(.borderedProminent)
                    }
                }
            })
            .listStyle(.plain).refreshable { model.refreshResources() }
        }.background(Color(.systemGroupedBackground))
    }

    private var build: some View {
        NavigationView {
            List {
                Section("输入文件") {
                    pickerRow("已解密 IPA", model.ipaURL, .ipa)
                    pickerRow("游戏数据包", model.configURL, .config)
                    if model.buildMode == .menu { pickerRow("菜单动态库", model.dylibURL, .dylib) }
                }
                Section("处理方式") {
                    Picker("模式", selection: $model.buildMode) {
                        ForEach(PatchBuildMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(model.buildMode == .fixed ? "直接把 Enabled 写进二进制。" : "注入你自己的菜单动态库，并写入适配后的 JSON。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                if let prepared = model.prepared {
                    Section("App 信息") {
                        valueRow("App 名字", prepared.appInfo.name)
                        valueRow("Bundle Identifier", prepared.appInfo.bundleIdentifier)
                        valueRow("版本号", prepared.appInfo.shortVersion)
                    }
                    comparisonSection(prepared)
                }
                Section("处理") {
                    Button { model.validate() } label: { Label("解包、读取并对比 Patch", systemImage: "shield.checkered") }
                        .disabled(!model.canValidate)
                    Button { model.build() } label: {
                        Label(model.buildMode == .fixed ? "写死 Patch 并生成 IPA" : "注入菜单并生成 IPA", systemImage: "shippingbox.fill")
                    }.disabled(!model.canBuild)
                    if model.isBusy { ProgressView(model.status).frame(maxWidth: .infinity) }
                    else { Text(model.status).font(.footnote).foregroundColor(model.errorMessage == nil ? .secondary : .red) }
                }
                if let output = model.output {
                    Section("生成完成") {
                        Button(output.ipaURL.lastPathComponent) { shareURLs = [output.ipaURL, output.logURL] }
                    }
                }
            }
            .navigationTitle("制作配置").navigationBarTitleDisplayMode(.inline).listStyle(.insetGrouped)
        }.navigationViewStyle(.stack)
    }

    private var packages: some View {
        NavigationView {
            List {
                Section { Button { importKind = .config } label: { Label("导入 .hfapatch.json", systemImage: "folder.badge.plus") } }
                Section("游戏数据包") { resourceRows(kind: .config) }
            }.navigationTitle("数据包").navigationBarTitleDisplayMode(.inline)
        }.navigationViewStyle(.stack)
    }

    private var outputs: some View {
        NavigationView {
            List { resourceRows(kind: .output) }
                .navigationTitle("已生成").navigationBarTitleDisplayMode(.inline).refreshable { model.refreshResources() }
        }.navigationViewStyle(.stack)
    }

    private var settings: some View {
        NavigationView {
            Form {
                Section { valueRow("UDID", UIDevice.current.identifierForVendor?.uuidString ?? "不可用") }
                Section {
                    Button { importKind = .ipa } label: { settingRow("导入文件", "folder.fill", .blue) }
                    Button { model.refreshResources() } label: { settingRow("缓存管理", "archivebox", .primary) }
                    valueRow("剩余空间", freeSpace)
                }
                Section("默认配置") {
                    Toggle("生成后清理解包缓存", isOn: setting("cleanup", true))
                    Toggle("保留处理日志", isOn: setting("logs", true))
                    Toggle("仅警告，不强制限制", isOn: .constant(true)).disabled(true)
                    valueRow("注入路径", "@executable_path/Frameworks/")
                }
                Section("文件访问") {
                    valueRow("分享导入", "已开启 public.data")
                    valueRow("HFAPatchIPA", "v2.2.0")
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        }.navigationViewStyle(.stack)
    }

    private func topBar(_ title: String, trailing: String, action: @escaping () -> Void) -> some View {
        ZStack {
            theme.ignoresSafeArea(edges: .top)
            Text(title).font(.headline).foregroundColor(.white)
            HStack { Spacer(); Button(trailing, action: action).foregroundColor(.white).padding(.trailing, 18) }
        }.frame(height: 44)
    }

    private func categoryButton(_ title: String, _ kind: ResourceKind) -> some View {
        Button { category = kind } label: {
            VStack(spacing: 7) {
                Text(title).font(.system(size: 15))
                Rectangle().fill(category == kind ? Color.red : .clear).frame(height: 3)
            }.foregroundColor(category == kind ? .white : .white.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filteredResources: [LocalResource] {
        model.resources.filter { $0.kind == category && (search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search)) }
    }

    private func resourceRow(_ item: LocalResource) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 17).fill(iconGradient(item.kind)).frame(width: 78, height: 78)
                .overlay(Image(systemName: item.kind.icon).font(.system(size: 31, weight: .medium)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 7) {
                Text(displayName(item)).font(.system(size: 20)).foregroundColor(.primary).lineLimit(1)
                Text("\(item.kind.rawValue) | \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                    .font(.system(size: 14)).foregroundColor(.secondary)
                Text(item.url.lastPathComponent).font(.system(size: 14)).foregroundColor(.primary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }

    @ViewBuilder private func resourceRows(kind: ResourceKind) -> some View {
        let items = model.resources.filter { $0.kind == kind }
        if items.isEmpty { Text("暂无文件").foregroundColor(.secondary) }
        ForEach(items) { item in Button { selectedResource = item } label: { compactRow(item) }.buttonStyle(.plain) }
    }

    private func compactRow(_ item: LocalResource) -> some View {
        HStack {
            Image(systemName: item.kind.icon).font(.title2).frame(width: 36).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).foregroundColor(.primary).lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).font(.caption).foregroundColor(.secondary)
            }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
    }

    private func pickerRow(_ title: String, _ url: URL?, _ kind: WorkspaceModel.ImportKind) -> some View {
        Button { importKind = kind } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundColor(.primary)
                    Text(url?.lastPathComponent ?? "点击选择文件").font(.caption).foregroundColor(url == nil ? .secondary : .blue).lineLimit(1)
                }
                Spacer(); Image(systemName: "folder").font(.title2)
            }
        }.disabled(model.isBusy)
    }

    private func comparisonSection(_ prepared: PreparedWorkspace) -> some View {
        Section("Patch 对比（仅警告，不锁定）") {
            ForEach(prepared.comparisons) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(item.title).font(.headline); Spacer(); Text(item.status.rawValue).foregroundColor(statusColor(item.status)) }
                    Text("OFFSET   0x\(String(item.rva, radix: 16).uppercased())")
                    Text("ORIGINAL \(hex(item.jsonOriginal))")
                    Text("ACTUAL   \(item.actual.map(hex) ?? "无法读取")")
                    Text("ENABLED  \(hex(item.enabled))")
                }.font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.vertical, 4)
            }
        }
    }

    private func resourceActions(_ item: LocalResource) -> [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = []
        if item.kind != .output {
            buttons.append(.default(Text(item.kind == .ipa ? "制作" : "选择")) { model.select(item); tab = 1 })
        }
        buttons.append(.default(Text("分享")) { shareURLs = [item.url] })
        buttons.append(.destructive(Text("删除")) { model.delete(item) })
        buttons.append(.cancel(Text("取消")))
        return buttons
    }

    private func settingRow(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.title2).frame(width: 30).foregroundColor(color); Text(title).foregroundColor(.primary); Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary) }
    }
    private func valueRow(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing).lineLimit(2) } }
    private var importKindForCategory: WorkspaceModel.ImportKind { switch category { case .config: return .config; case .dylib: return .dylib; default: return .ipa } }
    private func displayName(_ item: LocalResource) -> String { item.url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ") }
    private func iconGradient(_ kind: ResourceKind) -> LinearGradient {
        let colors: [Color]
        switch kind { case .ipa: colors = [.indigo, .purple]; case .config: colors = [.orange, .red]; case .dylib: colors = [.black, .green]; case .output: colors = [.blue, .cyan] }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var freeSpace: String {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return ByteCountFormatter.string(fromByteCount: values?.volumeAvailableCapacityForImportantUsage ?? 0, countStyle: .file)
    }
    private func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined() }
    private func statusColor(_ status: PatchByteStatus) -> Color { status == .original ? .green : (status == .unavailable ? .red : .orange) }
    private func setting(_ key: String, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
}

extension WorkspaceModel.ImportKind: Identifiable {
    var id: String { switch self { case .ipa: return "ipa"; case .config: return "config"; case .dylib: return "dylib" } }
}
