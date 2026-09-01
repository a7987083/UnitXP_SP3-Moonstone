#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uintptr_t gLastIntIMP = 0;
static uintptr_t gLastDataIMP = 0;

static const char *HFABaseName(const char *path) {
    if (!path) return "?";
    const char *p = strrchr(path, '/');
    return p ? p + 1 : path;
}

static void HFALog(const char *fmt, ...) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
        FILE *f = fopen(path.fileSystemRepresentation, "a");
        if (!f) return;
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fflush(f);
        fclose(f);
    }
}

static void HFAImageForAddress(uintptr_t addr, uintptr_t *baseOut, const char **nameOut) {
    uintptr_t best = 0;
    const char *bestName = NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t base = (uintptr_t)_dyld_get_image_header(i);
        if (base <= addr && base > best) {
            best = base;
            bestName = _dyld_get_image_name(i);
        }
    }
    if (baseOut) *baseOut = best;
    if (nameOut) *nameOut = bestName;
}

static int64_t HFASignExtend26(uint32_t imm26) {
    int64_t x = (int64_t)(imm26 & 0x03FFFFFFU);
    if (x & 0x02000000LL) x |= ~0x03FFFFFFLL;
    return x;
}

static void HFAScanSecretIMP(const char *kind, uintptr_t imp) {
    uintptr_t *last = strstr(kind, "Data") ? &gLastDataIMP : &gLastIntIMP;
    if (!imp || *last == imp) return;
    *last = imp;

    uintptr_t impBase = 0;
    const char *impImage = NULL;
    HFAImageForAddress(imp, &impBase, &impImage);
    uint64_t impRVA = (impBase && imp >= impBase && imp - impBase < 0x10000000ULL)
        ? (uint64_t)(imp - impBase) : 0;

    HFALog("[CG]%s imp=%p image=%s base=%p rva=%llX scan=0x100\n",
           kind, (void *)imp, HFABaseName(impImage), (void *)impBase,
           (unsigned long long)impRVA);

    unsigned hits = 0;
    for (unsigned off = 0; off < 0x100; off += 4) {
        uint32_t insn = 0, prev = 0, next = 0;
        memcpy(&insn, (const void *)(imp + off), sizeof(insn));

        // ARM64 BL immediate: op[31:26] == 100101b.
        if ((insn & 0xFC000000U) != 0x94000000U) continue;

        if (off >= 4) memcpy(&prev, (const void *)(imp + off - 4), sizeof(prev));
        if (off + 4 < 0x100) memcpy(&next, (const void *)(imp + off + 4), sizeof(next));

        int64_t rel = HFASignExtend26(insn) * 4LL;
        uintptr_t pc = imp + off;
        uintptr_t target = (uintptr_t)((int64_t)pc + rel);

        uintptr_t targetBase = 0;
        const char *targetImage = NULL;
        HFAImageForAddress(target, &targetBase, &targetImage);
        uint64_t targetRVA = (targetBase && target >= targetBase && target - targetBase < 0x10000000ULL)
            ? (uint64_t)(target - targetBase) : 0;

        HFALog("[CG-BL]%s off=%03X pc=%p target=%p image=%s base=%p rva=%llX ctx=%08X/%08X/%08X\n",
               kind, off, (void *)pc, (void *)target, HFABaseName(targetImage),
               (void *)targetBase, (unsigned long long)targetRVA,
               prev, insn, next);
        hits++;
    }

    HFALog("[CG-END]%s hits=%u\n", kind, hits);
}

// Called by the proven v1.4.4 live-object path after it extracts the exact IMP
// from the object's _methodDescription. No class-name or global-runtime scan.
void HFAScanSecretIMPFromRuntimeObject(const char *kind,
                                       uintptr_t imp,
                                       const char *actualClass) {
    if (!kind || !imp) return;
    HFALog("[CG-SOURCE] kind=%s class=%s imp=%p source=_methodDescription\n",
           kind, actualClass ? actualClass : "?", (void *)imp);
    HFAScanSecretIMP(kind, imp);
}

__attribute__((constructor))
static void HFASecretCallGraphInit(void) {
    @autoreleasepool {
        HFALog("[HFALearn v1.4.5.3 SecretIMPCallGraph] loaded\n");
    }
}
