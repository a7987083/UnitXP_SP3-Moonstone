import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = SourceProbeModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("软件源") {
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
                    Button("检查当前软件源 envelope") { Task { await model.runSourceInspect() } }
                        .disabled(model.isLoading)
                }

                Section("Nuosike 已知明文 Oracle") {
                    TextEditor(text: $model.oracleText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 76)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("V2 encrypt.php：自定义明文双抓") { Task { await model.runCustomV2Oracle() } }
                        .disabled(model.isLoading)
                    Button("V1 api.php：自定义明文双抓") { Task { await model.runCustomV1Oracle() } }
                        .disabled(model.isLoading)
                }

                Section("自动矩阵") {
                    Button("V2 已知明文矩阵（7×2）") { Task { await model.runV2Matrix() } }
                        .disabled(model.isLoading)
                    Button("V1 已知明文矩阵（7×2）") { Task { await model.runV1Matrix() } }
                        .disabled(model.isLoading)
                    Text("矩阵使用空串、A、AA、AAAA、{}、{\"a\":1}、{\"a\":\"AAAA\"}。每个样本只请求两次，并按后台源码的 content=Base64(plaintext) 表单格式提交。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if model.isLoading {
                    Section { HStack { Spacer(); ProgressView("测试中…"); Spacer() } }
                }

                Section("结果") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(model.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 500)

                    Button("复制结果") { UIPasteboard.general.string = model.output }
                    if let url = model.exportReportURL {
                        ShareLink(item: url) { Label("分享报告", systemImage: "square.and.arrow.up") }
                    }
                    if let url = model.exportAURL {
                        ShareLink(item: url) { Label("分享 A decoded.bin", systemImage: "doc") }
                    }
                    if let url = model.exportBURL {
                        ShareLink(item: url) { Label("分享 B decoded.bin", systemImage: "doc.on.doc") }
                    }
                }

                Section("v0.6 重点") {
                    Text("不再把 offset 128 的 UInt32 当 Segment2 长度。V2 只确认 3e b7 f6 f4 + LE32(120) + 120-byte 动态块，并用官方 encrypt.php 的已知明文输出验证尾部长度、固定开销和随机化范围；V1 同样用 api.php 反推 DES 前处理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QNQ Source Lab v0.6")
        }
    }
}
