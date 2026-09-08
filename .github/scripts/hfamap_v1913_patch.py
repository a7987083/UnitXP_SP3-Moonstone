from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.13: capture the replacement function body and its direct ARM64
# PC-relative dependencies. Analysis/export only: no relocation rewriting and
# no changes to the stable AP descriptor path.
anchor = r'''static unsigned HFAAppendNativeHookPackageFeatures(NSMutableArray *features,
                                                    NSMutableDictionary *targets) {
'''
helper = r'''
static int HFAULEB128Read(const uint8_t *data, size_t size, size_t *offset,
                          uint64_t *valueOut) {
    if (!data || !offset || !valueOut || *offset >= size) return 0;
    uint64_t value = 0;
    unsigned shift = 0;
    while (*offset < size && shift < 64) {
        uint8_t byte = data[(*offset)++];
        value |= ((uint64_t)(byte & 0x7Fu)) << shift;
        if (!(byte & 0x80u)) {
            *valueOut = value;
            return 1;
        }
        shift += 7;
    }
    return 0;
}

static int HFAPortableFunctionBounds(const char *imageName,
                                     uintptr_t replacementAddress,
                                     uintptr_t replacementRVA,
                                     uintptr_t *startRVAOut,
                                     uintptr_t *endRVAOut,
                                     const char **sourceOut) {
    if (!imageName || !*imageName || !replacementAddress || !replacementRVA)
        return 0;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return 0;
    const struct mach_header *mh = _dyld_get_image_header((uint32_t)imageIndex);
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    if (!mh || mh->magic != MH_MAGIC_64) return 0;

    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    uint64_t textVMAddr = 0, textEnd = 0;
    uint64_t linkeditVMAddr = 0, linkeditFileOff = 0;
    uint32_t functionDataOff = 0, functionDataSize = 0;

    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) {
                textVMAddr = seg->vmaddr;
                const struct section_64 *sec =
                    (const struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                    if (strncmp(sec->sectname, "__text", 16) == 0) {
                        textEnd = sec->addr + sec->size;
                        break;
                    }
                }
            } else if (strncmp(seg->segname, "__LINKEDIT", 16) == 0) {
                linkeditVMAddr = seg->vmaddr;
                linkeditFileOff = seg->fileoff;
            }
        } else if (lc->cmd == LC_FUNCTION_STARTS) {
            const struct linkedit_data_command *cmd =
                (const struct linkedit_data_command *)cursor;
            functionDataOff = cmd->dataoff;
            functionDataSize = cmd->datasize;
        }
        if (!lc->cmdsize) break;
        cursor += lc->cmdsize;
    }

    if (textVMAddr && linkeditVMAddr && functionDataOff && functionDataSize) {
        uintptr_t encodedAddress =
            (uintptr_t)((intptr_t)slide + (intptr_t)linkeditVMAddr +
                        (intptr_t)functionDataOff - (intptr_t)linkeditFileOff);
        if (HFAReadable(encodedAddress, functionDataSize)) {
            const uint8_t *data = (const uint8_t *)encodedAddress;
            size_t off = 0;
            uint64_t cumulative = 0;
            uintptr_t previous = 0;
            while (off < functionDataSize) {
                uint64_t delta = 0;
                if (!HFAULEB128Read(data, functionDataSize, &off, &delta))
                    break;
                if (!delta) break;
                cumulative += delta;
                uintptr_t current = (uintptr_t)(textVMAddr + cumulative);
                if (current > replacementRVA) {
                    if (previous && replacementRVA >= previous) {
                        if (startRVAOut) *startRVAOut = previous;
                        if (endRVAOut) *endRVAOut = current;
                        if (sourceOut) *sourceOut = "LC_FUNCTION_STARTS";
                        return 1;
                    }
                    break;
                }
                previous = current;
            }
            if (previous && replacementRVA >= previous && textEnd > previous) {
                if (startRVAOut) *startRVAOut = previous;
                if (endRVAOut) *endRVAOut = (uintptr_t)textEnd;
                if (sourceOut) *sourceOut = "LC_FUNCTION_STARTS_LAST";
                return 1;
            }
        }
    }

    uintptr_t startAddress = replacementAddress;
    uintptr_t startRVA = replacementRVA;
    const size_t maxScan = 0x2000u;
    for (size_t off = 0; off + 4 <= maxScan; off += 4) {
        uintptr_t pc = startAddress + off;
        if (!HFAReadable(pc, 4)) break;
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);
        if (word == 0xD65F03C0u) {
            if (startRVAOut) *startRVAOut = startRVA;
            if (endRVAOut) *endRVAOut = startRVA + off + 4;
            if (sourceOut) *sourceOut = "replacement-entry+RET";
            return 1;
        }
    }
    return 0;
}

static NSString *HFAPortableCodeHex(uintptr_t address, size_t size) {
    if (!address || !size || size > 0x4000u || !HFAReadable(address, size))
        return nil;
    const uint8_t *bytes = (const uint8_t *)address;
    NSMutableString *hex = [NSMutableString stringWithCapacity:size * 2];
    for (size_t i = 0; i < size; i++)
        [hex appendFormat:@"%02X", bytes[i]];
    return hex;
}

static NSDictionary *HFAPortableReference(const char *kind,
                                          uintptr_t instructionRVA,
                                          uintptr_t targetAddress,
                                          uintptr_t functionStartRVA,
                                          uintptr_t functionEndRVA) {
    if (!kind || !*kind || !targetAddress) return nil;
    char image[256] = {0};
    uintptr_t targetRVA = 0;
    HFADescribePointer(targetAddress, image, sizeof(image), &targetRVA);
    NSString *targetImage = image[0] ?
        [NSString stringWithUTF8String:image] : @"?";
    if (!targetImage) targetImage = @"?";
    BOOL internal = targetRVA >= functionStartRVA && targetRVA < functionEndRVA;
    return @{
        @"kind": [NSString stringWithUTF8String:kind],
        @"instructionOffset": HFANativeOffsetString(instructionRVA),
        @"target": targetImage,
        @"targetOffset": HFANativeOffsetString(targetRVA),
        @"internal": @(internal)
    };
}

static void HFAPortableAppendReference(NSMutableArray *refs,
                                       const char *identifier,
                                       const char *kind,
                                       uintptr_t instructionRVA,
                                       uintptr_t targetAddress,
                                       uintptr_t functionStartRVA,
                                       uintptr_t functionEndRVA) {
    if (!refs || refs.count >= 128 || !targetAddress) return;
    NSDictionary *entry = HFAPortableReference(kind, instructionRVA,
                                               targetAddress,
                                               functionStartRVA,
                                               functionEndRVA);
    if (!entry) return;
    [refs addObject:entry];
    HFALog("[PORTABLE-NATIVE-REF] identifier=%s kind=%s instructionRVA=%llX target=%s+%s internal=%u\n",
           identifier && *identifier ? identifier : "?",
           kind,
           (unsigned long long)instructionRVA,
           [[entry objectForKey:@"target"] UTF8String],
           [[entry objectForKey:@"targetOffset"] UTF8String],
           [[entry objectForKey:@"internal"] boolValue] ? 1u : 0u);
}

static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
    if (!r || !r->identifier[0] || !r->replacementImage[0] ||
        !r->replacement || !r->replacementRVA)
        return nil;

    uintptr_t startRVA = 0, endRVA = 0;
    const char *boundarySource = NULL;
    if (!HFAPortableFunctionBounds(r->replacementImage, r->replacement,
                                   r->replacementRVA, &startRVA, &endRVA,
                                   &boundarySource) ||
        !startRVA || endRVA <= startRVA) {
        HFALog("[PORTABLE-NATIVE-FUNC] identifier=%s image=%s status=NO_BOUNDARY replacementRVA=%llX\n",
               r->identifier, r->replacementImage,
               (unsigned long long)r->replacementRVA);
        return @{
            @"status": @"boundaryUnavailable",
            @"portablePayload": @NO
        };
    }

    int imageIndex = HFAImageIndexForName(r->replacementImage);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t startAddress = (uintptr_t)((intptr_t)slide + (intptr_t)startRVA);
    size_t size = (size_t)(endRVA - startRVA);
    if (!size || size > 0x4000u || !HFAReadable(startAddress, size)) {
        HFALog("[PORTABLE-NATIVE-FUNC] identifier=%s image=%s status=SIZE_OR_READ_FAIL startRVA=%llX endRVA=%llX size=%zu\n",
               r->identifier, r->replacementImage,
               (unsigned long long)startRVA,
               (unsigned long long)endRVA, size);
        return @{
            @"status": @"bodyUnavailable",
            @"portablePayload": @NO,
            @"functionStart": HFANativeOffsetString(startRVA),
            @"functionEnd": HFANativeOffsetString(endRVA),
            @"functionSize": @(size)
        };
    }

    HFALog("[PORTABLE-NATIVE-FUNC] identifier=%s image=%s status=CAPTURED startRVA=%llX endRVA=%llX size=%zu source=%s\n",
           r->identifier, r->replacementImage,
           (unsigned long long)startRVA,
           (unsigned long long)endRVA, size,
           boundarySource ? boundarySource : "?");

    NSMutableArray *refs = [NSMutableArray array];
    for (size_t off = 0; off + 4 <= size; off += 4) {
        uintptr_t pc = startAddress + off;
        uintptr_t instructionRVA = startRVA + off;
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);

        uint32_t branchClass = word & 0xFC000000u;
        if (branchClass == 0x94000000u || branchClass == 0x14000000u) {
            int64_t displacement =
                HFAStaticSignExtend(((uint64_t)(word & 0x03FFFFFFu)) << 2, 28);
            uintptr_t target = (uintptr_t)((intptr_t)pc + displacement);
            HFAPortableAppendReference(refs, r->identifier,
                                       branchClass == 0x94000000u ? "BL" : "B",
                                       instructionRVA, target,
                                       startRVA, endRVA);
            continue;
        }

        if ((word & 0x9F000000u) == 0x10000000u) {
            unsigned rd = word & 31u;
            uintptr_t target = HFAStaticADRTarget(pc, word, rd);
            HFAPortableAppendReference(refs, r->identifier, "ADR",
                                       instructionRVA, target,
                                       startRVA, endRVA);
            continue;
        }

        if ((word & 0x9F000000u) == 0x90000000u) {
            unsigned rd = word & 31u;
            uintptr_t page = HFAStaticADRPPage(pc, word, rd);
            if (!page) continue;
            int paired = 0;
            for (size_t ahead = 4; ahead <= 16 && off + ahead + 4 <= size;
                 ahead += 4) {
                uint32_t next = 0;
                memcpy(&next, (const void *)(pc + ahead), 4);
                unsigned rn = (next >> 5) & 31u;
                if (rn != rd) continue;

                if ((next & 0xFF000000u) == 0x91000000u) {
                    uintptr_t imm = (uintptr_t)((next >> 10) & 0xFFFu);
                    if ((next >> 22) & 1u) imm <<= 12;
                    HFAPortableAppendReference(refs, r->identifier,
                                               "ADRP+ADD",
                                               instructionRVA,
                                               page + imm,
                                               startRVA, endRVA);
                    paired = 1;
                    break;
                }

                if ((next & 0x3B000000u) == 0x39000000u) {
                    unsigned scale = (next >> 30) & 3u;
                    uintptr_t imm =
                        (uintptr_t)((next >> 10) & 0xFFFu) << scale;
                    HFAPortableAppendReference(refs, r->identifier,
                                               "ADRP+LDST",
                                               instructionRVA,
                                               page + imm,
                                               startRVA, endRVA);
                    paired = 1;
                    break;
                }
            }
            if (!paired)
                HFAPortableAppendReference(refs, r->identifier, "ADRP",
                                           instructionRVA, page,
                                           startRVA, endRVA);
            continue;
        }

        if ((word & 0x3B000000u) == 0x18000000u) {
            int64_t displacement = HFAStaticSignExtend(
                ((uint64_t)((word >> 5) & 0x7FFFFu)) << 2, 21);
            uintptr_t target = (uintptr_t)((intptr_t)pc + displacement);
            HFAPortableAppendReference(refs, r->identifier, "LDR_LITERAL",
                                       instructionRVA, target,
                                       startRVA, endRVA);
        }
    }

    NSString *codeHex = HFAPortableCodeHex(startAddress, size);
    unsigned externalRefs = 0;
    for (NSDictionary *entry in refs) {
        if (![[entry objectForKey:@"internal"] boolValue]) externalRefs++;
    }

    HFALog("[PORTABLE-NATIVE-CAPTURE] identifier=%s image=%s codeBytes=%zu refs=%u externalRefs=%u portablePayload=0 reason=relocations-required\n",
           r->identifier, r->replacementImage, size,
           (unsigned)refs.count, externalRefs);

    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
        @"status": @"captured",
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @(size),
        @"boundarySource": [NSString stringWithUTF8String:
            boundarySource ? boundarySource : "?"],
        @"references": refs,
        @"referenceCount": @((unsigned)refs.count),
        @"externalReferenceCount": @(externalRefs),
        @"portablePayload": @NO,
        @"reason": @"relocations-required"
    }];
    if (codeHex) capture[@"codeHex"] = codeHex;
    return capture;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected native package feature anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''        NSDictionary *hook = @{
            @"target": @{ @"target": targetID,
                           @"offset": HFANativeOffsetString(r->targetRVA) },
            @"replacement": @{ @"target": replacementID,
                                @"offset": HFANativeOffsetString(r->replacementRVA) },
            @"originalSlot": @{ @"target": slotID,
                                 @"offset": HFANativeOffsetString(r->slotRVA) },
            @"original": @{ @"target": originalID,
                             @"offset": HFANativeOffsetString(r->originalRVA) }
        };

        [features addObject:@{
'''
new = r'''        NSMutableDictionary *hook = [NSMutableDictionary dictionaryWithDictionary:@{
            @"target": @{ @"target": targetID,
                           @"offset": HFANativeOffsetString(r->targetRVA) },
            @"replacement": @{ @"target": replacementID,
                                @"offset": HFANativeOffsetString(r->replacementRVA) },
            @"originalSlot": @{ @"target": slotID,
                                 @"offset": HFANativeOffsetString(r->slotRVA) },
            @"original": @{ @"target": originalID,
                             @"offset": HFANativeOffsetString(r->originalRVA) }
        }];
        NSDictionary *capture = HFACapturePortableNativeHook(r);
        if (capture) {
            hook[@"capture"] = capture;
            NSString *captureStart = [capture objectForKey:@"functionStart"];
            NSString *captureEnd = [capture objectForKey:@"functionEnd"];
            HFALog("[PACKAGE-NATIVEHOOK-CAPTURE] identifier=%s status=%s functionStart=%s functionEnd=%s references=%u portablePayload=%u\n",
                   r->identifier,
                   [[capture objectForKey:@"status"] UTF8String],
                   captureStart.length ? captureStart.UTF8String : "?",
                   captureEnd.length ? captureEnd.UTF8String : "?",
                   [[capture objectForKey:@"referenceCount"] unsignedIntValue],
                   [[capture objectForKey:@"portablePayload"] boolValue] ? 1u : 0u);
        }

        [features addObject:@{
'''
if s.count(old) != 1:
    raise SystemExit(f"expected native hook dictionary once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.12 NativeHookExportTimingFix] loaded'
new_marker = '[HFALearn v1.9.13 PortableNativeHookCapture] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.12 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.12 NativeHookExportTimingFix] loaded'
new_marker = '[HFALearn UI v1.9.13 PortableNativeHookCapture] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.12 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
