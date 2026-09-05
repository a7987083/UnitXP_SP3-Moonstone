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

                Section("探测") {
                    Button {
                        Task { await model.run() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isLoading { ProgressView().padding(.trailing, 8) }
                            Text(model.isLoading ? "正在探测…" : "获取并深度探测")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(model.isLoading)

                    Button("同源双抓对比") {
                        Task { await model.runRepeatCompare() }
                    }
                    .disabled(model.isLoading)

                    Button("V2 两源自动对比（qnq / yxy）") {
                        Task { await model.runV2Compare() }
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
                    .frame(minHeight: 420)

                    Button("复制结果") {
                        UIPasteboard.general.string = model.output
                    }
                }

                Section("用途") {
                    Text("v0.2 专门验证 appstore / appstore_v2 容器结构：头部整数、候选偏移、熵、文件签名、同源随机性和两源公共前缀。仍不包含 zonoe/Ksign 业务逻辑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QNQ Source Lab v0.2")
        }
    }
}
