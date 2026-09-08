from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.9: recover the common feature-bootstrap function that owns the native
# hook registration and correlate already-discovered ordinary descriptors to
# the same function. This operates on Mach-O function-start metadata and the
# actual runtime secret pointers, so it does not hardcode obfuscated names,
# feature identifiers, or sample RVAs.
anchor = r'''static uintptr_t HFACustomBlockInvoke(void *block, uintptr_t a1, uintptr_t a2,
'''
insert = r'''
static uintptr_t gFeatureBootstrapLogged[64];
static unsigned gFeatureBootstrapLoggedCount;

static uintptr_t HFASecretPointerForWrapper(id wrapper) {
    if (!wrapper) return 0;
    SEL secretSel = sel_registerName("secret");
    Method getter = class_getInstanceMethod(object_getClass(wrapper), secretSel);
    if (!getter) return 0;
    return (uintptr_t)((void *(*)(id,SEL))objc_msgSend)(wrapper, secretSel);
}

static int HFAFunctionStartsRange(const struct mach_header *mh,
                                  intptr_t slide,
                                  uintptr_t address,
                                  uintptr_t textEnd,
                                  uintptr_t *startOut,
                                  uintptr_t *endOut) {
    if (!mh || mh->magic != MH_MAGIC_64 || !address) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    const struct linkedit_data_command *starts = NULL;
    uint64_t textVM = 0, linkVM = 0, linkFile = 0;
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_FUNCTION_STARTS)
            starts = (const struct linkedit_data_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) textVM = seg->vmaddr;
            if (strncmp(seg->segname, "__LINKEDIT", 16) == 0) {
                linkVM = seg->vmaddr;
                linkFile = seg->fileoff;
            }
        }
        if (!lc->cmdsize) break;
        cursor += lc->cmdsize;
    }
    if (!starts || !starts->datasize || !linkVM) return 0;

    uintptr_t linkBase = (uintptr_t)((intptr_t)slide +
                                     (intptr_t)linkVM -
                                     (intptr_t)linkFile);
    const uint8_t *p = (const uint8_t *)(linkBase + starts->dataoff);
    const uint8_t *end = p + starts->datasize;
    uintptr_t imageTextBase = (uintptr_t)((intptr_t)slide + (intptr_t)textVM);
    uintptr_t previous = 0;
    uint64_t cumulative = 0;

    while (p < end) {
        uint64_t delta = 0;
        unsigned shift = 0;
        while (p < end && shift < 64) {
            uint8_t byte = *p++;
            delta |= (uint64_t)(byte & 0x7fu) << shift;
            if (!(byte & 0x80u)) break;
            shift += 7;
        }
        if (!delta) continue;
        cumulative += delta;
        uintptr_t current = imageTextBase + (uintptr_t)cumulative;
        if (current > address) {
            if (!previous) return 0;
            if (startOut) *startOut = previous;
            if (endOut) *endOut = current;
            return 1;
        }
        previous = current;
    }
    if (previous && address >= previous && address < textEnd) {
        if (startOut) *startOut = previous;
        if (endOut) *endOut = textEnd;
        return 1;
    }
    return 0;
}

static uintptr_t HFAFindADRReference(uintptr_t start, uintptr_t end,
                                     uintptr_t target) {
    if (!start || end <= start || !target) return 0;
    for (uintptr_t pc = start; pc + 4 <= end; pc += 4) {
        if (!HFAReadable(pc, 4)) break;
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);
        if ((word & 0x9F000000u) != 0x10000000u) continue;
        unsigned reg = word & 31u;
        if (HFAStaticADRTarget(pc, word, reg) == target) return pc;
    }
    return 0;
}

static uintptr_t HFAStaticADRPAny(uintptr_t pc, uint32_t word,
                                  unsigned *regOut) {
    if ((word & 0x9F000000u) != 0x90000000u) return 0;
    unsigned reg = word & 31u;
    uintptr_t page = HFAStaticADRPPage(pc, word, reg);
    if (page && regOut) *regOut = reg;
    return page;
}

static int HFAStaticADDImmSame(uint32_t word, unsigned reg,
                               uintptr_t *offsetOut) {
    if ((word & 0xFF000000u) != 0x91000000u ||
        (word & 31u) != reg || ((word >> 5) & 31u) != reg)
        return 0;
    uintptr_t imm = (uintptr_t)((word >> 10) & 0xFFFu);
    if ((word >> 22) & 1u) imm <<= 12;
    if (offsetOut) *offsetOut = imm;
    return 1;
}

static int HFAFeatureRootAlreadyLogged(uintptr_t root) {
    for (unsigned i = 0; i < gFeatureBootstrapLoggedCount; i++)
        if (gFeatureBootstrapLogged[i] == root) return 1;
    if (gFeatureBootstrapLoggedCount < 64)
        gFeatureBootstrapLogged[gFeatureBootstrapLoggedCount++] = root;
    return 0;
}

static unsigned HFAProbeRootBlocks(const char *identifier,
                                   uintptr_t imageBase,
                                   uintptr_t textStart,
                                   uintptr_t textEnd,
                                   uintptr_t rootStart,
                                   uintptr_t rootEnd,
                                   unsigned *nextFunctionBlocksOut) {
    uintptr_t seen[64] = {0};
    unsigned seenCount = 0, blocks = 0, nextFunctionBlocks = 0;
    for (uintptr_t pc = rootStart; pc + 8 <= rootEnd; pc += 4) {
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);
        unsigned reg = 0;
        uintptr_t page = HFAStaticADRPAny(pc, word, &reg);
        if (!page) continue;
        uintptr_t candidate = 0, addPC = 0;
        for (uintptr_t q = pc + 4; q < pc + 0x10u && q + 4 <= rootEnd; q += 4) {
            uint32_t addWord = 0;
            memcpy(&addWord, (const void *)q, 4);
            uintptr_t add = 0;
            if (!HFAStaticADDImmSame(addWord, reg, &add)) continue;
            candidate = page + add;
            addPC = q;
            break;
        }
        if (!candidate || !HFAReadable(candidate, sizeof(HFABlockLiteral))) continue;
        int duplicate = 0;
        for (unsigned i = 0; i < seenCount; i++)
            if (seen[i] == candidate) { duplicate = 1; break; }
        if (duplicate) continue;

        HFABlockLiteral literal;
        memcpy(&literal, (const void *)candidate, sizeof(literal));
        if (!(literal.flags & (1u << 28))) continue;
        uintptr_t invoke = HFAStripCodePointer((uintptr_t)literal.invoke);
        if (invoke < textStart || invoke >= textEnd) continue;
        if (seenCount < 64) seen[seenCount++] = candidate;
        blocks++;
        int nextFunction = invoke == rootEnd;
        if (nextFunction) nextFunctionBlocks++;
        HFALog("[FEATURE-ROOT-BLOCK] identifier=%s rootRVA=%llX refRVA=%llX addRVA=%llX blockRVA=%llX invokeRVA=%llX role=%s\n",
               identifier && *identifier ? identifier : "?",
               (unsigned long long)(rootStart - imageBase),
               (unsigned long long)(pc - imageBase),
               (unsigned long long)(addPC - imageBase),
               (unsigned long long)(candidate - imageBase),
               (unsigned long long)(invoke - imageBase),
               nextFunction ? "NEXT_FUNCTION_CALLBACK" : "BLOCK_CALLBACK");
    }
    if (nextFunctionBlocksOut) *nextFunctionBlocksOut = nextFunctionBlocks;
    return blocks;
}

static void HFAProbeFeatureBootstrapRoot(const HFANativeHookRegistration *r,
                                         const char *identifier) {
    if (!r || !identifier || !*identifier || !r->apiImage[0]) return;
    const struct mach_header *mh = NULL;
    intptr_t slide = 0;
    uintptr_t imageBase = 0, textStart = 0, textEnd = 0;
    if (!HFAStaticImageForName(r->apiImage, &mh, &slide, &imageBase) ||
        !HFAStaticFindTextSection(mh, slide, &textStart, &textEnd)) {
        HFALog("[FEATURE-BOOTSTRAP-ROOT] identifier=%s image=%s status=NO_TEXT\n",
               identifier, r->apiImage);
        return;
    }

    uintptr_t nativeSecret = HFASecretPointerForWrapper(r->targetWrapper);
    uintptr_t anchorPC = nativeSecret ?
        HFAFindADRReference(textStart, textEnd, nativeSecret) : 0;
    if (!anchorPC && r->apiRVA) anchorPC = imageBase + r->apiRVA;
    if (!anchorPC) {
        HFALog("[FEATURE-BOOTSTRAP-ROOT] identifier=%s image=%s status=NO_ANCHOR\n",
               identifier, r->apiImage);
        return;
    }

    uintptr_t rootStart = 0, rootEnd = 0;
    if (!HFAFunctionStartsRange(mh, slide, anchorPC, textEnd,
                                &rootStart, &rootEnd) ||
        rootEnd <= rootStart) {
        HFALog("[FEATURE-BOOTSTRAP-ROOT] identifier=%s image=%s anchorRVA=%llX status=NO_FUNCTION_RANGE\n",
               identifier, r->apiImage,
               (unsigned long long)(anchorPC - imageBase));
        return;
    }
    if (HFAFeatureRootAlreadyLogged(rootStart)) return;

    uintptr_t nativeRef = nativeSecret ?
        HFAFindADRReference(rootStart, rootEnd, nativeSecret) : 0;
    HFALog("[FEATURE-ROOT-NATIVE] identifier=%s rootRVA=%llX callsiteRVA=%llX secretRVA=%llX secretRefRVA=%llX target=%s replacementRVA=%llX slotRVA=%llX originalRVA=%llX\n",
           identifier,
           (unsigned long long)(rootStart - imageBase),
           (unsigned long long)r->apiRVA,
           (unsigned long long)(nativeSecret ? nativeSecret - imageBase : 0),
           (unsigned long long)(nativeRef ? nativeRef - imageBase : 0),
           r->targetPlain[0] ? r->targetPlain : "?",
           (unsigned long long)r->replacementRVA,
           (unsigned long long)r->slotRVA,
           (unsigned long long)r->originalRVA);

    unsigned descriptors = 0;
    for (unsigned i = 0; i < gDescriptorCount; i++) {
        HFADescriptor *d = &gDescriptors[i];
        uintptr_t offsetSecret = HFASecretPointerForWrapper(d->offsetWrapper);
        uintptr_t patchSecret = HFASecretPointerForWrapper(d->patchWrapper);
        uintptr_t offsetRef = offsetSecret ?
            HFAFindADRReference(rootStart, rootEnd, offsetSecret) : 0;
        uintptr_t patchRef = patchSecret ?
            HFAFindADRReference(rootStart, rootEnd, patchSecret) : 0;
        if (!offsetRef && !patchRef) continue;

        char offsetPlain[192] = {0}, patchPlain[768] = {0};
        int offsetDecoded = d->offsetWrapper ?
            HFADecryptWrapper(d->offsetWrapper, offsetPlain, sizeof(offsetPlain),
                              "feature-root-offset") : 0;
        int patchDecoded = d->patchWrapper ?
            HFADecryptWrapper(d->patchWrapper, patchPlain, sizeof(patchPlain),
                              "feature-root-patchData") : 0;
        descriptors++;
        HFALog("[FEATURE-ROOT-DESCRIPTOR] identifier=%s index=%u key=%s module=%s offsetSecretRVA=%llX offsetRefRVA=%llX offset=%s patchSecretRVA=%llX patchRefRVA=%llX patch=%s\n",
               identifier, descriptors,
               d->key[0] ? d->key : "?",
               d->module[0] ? d->module : "?",
               (unsigned long long)(offsetSecret ? offsetSecret - imageBase : 0),
               (unsigned long long)(offsetRef ? offsetRef - imageBase : 0),
               offsetDecoded ? offsetPlain : "?",
               (unsigned long long)(patchSecret ? patchSecret - imageBase : 0),
               (unsigned long long)(patchRef ? patchRef - imageBase : 0),
               patchDecoded ? patchPlain : "?");
    }

    unsigned nextFunctionBlocks = 0;
    unsigned blocks = HFAProbeRootBlocks(identifier, imageBase, textStart, textEnd,
                                         rootStart, rootEnd,
                                         &nextFunctionBlocks);
    const char *verdict = nativeRef && descriptors && nextFunctionBlocks ?
        "COMMON_FEATURE_ROOT" : "PARTIAL_ROOT";
    HFALog("[FEATURE-BOOTSTRAP-ROOT] identifier=%s image=%s rootRVA=%llX endRVA=%llX size=%llX anchorRVA=%llX native=%u descriptors=%u blocks=%u nextFunctionBlocks=%u featureDefinitions=%u verdict=%s\n",
           identifier, r->apiImage,
           (unsigned long long)(rootStart - imageBase),
           (unsigned long long)(rootEnd - imageBase),
           (unsigned long long)(rootEnd - rootStart),
           (unsigned long long)(anchorPC - imageBase),
           nativeRef ? 1u : 0u, descriptors, blocks, nextFunctionBlocks,
           gFeatureDefinitionCount, verdict);
}

static void HFAProbeFeatureBootstrapRoots(const char *image,
                                          const char *identifier) {
    if (!image || !*image || !identifier || !*identifier) return;
    for (unsigned i = 0; i < gNativeHookRegistrationCount; i++) {
        HFANativeHookRegistration *r = &gNativeHookRegistrations[i];
        if (strcmp(r->apiImage, image) != 0) continue;
        if (r->identifier[0] && strcmp(r->identifier, identifier) != 0) continue;
        HFAProbeFeatureBootstrapRoot(r, identifier);
    }
}

'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected custom block invoke anchor once, found {s.count(anchor)}")
s = s.replace(anchor, insert + anchor, 1)

old = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFARecoverStaticNativeHooksForImage(image, gIdentifier);
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
        HFAInstallBuiltinDispatchHooks(cls, image);
    }
'''
new = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFARecoverStaticNativeHooksForImage(image, gIdentifier);
        HFAProbeFeatureBootstrapRoots(image, gIdentifier);
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
        HFAInstallBuiltinDispatchHooks(cls, image);
    }
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.8 customSwitch action body once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.8 StaticNativeHookRecovery] loaded'
new_marker = '[HFALearn v1.9.9 FeatureBootstrapRootProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.8 patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.8 StaticNativeHookRecovery] loaded'
new_marker = '[HFALearn UI v1.9.9 FeatureBootstrapRootProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.8 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
