import Foundation
import Security

@MainActor
final class SourceProbeModel: ObservableObject {
    @Published var urlText = "https://qnq.ioswg.com/appstore"
    @Published var isLoading = false
    @Published var output = "等待 QNQ Source Lab v0.7 Original Decoder Reconstruction。"
    @Published var exportReportURL: URL?
    @Published var exportDecodedURL: URL?

    static let plainPreset = "https://raw.githubusercontent.com/maxchang3/ani-altstore-source/main/generated/apps.json"
    static let legacyPreset = "https://sign.io31.top/appstore"
    static let v2Preset = "https://qnq.ioswg.com/appstore"
    static let v2AltPreset = "https://yxy.ioswg.com/appstore"

    func usePlainPreset() { urlText = Self.plainPreset }
    func useLegacyPreset() { urlText = Self.legacyPreset }
    func useV2Preset() { urlText = Self.v2Preset }
    func useV2AltPreset() { urlText = Self.v2AltPreset }

    func runCurrent() async {
        guard let url = Self.checkedURL(urlText) else { output = "❌ URL 无效"; return }
        await run(urls: [url])
    }

    func runAll() async {
        let urls = [Self.plainPreset, Self.legacyPreset, Self.v2Preset, Self.v2AltPreset].compactMap(Self.checkedURL)
        await run(urls: urls)
    }

    private func run(urls: [URL]) async {
        isLoading = true
        exportReportURL = nil
        exportDecodedURL = nil
        defer { isLoading = false }

        var allLines = [
            "QNQ Source Lab v0.7 — Original Decoder Reconstruction",
            "原版处理原则：Plain / appstore / appstore_v2 统一进入 OriginalSourcePipeline",
            ""
        ]
        var lastDecoded: Data?
        for (index, url) in urls.enumerated() {
            if index > 0 {
                allLines.append("")
                allLines.append(String(repeating: "=", count: 56))
                allLines.append("")
            }
            let result = await OriginalSourcePipeline.load(url: url, v2PrivateKeyPEM: Self.loadV2Key())
            allLines.append(contentsOf: result.lines)
            if let decoded = result.decodedJSON { lastDecoded = decoded }
        }
        finish(lines: allLines, decoded: lastDecoded)
    }

    private func finish(lines: [String], decoded: Data?) {
        let report = lines.joined(separator: "\n")
        output = report
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QNQSourceLab-v0.7-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reportURL = dir.appendingPathComponent("v0.7-original-decoder-report.txt")
        try? Data(report.utf8).write(to: reportURL)
        exportReportURL = reportURL
        if let decoded {
            let jsonURL = dir.appendingPathComponent("last-decoded-source.json")
            try? decoded.write(to: jsonURL)
            exportDecodedURL = jsonURL
        }
    }

    func installV2Key(from sourceURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: sourceURL)
        guard String(data: data, encoding: .utf8)?.contains("BEGIN PRIVATE KEY") == true else {
            throw V2DecodeError("不是 PKCS#8 PRIVATE KEY PEM")
        }
        try data.write(to: Self.v2KeyURL, options: .atomic)
        output = "✅ 已导入 appstore_v2.pem：\(data.count) bytes"
    }

    func removeV2Key() {
        try? FileManager.default.removeItem(at: Self.v2KeyURL)
        output = "已移除本地 appstore_v2.pem"
    }

    var hasV2Key: Bool { FileManager.default.fileExists(atPath: Self.v2KeyURL.path) }

    private static var v2KeyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("appstore_v2.pem")
    }

    private static func loadV2Key() -> Data? { try? Data(contentsOf: v2KeyURL) }

    private static func checkedURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

private struct OriginalPipelineResult {
    let lines: [String]
    let decodedJSON: Data?
}

private enum SourceEnvelopeKind: String {
    case plain = "Plain JSON"
    case appstore = "appstore"
    case appstoreV2 = "appstore_v2"
}

private enum OriginalSourcePipeline {
    static func load(url: URL, v2PrivateKeyPEM: Data?) async -> OriginalPipelineResult {
        var lines = ["URL: \(url.absoluteString)"]
        let responseData: Data
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("QNQSourceLab/0.7", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            guard let status = http?.statusCode else {
                lines.append("[1] HTTP ❌ 非 HTTP 响应")
                return OriginalPipelineResult(lines: lines, decodedJSON: nil)
            }
            lines.append("[1] HTTP ✅ status=\(status) bytes=\(data.count) content-type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "?")")
            guard (200...299).contains(status) else {
                lines.append("[1] HTTP ❌ status=\(status)")
                return OriginalPipelineResult(lines: lines, decodedJSON: nil)
            }
            responseData = data
        } catch {
            lines.append("[1] HTTP ❌ \(error.localizedDescription)")
            return OriginalPipelineResult(lines: lines, decodedJSON: nil)
        }

        let outerObject: Any
        do {
            outerObject = try JSONSerialization.jsonObject(with: responseData, options: [.fragmentsAllowed])
        } catch {
            lines.append("[2] Outer detection ❌ outer JSON parse: \(error.localizedDescription)")
            return OriginalPipelineResult(lines: lines, decodedJSON: nil)
        }

        let envelope: SourceEnvelopeKind
        let payload: String?
        if let root = outerObject as? [String: Any], let value = root["appstore_v2"] as? String {
            envelope = .appstoreV2; payload = value
        } else if let root = outerObject as? [String: Any], let value = root["appstore"] as? String {
            envelope = .appstore; payload = value
        } else {
            envelope = .plain; payload = nil
        }
        lines.append("[2] Outer detection ✅ \(envelope.rawValue)")

        switch envelope {
        case .plain:
            lines.append("[3] Envelope decode ✅ skipped (plain JSON)")
            lines.append("[4] Original preprocess ✅ skipped")
            lines.append("[5] Crypto ✅ skipped")
            lines.append("[6] UTF-8 \(String(data: responseData, encoding: .utf8) == nil ? "❌" : "✅") bytes=\(responseData.count)")
            return finishJSON(data: responseData, object: outerObject, lines: lines)

        case .appstore:
            guard let payload else {
                lines.append("[3] Base64 ❌ wrapper value missing")
                return OriginalPipelineResult(lines: lines, decodedJSON: nil)
            }
            guard let decoded = flexibleBase64Decode(payload) else {
                lines.append("[3] Base64 ❌ invalid appstore payload")
                return OriginalPipelineResult(lines: lines, decodedJSON: nil)
            }
            lines.append("[3] Base64 ✅ decoded=\(decoded.count) mod8=\(decoded.count % 8) mod16=\(decoded.count % 16)")
            lines.append("    first32=\(hex(Data(decoded.prefix(32))))")
            lines.append("    last32=\(hex(Data(decoded.suffix(32))))")
            lines.append("[4] Original V1 preprocess ❌ 尚未完成：继续从 +[YYYAppStoreSource modelWithJSON:] 反追真实 appstore 分支输入构造")
            lines.append("[5] Crypto ⏸ 未调用猜测 DES；等待 V1 原版参数链完成")
            lines.append("[6] UTF-8 ⏸")
            lines.append("[7] JSON ⏸")
            lines.append("[8] Repo schema ⏸")
            lines.append("[9] Apps ⏸")
            return OriginalPipelineResult(lines: lines, decodedJSON: nil)

        case .appstoreV2:
            guard let payload else {
                lines.append("[3] V2 codec ❌ wrapper value missing")
                return OriginalPipelineResult(lines: lines, decodedJSON: nil)
            }
            do {
                let raw = try NuosikeAppstoreV2Decoder.decodeCodec(payload)
                lines.append("[3] Original V2 codec ✅ decoded=\(raw.count)")
                let container = try NuosikeAppstoreV2Decoder.parseContainer(raw)
                lines.append("[4] Original V2 preprocess ✅ magic=0x\(String(container.magic, radix: 16)) rsa_len=\(container.rsaBlob.count) payload_len=\(container.payload.count) trailing=\(container.trailingCount)")
                guard let v2PrivateKeyPEM else {
                    lines.append("[5] Crypto / RSA ❌ appstore_v2.pem 未导入")
                    lines.append("[6] UTF-8 ⏸")
                    lines.append("[7] JSON ⏸")
                    lines.append("[8] Repo schema ⏸")
                    lines.append("[9] Apps ⏸")
                    return OriginalPipelineResult(lines: lines, decodedJSON: nil)
                }
                let keyData = try NuosikeAppstoreV2Decoder.rsaDecrypt(container.rsaBlob, privateKeyPEM: v2PrivateKeyPEM)
                guard let keyText = String(data: keyData, encoding: .utf8) else { throw V2DecodeError("RSA plaintext is not UTF-8 RC4 key text") }
                lines.append("[5] Crypto / RSA ✅ key_chars=\(keyText.utf16.count)")
                let jsonData = try NuosikeAppstoreV2Decoder.rc4(container.payload, keyText: keyText)
                guard String(data: jsonData, encoding: .utf8) != nil else { throw V2DecodeError("RC4 plaintext is not UTF-8") }
                lines.append("[5] Crypto / RC4 ✅ plaintext=\(jsonData.count)")
                lines.append("[6] UTF-8 ✅")
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
                return finishJSON(data: jsonData, object: jsonObject, lines: lines)
            } catch {
                lines.append("❌ V2 / \(error.localizedDescription)")
                return OriginalPipelineResult(lines: lines, decodedJSON: nil)
            }
        }
    }

    private static func finishJSON(data: Data, object: Any, lines: [String]) -> OriginalPipelineResult {
        var lines = lines
        lines.append("[7] JSON ✅ top-level=\(typeName(object))")
        if let root = object as? [String: Any] {
            let keys = root.keys.sorted()
            lines.append("[8] Repo schema ✅ keys=\(keys.prefix(12).joined(separator: ","))")
            if let apps = root["apps"] as? [Any] { lines.append("[9] Apps ✅ Apps: \(apps.count)") }
            else { lines.append("[9] Apps ❌ top-level apps[] missing") }
        } else {
            lines.append("[8] Repo schema ❌ expected top-level object")
            lines.append("[9] Apps ❌")
        }
        return OriginalPipelineResult(lines: lines, decodedJSON: data)
    }

    private static func typeName(_ value: Any) -> String {
        if value is [String: Any] { return "object" }
        if value is [Any] { return "array" }
        if value is String { return "string" }
        if value is NSNumber { return "number/bool" }
        if value is NSNull { return "null" }
        return String(describing: type(of: value))
    }

    private static func flexibleBase64Decode(_ value: String) -> Data? {
        let compact = value.components(separatedBy: .whitespacesAndNewlines).joined()
        if let data = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]) { return data }
        var padded = compact.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = padded.count % 4
        if rem != 0 { padded += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: padded, options: [.ignoreUnknownCharacters])
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined(separator: " ") }
}

private struct V2DecodeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct V2Container {
    let magic: UInt32
    let rsaBlob: Data
    let payload: Data
    let trailingCount: Int
}

private enum NuosikeAppstoreV2Decoder {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)
    private static let magic: UInt32 = 0xFEEDFACF

    static func decodeCodec(_ text: String) throws -> Data {
        var lookup = [Int](repeating: -1, count: 256)
        for (index, byte) in alphabet.enumerated() { lookup[Int(byte)] = index }
        var output = Data()
        output.reserveCapacity(text.utf8.count * 3 / 4 + 8)
        var accumulator: UInt64 = 0
        var bitCount = 0
        for (position, byte) in text.utf8.enumerated() {
            let value = byte < 128 ? lookup[Int(byte)] : -1
            guard value >= 0 else { throw V2DecodeError("invalid codec character at index \(position)") }
            let width = (value == 30 || value == 31) ? 5 : 6
            accumulator |= UInt64(value & ((1 << width) - 1)) << UInt64(bitCount)
            bitCount += width
            while bitCount >= 8 {
                output.append(UInt8(accumulator & 0xff))
                accumulator >>= 8
                bitCount -= 8
            }
        }
        if bitCount > 0 { output.append(UInt8(accumulator & 0xff)) }
        return output
    }

    static func parseContainer(_ raw: Data) throws -> V2Container {
        guard raw.count >= 12 else { throw V2DecodeError("container too short: \(raw.count)") }
        let containerMagic = try u32LE(raw, 0)
        guard containerMagic == magic else { throw V2DecodeError("unexpected magic: 0x\(String(containerMagic, radix: 16)); expected 0xfeedfacf") }
        let rsaLength = Int(try u32LE(raw, 4))
        guard rsaLength > 0 else { throw V2DecodeError("invalid RSA blob length: \(rsaLength)") }
        let rsaStart = 8
        let rsaEnd = rsaStart + rsaLength
        guard rsaEnd + 4 <= raw.count else { throw V2DecodeError("RSA blob out of bounds: L1=\(rsaLength), decoded=\(raw.count)") }
        let payloadLength = Int(try u32LE(raw, rsaEnd))
        let payloadStart = rsaEnd + 4
        let payloadEnd = payloadStart + payloadLength
        guard payloadEnd <= raw.count else { throw V2DecodeError("payload out of bounds: L2=\(payloadLength), remaining=\(raw.count - payloadStart)") }
        return V2Container(magic: containerMagic, rsaBlob: raw.subdata(in: rsaStart..<rsaEnd), payload: raw.subdata(in: payloadStart..<payloadEnd), trailingCount: raw.count - payloadEnd)
    }

    static func rsaDecrypt(_ ciphertext: Data, privateKeyPEM: Data) throws -> Data {
        guard let pem = String(data: privateKeyPEM, encoding: .utf8) else { throw V2DecodeError("private key PEM is not UTF-8") }
        let pkcs1 = try extractPKCS1PrivateKey(fromPEM: pem)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048
        ]
        var createError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &createError) else {
            let message = createError?.takeRetainedValue().localizedDescription ?? "unknown SecKeyCreateWithData error"
            throw V2DecodeError("RSA private key import failed: \(message)")
        }
        let blockSize = SecKeyGetBlockSize(key)
        guard blockSize > 0, ciphertext.count % blockSize == 0 else { throw V2DecodeError("RSA ciphertext length \(ciphertext.count) is not a multiple of RSA_size \(blockSize)") }
        var output = Data()
        for offset in stride(from: 0, to: ciphertext.count, by: blockSize) {
            let block = ciphertext.subdata(in: offset..<(offset + blockSize))
            var decryptError: Unmanaged<CFError>?
            guard let plain = SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, block as CFData, &decryptError) as Data? else {
                let message = decryptError?.takeRetainedValue().localizedDescription ?? "unknown RSA decrypt error"
                throw V2DecodeError("RSA PKCS#1 v1.5 decrypt failed at block \(offset / blockSize): \(message)")
            }
            output.append(plain)
        }
        return output
    }

    static func rc4(_ data: Data, keyText: String) throws -> Data {
        let key = keyText.utf16.map { UInt8(truncatingIfNeeded: $0) }
        guard !key.isEmpty else { throw V2DecodeError("empty RC4 key") }
        var state = Array(0...255).map(UInt8.init)
        var j = 0
        for i in 0..<256 {
            j = (j + Int(state[i]) + Int(key[i % key.count])) & 0xff
            state.swapAt(i, j)
        }
        var i = 0
        j = 0
        var output = Data(capacity: data.count)
        for byte in data {
            i = (i + 1) & 0xff
            j = (j + Int(state[i])) & 0xff
            state.swapAt(i, j)
            let k = state[(Int(state[i]) + Int(state[j])) & 0xff]
            output.append(byte ^ k)
        }
        return output
    }

    private static func u32LE(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw V2DecodeError("u32 out of bounds @\(offset)") }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func extractPKCS1PrivateKey(fromPEM pem: String) throws -> Data {
        let body = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined()
        guard let der = Data(base64Encoded: body) else { throw V2DecodeError("invalid PKCS#8 PEM Base64") }
        var outer = DERReader(data: der)
        let sequence = try outer.read(expectedTag: 0x30)
        var inner = DERReader(data: sequence)
        _ = try inner.read(expectedTag: 0x02)
        _ = try inner.read(expectedTag: 0x30)
        return try inner.read(expectedTag: 0x04)
    }
}

private struct DERReader {
    let data: Data
    var index = 0

    mutating func read(expectedTag: UInt8) throws -> Data {
        guard index < data.count else { throw V2DecodeError("DER truncated before tag") }
        let tag = data[index]
        index += 1
        guard tag == expectedTag else { throw V2DecodeError("DER tag mismatch: got 0x\(String(tag, radix: 16)), expected 0x\(String(expectedTag, radix: 16))") }
        let length = try readLength()
        guard length >= 0, index + length <= data.count else { throw V2DecodeError("DER value out of bounds") }
        let value = data.subdata(in: index..<(index + length))
        index += length
        return value
    }

    private mutating func readLength() throws -> Int {
        guard index < data.count else { throw V2DecodeError("DER truncated before length") }
        let first = data[index]
        index += 1
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7f)
        guard count > 0, count <= MemoryLayout<Int>.size, index + count <= data.count else { throw V2DecodeError("unsupported DER length") }
        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}
