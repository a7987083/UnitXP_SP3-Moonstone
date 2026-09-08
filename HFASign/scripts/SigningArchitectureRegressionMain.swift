import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private final class RecordingGenerator: ZonoeUDIDCallbackSchemeGenerating {
    var calls: [(String, Date, String)] = []
    let output: String
    
    init(output: String) {
        self.output = output
    }
    
    func makeScheme(bundleIdentifier: String, date: Date, nonce: String) -> String {
        calls.append((bundleIdentifier, date, nonce))
        return output
    }
}

private func legacyMakeScheme(bundleID: String, date: Date, nonce: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+.-")
    let sanitized = bundleID.unicodeScalars
        .map { allowed.contains($0) ? String($0) : "-" }
        .joined()
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        .lowercased()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyyMMddHHmm"
    let cleanNonce = nonce.replacingOccurrences(of: "-", with: "").lowercased()
    let identifier = sanitized.isEmpty ? "unknown" : sanitized
    return "zonoe-\(identifier)-\(formatter.string(from: date))-\(cleanNonce)"
}

private func legacyApply(
    enabled: Bool,
    customBundleIdentifier: String?,
    date: Date,
    nonce: String,
    to infoDictionary: NSMutableDictionary
) {
    let marker = "zonoe.udid.callback"
    let previousScheme = infoDictionary["ZonoeUDIDCallbackScheme"] as? String
    var urlTypes = (infoDictionary["CFBundleURLTypes"] as? [[String: Any]]) ?? []
    
    urlTypes.removeAll { type in
        if (type["CFBundleURLName"] as? String) == marker { return true }
        guard let previousScheme else { return false }
        return (type["CFBundleURLSchemes"] as? [String])?.contains(previousScheme) == true
    }
    
    infoDictionary.removeObject(forKey: "ZonoeUDIDCallbackScheme")
    infoDictionary.removeObject(forKey: "ZonoeUDIDCallbackHost")
    
    guard enabled else {
        if urlTypes.isEmpty { infoDictionary.removeObject(forKey: "CFBundleURLTypes") }
        else { infoDictionary["CFBundleURLTypes"] = urlTypes }
        return
    }
    
    let customID = customBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
    let bundleID: String
    if let customID, !customID.isEmpty { bundleID = customID }
    else { bundleID = (infoDictionary["CFBundleIdentifier"] as? String) ?? "unknown" }
    
    let callbackScheme = legacyMakeScheme(bundleID: bundleID, date: date, nonce: nonce)
    urlTypes.append([
        "CFBundleURLName": marker,
        "CFBundleURLSchemes": [callbackScheme]
    ])
    infoDictionary["CFBundleURLTypes"] = urlTypes
    infoDictionary["ZonoeUDIDCallbackScheme"] = callbackScheme
    infoDictionary["ZonoeUDIDCallbackHost"] = "udid-callback"
}

private func applyRefactored(
    enabled: Bool,
    customBundleIdentifier: String?,
    date: Date,
    nonce: String,
    to infoDictionary: NSMutableDictionary
) {
    let request = ZonoeUDIDCallbackRequest(
        enabled: enabled,
        customBundleIdentifier: customBundleIdentifier,
        plistBundleIdentifier: infoDictionary["CFBundleIdentifier"] as? String
    )
    let useCase = ConfigureZonoeUDIDCallbackUseCase(
        generator: DefaultZonoeUDIDCallbackSchemeGenerator(),
        now: { date },
        nonce: { nonce }
    )
    ZonoeUDIDCallbackPlistAdapter().apply(useCase.execute(request), to: infoDictionary)
}

private func assertLegacyParity(
    enabled: Bool,
    customBundleIdentifier: String?,
    source: [AnyHashable: Any],
    date: Date,
    nonce: String,
    label: String
) {
    let legacy = NSMutableDictionary(dictionary: source)
    let refactored = NSMutableDictionary(dictionary: source)
    legacyApply(
        enabled: enabled,
        customBundleIdentifier: customBundleIdentifier,
        date: date,
        nonce: nonce,
        to: legacy
    )
    applyRefactored(
        enabled: enabled,
        customBundleIdentifier: customBundleIdentifier,
        date: date,
        nonce: nonce,
        to: refactored
    )
    expect(legacy.isEqual(refactored), "legacy parity failed: \(label)\nlegacy=\(legacy)\nrefactored=\(refactored)")
}

private func testDisabledDoesNotGenerate() {
    let generator = RecordingGenerator(output: "unused")
    let useCase = ConfigureZonoeUDIDCallbackUseCase(
        generator: generator,
        now: { Date(timeIntervalSince1970: 1) },
        nonce: { "nonce" }
    )
    let result = useCase.execute(.init(
        enabled: false,
        customBundleIdentifier: "com.custom",
        plistBundleIdentifier: "com.base"
    ))
    expect(result == nil, "disabled request must return nil")
    expect(generator.calls.isEmpty, "disabled request must not generate a scheme")
}

private func testCustomBundleIdentifierWins() {
    let generator = RecordingGenerator(output: "fixed-scheme")
    let useCase = ConfigureZonoeUDIDCallbackUseCase(
        generator: generator,
        now: { Date(timeIntervalSince1970: 2) },
        nonce: { "ABC-123" }
    )
    let result = useCase.execute(.init(
        enabled: true,
        customBundleIdentifier: "  com.custom.app  ",
        plistBundleIdentifier: "com.base.app"
    ))
    expect(result == .init(scheme: "fixed-scheme", host: "udid-callback"), "configuration must preserve generated scheme and host")
    expect(generator.calls.count == 1, "enabled request must generate exactly once")
    expect(generator.calls.first?.0 == "com.custom.app", "trimmed custom Bundle ID must win")
    expect(generator.calls.first?.2 == "ABC-123", "nonce must be forwarded unchanged to generator")
}

private func testFallbackBundleIdentifier() {
    let generator = RecordingGenerator(output: "fallback")
    let useCase = ConfigureZonoeUDIDCallbackUseCase(generator: generator, nonce: { "n" })
    _ = useCase.execute(.init(enabled: true, customBundleIdentifier: "   ", plistBundleIdentifier: "com.base"))
    expect(generator.calls.first?.0 == "com.base", "plist Bundle ID must be used when custom ID is blank")
    
    let unknownGenerator = RecordingGenerator(output: "unknown")
    let unknownUseCase = ConfigureZonoeUDIDCallbackUseCase(generator: unknownGenerator, nonce: { "n" })
    _ = unknownUseCase.execute(.init(enabled: true, customBundleIdentifier: nil, plistBundleIdentifier: nil))
    expect(unknownGenerator.calls.first?.0 == "unknown", "missing Bundle ID must preserve legacy unknown fallback")
}

private func testPlistEnableDisableAndIdempotency() {
    let dictionary = NSMutableDictionary(dictionary: [
        "CFBundleIdentifier": "com.base",
        "CFBundleURLTypes": [
            ["CFBundleURLName": "other", "CFBundleURLSchemes": ["other"]],
            ["CFBundleURLName": ZonoeUDIDCallbackMetadata.marker, "CFBundleURLSchemes": ["old-zonoe"]]
        ],
        ZonoeUDIDCallbackMetadata.schemeKey: "old-zonoe",
        ZonoeUDIDCallbackMetadata.hostKey: ZonoeUDIDCallbackMetadata.host
    ])
    let adapter = ZonoeUDIDCallbackPlistAdapter()
    let configuration = ZonoeUDIDCallbackConfiguration(scheme: "new-zonoe", host: ZonoeUDIDCallbackMetadata.host)
    
    adapter.apply(configuration, to: dictionary)
    adapter.apply(configuration, to: dictionary)
    
    let enabledTypes = dictionary["CFBundleURLTypes"] as? [[String: Any]] ?? []
    let zonoeTypes = enabledTypes.filter { ($0["CFBundleURLName"] as? String) == ZonoeUDIDCallbackMetadata.marker }
    expect(enabledTypes.count == 2, "enabling twice must preserve unrelated URL type and avoid duplicates")
    expect(zonoeTypes.count == 1, "zonoe URL type must be idempotent")
    expect((zonoeTypes.first?["CFBundleURLSchemes"] as? [String]) == ["new-zonoe"], "new scheme must replace old scheme")
    expect(dictionary[ZonoeUDIDCallbackMetadata.schemeKey] as? String == "new-zonoe", "scheme metadata must be written")
    expect(dictionary[ZonoeUDIDCallbackMetadata.hostKey] as? String == ZonoeUDIDCallbackMetadata.host, "host metadata must be written")
    
    adapter.apply(nil, to: dictionary)
    let disabledTypes = dictionary["CFBundleURLTypes"] as? [[String: Any]] ?? []
    expect(disabledTypes.count == 1, "disabling must preserve unrelated URL type")
    expect((disabledTypes.first?["CFBundleURLName"] as? String) == "other", "unrelated URL type must survive disable")
    expect(dictionary[ZonoeUDIDCallbackMetadata.schemeKey] == nil, "scheme metadata must be removed when disabled")
    expect(dictionary[ZonoeUDIDCallbackMetadata.hostKey] == nil, "host metadata must be removed when disabled")
}

private func testPreviousSchemeCleanupWithoutMarker() {
    let dictionary = NSMutableDictionary(dictionary: [
        "CFBundleURLTypes": [
            ["CFBundleURLName": "legacy", "CFBundleURLSchemes": ["legacy-zonoe"]],
            ["CFBundleURLName": "other", "CFBundleURLSchemes": ["other"]]
        ],
        ZonoeUDIDCallbackMetadata.schemeKey: "legacy-zonoe"
    ])
    
    ZonoeUDIDCallbackPlistAdapter().apply(nil, to: dictionary)
    let urlTypes = dictionary["CFBundleURLTypes"] as? [[String: Any]] ?? []
    expect(urlTypes.count == 1, "legacy previous-scheme URL type must be removed")
    expect((urlTypes.first?["CFBundleURLName"] as? String) == "other", "unrelated URL type must remain after legacy cleanup")
}

private func testEmptyURLTypesRemovedOnDisable() {
    let dictionary = NSMutableDictionary(dictionary: [
        "CFBundleURLTypes": [
            ["CFBundleURLName": ZonoeUDIDCallbackMetadata.marker, "CFBundleURLSchemes": ["old"]]
        ],
        ZonoeUDIDCallbackMetadata.schemeKey: "old"
    ])
    
    ZonoeUDIDCallbackPlistAdapter().apply(nil, to: dictionary)
    expect(dictionary["CFBundleURLTypes"] == nil, "empty CFBundleURLTypes must be removed to preserve legacy behavior")
}

private func testDefaultSchemeGeneratorContract() {
    let generator = DefaultZonoeUDIDCallbackSchemeGenerator()
    let scheme = generator.makeScheme(
        bundleIdentifier: "Com.Example/测试 App",
        date: Date(timeIntervalSince1970: 0),
        nonce: "ABC-DEF-123"
    )
    
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789+.-")
    expect(scheme.hasPrefix("zonoe-com.example-"), "scheme must be lowercased and sanitize invalid Bundle ID characters")
    expect(scheme.hasSuffix("-abcdef123"), "UUID-style nonce hyphens must be removed and lowercased")
    expect(scheme.unicodeScalars.allSatisfy { allowed.contains($0) }, "generated scheme must contain only URL-scheme-safe characters")
}

private func testLegacyParityMatrix() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let nonce = "12345678-ABCD-EF01-2345-6789ABCDEF01"
    let source: [AnyHashable: Any] = [
        "CFBundleIdentifier": "com.base.app",
        "CFBundleURLTypes": [
            ["CFBundleURLName": "other", "CFBundleURLSchemes": ["other"]],
            ["CFBundleURLName": "zonoe.udid.callback", "CFBundleURLSchemes": ["old-zonoe"]]
        ],
        "ZonoeUDIDCallbackScheme": "old-zonoe",
        "ZonoeUDIDCallbackHost": "udid-callback"
    ]
    
    assertLegacyParity(enabled: true, customBundleIdentifier: " com.custom.app ", source: source, date: date, nonce: nonce, label: "enabled/custom bundle id")
    assertLegacyParity(enabled: true, customBundleIdentifier: "   ", source: source, date: date, nonce: nonce, label: "enabled/plist fallback")
    assertLegacyParity(enabled: false, customBundleIdentifier: nil, source: source, date: date, nonce: nonce, label: "disabled/cleanup")
    assertLegacyParity(enabled: false, customBundleIdentifier: nil, source: [:], date: date, nonce: nonce, label: "disabled/empty plist")
}

@main
private enum SigningArchitectureRegressionMain {
    static func main() {
        testDisabledDoesNotGenerate()
        testCustomBundleIdentifierWins()
        testFallbackBundleIdentifier()
        testPlistEnableDisableAndIdempotency()
        testPreviousSchemeCleanupWithoutMarker()
        testEmptyURLTypesRemovedOnDisable()
        testDefaultSchemeGeneratorContract()
        testLegacyParityMatrix()
        print("Signing clean-architecture regression: PASS")
    }
}
