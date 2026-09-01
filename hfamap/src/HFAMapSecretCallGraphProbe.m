#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/loader.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

static int gKey2PathDone;

static const char *HFABaseName(const char *path) {
    const char *p = path ? strrchr(path, '/') : NULL;
    return p ? p + 1 : (path ? path : "?");
}

static void HFAKey2Log(const char *fmt, ...) {
    @autoreleasepool {
        NSString *path = [NSHomeDirectory()
            stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
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

static uintptr_t HFAStripPointer(uintptr_t value) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip((void *)value,
                                    ptrauth_key_function_pointer);
#else
    return value;
#endif
}

static uintptr_t HFABLTarget(uintptr_t pc, uint32_t instruction) {
    int64_t immediate = instruction & 0x03FFFFFFu;
    if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
    return (uintptr_t)((int64_t)pc + (immediate << 2));
}

static int HFAFindText(uintptr_t base, uintptr_t *startOut,
                       uintptr_t *endOut) {
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)base;
    if (!header || header->magic != MH_MAGIC_64) return 0;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command =
            (const struct load_command *)cursor;
        if (!command->cmdsize) return 0;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *section =
                (const struct section_64 *)(segment + 1);
            for (uint32_t j = 0; j < segment->nsects; j++) {
                if (strncmp(section[j].sectname, "__text", 16) == 0) {
                    uintptr_t start = base + (uintptr_t)section[j].addr;
                    uintptr_t size = (uintptr_t)section[j].size;
                    if (!size || size > 0x2000000u ||
                        start + size < start) return 0;
                    *startOut = start;
                    *endOut = start + size;
                    return 1;
                }
            }
        }
        cursor += command->cmdsize;
    }
    return 0;
}

static uintptr_t HFAFindFunctionStart(uintptr_t textStart,
                                      uintptr_t caller) {
    uintptr_t best = 0;
    for (uintptr_t delta = 4; delta <= 0x1000 && caller >= delta;
         delta += 4) {
        uintptr_t address = caller - delta;
        if (address < textStart) break;
        uint32_t word = 0;
        memcpy(&word, (const void *)address, 4);
        if ((word & 0xFFC003FFu) == 0xD10003FFu) {
            best = address;
            break;
        }
        if (word == 0xD65F03C0u) {
            best = address + 4;
            break;
        }
    }
    return best;
}

static unsigned HFAAddUnique(uintptr_t *values, unsigned count,
                             unsigned capacity, uintptr_t value) {
    if (!value) return count;
    for (unsigned i = 0; i < count; i++)
        if (values[i] == value) return count;
    if (count < capacity) values[count++] = value;
    return count;
}

static unsigned HFAScanXrefs(uintptr_t base, uintptr_t textStart,
                             uintptr_t textEnd, const uintptr_t *targets,
                             unsigned targetCount, unsigned depth,
                             uintptr_t *functions, unsigned functionCount,
                             unsigned functionCapacity) {
    for (uintptr_t pc = textStart; pc + 4 <= textEnd; pc += 4) {
        uint32_t instruction = 0;
        memcpy(&instruction, (const void *)pc, 4);
        if ((instruction & 0xFC000000u) != 0x94000000u) continue;
        uintptr_t target = HFABLTarget(pc, instruction);
        int match = 0;
        for (unsigned i = 0; i < targetCount; i++)
            if (target == targets[i]) { match = 1; break; }
        if (!match) continue;
        uintptr_t function = HFAFindFunctionStart(textStart, pc);
        uint32_t context[8] = {0};
        uintptr_t contextStart = pc >= textStart + 16 ? pc - 16 : pc;
        for (unsigned i = 0; i < 8 &&
             contextStart + i * 4 + 4 <= textEnd; i++)
            memcpy(&context[i], (const void *)(contextStart + i * 4), 4);
        HFAKey2Log("[KEY2-XREF] depth=%u targetRVA=%llX callsiteRVA=%llX functionRVA=%llX ctx=%08X/%08X/%08X/%08X/%08X/%08X/%08X/%08X\n",
                   depth,
                   (unsigned long long)(target - base),
                   (unsigned long long)(pc - base),
                   function ? (unsigned long long)(function - base) : 0,
                   context[0], context[1], context[2], context[3],
                   context[4], context[5], context[6], context[7]);
        functionCount = HFAAddUnique(functions, functionCount,
                                     functionCapacity, function);
    }
    return functionCount;
}

static void HFALogMethodsForNodes(uintptr_t base, const char *image,
                                  const uintptr_t *nodes,
                                  unsigned nodeCount) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = malloc((size_t)classCount * sizeof(Class));
    if (!classes) return;
    classCount = objc_getClassList(classes, classCount);
    unsigned matches = 0;
    for (int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        const char *classImage = class_getImageName(cls);
        if (!classImage ||
            strcmp(HFABaseName(classImage), image) != 0) continue;
        Class owners[2] = {cls, object_getClass(cls)};
        for (unsigned kind = 0; kind < 2; kind++) {
            unsigned methodCount = 0;
            Method *methods = class_copyMethodList(owners[kind],
                                                   &methodCount);
            for (unsigned m = 0; methods && m < methodCount; m++) {
                uintptr_t implementation = HFAStripPointer(
                    (uintptr_t)method_getImplementation(methods[m]));
                for (unsigned n = 0; n < nodeCount; n++) {
                    if (implementation != nodes[n]) continue;
                    HFAKey2Log("[KEY2-METHOD] kind=%c class=%s selector=%s rva=%llX\n",
                               kind ? '+' : '-',
                               class_getName(cls),
                               sel_getName(method_getName(methods[m])),
                               (unsigned long long)(implementation - base));
                    matches++;
                }
            }
            free(methods);
        }
    }
    free(classes);
    HFAKey2Log("[KEY2-METHOD-END] matches=%u nodes=%u\n",
               matches, nodeCount);
}

void HFAProbeKey2Path(uintptr_t getterAddress) {
    if (gKey2PathDone || !getterAddress) return;
    gKey2PathDone = 1;
    Dl_info info = {0};
    if (!dladdr((void *)getterAddress, &info) || !info.dli_fbase) return;
    uintptr_t base = (uintptr_t)info.dli_fbase;
    uintptr_t getterRVA = getterAddress - base;
    const char *image = HFABaseName(info.dli_fname);
    if (strcmp(image, "RiseofBerk.dylib") != 0 ||
        getterRVA != 0x994EA4u) {
        HFAKey2Log("[KEY2-PATH-SKIP] image=%s getterRVA=%llX\n",
                   image, (unsigned long long)getterRVA);
        return;
    }

    uintptr_t registerAddress = getterAddress + 0x1F38u;
    uintptr_t loaderAddress = getterAddress + 0xA70u;
    uint32_t registerInsn = 0, loaderInsn = 0;
    memcpy(&registerInsn, (const void *)registerAddress, 4);
    memcpy(&loaderInsn, (const void *)loaderAddress, 4);
    if (registerInsn != 0xA9BD57F6u ||
        loaderInsn != 0xD10643FFu) {
        HFAKey2Log("[KEY2-PATH-SKIP] image=%s fingerprint=%08X/%08X\n",
                   image, registerInsn, loaderInsn);
        return;
    }

    uintptr_t textStart = 0, textEnd = 0;
    if (!HFAFindText(base, &textStart, &textEnd)) {
        HFAKey2Log("[KEY2-PATH-SKIP] image=%s reason=no-text\n", image);
        return;
    }

    uintptr_t keyTableAddress = base + 0xD31D40u;
    uintptr_t slots[4] = {0};
    uint64_t mask = 0;
    memcpy(slots, (const void *)keyTableAddress, sizeof(slots));
    memcpy(&mask, (const void *)(base + 0xCFC9C0u), sizeof(mask));
    HFAKey2Log("[KEY2-PATH-BEGIN] image=%s base=%p textRVA=%llX-%llX registerRVA=%llX loaderRVA=%llX\n",
               image, (void *)base,
               (unsigned long long)(textStart - base),
               (unsigned long long)(textEnd - base),
               (unsigned long long)(registerAddress - base),
               (unsigned long long)(loaderAddress - base));
    HFAKey2Log("[KEY2-TABLE] mask=%016llX slot0=%p slot1=%p slot2=%p slot3=%p\n",
               (unsigned long long)mask, (void *)slots[0],
               (void *)slots[1], (void *)slots[2], (void *)slots[3]);

    uintptr_t targets[64] = {registerAddress, loaderAddress};
    unsigned targetCount = 2;
    uintptr_t nodes[128] = {registerAddress, loaderAddress};
    unsigned nodeCount = 2;
    for (unsigned depth = 0; depth < 3 && targetCount; depth++) {
        uintptr_t functions[64] = {0};
        unsigned functionCount = HFAScanXrefs(
            base, textStart, textEnd, targets, targetCount, depth,
            functions, 0, 64);
        targetCount = 0;
        for (unsigned i = 0; i < functionCount; i++) {
            unsigned oldCount = nodeCount;
            nodeCount = HFAAddUnique(nodes, nodeCount, 128, functions[i]);
            if (nodeCount != oldCount && targetCount < 64)
                targets[targetCount++] = functions[i];
        }
        HFAKey2Log("[KEY2-XREF-DEPTH-END] depth=%u functions=%u next=%u\n",
                   depth, functionCount, targetCount);
    }
    HFALogMethodsForNodes(base, image, nodes, nodeCount);
    HFAKey2Log("[KEY2-PATH-END] nodes=%u\n", nodeCount);
}
