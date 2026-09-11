#import "ZNStaticBinaryBuilder.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import "ZNStaticPatchFormat.h"
#import <mach-o/loader.h>
#import <mach/machine.h>
#import <mach/vm_prot.h>
#import <objc/runtime.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <vector>
#import <algorithm>

// Shared-Site Builder V2 is activated only when a workspace contains two or
// more logical rows with the same Target + starting RVA. Ordinary workspaces
// continue through the proven V1 builder unchanged.
//
// V2 model:
//   one physical Site -> one thunk -> canonical selectedTarget
//   OFF               -> relocated full original window
//   logical Feature A -> relocated Variant A
//   logical Feature B -> relocated Variant B
// Runtime keeps an owner stack; the most recently enabled active owner wins.

struct ZNV2Section {
    uint64_t fileStart;
    uint64_t fileEnd;
    uint64_t addr;
    uint64_t size;
    uint32_t flags;
};

struct ZNV2Segment {
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    vm_prot_t initprot;
    vm_prot_t maxprot;
    char name[17];
    std::vector<ZNV2Section> sections;
};

struct ZNV2Gap {
    uint64_t fileoff;
    uint64_t size;
    uint64_t rva;
    size_t segIndex;
};

struct ZNV2Logical {
    __unsafe_unretained ZNBinaryPatchRow *row;
    uint64_t rva;
    uint64_t fileoff;
    uint64_t length;
    size_t segIndex;
    NSData *original;
    NSData *enabled;
};

struct ZNV2Physical {
    uint64_t rva;
    uint64_t fileoff;
    uint64_t window;
    size_t segIndex;
    std::vector<size_t> members;
    NSData *original;
    uint64_t thunkRVA;
    uint64_t offRVA;
};

static uint64_t ZNV2Align(uint64_t value, uint64_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

static int64_t ZNV2SX(uint64_t value, int bits) {
    uint64_t sign = 1ULL << (bits - 1);
    return (int64_t)((value ^ sign) - sign);
}

static uint32_t ZNV2Read32(const uint8_t *p) {
    uint32_t value = 0;
    memcpy(&value, p, sizeof(value));
    return value;
}

static void ZNV2Write32(uint8_t *p, uint32_t value) {
    memcpy(p, &value, sizeof(value));
}

static BOOL ZNV2Zero(const uint8_t *base, uint64_t offset, uint64_t length) {
    for (uint64_t i = 0; i < length; i++) if (base[offset + i] != 0) return NO;
    return YES;
}

static BOOL ZNV2Parse(uint8_t *base,
                      size_t size,
                      std::vector<ZNV2Segment> &segments,
                      uint64_t &imageVMBase,
                      NSString **error) {
    if (size < sizeof(struct mach_header_64)) {
        if (error) *error = @"Mach-O 太小";
        return NO;
    }
    struct mach_header_64 *mh = (struct mach_header_64 *)base;
    if (mh->magic != MH_MAGIC_64) {
        if (error) *error = @"Shared-Site Builder V2 仅支持 thin 64-bit Mach-O";
        return NO;
    }
    if (mh->cputype != CPU_TYPE_ARM64) {
        if (error) *error = @"目标不是 arm64/arm64e Mach-O";
        return NO;
    }
    if (sizeof(*mh) + (uint64_t)mh->sizeofcmds > size) {
        if (error) *error = @"Mach-O load commands 越界";
        return NO;
    }

    imageVMBase = UINT64_MAX;
    uint8_t *cursor = base + sizeof(*mh);
    uint8_t *commandEnd = cursor + mh->sizeofcmds;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commandEnd) {
            if (error) *error = @"load command 损坏";
            return NO;
        }
        struct load_command *lc = (struct load_command *)cursor;
        if (lc->cmdsize < sizeof(struct load_command) || cursor + lc->cmdsize > commandEnd) {
            if (error) *error = @"load command size 损坏";
            return NO;
        }
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
            if (seg->fileoff + seg->filesize > size) {
                if (error) *error = @"segment file range 越界";
                return NO;
            }
            ZNV2Segment parsed = {};
            parsed.vmaddr = seg->vmaddr;
            parsed.vmsize = seg->vmsize;
            parsed.fileoff = seg->fileoff;
            parsed.filesize = seg->filesize;
            parsed.initprot = seg->initprot;
            parsed.maxprot = seg->maxprot;
            memcpy(parsed.name, seg->segname, 16);
            parsed.name[16] = 0;
            if (strncmp(seg->segname, SEG_TEXT, 16) == 0) imageVMBase = seg->vmaddr;

            uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
            if (lc->cmdsize >= sizeof(struct segment_command_64) + sectionBytes) {
                struct section_64 *sec = (struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    uint32_t type = sec[j].flags & SECTION_TYPE;
                    if (type == S_ZEROFILL || type == S_GB_ZEROFILL || type == S_THREAD_LOCAL_ZEROFILL) continue;
                    if (!sec[j].size || !sec[j].offset) continue;
                    uint64_t fileStart = sec[j].offset;
                    uint64_t fileEnd = fileStart + sec[j].size;
                    if (fileEnd > size) continue;
                    parsed.sections.push_back({fileStart, fileEnd, sec[j].addr, sec[j].size, sec[j].flags});
                }
            }
            segments.push_back(parsed);
        }
        cursor += lc->cmdsize;
    }
    if (imageVMBase == UINT64_MAX) {
        if (error) *error = @"未找到 __TEXT segment";
        return NO;
    }
    return YES;
}

static BOOL ZNV2RVAToFile(const std::vector<ZNV2Segment> &segments,
                          uint64_t imageVMBase,
                          uint64_t rva,
                          uint64_t length,
                          uint64_t &fileOffset,
                          size_t &segmentIndex) {
    uint64_t va = imageVMBase + rva;
    for (size_t i = 0; i < segments.size(); i++) {
        const ZNV2Segment &seg = segments[i];
        if (va >= seg.vmaddr && va + length <= seg.vmaddr + seg.filesize) {
            fileOffset = seg.fileoff + (va - seg.vmaddr);
            segmentIndex = i;
            return YES;
        }
    }
    return NO;
}

static uint64_t ZNV2FileToRVA(const ZNV2Segment &segment, uint64_t imageVMBase, uint64_t fileOffset) {
    return segment.vmaddr + (fileOffset - segment.fileoff) - imageVMBase;
}

static BOOL ZNV2InstructionRange(const std::vector<ZNV2Segment> &segments,
                                 uint64_t imageVMBase,
                                 uint64_t rva,
                                 uint64_t length) {
    uint64_t va = imageVMBase + rva;
    for (const ZNV2Segment &seg : segments) {
        if (!(seg.initprot & VM_PROT_EXECUTE)) continue;
        for (const ZNV2Section &sec : seg.sections) {
            if (!(sec.flags & (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS))) continue;
            if (va >= sec.addr && va + length <= sec.addr + sec.size) return YES;
        }
    }
    return NO;
}

static std::vector<ZNV2Gap> ZNV2Gaps(const uint8_t *base,
                                     const std::vector<ZNV2Segment> &segments,
                                     uint64_t imageVMBase,
                                     BOOL executable,
                                     uint64_t needed,
                                     const std::vector<uint64_t> &sites) {
    std::vector<ZNV2Gap> result;
    for (size_t segmentIndex = 0; segmentIndex < segments.size(); segmentIndex++) {
        const ZNV2Segment &seg = segments[segmentIndex];
        if (executable) {
            if (!(seg.initprot & VM_PROT_EXECUTE)) continue;
        } else if (!(seg.initprot & VM_PROT_WRITE)) continue;
        if (!seg.filesize || seg.sections.empty()) continue;

        std::vector<std::pair<uint64_t,uint64_t>> ranges;
        for (const ZNV2Section &sec : seg.sections) {
            if (sec.fileStart >= seg.fileoff && sec.fileEnd <= seg.fileoff + seg.filesize)
                ranges.push_back({sec.fileStart, sec.fileEnd});
        }
        if (ranges.empty()) continue;
        std::sort(ranges.begin(), ranges.end());
        uint64_t cursor = ranges.front().second;
        for (size_t i = 1; i <= ranges.size(); i++) {
            uint64_t nextStart = (i < ranges.size()) ? ranges[i].first : (seg.fileoff + seg.filesize);
            if (nextStart > cursor) {
                uint64_t aligned = ZNV2Align(cursor, executable ? 16 : 8);
                if (nextStart > aligned && nextStart - aligned >= needed && ZNV2Zero(base, aligned, needed)) {
                    uint64_t gapRVA = ZNV2FileToRVA(seg, imageVMBase, aligned);
                    BOOL reachable = YES;
                    if (executable) {
                        for (uint64_t site : sites) {
                            int64_t deltaStart = (int64_t)gapRVA - (int64_t)site;
                            int64_t deltaEnd = (int64_t)(gapRVA + needed) - (int64_t)site;
                            if (deltaStart <= -(1LL << 27) || deltaStart >= (1LL << 27) ||
                                deltaEnd <= -(1LL << 27) || deltaEnd >= (1LL << 27)) {
                                reachable = NO; break;
                            }
                        }
                    }
                    if (reachable) result.push_back({aligned, nextStart - aligned, gapRVA, segmentIndex});
                }
            }
            if (i < ranges.size()) cursor = std::max(cursor, ranges[i].second);
        }
    }
    std::sort(result.begin(), result.end(), [](const ZNV2Gap &a, const ZNV2Gap &b){ return a.size > b.size; });
    return result;
}

static BOOL ZNV2EncodeB(uint64_t fromRVA, uint64_t toRVA, BOOL link, uint32_t *outInstruction) {
    int64_t delta = (int64_t)toRVA - (int64_t)fromRVA;
    if ((delta & 3) || delta < -(1LL << 27) || delta >= (1LL << 27)) return NO;
    uint32_t imm26 = (uint32_t)((delta >> 2) & 0x03FFFFFFu);
    *outInstruction = (link ? 0x94000000u : 0x14000000u) | imm26;
    return YES;
}

static BOOL ZNV2EncodeADRPX17(uint64_t fromRVA, uint64_t toRVA, uint32_t *outInstruction) {
    int64_t pages = ((int64_t)(toRVA & ~0xFFFULL) - (int64_t)(fromRVA & ~0xFFFULL)) >> 12;
    if (pages < -(1LL << 20) || pages >= (1LL << 20)) return NO;
    uint64_t imm = (uint64_t)pages & 0x1FFFFFu;
    *outInstruction = 0x90000000u | ((uint32_t)(imm & 3u) << 29) |
                      ((uint32_t)((imm >> 2) & 0x7FFFFu) << 5) | 17u;
    return YES;
}

static uint32_t ZNV2LdrX17FromX17(uint64_t targetRVA) {
    uint32_t imm12 = (uint32_t)((targetRVA & 0xFFFULL) >> 3);
    return 0xF9400000u | (imm12 << 10) | (17u << 5) | 17u;
}

static BOOL ZNV2IsRET(uint32_t instruction) { return (instruction & 0xFFFFFC1Fu) == 0xD65F0000u; }
static BOOL ZNV2IsBR(uint32_t instruction) { return (instruction & 0xFFFFFC1Fu) == 0xD61F0000u; }

static BOOL ZNV2Relocate(uint32_t instruction,
                         uint64_t sourceRVA,
                         uint64_t destinationRVA,
                         uint64_t windowStart,
                         uint64_t windowEnd,
                         uint32_t *outInstruction,
                         BOOL *terminal,
                         NSString **error) {
    *terminal = NO;
    if ((instruction & 0x7C000000u) == 0x14000000u) {
        BOOL link = (instruction & 0x80000000u) != 0;
        int64_t delta = ZNV2SX(instruction & 0x03FFFFFFu, 26) << 2;
        uint64_t target = (uint64_t)((int64_t)sourceRVA + delta);
        if (target >= windowStart && target < windowEnd) { if(error)*error=@"PC-relative B/BL 指向 Shared Site 覆盖窗口内部"; return NO; }
        if (!ZNV2EncodeB(destinationRVA, target, link, outInstruction)) { if(error)*error=@"重定位 B/BL 超出 ±128MB"; return NO; }
        *terminal = !link; return YES;
    }
    if ((instruction & 0xFF000010u) == 0x54000000u ||
        (instruction & 0x7E000000u) == 0x34000000u ||
        (instruction & 0x3B000000u) == 0x18000000u) {
        int64_t delta = ZNV2SX((instruction >> 5) & 0x7FFFFu, 19) << 2;
        uint64_t target = (uint64_t)((int64_t)sourceRVA + delta);
        if (target >= windowStart && target < windowEnd) { if(error)*error=@"PC-relative imm19 指向 Shared Site 覆盖窗口内部"; return NO; }
        int64_t newDelta = (int64_t)target - (int64_t)destinationRVA;
        if ((newDelta & 3) || newDelta < -(1LL << 20) || newDelta >= (1LL << 20)) { if(error)*error=@"重定位 imm19 超出 ±1MB"; return NO; }
        *outInstruction = (instruction & ~0x00FFFFE0u) | (((uint32_t)(newDelta >> 2) & 0x7FFFFu) << 5); return YES;
    }
    if ((instruction & 0x7E000000u) == 0x36000000u) {
        int64_t delta = ZNV2SX((instruction >> 5) & 0x3FFFu, 14) << 2;
        uint64_t target = (uint64_t)((int64_t)sourceRVA + delta);
        if (target >= windowStart && target < windowEnd) { if(error)*error=@"TBZ/TBNZ 指向 Shared Site 覆盖窗口内部"; return NO; }
        int64_t newDelta = (int64_t)target - (int64_t)destinationRVA;
        if ((newDelta & 3) || newDelta < -(1LL << 15) || newDelta >= (1LL << 15)) { if(error)*error=@"重定位 TBZ/TBNZ 超出 ±32KB"; return NO; }
        *outInstruction = (instruction & ~0x0007FFE0u) | (((uint32_t)(newDelta >> 2) & 0x3FFFu) << 5); return YES;
    }
    uint32_t adrMask = instruction & 0x9F000000u;
    if (adrMask == 0x10000000u || adrMask == 0x90000000u) {
        uint64_t imm = ((uint64_t)((instruction >> 5) & 0x7FFFFu) << 2) | ((instruction >> 29) & 3u);
        int64_t signedImm = ZNV2SX(imm, 21);
        uint64_t target = adrMask == 0x90000000u
            ? (uint64_t)((int64_t)(sourceRVA & ~0xFFFULL) + (signedImm << 12))
            : (uint64_t)((int64_t)sourceRVA + signedImm);
        if (target >= windowStart && target < windowEnd) { if(error)*error=@"ADR/ADRP 指向 Shared Site 覆盖窗口内部"; return NO; }
        int64_t newImm = adrMask == 0x90000000u
            ? (((int64_t)(target & ~0xFFFULL) - (int64_t)(destinationRVA & ~0xFFFULL)) >> 12)
            : ((int64_t)target - (int64_t)destinationRVA);
        if (newImm < -(1LL << 20) || newImm >= (1LL << 20)) { if(error)*error=@"重定位 ADR/ADRP 超范围"; return NO; }
        uint64_t u = (uint64_t)newImm & 0x1FFFFFu;
        *outInstruction = (instruction & ~((3u << 29) | (0x7FFFFu << 5))) |
                          ((uint32_t)(u & 3u) << 29) |
                          ((uint32_t)((u >> 2) & 0x7FFFFu) << 5);
        return YES;
    }
    *outInstruction = instruction;
    if (ZNV2IsRET(instruction) || ZNV2IsBR(instruction)) *terminal = YES;
    return YES;
}

static BOOL ZNV2InboundInterior(const uint8_t *base,
                                const std::vector<ZNV2Segment> &segments,
                                uint64_t imageVMBase,
                                uint64_t siteRVA,
                                uint64_t length) {
    uint64_t endRVA = siteRVA + length;
    for (const ZNV2Segment &seg : segments) {
        if (!(seg.initprot & VM_PROT_EXECUTE)) continue;
        for (const ZNV2Section &sec : seg.sections) {
            if (!(sec.flags & (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS))) continue;
            if (sec.fileEnd <= sec.fileStart) continue;
            for (uint64_t offset = sec.fileStart; offset + 4 <= sec.fileEnd; offset += 4) {
                uint32_t instruction = ZNV2Read32(base + offset);
                uint64_t sourceRVA = sec.addr + (offset - sec.fileStart) - imageVMBase;
                uint64_t targetRVA = 0; BOOL direct = NO;
                if ((instruction & 0x7C000000u) == 0x14000000u) {
                    targetRVA = (uint64_t)((int64_t)sourceRVA + (ZNV2SX(instruction & 0x03FFFFFFu, 26) << 2)); direct = YES;
                } else if ((instruction & 0xFF000010u) == 0x54000000u || (instruction & 0x7E000000u) == 0x34000000u) {
                    targetRVA = (uint64_t)((int64_t)sourceRVA + (ZNV2SX((instruction >> 5) & 0x7FFFFu, 19) << 2)); direct = YES;
                } else if ((instruction & 0x7E000000u) == 0x36000000u) {
                    targetRVA = (uint64_t)((int64_t)sourceRVA + (ZNV2SX((instruction >> 5) & 0x3FFFu, 14) << 2)); direct = YES;
                }
                if (direct && targetRVA > siteRVA && targetRVA < endRVA) return YES;
            }
        }
    }
    return NO;
}

static BOOL ZNV2WriteVariant(uint8_t *base,
                             uint64_t fileOffset,
                             uint64_t variantRVA,
                             uint64_t reserved,
                             NSData *source,
                             uint64_t sourceRVA,
                             uint64_t windowStart,
                             uint64_t windowEnd,
                             uint64_t resumeRVA,
                             NSString **error) {
    const uint32_t NOP = 0xD503201Fu;
    const uint32_t LDP_X16_X17_POST = 0xA8C147F0u;
    for (uint64_t p = 0; p < reserved; p += 4) ZNV2Write32(base + fileOffset + p, NOP);
    ZNV2Write32(base + fileOffset, LDP_X16_X17_POST);
    const uint8_t *sourceBytes = (const uint8_t *)source.bytes;
    BOOL terminalSeen = NO; NSUInteger emittedLength = 0;
    for (NSUInteger i = 0; i < source.length; i += 4) {
        if (terminalSeen) break;
        uint32_t relocated = 0; BOOL terminal = NO;
        if (!ZNV2Relocate(ZNV2Read32(sourceBytes + i), sourceRVA + i, variantRVA + 4 + i,
                          windowStart, windowEnd, &relocated, &terminal, error)) return NO;
        ZNV2Write32(base + fileOffset + 4 + i, relocated);
        emittedLength = i + 4; if (terminal) terminalSeen = YES;
    }
    if (!terminalSeen) {
        uint32_t resumeBranch = 0; uint64_t branchRVA = variantRVA + 4 + emittedLength;
        if (!ZNV2EncodeB(branchRVA, resumeRVA, NO, &resumeBranch)) { if(error)*error=@"Variant 返回原代码超出 ±128MB"; return NO; }
        ZNV2Write32(base + fileOffset + 4 + emittedLength, resumeBranch);
    }
    return YES;
}

static void ZNV2CopyFixed(char *destination, size_t capacity, NSString *string) {
    memset(destination, 0, capacity);
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length || !capacity) return;
    memcpy(destination, data.bytes, std::min(capacity - 1, (size_t)data.length));
}

static NSData *ZNV2ComposedVariant(const ZNV2Physical &physical, const ZNV2Logical &logical) {
    NSMutableData *data = [physical.original mutableCopy];
    if (!data || logical.enabled.length > data.length) return nil;
    [data replaceBytesInRange:NSMakeRange(0, logical.enabled.length) withBytes:logical.enabled.bytes];
    return data;
}

static BOOL ZNV2BuildTarget(NSString *target,
                            NSArray<ZNBinaryPatchRow *> *rows,
                            NSString *folder,
                            NSString **outPath,
                            NSDictionary **metadata,
                            NSString **error) {
    NSDictionary *module = [[ZNModuleManager sharedManager] moduleNamed:target];
    if (!module) { if(error)*error=[NSString stringWithFormat:@"目标模块未加载：%@",target]; return NO; }
    NSString *inputPath = module[@"path"];
    if (!inputPath.length) { if(error)*error=@"无法取得目标 Mach-O 路径"; return NO; }
    NSString *name = inputPath.lastPathComponent.length ? inputPath.lastPathComponent : target;
    NSString *outputPath = [folder stringByAppendingPathComponent:[name stringByAppendingString:@".znpatched"]];
    NSFileManager *fm = NSFileManager.defaultManager; [fm removeItemAtPath:outputPath error:nil];
    NSError *copyError=nil;
    if (![fm copyItemAtPath:inputPath toPath:outputPath error:&copyError]) { if(error)*error=[NSString stringWithFormat:@"复制目标失败：%@",copyError.localizedDescription?:@"未知错误"]; return NO; }

    int fd=open(outputPath.fileSystemRepresentation,O_RDWR);
    if(fd<0){[fm removeItemAtPath:outputPath error:nil];if(error)*error=[NSString stringWithFormat:@"打开输出文件失败：errno=%d",errno];return NO;}
    struct stat st={};
    if(fstat(fd,&st)!=0||st.st_size<=0){close(fd);[fm removeItemAtPath:outputPath error:nil];if(error)*error=@"读取输出文件大小失败";return NO;}
    size_t fileSize=(size_t)st.st_size;
    uint8_t *base=(uint8_t *)mmap(NULL,fileSize,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(base==MAP_FAILED){close(fd);[fm removeItemAtPath:outputPath error:nil];if(error)*error=@"mmap 输出文件失败";return NO;}

    BOOL success=NO; NSString *localError=nil; std::vector<ZNV2Segment> segments; uint64_t imageVMBase=0;
    do {
        if(!ZNV2Parse(base,fileSize,segments,imageVMBase,&localError))break;
        if(rows.count>ZN44_STATIC_MAX_ENTRIES){localError=@"Patch 数量超过 Static Dispatch 上限";break;}

        std::vector<ZNV2Logical> logicals; logicals.reserve(rows.count);
        for(ZNBinaryPatchRow *row in rows){
            NSData *enabled=row.validator.patchBytes; NSData *liveOriginal=row.validator.capturedOriginalBytes;
            if(!enabled.length||!liveOriginal.length||enabled.length!=liveOriginal.length||(enabled.length&3u)){
                localError=@"Patch 必须已验证，且 Enabled/Original 长度一致并为 4-byte 倍数";break;
            }
            uint64_t rva=row.validator.rva,fileOffset=0;size_t segmentIndex=0;
            if(!ZNV2RVAToFile(segments,imageVMBase,rva,enabled.length,fileOffset,segmentIndex)){
                localError=[NSString stringWithFormat:@"%@+0x%llX 无法映射到 file offset",target,rva];break;
            }
            if(!(segments[segmentIndex].initprot&VM_PROT_EXECUTE)||!ZNV2InstructionRange(segments,imageVMBase,rva,enabled.length)){
                localError=[NSString stringWithFormat:@"%@+0x%llX 不在可确认的 ARM64 instruction section",target,rva];break;
            }
            NSData *diskOriginal=[NSData dataWithBytes:base+fileOffset length:enabled.length];
            if(![diskOriginal isEqualToData:liveOriginal]){
                localError=[NSString stringWithFormat:@"%@+0x%llX 磁盘原字节与 Live Original 不一致",target,rva];break;
            }
            logicals.push_back({row,rva,fileOffset,(uint64_t)enabled.length,segmentIndex,diskOriginal,enabled});
        }
        if(localError)break;

        std::vector<ZNV2Physical> physicals;
        std::vector<size_t> logicalToPhysical(logicals.size(),0);
        for(size_t i=0;i<logicals.size();i++){
            ZNV2Logical &logical=logicals[i]; size_t pIndex=SIZE_MAX;
            for(size_t p=0;p<physicals.size();p++)if(physicals[p].rva==logical.rva){pIndex=p;break;}
            if(pIndex==SIZE_MAX){
                ZNV2Physical physical={}; physical.rva=logical.rva;physical.fileoff=logical.fileoff;physical.window=logical.length;physical.segIndex=logical.segIndex;physical.members.push_back(i);physical.original=nil;physical.thunkRVA=0;physical.offRVA=0;
                physicals.push_back(physical);pIndex=physicals.size()-1;
            }else{
                ZNV2Physical &physical=physicals[pIndex];
                physical.window=std::max(physical.window,logical.length);physical.members.push_back(i);
            }
            logicalToPhysical[i]=pIndex;
        }

        std::vector<uint64_t> siteRVAs;
        for(size_t p=0;p<physicals.size();p++){
            ZNV2Physical &physical=physicals[p];uint64_t mapped=0;size_t segIndex=0;
            if(!ZNV2RVAToFile(segments,imageVMBase,physical.rva,physical.window,mapped,segIndex)||mapped!=physical.fileoff||segIndex!=physical.segIndex){
                localError=[NSString stringWithFormat:@"%@+0x%llX Shared Site 最大窗口无法映射",target,physical.rva];break;
            }
            if(!ZNV2InstructionRange(segments,imageVMBase,physical.rva,physical.window)){
                localError=[NSString stringWithFormat:@"%@+0x%llX Shared Site 最大窗口不在 instruction section",target,physical.rva];break;
            }
            if(ZNV2InboundInterior(base,segments,imageVMBase,physical.rva,physical.window)){
                localError=[NSString stringWithFormat:@"%@+0x%llX Shared Site 覆盖窗口内部存在直接分支目标",target,physical.rva];break;
            }
            physical.original=[NSData dataWithBytes:base+physical.fileoff length:physical.window];siteRVAs.push_back(physical.rva);
        }
        if(localError)break;

        // Same starting RVA has already been merged. Any overlap between two
        // different physical starts remains unsafe and is intentionally rejected.
        for(size_t a=0;a<physicals.size();a++){
            for(size_t b=a+1;b<physicals.size();b++){
                uint64_t aStart=physicals[a].rva,aEnd=aStart+physicals[a].window;
                uint64_t bStart=physicals[b].rva,bEnd=bStart+physicals[b].window;
                if(aStart<bEnd&&bStart<aEnd){localError=[NSString stringWithFormat:@"不同起点 Patch 覆盖窗口重叠：0x%llX / 0x%llX",aStart,bStart];break;}
            }
            if(localError)break;
        }
        if(localError)break;

        const uint64_t thunkSize=24;uint64_t codeNeeded=0;
        for(const ZNV2Physical &physical:physicals){
            uint64_t variantSize=ZNV2Align(4+physical.window+4,16);NSMutableArray<NSData *> *unique=[NSMutableArray array];
            for(size_t logicalIndex:physical.members){NSData *source=ZNV2ComposedVariant(physical,logicals[logicalIndex]);if(!source){localError=@"Shared Site Variant 合成失败";break;}BOOL exists=NO;for(NSData *x in unique)if([x isEqualToData:source]){exists=YES;break;}if(!exists)[unique addObject:source];}
            if(localError)break;codeNeeded=ZNV2Align(codeNeeded,16)+thunkSize+variantSize*(1+unique.count);
        }
        if(localError)break;codeNeeded+=32;
        uint64_t dataNeeded=ZNV2Align(sizeof(ZN44StaticHeader)+logicals.size()*sizeof(ZN44StaticEntry),8);
        std::vector<ZNV2Gap> codeGaps=ZNV2Gaps(base,segments,imageVMBase,YES,codeNeeded,siteRVAs);
        std::vector<ZNV2Gap> dataGaps=ZNV2Gaps(base,segments,imageVMBase,NO,dataNeeded,{});
        if(codeGaps.empty()){localError=@"无安全 executable gap：Shared-Site V2 不会猜测 code cave";break;}
        if(dataGaps.empty()){localError=@"无安全 writable gap：Shared-Site V2 拒绝生成";break;}
        ZNV2Gap codeGap=codeGaps.front(),dataGap=dataGaps.front();

        ZN44StaticHeader *header=(ZN44StaticHeader *)(base+dataGap.fileoff);memset(header,0,dataNeeded);
        header->magic0=ZN44_STATIC_MAGIC0;header->magic1=ZN44_STATIC_MAGIC1;header->version=ZN44_STATIC_VERSION_V2;header->count=(uint32_t)logicals.size();header->entrySize=sizeof(ZN44StaticEntry);
        ZN44StaticEntry *entries=(ZN44StaticEntry *)(header+1);
        std::vector<uint64_t> onRVAs(logicals.size(),0);
        const uint32_t STP_X16_X17_PRE=0xA9BF47F0u,CBNZ_X17_PLUS_8=0xB5000051u,BR_X17=0xD61F0220u,NOP=0xD503201Fu;
        uint64_t codeCursor=codeGap.fileoff;

        for(size_t p=0;p<physicals.size();p++){
            ZNV2Physical &physical=physicals[p];codeCursor=ZNV2Align(codeCursor,16);
            uint64_t thunkFileOffset=codeCursor;uint64_t thunkRVA=ZNV2FileToRVA(segments[codeGap.segIndex],imageVMBase,thunkFileOffset);codeCursor+=thunkSize;
            uint64_t variantSize=ZNV2Align(4+physical.window+4,16);
            uint64_t offFileOffset=ZNV2Align(codeCursor,16);uint64_t offRVA=ZNV2FileToRVA(segments[codeGap.segIndex],imageVMBase,offFileOffset);codeCursor=offFileOffset+variantSize;
            physical.thunkRVA=thunkRVA;physical.offRVA=offRVA;
            if(!ZNV2WriteVariant(base,offFileOffset,offRVA,variantSize,physical.original,physical.rva,physical.rva,physical.rva+physical.window,physical.rva+physical.window,&localError))break;

            NSMutableArray<NSData *> *writtenSources=[NSMutableArray array];NSMutableArray<NSNumber *> *writtenRVAs=[NSMutableArray array];
            for(size_t logicalIndex:physical.members){
                NSData *source=ZNV2ComposedVariant(physical,logicals[logicalIndex]);NSUInteger found=NSNotFound;
                for(NSUInteger j=0;j<writtenSources.count;j++)if([writtenSources[j] isEqualToData:source]){found=j;break;}
                if(found!=NSNotFound){onRVAs[logicalIndex]=writtenRVAs[found].unsignedLongLongValue;continue;}
                uint64_t onFileOffset=ZNV2Align(codeCursor,16);uint64_t onRVA=ZNV2FileToRVA(segments[codeGap.segIndex],imageVMBase,onFileOffset);codeCursor=onFileOffset+variantSize;
                if(!ZNV2WriteVariant(base,onFileOffset,onRVA,variantSize,source,physical.rva,physical.rva,physical.rva+physical.window,physical.rva+physical.window,&localError))break;
                [writtenSources addObject:source];[writtenRVAs addObject:@(onRVA)];onRVAs[logicalIndex]=onRVA;
            }
            if(localError)break;

            size_t canonicalLogical=physical.members.front();uint64_t entryRVA=dataGap.rva+sizeof(ZN44StaticHeader)+canonicalLogical*sizeof(ZN44StaticEntry);
            if(entryRVA&7u){localError=@"Shared Site canonical selectedTarget 未 8-byte 对齐";break;}
            uint32_t adrp=0,offBranch=0;
            if(!ZNV2EncodeADRPX17(thunkRVA+4,entryRVA,&adrp)){localError=@"Thunk → canonical selectedTarget ADRP 超出 ±4GB";break;}
            if(!ZNV2EncodeB(thunkRVA+16,offRVA,NO,&offBranch)){localError=@"Thunk boot-safe OFF fallback 超出 ±128MB";break;}
            ZNV2Write32(base+thunkFileOffset+0,STP_X16_X17_PRE);ZNV2Write32(base+thunkFileOffset+4,adrp);ZNV2Write32(base+thunkFileOffset+8,ZNV2LdrX17FromX17(entryRVA));ZNV2Write32(base+thunkFileOffset+12,CBNZ_X17_PLUS_8);ZNV2Write32(base+thunkFileOffset+16,offBranch);ZNV2Write32(base+thunkFileOffset+20,BR_X17);
            uint32_t siteBranch=0;if(!ZNV2EncodeB(physical.rva,thunkRVA,NO,&siteBranch)){localError=@"Site → shared thunk 超出 ±128MB";break;}
            ZNV2Write32(base+physical.fileoff,siteBranch);for(uint64_t q=4;q<physical.window;q+=4)ZNV2Write32(base+physical.fileoff+q,NOP);
        }
        if(localError)break;

        for(size_t i=0;i<logicals.size();i++){
            ZNV2Logical &logical=logicals[i];ZNV2Physical &physical=physicals[logicalToPhysical[i]];ZN44StaticEntry &entry=entries[i];memset(&entry,0,sizeof(entry));
            entry.offRVA=physical.offRVA;entry.onRVA=onRVAs[i];entry.siteRVA=physical.rva;entry.windowLength=(uint32_t)physical.window;entry.patchID=(uint32_t)i+1;entry.enabledLength=(uint32_t)logical.enabled.length;
            entry.physicalID=(uint32_t)logicalToPhysical[i]+1;entry.canonicalIndex=(uint32_t)physical.members.front();entry.flags=(i==physical.members.front()?ZN44_STATIC_ENTRY_FLAG_CANONICAL:0u)|(physical.members.size()>1?ZN44_STATIC_ENTRY_FLAG_SHARED:0u);
            ZNV2CopyFixed(entry.title,sizeof(entry.title),logical.row.title.length?logical.row.title:[NSString stringWithFormat:@"Patch #%u",entry.patchID]);
            ZNV2CopyFixed(entry.group,sizeof(entry.group),logical.row.group.length?logical.row.group:@"Imported");
        }

        if(msync(base,fileSize,MS_SYNC)!=0){localError=[NSString stringWithFormat:@"msync 失败：errno=%d",errno];break;}
        success=YES;
        NSUInteger sharedSites=0;for(const ZNV2Physical &p:physicals)if(p.members.size()>1)sharedSites++;
        if(metadata)*metadata=@{@"target":target,@"input":inputPath,@"output":outputPath,@"logicalPatchCount":@(logicals.size()),@"physicalSiteCount":@(physicals.size()),@"sharedSiteCount":@(sharedSites),@"codeGapRVA":[NSString stringWithFormat:@"0x%llX",codeGap.rva],@"dataGapRVA":[NSString stringWithFormat:@"0x%llX",dataGap.rva],@"ownerPolicy":@"last-enabled-active-owner-wins",@"bootSafeOffFallback":@YES,@"needsResign":@YES};
        if(outPath)*outPath=outputPath;
    }while(0);

    munmap(base,fileSize);close(fd);
    if(!success){[fm removeItemAtPath:outputPath error:nil];if(error)*error=localError?:@"Shared-Site V2 生成失败";}
    return success;
}

static BOOL ZNV2WorkspaceHasSharedSite(ZNBinaryPatchWorkspace *workspace) {
    NSMutableSet<NSString *> *seen=[NSMutableSet set];
    for(ZNBinaryPatchRow *row in workspace.rows){
        if(!row.offsetText.length&&!row.enabledText.length)continue;
        if(!row.validated||!row.validator)continue;
        NSString *target=(row.explicitTarget&&row.target.length)?row.target:workspace.defaultTarget;
        NSString *key=[NSString stringWithFormat:@"%@|%llx",target.lowercaseString,row.validator.rva];
        if([seen containsObject:key])return YES;[seen addObject:key];
    }
    return NO;
}

static BOOL ZNV2BuildWorkspace(ZNBinaryPatchWorkspace *workspace,
                               NSArray<NSString *> **outputs,
                               NSString **report,
                               NSString **error) {
    if(!workspace||workspace.hasAnyApplied){if(error)*error=@"生成前必须恢复所有临时 Runtime Patch";return NO;}
    if(!workspace.filledCount){if(error)*error=@"没有 Patch";return NO;}
    NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *groups=[NSMutableDictionary dictionary];
    for(ZNBinaryPatchRow *row in workspace.rows){
        if(!row.offsetText.length&&!row.enabledText.length)continue;
        if(!row.validated||!row.validator){if(error)*error=@"所有已填写 Patch 必须先“读取验证”通过";return NO;}
        NSString *target=(row.explicitTarget&&row.target.length)?row.target:workspace.defaultTarget;if(!groups[target])groups[target]=[NSMutableArray array];[groups[target] addObject:row];
    }
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ZonoePatchOutput"];NSDateFormatter *formatter=[NSDateFormatter new];formatter.dateFormat=@"yyyyMMdd-HHmmss";NSString *folder=[root stringByAppendingPathComponent:[formatter stringFromDate:[NSDate date]]];
    NSError *directoryError=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&directoryError]){if(error)*error=directoryError.localizedDescription?:@"创建输出目录失败";return NO;}
    NSMutableArray<NSString *> *paths=[NSMutableArray array];NSMutableArray<NSDictionary *> *metadata=[NSMutableArray array];NSString *failure=nil;
    for(NSString *target in groups){NSString *path=nil,*targetError=nil;NSDictionary *targetMetadata=nil;if(!ZNV2BuildTarget(target,groups[target],folder,&path,&targetMetadata,&targetError)){failure=[NSString stringWithFormat:@"%@：%@",target,targetError?:@"生成失败"];break;}if(path.length)[paths addObject:path];if(targetMetadata)[metadata addObject:targetMetadata];}
    if(failure){[NSFileManager.defaultManager removeItemAtPath:folder error:nil];if(error)*error=failure;return NO;}
    NSDictionary *reportObject=@{@"format":@"com.zonoe.static-dispatch/v2-shared-site",@"generatedAt":[[NSDate date] description],@"targets":metadata,@"notes":@[@"Same Target + same starting RVA is one physical site",@"Different Enabled values become logical variants",@"Short variants are composed with the original tail before relocation",@"Runtime owner policy: most recently enabled active owner wins",@"Disabling the selected owner falls back to the previous active owner",@"No active owner selects relocated Original",@"Different-start overlapping windows remain a hard conflict",@"Runtime changes RW selectedTarget only; executable pages are not modified",@"Output Mach-O must be re-signed before installation"]};
    NSData *json=[NSJSONSerialization dataWithJSONObject:reportObject options:NSJSONWritingPrettyPrinted error:nil];NSString *reportPath=[folder stringByAppendingPathComponent:@"build_report.json"];[json writeToFile:reportPath atomically:YES];[paths addObject:reportPath];
    if(outputs)*outputs=paths;if(report)*report=[NSString stringWithFormat:@"Shared-Site V2 生成成功：%lu 个目标 · %lu 个逻辑 Patch\n输出：%@\n同 Offset 多 Variant 已合并为单一物理 Site；必须重新签名后安装",(unsigned long)groups.count,(unsigned long)workspace.filledCount,folder];return YES;
}

@implementation ZNStaticBinaryBuilder (ZNSharedSiteV2)

+ (void)load {
    static dispatch_once_t onceToken;dispatch_once(&onceToken,^{
        Class meta=object_getClass((id)self);
        Method original=class_getClassMethod(self,@selector(buildWorkspace:outputs:report:error:));
        Method replacement=class_getClassMethod(self,@selector(znv2_buildWorkspace:outputs:report:error:));
        if(meta&&original&&replacement)method_exchangeImplementations(original,replacement);
    });
}

+ (BOOL)znv2_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
                    outputs:(NSArray<NSString *> **)outputs
                     report:(NSString **)report
                      error:(NSString **)error {
    if(!ZNV2WorkspaceHasSharedSite(workspace)){
        // After method_exchangeImplementations this selector points to the
        // original V1 implementation. Ordinary projects therefore keep their
        // existing builder behavior byte-for-byte.
        return [self znv2_buildWorkspace:workspace outputs:outputs report:report error:error];
    }
    return ZNV2BuildWorkspace(workspace,outputs,report,error);
}

@end
