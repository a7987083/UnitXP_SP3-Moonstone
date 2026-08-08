#include "dirkNativeDumpV3.h"

#include <Windows.h>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace dirkNativeDumpV3 {
namespace {

std::string exeDir() {
    char p[MAX_PATH] = {};
    DWORD n = GetModuleFileNameA(nullptr, p, MAX_PATH);
    if (!n || n >= MAX_PATH) return {};
    std::string s(p, p+n);
    auto pos = s.find_last_of("\\/");
    return pos == std::string::npos ? std::string(".\\") : s.substr(0,pos+1);
}

bool readable(std::uintptr_t a, std::size_t n) {
    std::uintptr_t cur=a, end=a+n;
    while (cur<end) {
        MEMORY_BASIC_INFORMATION mbi={};
        if (VirtualQuery((LPCVOID)cur,&mbi,sizeof(mbi))!=sizeof(mbi)) return false;
        if (mbi.State!=MEM_COMMIT || (mbi.Protect&PAGE_GUARD) || (mbi.Protect&PAGE_NOACCESS)) return false;
        DWORD p=mbi.Protect&0xff;
        bool ok=p==PAGE_READONLY||p==PAGE_READWRITE||p==PAGE_WRITECOPY||p==PAGE_EXECUTE_READ||p==PAGE_EXECUTE_READWRITE||p==PAGE_EXECUTE_WRITECOPY;
        if(!ok) return false;
        std::uintptr_t re=(std::uintptr_t)mbi.BaseAddress+mbi.RegionSize;
        if(re<=cur) return false;
        cur=re<end?re:end;
    }
    return true;
}

std::string moduleAt(std::uintptr_t a, std::uintptr_t* baseOut=nullptr) {
    HMODULE h=nullptr;
    if(!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        (LPCSTR)a,&h) || !h) {
        if(baseOut) *baseOut=0;
        return "<none>";
    }
    if(baseOut) *baseOut=(std::uintptr_t)h;
    char p[MAX_PATH]={};
    DWORD n=GetModuleFileNameA(h,p,MAX_PATH);
    return n?std::string(p,p+n):"<module-path-unavailable>";
}

void regionInfo(std::ostringstream& ss, std::uintptr_t a) {
    MEMORY_BASIC_INFORMATION mbi={};
    if(VirtualQuery((LPCVOID)a,&mbi,sizeof(mbi))!=sizeof(mbi)) { ss<<"VirtualQuery=0\r\n"; return; }
    std::uintptr_t mb=0;
    ss<<std::hex<<std::uppercase;
    ss<<"Address=0x"<<a<<" RegionBase=0x"<<(std::uintptr_t)mbi.BaseAddress
      <<" AllocationBase=0x"<<(std::uintptr_t)mbi.AllocationBase
      <<" RegionSize=0x"<<mbi.RegionSize<<" State=0x"<<mbi.State
      <<" Protect=0x"<<mbi.Protect<<" Type=0x"<<mbi.Type<<"\r\n";
    std::string mod=moduleAt(a,&mb);
    ss<<"ContainingModule="<<mod;
    if(mb) ss<<" ModuleBase=0x"<<mb<<" RVA=0x"<<(a-mb);
    ss<<"\r\n"<<std::dec;
}

void hexDump(std::ostringstream& ss, std::uintptr_t a, std::size_t n) {
    if(!readable(a,n)) { ss<<"READABLE=0\r\n"; return; }
    std::vector<unsigned char> b(n);
    SIZE_T got=0;
    if(!ReadProcessMemory(GetCurrentProcess(),(LPCVOID)a,b.data(),n,&got)) { ss<<"ReadProcessMemory=0\r\n"; return; }
    b.resize(got);
    for(std::size_t i=0;i<b.size();i+=16) {
        ss<<std::hex<<std::uppercase<<std::setfill('0')<<std::setw(8)<<(unsigned long)(a+i)<<"  ";
        for(std::size_t j=0;j<16;j++) {
            if(i+j<b.size()) ss<<std::setw(2)<<(unsigned)b[i+j]<<' ';
            else ss<<"   ";
        }
        ss<<" |";
        for(std::size_t j=0;j<16 && i+j<b.size();j++) { unsigned char c=b[i+j]; ss<<((c>=32&&c<=126)?(char)c:'.'); }
        ss<<"|\r\n";
    }
    ss<<std::dec;
}

std::uintptr_t rel32Target(std::uintptr_t opcodeAddr) {
    if(!readable(opcodeAddr,5)) return 0;
    unsigned char op=*(unsigned char*)opcodeAddr;
    if(op!=0xE8 && op!=0xE9) return 0;
    std::int32_t rel=0; std::memcpy(&rel,(void*)(opcodeAddr+1),4);
    return opcodeAddr+5+(std::intptr_t)rel;
}

void inspectTarget(std::ostringstream& ss, const char* label, std::uintptr_t a) {
    ss<<"\r\n=== "<<label<<" ===\r\n";
    regionInfo(ss,a);
    hexDump(ss,a,0x100);
}

void followSource(std::ostringstream& ss, std::uintptr_t source) {
    ss<<"\r\n==============================\r\n";
    ss<<"SOURCE 0x"<<std::hex<<std::uppercase<<source<<std::dec<<"\r\n";
    regionInfo(ss,source);
    hexDump(ss,source,0x20);
    std::uintptr_t tramp=rel32Target(source);
    ss<<"source_rel32_target=0x"<<std::hex<<std::uppercase<<tramp<<std::dec<<"\r\n";
    if(!tramp) return;
    inspectTarget(ss,"TRAMPOLINE",tramp);

    if(!readable(tramp,0x80)) return;
    const unsigned char* p=(const unsigned char*)tramp;
    for(int i=0;i<0x60;i++) {
        if(p[i]==0xB8 && i+5<=0x60) {
            std::uint32_t imm=0; std::memcpy(&imm,p+i+1,4);
            std::ostringstream name; name<<"MOV EAX immediate @+0x"<<std::hex<<std::uppercase<<i;
            inspectTarget(ss,name.str().c_str(),imm);
        }
        if((p[i]==0xE8 || p[i]==0xE9) && i+5<=0x60) {
            std::uintptr_t t=rel32Target(tramp+i);
            std::ostringstream name; name<<(p[i]==0xE8?"CALL rel32":"JMP rel32")<<" @+0x"<<std::hex<<std::uppercase<<i;
            inspectTarget(ss,name.str().c_str(),t);
        }
    }
}

} // namespace

bool dump(std::string& outputPath, std::string& status) {
    outputPath.clear(); status.clear();
    std::ostringstream ss;
    ss<<"DirkNativeDump v3 - READ ONLY\r\n";
    ss<<"Purpose: recursively identify the module and bytes behind existing 0x5D55C0/0x5D57C0 detours.\r\n";
    ss<<"No hooks, no writes, no calls into inspected functions.\r\n";

    std::uintptr_t selfBase=0;
    std::string self=moduleAt((std::uintptr_t)&dump,&selfBase);
    ss<<"SelfModule="<<self<<" SelfBase=0x"<<std::hex<<std::uppercase<<selfBase<<std::dec<<"\r\n";
    regionInfo(ss,0x005D55C0u);
    regionInfo(ss,0x005D57C0u);

    followSource(ss,0x005D55C0u);
    followSource(ss,0x005D57C0u);

    std::string dir=exeDir();
    if(dir.empty()) { status="EXE_DIRECTORY_UNAVAILABLE"; return false; }
    outputPath=dir+"DirkNativeDump-v3.txt";
    std::ofstream f(outputPath.c_str(),std::ios::binary|std::ios::trunc);
    if(!f) { status="OPEN_OUTPUT_FAILED"; return false; }
    std::string text=ss.str(); f.write(text.data(),(std::streamsize)text.size()); f.flush();
    if(!f.good()) { status="WRITE_OUTPUT_FAILED"; return false; }
    status="DUMP3_OK";
    return true;
}

} // namespace dirkNativeDumpV3
