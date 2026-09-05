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

                Section("可选动态密钥") {
                    SecureField("bkey（有就填，没有留空）", text: $model.bkey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("单次探测") {
                    Button("获取并深度探测") { Task { await model.run() } }
                        .disabled(model.isLoading)
                    Button("当前地址同源双抓") { Task { await model.runRepeatCompare() } }
                        .disabled(model.isLoading)
                }

                Section("自动对比") {
                    Button("Legacy 同源双抓") { Task { await model.runLegacyRepeat() } }
                        .disabled(model.isLoading)
                    Button("V2 qnq 同源双抓") { Task { await model.runV2QnqRepeat() } }
                        .disabled(model.isLoading)
                    Button("V2 yxy 同源双抓") { Task { await model.runV2YxyRepeat() } }
                        .disabled(model.isLoading)
                    Button("V2 两源对比（qnq / yxy）") { Task { await model.runV2Compare() } }
                        .disabled(model.isLoading)
                }

                if model.isLoading {
                    Section { HStack { Spacer(); ProgressView("分析中…"); Spacer() } }
                }

                Section("结果") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(model.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 480)

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

                Section("v0.3 重点") {
                    Text("验证 V2 同源是否只有固定 8 字节头、统计变化比例/变化区间、熵、重复分块和自相关；同时可直接导出 Base64 解码后的 A/B 原始二进制，方便离线定位 appstore/appstore_v2 协议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QNQ Source Lab v0.3")
        }
    }
}
