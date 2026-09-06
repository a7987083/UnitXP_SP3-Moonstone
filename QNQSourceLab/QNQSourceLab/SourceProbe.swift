import Foundation

@MainActor
final class SourceProbeModel: ObservableObject {
    @Published var urlText = "https://qnq.ioswg.com/appstore"
    @Published var oracleText = "{\"a\":\"AAAA\"}"
    @Published var isLoading = false
    @Published var output = "等待 v0.6 测试。"
    @Published var exportReportURL: URL?
    @Published var exportAURL: URL?
    @Published var exportBURL: URL?

    private let v2OracleURL = URL(string: "https://api.nuosike.com/encrypt.php")!
    private let v1OracleURL = URL(string: "https://api.nuosike.com/api.php")!

    private struct SourceSample {
        let url: URL
        let status: Int?
        let contentType: String?
        let responseBytes: Int
        let wrapper: String
        let payload: String
        let decoded: Data?
    }

    private struct OracleSample {
        let endpoint: URL
        let plain: Data
        let contentBase64: String
        let status: Int?
        let responseText: String
        let encodedResponse: String?
        let decoded: Data?
    }

    private struct V2Shape {
        let magicOK: Bool
        let keyBlockLength: Int?
        let keyBlock: Data?
        let bodyStart: Int?
        let body: Data?
        let last4LE: UInt32?
        let last4BE: UInt32?
    }

    func useLegacyPreset() { urlText = "https://sign.io31.top/appstore" }
    func useV2Preset() { urlText = "https://qnq.ioswg.com/appstore" }
    func useV2AltPreset() { urlText = "https://yxy.ioswg.com/appstore" }

    func runSourceInspect() async {
        guard let url = checkedURL(urlText) else { output = "URL 无效"; return }
        await withBusy {
            let sample = try await Self.fetchSource(url)
            var lines = [
                "QNQ Source Lab v0.6",
                "[软件源结构验证]",
                "URL: \(sample.url.absoluteString)",
                "HTTP: \(sample.status.map(String.init) ?? "?")",
                "Content-Type: \(sample.contentType ?? "?")",
                "Response bytes: \(sample.responseBytes)",
                "Wrapper: \(sample.wrapper)",
                "Payload chars: \(sample.payload.count)"
            ]
            guard let data = sample.decoded else {
                lines.append("❌ Base64 decode failed")
                self.finish(lines: lines)
                return
            }
            lines.append("Base64 decoded: \(data.count) bytes")
            if sample.wrapper == "appstore_v2" {
                lines.append(contentsOf: Self.v2ShapeReport(data, knownPlainLength: nil))
                lines.append("结论: v0.5 的 @128 Segment2 length 假设已移除；本版只按已确认的 8-byte header + 120-byte key block 解析。")
            } else if sample.wrapper == "appstore" {
                lines.append("")
                lines.append("[appstore / v1]")
                lines.append("mod8=\(data.count % 8) mod16=\(data.count % 16)")
                lines.append("first32: \(Self.hex(Data(data.prefix(32))))")
                lines.append("last32: \(Self.hex(Data(data.suffix(32))))")
                lines.append("结论: 继续用 api.php 已知明文 Oracle 反推 DES 前 envelope/preprocessing，不再扩大 offset 暴力枚举。")
            } else {
                lines.append("❌ Unsupported wrapper")
            }
            self.finish(lines: lines)
        }
    }

    func runCustomV2Oracle() async { await runCustomOracle(endpoint: v2OracleURL, label: "V2 encrypt.php") }
    func runCustomV1Oracle() async { await runCustomOracle(endpoint: v1OracleURL, label: "V1 api.php") }

    func runV2Matrix() async { await runMatrix(endpoint: v2OracleURL, isV2: true) }
    func runV1Matrix() async { await runMatrix(endpoint: v1OracleURL, isV2: false) }

    private func runCustomOracle(endpoint: URL, label: String) async {
        await withBusy {
            let plain = Data(self.oracleText.utf8)
            let a = try await Self.postOracle(endpoint: endpoint, plain: plain)
            try? await Task.sleep(nanoseconds: 250_000_000)
            let b = try await Self.postOracle(endpoint: endpoint, plain: plain)

            var lines = [
                "QNQ Source Lab v0.6",
                "[\(label) 自定义明文双抓]",
                "Endpoint: \(endpoint.absoluteString)",
                "Plain UTF-8 bytes: \(plain.count)",
                "POST content(Base64) chars: \(a.contentBase64.count)"
            ]
            lines.append(contentsOf: Self.oraclePairReport(a, b, isV2: endpoint.lastPathComponent == "encrypt.php"))
            self.finish(lines: lines, a: a.decoded, b: b.decoded)
        }
    }

    private func runMatrix(endpoint: URL, isV2: Bool) async {
        let cases = [
            "",
            "A",
            "AA",
            "AAAA",
            "{}",
            "{\"a\":1}",
            "{\"a\":\"AAAA\"}"
        ]

        await withBusy {
            var lines = [
                "QNQ Source Lab v0.6",
                isV2 ? "[V2 encrypt.php 已知明文矩阵]" : "[V1 api.php 已知明文矩阵]",
                "Endpoint: \(endpoint.absoluteString)",
                "每个明文连续请求 2 次；POST 格式与全能签后台一致：application/x-www-form-urlencoded, content=Base64(plaintext)",
                ""
            ]

            var firstA: Data?
            var firstB: Data?
            var lengthRows: [(Int, Int)] = []

            for (index, text) in cases.enumerated() {
                let plain = Data(text.utf8)
                let a = try await Self.postOracle(endpoint: endpoint, plain: plain)
                try? await Task.sleep(nanoseconds: 220_000_000)
                let b = try await Self.postOracle(endpoint: endpoint, plain: plain)
                if index == 0 { firstA = a.decoded; firstB = b.decoded }

                lines.append("#\(index + 1) plain=\(Self.quoted(text)) bytes=\(plain.count)")
                lines.append(contentsOf: Self.compactOraclePairReport(a, b, isV2: isV2))
                lines.append("")
                if let count = a.decoded?.count { lengthRows.append((plain.count, count)) }
                try? await Task.sleep(nanoseconds: 220_000_000)
            }

            lines.append("[长度关系]")
            for row in lengthRows {
                lines.append("plain=\(row.0) -> decoded=\(row.1), overhead=\(row.1 - row.0)")
            }
            if lengthRows.count >= 2 {
                let overheads = Set(lengthRows.map { $0.1 - $0.0 })
                lines.append("固定 overhead: \(overheads.count == 1 ? "YES (\(overheads.first!))" : "NO")")
            }
            self.finish(lines: lines, a: firstA, b: firstB)
        }
    }

    private func checkedURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func withBusy(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        exportReportURL = nil
        exportAURL = nil
        exportBURL = nil
        defer { isLoading = false }
        do { try await operation() }
        catch {
            finish(lines: ["QNQ Source Lab v0.6", "❌ \(error.localizedDescription)"])
        }
    }

    private func finish(lines: [String], a: Data? = nil, b: Data? = nil) {
        let report = lines.joined(separator: "\n")
        output = report
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QNQSourceLab-v0.6-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reportURL = dir.appendingPathComponent("v0.6-report.txt")
        try? Data(report.utf8).write(to: reportURL)
        exportReportURL = reportURL
        if let a {
            let u = dir.appendingPathComponent("A-decoded.bin")
            try? a.write(to: u)
            exportAURL = u
        }
        if let b {
            let u = dir.appendingPathComponent("B-decoded.bin")
            try? b.write(to: u)
            exportBURL = u
        }
    }

    private static func fetchSource(_ url: URL) async throws -> SourceSample {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("QNQSourceLab/0.6", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        guard let obj = try? JSONSerialization.jsonObject(with: data), let root = obj as? [String: Any] else {
            return SourceSample(url: url, status: http?.statusCode, contentType: http?.value(forHTTPHeaderField: "Content-Type"), responseBytes: data.count, wrapper: "<outer-json-failed>", payload: "", decoded: nil)
        }
        let wrapper: String
        if root["appstore_v2"] is String { wrapper = "appstore_v2" }
        else if root["appstore"] is String { wrapper = "appstore" }
        else { wrapper = "<unknown>" }
        let payload = root[wrapper] as? String ?? ""
        return SourceSample(url: url, status: http?.statusCode, contentType: http?.value(forHTTPHeaderField: "Content-Type"), responseBytes: data.count, wrapper: wrapper, payload: payload, decoded: decodeBase64Flexible(payload))
    }

    private static func postOracle(endpoint: URL, plain: Data) async throws -> OracleSample {
        let content = plain.base64EncodedString()
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "content", value: content)]
        let body = Data((comps.percentEncodedQuery ?? "content=").utf8)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpBody = body
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("QNQSourceLab/0.6", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode
        let text = String(data: data, encoding: .utf8) ?? ""
        let encoded = extractBase64Response(text)
        let decoded = encoded.flatMap(decodeBase64Flexible)
        return OracleSample(endpoint: endpoint, plain: plain, contentBase64: content, status: status, responseText: text, encodedResponse: encoded, decoded: decoded)
    }

    private static func extractBase64Response(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = decodeBase64Flexible(trimmed), d.count >= 4 { return trimmed }

        let pattern = "[A-Za-z0-9+/_=-]{32,}"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        let candidates = re.matches(in: raw, range: range).map { ns.substring(with: $0.range) }
        return candidates.max(by: { $0.count < $1.count })
    }

    private static func oraclePairReport(_ a: OracleSample, _ b: OracleSample, isV2: Bool) -> [String] {
        var lines = [
            "A HTTP: \(a.status.map(String.init) ?? "?") response chars=\(a.responseText.count) decoded=\(a.decoded?.count ?? -1)",
            "B HTTP: \(b.status.map(String.init) ?? "?") response chars=\(b.responseText.count) decoded=\(b.decoded?.count ?? -1)"
        ]
        guard let ad = a.decoded, let bd = b.decoded else {
            lines.append("❌ 至少一次响应无法提取/解码 Base64")
            lines.append("A prefix: \(String(a.responseText.prefix(180)))")
            lines.append("B prefix: \(String(b.responseText.prefix(180)))")
            return lines
        }
        lines.append(contentsOf: binaryCompareReport(ad, bd))
        if isV2 {
            lines.append("")
            lines.append("[A V2 envelope]")
            lines.append(contentsOf: v2ShapeReport(ad, knownPlainLength: a.plain.count))
            lines.append("")
            lines.append("[B V2 envelope]")
            lines.append(contentsOf: v2ShapeReport(bd, knownPlainLength: b.plain.count))
        } else {
            lines.append("A mod8=\(ad.count % 8) mod16=\(ad.count % 16)")
            lines.append("A first32: \(hex(Data(ad.prefix(32))))")
            lines.append("A last32: \(hex(Data(ad.suffix(32))))")
            lines.append("B first32: \(hex(Data(bd.prefix(32))))")
            lines.append("B last32: \(hex(Data(bd.suffix(32))))")
        }
        return lines
    }

    private static func compactOraclePairReport(_ a: OracleSample, _ b: OracleSample, isV2: Bool) -> [String] {
        guard let ad = a.decoded, let bd = b.decoded else {
            return ["decode: FAIL A=\(a.decoded?.count ?? -1) B=\(b.decoded?.count ?? -1)"]
        }
        let prefix = commonPrefix(ad, bd)
        let suffix = commonSuffix(ad, bd)
        let changed = changedCount(ad, bd)
        let overlap = min(ad.count, bd.count)
        let ratio = overlap == 0 ? 0 : Double(changed) / Double(overlap)
        var lines = [
            String(format: "A=%d B=%d commonPrefix=%d commonSuffix=%d changed=%d/%d (%.6f)", ad.count, bd.count, prefix, suffix, changed, overlap, ratio)
        ]
        if isV2 {
            let sa = parseV2(ad)
            let sb = parseV2(bd)
            lines.append("A: magic=\(sa.magicOK ? "OK" : "NO") keyLen=\(sa.keyBlockLength.map(String.init) ?? "?") bodyStart=\(sa.bodyStart.map(String.init) ?? "?") bodyBytes=\(sa.body?.count ?? -1) last4LE=\(sa.last4LE.map(String.init) ?? "?") plainLenMatch=\(sa.last4LE == UInt32(a.plain.count) ? "YES" : "NO")")
            lines.append("B: magic=\(sb.magicOK ? "OK" : "NO") keyLen=\(sb.keyBlockLength.map(String.init) ?? "?") bodyStart=\(sb.bodyStart.map(String.init) ?? "?") bodyBytes=\(sb.body?.count ?? -1) last4LE=\(sb.last4LE.map(String.init) ?? "?") plainLenMatch=\(sb.last4LE == UInt32(b.plain.count) ? "YES" : "NO")")
        } else {
            lines.append("mod8 A=\(ad.count % 8) B=\(bd.count % 8); first8 A=\(hex(Data(ad.prefix(8)))) B=\(hex(Data(bd.prefix(8))))")
        }
        return lines
    }

    private static func parseV2(_ data: Data) -> V2Shape {
        let expected = Data([0x3e, 0xb7, 0xf6, 0xf4])
        let magicOK = data.count >= 4 && Data(data.prefix(4)) == expected
        guard data.count >= 8, let keyLen32 = readU32LE(data, at: 4) else {
            return V2Shape(magicOK: magicOK, keyBlockLength: nil, keyBlock: nil, bodyStart: nil, body: nil, last4LE: readU32LEAtEnd(data), last4BE: readU32BEAtEnd(data))
        }
        let keyLen = Int(keyLen32)
        let start = 8
        let end = start + keyLen
        guard keyLen >= 0, end <= data.count else {
            return V2Shape(magicOK: magicOK, keyBlockLength: keyLen, keyBlock: nil, bodyStart: nil, body: nil, last4LE: readU32LEAtEnd(data), last4BE: readU32BEAtEnd(data))
        }
        let block = data.subdata(in: start..<end)
        let body = end <= data.count ? data.subdata(in: end..<data.count) : nil
        return V2Shape(magicOK: magicOK, keyBlockLength: keyLen, keyBlock: block, bodyStart: end, body: body, last4LE: readU32LEAtEnd(data), last4BE: readU32BEAtEnd(data))
    }

    private static func v2ShapeReport(_ data: Data, knownPlainLength: Int?) -> [String] {
        let s = parseV2(data)
        var lines = ["", "[appstore_v2 envelope]"]
        lines.append("Magic: \(s.magicOK ? "✅ 3e b7 f6 f4" : "❌")")
        lines.append("Key block length @4 LE32: \(s.keyBlockLength.map(String.init) ?? "?")")
        if let key = s.keyBlock {
            lines.append("Key block: \(key.count) bytes")
            lines.append("Key first16: \(hex(Data(key.prefix(16))))")
            lines.append("Key last16: \(hex(Data(key.suffix(16))))")
        }
        lines.append("Body start: \(s.bodyStart.map(String.init) ?? "?")")
        if let body = s.body {
            lines.append("Body bytes (including possible trailer): \(body.count)")
            lines.append("Body first24: \(hex(Data(body.prefix(24))))")
            lines.append("Body last24: \(hex(Data(body.suffix(24))))")
        }
        lines.append("Last4 LE: \(s.last4LE.map(String.init) ?? "?")")
        lines.append("Last4 BE: \(s.last4BE.map(String.init) ?? "?")")
        if let knownPlainLength, let last = s.last4LE {
            lines.append("Last4LE == plaintext bytes: \(last == UInt32(knownPlainLength) ? "✅ YES" : "❌ NO") (plain=\(knownPlainLength))")
        }
        return lines
    }

    private static func binaryCompareReport(_ a: Data, _ b: Data) -> [String] {
        let prefix = commonPrefix(a, b)
        let suffix = commonSuffix(a, b)
        let changed = changedCount(a, b)
        let overlap = min(a.count, b.count)
        let ratio = overlap == 0 ? 0 : Double(changed) / Double(overlap)
        return [
            "Exact equal: \(a == b ? "YES" : "NO")",
            "Common prefix: \(prefix)",
            "Common suffix: \(suffix)",
            "Length delta: \(a.count - b.count)",
            "Changed overlap: \(changed)/\(overlap)",
            String(format: "Changed ratio: %.6f", ratio),
            "A first16: \(hex(Data(a.prefix(16))))",
            "B first16: \(hex(Data(b.prefix(16))))",
            "A last16: \(hex(Data(a.suffix(16))))",
            "B last16: \(hex(Data(b.suffix(16))))"
        ]
    }

    private static func commonPrefix(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b)
        let n = min(aa.count, bb.count)
        var i = 0
        while i < n && aa[i] == bb[i] { i += 1 }
        return i
    }

    private static func commonSuffix(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b)
        let n = min(aa.count, bb.count)
        var i = 0
        while i < n && aa[aa.count - 1 - i] == bb[bb.count - 1 - i] { i += 1 }
        return i
    }

    private static func changedCount(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b)
        let n = min(aa.count, bb.count)
        var c = 0
        for i in 0..<n where aa[i] != bb[i] { c += 1 }
        return c
    }

    private static func decodeBase64Flexible(_ input: String) -> Data? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        while text.count % 4 != 0 { text.append("=") }
        return Data(base64Encoded: text, options: [.ignoreUnknownCharacters])
    }

    private static func readU32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let b = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    private static func readU32BE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let b = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    private static func readU32LEAtEnd(_ data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return readU32LE(data, at: data.count - 4)
    }

    private static func readU32BEAtEnd(_ data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return readU32BE(data, at: data.count - 4)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private static func quoted(_ s: String) -> String {
        if s.isEmpty { return "<empty>" }
        return "\"\(s.replacingOccurrences(of: "\n", with: "\\n"))\""
    }
}
