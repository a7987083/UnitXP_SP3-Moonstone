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
            try validateIdentity(config, appInfo: info)
            log.append("[IDENTITY-OK] BundleID/Version/Build")

            let executableURL = appURL.appendingPathComponent(info.executableName)
            guard fileManager.fileExists(atPath: executableURL.path) else {
                throw IPAProcessorError.failed("找不到主程序：\(info.executableName)")
            }

            var targetFiles: [String: URL] = [:]
            var targetSlices: [String: MachOSliceInfo] = [:]
            for (targetID, target) in config.targets.sorted(by: { $0.key < $1.key }) {
                let targetURL = try resolveTarget(target, appURL: appURL, executableURL: executableURL)
                let slices = try MachOInspector.inspect(targetURL)
                let expectedUUID = Self.normalizeUUID(target.uuid)
                guard let slice = slices.first(where: {
                    $0.uuid == expectedUUID && config.package.architectures.contains($0.architecture)
                }) else {
                    let found = slices.map { "\($0.architecture):\($0.uuid)" }.joined(separator: ", ")
                    throw IPAProcessorError.failed("模块 \(target.image) UUID/架构不匹配；实际：\(found)")
                }
                guard !slice.encrypted else {
                    throw IPAProcessorError.failed("模块 \(target.image) 仍处于加密状态")
                }
                targetFiles[targetID] = targetURL
                targetSlices[targetID] = slice
                log.append("[TARGET-OK] id=\(targetID) image=\(target.image) arch=\(slice.architecture) uuid=\(slice.uuid)")
            }

            var patchCount = 0
            for feature in config.features {
                for patch in feature.patches {
                    guard let targetURL = targetFiles[patch.target],
                          let slice = targetSlices[patch.target] else {
                        throw IPAProcessorError.failed("内部错误：Patch目标未解析")
                    }
                    let original = try HFAPatchPackage.bytes(fromHex: patch.original)
                    guard let fileOffset = slice.fileOffset(forRVA: patch.offset.value,
                                                            length: UInt64(original.count)) else {
                        throw IPAProcessorError.failed("\(feature.title) RVA 0x\(String(patch.offset.value, radix: 16).uppercased()) 无法转换为文件偏移")
                    }
                    let actual = try MachOInspector.bytes(at: fileOffset, count: original.count, in: targetURL)
                    guard actual == original else {
                        throw IPAProcessorError.failed("\(feature.title) 原始字节不匹配：\(patch.target)+0x\(String(patch.offset.value, radix: 16).uppercased()) 期望 \(Self.hex(original))，实际 \(Self.hex(actual))")
                    }
                    patchCount += 1
                    log.append("[PATCH-OK] feature=\(feature.id) target=\(patch.target) rva=0x\(String(patch.offset.value, radix: 16).uppercased()) original=\(Self.hex(original))")
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
                                     validationLines: log)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    func build(_ workspace: PreparedWorkspace) throws -> BuildResult {
        var log = workspace.validationLines
        guard let menuURL = Bundle.main.url(forResource: "HFAPatchMenu_v0.1.0", withExtension: "dylib") else {
            throw IPAProcessorError.failed("工具内缺少 HFAPatchMenu_v0.1.0.dylib")
        }

        let frameworks = workspace.appURL.appendingPathComponent("Frameworks", isDirectory: true)
        try fileManager.createDirectory(at: frameworks, withIntermediateDirectories: true)
        let destinationMenu = frameworks.appendingPathComponent("HFAPatchMenu.dylib")
        if fileManager.fileExists(atPath: destinationMenu.path) {
            try fileManager.removeItem(at: destinationMenu)
        }
        try fileManager.copyItem(at: menuURL, to: destinationMenu)
        log.append("[MENU-COPY] Frameworks/HFAPatchMenu.dylib")

        let configDirectory = workspace.appURL.appendingPathComponent("HFAPatch", isDirectory: true)
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let destinationConfig = configDirectory.appendingPathComponent("default.hfapatch.json")
        try workspace.configData.write(to: destinationConfig, options: .atomic)
        log.append("[CONFIG-COPY] HFAPatch/default.hfapatch.json")

        let executable = workspace.appURL.appendingPathComponent(workspace.appInfo.executableName)
        let loadPath = "@executable_path/Frameworks/HFAPatchMenu.dylib"
        let existing = Zsign.listDylibs(appExecutable: executable.path)
        if !existing.contains(loadPath) {
            guard Zsign.injectDyLib(appExecutable: executable.path, with: loadPath, weak: false) else {
                throw IPAProcessorError.failed("LC_LOAD_DYLIB 注入失败，可能是 Load Commands 空间不足")
            }
            log.append("[INJECT-OK] \(loadPath)")
        } else {
            log.append("[INJECT-SKIP] 菜单已存在")
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
        let filename = "\(safeName)_HFAPatchIPA_v1.0.0_\(Self.safeFilename(workspace.appInfo.shortVersion)).ipa"
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

    private func validateIdentity(_ config: HFAPatchPackage, appInfo: GameAppInfo) throws {
        guard config.package.bundleIdentifier == appInfo.bundleIdentifier else {
            throw IPAProcessorError.failed("BundleID 不匹配：配置 \(config.package.bundleIdentifier)，IPA \(appInfo.bundleIdentifier)")
        }
        guard config.package.shortVersion == appInfo.shortVersion,
              config.package.buildVersion == appInfo.buildVersion else {
            throw IPAProcessorError.failed("游戏版本不匹配：配置 \(config.package.shortVersion)(\(config.package.buildVersion))，IPA \(appInfo.shortVersion)(\(appInfo.buildVersion))")
        }
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

    private static func normalizeUUID(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "").uppercased()
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return value.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "_")
    }
}
