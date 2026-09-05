import Foundation

@MainActor
final class SourceProbeModel: ObservableObject {
    @Published var urlText = "https://sign.io31.top/appstore"
    @Published var bkey = ""
    @Published var isLoading = false
    @Published var output = "等待测试。"
    @Published var exportReportURL: URL?
    @Published var exportAURL: URL?
    @Published var exportBURL: URL?

    private struct Sample {
        let url: URL
        let httpStatus: Int?
        let contentType: String?
        let responseBytes: Int
        let wrapper: String
        let payloadChars: Int
        let decoded: Data?
        let payloadPrefix: String
    }

    func useLegacyPreset() { urlText = "https://sign.io31.top/appstore" }
    func useV2Preset() { urlText = "https://qnq.ioswg.com/appstore" }
    func useV2AltPreset() { urlText = "https://yxy.ioswg.com/appstore" }

    func run() async {
        guard let url = checkedURL(urlText) else { output = "URL 无效"; return }
        await perform {
            let sample = try await Self.fetchSample(url)
            let report = Self.inspect(sample: sample, bkey: self.bkey).joined(separator: "\n")
            self.output = report
            self.saveExports(report: report, a: sample, b: nil, label: "single")
        }
    }

    func runRepeatCompare() async {
        guard let url = checkedURL(urlText) else { output = "URL 无效"; return }
        await compareSame(url: url, title: "当前地址同源双抓")
    }

    func runLegacyRepeat() async {
        await compareSame(url: URL(string: "https://sign.io31.top/appstore")!, title: "Legacy 同源双抓")
    }

    func runV2QnqRepeat() async {
        await compareSame(url: URL(string: "https://qnq.ioswg.com/appstore")!, title: "V2 qnq 同源双抓")
    }

    func runV2YxyRepeat() async {
        await compareSame(url: URL(string: "https://yxy.ioswg.com/appstore")!, title: "V2 yxy 同源双抓")
    }

    func runV2Compare() async {
        await perform {
            let a = try await Self.fetchSample(URL(string: "https://qnq.ioswg.com/appstore")!)
            let b = try await Self.fetchSample(URL(string: "https://yxy.ioswg.com/appstore")!)
            let report = Self.compareSamples(a, b, title: "V2 两源对比").joined(separator: "\n")
            self.output = report
            self.saveExports(report: report, a: a, b: b, label: "v2-cross")
        }
    }

    private func compareSame(url: URL, title: String) async {
        await perform {
            let a = try await Self.fetchSample(url)
            try? await Task.sleep(nanoseconds: 450_000_000)
            let b = try await Self.fetchSample(url)
            let report = Self.compareSamples(a, b, title: title).joined(separator: "\n")
            self.output = report
            self.saveExports(report: report, a: a, b: b, label: title.replacingOccurrences(of: " ", with: "-"))
        }
    }

    private func checkedURL(_ value: String) -> URL? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isLoading = true
        exportReportURL = nil
        exportAURL = nil
        exportBURL = nil
        defer { isLoading = false }
        do { try await work() }
        catch { output = "失败: \(error.localizedDescription)" }
    }

    private func saveExports(report: String, a: Sample, b: Sample?, label: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QNQSourceLab-v0.3-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reportURL = dir.appendingPathComponent("\(label)-report.txt")
        try? Data(report.utf8).write(to: reportURL)
        exportReportURL = reportURL
        if let data = a.decoded {
            let u = dir.appendingPathComponent("A-\(a.wrapper)-decoded.bin")
            try? data.write(to: u)
            exportAURL = u
        }
        if let b, let data = b.decoded {
            let u = dir.appendingPathComponent("B-\(b.wrapper)-decoded.bin")
            try? data.write(to: u)
            exportBURL = u
        }
    }

    private static func fetchSample(_ url: URL) async throws -> Sample {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("QNQSourceLab/0.3", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return Sample(url: url, httpStatus: http?.statusCode, contentType: http?.value(forHTTPHeaderField: "Content-Type"), responseBytes: data.count, wrapper: "<outer-json-failed>", payloadChars: 0, decoded: nil, payloadPrefix: textPrefix(data, limit: 240))
        }

        let wrapper: String
        if dict["appstore_v2"] != nil { wrapper = "appstore_v2" }
        else if dict["appstore"] != nil { wrapper = "appstore" }
        else { wrapper = "<unknown>" }

        guard wrapper != "<unknown>", let payload = dict[wrapper] as? String else {
            return Sample(url: url, httpStatus: http?.statusCode, contentType: http?.value(forHTTPHeaderField: "Content-Type"), responseBytes: data.count, wrapper: wrapper, payloadChars: 0, decoded: nil, payloadPrefix: String(data: data.prefix(240), encoding: .utf8) ?? "<binary>")
        }
        let compact = extractSourcePayload(payload)
        return Sample(url: url, httpStatus: http?.statusCode, contentType: http?.value(forHTTPHeaderField: "Content-Type"), responseBytes: data.count, wrapper: wrapper, payloadChars: payload.count, decoded: decodeBase64Flexible(compact), payloadPrefix: String(payload.prefix(240)))
    }

    private static func inspect(sample: Sample, bkey: String) -> [String] {
        var lines = ["QNQ Source Lab v0.3", "URL: \(sample.url.absoluteString)"]
        if let s = sample.httpStatus { lines.append("HTTP: \(s)") }
        if let t = sample.contentType { lines.append("Content-Type: \(t)") }
        lines.append("Response bytes: \(sample.responseBytes)")
        lines.append("Wrapper: \(sample.wrapper)")
        lines.append("Payload chars: \(sample.payloadChars)")
        guard let data = sample.decoded else {
            lines.append("Base64: ✗")
            lines.append("Prefix: \(sample.payloadPrefix)")
            return lines
        }
        lines.append("Base64: ✓")
        lines.append(contentsOf: structuralReport(data))

        let known = rc4(data: data, key: Data("source_share".utf8))
        lines.append("")
        lines.append("RC4 source_share JSON: \(utf8JSON(known) != nil ? "✓" : "✗")")
        let key = bkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            let custom = rc4(data: data, key: Data(key.utf8))
            lines.append("RC4 bkey JSON: \(utf8JSON(custom) != nil ? "✓" : "✗")")
        }
        return lines
    }

    private static func structuralReport(_ data: Data) -> [String] {
        var lines: [String] = []
        lines.append("Decoded bytes: \(data.count)")
        lines.append("mod8=\(data.count % 8) mod16=\(data.count % 16)")
        lines.append("first64: \(hexPrefix(data, count: 64))")
        lines.append(String(format: "Entropy first64K: %.4f", entropy(Data(data.prefix(65536)))))
        lines.append(String(format: "Printable first64K: %.4f", printableRatio(Data(data.prefix(65536)))))
        if data.count >= 8 {
            lines.append(String(format: "u32LE @0 = 0x%08x", readU32LE(data, 0) ?? 0))
            lines.append("u32LE @4 = \(readU32LE(data, 4) ?? 0)")
        }
        if isV2(data) { lines.append("V2 marker 3e b7 f6 f4 + LE32(120): ✓") }
        for offset in [0, 8, 120, 128] where offset < data.count {
            let body = data.subdata(in: offset..<data.count)
            let prefix = Data(body.prefix(65536))
            let dup8 = duplicateBlockStats(body, blockSize: 8)
            let dup16 = duplicateBlockStats(body, blockSize: 16)
            lines.append(String(format: "off=%d len=%d H=%.4f print=%.4f dup8=%d/%d dup16=%d/%d", offset, body.count, entropy(prefix), printableRatio(prefix), dup8.duplicates, dup8.blocks, dup16.duplicates, dup16.blocks))
        }
        lines.append("ASCII runs >=12 (first64K): \(asciiRuns(Data(data.prefix(65536)), minimum: 12, limit: 8).joined(separator: " | "))")
        return lines
    }

    private static func compareSamples(_ a: Sample, _ b: Sample, title: String) -> [String] {
        var lines = ["QNQ Source Lab v0.3", "[\(title)]", "A: \(a.url.absoluteString)", "   wrapper=\(a.wrapper) response=\(a.responseBytes) decoded=\(a.decoded?.count ?? -1)", "B: \(b.url.absoluteString)", "   wrapper=\(b.wrapper) response=\(b.responseBytes) decoded=\(b.decoded?.count ?? -1)"]
        guard let ad = a.decoded, let bd = b.decoded else {
            lines.append("至少一个 payload Base64 解码失败。")
            lines.append("A prefix: \(a.payloadPrefix)")
            lines.append("B prefix: \(b.payloadPrefix)")
            return lines
        }

        let minCount = min(ad.count, bd.count)
        let prefix = commonPrefixLength(ad, bd)
        let suffix = commonSuffixLength(ad, bd)
        let stats = differenceStats(ad, bd)
        lines.append("Common prefix bytes: \(prefix)")
        lines.append("Common suffix bytes: \(suffix)")
        lines.append("Exact equal: \(ad == bd ? "YES" : "NO")")
        lines.append("Length delta: \(ad.count - bd.count)")
        lines.append("Changed bytes(overlap): \(stats.changed)/\(minCount)")
        lines.append(String(format: "Changed ratio: %.6f", minCount == 0 ? 0 : Double(stats.changed) / Double(minCount)))
        lines.append("Changed regions: \(stats.regions.count)")
        if let first = stats.regions.first, let last = stats.regions.last {
            lines.append("Diff span: \(first.lowerBound)..<\(last.upperBound) spanLen=\(last.upperBound - first.lowerBound)")
        }
        lines.append("First regions: \(stats.regions.prefix(12).map { "\($0.lowerBound)..<\($0.upperBound)" }.joined(separator: ", "))")
        lines.append("A first64: \(hexPrefix(ad, count: 64))")
        lines.append("B first64: \(hexPrefix(bd, count: 64))")
        if prefix < minCount {
            lines.append("A @firstDiff: \(hexWindow(ad, offset: prefix, radius: 20))")
            lines.append("B @firstDiff: \(hexWindow(bd, offset: prefix, radius: 20))")
        }
        if prefix >= 8 {
            lines.append("Shared first8: \(hexPrefix(ad, count: 8))")
            lines.append(String(format: "first8 u32LE[0]=0x%08x", readU32LE(ad, 0) ?? 0))
            lines.append("first8 u32LE[4]=\(readU32LE(ad, 4) ?? 0)")
        }

        lines.append("")
        lines.append("[A structure]")
        lines.append(contentsOf: structuralReport(ad))
        lines.append("")
        lines.append("[B structure]")
        lines.append(contentsOf: structuralReport(bd))

        if ad.count == bd.count {
            let xor = xorData(ad, bd)
            lines.append("")
            lines.append(String(format: "XOR entropy(nonzero window): %.4f", entropy(nonzeroWindow(xor))))
            lines.append("XOR first64: \(hexPrefix(xor, count: 64))")
            for lag in [1, 4, 8, 16, 32, 64, 120, 128, 256] {
                lines.append(String(format: "A autocorr lag=%d equal=%.5f", lag, lagEquality(ad, lag: lag, limit: 131072)))
            }
        }

        lines.append("")
        lines.append("[判定提示]")
        if a.url == b.url && ad.count == bd.count {
            let ratio = minCount == 0 ? 0 : Double(stats.changed) / Double(minCount)
            if prefix == 8 && ratio > 0.90 {
                lines.append("同源仅前8字节固定且正文几乎全部变化：强烈支持 V2 正文含随机化 IV/nonce/每次会话随机过程。")
            } else if prefix > 32 && suffix > 32 && ratio < 0.10 {
                lines.append("同源大部分字节稳定，仅局部窗口变化：更符合固定流/XOR/独立分块编码叠加动态字段，不符合普通 CBC 从变化点后持续扩散。")
            } else {
                lines.append("同源变化模式尚不能单独确定算法，结合导出的 A/B decoded.bin 做离线分析。")
            }
        } else if prefix == 8 && isV2(ad) && isV2(bd) {
            lines.append("不同 V2 源仅共享固定8字节头，确认 3e b7 f6 f4 + LE32(120) 属于协议容器，而非源内容。")
        }
        return lines
    }

    private static func isV2(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let b = [UInt8](data.prefix(8))
        return b[0] == 0x3e && b[1] == 0xb7 && b[2] == 0xf6 && b[3] == 0xf4 && readU32LE(data, 4) == 120
    }

    private static func differenceStats(_ a: Data, _ b: Data) -> (changed: Int, regions: [Range<Int>]) {
        let aa = [UInt8](a), bb = [UInt8](b), n = min(aa.count, bb.count)
        var changed = 0, regions: [Range<Int>] = [], start: Int?
        for i in 0..<n {
            if aa[i] != bb[i] {
                changed += 1
                if start == nil { start = i }
            } else if let s = start {
                regions.append(s..<i); start = nil
            }
        }
        if let s = start { regions.append(s..<n) }
        return (changed, regions)
    }

    private static func commonPrefixLength(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b), n = min(aa.count, bb.count)
        var i = 0; while i < n && aa[i] == bb[i] { i += 1 }; return i
    }

    private static func commonSuffixLength(_ a: Data, _ b: Data) -> Int {
        let aa = [UInt8](a), bb = [UInt8](b), n = min(aa.count, bb.count)
        var i = 0; while i < n && aa[aa.count - 1 - i] == bb[bb.count - 1 - i] { i += 1 }; return i
    }

    private static func xorData(_ a: Data, _ b: Data) -> Data {
        let aa = [UInt8](a), bb = [UInt8](b), n = min(aa.count, bb.count)
        return Data((0..<n).map { aa[$0] ^ bb[$0] })
    }

    private static func nonzeroWindow(_ data: Data) -> Data {
        let b = [UInt8](data)
        guard let first = b.firstIndex(where: { $0 != 0 }), let last = b.lastIndex(where: { $0 != 0 }) else { return Data() }
        return Data(b[first...last])
    }

    private static func duplicateBlockStats(_ data: Data, blockSize: Int) -> (blocks: Int, duplicates: Int) {
        let bytes = [UInt8](data)
        let blocks = min(bytes.count / blockSize, 131072)
        if blocks == 0 { return (0, 0) }
        var seen = Set<UInt64>(), dup = 0
        for n in 0..<blocks {
            var h: UInt64 = 1469598103934665603
            let base = n * blockSize
            for j in 0..<blockSize { h = (h ^ UInt64(bytes[base + j])) &* 1099511628211 }
            if !seen.insert(h).inserted { dup += 1 }
        }
        return (blocks, dup)
    }

    private static func lagEquality(_ data: Data, lag: Int, limit: Int) -> Double {
        let b = [UInt8](data.prefix(limit))
        guard lag > 0, b.count > lag else { return 0 }
        var equal = 0
        for i in lag..<b.count { if b[i] == b[i - lag] { equal += 1 } }
        return Double(equal) / Double(b.count - lag)
    }

    private static func asciiRuns(_ data: Data, minimum: Int, limit: Int) -> [String] {
        let b = [UInt8](data); var out: [String] = [], cur: [UInt8] = []
        func flush() {
            if cur.count >= minimum, out.count < limit { out.append(String(bytes: cur, encoding: .ascii) ?? "") }
            cur.removeAll(keepingCapacity: true)
        }
        for x in b {
            if (32...126).contains(x) { cur.append(x) } else { flush() }
            if out.count >= limit { break }
        }
        flush(); return out
    }

    private static func entropy(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        for b in data { counts[Int(b)] += 1 }
        let total = Double(data.count)
        var h = 0.0
        for c in counts where c > 0 { let p = Double(c) / total; h -= p * log2(p) }
        return h
    }

    private static func printableRatio(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var n = 0
        for b in data where b == 9 || b == 10 || b == 13 || (32...126).contains(b) { n += 1 }
        return Double(n) / Double(data.count)
    }

    private static func readU32LE(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let b = [UInt8](data[offset..<(offset + 4)])
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    private static func extractSourcePayload(_ value: String) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = t.range(of: "source[", options: .caseInsensitive), let e = t.range(of: "]", options: .backwards), s.upperBound <= e.lowerBound {
            return String(t[s.upperBound..<e.lowerBound]).filter { !$0.isWhitespace }
        }
        return t.filter { !$0.isWhitespace }
    }

    private static func decodeBase64Flexible(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let r = s.count % 4; if r != 0 { s += String(repeating: "=", count: 4 - r) }
        return Data(base64Encoded: s, options: .ignoreUnknownCharacters)
    }

    private static func rc4(data: Data, key: Data) -> Data {
        let keyBytes = [UInt8](key); guard !keyBytes.isEmpty else { return data }
        var s = (0...255).map(UInt8.init), j = 0
        for i in 0..<256 { j = (j + Int(s[i]) + Int(keyBytes[i % keyBytes.count])) & 255; s.swapAt(i, j) }
        let input = [UInt8](data); var output = [UInt8](repeating: 0, count: input.count); var i = 0; j = 0
        for n in input.indices { i = (i + 1) & 255; j = (j + Int(s[i])) & 255; s.swapAt(i, j); output[n] = input[n] ^ s[(Int(s[i]) + Int(s[j])) & 255] }
        return Data(output)
    }

    private static func utf8JSON(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data), JSONSerialization.isValidJSONObject(obj), let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func hexPrefix(_ data: Data, count: Int) -> String { data.prefix(count).map { String(format: "%02x", $0) }.joined(separator: " ") }

    private static func hexWindow(_ data: Data, offset: Int, radius: Int) -> String {
        let lo = max(0, offset - radius), hi = min(data.count, offset + radius)
        return "[\(lo)..<\(hi)] " + data.subdata(in: lo..<hi).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private static func textPrefix(_ data: Data, limit: Int) -> String { String(data: data.prefix(limit), encoding: .utf8) ?? "<非 UTF-8>" }
}
