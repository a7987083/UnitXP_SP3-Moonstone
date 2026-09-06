import SwiftUI

struct ContentView: View {
    @StateObject private var model = SourceProbeModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("软件源 URL", text: $model.urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    presetButton("普通 JSON", action: model.usePlainPreset)
                    presetButton("appstore / V1", action: model.useLegacyPreset)
                    presetButton("appstore_v2 / QNQ", action: model.useV2Preset)
                    presetButton("appstore_v2 / YXY", action: model.useV2AltPreset)
                }

                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                    Text("V2 Key：内置 / 自动加载")
                        .font(.caption.monospaced())
                    Spacer()
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("运行当前") { Task { await model.runCurrent() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading)
                    Button("四源全部运行") { Task { await model.runAll() } }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoading)
                }

                if model.isLoading {
                    ProgressView("按原版流程执行…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ScrollView {
                    Text(model.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    if let url = model.exportReportURL {
                        ShareLink(item: url) { Label("导出日志", systemImage: "square.and.arrow.up") }
                    }
                    if let url = model.exportDecodedURL {
                        ShareLink(item: url) { Label("导出 JSON", systemImage: "doc.text") }
                    }
                    Spacer()
                    Text("v0.7.2")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("QNQ Source Lab")
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }
}
