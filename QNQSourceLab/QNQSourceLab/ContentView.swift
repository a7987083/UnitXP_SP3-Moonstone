import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = SourceProbeModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("测试地址") {
                    TextField("软件源 URL", text: $model.urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack {
                        Button("Legacy") { model.useLegacyPreset() }
                        Spacer()
                        Button("V2-qnq") { model.useV2Preset() }
                        Spacer()
                        Button("V2-yxy") { model.useV2AltPreset() }
                    }
                }

                Section("真实解密") {
                    Button("当前地址：解密 → JSON → App 数量") { Task { await model.run() } }
                        .disabled(model.isLoading)
                    Button("测试 Legacy appstore") { Task { await model.runLegacy() } }
                        .disabled(model.isLoading)
                    Button("测试 V2 qnq") { Task { await model.runV2Qnq() } }
                        .disabled(model.isLoading)
                    Button("测试 V2 yxy") { Task { await model.runV2Yxy() } }
                        .disabled(model.isLoading)
                }

                if model.isLoading {
                    Section { HStack { Spacer(); ProgressView("解密中…"); Spacer() } }
                }

                Section("结果") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(model.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 420)

                    Button("复制结果") { UIPasteboard.general.string = model.output }
                    if let url = model.exportReportURL { ShareLink(item: url) { Label("分享报告", systemImage: "square.and.arrow.up") } }
                    if let url = model.exportPayloadURL { ShareLink(item: url) { Label("分享 payload-decoded.bin", systemImage: "doc") } }
                    if let url = model.exportSegment1URL { ShareLink(item: url) { Label("分享 V2 segment1.bin", systemImage: "1.square") } }
                    if let url = model.exportSegment2URL { ShareLink(item: url) { Label("分享 V2 segment2.bin", systemImage: "2.square") } }
                    if let url = model.exportPlainURL { ShareLink(item: url) { Label("分享 decrypted-plain.json", systemImage: "checkmark.seal") } }
                }

                Section("v0.5 验收") {
                    Text("只有真正解析出 Repo JSON 并取得 apps 数量才显示成功。Legacy 会执行原版 DES 路径候选；V2 会解析真实分段 envelope 并执行 RC4-family 候选。失败时明确显示停在哪一层。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QNQ Source Lab v0.5")
        }
    }
}
