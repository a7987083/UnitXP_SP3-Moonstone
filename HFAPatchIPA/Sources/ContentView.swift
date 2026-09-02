import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: WorkspaceModel
    @State private var importKind: WorkspaceModel.ImportKind?
    @State private var sharingURLs: [URL] = []

    var body: some View {
        TabView {
            resourceView.tabItem { Label("资源", systemImage: "archivebox") }
            buildView.tabItem { Label("制作", systemImage: "hammer") }
            generatedView.tabItem { Label("已生成", systemImage: "checkmark.seal") }
            settingsView.tabItem { Label("设置", systemImage: "gearshape") }
        }
        .sheet(item: $importKind) { kind in
            DocumentPicker(contentTypes: [.data]) { url in
                importKind = nil
                model.acceptImportedURL(url, kind: kind)
            }
        }
        .sheet(isPresented: Binding(get: { !sharingURLs.isEmpty }, set: { if !$0 { sharingURLs = [] } })) {
            ActivityView(items: sharingURLs)
        }
    }

    private var resourceView: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 12) {
                        importButton("IPA", icon: "app.badge", kind: .ipa)
                        importButton("JSON", icon: "doc.badge.plus", kind: .config)
                        importButton("dylib", icon: "shippingbox", kind: .dylib)
                    }.buttonStyle(.bordered)
                }
                ForEach([ResourceKind.ipa, .config, .dylib], id: \.self) { kind in
                    Section(kind.rawValue) {
                        let items = model.resources.filter { $0.kind == kind }
                        if items.isEmpty { Text("暂无文件").foregroundColor(.secondary) }
                        ForEach(items) { resource in resourceRow(resource, selectable: true) }
                    }
                }
            }
            .navigationTitle("资源库")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Text("v2.1.0").font(.caption) } }
            .refreshable { model.refreshResources() }
        }.navigationViewStyle(.stack)
    }

    private var buildView: some View {
        NavigationView {
            List {
                Section("当前项目") {
                    selectedRow("已解密 IPA", model.ipaURL, .ipa)
                    selectedRow("游戏数据包", model.configURL, .config)
                    if model.buildMode == .menu { selectedRow("我的菜单 dylib", model.dylibURL, .dylib) }
                }
                Section("处理方式") {
                    Picker("模式", selection: $model.buildMode) {
                        ForEach(PatchBuildMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(model.buildMode == .fixed ? "直接把 Enabled 写入二进制，不注入菜单。" : "注入你的菜单 dylib，并把适配后的 JSON 放入游戏包。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("执行") {
                    Button { model.validate() } label: { Label("解包并读取 Patch", systemImage: "magnifyingglass") }.disabled(!model.canValidate)
                    Button { model.build() } label: {
                        Label(model.buildMode == .fixed ? "写死 Patch 并生成" : "注入菜单并生成", systemImage: "shippingbox.fill")
                    }.disabled(!model.canBuild)
                    if model.isBusy { ProgressView(model.status).frame(maxWidth: .infinity) }
                    else { Text(model.status).font(.footnote).foregroundColor(model.errorMessage == nil ? .secondary : .red) }
                }
                if let prepared = model.prepared {
                    Section("App 信息") {
                        valueRow("名称", prepared.appInfo.name)
                        valueRow("BundleID", prepared.appInfo.bundleIdentifier)
                        valueRow("版本", "\(prepared.appInfo.shortVersion) (\(prepared.appInfo.buildVersion))")
                        valueRow("功能 / Patch", "\(prepared.config.features.count) / \(prepared.comparisons.count)")
                    }
                    patchSection(prepared)
                }
                if let error = model.errorMessage { Section("处理错误") { Text(error).foregroundColor(.red).textSelection(.enabled) } }
                if let output = model.output {
                    Section("生成完成") {
                        Text(output.ipaURL.lastPathComponent)
                        Button("分享 IPA 和日志") { sharingURLs = [output.ipaURL, output.logURL] }
                    }
                }
            }.navigationTitle("制作 IPA")
        }.navigationViewStyle(.stack)
    }

    private var generatedView: some View {
        NavigationView {
            List {
                let outputs = model.resources.filter { $0.kind == .output }
                if outputs.isEmpty { Text("暂无生成记录").foregroundColor(.secondary) }
                ForEach(outputs) { resource in resourceRow(resource, selectable: false) }
            }.navigationTitle("已生成").refreshable { model.refreshResources() }
        }.navigationViewStyle(.stack)
    }

    private var settingsView: some View {
        NavigationView {
            Form {
                Section("文件") {
                    Toggle("生成后清理解包缓存", isOn: setting("cleanup", true))
                    Toggle("保留处理日志", isOn: setting("logs", true))
                    valueRow("文件访问", "已开启")
                }
                Section("默认设置") {
                    valueRow("注入目录", "Frameworks/")
                    valueRow("注入路径", "@executable_path")
                    valueRow("签名方式", "Ad-hoc")
                }
                Section("缓存") { Button("刷新资源库") { model.refreshResources() } }
                Section("关于") { valueRow("HFAPatchIPA", "v2.1.0") }
            }.navigationTitle("设置")
        }.navigationViewStyle(.stack)
    }

    private func patchSection(_ prepared: PreparedWorkspace) -> some View {
        Section("Patch 对比（警告不锁定）") {
            ForEach(prepared.comparisons) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(item.title).font(.headline); Spacer(); Text(item.status.rawValue).foregroundColor(statusColor(item.status)) }
                    Text("\(item.target) + 0x\(String(item.rva, radix: 16).uppercased())")
                    Text("JSON Original  \(hex(item.jsonOriginal))")
                    Text("IPA Actual     \(item.actual.map(hex) ?? "无法读取")")
                    Text("Enabled        \(hex(item.enabled))")
                }.font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.vertical, 3)
            }
        }
    }

    private func resourceRow(_ resource: LocalResource, selectable: Bool) -> some View {
        Button {
            if selectable { model.select(resource) } else { sharingURLs = [resource.url] }
        } label: {
            HStack {
                Image(systemName: resource.kind.icon).font(.title2).frame(width: 36).foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.url.lastPathComponent).foregroundColor(.primary).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: resource.size, countStyle: .file)).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isSelected(resource) { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
            }
        }
        .swipeActions {
            Button(role: .destructive) { model.delete(resource) } label: { Label("删除", systemImage: "trash") }
            Button { sharingURLs = [resource.url] } label: { Label("分享", systemImage: "square.and.arrow.up") }.tint(.blue)
        }
    }

    private func selectedRow(_ title: String, _ url: URL?, _ kind: WorkspaceModel.ImportKind) -> some View {
        Button { importKind = kind } label: {
            HStack {
                VStack(alignment: .leading) { Text(title).foregroundColor(.primary); Text(url?.lastPathComponent ?? "未选择").font(.caption).foregroundColor(url == nil ? .secondary : .blue).lineLimit(1) }
                Spacer(); Image(systemName: "folder")
            }
        }.disabled(model.isBusy)
    }

    private func importButton(_ title: String, icon: String, kind: WorkspaceModel.ImportKind) -> some View {
        Button { importKind = kind } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity) }
    }
    private func isSelected(_ resource: LocalResource) -> Bool { resource.url == model.ipaURL || resource.url == model.configURL || resource.url == model.dylibURL }
    private func valueRow(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing) } }
    private func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined() }
    private func statusColor(_ status: PatchByteStatus) -> Color { status == .original ? .green : (status == .unavailable ? .red : .orange) }
    private func setting(_ key: String, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
}

extension WorkspaceModel.ImportKind: Identifiable {
    var id: String { switch self { case .ipa: return "ipa"; case .config: return "config"; case .dylib: return "dylib" } }
}
