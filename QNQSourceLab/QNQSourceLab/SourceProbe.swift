import Foundation

@MainActor
final class SourceProbeModel: ObservableObject {
    @Published var urlText = "https://sign.io31.top/appstore"
    @Published var bkey = ""
    @Published var isLoading = false
    @Published var output = "等待测试。"

    func useLegacyPreset() {
        urlText = "https://sign.io31.top/appstore"
    }

    func useV2Preset() {
        urlText = "https://qnq.ioswg.com/appstore"
    }

    func run() async {
        let input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input), !input.isEmpty else {
            output = "URL 无效"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("QNQSourceLab/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            var lines: [String] = []
            lines.append("URL: \(url.absoluteString)")
            if let http = response as? HTTPURLResponse {
                lines.append("HTTP: \(http.statusCode)")
                if let type = http.value(forHTTPHeaderField: "Content-Type") {
                    lines.append("Content-Type: \(type)")
                }
            }
            lines.append("Response bytes: \(data.count)")
            lines.append("")
            lines.append(contentsOf: Self.inspectResponse(data, bkey: bkey))
            output = lines.joined(separator: "\n")
        } catch {
            output = "请求失败: \(error.localizedDescription)"
        }
    }

    private static func inspectResponse(_ data: Data, bkey: String) -> [String] {
        var lines: [String] = []

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            lines.append("Outer JSON: ✗")
            lines.append("Raw prefix: \(textPrefix(data, limit: 500))")
            lines.append("Hex prefix: \(hexPrefix(data))")
            return lines
        }

        lines.append("Outer JSON: ✓")
        lines.append("Top-level keys: \(dictionary.keys.sorted().joined(separator: ", "))")

        let wrapperKey: String?
        if dictionary["appstore_v2"] != nil {
            wrapperKey = "appstore_v2"
        } else if dictionary["appstore"] != nil {
            wrapperKey = "appstore"
        } else {
            wrapperKey = nil
        }

        guard let wrapperKey,
              let payload = dictionary[wrapperKey] as? String else {
            lines.append("Wrapper: 未发现 appstore/appstore_v2 字符串字段")
            lines.append("Pretty JSON prefix:")
            lines.append(prettyJSONPrefix(object))
            return lines
        }

        lines.append("Wrapper: \(wrapperKey)")
        lines.append("Payload chars: \(payload.count)")

        let compactPayload = extractSourcePayload(payload)
        lines.append("Payload normalized chars: \(compactPayload.count)")

        guard let decoded = decodeBase64Flexible(compactPayload) else {
            lines.append("Base64: ✗")
            lines.append("Payload prefix: \(String(payload.prefix(240)))")
            return lines
        }

        lines.append("Base64: ✓")
        lines.append("Decoded bytes: \(decoded.count)")
        lines.append("Decoded mod 8: \(decoded.count % 8)")
        lines.append("Decoded mod 16: \(decoded.count % 16)")
        lines.append("Hex prefix: \(hexPrefix(decoded))")
        lines.append("Signature: \(signature(decoded))")
        lines.append(String(format: "Printable ratio: %.3f", printableRatio(decoded)))

        if let direct = utf8JSON(decoded) {
            lines.append("")
            lines.append("[Direct Base64 → UTF-8 JSON] ✓")
            lines.append(String(direct.prefix(1500)))
        } else {
            lines.append("[Direct Base64 → UTF-8 JSON] ✗")
        }

        let sourceShare = rc4(data: decoded, key: Data("source_share".utf8))
        appendCandidate(name: "RC4 key=source_share", data: sourceShare, to: &lines)

        let trimmedKey = bkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let custom = rc4(data: decoded, key: Data(trimmedKey.utf8))
            appendCandidate(name: "RC4 key=bkey(用户输入)", data: custom, to: &lines)
        } else {
            lines.append("")
            lines.append("[RC4 bkey] 未输入 bkey，跳过")
        }

        if let directText = String(data: decoded, encoding: .utf8) {
            let compact = directText.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeBase64(compact), let second = decodeBase64Flexible(compact) {
                lines.append("")
                lines.append("[Second Base64 layer] ✓")
                lines.append("Bytes: \(second.count)")
                lines.append("Hex prefix: \(hexPrefix(second))")
                lines.append("Signature: \(signature(second))")
                if let json = utf8JSON(second) {
                    lines.append("Second Base64 → JSON: ✓")
                    lines.append(String(json.prefix(1500)))
                }
            }
        }

        return lines
    }

    private static func appendCandidate(name: String, data: Data, to lines: inout [String]) {
        lines.append("")
        if let json = utf8JSON(data) {
            lines.append("[\(name)] ✓ JSON")
            lines.append(String(json.prefix(1500)))
        } else {
            lines.append("[\(name)] ✗")
            lines.append("Hex prefix: \(hexPrefix(data))")
            lines.append("Signature: \(signature(data))")
            lines.append(String(format: "Printable ratio: %.3f", printableRatio(data)))
        }
    }

    private static func utf8JSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8)
    }

    private static func prettyJSONPrefix(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "<无法格式化>"
        }
        return String(text.prefix(1500))
    }

    private static func extractSourcePayload(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.range(of: "source[", options: [.caseInsensitive]),
           let end = trimmed.range(of: "]", options: [.backwards]),
           start.upperBound <= end.lowerBound {
            return String(trimmed[start.upperBound..<end.lowerBound]).filter { !$0.isWhitespace }
        }
        return trimmed.filter { !$0.isWhitespace }
    }

    private static func decodeBase64Flexible(_ text: String) -> Data? {
        var normalized = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters])
    }

    private static func looksLikeBase64(_ text: String) -> Bool {
        guard text.count >= 8 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-\r\n")
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func rc4(data: Data, key: Data) -> Data {
        let keyBytes = [UInt8](key)
        guard !keyBytes.isEmpty else { return data }

        var state = (0...255).map { UInt8($0) }
        var j = 0
        for i in 0..<256 {
            j = (j + Int(state[i]) + Int(keyBytes[i % keyBytes.count])) & 0xff
            state.swapAt(i, j)
        }

        let input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: input.count)
        var i = 0
        j = 0
        for index in input.indices {
            i = (i + 1) & 0xff
            j = (j + Int(state[i])) & 0xff
            state.swapAt(i, j)
            let stream = state[(Int(state[i]) + Int(state[j])) & 0xff]
            output[index] = input[index] ^ stream
        }
        return Data(output)
    }

    private static func hexPrefix(_ data: Data, count: Int = 32) -> String {
        data.prefix(count).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private static func textPrefix(_ data: Data, limit: Int) -> String {
        guard let text = String(data: data.prefix(limit), encoding: .utf8) else { return "<非 UTF-8>" }
        return text
    }

    private static func printableRatio(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        let printable = data.reduce(into: 0) { result, byte in
            if byte == 9 || byte == 10 || byte == 13 || (32...126).contains(byte) {
                result += 1
            }
        }
        return Double(printable) / Double(data.count)
    }

    private static func signature(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(8))
        if bytes.count >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b { return "gzip" }
        if bytes.count >= 2 && bytes[0] == 0x78 && [0x01, 0x5e, 0x9c, 0xda].contains(bytes[1]) { return "zlib" }
        if bytes.count >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b { return "ZIP" }
        if data.starts(with: Data("bplist00".utf8)) { return "binary plist" }
        if data.starts(with: Data("Salted__".utf8)) { return "OpenSSL Salted__" }
        if let first = bytes.first, first == 0x7b || first == 0x5b { return "JSON-like" }
        return "unknown"
    }
}
