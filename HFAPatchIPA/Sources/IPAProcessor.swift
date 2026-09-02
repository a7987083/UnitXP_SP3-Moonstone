import Foundation
import Zip
import Zsign

struct GameAppInfo {
    let name: String
    let bundleIdentifier: String
    let shortVersion: String
    let buildVersion: String
    let executableName: String
}

enum PatchBuildMode: String, CaseIterable, Identifiable {
    case menu = "菜单灵活开启"
    case fixed = "写死 Patch"
    var id: String { rawValue }
}

enum PatchByteStatus: String {
    case original = "Original 匹配"
    case enabled = "已经写入 Enabled"
    case different = "实际字节不同"
    case unavailable = "无法定位，已跳过"
}

struct PatchComparison: Identifiable {
    let id = UUID()
    let featureID: String
    let title: String
    let target: String
    let rva: UInt64
    let fileOffset: UInt64?
    let jsonOriginal: Data
    let actual: Data?
    let enabled: Data
    let status: PatchByteStatus
}

final class PreparedWorkspace {
    let rootURL: URL
    let payloadURL: URL
    let appURL: URL
    let sourceIPAURL: URL
    let configURL: URL
    let configData: Data
    let config: HFAPatchPackage
    let appInfo: GameAppInfo
    let targetFiles: [String: URL]
    let targetSlices: [String: MachOSliceInfo]
    let comparisons: [PatchComparison]
    let validationLines: [String]

    init(rootURL: URL,
         payloadURL: URL,
         appURL: URL,
         sourceIPAURL: URL,
         configURL: URL,
         configData: Data,
         config: HFAPatchPackage,
         appInfo: GameAppInfo,
         targetFiles: [String: URL],
         targetSlices: [String: MachOSliceInfo],
         comparisons: [PatchComparison],
         validationLines: [String]) {
        self.rootURL = rootURL
        self.payloadURL = payloadURL
        self.appURL = appURL
        self.sourceIPAURL = sourceIPAURL
        self.configURL = configURL
        self.configData = configData
        self.config = config
        self.appInfo = appInfo
        self.targetFiles = targetFiles
        self.targetSlices = targetSlices
        self.comparisons = comparisons
        self.validationLines = validationLines
    }

    deinit { try? FileManager.default.removeItem(at: rootURL) }
}

struct BuildResult {
    let ipaURL: URL
    let logURL: URL
    let log: [String]
}

enum IPAProcessorError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

final class IPAProcessor {
    private let fileManager = FileManager.default

    func prepare(ipaURL: URL, configURL: URL) throws -> PreparedWorkspace {
        var log: [String] = []
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("HFAPatchIPA_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        do {
            let localIPA = root.appendingPathComponent("Input.ipa")
            try fileManager.copyItem(at: ipaURL, to: localIPA)
            log.append("[INPUT] \(ipaURL.lastPathComponent)")

            Zip.addCustomFileExtension("ipa")
            try Zip.unzipFile(localIPA, destination: root, overwrite: true, password: nil)
            let payload = root.appendingPathComponent("Payload", isDirectory: true)
            let appCandidates = try fileManager.contentsOfDirectory(at: payload,
                                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "app" }
            guard appCandidates.count == 1, let appURL = appCandidates.first else {
                throw IPAProcessorError.failed("Payload 中必须且只能有一个 .app")
            }

            let info = try readAppInfo(appURL)
            log.append("[APP] \(info.name) bundle=\(info.bundleIdentifier) version=\(info.shortVersion)(\(info.buildVersion))")

            let configData = try Data(contentsOf: configURL)
            let config = try HFAPatchPackage.load(from: configData)
            log.append(contentsOf: identityWarnings(config, appInfo: info))

            let executableURL = appURL.appendingPathComponent(info.executableName)
            guard fileManager.fileExists(atPath: executableURL.path) else {
                throw IPAProcessorError.failed("找不到主程序：\(info.executableName)")
            }

            var targetFiles: [String: URL] = [:]
            var targetSlices: [String: MachOSliceInfo] = [:]
            for (targetID, target) in config.targets.sorted(by: { $0.key < $1.key }) {
                do {
                    let targetURL = try resolveTarget(target, appURL: appURL, executableURL: executableURL)
                    let slices = try MachOInspector.inspect(targetURL)
                    guard let slice = slices.first else {
                        log.append("[WARNING] 模块 \(target.image) 没有可处理的 arm64 Slice")
                        continue
                    }
                    if !config.package.architectures.contains(slice.architecture) {
                        log.append("[WARNING] 模块 \(target.image) 架构 \(slice.architecture) 不在 JSON 声明中，仍继续")
                    }
                    if slice.encrypted {
                        log.append("[WARNING] 模块 \(target.image) 仍显示加密；相关 Patch 将尝试读取")
                    }
                    targetFiles[targetID] = targetURL
                    targetSlices[targetID] = slice
                    log.append("[TARGET] id=\(targetID) image=\(target.image) arch=\(slice.architecture)")
                } catch {
                    log.append("[WARNING] \(error.localizedDescription)")
                }
            }

            var patchCount = 0
            var comparisons: [PatchComparison] = []
            for feature in config.features {
                for patch in feature.patches {
                    let original = try HFAPatchPackage.bytes(fromHex: patch.original)
                    let enabled = try HFAPatchPackage.bytes(fromHex: patch.enabled)
                    guard let targetURL = targetFiles[patch.target],
                          let slice = targetSlices[patch.target],
                          let fileOffset = slice.fileOffset(forRVA: patch.offset.value,
                                                           length: UInt64(original.count)),
                          let actual = try? MachOInspector.bytes(at: fileOffset, count: original.count, in: targetURL) else {
                        comparisons.append(PatchComparison(featureID: feature.id, title: feature.title,
                                                           target: patch.target, rva: patch.offset.value,
                                                           fileOffset: nil, jsonOriginal: original,
                                                           actual: nil, enabled: enabled, status: .unavailable))
                        log.append("[WARNING] feature=\(feature.id) target=\(patch.target) rva=0x\(String(patch.offset.value, radix: 16).uppercased()) 无法定位，已跳过")
                        continue
                    }
                    let status: PatchByteStatus = actual == original ? .original :
                        (actual == enabled ? .enabled : .different)
                    comparisons.append(PatchComparison(featureID: feature.id,
                                                       title: feature.title,
                                                       target: patch.target,
                                                       rva: patch.offset.value,
                                                       fileOffset: fileOffset,
                                                       jsonOriginal: original,
                                                       actual: actual,
                                                       enabled: enabled,
                                                       status: status))
                    patchCount += 1
                    log.append("[PATCH-CHECK] feature=\(feature.id) target=\(patch.target) rva=0x\(String(patch.offset.value, radix: 16).uppercased()) jsonOriginal=\(Self.hex(original)) actual=\(Self.hex(actual)) enabled=\(Self.hex(enabled)) status=\(status.rawValue)")
                }
            }
            log.append("[VALIDATION-OK] features=\(config.features.count) patches=\(patchCount)")

            return PreparedWorkspace(rootURL: root,
                                     payloadURL: payload,
                                     appURL: appURL,
                                     sourceIPAURL: ipaURL,
                                     configURL: configURL,
                                     configData: configData,
                                     config: config,
                                     appInfo: info,
                                     targetFiles: targetFiles,
                                     targetSlices: targetSlices,
                                     comparisons: comparisons,
                                     validationLines: log)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    func build(_ workspace: PreparedWorkspace, mode: PatchBuildMode, customMenuURL: URL?) throws -> BuildResult {
        var log = workspace.validationLines
        if mode == .fixed {
            for comparison in workspace.comparisons {
                guard let targetURL = workspace.targetFiles[comparison.target],
                      let fileOffset = comparison.fileOffset,
                      let actual = comparison.actual else { continue }
                try Self.write(comparison.enabled, at: fileOffset, to: targetURL)
                log.append("[FIXED-PATCH] feature=\(comparison.featureID) target=\(comparison.target) rva=0x\(String(comparison.rva, radix: 16).uppercased()) before=\(Self.hex(actual)) after=\(Self.hex(comparison.enabled))")
            }
        } else {
            guard let menuURL = customMenuURL else {
                throw IPAProcessorError.failed("请选择你自己的菜单 dylib")
            }
            let frameworks = workspace.appURL.appendingPathComponent("Frameworks", isDirectory: true)
            try fileManager.createDirectory(at: frameworks, withIntermediateDirectories: true)
            let menuName = menuURL.lastPathComponent
            let destinationMenu = frameworks.appendingPathComponent(menuName)
            try? fileManager.removeItem(at: destinationMenu)
            try fileManager.copyItem(at: menuURL, to: destinationMenu)
            log.append("[MENU-COPY] Frameworks/\(menuName)")

            let configDirectory = workspace.appURL.appendingPathComponent("HFAPatch", isDirectory: true)
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            let destinationConfig = configDirectory.appendingPathComponent("default.hfapatch.json")
            let adapted = try Self.adaptedConfig(workspace.configData, comparisons: workspace.comparisons)
            try adapted.write(to: destinationConfig, options: .atomic)
            log.append("[CONFIG-COPY] actual bytes saved as Original; UUID removed")

            let executable = workspace.appURL.appendingPathComponent(workspace.appInfo.executableName)
            let loadPath = "@executable_path/Frameworks/\(menuName)"
            let existing = Zsign.listDylibs(appExecutable: executable.path)
            if !existing.contains(loadPath) {
                guard Zsign.injectDyLib(appExecutable: executable.path, with: loadPath, weak: false) else {
                    throw IPAProcessorError.failed("LC_LOAD_DYLIB 注入失败，可能是 Load Commands 空间不足")
                }
                log.append("[INJECT-OK] \(loadPath)")
            } else {
                log.append("[INJECT-SKIP] 菜单已存在")
            }
        }

        guard Zsign.sign(appPath: workspace.appURL.path,
                         entitlementsPath: "",
                         adhoc: true,
                         removeProvision: true) else {
            throw IPAProcessorError.failed("Ad-hoc/Fake Sign 失败")
        }
        log.append("[SIGN-OK] mode=adhoc")

        let exportDirectory = try Self.exportDirectory()
        let safeName = Self.safeFilename(workspace.appInfo.name)
        let modeName = mode == .fixed ? "Fixed" : "Menu"
        let filename = "\(safeName)_HFAPatchIPA_v2.2.1_\(modeName)_\(Self.safeFilename(workspace.appInfo.shortVersion)).ipa"
        let output = exportDirectory.appendingPathComponent(filename)
        let temporaryZip = workspace.rootURL.appendingPathComponent("Output.zip")
        try? fileManager.removeItem(at: temporaryZip)
        try? fileManager.removeItem(at: output)
        try Zip.zipFiles(paths: [workspace.payloadURL],
                         zipFilePath: temporaryZip,
                         password: nil,
                         compression: .DefaultCompression,
                         progress: nil)
        try fileManager.moveItem(at: temporaryZip, to: output)
        log.append("[OUTPUT] \(output.lastPathComponent)")

        let logURL = exportDirectory.appendingPathComponent(filename + ".log")
        try (log.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        return BuildResult(ipaURL: output, logURL: logURL, log: log)
    }

    private func readAppInfo(_ appURL: URL) throws -> GameAppInfo {
        let plistURL = appURL.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              let executable = plist["CFBundleExecutable"] as? String,
              let shortVersion = plist["CFBundleShortVersionString"] as? String,
              let buildVersion = plist["CFBundleVersion"] as? String else {
            throw IPAProcessorError.failed("Info.plist 缺少 BundleID、版本、Build或主程序字段")
        }
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return GameAppInfo(name: name,
                           bundleIdentifier: bundleID,
                           shortVersion: shortVersion,
                           buildVersion: buildVersion,
                           executableName: executable)
    }

    private func identityWarnings(_ config: HFAPatchPackage, appInfo: GameAppInfo) -> [String] {
        var lines: [String] = []
        if config.package.bundleIdentifier != appInfo.bundleIdentifier {
            lines.append("[WARNING] BundleID 不同：JSON=\(config.package.bundleIdentifier) IPA=\(appInfo.bundleIdentifier)")
        }
        if config.package.shortVersion != appInfo.shortVersion {
            lines.append("[WARNING] Version 不同：JSON=\(config.package.shortVersion) IPA=\(appInfo.shortVersion)")
        }
        if config.package.buildVersion != appInfo.buildVersion {
            lines.append("[WARNING] Build 不同：JSON=\(config.package.buildVersion) IPA=\(appInfo.buildVersion)")
        }
        if lines.isEmpty { lines.append("[IDENTITY] BundleID/Version/Build 一致") }
        return lines
    }

    private func resolveTarget(_ target: HFAPatchPackage.PatchTarget,
                               appURL: URL,
                               executableURL: URL) throws -> URL {
        if target.image == "@main" { return executableURL }
        let enumerator = fileManager.enumerator(at: appURL,
                                                includingPropertiesForKeys: [.isRegularFileKey],
                                                options: [.skipsHiddenFiles])
        var matches: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            if file.lastPathComponent == target.image { matches.append(file) }
        }
        guard matches.count == 1, let match = matches.first else {
            if matches.isEmpty { throw IPAProcessorError.failed("找不到目标模块：\(target.image)") }
            throw IPAProcessorError.failed("目标模块名称不唯一：\(target.image)")
        }
        return match
    }

    private static func exportDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("HFAPatchIPA/Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ data: Data, at offset: UInt64, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }

    private static func adaptedConfig(_ source: Data, comparisons: [PatchComparison]) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: source) as? [String: Any],
              var targets = root["targets"] as? [String: [String: Any]],
              var features = root["features"] as? [[String: Any]] else {
            throw IPAProcessorError.failed("无法更新游戏数据包")
        }
        for key in Array(targets.keys) {
            var target = targets[key] ?? [:]
            target.removeValue(forKey: "uuid")
            targets[key] = target
        }
        var index = 0
        for featureIndex in features.indices {
            guard var patches = features[featureIndex]["patches"] as? [[String: Any]] else { continue }
            for patchIndex in patches.indices where index < comparisons.count {
                let item = comparisons[index]
                let restoreBytes = item.status == .enabled ? item.jsonOriginal : (item.actual ?? item.jsonOriginal)
                patches[patchIndex]["original"] = hex(restoreBytes)
                index += 1
            }
            features[featureIndex]["patches"] = patches
        }
        root["targets"] = targets
        root["features"] = features
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return value.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "_")
    }
}
