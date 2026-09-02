import Foundation

struct HFAPatchPackage: Codable {
    let schema: String
    let name: String
    let package: PackageIdentity
    let targets: [String: PatchTarget]
    let features: [PatchFeature]

    struct PackageIdentity: Codable {
        let bundleIdentifier: String
        let shortVersion: String
        let buildVersion: String
        let architectures: [String]
    }

    struct PatchTarget: Codable {
        let image: String
        let uuid: String?
    }

    struct PatchFeature: Codable, Identifiable {
        let id: String
        let title: String
        let group: String
        let defaultEnabled: Bool?
        let patches: [PatchOperation]
    }

    struct PatchOperation: Codable {
        let target: String
        let offset: PatchOffset
        let original: String
        let enabled: String
    }

    struct PatchOffset: Codable {
        let value: UInt64

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let integer = try? container.decode(UInt64.self) {
                value = integer
                return
            }
            let string = try container.decode(String.self)
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed: UInt64?
            if trimmed.lowercased().hasPrefix("0x") {
                parsed = UInt64(trimmed.dropFirst(2), radix: 16)
            } else {
                parsed = UInt64(trimmed, radix: 10)
            }
            guard let parsed else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Patch offset")
            }
            value = parsed
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(String(format: "0x%llX", value))
        }
    }
}

enum HFAPatchPackageError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

extension HFAPatchPackage {
    static func load(from data: Data) throws -> HFAPatchPackage {
        let value = try JSONDecoder().decode(HFAPatchPackage.self, from: data)
        try value.validate()
        return value
    }

    func validate() throws {
        guard schema == "com.hfa.patch/v1" else {
            throw HFAPatchPackageError.invalid("不支持的配置格式：\(schema)")
        }
        guard !name.isEmpty,
              !package.bundleIdentifier.isEmpty,
              !package.shortVersion.isEmpty,
              !package.buildVersion.isEmpty else {
            throw HFAPatchPackageError.invalid("游戏身份字段不完整")
        }
        guard !package.architectures.isEmpty,
              package.architectures.allSatisfy({ $0 == "arm64" || $0 == "arm64e" }) else {
            throw HFAPatchPackageError.invalid("第一版仅支持 arm64/arm64e")
        }
        guard !targets.isEmpty, !features.isEmpty else {
            throw HFAPatchPackageError.invalid("配置没有目标模块或功能")
        }

        for (targetID, target) in targets {
            guard !targetID.isEmpty, !target.image.isEmpty else {
                throw HFAPatchPackageError.invalid("目标模块名称为空")
            }
        }

        var featureIDs = Set<String>()
        var ranges: [String: [(Range<UInt64>, String)]] = [:]
        for feature in features {
            guard !feature.id.isEmpty, !feature.title.isEmpty, !feature.group.isEmpty else {
                throw HFAPatchPackageError.invalid("存在名称不完整的功能")
            }
            guard featureIDs.insert(feature.id).inserted else {
                throw HFAPatchPackageError.invalid("功能 ID 重复：\(feature.id)")
            }
            guard !feature.patches.isEmpty else {
                throw HFAPatchPackageError.invalid("功能 \(feature.title) 没有 Patch")
            }
            for patch in feature.patches {
                guard targets[patch.target] != nil else {
                    throw HFAPatchPackageError.invalid("功能 \(feature.title) 引用了未知模块 \(patch.target)")
                }
                let original = try Self.bytes(fromHex: patch.original)
                let enabled = try Self.bytes(fromHex: patch.enabled)
                guard original.count == enabled.count else {
                    throw HFAPatchPackageError.invalid("功能 \(feature.title) 的原始字节与Patch长度不同")
                }
                let end = patch.offset.value.addingReportingOverflow(UInt64(original.count))
                guard !end.overflow else {
                    throw HFAPatchPackageError.invalid("功能 \(feature.title) 的地址溢出")
                }
                let candidate = patch.offset.value..<end.partialValue
                for (existing, owner) in ranges[patch.target, default: []] where existing.overlaps(candidate) {
                    throw HFAPatchPackageError.invalid("功能 \(feature.title) 与 \(owner) 的地址重叠")
                }
                ranges[patch.target, default: []].append((candidate, feature.title))
            }
        }
    }

    static func bytes(fromHex input: String) throws -> Data {
        var text = input.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        if text.lowercased().hasPrefix("0x") { text.removeFirst(2) }
        guard !text.isEmpty, text.count.isMultiple(of: 2) else {
            throw HFAPatchPackageError.invalid("十六进制字节长度无效")
        }
        var result = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else {
                throw HFAPatchPackageError.invalid("包含无效十六进制字符")
            }
            result.append(byte)
            index = next
        }
        return result
    }
}
