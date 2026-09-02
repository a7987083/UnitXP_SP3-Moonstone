import Foundation

struct MachOSliceInfo: Identifiable {
    let id = UUID()
    let architecture: String
    let fileOffset: UInt64
    let fileSize: UInt64
    let uuid: String
    let encrypted: Bool
    let segments: [MachOSegment]
    let headerVMAddress: UInt64

    struct MachOSegment {
        let name: String
        let vmAddress: UInt64
        let vmSize: UInt64
        let fileOffset: UInt64
        let fileSize: UInt64
    }

    func fileOffset(forRVA rva: UInt64, length: UInt64) -> UInt64? {
        let targetResult = headerVMAddress.addingReportingOverflow(rva)
        guard !targetResult.overflow else { return nil }
        let target = targetResult.partialValue
        let targetEnd = target.addingReportingOverflow(length)
        guard !targetEnd.overflow else { return nil }

        for segment in segments {
            let vmEnd = segment.vmAddress.addingReportingOverflow(segment.fileSize)
            guard !vmEnd.overflow,
                  target >= segment.vmAddress,
                  targetEnd.partialValue <= vmEnd.partialValue else { continue }
            let delta = target - segment.vmAddress
            let local = segment.fileOffset.addingReportingOverflow(delta)
            guard !local.overflow else { return nil }
            let absolute = fileOffset.addingReportingOverflow(local.partialValue)
            return absolute.overflow ? nil : absolute.partialValue
        }
        return nil
    }
}

enum MachOInspectionError: LocalizedError {
    case invalid(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .io(let message): return message
        }
    }
}

final class MachOInspector {
    private static let mhMagic64: UInt32 = 0xfeedfacf
    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatMagic64: UInt32 = 0xcafebabf
    private static let cpuTypeArm64: UInt32 = 0x0100000c
    private static let cpuSubtypeMask: UInt32 = 0xff000000
    private static let cpuSubtypeArm64e: UInt32 = 2
    private static let lcSegment64: UInt32 = 0x19
    private static let lcUUID: UInt32 = 0x1b
    private static let lcEncryptionInfo64: UInt32 = 0x2c

    static func inspect(_ url: URL) throws -> [MachOSliceInfo] {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw MachOInspectionError.io("无法读取 Mach-O：\(url.lastPathComponent)") }
        defer { try? handle.close() }

        let prefix = try read(handle, offset: 0, count: 8)
        guard prefix.count == 8 else { throw MachOInspectionError.invalid("文件不是完整 Mach-O") }
        let littleMagic = prefix.u32LE(0)
        let bigMagic = prefix.u32BE(0)

        if littleMagic == mhMagic64 {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            return [try parseSlice(handle, fileOffset: 0, fileSize: size)]
        }

        guard bigMagic == fatMagic || bigMagic == fatMagic64 else {
            throw MachOInspectionError.invalid("不支持的 Mach-O 格式：\(url.lastPathComponent)")
        }
        let count = Int(prefix.u32BE(4))
        guard count > 0, count <= 32 else { throw MachOInspectionError.invalid("Fat Mach-O Slice 数量异常") }
        let is64 = bigMagic == fatMagic64
        let entrySize = is64 ? 32 : 20
        let table = try read(handle, offset: 8, count: count * entrySize)
        var result: [MachOSliceInfo] = []
        for index in 0..<count {
            let base = index * entrySize
            let cpuType = table.u32BE(base)
            guard cpuType == cpuTypeArm64 else { continue }
            let offset = is64 ? table.u64BE(base + 8) : UInt64(table.u32BE(base + 8))
            let size = is64 ? table.u64BE(base + 16) : UInt64(table.u32BE(base + 12))
            result.append(try parseSlice(handle, fileOffset: offset, fileSize: size))
        }
        guard !result.isEmpty else { throw MachOInspectionError.invalid("没有 arm64/arm64e Slice") }
        return result
    }

    static func bytes(at absoluteOffset: UInt64, count: Int, in url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try read(handle, offset: absoluteOffset, count: count)
    }

    private static func parseSlice(_ handle: FileHandle, fileOffset: UInt64, fileSize: UInt64) throws -> MachOSliceInfo {
        let header = try read(handle, offset: fileOffset, count: 32)
        guard header.count == 32, header.u32LE(0) == mhMagic64 else {
            throw MachOInspectionError.invalid("Slice 不是 arm64 Mach-O")
        }
        let cpuType = header.u32LE(4)
        guard cpuType == cpuTypeArm64 else { throw MachOInspectionError.invalid("Slice 架构不是 ARM64") }
        let subtype = header.u32LE(8) & ~cpuSubtypeMask
        let architecture = subtype == cpuSubtypeArm64e ? "arm64e" : "arm64"
        let commandCount = Int(header.u32LE(16))
        let commandBytes = Int(header.u32LE(20))
        guard commandCount > 0, commandCount <= 65535, commandBytes >= 8, commandBytes <= 16 * 1024 * 1024 else {
            throw MachOInspectionError.invalid("Mach-O Load Commands 异常")
        }
        let commands = try read(handle, offset: fileOffset + 32, count: commandBytes)
        var cursor = 0
        var uuid = ""
        var encrypted = false
        var segments: [MachOSliceInfo.MachOSegment] = []
        var headerVMAddress: UInt64?

        for _ in 0..<commandCount {
            guard cursor + 8 <= commands.count else { throw MachOInspectionError.invalid("Load Command 越界") }
            let command = commands.u32LE(cursor)
            let size = Int(commands.u32LE(cursor + 4))
            guard size >= 8, cursor + size <= commands.count else {
                throw MachOInspectionError.invalid("Load Command 长度异常")
            }
            if command == lcUUID, size >= 24 {
                uuid = commands.subdata(in: (cursor + 8)..<(cursor + 24)).map { String(format: "%02X", $0) }.joined()
            } else if command == lcEncryptionInfo64, size >= 24 {
                encrypted = commands.u32LE(cursor + 16) != 0
            } else if command == lcSegment64, size >= 72 {
                let nameData = commands.subdata(in: (cursor + 8)..<(cursor + 24))
                let name = String(bytes: nameData.prefix { $0 != 0 }, encoding: .utf8) ?? "?"
                let vmAddress = commands.u64LE(cursor + 24)
                let vmSize = commands.u64LE(cursor + 32)
                let segmentFileOffset = commands.u64LE(cursor + 40)
                let segmentFileSize = commands.u64LE(cursor + 48)
                segments.append(.init(name: name,
                                      vmAddress: vmAddress,
                                      vmSize: vmSize,
                                      fileOffset: segmentFileOffset,
                                      fileSize: segmentFileSize))
                if segmentFileOffset == 0, segmentFileSize > 0 { headerVMAddress = vmAddress }
            }
            cursor += size
        }

        guard uuid.count == 32 else { throw MachOInspectionError.invalid("Mach-O 没有有效 UUID") }
        guard let headerVMAddress else { throw MachOInspectionError.invalid("Mach-O 没有 Header Segment") }
        return MachOSliceInfo(architecture: architecture,
                              fileOffset: fileOffset,
                              fileSize: fileSize,
                              uuid: uuid,
                              encrypted: encrypted,
                              segments: segments,
                              headerVMAddress: headerVMAddress)
    }

    private static func read(_ handle: FileHandle, offset: UInt64, count: Int) throws -> Data {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw MachOInspectionError.io("读取 Mach-O 数据不完整")
            }
            return data
        } catch let error as MachOInspectionError {
            throw error
        } catch {
            throw MachOInspectionError.io("读取 Mach-O 失败：\(error.localizedDescription)")
        }
    }
}

private extension Data {
    func u32LE(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) |
        (UInt32(self[offset + 1]) << 8) |
        (UInt32(self[offset + 2]) << 16) |
        (UInt32(self[offset + 3]) << 24)
    }

    func u32BE(_ offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) |
        (UInt32(self[offset + 1]) << 16) |
        (UInt32(self[offset + 2]) << 8) |
        UInt32(self[offset + 3])
    }

    func u64LE(_ offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<8 { result |= UInt64(self[offset + index]) << UInt64(index * 8) }
        return result
    }

    func u64BE(_ offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<8 { result = (result << 8) | UInt64(self[offset + index]) }
        return result
    }
}
