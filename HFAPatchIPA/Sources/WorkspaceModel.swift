import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkspaceModel: ObservableObject {
    enum ImportKind: Equatable { case ipa, config }

    @Published var ipaURL: URL?
    @Published var configURL: URL?
    @Published var prepared: PreparedWorkspace?
    @Published var output: BuildResult?
    @Published var isBusy = false
    @Published var status = "请选择已解密 IPA 和游戏数据包"
    @Published var errorMessage: String?
    @Published var logLines: [String] = []

    private let processor = IPAProcessor()

    var canValidate: Bool { ipaURL != nil && configURL != nil && !isBusy }
    var canBuild: Bool { prepared != nil && !isBusy }

    func acceptImportedURL(_ source: URL, kind: ImportKind) {
        isBusy = true
        errorMessage = nil
        status = "正在导入 \(source.lastPathComponent)…"
        Task {
            do {
                let local = try await Self.copyIntoImports(source, kind: kind)
                switch kind {
                case .ipa: ipaURL = local
                case .config: configURL = local
                }
                prepared = nil
                output = nil
                logLines = []
                status = ipaURL != nil && configURL != nil ? "文件已就绪，请开始校验" : "请继续选择文件"
            } catch {
                errorMessage = error.localizedDescription
                status = "导入失败"
            }
            isBusy = false
        }
    }

    func validate() {
        guard let ipaURL, let configURL else { return }
        isBusy = true
        errorMessage = nil
        prepared = nil
        output = nil
        logLines = []
        status = "正在解包并校验 IPA…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try IPAProcessor().prepare(ipaURL: ipaURL, configURL: configURL)
                }.value
                prepared = result
                logLines = result.validationLines
                status = "校验通过：\(result.appInfo.name) \(result.appInfo.shortVersion)"
            } catch {
                errorMessage = error.localizedDescription
                status = "校验失败"
            }
            isBusy = false
        }
    }

    func build() {
        guard let prepared else { return }
        isBusy = true
        errorMessage = nil
        output = nil
        status = "正在注入菜单并生成 IPA…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try IPAProcessor().build(prepared)
                }.value
                output = result
                logLines = result.log
                status = "生成完成：\(result.ipaURL.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
                status = "生成失败"
            }
            isBusy = false
        }
    }

    func reset() {
        prepared = nil
        output = nil
        logLines = []
        errorMessage = nil
        status = ipaURL != nil && configURL != nil ? "文件已就绪，请开始校验" : "请选择已解密 IPA 和游戏数据包"
    }

    private static func copyIntoImports(_ source: URL, kind: ImportKind) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = documents.appendingPathComponent("HFAPatchIPA/Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = kind == .ipa ? "ipa" : "json"
            let base = source.deletingPathExtension().lastPathComponent
            let destination = directory.appendingPathComponent("\(base).\(ext)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }.value
    }
}

extension UTType {
    static let hfaIPA = UTType(filenameExtension: "ipa") ?? .archive
    static let hfaPatchJSON = UTType(filenameExtension: "json") ?? .json
}
