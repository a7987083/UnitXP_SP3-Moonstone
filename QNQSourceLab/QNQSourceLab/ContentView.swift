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
                        Button("Legacy appstore") {
                            model.useLegacyPreset()
                        }
                        Spacer()
                        Button("appstore_v2") {
                            model.useV2Preset()
                        }
                    }
                }

                Section("可选动态密钥") {
                    SecureField("bkey（有就填，没有留空）", text: $model.bkey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await model.run() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(model.isLoading ? "正在探测…" : "获取并探测")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(model.isLoading)
                }

                Section("结果") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(model.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 320)

                    Button("复制结果") {
                        UIPasteboard.general.string = model.output
                    }
                }

                Section("用途") {
                    Text("只用于 appstore / appstore_v2 协议探测：外层 JSON、Base64、字节长度、头部特征、RC4 source_share、可选 bkey。它不包含 zonoe、Ksign 或签名功能。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QNQ Source Lab")
        }
    }
}
