import Foundation

struct HFAPatchPackage: Decodable {
    struct PackageIdentity: Decodable {
        let bundleIdentifier: String
        let shortVersion: String
        let buildVersion: String
        let architectures: [String]
    }

    struct Target: Decodable {
        let image: String
    }

    struct Patch: Decodable {
        let target: String
        let offset: String
        let original: String
        let enabled: String
    }

    struct HookLocation: Decodable, Hashable {
        let target: String
        let offset: String
    }

    struct NativeHook: Decodable {
        let target: HookLocation
        let replacement: HookLocation
        let originalSlot: HookLocation
        let original: HookLocation
    }

    struct Feature: Decodable {
        let id: String
        let title: String
        let group: String?
        let defaultEnabled: Bool?
        let patches: [Patch]
        let type: String?
        let implementation: String?
        let hook: NativeHook?
    }

    let schema: String
    let name: String
    let package: PackageIdentity
    let targets: [String: Target]
    let features: [Feature]
}

enum HFAPatchReplayKind: Equatable, CustomStringConvertible {
    case patchList
    case nativeHookSourceDependent(requiredImages: Set<String>)
    case unsupported(reason: String)

    var description: String {
        switch self {
        case .patchList:
            return "patchList"
        case .nativeHookSourceDependent(let requiredImages):
            return "nativeHook/sourceDependent(" + requiredImages.sorted().joined(separator: ",") + ")"
        case .unsupported(let reason):
            return "unsupported(\(reason))"
        }
    }
}

struct HFAPatchFeaturePlan {
    let feature: HFAPatchPackage.Feature
    let replayKind: HFAPatchReplayKind
}

struct HFAPatchConsumerPreflight {
    let package: HFAPatchPackage

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode(HFAPatchPackage.self, from: data)
        guard decoded.schema == "com.hfa.patch/v1" else {
            throw NSError(domain: "HFAPatchConsumer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported schema: \(decoded.schema)"])
        }
        self.package = decoded
    }

    func plan(for feature: HFAPatchPackage.Feature) -> HFAPatchFeaturePlan {
        if feature.implementation == "nativeHook" || feature.type == "customSwitch" {
            guard feature.implementation == "nativeHook",
                  feature.type == "customSwitch",
                  let hook = feature.hook else {
                return HFAPatchFeaturePlan(feature: feature,
                    replayKind: .unsupported(reason: "incomplete customSwitch/nativeHook schema"))
            }

            let locations = [hook.target, hook.replacement, hook.originalSlot, hook.original]
            for location in locations {
                guard package.targets[location.target] != nil else {
                    return HFAPatchFeaturePlan(feature: feature,
                        replayKind: .unsupported(reason: "unknown target id \(location.target)"))
                }
                guard Self.isHexOffset(location.offset) else {
                    return HFAPatchFeaturePlan(feature: feature,
                        replayKind: .unsupported(reason: "invalid hook offset \(location.offset)"))
                }
            }

            // The target address is sufficient to identify the hooked function, but
            // replacement/originalSlot/original are executable/data references inside
            // the source plugin image. RVAs alone do not carry the implementation,
            // relocations, globals, ObjC dependencies, or writable original-function slot.
            // A clean target app therefore cannot replay this hook from JSON alone.
            let targetImage = package.targets[hook.target.target]!.image
            let implementationImages: Set<String> = [
                package.targets[hook.replacement.target]!.image,
                package.targets[hook.originalSlot.target]!.image,
                package.targets[hook.original.target]!.image
            ]
            let sourceImages = implementationImages.subtracting([targetImage])
            return HFAPatchFeaturePlan(feature: feature,
                replayKind: .nativeHookSourceDependent(requiredImages: sourceImages))
        }

        guard !feature.patches.isEmpty else {
            return HFAPatchFeaturePlan(feature: feature,
                replayKind: .unsupported(reason: "feature has no patches"))
        }
        for patch in feature.patches {
            guard package.targets[patch.target] != nil else {
                return HFAPatchFeaturePlan(feature: feature,
                    replayKind: .unsupported(reason: "unknown patch target \(patch.target)"))
            }
            guard Self.isHexOffset(patch.offset),
                  Self.isEvenHex(patch.original), Self.isEvenHex(patch.enabled),
                  patch.original.count == patch.enabled.count else {
                return HFAPatchFeaturePlan(feature: feature,
                    replayKind: .unsupported(reason: "invalid patch bytes/offset"))
            }
        }
        return HFAPatchFeaturePlan(feature: feature, replayKind: .patchList)
    }

    func plans() -> [HFAPatchFeaturePlan] {
        package.features.map(plan(for:))
    }

    static func isHexOffset(_ text: String) -> Bool {
        guard text.hasPrefix("0x"), text.count > 2 else { return false }
        return text.dropFirst(2).allSatisfy { $0.isHexDigit }
    }

    static func isEvenHex(_ text: String) -> Bool {
        !text.isEmpty && text.count % 2 == 0 && text.allSatisfy { $0.isHexDigit }
    }
}
