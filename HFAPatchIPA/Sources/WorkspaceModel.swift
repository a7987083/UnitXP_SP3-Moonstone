import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ResourceKind: String, CaseIterable, Identifiable {
    case ipa = "App"
    case config = "数据包"
    case dylib = "动态库"
    case output = "已生成"
    var id: String { rawValue }
    var icon: String {
        switch self { case .ipa: return "app"; case .config: return "doc.text";
        case .dylib: return "shippingbox"; case .output: return "checkmark.seal" }
    }
}

struct LocalResource: Identifiable {
    let url: URL
    let kind: ResourceKind
    let size: Int64
    let modified: Date
    var id: String { url.path }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    enum ImportKind: Equatable { case ipa, config, dylib }

    @Published var ipaURL: URL?
    @Published var configURL: URL?
    @Published var dylibURL: URL?
    @Published var prepared: PreparedWorkspace?
    @Published var output: BuildResult?
    @Published var isBusy = false
    @Published var status = "请选择已解密 IPA 和游戏数据包"
    @Published var errorMessage: String?
    @Published var logLines: [String] = []
    @Published var buildMode: PatchBuildMode = .menu
    @Published var resources: [LocalResource] = []

    private let processor = IPAProcessor()

    init() { refreshResources() }

    var canValidate: Bool { ipaURL != nil && configURL != nil && !isBusy }
    var canBuild: Bool {
        prepared != nil && !isBusy && (buildMode == .fixed || dylibURL != nil)
    }

    func acceptImportedURL(_ source: URL, kind: ImportKind) {
        guard Self.isSupported(source, as: kind) else {
            errorMessage = "文件类型不匹配：\(source.lastPathComponent)"
            status = "请选择正确的 IPA、JSON 或 dylib 文件"
            return
        }
        isBusy = true
        errorMessage = nil
        status = "正在导入 \(source.lastPathComponent)…"
        Task {
            do {
                let local = try await Self.copyIntoImports(source, kind: kind)
                switch kind {
                case .ipa: ipaURL = local
                case .config: configURL = local
                case .dylib: dylibURL = local
                }
                prepared = nil
                output = nil
                logLines = []
                status = ipaURL != nil && configURL != nil ? "文件已就绪，请开始校验" : "请继续选择文件"
                refreshResources()
            } catch {
                errorMessage = error.localizedDescription
                status = "导入失败"
            }
            isBusy = false
        }
    }

    func acceptSharedURL(_ source: URL) {
        let name = source.lastPathComponent.lowercased()
        if name.hasSuffix(".ipa") {
            acceptImportedURL(source, kind: .ipa)
        } else if name.hasSuffix(".json") || name.hasSuffix(".hfapatch") {
            acceptImportedURL(source, kind: .config)
        } else if name.hasSuffix(".dylib") {
            acceptImportedURL(source, kind: .dylib)
        } else {
            errorMessage = "不支持的文件：\(source.lastPathComponent)"
            status = "导入失败"
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
        let mode = buildMode
        let menuURL = dylibURL
        isBusy = true
        errorMessage = nil
        output = nil
        status = mode == .menu ? "正在注入菜单并生成 IPA…" : "正在写入 Patch 并生成 IPA…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try IPAProcessor().build(prepared, mode: mode, customMenuURL: menuURL)
                }.value
                output = result
                logLines = result.log
                status = "生成完成：\(result.ipaURL.lastPathComponent)"
                refreshResources()
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

    func select(_ resource: LocalResource) {
        switch resource.kind {
        case .ipa: ipaURL = resource.url
        case .config: configURL = resource.url
        case .dylib: dylibURL = resource.url
        case .output: break
        }
        prepared = nil
        output = nil
        status = ipaURL != nil && configURL != nil ? "资源已选择，请进入制作" : "已选择 \(resource.url.lastPathComponent)"
    }

    func delete(_ resource: LocalResource) {
        try? FileManager.default.removeItem(at: resource.url)
        if ipaURL == resource.url { ipaURL = nil }
        if configURL == resource.url { configURL = nil }
        if dylibURL == resource.url { dylibURL = nil }
        refreshResources()
    }

    func refreshResources() {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sources: [(URL, ResourceKind?)] = [
            (documents.appendingPathComponent("HFAPatchIPA/Imports", isDirectory: true), nil),
            (documents.appendingPathComponent("HFAPatchIPA/Exports", isDirectory: true), .output)
        ]
        var found: [LocalResource] = []
        for (directory, forcedKind) in sources {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = (try? manager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                           options: [.skipsHiddenFiles])) ?? []
            for url in files where url.pathExtension.lowercased() != "log" {
                let kind: ResourceKind?
                if let forcedKind { kind = forcedKind }
                else {
                    switch url.pathExtension.lowercased() {
                    case "ipa": kind = .ipa
                    case "json", "hfapatch": kind = .config
                    case "dylib": kind = .dylib
                    default: kind = nil
                    }
                }
                guard let kind else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                found.append(LocalResource(url: url, kind: kind,
                                           size: Int64(values?.fileSize ?? 0),
                                           modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        resources = found.sorted { $0.modified > $1.modified }
    }

    private static func copyIntoImports(_ source: URL, kind: ImportKind) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = documents.appendingPathComponent("HFAPatchIPA/Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext: String
            switch kind {
            case .ipa: ext = "ipa"
            case .config: ext = "json"
            case .dylib: ext = "dylib"
            }
            let base = source.deletingPathExtension().lastPathComponent
            let destination = directory.appendingPathComponent("\(base).\(ext)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }.value
    }

    private static func isSupported(_ url: URL, as kind: ImportKind) -> Bool {
        let name = url.lastPathComponent.lowercased()
        switch kind {
        case .ipa:
            return name.hasSuffix(".ipa")
        case .config:
            return name.hasSuffix(".json") || name.hasSuffix(".hfapatch") || name.hasSuffix(".hfapatch.json")
        case .dylib:
            return name.hasSuffix(".dylib")
        }
    }
}

extension UTType {
    static let hfaIPA = UTType(importedAs: "com.apple.itunes.ipa", conformingTo: .zip)
    static let hfaPatchJSON = UTType(importedAs: "com.hfa.patch-package", conformingTo: .json)
}
