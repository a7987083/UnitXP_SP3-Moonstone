from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.10: resolve a recovered native-hook target offset to the loaded Mach-O
# image whose executable code range uniquely contains that RVA. This keeps the
# customSwitch route generic: no feature identifier, image name, selector, or
# sample RVA is hardcoded.

old = r'''    char targetClass[128];
    char targetPlain[192];
    char apiImage[256];
'''
new = r'''    char targetClass[128];
    char targetPlain[192];
    char targetImage[256];
    uintptr_t targetRVA;
    uintptr_t targetAddress;
    unsigned targetCandidates;
    char apiImage[256];
'''
if s.count(old) != 1:
    raise SystemExit(f"expected native registration target fields once, found {s.count(old)}")
s = s.replace(old, new, 1)

anchor = r'''static void HFAAssociateNativeHookWithCustomSwitch(const char *identifier) {
'''
helper = r'''
static int HFAReadable(uintptr_t address, size_t length);

static int HFANativeTargetRangeForImage(uint32_t imageIndex, uintptr_t rva,
                                        uintptr_t *addressOut,
                                        int instructionOnly) {
    const struct mach_header *mh = _dyld_get_image_header(imageIndex);
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);

    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *sec =
                (const struct section_64 *)(seg + 1);

            if (instructionOnly) {
                for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                    uint32_t attrs = sec->flags &
                        (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS);
                    if (!attrs) continue;
                    if (rva < (uintptr_t)sec->addr ||
                        rva >= (uintptr_t)(sec->addr + sec->size))
                        continue;
                    uintptr_t address = (uintptr_t)((intptr_t)slide +
                                                    (intptr_t)rva);
                    if (!HFAReadable(address, 4)) continue;
                    if (addressOut) *addressOut = address;
                    return 1;
                }
            } else if ((seg->initprot & VM_PROT_EXECUTE) &&
                       rva >= (uintptr_t)seg->vmaddr &&
                       rva < (uintptr_t)(seg->vmaddr + seg->vmsize)) {
                uintptr_t address = (uintptr_t)((intptr_t)slide +
                                                (intptr_t)rva);
                if (!HFAReadable(address, 4)) continue;
                if (addressOut) *addressOut = address;
                return 1;
            }
        }
        if (!lc->cmdsize) break;
        cursor += lc->cmdsize;
    }
    return 0;
}

static int HFAParseNativeTargetRVA(const char *text, uintptr_t *rvaOut) {
    if (!text || !*text || !rvaOut) return 0;
    const char *p = text;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
    if (!*p) return 0;
    for (const char *q = p; *q; q++)
        if (!strchr("0123456789abcdefABCDEF", *q)) return 0;
    unsigned long long value = strtoull(text, NULL, 16);
    if (!value || value > UINTPTR_MAX) return 0;
    *rvaOut = (uintptr_t)value;
    return 1;
}

static void HFAResolveNativeTargetRegistration(HFANativeHookRegistration *r,
                                               const char *identifier) {
    if (!r || r->targetImage[0] || !r->targetPlain[0]) return;

    uintptr_t targetRVA = 0;
    if (!HFAParseNativeTargetRVA(r->targetPlain, &targetRVA)) {
        HFALog("[CUSTOM-NATIVE-TARGET-RESOLVE] identifier=%s target=%s status=NON_RVA\n",
               identifier && *identifier ? identifier : "?",
               r->targetPlain);
        return;
    }

    unsigned exactCount = 0, fallbackCount = 0;
    int exactIndex = -1, fallbackIndex = -1;
    uintptr_t exactAddress = 0, fallbackAddress = 0;
    uint32_t imageCount = _dyld_image_count();

    for (uint32_t i = 0; i < imageCount; i++) {
        uintptr_t address = 0;
        if (HFANativeTargetRangeForImage(i, targetRVA, &address, 1)) {
            exactCount++;
            exactIndex = (int)i;
            exactAddress = address;
            uint32_t words[4] = {0};
            if (HFAReadable(address, sizeof(words)))
                memcpy(words, (const void *)address, sizeof(words));
            HFALog("[CUSTOM-NATIVE-TARGET-CANDIDATE] identifier=%s target=%s mode=instruction image=%s rva=%llX address=%p words=%08X/%08X/%08X/%08X\n",
                   identifier && *identifier ? identifier : "?",
                   r->targetPlain,
                   HFABase(_dyld_get_image_name(i)),
                   (unsigned long long)targetRVA, (void *)address,
                   words[0], words[1], words[2], words[3]);
        }
    }

    if (!exactCount) {
        for (uint32_t i = 0; i < imageCount; i++) {
            uintptr_t address = 0;
            if (!HFANativeTargetRangeForImage(i, targetRVA, &address, 0))
                continue;
            fallbackCount++;
            fallbackIndex = (int)i;
            fallbackAddress = address;
            HFALog("[CUSTOM-NATIVE-TARGET-CANDIDATE] identifier=%s target=%s mode=exec-segment image=%s rva=%llX address=%p\n",
                   identifier && *identifier ? identifier : "?",
                   r->targetPlain,
                   HFABase(_dyld_get_image_name(i)),
                   (unsigned long long)targetRVA, (void *)address);
        }
    }

    unsigned chosenCount = exactCount ? exactCount : fallbackCount;
    int chosenIndex = exactCount ? exactIndex : fallbackIndex;
    uintptr_t chosenAddress = exactCount ? exactAddress : fallbackAddress;
    r->targetCandidates = chosenCount;
    r->targetRVA = targetRVA;

    if (chosenCount == 1 && chosenIndex >= 0) {
        const char *image = HFABase(_dyld_get_image_name((uint32_t)chosenIndex));
        snprintf(r->targetImage, sizeof(r->targetImage), "%s", image);
        r->targetAddress = chosenAddress;
        HFALog("[CUSTOM-NATIVE-TARGET-RESOLVE] identifier=%s target=%s status=UNIQUE image=%s rva=%llX address=%p mode=%s\n",
               identifier && *identifier ? identifier : "?",
               r->targetPlain, image, (unsigned long long)targetRVA,
               (void *)chosenAddress,
               exactCount ? "instruction" : "exec-segment");
    } else {
        HFALog("[CUSTOM-NATIVE-TARGET-RESOLVE] identifier=%s target=%s status=%s candidates=%u mode=%s\n",
               identifier && *identifier ? identifier : "?",
               r->targetPlain,
               chosenCount ? "AMBIGUOUS" : "NONE",
               chosenCount,
               exactCount ? "instruction" : "exec-segment");
    }
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected native association anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    snprintf(candidate->identifier, sizeof(candidate->identifier), "%s", identifier);
    HFAFeatureDefinition *definition = HFAFeatureDefinitionForIdentifier(identifier);
    HFALog("[CUSTOM-NATIVE-HOOK-ASSOC] identifier=%s label=%s candidates=1 status=ASSOCIATED sequence=%u target=%s replacementImage=%s replacementRVA=%llX originalSlotImage=%s originalSlotRVA=%llX originalImage=%s originalRVA=%llX\n",
'''
new = r'''    snprintf(candidate->identifier, sizeof(candidate->identifier), "%s", identifier);
    HFAResolveNativeTargetRegistration(candidate, identifier);
    HFAFeatureDefinition *definition = HFAFeatureDefinitionForIdentifier(identifier);
    HFALog("[CUSTOM-NATIVE-HOOK-ASSOC] identifier=%s label=%s candidates=1 status=ASSOCIATED sequence=%u target=%s targetImage=%s targetRVA=%llX targetCandidates=%u replacementImage=%s replacementRVA=%llX originalSlotImage=%s originalSlotRVA=%llX originalImage=%s originalRVA=%llX\n",
'''
if s.count(old) != 1:
    raise SystemExit(f"expected native association log anchor once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''           candidate->sequence,
           candidate->targetPlain[0] ? candidate->targetPlain : "?",
           candidate->replacementImage[0] ? candidate->replacementImage : "?",
'''
new = r'''           candidate->sequence,
           candidate->targetPlain[0] ? candidate->targetPlain : "?",
           candidate->targetImage[0] ? candidate->targetImage : "?",
           (unsigned long long)candidate->targetRVA,
           candidate->targetCandidates,
           candidate->replacementImage[0] ? candidate->replacementImage : "?",
'''
if s.count(old) != 1:
    raise SystemExit(f"expected native association args once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''    HFALog("[CUSTOM-NATIVE-HOOK-MAPPING] title=\"%s\" identifier=%s type=customSwitch/nativeHook target=%s replacement=%s+0x%llX originalSlot=%s+0x%llX original=%s+0x%llX\n",
           definition && definition->label[0] ? definition->label : "?",
           identifier,
           candidate->targetPlain[0] ? candidate->targetPlain : "?",
           candidate->replacementImage[0] ? candidate->replacementImage : "?",
'''
new = r'''    HFALog("[CUSTOM-NATIVE-HOOK-MAPPING] title=\"%s\" identifier=%s type=customSwitch/nativeHook target=%s targetImage=%s targetRVA=0x%llX replacement=%s+0x%llX originalSlot=%s+0x%llX original=%s+0x%llX\n",
           definition && definition->label[0] ? definition->label : "?",
           identifier,
           candidate->targetPlain[0] ? candidate->targetPlain : "?",
           candidate->targetImage[0] ? candidate->targetImage : "?",
           (unsigned long long)candidate->targetRVA,
           candidate->replacementImage[0] ? candidate->replacementImage : "?",
'''
if s.count(old) != 1:
    raise SystemExit(f"expected native mapping log once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.9 FeatureBootstrapRootProbe] loaded'
new_marker = '[HFALearn v1.9.10 NativeTargetResolveProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.9 patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.9 FeatureBootstrapRootProbe] loaded'
new_marker = '[HFALearn UI v1.9.10 NativeTargetResolveProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.9 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
