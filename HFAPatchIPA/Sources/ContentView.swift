import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: WorkspaceModel
    @State private var importingIPA = false
    @State private var importingConfig = false
    @State private var importingDylib = false
    @State private var sharing = false

    var body: some View {
        NavigationView {
            List {
                header
                filesSection
                actionSection
                if let app = model.prepared?.appInfo { resultSection(app) }
                if let prepared = model.prepared { patchSection(prepared) }
                if let error = model.errorMessage { errorSection(error) }
                if !model.logLines.isEmpty { logSection }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("HFAPatchIPA")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("v2.0.0").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $importingIPA) {
            DocumentPicker(contentTypes: [.hfaIPA, .data]) { url in
                importingIPA = false
                model.acceptImportedURL(url, kind: .ipa)
            }
        }
        .sheet(isPresented: $importingConfig) {
            DocumentPicker(contentTypes: [.json, .hfaPatchJSON, .data]) { url in
                importingConfig = false
                model.acceptImportedURL(url, kind: .config)
            }
        }
        .sheet(isPresented: $importingDylib) {
            DocumentPicker(contentTypes: [.data]) { url in
                importingDylib = false
                model.acceptImportedURL(url, kind: .dylib)
            }
        }
        .sheet(isPresented: $sharing) {
            if let output = model.output {
                ActivityView(items: [output.ipaURL, output.logURL])
            }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("TrollStore / 越狱无证书版")
                    .font(.headline)
                Text(model.status)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
                if model.isBusy { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(.vertical, 4)
        }
    }

    private var filesSection: some View {
        Section("输入文件") {
            fileRow(title: "已解密 IPA", value: model.ipaURL?.lastPathComponent) {
                importingIPA = true
            }
            fileRow(title: "游戏数据包", value: model.configURL?.lastPathComponent) {
                importingConfig = true
            }
            fileRow(title: "我的菜单 dylib", value: model.dylibURL?.lastPathComponent) {
                importingDylib = true
            }
        }
    }

    private var actionSection: some View {
        Section("处理") {
            Button {
                model.validate()
            } label: {
                Label("解包并校验", systemImage: "checkmark.shield")
            }
            .disabled(!model.canValidate)

            Picker("处理模式", selection: $model.buildMode) {
                ForEach(PatchBuildMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.prepared == nil || model.isBusy)

            Button {
                model.build()
            } label: {
                Label(model.buildMode == .menu ? "注入菜单并生成 IPA" : "写死 Patch 并生成 IPA",
                      systemImage: "shippingbox")
            }
            .disabled(!model.canBuild)

            if model.output != nil {
                Button {
                    sharing = true
                } label: {
                    Label("导出 IPA 和日志", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func patchSection(_ prepared: PreparedWorkspace) -> some View {
        Section("Patch 对比") {
            ForEach(prepared.comparisons) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.title).font(.headline)
                        Spacer()
                        Text(item.status.rawValue)
                            .font(.caption)
                            .foregroundColor(item.status == .unavailable ? .red :
                                             (item.status == .different || item.status == .enabled ? .orange : .green))
                    }
                    Text("\(item.target) + 0x\(String(item.rva, radix: 16).uppercased())")
                    Text("JSON Original  \(hex(item.jsonOriginal))")
                    Text("IPA Actual     \(item.actual.map(hex) ?? "无法读取")")
                    Text("Enabled        \(hex(item.enabled))")
                }
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(.vertical, 4)
            }
            if prepared.comparisons.contains(where: { $0.status == .different }) {
                Text("存在未知实际字节。继续时，菜单模式会把 IPA Actual 作为恢复字节；写死模式会直接写入 Enabled。")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
        }
    }

    private func resultSection(_ app: GameAppInfo) -> some View {
        Section("校验结果") {
            valueRow("应用", app.name)
            valueRow("BundleID", app.bundleIdentifier)
            valueRow("版本", "\(app.shortVersion) (\(app.buildVersion))")
            valueRow("主程序", app.executableName)
            if let config = model.prepared?.config {
                valueRow("功能", "\(config.features.count)")
                valueRow("模块", "\(config.targets.count)")
            }
            if let output = model.output {
                valueRow("输出", output.ipaURL.lastPathComponent)
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        Section("错误") {
            Text(error)
                .font(.footnote)
                .foregroundColor(.red)
                .textSelection(.enabled)
        }
    }

    private var logSection: some View {
        Section("处理日志") {
            ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func fileRow(title: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundColor(.primary)
                    Text(value ?? "未选择")
                        .font(.caption)
                        .foregroundColor(value == nil ? .secondary : .blue)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "folder")
            }
        }
        .disabled(model.isBusy)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.footnote)
    }

    private var statusColor: Color {
        if model.errorMessage != nil { return .red }
        if model.output != nil || model.prepared != nil { return .green }
        return .secondary
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

}
