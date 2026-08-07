#include "dirkNativeDump.h"

#include <Windows.h>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace dirkNativeDump {
namespace {

constexpr std::uintptr_t kPreferredImageBase = 0x00400000u;

struct CodeRange {
    const char* name;
    std::uintptr_t referenceAddress;
    std::size_t size;
};

// Addresses are reference-client WoW 1.12.1.5875 virtual addresses. At runtime we
// relocate them from the actual module base, so the dump also works if the image
// was rebased. These ranges are deliberately wider than one function so callers,
// prologues, epilogues and adjacent helper branches are available for analysis.
const CodeRange kRanges[] = {
    {"DynamicObject visual machine (includes 0x5D55C0 / 0x5D57C0 / 0x5D5580)", 0x005D5000u, 0x1000u},
    {"DynamicObject facing/apply path (includes 0x613EF0)", 0x00613C00u, 0x0800u},
    {"Spell effect lifecycle/reap (includes 0x614150)", 0x00614000u, 0x0500u},
    {"Destination spell GO effect path (includes 0x6E8088..0x6E8143)", 0x006E7E00u, 0x0800u},
    {"Area shard/emitter path (includes 0x6ECE30 / 0x6ECF20)", 0x006ECC00u, 0x0800u},
    {"DynamicObject radius emitter placement (includes 0x6EBAD0)", 0x006EB800u, 0x0600u},
    {"World effect transform path (includes 0x7BDD60)", 0x007BDB00u, 0x0800u},
};

std::string directoryOfExecutable() {
    char path[MAX_PATH] = {};
    const DWORD n = GetModuleFileNameA(nullptr, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return std::string();
    std::string out(path, path + n);
    const std::string::size_type slash = out.find_last_of("\\/");
    if (slash == std::string::npos) return std::string(".\\");
    return out.substr(0, slash + 1);
}

bool readablePage(std::uintptr_t address, std::size_t size) {
    std::uintptr_t cur = address;
    const std::uintptr_t end = address + size;
    while (cur < end) {
        MEMORY_BASIC_INFORMATION mbi = {};
        if (VirtualQuery(reinterpret_cast<const void*>(cur), &mbi, sizeof(mbi)) != sizeof(mbi))
            return false;
        if (mbi.State != MEM_COMMIT || (mbi.Protect & PAGE_GUARD) || (mbi.Protect & PAGE_NOACCESS))
            return false;
        const DWORD p = mbi.Protect & 0xFFu;
        const bool readable = p == PAGE_READONLY || p == PAGE_READWRITE || p == PAGE_WRITECOPY
            || p == PAGE_EXECUTE_READ || p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
        if (!readable) return false;
        const std::uintptr_t regionEnd = reinterpret_cast<std::uintptr_t>(mbi.BaseAddress) + mbi.RegionSize;
        if (regionEnd <= cur) return false;
        cur = regionEnd < end ? regionEnd : end;
    }
    return true;
}

void appendHex(std::ostringstream& ss, std::uintptr_t start, const std::vector<std::uint8_t>& bytes) {
    for (std::size_t i = 0; i < bytes.size(); i += 16) {
        ss << std::hex << std::uppercase << std::setfill('0')
           << std::setw(8) << static_cast<unsigned long>(start + i) << "  ";
        for (std::size_t j = 0; j < 16; ++j) {
            if (i + j < bytes.size())
                ss << std::setw(2) << static_cast<unsigned int>(bytes[i + j]) << ' ';
            else
                ss << "   ";
        }
        ss << " |";
        for (std::size_t j = 0; j < 16 && i + j < bytes.size(); ++j) {
            const unsigned char c = bytes[i + j];
            ss << ((c >= 32 && c <= 126) ? static_cast<char>(c) : '.');
        }
        ss << "|\r\n";
    }
    ss << std::dec;
}

bool appendRange(std::ostringstream& ss, std::uintptr_t moduleBase, const CodeRange& range) {
    const std::uintptr_t actual = moduleBase + (range.referenceAddress - kPreferredImageBase);
    ss << "\r\n=== " << range.name << " ===\r\n";
    ss << "reference=0x" << std::hex << std::uppercase << range.referenceAddress
       << " actual=0x" << actual << " size=0x" << range.size << std::dec << "\r\n";

    if (!readablePage(actual, range.size)) {
        ss << "READABLE=0\r\n";
        return false;
    }

    std::vector<std::uint8_t> bytes(range.size);
    SIZE_T got = 0;
    if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(actual),
                           bytes.data(), bytes.size(), &got) || got != bytes.size()) {
        ss << "READPROCESSMEMORY=0 got=" << static_cast<unsigned long>(got) << "\r\n";
        return false;
    }
    ss << "READABLE=1\r\n";
    appendHex(ss, actual, bytes);
    return true;
}

} // namespace

bool dump(std::string& outputPath, std::string& status) {
    outputPath.clear();
    status.clear();

    HMODULE module = GetModuleHandleA(nullptr);
    if (!module) {
        status = "NO_WOW_MODULE";
        return false;
    }
    const std::uintptr_t base = reinterpret_cast<std::uintptr_t>(module);

    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        status = "BAD_DOS_HEADER";
        return false;
    }
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        status = "BAD_NT_HEADER";
        return false;
    }

    std::ostringstream ss;
    ss << "DirkNativeDump v1 - READ ONLY\r\n";
    ss << "Purpose: recover exact WoW client calling conventions for DynamicObject/AreaModel/CEffect.\r\n";
    ss << "No hooks, no writes, no calls into the inspected functions.\r\n\r\n";
    ss << std::hex << std::uppercase;
    ss << "ModuleBase=0x" << base << "\r\n";
    ss << "PreferredImageBase=0x" << kPreferredImageBase << "\r\n";
    ss << "PE.TimeDateStamp=0x" << nt->FileHeader.TimeDateStamp << "\r\n";
    ss << "PE.SizeOfImage=0x" << nt->OptionalHeader.SizeOfImage << "\r\n";
    ss << "PE.CheckSum=0x" << nt->OptionalHeader.CheckSum << "\r\n";
    ss << "EntryPointRVA=0x" << nt->OptionalHeader.AddressOfEntryPoint << "\r\n";
    ss << std::dec;

    unsigned okCount = 0;
    for (const CodeRange& range : kRanges) {
        if (appendRange(ss, base, range)) ++okCount;
    }

    const std::string dir = directoryOfExecutable();
    if (dir.empty()) {
        status = "EXE_DIRECTORY_UNAVAILABLE";
        return false;
    }
    outputPath = dir + "DirkNativeDump.txt";

    std::ofstream file(outputPath.c_str(), std::ios::out | std::ios::binary | std::ios::trunc);
    if (!file) {
        status = "OPEN_OUTPUT_FAILED";
        return false;
    }
    const std::string text = ss.str();
    file.write(text.data(), static_cast<std::streamsize>(text.size()));
    file.flush();
    if (!file.good()) {
        status = "WRITE_OUTPUT_FAILED";
        return false;
    }

    std::ostringstream result;
    result << "DUMP_OK ranges=" << okCount << "/" << (sizeof(kRanges) / sizeof(kRanges[0]));
    status = result.str();
    return okCount != 0;
}

} // namespace dirkNativeDump
