#import "ZNDirectNativeCallExecutor.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNPatchCore.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#include <string.h>

static NSMutableDictionary<NSString *, NSDictionary *> *ZNDirectValidated(void) {
    static NSMutableDictionary *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [NSMutableDictionary dictionary]; });
    return store;
}

static NSString *ZNDirectCandidateKey(NSDictionary *candidate) {
    uint64_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    uint64_t methodPointer = [candidate[@"methodPointer"] unsignedLongLongValue];
    NSString *canonical = [candidate[@"canonical"] isKindOfClass:NSString.class] ? candidate[@"canonical"] : @"";
    return [NSString stringWithFormat:@"%llx|%llx|%@", (unsigned long long)methodInfo, (unsigned long long)methodPointer, canonical];
}

static BOOL ZNDirectParseImageLayout(const struct mach_header_64 *mh,
                                     uint64_t *imageVMBase,
                                     NSArray<NSDictionary *> **segments,
                                     NSString **error) {
    if (!mh || mh->magic != MH_MAGIC_64) {
        if (error) *error = @"Direct Native：目标不是有效 arm64 Mach-O";
        return NO;
    }
    if (mh->ncmds > 4096 || mh->sizeofcmds > 16 * 1024 * 1024) {
        if (error) *error = @"Direct Native：Mach-O load commands 异常";
        return NO;
    }
    const uint8_t *cursor = (const uint8_t *)(mh + 1);
    const uint8_t *limit = cursor + mh->sizeofcmds;
    uint64_t base = UINT64_MAX;
    NSMutableArray *items = [NSMutableArray array];
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > limit) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) break;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            NSString *name = [[NSString alloc] initWithBytes:seg->segname
                                                     length:strnlen(seg->segname, 16)
                                                   encoding:NSUTF8StringEncoding] ?: @"?";
            if (strncmp(seg->segname, SEG_TEXT, 16) == 0) base = seg->vmaddr;
            [items addObject:@{
                @"name": name,
                @"vmaddr": @(seg->vmaddr),
                @"vmsize": @(seg->vmsize),
                @"initprot": @(seg->initprot)
            }];
        }
        cursor += lc->cmdsize;
    }
    if (base == UINT64_MAX) {
        if (error) *error = @"Direct Native：目标 image 没有 __TEXT";
        return NO;
    }
    if (imageVMBase) *imageVMBase = base;
    if (segments) *segments = [items copy];
    return YES;
}

static BOOL ZNDirectExecutableRuntimeAddress(uintptr_t header,
                                             intptr_t slide,
                                             uint64_t rva,
                                             uintptr_t *address,
                                             NSString **error) {
    uint64_t imageVMBase = 0;
    NSArray<NSDictionary *> *segments = nil;
    if (!ZNDirectParseImageLayout((const struct mach_header_64 *)header, &imageVMBase, &segments, error)) return NO;
    if (rva > UINT64_MAX - imageVMBase) {
        if (error) *error = @"Direct Native：RVA 溢出";
        return NO;
    }
    uint64_t preferred = imageVMBase + rva;
    NSDictionary *match = nil;
    for (NSDictionary *seg in segments) {
        uint64_t start = [seg[@"vmaddr"] unsignedLongLongValue];
        uint64_t size = [seg[@"vmsize"] unsignedLongLongValue];
        if (!size || preferred < start || preferred >= start + size) continue;
        match = seg;
        break;
    }
    if (!match || !([match[@"initprot"] intValue] & VM_PROT_EXECUTE)) {
        if (error) *error = @"Direct Native：RVA 不在 executable segment";
        return NO;
    }
    __int128 runtime = (__int128)preferred + (__int128)slide;
    if (runtime <= 0 || runtime > UINTPTR_MAX) {
        if (error) *error = @"Direct Native：Runtime VA 溢出";
        return NO;
    }
    if (address) *address = (uintptr_t)runtime;
    return YES;
}

static NSDictionary *ZNDirectFindImageForPointer(uintptr_t pointer, uint64_t candidateRVA, NSString **error) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *raw = _dyld_get_image_header(i);
        if (!raw || raw->magic != MH_MAGIC_64) continue;
        uintptr_t header = (uintptr_t)raw;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        uint64_t imageVMBase = 0;
        NSArray<NSDictionary *> *segments = nil;
        if (!ZNDirectParseImageLayout((const struct mach_header_64 *)raw, &imageVMBase, &segments, NULL)) continue;
        for (NSDictionary *seg in segments) {
            if (!([seg[@"initprot"] intValue] & VM_PROT_EXECUTE)) continue;
            uint64_t startPreferred = [seg[@"vmaddr"] unsignedLongLongValue];
            uint64_t size = [seg[@"vmsize"] unsignedLongLongValue];
            __int128 startRuntime = (__int128)startPreferred + (__int128)slide;
            __int128 endRuntime = startRuntime + size;
            if ((__int128)pointer < startRuntime || (__int128)pointer >= endRuntime) continue;
            uint64_t preferred = (uint64_t)((__int128)pointer - (__int128)slide);
            if (preferred < imageVMBase) continue;
            uint64_t rva = preferred - imageVMBase;
            if (candidateRVA && candidateRVA != rva) {
                if (error) *error = [NSString stringWithFormat:@"Direct Native：Finder RVA(0x%llX) 与 methodPointer RVA(0x%llX) 不一致",
                                      (unsigned long long)candidateRVA, (unsigned long long)rva];
                return nil;
            }
            const char *cpath = _dyld_get_image_name(i);
            NSString *path = cpath ? [NSString stringWithUTF8String:cpath] : @"";
            NSString *name = path.lastPathComponent ?: @"";
            return @{@"image": name.length ? name : path,
                     @"path": path ?: @"",
                     @"header": @(header),
                     @"slide": @((long long)slide),
                     @"rva": @(rva),
                     @"runtime": @(pointer)};
        }
    }
    if (error) *error = @"Direct Native：methodPointer 不属于已加载 executable image";
    return nil;
}

static BOOL ZNDirectReadInstruction(uintptr_t address, uint32_t *instruction) {
    mach_vm_size_t read = 0;
    uint32_t value = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)address, 4,
                                              (mach_vm_address_t)(uintptr_t)&value, &read);
    if (kr != KERN_SUCCESS || read != 4) return NO;
    if (instruction) *instruction = value;
    return YES;
}

static BOOL ZNDirectRegTainted(uint32_t reg, BOOL x0, BOOL x1) {
    return (reg == 0 && x0) || (reg == 1 && x1);
}

static void ZNDirectKillWrite(uint32_t reg, BOOL *x0, BOOL *x1) {
    if (reg == 0) *x0 = NO;
    else if (reg == 1) *x1 = NO;
}

// Conservative entry-argument data-flow proof. It only proves that the incoming
// x0/x1 are never consumed before being overwritten (or RET). Unknown
// instructions that mention a live x0/x1 fail closed.
static BOOL ZNDirectProveX0X1Unused(uintptr_t address, NSString **proof, NSString **error) {
    BOOL x0Live = YES, x1Live = YES;
    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    for (NSUInteger i = 0; i < 96; i++) {
        uint32_t insn = 0;
        uintptr_t pc = address + i * 4;
        if (!ZNDirectReadInstruction(pc, &insn)) {
            if (error) *error = @"Direct Native：无法读取 ARM64 指令";
            return NO;
        }
        if (insn == 0xD65F03C0u) { // RET
            if (proof) *proof = [NSString stringWithFormat:@"RET before any incoming x0/x1 use · scanned=%lu", (unsigned long)(i + 1)];
            return YES;
        }
        uint32_t rd = insn & 31u;
        uint32_t rn = (insn >> 5) & 31u;
        uint32_t rt2 = (insn >> 10) & 31u;
        uint32_t rm = (insn >> 16) & 31u;

        BOOL recognized = NO;
        BOOL read0 = NO, read1 = NO;
        uint32_t writes[2] = { 31u, 31u };
        NSUInteger writeCount = 0;

        // ADR / ADRP.
        if ((insn & 0x1F000000u) == 0x10000000u) {
            recognized = YES; writes[writeCount++] = rd;
        }
        // MOVZ / MOVN.
        else if ((insn & 0x5F800000u) == 0x52800000u || (insn & 0x5F800000u) == 0x12800000u) {
            recognized = YES; writes[writeCount++] = rd;
        }
        // MOVK reads and rewrites Rd.
        else if ((insn & 0x7F800000u) == 0x72800000u) {
            recognized = YES;
            read0 |= (rd == 0 && x0Live); read1 |= (rd == 1 && x1Live);
            writes[writeCount++] = rd;
        }
        // ADD/SUB immediate.
        else if ((insn & 0x1F000000u) == 0x11000000u) {
            recognized = YES;
            read0 |= (rn == 0 && x0Live); read1 |= (rn == 1 && x1Live);
            writes[writeCount++] = rd;
        }
        // Logical immediate.
        else if ((insn & 0x1F800000u) == 0x12000000u) {
            recognized = YES;
            read0 |= (rn == 0 && x0Live); read1 |= (rn == 1 && x1Live);
            writes[writeCount++] = rd;
        }
        // ADD/SUB shifted register.
        else if ((insn & 0x1F200000u) == 0x0B000000u) {
            recognized = YES;
            read0 |= ZNDirectRegTainted(rn, x0Live, x1Live) && rn == 0;
            read1 |= ZNDirectRegTainted(rn, x0Live, x1Live) && rn == 1;
            read0 |= ZNDirectRegTainted(rm, x0Live, x1Live) && rm == 0;
            read1 |= ZNDirectRegTainted(rm, x0Live, x1Live) && rm == 1;
            writes[writeCount++] = rd;
        }
        // Logical shifted register (covers MOV alias ORR Rd,XZR,Rm).
        else if ((insn & 0x1F000000u) == 0x0A000000u) {
            recognized = YES;
            if (rn != 31u) {
                read0 |= (rn == 0 && x0Live); read1 |= (rn == 1 && x1Live);
            }
            read0 |= (rm == 0 && x0Live); read1 |= (rm == 1 && x1Live);
            writes[writeCount++] = rd;
        }
        // LDR/STR unsigned immediate and common unscaled forms.
        else if ((insn & 0x3B000000u) == 0x39000000u || (insn & 0x3B200C00u) == 0x38000000u) {
            recognized = YES;
            BOOL load = (insn & (1u << 22)) != 0;
            read0 |= (rn == 0 && x0Live); read1 |= (rn == 1 && x1Live);
            if (load) writes[writeCount++] = rd;
            else {
                read0 |= (rd == 0 && x0Live); read1 |= (rd == 1 && x1Live);
            }
        }
        // LDP/STP.
        else if ((insn & 0x3A000000u) == 0x28000000u) {
            recognized = YES;
            BOOL load = (insn & (1u << 22)) != 0;
            read0 |= (rn == 0 && x0Live); read1 |= (rn == 1 && x1Live);
            if (load) { writes[writeCount++] = rd; writes[writeCount++] = rt2; }
            else {
                read0 |= (rd == 0 && x0Live) || (rt2 == 0 && x0Live);
                read1 |= (rd == 1 && x1Live) || (rt2 == 1 && x1Live);
            }
        }
        // BL: any still-live entry argument could escape to callee -> fail closed.
        else if ((insn & 0xFC000000u) == 0x94000000u) {
            recognized = YES;
            if (x0Live || x1Live) {
                if (error) *error = [NSString stringWithFormat:@"Direct Native：在覆盖 entry x0/x1 前遇到 BL（+0x%lX）", (unsigned long)(i * 4)];
                return NO;
            }
            if (proof) *proof = [NSString stringWithFormat:@"entry x0/x1 overwritten before first BL · scanned=%lu", (unsigned long)(i + 1)];
            return YES;
        }
        // Any branch while entry values remain live requires CFG proof we do not have.
        else if ((insn & 0x7C000000u) == 0x14000000u ||
                 (insn & 0xFF000010u) == 0x54000000u ||
                 (insn & 0x7E000000u) == 0x34000000u ||
                 (insn & 0x7E000000u) == 0x36000000u) {
            recognized = YES;
            if (x0Live || x1Live) {
                if (error) *error = [NSString stringWithFormat:@"Direct Native：entry x0/x1 尚存活时遇到控制流分支（+0x%lX）", (unsigned long)(i * 4)];
                return NO;
            }
            if (proof) *proof = [NSString stringWithFormat:@"entry x0/x1 overwritten before first branch · scanned=%lu", (unsigned long)(i + 1)];
            return YES;
        }

        if (read0 || read1) {
            if (error) *error = [NSString stringWithFormat:@"Direct Native：ARM64 数据流读取了 entry %@%@（+0x%lX insn=%08X）",
                                  read0 ? @"x0/self" : @"",
                                  (read0 && read1) ? @" + x1/MethodInfo" : (read1 ? @"x1/MethodInfo" : @""),
                                  (unsigned long)(i * 4), insn];
            return NO;
        }

        if (recognized) {
            for (NSUInteger w = 0; w < writeCount; w++) ZNDirectKillWrite(writes[w], &x0Live, &x1Live);
            if (!x0Live && !x1Live) {
                if (proof) *proof = [NSString stringWithFormat:@"entry x0/self and x1/MethodInfo overwritten before use · scanned=%lu", (unsigned long)(i + 1)];
                return YES;
            }
            continue;
        }

        // Unknown instruction: if any conventional register field names a live
        // x0/x1, reject instead of guessing whether that field is source/dest.
        BOOL mentions0 = x0Live && (rd == 0 || rn == 0 || rm == 0 || rt2 == 0);
        BOOL mentions1 = x1Live && (rd == 1 || rn == 1 || rm == 1 || rt2 == 1);
        if (mentions0 || mentions1) {
            if (error) *error = [NSString stringWithFormat:@"Direct Native：未知 ARM64 指令涉及 live x0/x1（+0x%lX insn=%08X）",
                                  (unsigned long)(i * 4), insn];
            return NO;
        }
        [trace addObject:[NSString stringWithFormat:@"+0x%lX:%08X", (unsigned long)(i * 4), insn]];
    }
    if (error) *error = @"Direct Native：96 条指令内无法完成 x0/x1 unused 证明";
    return NO;
}

NSDictionary<NSString *, id> *ZNDirectNativeAnalyzeCandidate(NSDictionary<NSString *, id> *candidate,
                                                              NSString **error) {
    if (![candidate isKindOfClass:NSDictionary.class]) {
        if (error) *error = @"Direct Native：candidate 为空";
        return nil;
    }
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    if (argc != 0) {
        if (error) *error = @"Direct Native V1 仅开放 /0；参数 ABI 后续单独扩展";
        return nil;
    }
    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    NSDictionary *ret = [abi[@"return"] isKindOfClass:NSDictionary.class] ? abi[@"return"] : nil;
    NSString *returnName = [ret[@"name"] isKindOfClass:NSString.class] ? [ret[@"name"] lowercaseString] : @"";
    if (![returnName isEqualToString:@"system.void"] && ![returnName isEqualToString:@"void"]) {
        if (error) *error = [NSString stringWithFormat:@"Direct Native V1 仅开放 void /0；当前 return=%@", ret[@"name"] ?: @"?"];
        return nil;
    }

    uintptr_t pointer = (uintptr_t)[candidate[@"methodPointer"] unsignedLongLongValue];
    uint64_t candidateRVA = [candidate[@"rva"] unsignedLongLongValue];
    if (!pointer) {
        if (error) *error = @"Direct Native：Method Pointer 不可用";
        return nil;
    }
    NSString *imageError = nil;
    NSDictionary *image = ZNDirectFindImageForPointer(pointer, candidateRVA, &imageError);
    if (!image) {
        if (error) *error = imageError;
        return nil;
    }

    NSString *proof = nil;
    NSString *flowError = nil;
    if (!ZNDirectProveX0X1Unused(pointer, &proof, &flowError)) {
        if (error) *error = flowError ?: @"Direct Native：无法证明 self/MethodInfo unused";
        return nil;
    }

    NSDictionary *config = @{
        @"version": @1,
        @"callMode": @"direct-native-call",
        @"image": image[@"image"] ?: @"UnityFramework",
        @"imagePath": image[@"path"] ?: @"",
        @"rva": image[@"rva"] ?: @0,
        @"returnType": @"void",
        @"parameterCount": @0,
        @"selfPolicy": @"unused",
        @"methodInfoPolicy": @"unused",
        @"proof": proof ?: @"ARM64 entry x0/x1 unused",
        @"methodPointerAtAuthoring": @(pointer)
    };
    return config;
}

NSDictionary<NSString *, id> *ZNDirectNativeExecuteConfig(NSDictionary<NSString *, id> *config,
                                                           NSString **error) {
    if (![config isKindOfClass:NSDictionary.class] || ![[config[@"callMode"] description] isEqualToString:@"direct-native-call"]) {
        if (error) *error = @"Direct Native：配置无效";
        return nil;
    }
    if ([config[@"parameterCount"] unsignedIntegerValue] != 0 ||
        ![[config[@"returnType"] description].lowercaseString isEqualToString:@"void"] ||
        ![[config[@"selfPolicy"] description] isEqualToString:@"unused"] ||
        ![[config[@"methodInfoPolicy"] description] isEqualToString:@"unused"]) {
        if (error) *error = @"Direct Native V1：仅允许 void /0 + self unused + MethodInfo unused";
        return nil;
    }

    NSString *wanted = [config[@"image"] isKindOfClass:NSString.class] ? config[@"image"] : @"";
    NSString *wantedPath = [config[@"imagePath"] isKindOfClass:NSString.class] ? config[@"imagePath"] : @"";
    uint64_t rva = [config[@"rva"] unsignedLongLongValue];
    if (!wanted.length || !rva) {
        if (error) *error = @"Direct Native：image/RVA 缺失";
        return nil;
    }

    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *cpath = _dyld_get_image_name(i);
        NSString *path = cpath ? [NSString stringWithUTF8String:cpath] : @"";
        NSString *name = path.lastPathComponent ?: @"";
        BOOL match = wantedPath.length ? [path isEqualToString:wantedPath] : ([name caseInsensitiveCompare:wanted] == NSOrderedSame);
        if (!match) continue;

        uintptr_t header = (uintptr_t)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        uintptr_t address = 0;
        NSString *resolveError = nil;
        if (!ZNDirectExecutableRuntimeAddress(header, slide, rva, &address, &resolveError)) {
            if (error) *error = resolveError;
            return nil;
        }

        typedef void (*ZNDirectVoidNoArgsInstanceFn)(void *, const void *);
        ZNDirectVoidNoArgsInstanceFn fn = reinterpret_cast<ZNDirectVoidNoArgsInstanceFn>(address);
        fn(nullptr, nullptr);

        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[direct-native-call] SUCCESS image=%@ rva=0x%llX runtime=0x%llX self=unused methodInfo=unused",
                                             name.length ? name : wanted,
                                             (unsigned long long)rva,
                                             (unsigned long long)address]];
        return @{
            @"status": @"SUCCESS",
            @"callMode": @"direct-native-call",
            @"image": name.length ? name : wanted,
            @"rva": @(rva),
            @"methodPointer": @(address),
            @"returnType": @"void",
            @"returnKind": @"void",
            @"returnValue": @"void",
            @"returnRawObject": @0,
            @"instance": @0,
            @"selfPolicy": @"unused",
            @"methodInfoPolicy": @"unused"
        };
    }

    if (error) *error = [NSString stringWithFormat:@"Direct Native：目标 image 未加载：%@", wanted];
    return nil;
}

NSDictionary<NSString *, id> *ZNDirectNativeTestCandidate(NSDictionary<NSString *, id> *candidate,
                                                           NSString **error) {
    NSString *analysisError = nil;
    NSDictionary *config = ZNDirectNativeAnalyzeCandidate(candidate, &analysisError);
    if (!config) {
        if (error) *error = analysisError;
        return nil;
    }
    NSString *executeError = nil;
    NSDictionary *result = ZNDirectNativeExecuteConfig(config, &executeError);
    if (!result) {
        if (error) *error = executeError;
        return nil;
    }
    @synchronized (ZNDirectValidated()) {
        ZNDirectValidated()[ZNDirectCandidateKey(candidate)] = config;
    }
    NSMutableDictionary *out = [result mutableCopy];
    out[@"config"] = config;
    return [out copy];
}

NSDictionary<NSString *, id> *ZNDirectNativeValidatedConfigForCandidate(NSDictionary<NSString *, id> *candidate) {
    if (![candidate isKindOfClass:NSDictionary.class]) return nil;
    @synchronized (ZNDirectValidated()) {
        return [ZNDirectValidated()[ZNDirectCandidateKey(candidate)] copy];
    }
}
