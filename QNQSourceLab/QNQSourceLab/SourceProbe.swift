import Foundation
import Darwin

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

    func useV2AltPreset() {
        urlText = "https://yxy.ioswg.com/appstore"
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
            let sample = try await Self.fetchSample(url)
            output = Self.inspect(sample: sample, bkey: bkey).joined(separator: "\n")
        } catch {
            output = "请求失败: \(error.localizedDescription)"
        }
    }

    func runRepeatCompare() async {
        let input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input), !input.isEmpty else {
            output = "URL 无效"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let a = try await Self.fetchSample(url)
            try? await Task.sleep(nanoseconds: 350_000_000)
            let b = try await Self.fetchSample(url)
            output = Self.compareSamples(a, b, title: "同源双抓对比").joined(separator: "\n")
        } catch {
            output = "对比失败: \(error.localizedDescription)"
        }
    }

    func runV2Compare() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let qnq = try await Self.fetchSample(URL(string: "https://qnq.ioswg.com/appstore")!)
            let yxy = try await Self.fetchSample(URL(string: "https://yxy.ioswg.com/appstore")!)
            var lines = Self.compareSamples(qnq, yxy, title: "V2 两源对比")
            lines.append("")
            lines.append("--- qnq 头部 ---")
            lines.append(contentsOf: Self.headerReport(qnq.decoded))
            lines.append("")
            lines.append("--- yxy 头部 ---")
            lines.append(contentsOf: Self.headerReport(yxy.decoded))
            output = lines.joined(separator: "\n")
        } catch {
            output = "V2 对比失败: \(error.localizedDescription)"
        }
    }

    private struct Sample {
        let url: URL
        let httpStatus: Int?
        let contentType: String?
        let responseBytes: Int
        let wrapper: String
        let payloadChars: Int
        let normalizedChars: Int
        let decoded: Data?
        let payloadPrefix: String
    }

    private static func fetchSample(_ url: URL) async throws -> Sample {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("QNQSourceLab/0.2", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return Sample(
                url: url,
                httpStatus: http?.statusCode,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                responseBytes: data.count,
                wrapper: "<outer-json-failed>",
                payloadChars: 0,
                normalizedChars: 0,
                decoded: nil,
                payloadPrefix: textPrefix(data, limit: 240)
            )
        }

        let wrapper: String
        if dictionary["appstore_v2"] != nil {
            wrapper = "appstore_v2"
        } else if dictionary["appstore"] != nil {
            wrapper = "appstore"
        } else {
            wrapper = "<unknown>"
        }

        guard wrapper != "<unknown>", let payload = dictionary[wrapper] as? String else {
            return Sample(
                url: url,
                httpStatus: http?.statusCode,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                responseBytes: data.count,
                wrapper: wrapper,
                payloadChars: 0,
                normalizedChars: 0,
                decoded: nil,
                payloadPrefix: prettyJSONPrefix(object)
            )
        }

        let compact = extractSourcePayload(payload)
        return Sample(
            url: url,
            httpStatus: http?.statusCode,
            contentType: http?.value(forHTTPHeaderField: "Content-Type"),
            responseBytes: data.count,
            wrapper: wrapper,
            payloadChars: payload.count,
            normalizedChars: compact.count,
            decoded: decodeBase64Flexible(compact),
            payloadPrefix: String(payload.prefix(240))
        )
    }

    private static func inspect(sample: Sample, bkey: String) -> [String] {
        var lines: [String] = []
        lines.append("QNQ Source Lab v0.2")
        lines.append("URL: \(sample.url.absoluteString)")
        if let status = sample.httpStatus { lines.append("HTTP: \(status)") }
        if let type = sample.contentType { lines.append("Content-Type: \(type)") }
        lines.append("Response bytes: \(sample.responseBytes)")
        lines.append("")

        guard sample.wrapper != "<outer-json-failed>" else {
            lines.append("Outer JSON: ✗")
            lines.append("Raw prefix: \(sample.payloadPrefix)")
            return lines
        }

        lines.append("Outer JSON: ✓")
        lines.append("Wrapper: \(sample.wrapper)")
        lines.append("Payload chars: \(sample.payloadChars)")
        lines.append("Payload normalized chars: \(sample.normalizedChars)")

        guard let decoded = sample.decoded else {
            lines.append("Base64: ✗")
            lines.append("Payload prefix: \(sample.payloadPrefix)")
            return lines
        }

        lines.append("Base64: ✓")
        lines.append("Decoded bytes: \(decoded.count)")
        lines.append("Decoded mod 8: \(decoded.count % 8)")
        lines.append("Decoded mod 16: \(decoded.count % 16)")
        lines.append("Hex prefix 64: \(hexPrefix(decoded, count: 64))")
        lines.append("Signature: \(signature(decoded))")
        lines.append(String(format: "Printable ratio: %.3f", printableRatio(decoded)))
        lines.append(String(format: "Entropy(first64K): %.3f bits/byte", entropy(decoded.prefixData(65536))))

        lines.append("")
        lines.append("[Header integers]")
        lines.append(contentsOf: headerReport(decoded))

        lines.append("")
        lines.append("[Candidate offsets]")
        let offsets = candidateOffsets(decoded)
        for offset in offsets where offset < decoded.count {
            let tail = decoded.subdata(in: offset..<decoded.count)
            let sampleData = tail.prefixData(65536)
            lines.append(
                String(
                    format: "off=%d len=%d mod8=%d mod16=%d sig=%@ print=%.3f H=%.3f hex=%@",
                    offset,
                    tail.count,
                    tail.count % 8,
                    tail.count % 16,
                    signature(tail),
                    printableRatio(sampleData),
                    entropy(sampleData),
                    hexPrefix(tail, count: 16)
                )
            )
            if let json = utf8JSON(tail) {
                lines.append("  → JSON ✓ \(String(json.prefix(700)))")
            }
        }

        lines.append("")
        lines.append("[Signature scan first 4096]")
        lines.append(signatureScan(decoded).joined(separator: "\n"))

        if let direct = utf8JSON(decoded) {
            lines.append("")
            lines.append("[Direct Base64 → UTF-8 JSON] ✓")
            lines.append(String(direct.prefix(1200)))
        } else {
            lines.append("")
            lines.append("[Direct Base64 → UTF-8 JSON] ✗")
        }

        let sourceShare = rc4(data: decoded, key: Data("source_share".utf8))
        appendCandidate(name: "RC4 full key=source_share", data: sourceShare, to: &lines)

        for offset in [8, 120, 128] where offset < decoded.count {
            let tail = decoded.subdata(in: offset..<decoded.count)
            let candidate = rc4(data: tail, key: Data("source_share".utf8))
            appendCandidate(name: "RC4 off=\(offset) key=source_share", data: candidate, to: &lines, compact: true)
        }

        let trimmedKey = bkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let key = Data(trimmedKey.utf8)
            appendCandidate(name: "RC4 full key=bkey", data: rc4(data: decoded, key: key), to: &lines)
            for offset in [8, 120, 128] where offset < decoded.count {
                let tail = decoded.subdata(in: offset..<decoded.count)
                appendCandidate(name: "RC4 off=\(offset) key=bkey", data: rc4(data: tail, key: key), to: &lines, compact: true)
            }
        } else {
            lines.append("")
            lines.append("[RC4 bkey] 未输入 bkey，跳过")
        }

        return lines
    }

    private static func compareSamples(_ a: Sample, _ b: Sample, title: String) -> [String] {
        var lines: [String] = []
        lines.append("QNQ Source Lab v0.2")
        lines.append("[\(title)]")
        lines.append("A: \(a.url.absoluteString)")
        lines.append("   wrapper=\(a.wrapper) response=\(a.responseBytes) decoded=\(a.decoded?.count ?? -1)")
        lines.append("B: \(b.url.absoluteString)")
        lines.append("   wrapper=\(b.wrapper) response=\(b.responseBytes) decoded=\(b.decoded?.count ?? -1)")

        guard let ad = a.decoded, let bd = b.decoded else {
            lines.append("至少一个 payload 无法 Base64 解码。")
            lines.append("A prefix: \(a.payloadPrefix)")
            lines.append("B prefix: \(b.payloadPrefix)")
            return lines
        }

        let prefix = commonPrefixLength(ad, bd)
        let suffix = commonSuffixLength(ad, bd)
        lines.append("Common prefix bytes: \(prefix)")
        lines.append("Common suffix bytes: \(suffix)")
        lines.append("Exact equal: \(ad == bd ? "YES" : "NO")")
        lines.append("A first64: \(hexPrefix(ad, count: 64))")
        lines.append("B first64: \(hexPrefix(bd, count: 64))")

        if prefix < min(ad.count, bd.count) {
            lines.append("First diff offset: \(prefix)")
            lines.append("A @diff: \(hexWindow(ad, offset: prefix, radius: 16))")
            lines.append("B @diff: \(hexWindow(bd, offset: prefix, radius: 16))")
        }

        if prefix >= 8 {
            let header8 = ad.prefixData(8)
            lines.append("Shared first8: \(hexPrefix(header8, count: 8))")
            lines.append("first8 u32LE[0]=0x\(String(readU32LE(ad, 0) ?? 0, radix: 16))")
            lines.append("first8 u32LE[4]=\(readU32LE(ad, 4) ?? 0)")
        }

        return lines
    }

    private static func candidateOffsets(_ data: Data) -> [Int] {
        var values = [0, 2, 4, 8, 12, 16, 24, 32, 64, 96, 120, 124, 128, 136, 256]
        if let v = readU32LE(data, 4), v >= 4, v <= 4096 {
            values.append(Int(v))
            values.append(Int(v) + 4)
            values.append(Int(v) + 8)
        }
        return Array(Set(values)).sorted()
    }

    private static func headerReport(_ data: Data?) -> [String] {
        guard let data, !data.isEmpty else { return ["<no decoded data>"] }
        var lines: [String] = []
        for offset in stride(from: 0, through: min(28, max(0, data.count - 4)), by: 4) {
            let le = readU32LE(data, offset) ?? 0
            let be = readU32BE(data, offset) ?? 0
            lines.append(String(format: "u32 @%02d  LE=%10u (0x%08x)  BE=%10u (0x%08x)", offset, le, le, be, be))
        }
        if data.count >= 8,
           data[0] == 0x3e, data[1] == 0xb7, data[2] == 0xf6, data[3] == 0xf4,
           readU32LE(data, 4) == 120 {
            lines.append("V2 marker: 3e b7 f6 f4 + LE32(120) ✓")
            lines.append("推测：前 8 字节为固定容器头；120 可能是长度/版本参数，需继续对比验证。")
        }
        return lines
    }

    private static func signatureScan(_ data: Data) -> [String] {
        let limit = min(data.count, 4096)
        let bytes = [UInt8](data.prefix(limit))
        var findings: [String] = []

        func find(_ pattern: [UInt8], name: String) {
            guard pattern.count <= bytes.count else { return }
            for i in 0...(bytes.count - pattern.count) {
                if Array(bytes[i..<(i + pattern.count)]) == pattern {
                    findings.append("\(name) @ \(i)")
                    return
                }
            }
        }

        find([0x1f, 0x8b], name: "gzip")
        find([0x78, 0x01], name: "zlib-01")
        find([0x78, 0x5e], name: "zlib-5e")
        find([0x78, 0x9c], name: "zlib-9c")
        find([0x78, 0xda], name: "zlib-da")
        find([0x50, 0x4b, 0x03, 0x04], name: "ZIP")
        find(Array("bplist00".utf8), name: "bplist00")
        find([0x7b, 0x22], name: "JSON-object")
        find([0x5b, 0x7b], name: "JSON-array")

        return findings.isEmpty ? ["无明确文件/压缩/JSON 签名（扫描范围前 4096；随机命中也不代表真实格式）"] : findings
    }

    private static func appendCandidate(name: String, data: Data, to lines: inout [String], compact: Bool = false) {
        lines.append("")
        if let json = utf8JSON(data) {
            lines.append("[\(name)] ✓ JSON")
            lines.append(String(json.prefix(1000)))
        } else {
            lines.append("[\(name)] ✗")
            lines.append("Hex prefix: \(hexPrefix(data, count: compact ? 16 : 32))")
            lines.append("Signature: \(signature(data))")
            if !compact {
                lines.append(String(format: "Printable ratio: %.3f", printableRatio(data.prefixData(65536))))
                lines.append(String(format: "Entropy: %.3f", entropy(data.prefixData(65536))))
            }
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

    private static func readU32LE(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let b = [UInt8](data[offset..<(offset + 4)])
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    private static func readU32BE(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let b = [UInt8](data[offset..<(offset + 4)])
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    private static func commonPrefixLength(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b)
        let n = min(aa.count, bb.count)
        var i = 0
        while i < n && aa[i] == bb[i] { i += 1 }
        return i
    }

    private static func commonSuffixLength(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b)
        let n = min(aa.count, bb.count)
        var i = 0
        while i < n && aa[aa.count - 1 - i] == bb[bb.count - 1 - i] { i += 1 }
        return i
    }

    private static func hexWindow(_ data: Data, offset: Int, radius: Int) -> String {
        let start = max(0, offset - radius)
        let end = min(data.count, offset + radius)
        return "[\(start)..<\(end)] " + data[start..<end].map { String(format: "%02x", $0) }.joined(separator: " ")
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
            if byte == 9 || byte == 10 || byte == 13 || (32...126).contains(byte) { result += 1 }
        }
        return Double(printable) / Double(data.count)
    }

    private static func entropy(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        for byte in data { counts[Int(byte)] += 1 }
        let total = Double(data.count)
        var result = 0.0
        for count in counts where count > 0 {
            let p = Double(count) / total
            result -= p * log2(p)
        }
        return result
    }

    private static func signature(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(8))
        if bytes.count >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b { return "gzip" }
        if bytes.count >= 2 && bytes[0] == 0x78 && [0x01, 0x5e, 0x9c, 0xda].contains(bytes[1]) { return "zlib" }
        if bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b && bytes[2] == 0x03 && bytes[3] == 0x04 { return "ZIP" }
        if data.starts(with: Data("bplist00".utf8)) { return "binary plist" }
        if data.starts(with: Data("Salted__".utf8)) { return "OpenSSL Salted__" }
        if let first = bytes.first, first == 0x7b || first == 0x5b { return "JSON-like" }
        return "unknown"
    }
}

private extension Data {
    func prefixData(_ count: Int) -> Data {
        Data(prefix(count))
    }
}
