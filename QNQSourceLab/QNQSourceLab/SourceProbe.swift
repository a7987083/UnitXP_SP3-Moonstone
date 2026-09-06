import Foundation
import CommonCrypto

@MainActor
final class SourceProbeModel: ObservableObject {
    @Published var urlText = "https://sign.io31.top/appstore"
    @Published var isLoading = false
    @Published var output = "等待真实解密测试。"
    @Published var exportReportURL: URL?
    @Published var exportPayloadURL: URL?
    @Published var exportSegment1URL: URL?
    @Published var exportSegment2URL: URL?
    @Published var exportPlainURL: URL?

    private struct Sample {
        let url: URL
        let status: Int?
        let contentType: String?
        let responseBytes: Int
        let wrapper: String
        let payload: String
        let decoded: Data?
    }

    private struct DecodeOutcome {
        var lines: [String]
        var plain: Data?
        var segment1: Data?
        var segment2: Data?
        var appCount: Int?
    }

    private struct JSONInfo {
        let appCount: Int
        let name: String?
        let data: Data
    }

    func useLegacyPreset() { urlText = "https://sign.io31.top/appstore" }
    func useV2Preset() { urlText = "https://qnq.ioswg.com/appstore" }
    func useV2AltPreset() { urlText = "https://yxy.ioswg.com/appstore" }

    func run() async {
        guard let url = checkedURL(urlText) else { output = "URL 无效"; return }
        await perform(url: url)
    }

    func runLegacy() async {
        urlText = "https://sign.io31.top/appstore"
        await perform(url: URL(string: urlText)!)
    }

    func runV2Qnq() async {
        urlText = "https://qnq.ioswg.com/appstore"
        await perform(url: URL(string: urlText)!)
    }

    func runV2Yxy() async {
        urlText = "https://yxy.ioswg.com/appstore"
        await perform(url: URL(string: urlText)!)
    }

    private func checkedURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func perform(url: URL) async {
        isLoading = true
        clearExports()
        defer { isLoading = false }

        do {
            let sample = try await Self.fetchSampleWithRetry(url)
            var lines = [
                "QNQ Source Lab v0.5",
                "URL: \(sample.url.absoluteString)",
                "HTTP: \(sample.status.map { String($0) } ?? "?")",
                "Content-Type: \(sample.contentType ?? "?")",
                "Response bytes: \(sample.responseBytes)",
                "Wrapper: \(sample.wrapper)",
                "Payload chars: \(sample.payload.count)"
            ]

            guard let decoded = sample.decoded else {
                lines.append("❌ Base64 decode failed after retry")
                output = lines.joined(separator: "\n")
                saveExports(report: output, payload: nil, outcome: nil)
                return
            }

            lines.append("Base64 decoded: \(decoded.count) bytes")
            let outcome: DecodeOutcome
            switch sample.wrapper {
            case "appstore": outcome = Self.decodeLegacy(decoded)
            case "appstore_v2": outcome = Self.decodeV2(decoded)
            default:
                outcome = DecodeOutcome(lines: ["❌ Unsupported wrapper"], plain: nil, segment1: nil, segment2: nil, appCount: nil)
            }
            lines.append(contentsOf: outcome.lines)
            output = lines.joined(separator: "\n")
            saveExports(report: output, payload: decoded, outcome: outcome)
        } catch {
            output = "QNQ Source Lab v0.5\n❌ 请求失败: \(error.localizedDescription)"
        }
    }

    private func clearExports() {
        exportReportURL = nil
        exportPayloadURL = nil
        exportSegment1URL = nil
        exportSegment2URL = nil
        exportPlainURL = nil
    }

    private func saveExports(report: String, payload: Data?, outcome: DecodeOutcome?) {
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QNQSourceLab-v0.5-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let reportURL = dir.appendingPathComponent("decrypt-report.txt")
        try? Data(report.utf8).write(to: reportURL)
        exportReportURL = reportURL

        if let payload {
            let url = dir.appendingPathComponent("payload-decoded.bin")
            try? payload.write(to: url)
            exportPayloadURL = url
        }
        if let data = outcome?.segment1 {
            let url = dir.appendingPathComponent("v2-segment1.bin")
            try? data.write(to: url)
            exportSegment1URL = url
        }
        if let data = outcome?.segment2 {
            let url = dir.appendingPathComponent("v2-segment2.bin")
            try? data.write(to: url)
            exportSegment2URL = url
        }
        if let data = outcome?.plain {
            let url = dir.appendingPathComponent("decrypted-plain.json")
            try? data.write(to: url)
            exportPlainURL = url
        }
    }

    // MARK: - Network / wrapper

    private static func fetchSampleWithRetry(_ url: URL) async throws -> Sample {
        var last: Sample?
        for attempt in 0..<3 {
            let sample = try await fetchSample(url)
            last = sample
            if sample.decoded != nil { return sample }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 350_000_000) }
        }
        return last!
    }

    private static func fetchSample(_ url: URL) async throws -> Sample {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("QNQSourceLab/0.5", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            return Sample(url: url, status: http?.statusCode, contentType: http?.value(forHTTPHeaderField: "Content-Type"), responseBytes: data.count, wrapper: "<outer-json-failed>", payload: "", decoded: nil)
        }

        let wrapper: String
        if root["appstore_v2"] is String { wrapper = "appstore_v2" }
        else if root["appstore"] is String { wrapper = "appstore" }
        else { wrapper = "<unknown>" }

        let payload = root[wrapper] as? String ?? ""
        return Sample(
            url: url,
            status: http?.statusCode,
            contentType: http?.value(forHTTPHeaderField: "Content-Type"),
            responseBytes: data.count,
            wrapper: wrapper,
            payload: payload,
            decoded: decodeBase64Flexible(payload)
        )
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

    // MARK: - appstore v1

    private static func decodeLegacy(_ decoded: Data) -> DecodeOutcome {
        var lines = ["", "[appstore / v1]"]
        lines.append("Decoded mod8: \(decoded.count % 8)")
        lines.append("Prefix: \(hex(decoded.prefix(24)))")

        // Original NSKSign static 24-byte material recovered from its decrypt path.
        // bytes 0..<8 = DES key, bytes 8..<16 = IV; keep historical ASCII pair
        // as a comparison candidate until the full envelope preprocessing is proven.
        let originalMaterial = Data([
            0x12, 0x92, 0xf1, 0xb7, 0xbf, 0x4d, 0x9d, 0x9c,
            0xfa, 0xbd, 0x74, 0x2d, 0x01, 0xd2, 0x54, 0x08,
            0x1f, 0xee, 0x10, 0xfa, 0x2a, 0x35, 0xf1, 0x22
        ])
        let keySets: [(String, Data, Data)] = [
            ("NSKSign-static", originalMaterial.subdata(in: 0..<8), originalMaterial.subdata(in: 8..<16)),
            ("legacy-ascii", Data("esign_so".utf8), Data("urce_enc".utf8))
        ]

        var tried = 0
        for (keyName, key, iv) in keySets {
            var ranges: [(Int, Int)] = [(0, 0)]
            for prefix in 0...32 {
                for suffix in 0...32 where prefix != 0 || suffix != 0 {
                    let length = decoded.count - prefix - suffix
                    if length > 0 && length % kCCBlockSizeDES == 0 { ranges.append((prefix, suffix)) }
                }
            }

            for (prefix, suffix) in ranges {
                guard prefix + suffix < decoded.count else { continue }
                let end = decoded.count - suffix
                let cipher = decoded.subdata(in: prefix..<end)
                guard cipher.count % kCCBlockSizeDES == 0 else { continue }
                tried += 1
                guard let plain = desCBCDecrypt(cipher, key: key, iv: iv) else { continue }
                if let info = findRepositoryJSON(in: plain) {
                    lines.append("✅ DES: OK")
                    lines.append("✅ Key material: \(keyName)")
                    lines.append("✅ Envelope trim: prefix=\(prefix), suffix=\(suffix)")
                    lines.append("✅ JSON: OK")
                    if let name = info.name { lines.append("✅ Source: \(name)") }
                    lines.append("✅ Apps: \(info.appCount)")
                    return DecodeOutcome(lines: lines, plain: info.data, segment1: nil, segment2: nil, appCount: info.appCount)
                }
            }
        }

        lines.append("DES candidates tried: \(tried)")
        lines.append("❌ V1 preprocessing/decrypt failed")
        lines.append("结论: DES 核心已进入真实验证，但当前响应仍存在尚未还原的 envelope/preprocessing。")
        return DecodeOutcome(lines: lines, plain: nil, segment1: nil, segment2: nil, appCount: nil)
    }

    private static func desCBCDecrypt(_ encrypted: Data, key: Data, iv: Data) -> Data? {
        guard key.count == kCCKeySizeDES, iv.count == kCCBlockSizeDES, !encrypted.isEmpty, encrypted.count % kCCBlockSizeDES == 0 else { return nil }
        let outputCapacity = encrypted.count + kCCBlockSizeDES
        var output = Data(count: outputCapacity)
        var moved = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            encrypted.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmDES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeDES,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            encrypted.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, moved > 0 else { return nil }
        output.removeSubrange(moved..<output.count)
        return output
    }

    // MARK: - appstore_v2

    private static func decodeV2(_ decoded: Data) -> DecodeOutcome {
        var lines = ["", "[appstore_v2]"]
        guard decoded.count >= 12 else {
            lines.append("❌ Envelope too short")
            return DecodeOutcome(lines: lines, plain: nil, segment1: nil, segment2: nil, appCount: nil)
        }

        let magic = decoded.prefix(4)
        let expected = Data([0x3e, 0xb7, 0xf6, 0xf4])
        guard Data(magic) == expected else {
            lines.append("❌ Magic mismatch: \(hex(magic))")
            return DecodeOutcome(lines: lines, plain: nil, segment1: nil, segment2: nil, appCount: nil)
        }
        lines.append("✅ Magic: 3e b7 f6 f4")

        guard let firstLength32 = readU32LE(decoded, at: 4) else {
            lines.append("❌ Segment1 length missing")
            return DecodeOutcome(lines: lines, plain: nil, segment1: nil, segment2: nil, appCount: nil)
        }
        let firstLength = Int(firstLength32)
        let firstStart = 8
        let firstEnd = firstStart + firstLength
        guard firstLength > 0, firstEnd + 4 <= decoded.count else {
            lines.append("❌ Segment1 bounds invalid: \(firstLength)")
            return DecodeOutcome(lines: lines, plain: nil, segment1: nil, segment2: nil, appCount: nil)
        }
        let segment1 = decoded.subdata(in: firstStart..<firstEnd)
        lines.append("✅ Segment1: \(segment1.count) bytes")

        guard let secondLength32 = readU32LE(decoded, at: firstEnd) else {
            lines.append("❌ Segment2 length missing @\(firstEnd)")
            return DecodeOutcome(lines: lines, plain: nil, segment1: segment1, segment2: nil, appCount: nil)
        }
        let secondLength = Int(secondLength32)
        let secondStart = firstEnd + 4
        guard secondLength > 0, secondStart <= decoded.count, secondLength <= decoded.count - secondStart else {
            lines.append("❌ Segment2 bounds invalid: declared=\(secondLength), remain=\(decoded.count - secondStart)")
            return DecodeOutcome(lines: lines, plain: nil, segment1: segment1, segment2: nil, appCount: nil)
        }
        let segment2 = decoded.subdata(in: secondStart..<(secondStart + secondLength))
        lines.append("✅ Segment2: \(segment2.count) bytes")
        if secondStart + secondLength < decoded.count {
            lines.append("Trailing bytes: \(decoded.count - secondStart - secondLength)")
        }

        // Original client sends segment2 through an RC4-family routine. The
        // remaining unknown is segment1 -> NSString key/material derivation.
        // Accept success ONLY if the candidate yields a real repository JSON.
        let candidateKeys: [(String, Data)] = [
            ("segment1/raw", segment1),
            ("segment1/base64-text", Data(segment1.base64EncodedString().utf8))
        ]

        for (label, key) in candidateKeys where !key.isEmpty {
            let plain = rc4(segment2, key: key)
            if let info = findRepositoryJSON(in: plain) {
                lines.append("✅ Key derivation candidate: \(label)")
                lines.append("✅ RC4-family decrypt: OK")
                lines.append("✅ JSON: OK")
                if let name = info.name { lines.append("✅ Source: \(name)") }
                lines.append("✅ Apps: \(info.appCount)")
                return DecodeOutcome(lines: lines, plain: info.data, segment1: segment1, segment2: segment2, appCount: info.appCount)
            }
        }

        lines.append("❌ Key derivation unresolved")
        lines.append("RC4-family core已执行真实候选，但没有得到可验证 Repo JSON。")
        return DecodeOutcome(lines: lines, plain: nil, segment1: segment1, segment2: segment2, appCount: nil)
    }

    private static func rc4(_ data: Data, key: Data) -> Data {
        let keyBytes = [UInt8](key)
        guard !keyBytes.isEmpty else { return Data() }
        var state = Array(0...255).map { UInt8($0) }
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
            let k = state[(Int(state[i]) + Int(state[j])) & 0xff]
            output[index] = input[index] ^ k
        }
        return Data(output)
    }

    // MARK: - JSON validation

    private static func findRepositoryJSON(in input: Data) -> JSONInfo? {
        var candidates: [Data] = [input]
        if input.count > 16 { candidates.append(input.subdata(in: 16..<input.count)) }

        if let marker = input.prefix(96).firstIndex(where: { $0 == 0x7b || $0 == 0x5b }), marker > input.startIndex {
            candidates.append(input.subdata(in: marker..<input.endIndex))
        }

        for candidate in candidates {
            if let info = repositoryJSON(candidate) { return info }
        }
        return nil
    }

    private static func repositoryJSON(_ data: Data) -> JSONInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let root = object as? [String: Any] {
            if let apps = root["apps"] as? [Any] {
                return JSONInfo(appCount: apps.count, name: root["name"] as? String, data: data)
            }
            if let content = root["content"] as? String, let nested = decodeBase64Flexible(content), let info = repositoryJSON(nested) {
                return info
            }
            if let nested = root["data"] as? [String: Any], let apps = nested["apps"] as? [Any], let normalized = try? JSONSerialization.data(withJSONObject: nested) {
                return JSONInfo(appCount: apps.count, name: nested["name"] as? String, data: normalized)
            }
        }
        return nil
    }

    private static func readU32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let bytes = [UInt8](data[offset..<(offset + 4)])
        return UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }

    private static func hex<T: DataProtocol>(_ data: T) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
