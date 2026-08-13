#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
scanner = root / "MoonMarkerM2Scanner.cpp"
if not scanner.exists():
    raise SystemExit(f"missing required source: {scanner}")

s = scanner.read_text(encoding="utf-8")

def replace_once(old, new, label):
    global s
    n=s.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {n}")
    s=s.replace(old,new,1)

marker = '''bool readArchiveListfile(const std::string& archivePath) {\n'''
helper = r'''
// R7.5.2 fallback for small/custom MPQs whose embedded (listfile) cannot be
// opened by the client's legacy SFile path.  This does NOT enumerate unknown
// names from MPQ hashes; it only reads a physically stored (listfile).
// Supported fallback payload: classic MPQ v0 with an unencrypted,
// uncompressed (listfile), including SINGLE_UNIT files.  Official archives
// still use the normal client SFile path first.
std::uint32_t readLe32(const unsigned char* p) {
    return static_cast<std::uint32_t>(p[0])
        | (static_cast<std::uint32_t>(p[1]) << 8u)
        | (static_cast<std::uint32_t>(p[2]) << 16u)
        | (static_cast<std::uint32_t>(p[3]) << 24u);
}

std::uint16_t readLe16(const unsigned char* p) {
    return static_cast<std::uint16_t>(p[0])
        | static_cast<std::uint16_t>(static_cast<std::uint16_t>(p[1]) << 8u);
}

const std::uint32_t* mpqCryptTable() {
    static std::uint32_t table[0x500] = {};
    static bool ready = false;
    if (ready) return table;
    std::uint32_t seed = 0x00100001u;
    for (std::uint32_t i = 0; i < 0x100u; ++i) {
        for (std::uint32_t j = 0; j < 5u; ++j) {
            const std::uint32_t index = i + (j * 0x100u);
            seed = (seed * 125u + 3u) % 0x2AAAABu;
            const std::uint32_t high = (seed & 0xFFFFu) << 16u;
            seed = (seed * 125u + 3u) % 0x2AAAABu;
            table[index] = high | (seed & 0xFFFFu);
        }
    }
    ready = true;
    return table;
}

std::uint32_t mpqHashString(const std::string& input, const std::uint32_t type) {
    const std::uint32_t* table = mpqCryptTable();
    std::uint32_t seed1 = 0x7FED7FEDu;
    std::uint32_t seed2 = 0xEEEEEEEEu;
    for (unsigned char raw : input) {
        unsigned char ch = raw;
        if (ch == '/') ch = '\\';
        if (ch >= 'a' && ch <= 'z') ch = static_cast<unsigned char>(ch - 'a' + 'A');
        seed1 = table[(type << 8u) + ch] ^ (seed1 + seed2);
        seed2 = static_cast<std::uint32_t>(ch) + seed1 + seed2 + (seed2 << 5u) + 3u;
    }
    return seed1;
}

void mpqDecryptDwords(std::vector<unsigned char>& bytes, const std::uint32_t key) {
    const std::uint32_t* table = mpqCryptTable();
    std::uint32_t seed1 = key;
    std::uint32_t seed2 = 0xEEEEEEEEu;
    const std::size_t count = bytes.size() / 4u;
    for (std::size_t i = 0; i < count; ++i) {
        seed2 += table[0x400u + (seed1 & 0xFFu)];
        const std::size_t pos = i * 4u;
        const std::uint32_t value = readLe32(bytes.data() + pos);
        const std::uint32_t plain = value ^ (seed1 + seed2);
        bytes[pos + 0u] = static_cast<unsigned char>(plain & 0xFFu);
        bytes[pos + 1u] = static_cast<unsigned char>((plain >> 8u) & 0xFFu);
        bytes[pos + 2u] = static_cast<unsigned char>((plain >> 16u) & 0xFFu);
        bytes[pos + 3u] = static_cast<unsigned char>((plain >> 24u) & 0xFFu);
        seed1 = ((~seed1 << 21u) + 0x11111111u) | (seed1 >> 11u);
        seed2 = plain + seed2 + (seed2 << 5u) + 3u;
    }
}

bool readDiskRange(std::ifstream& input, const std::uint32_t offset,
                   const std::size_t size, std::vector<unsigned char>& out) {
    if (size == 0u || size > kMaxListfileBytes) return false;
    input.clear();
    input.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!input) return false;
    out.resize(size);
    input.read(reinterpret_cast<char*>(out.data()), static_cast<std::streamsize>(size));
    return input.gcount() == static_cast<std::streamsize>(size);
}

bool readRawClassicMpqListfile(const std::string& archivePath, std::vector<char>& out) {
    std::ifstream input(archivePath, std::ios::binary);
    if (!input) return false;
    input.seekg(0, std::ios::end);
    const std::streamoff diskSize = input.tellg();
    if (diskSize < 32) return false;
    input.seekg(0, std::ios::beg);

    unsigned char header[32] = {};
    input.read(reinterpret_cast<char*>(header), sizeof(header));
    if (input.gcount() != static_cast<std::streamsize>(sizeof(header))) return false;
    if (header[0] != 'M' || header[1] != 'P' || header[2] != 'Q' || header[3] != 0x1Au) return false;

    const std::uint32_t headerSize = readLe32(header + 4u);
    const std::uint32_t archiveSize = readLe32(header + 8u);
    const std::uint16_t formatVersion = readLe16(header + 12u);
    const std::uint32_t hashOffset = readLe32(header + 16u);
    const std::uint32_t blockOffset = readLe32(header + 20u);
    const std::uint32_t hashCount = readLe32(header + 24u);
    const std::uint32_t blockCount = readLe32(header + 28u);
    if (headerSize < 32u || formatVersion != 0u || archiveSize < headerSize) return false;
    if (archiveSize > static_cast<std::uint64_t>(diskSize)) return false;
    if (hashCount == 0u || hashCount > (1u << 20u) || blockCount == 0u || blockCount > (1u << 20u)) return false;

    const std::uint64_t hashBytes64 = static_cast<std::uint64_t>(hashCount) * 16u;
    const std::uint64_t blockBytes64 = static_cast<std::uint64_t>(blockCount) * 16u;
    if (hashOffset + hashBytes64 > archiveSize || blockOffset + blockBytes64 > archiveSize) return false;

    std::vector<unsigned char> hashBytes;
    std::vector<unsigned char> blockBytes;
    if (!readDiskRange(input, hashOffset, static_cast<std::size_t>(hashBytes64), hashBytes)) return false;
    if (!readDiskRange(input, blockOffset, static_cast<std::size_t>(blockBytes64), blockBytes)) return false;
    mpqDecryptDwords(hashBytes, mpqHashString("(hash table)", 3u));
    mpqDecryptDwords(blockBytes, mpqHashString("(block table)", 3u));

    const std::string wanted = "(listfile)";
    const std::uint32_t wantedA = mpqHashString(wanted, 1u);
    const std::uint32_t wantedB = mpqHashString(wanted, 2u);
    const std::uint32_t start = mpqHashString(wanted, 0u) % hashCount;
    std::uint32_t blockIndex = 0xFFFFFFFFu;
    for (std::uint32_t probe = 0u; probe < hashCount; ++probe) {
        const std::uint32_t slot = (start + probe) % hashCount;
        const unsigned char* row = hashBytes.data() + static_cast<std::size_t>(slot) * 16u;
        const std::uint32_t index = readLe32(row + 12u);
        if (index == 0xFFFFFFFFu) break;
        if (index == 0xFFFFFFFEu) continue;
        if (readLe32(row + 0u) == wantedA && readLe32(row + 4u) == wantedB) {
            blockIndex = index;
            break;
        }
    }
    if (blockIndex >= blockCount) return false;

    const unsigned char* block = blockBytes.data() + static_cast<std::size_t>(blockIndex) * 16u;
    const std::uint32_t fileOffset = readLe32(block + 0u);
    const std::uint32_t compressedSize = readLe32(block + 4u);
    const std::uint32_t fileSize = readLe32(block + 8u);
    const std::uint32_t flags = readLe32(block + 12u);
    constexpr std::uint32_t kMpqExists = 0x80000000u;
    constexpr std::uint32_t kMpqEncrypted = 0x00010000u;
    constexpr std::uint32_t kMpqImplode = 0x00000100u;
    constexpr std::uint32_t kMpqCompress = 0x00000200u;
    if ((flags & kMpqExists) == 0u || (flags & kMpqEncrypted) != 0u) return false;
    if (fileSize == 0u || fileSize > kMaxListfileBytes) return false;
    if (compressedSize != fileSize || (flags & (kMpqImplode | kMpqCompress)) != 0u) return false;
    if (static_cast<std::uint64_t>(fileOffset) + fileSize > archiveSize) return false;

    std::vector<unsigned char> payload;
    if (!readDiskRange(input, fileOffset, fileSize, payload)) return false;
    out.assign(payload.begin(), payload.end());
    return true;
}

bool tryRawClassicListfileFallback(const std::string& archivePath) {
    std::vector<char> bytes;
    if (!readRawClassicMpqListfile(archivePath, bytes) || bytes.empty()) return false;
    parseListfile(bytes.data(), bytes.size(), fileNameOnly(archivePath));
    gLastError.clear();
    return true;
}
'''
replace_once(marker, helper + '\n' + marker, 'raw MPQ helper insertion')

# Redirect all normal SFile failure paths to the raw classic MPQ fallback.
repls = [
('''        gLastError = "SFILE_UNAVAILABLE";\n        return false;''', '''        gLastError = "SFILE_UNAVAILABLE";\n        return tryRawClassicListfileFallback(archivePath);''', 'SFile unavailable fallback'),
('''        gLastError = "OPEN_ARCHIVE_FAILED: " + fileNameOnly(archivePath);\n        return false;''', '''        gLastError = "OPEN_ARCHIVE_FAILED: " + fileNameOnly(archivePath);\n        return tryRawClassicListfileFallback(archivePath);''', 'open archive fallback'),
('''        gLastError = "NO_LISTFILE: " + fileNameOnly(archivePath);\n        return false;''', '''        gLastError = "NO_LISTFILE: " + fileNameOnly(archivePath);\n        return tryRawClassicListfileFallback(archivePath);''', 'no listfile fallback'),
('''        gLastError = "LISTFILE_SIZE_REJECTED: " + fileNameOnly(archivePath);\n        return false;''', '''        gLastError = "LISTFILE_SIZE_REJECTED: " + fileNameOnly(archivePath);\n        return tryRawClassicListfileFallback(archivePath);''', 'size fallback'),
('''        gLastError = "READ_LISTFILE_FAILED: " + fileNameOnly(archivePath);\n        return false;''', '''        gLastError = "READ_LISTFILE_FAILED: " + fileNameOnly(archivePath);\n        return tryRawClassicListfileFallback(archivePath);''', 'read fallback'),
]
for old,new,label in repls:
    replace_once(old,new,label)

scanner.write_text(s, encoding='utf-8')
print('Applied AutoRange R7.5.2 classic MPQ raw (listfile) fallback')
