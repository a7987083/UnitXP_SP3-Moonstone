from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.14: v1.9.13 could fall back to first RET when runtime __LINKEDIT was
# unreadable, truncating functions that contain cold/cleanup code after an
# early RET. Add a generic on-disk LC_FUNCTION_STARTS parser before RET fallback
# and annotate portable references with target segment/section metadata.

anchor = r'''static int HFAPortableFunctionBounds(const char *imageName,
                                     uintptr_t replacementAddress,
                                     uintptr_t replacementRVA,
                                     uintptr_t *startRVAOut,
                                     uintptr_t *endRVAOut,
                                     const char **sourceOut) {
'''
helper = r'''
static int HFAPortableFunctionBoundsFromFile(const char *imageName,
                                             uintptr_t replacementRVA,
                                             uintptr_t *startRVAOut,
                                             uintptr_t *endRVAOut,
                                             const char **sourceOut) {
    if (!imageName || !*imageName || !replacementRVA) return 0;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return 0;
    const char *path = _dyld_get_image_name((uint32_t)imageIndex);
    if (!path || !*path) return 0;
    NSString *nsPath = [NSString stringWithUTF8String:path];
    if (!nsPath) return 0;
    NSData *imageData = [NSData dataWithContentsOfFile:nsPath];
    if (!imageData || imageData.length < sizeof(struct mach_header_64)) return 0;

    const uint8_t *bytes = (const uint8_t *)imageData.bytes;
    size_t length = imageData.length;
    const struct mach_header_64 *h = (const struct mach_header_64 *)bytes;
    if (h->magic != MH_MAGIC_64) return 0;
    if ((size_t)sizeof(*h) + h->sizeofcmds > length) return 0;

    const uint8_t *cursor = bytes + sizeof(*h);
    uint64_t textVMAddr = 0, textEnd = 0;
    uint32_t functionDataOff = 0, functionDataSize = 0;
    for (uint32_t i = 0; i < h->ncmds; i++) {
        if ((size_t)(cursor - bytes) + sizeof(struct load_command) > length)
            return 0;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (!lc->cmdsize || (size_t)(cursor - bytes) + lc->cmdsize > length)
            return 0;
        if (lc->cmd == LC_SEGMENT_64 &&
            lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) {
                textVMAddr = seg->vmaddr;
                const struct section_64 *sec =
                    (const struct section_64 *)(seg + 1);
                if (lc->cmdsize >= sizeof(*seg) +
                    (size_t)seg->nsects * sizeof(struct section_64)) {
                    for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                        if (strncmp(sec->sectname, "__text", 16) == 0) {
                            textEnd = sec->addr + sec->size;
                            break;
                        }
                    }
                }
            }
        } else if (lc->cmd == LC_FUNCTION_STARTS &&
                   lc->cmdsize >= sizeof(struct linkedit_data_command)) {
            const struct linkedit_data_command *cmd =
                (const struct linkedit_data_command *)cursor;
            functionDataOff = cmd->dataoff;
            functionDataSize = cmd->datasize;
        }
        cursor += lc->cmdsize;
    }

    if (!textVMAddr && replacementRVA != 0) {
        // __TEXT vmaddr may legitimately be zero; absence is distinguished by
        // missing LC_FUNCTION_STARTS/textEnd below.
    }
    if (!functionDataOff || !functionDataSize || !textEnd ||
        (uint64_t)functionDataOff + functionDataSize > length)
        return 0;

    const uint8_t *data = bytes + functionDataOff;
    size_t off = 0;
    uint64_t cumulative = 0;
    uintptr_t previous = 0;
    while (off < functionDataSize) {
        uint64_t delta = 0;
        if (!HFAULEB128Read(data, functionDataSize, &off, &delta)) break;
        if (!delta) break;
        cumulative += delta;
        uintptr_t current = (uintptr_t)(textVMAddr + cumulative);
        if (current > replacementRVA) {
            if (previous && replacementRVA >= previous) {
                if (startRVAOut) *startRVAOut = previous;
                if (endRVAOut) *endRVAOut = current;
                if (sourceOut) *sourceOut = "LC_FUNCTION_STARTS_FILE";
                return 1;
            }
            break;
        }
        previous = current;
    }
    if (previous && replacementRVA >= previous && textEnd > previous) {
        if (startRVAOut) *startRVAOut = previous;
        if (endRVAOut) *endRVAOut = (uintptr_t)textEnd;
        if (sourceOut) *sourceOut = "LC_FUNCTION_STARTS_FILE_LAST";
        return 1;
    }
    return 0;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected portable function bounds anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    uintptr_t startAddress = replacementAddress;
    uintptr_t startRVA = replacementRVA;
    const size_t maxScan = 0x2000u;
'''
new = r'''    if (HFAPortableFunctionBoundsFromFile(imageName, replacementRVA,
                                               startRVAOut, endRVAOut,
                                               sourceOut))
        return 1;

    uintptr_t startAddress = replacementAddress;
    uintptr_t startRVA = replacementRVA;
    const size_t maxScan = 0x2000u;
'''
if s.count(old) != 1:
    raise SystemExit(f"expected RET fallback anchor once, found {s.count(old)}")
s = s.replace(old, new, 1)

anchor = r'''static NSDictionary *HFAPortableReference(const char *kind,
                                          uintptr_t instructionRVA,
                                          uintptr_t targetAddress,
                                          uintptr_t functionStartRVA,
                                          uintptr_t functionEndRVA) {
'''
section_helper = r'''
static void HFAPortableDescribeSection(const char *imageName,
                                       uintptr_t rva,
                                       char *segmentOut, size_t segmentSize,
                                       char *sectionOut, size_t sectionSize) {
    if (segmentOut && segmentSize) segmentOut[0] = 0;
    if (sectionOut && sectionSize) sectionOut[0] = 0;
    if (!imageName || !*imageName) return;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return;
    const struct mach_header *mh = _dyld_get_image_header((uint32_t)imageIndex);
    if (!mh || mh->magic != MH_MAGIC_64) return;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            if (rva >= (uintptr_t)seg->vmaddr &&
                rva < (uintptr_t)(seg->vmaddr + seg->vmsize)) {
                if (segmentOut && segmentSize)
                    snprintf(segmentOut, segmentSize, "%.*s", 16, seg->segname);
                const struct section_64 *sec =
                    (const struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                    if (rva >= (uintptr_t)sec->addr &&
                        rva < (uintptr_t)(sec->addr + sec->size)) {
                        if (sectionOut && sectionSize)
                            snprintf(sectionOut, sectionSize, "%.*s", 16,
                                     sec->sectname);
                        return;
                    }
                }
                return;
            }
        }
        if (!lc->cmdsize) break;
        cursor += lc->cmdsize;
    }
}

''' + anchor
if s.count(anchor) != 1:
    raise SystemExit(f"expected portable reference anchor once, found {s.count(anchor)}")
s = s.replace(anchor, section_helper, 1)

old = r'''    NSString *targetImage = image[0] ?
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
'''
new = r'''    NSString *targetImage = image[0] ?
        [NSString stringWithUTF8String:image] : @"?";
    if (!targetImage) targetImage = @"?";
    char segment[32] = {0}, section[32] = {0};
    if (image[0])
        HFAPortableDescribeSection(image, targetRVA, segment, sizeof(segment),
                                   section, sizeof(section));
    NSString *targetSegment = segment[0] ?
        [NSString stringWithUTF8String:segment] : @"?";
    NSString *targetSection = section[0] ?
        [NSString stringWithUTF8String:section] : @"?";
    BOOL internal = targetRVA >= functionStartRVA && targetRVA < functionEndRVA;
    return @{
        @"kind": [NSString stringWithUTF8String:kind],
        @"instructionOffset": HFANativeOffsetString(instructionRVA),
        @"target": targetImage,
        @"targetOffset": HFANativeOffsetString(targetRVA),
        @"targetSegment": targetSegment,
        @"targetSection": targetSection,
        @"internal": @(internal)
    };
'''
if s.count(old) != 1:
    raise SystemExit(f"expected portable reference dictionary once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''    HFALog("[PORTABLE-NATIVE-REF] identifier=%s kind=%s instructionRVA=%llX target=%s+%s internal=%u\n",
           identifier && *identifier ? identifier : "?",
           kind,
           (unsigned long long)instructionRVA,
           [[entry objectForKey:@"target"] UTF8String],
           [[entry objectForKey:@"targetOffset"] UTF8String],
           [[entry objectForKey:@"internal"] boolValue] ? 1u : 0u);
'''
new = r'''    HFALog("[PORTABLE-NATIVE-REF] identifier=%s kind=%s instructionRVA=%llX target=%s+%s segment=%s section=%s internal=%u\n",
           identifier && *identifier ? identifier : "?",
           kind,
           (unsigned long long)instructionRVA,
           [[entry objectForKey:@"target"] UTF8String],
           [[entry objectForKey:@"targetOffset"] UTF8String],
           [[entry objectForKey:@"targetSegment"] UTF8String],
           [[entry objectForKey:@"targetSection"] UTF8String],
           [[entry objectForKey:@"internal"] boolValue] ? 1u : 0u);
'''
if s.count(old) != 1:
    raise SystemExit(f"expected portable ref log once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.13 PortableNativeHookCapture] loaded'
new_marker = '[HFALearn v1.9.14 FunctionStartsFileFallback] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.13 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.13 PortableNativeHookCapture] loaded'
new_marker = '[HFALearn UI v1.9.14 FunctionStartsFileFallback] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.13 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
