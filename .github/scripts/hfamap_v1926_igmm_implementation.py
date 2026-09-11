from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()
l = legacy_path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


# v1.9.26:
# - keep v1.9.25 dual JSON export and the legacy ordinary Patch path intact
# - resolve iGMM runtime implementations from the actual menu image generically
# - map feature identifiers -> CFString xrefs -> containing native handler
# - recover a handler's original-function slot when it tail-dispatches through
#   a data pointer
# - for button blocks, follow a referenced nested block and recover a computed
#   slide+RVA branch target when it resolves uniquely among loaded images
# - no game class names, labels, ivar names or sample RVAs are hardcoded

s = replace_once(
    s,
    '[HFALearn v1.9.25 DualIOSGodsJSONExport] loaded',
    '[HFALearn v1.9.26 iGMMImplementationResolver] loaded',
    'update core marker',
)
l = replace_once(
    l,
    '[HFALearn UI v1.9.25 DualIOSGodsJSONExport] loaded',
    '[HFALearn UI v1.9.26 iGMMImplementationResolver] loaded',
    'update UI marker',
)
l = replace_once(
    l,
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-definition export=legacy-v1+igmm-v1',
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-implementation export=legacy-v1+igmm-v1',
    'update dual mode marker',
)

anchor = 'static void HFAWriteIGMMPackage(id menuTarget, NSArray *rawFeatures) {\n'
helper = r'''typedef struct {
    uintptr_t isa;
    uint32_t flags;
    uint32_t reserved;
    uintptr_t chars;
    uint64_t length;
} HFAIGMM26CFStringRecord;

static const char *HFAIGMM26Base(const char *path) {
    if (!path) return "?";
    const char *p = strrchr(path, '/');
    return p ? p + 1 : path;
}

static int HFAIGMM26ImageIndex(const char *imageName) {
    if (!imageName || !*imageName) return -1;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *path = _dyld_get_image_name(i);
        if (path && strcmp(HFAIGMM26Base(path), imageName) == 0)
            return (int)i;
    }
    return -1;
}

static int HFAIGMM26Section(uint32_t imageIndex, const char *sectionName,
                            uintptr_t *addressOut, uintptr_t *rvaOut,
                            size_t *sizeOut) {
    const struct mach_header *mh = _dyld_get_image_header(imageIndex);
    if (!mh || mh->magic != MH_MAGIC_64 || !sectionName) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (!lc->cmdsize) break;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *sec =
                (const struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                if (strncmp(sec->sectname, sectionName, 16) != 0) continue;
                if (addressOut)
                    *addressOut = (uintptr_t)((intptr_t)slide +
                                              (intptr_t)sec->addr);
                if (rvaOut) *rvaOut = (uintptr_t)sec->addr;
                if (sizeOut) *sizeOut = (size_t)sec->size;
                return 1;
            }
        }
        cursor += lc->cmdsize;
    }
    return 0;
}

static int64_t HFAIGMM26SignExtend(uint64_t value, unsigned bits) {
    uint64_t sign = 1ULL << (bits - 1);
    return (int64_t)((value ^ sign) - sign);
}

static uintptr_t HFAIGMM26ADRP(uintptr_t pc, uint32_t word) {
    if ((word & 0x9F000000u) != 0x90000000u) return 0;
    uint64_t immlo = (word >> 29) & 3u;
    uint64_t immhi = (word >> 5) & 0x7FFFFu;
    int64_t pages = HFAIGMM26SignExtend((immhi << 2) | immlo, 21);
    return (pc & ~(uintptr_t)0xFFFu) + (uintptr_t)(pages << 12);
}

static int HFAIGMM26ADDImmediate(uint32_t word, unsigned *rnOut,
                                uintptr_t *immOut) {
    if ((word & 0x7F000000u) != 0x11000000u) return 0;
    unsigned rn = (word >> 5) & 31u;
    uintptr_t imm = (uintptr_t)((word >> 10) & 0xFFFu);
    if ((word >> 22) & 1u) imm <<= 12;
    if (rnOut) *rnOut = rn;
    if (immOut) *immOut = imm;
    return 1;
}

static int HFAIGMM26FunctionBoundsFromFile(const char *imageName,
                                           uintptr_t targetRVA,
                                           uintptr_t *startOut,
                                           uintptr_t *endOut) {
    int imageIndex = HFAIGMM26ImageIndex(imageName);
    if (imageIndex < 0 || !targetRVA) return 0;
    const char *path = _dyld_get_image_name((uint32_t)imageIndex);
    if (!path) return 0;
    NSData *imageData = [NSData dataWithContentsOfFile:
        [NSString stringWithUTF8String:path]];
    if (!imageData || imageData.length < sizeof(struct mach_header_64))
        return 0;
    const uint8_t *bytes = (const uint8_t *)imageData.bytes;
    size_t length = imageData.length;
    const struct mach_header_64 *h = (const struct mach_header_64 *)bytes;
    if (h->magic != MH_MAGIC_64 ||
        sizeof(*h) + (size_t)h->sizeofcmds > length) return 0;

    const uint8_t *cursor = bytes + sizeof(*h);
    uint64_t textVMAddr = 0, textEnd = 0;
    uint32_t dataOff = 0, dataSize = 0;
    for (uint32_t i = 0; i < h->ncmds; i++) {
        if ((size_t)(cursor - bytes) + sizeof(struct load_command) > length)
            return 0;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (!lc->cmdsize ||
            (size_t)(cursor - bytes) + lc->cmdsize > length) return 0;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *sec =
                (const struct section_64 *)(seg + 1);
            if (lc->cmdsize >= sizeof(*seg) +
                (size_t)seg->nsects * sizeof(struct section_64)) {
                for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                    if (strncmp(sec->sectname, "__text", 16) == 0) {
                        textVMAddr = seg->vmaddr;
                        textEnd = sec->addr + sec->size;
                    }
                }
            }
        } else if (lc->cmd == LC_FUNCTION_STARTS &&
                   lc->cmdsize >= sizeof(struct linkedit_data_command)) {
            const struct linkedit_data_command *cmd =
                (const struct linkedit_data_command *)cursor;
            dataOff = cmd->dataoff;
            dataSize = cmd->datasize;
        }
        cursor += lc->cmdsize;
    }
    if (!textEnd || !dataOff || !dataSize ||
        (uint64_t)dataOff + dataSize > length) return 0;

    const uint8_t *data = bytes + dataOff;
    size_t off = 0;
    uint64_t cumulative = 0;
    uintptr_t previous = 0;
    while (off < dataSize) {
        uint64_t delta = 0;
        unsigned shift = 0;
        int done = 0;
        while (off < dataSize && shift < 64) {
            uint8_t b = data[off++];
            delta |= ((uint64_t)(b & 0x7Fu)) << shift;
            if (!(b & 0x80u)) { done = 1; break; }
            shift += 7;
        }
        if (!done || !delta) break;
        cumulative += delta;
        uintptr_t current = (uintptr_t)(textVMAddr + cumulative);
        if (current > targetRVA) {
            if (previous && targetRVA >= previous) {
                if (startOut) *startOut = previous;
                if (endOut) *endOut = current;
                return 1;
            }
            break;
        }
        previous = current;
    }
    if (previous && targetRVA >= previous && textEnd > previous) {
        if (startOut) *startOut = previous;
        if (endOut) *endOut = (uintptr_t)textEnd;
        return 1;
    }
    return 0;
}

static uintptr_t HFAIGMM26FindCFString(uint32_t imageIndex,
                                      const char *identifier) {
    if (!identifier || !*identifier) return 0;
    uintptr_t sectionAddress = 0, sectionRVA = 0;
    size_t sectionSize = 0;
    if (!HFAIGMM26Section(imageIndex, "__cfstring", &sectionAddress,
                          &sectionRVA, &sectionSize)) return 0;
    size_t wanted = strlen(identifier);
    for (size_t off = 0; off + sizeof(HFAIGMM26CFStringRecord) <= sectionSize;
         off += sizeof(HFAIGMM26CFStringRecord)) {
        uintptr_t recordAddress = sectionAddress + off;
        if (!HFAReadable(recordAddress, sizeof(HFAIGMM26CFStringRecord)))
            continue;
        HFAIGMM26CFStringRecord rec = {0};
        memcpy(&rec, (const void *)recordAddress, sizeof(rec));
        if (rec.length != wanted || !rec.chars ||
            !HFAReadable(rec.chars, wanted)) continue;
        if (memcmp((const void *)rec.chars, identifier, wanted) == 0)
            return recordAddress;
    }
    return 0;
}

static NSDictionary *HFAIGMM26OriginalDispatch(uint32_t imageIndex,
                                               const char *imageName,
                                               uintptr_t startRVA,
                                               uintptr_t endRVA) {
    if (!imageName || !startRVA || endRVA <= startRVA) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    uintptr_t start = (uintptr_t)((intptr_t)slide + (intptr_t)startRVA);
    size_t wordCount = (size_t)(endRVA - startRVA) / 4;
    if (!wordCount || wordCount > 4096 || !HFAReadable(start, wordCount * 4))
        return nil;

    for (size_t i = 0; i < wordCount; i++) {
        uint32_t br = 0;
        memcpy(&br, (const void *)(start + i * 4), 4);
        if ((br & 0xFFFFFC1Fu) != 0xD61F0000u) continue;
        unsigned branchReg = (br >> 5) & 31u;

        size_t backLDR = i > 24 ? i - 24 : 0;
        for (size_t j = i; j-- > backLDR;) {
            uint32_t ldr = 0;
            memcpy(&ldr, (const void *)(start + j * 4), 4);
            if ((ldr & 0xFFC00000u) != 0xF9400000u) continue;
            unsigned rt = ldr & 31u;
            unsigned rn = (ldr >> 5) & 31u;
            if (rt != branchReg) continue;
            uintptr_t imm = (uintptr_t)((ldr >> 10) & 0xFFFu) << 3;

            size_t backADRP = j > 16 ? j - 16 : 0;
            for (size_t k = j; k-- > backADRP;) {
                uint32_t adrp = 0;
                uintptr_t pc = start + k * 4;
                memcpy(&adrp, (const void *)pc, 4);
                if ((adrp & 31u) != rn) continue;
                uintptr_t page = HFAIGMM26ADRP(pc, adrp);
                if (!page) continue;
                uintptr_t slot = page + imm;
                if (!HFAReadable(slot, sizeof(uintptr_t))) continue;

                uintptr_t target = 0;
                memcpy(&target, (const void *)slot, sizeof(target));
#if __has_feature(ptrauth_calls)
                target = (uintptr_t)ptrauth_strip((void *)target,
                                                  ptrauth_key_function_pointer);
#endif
                Dl_info info = {0};
                uintptr_t imageBase =
                    (uintptr_t)_dyld_get_image_header(imageIndex);
                NSString *slotOffset =
                    [NSString stringWithFormat:@"0x%llX",
                     (unsigned long long)(slot - imageBase)];
                NSMutableDictionary *result =
                    [@{ @"slot": @{ @"image":
                                         [NSString stringWithUTF8String:imageName],
                                     @"offset": slotOffset } } mutableCopy];
                if (target && dladdr((void *)target, &info) &&
                    info.dli_fbase && info.dli_fname) {
                    uintptr_t rva = target - (uintptr_t)info.dli_fbase;
                    result[@"target"] = @{
                        @"image": [NSString stringWithUTF8String:
                            HFAIGMM26Base(info.dli_fname)],
                        @"offset": [NSString stringWithFormat:@"0x%llX",
                            (unsigned long long)rva]
                    };
                    HFALog("[IGMM-IMPL-ORIGINAL] handler=%s+0x%llX slot=%s+%s target=%s+0x%llX\n",
                           imageName, (unsigned long long)startRVA,
                           imageName, slotOffset.UTF8String,
                           HFAIGMM26Base(info.dli_fname),
                           (unsigned long long)rva);
                } else {
                    HFALog("[IGMM-IMPL-ORIGINAL] handler=%s+0x%llX slot=%s+%s target=unresolved\n",
                           imageName, (unsigned long long)startRVA,
                           imageName, slotOffset.UTF8String);
                }
                return result;
            }
        }
    }
    return nil;
}

static NSDictionary *HFAIGMM26IdentifierImplementation(const char *imageName,
                                                       const char *identifier) {
    int imageIndex = HFAIGMM26ImageIndex(imageName);
    if (imageIndex < 0 || !identifier || !*identifier) return nil;
    uintptr_t cf = HFAIGMM26FindCFString((uint32_t)imageIndex, identifier);
    if (!cf) return nil;

    uintptr_t text = 0, textRVA = 0;
    size_t textSize = 0;
    if (!HFAIGMM26Section((uint32_t)imageIndex, "__text", &text, &textRVA,
                          &textSize) ||
        !HFAReadable(text, textSize)) return nil;

    uintptr_t starts[16] = {0}, ends[16] = {0};
    unsigned hits[16] = {0}, used = 0;
    for (size_t off = 0; off + 20 <= textSize; off += 4) {
        uintptr_t pc = text + off;
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);
        uintptr_t page = HFAIGMM26ADRP(pc, word);
        if (!page) continue;
        unsigned adrpReg = word & 31u;
        for (size_t ahead = 4; ahead <= 16; ahead += 4) {
            uint32_t next = 0;
            memcpy(&next, (const void *)(pc + ahead), 4);
            unsigned rn = 0;
            uintptr_t imm = 0;
            if (!HFAIGMM26ADDImmediate(next, &rn, &imm) ||
                rn != adrpReg || page + imm != cf) continue;
            uintptr_t xrefRVA = textRVA + off;
            uintptr_t startRVA = 0, endRVA = 0;
            if (!HFAIGMM26FunctionBoundsFromFile(imageName, xrefRVA,
                                                  &startRVA, &endRVA))
                break;
            unsigned found = 0;
            for (unsigned k = 0; k < used; k++) {
                if (starts[k] == startRVA) {
                    hits[k]++;
                    found = 1;
                    break;
                }
            }
            if (!found && used < 16) {
                starts[used] = startRVA;
                ends[used] = endRVA;
                hits[used] = 1;
                used++;
            }
            break;
        }
    }
    if (!used) return nil;
    unsigned best = 0;
    for (unsigned i = 1; i < used; i++)
        if (hits[i] > hits[best]) best = i;

    uintptr_t startRVA = starts[best], endRVA = ends[best];
    NSMutableDictionary *impl = [@{
        @"kind": @"nativeIdentifierHandler",
        @"source": @"cfstring-xref",
        @"image": [NSString stringWithUTF8String:imageName],
        @"offset": [NSString stringWithFormat:@"0x%llX",
                     (unsigned long long)startRVA],
        @"functionEnd": [NSString stringWithFormat:@"0x%llX",
                         (unsigned long long)endRVA],
        @"xrefCount": @(hits[best])
    } mutableCopy];
    NSDictionary *dispatch =
        HFAIGMM26OriginalDispatch((uint32_t)imageIndex, imageName,
                                  startRVA, endRVA);
    if (dispatch) [impl addEntriesFromDictionary:dispatch];
    HFALog("[IGMM-IMPL-XREF] identifier=%s handler=%s+0x%llX end=0x%llX xrefs=%u\n",
           identifier, imageName, (unsigned long long)startRVA,
           (unsigned long long)endRVA, hits[best]);
    return impl;
}

static int HFAIGMM26ExecutableRVACandidate(uint32_t imageIndex,
                                          uintptr_t rva,
                                          uintptr_t *addressOut) {
    const struct mach_header *mh = _dyld_get_image_header(imageIndex);
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (!lc->cmdsize) break;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *sec =
                (const struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                uint32_t attrs = sec->flags &
                    (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS);
                if (!attrs || rva < (uintptr_t)sec->addr ||
                    rva >= (uintptr_t)(sec->addr + sec->size)) continue;
                uintptr_t address =
                    (uintptr_t)((intptr_t)slide + (intptr_t)rva);
                if (!HFAReadable(address, 4)) continue;
                if (addressOut) *addressOut = address;
                return 1;
            }
        }
        cursor += lc->cmdsize;
    }
    return 0;
}

static NSDictionary *HFAIGMM26ResolveExecutableRVA(uintptr_t rva) {
    if (!rva) return nil;
    uint32_t count = _dyld_image_count();
    unsigned candidates = 0;
    uint32_t chosen = 0;
    uintptr_t chosenAddress = 0;
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t address = 0;
        if (!HFAIGMM26ExecutableRVACandidate(i, rva, &address)) continue;
        candidates++;
        chosen = i;
        chosenAddress = address;
    }
    NSMutableDictionary *result = [@{
        @"offset": [NSString stringWithFormat:@"0x%llX",
                    (unsigned long long)rva],
        @"candidates": @(candidates)
    } mutableCopy];
    if (candidates == 1) {
        const char *path = _dyld_get_image_name(chosen);
        result[@"image"] = [NSString stringWithUTF8String:HFAIGMM26Base(path)];
        result[@"addressResolved"] = @YES;
        (void)chosenAddress;
    } else {
        result[@"addressResolved"] = @NO;
    }
    return result;
}

static int HFAIGMM26MoveWide(uint32_t word, uint64_t *values,
                             uint8_t *valid) {
    uint32_t top = word & 0x7F800000u;
    unsigned rd = word & 31u;
    unsigned hw = (word >> 21) & 3u;
    unsigned shift = hw * 16u;
    uint64_t imm = (uint64_t)((word >> 5) & 0xFFFFu) << shift;
    if (top == 0x52800000u) {
        values[rd] = imm;
        valid[rd] = 1;
        return 1;
    }
    if (top == 0x72800000u) {
        if (!valid[rd]) return 0;
        uint64_t mask = ~((uint64_t)0xFFFFu << shift);
        values[rd] = (values[rd] & mask) | imm;
        return 1;
    }
    return 0;
}

static NSDictionary *HFAIGMM26ComputedBranchTarget(uint32_t imageIndex,
                                                   const char *imageName,
                                                   uintptr_t startRVA,
                                                   uintptr_t endRVA) {
    if (!startRVA || endRVA <= startRVA) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    uintptr_t start = (uintptr_t)((intptr_t)slide + (intptr_t)startRVA);
    size_t words = (size_t)(endRVA - startRVA) / 4;
    if (!words || words > 512 || !HFAReadable(start, words * 4)) return nil;
    uint64_t values[32] = {0};
    uint8_t valid[32] = {0};

    for (size_t i = 0; i < words; i++) {
        uint32_t w = 0;
        memcpy(&w, (const void *)(start + i * 4), 4);
        if (HFAIGMM26MoveWide(w, values, valid)) continue;

        if ((w & 0xFF200000u) == 0x8B000000u) {
            unsigned rd = w & 31u;
            unsigned rn = (w >> 5) & 31u;
            unsigned rm = (w >> 16) & 31u;
            if (rd == rn && valid[rm] && values[rm]) {
                for (size_t ahead = 1; ahead <= 4 && i + ahead < words;
                     ahead++) {
                    uint32_t next = 0;
                    memcpy(&next, (const void *)(start + (i + ahead) * 4), 4);
                    if ((next & 0xFFFFFC1Fu) == 0xD61F0000u &&
                        ((next >> 5) & 31u) == rd) {
                        uintptr_t rva = (uintptr_t)values[rm];
                        NSDictionary *resolved =
                            HFAIGMM26ResolveExecutableRVA(rva);
                        if (!resolved) return nil;
                        HFALog("[IGMM-IMPL-COMPUTED-TARGET] handler=%s+0x%llX targetRVA=0x%llX candidates=%u image=%s\n",
                               imageName, (unsigned long long)startRVA,
                               (unsigned long long)rva,
                               [resolved[@"candidates"] unsignedIntValue],
                               [resolved[@"image"] UTF8String] ?: "?");
                        return resolved;
                    }
                }
            }
        }

        unsigned rd = w & 31u;
        if ((w & 0x1F000000u) != 0x10000000u &&
            (w & 0x1F000000u) != 0x12000000u)
            valid[rd] = 0;
    }
    return nil;
}

static NSDictionary *HFAIGMM26NestedBlockImplementation(
    const char *imageName, NSDictionary *handler) {
    if (!imageName || !handler) return nil;
    NSString *offsetString = handler[@"offset"];
    if (![offsetString isKindOfClass:[NSString class]]) return nil;
    uintptr_t handlerRVA = (uintptr_t)strtoull(offsetString.UTF8String, NULL, 0);
    int imageIndex = HFAIGMM26ImageIndex(imageName);
    if (imageIndex < 0 || !handlerRVA) return nil;

    uintptr_t startRVA = 0, endRVA = 0;
    if (!HFAIGMM26FunctionBoundsFromFile(imageName, handlerRVA,
                                          &startRVA, &endRVA)) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t start = (uintptr_t)((intptr_t)slide + (intptr_t)startRVA);
    size_t size = (size_t)(endRVA - startRVA);
    if (!size || size > 0x1000 || !HFAReadable(start, size)) return nil;

    for (size_t off = 0; off + 20 <= size; off += 4) {
        uintptr_t pc = start + off;
        uint32_t adrp = 0;
        memcpy(&adrp, (const void *)pc, 4);
        uintptr_t page = HFAIGMM26ADRP(pc, adrp);
        if (!page) continue;
        unsigned adrpReg = adrp & 31u;
        for (size_t ahead = 4; ahead <= 16 && off + ahead + 4 <= size;
             ahead += 4) {
            uint32_t add = 0;
            memcpy(&add, (const void *)(pc + ahead), 4);
            unsigned rn = 0;
            uintptr_t imm = 0;
            if (!HFAIGMM26ADDImmediate(add, &rn, &imm) || rn != adrpReg)
                continue;
            uintptr_t candidate = page + imm;
            if (!HFAReadable(candidate, 32)) continue;
            uintptr_t invoke = 0;
            memcpy(&invoke, (const void *)(candidate + 16), sizeof(invoke));
#if __has_feature(ptrauth_calls)
            invoke = (uintptr_t)ptrauth_strip((void *)invoke,
                                              ptrauth_key_function_pointer);
#endif
            Dl_info info = {0};
            if (!invoke || !dladdr((void *)invoke, &info) ||
                !info.dli_fbase || !info.dli_fname ||
                strcmp(HFAIGMM26Base(info.dli_fname), imageName) != 0)
                continue;
            uintptr_t nestedRVA = invoke - (uintptr_t)info.dli_fbase;
            uintptr_t nestedStart = 0, nestedEnd = 0;
            if (!HFAIGMM26FunctionBoundsFromFile(imageName, nestedRVA,
                                                  &nestedStart, &nestedEnd))
                continue;
            NSMutableDictionary *result = [@{
                @"kind": @"buttonBlock",
                @"source": @"block-reference",
                @"handler": handler,
                @"nestedHandler": @{
                    @"image": [NSString stringWithUTF8String:imageName],
                    @"offset": [NSString stringWithFormat:@"0x%llX",
                               (unsigned long long)nestedStart],
                    @"functionEnd": [NSString stringWithFormat:@"0x%llX",
                                    (unsigned long long)nestedEnd]
                }
            } mutableCopy];
            NSDictionary *target =
                HFAIGMM26ComputedBranchTarget((uint32_t)imageIndex, imageName,
                                              nestedStart, nestedEnd);
            if (target) result[@"target"] = target;
            HFALog("[IGMM-IMPL-BLOCK] handler=%s+%s nested=%s+0x%llX target=%s+%s candidates=%u\n",
                   imageName, offsetString.UTF8String,
                   imageName, (unsigned long long)nestedStart,
                   [target[@"image"] UTF8String] ?: "?",
                   [target[@"offset"] UTF8String] ?: "?",
                   [target[@"candidates"] unsignedIntValue]);
            return result;
        }
    }
    return nil;
}

static NSDictionary *HFAIGMM26ResolveImplementation(const char *imageName,
                                                    const char *identifier,
                                                    NSDictionary *buttonHandler) {
    NSDictionary *byIdentifier =
        HFAIGMM26IdentifierImplementation(imageName, identifier);
    if (byIdentifier) return byIdentifier;
    if (buttonHandler) {
        NSDictionary *block =
            HFAIGMM26NestedBlockImplementation(imageName, buttonHandler);
        if (block) return block;
        return @{ @"kind": @"buttonBlock",
                  @"source": @"direct-block",
                  @"handler": buttonHandler };
    }
    return nil;
}

''' + anchor
s = replace_once(s, anchor, helper, 'insert iGMM implementation resolver')

old = r'''        NSDictionary *handler = HFAIGMMBlockMetadata(d[@"kButtonTapHandler"]);
        if (handler) runtime[@"handler"] = handler;

        NSMutableDictionary *feature ='''
new = r'''        NSDictionary *handler = HFAIGMMBlockMetadata(d[@"kButtonTapHandler"]);
        if (handler) runtime[@"handler"] = handler;
        NSDictionary *implementation =
            HFAIGMM26ResolveImplementation(menuImage.UTF8String,
                                            identifier.UTF8String, handler);
        if (implementation) {
            runtime[@"implementation"] = implementation;
            HFALog("[IGMM-IMPL-RESOLVE] identifier=%s type=%s status=resolved kind=%s\n",
                   identifier.UTF8String, type.UTF8String,
                   [implementation[@"kind"] UTF8String] ?: "?");
        } else {
            HFALog("[IGMM-IMPL-RESOLVE] identifier=%s type=%s status=unresolved\n",
                   identifier.UTF8String, type.UTF8String);
        }

        NSMutableDictionary *feature ='''
s = replace_once(s, old, new, 'attach implementation metadata')

patch_path.write_text(s)
legacy_path.write_text(l)
