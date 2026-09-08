from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.8: registration may have completed before HFAMap is loaded. Recover the
# native-hook registration statically from the already-loaded menu Mach-O. The
# pattern is generic ARM64 data flow: ADR x2 -> IGSecretInt blob, ADR x3 ->
# replacement, ADRP/ADD x4 -> original slot, followed by an ObjC call. No
# obfuscated selector, class name, k1 identifier, or fixed RVA is hardcoded.
anchor = r'''static uintptr_t HFACustomBlockInvoke(void *block, uintptr_t a1, uintptr_t a2,
'''
insert = r'''
static int64_t HFAStaticSignExtend(uint64_t value, unsigned bits) {
    return (int64_t)(value << (64u - bits)) >> (64u - bits);
}

static uintptr_t HFAStaticADRTarget(uintptr_t pc, uint32_t word,
                                    unsigned expectedRegister) {
    if ((word & 0x9F000000u) != 0x10000000u ||
        (word & 31u) != expectedRegister)
        return 0;
    uint64_t imm = (((uint64_t)(word >> 5) & 0x7FFFFu) << 2) |
                   ((word >> 29) & 3u);
    int64_t displacement = HFAStaticSignExtend(imm, 21);
    return (uintptr_t)((intptr_t)pc + displacement);
}

static uintptr_t HFAStaticADRPPage(uintptr_t pc, uint32_t word,
                                   unsigned expectedRegister) {
    if ((word & 0x9F000000u) != 0x90000000u ||
        (word & 31u) != expectedRegister)
        return 0;
    uint64_t imm = (((uint64_t)(word >> 5) & 0x7FFFFu) << 2) |
                   ((word >> 29) & 3u);
    int64_t displacement = HFAStaticSignExtend(imm, 21) << 12;
    return (uintptr_t)((intptr_t)(pc & ~(uintptr_t)0xFFFu) + displacement);
}

static int HFAStaticADDImmX4(uint32_t word, uintptr_t *offsetOut) {
    if ((word & 0xFF000000u) != 0x91000000u ||
        (word & 31u) != 4u || ((word >> 5) & 31u) != 4u)
        return 0;
    uintptr_t imm = (uintptr_t)((word >> 10) & 0xFFFu);
    if ((word >> 22) & 1u) imm <<= 12;
    if (offsetOut) *offsetOut = imm;
    return 1;
}

static int HFAStaticLooksLikeIntSecret(uintptr_t address,
                                       uint32_t *lengthOut,
                                       uint32_t *flagsOut) {
    if (!address || !HFAReadable(address, 8)) return 0;
    uint32_t length = 0, flags = 0;
    memcpy(&length, (const void *)address, 4);
    memcpy(&flags, (const void *)(address + 4), 4);
    if (!length || length > 0x100u || (flags >> 24) != 2u ||
        ((flags >> 16) & 0xFFu) != 3u)
        return 0;
    size_t blobSize = (size_t)(length & ~0xFu) + 0x28u;
    if (blobSize < 0x28u || blobSize > 0x200u ||
        !HFAReadable(address, blobSize))
        return 0;
    if (lengthOut) *lengthOut = length;
    if (flagsOut) *flagsOut = flags;
    return 1;
}

static int HFAStaticFindTextSection(const struct mach_header *mh,
                                    intptr_t slide,
                                    uintptr_t *startOut,
                                    uintptr_t *endOut) {
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *sec =
                (const struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                if (strncmp(sec->sectname, "__text", 16) != 0) continue;
                uintptr_t start = (uintptr_t)(sec->addr + slide);
                uintptr_t end = start + (uintptr_t)sec->size;
                if (!start || end <= start) return 0;
                if (startOut) *startOut = start;
                if (endOut) *endOut = end;
                return 1;
            }
        }
        if (!lc->cmdsize) break;
        cursor += lc->cmdsize;
    }
    return 0;
}

static int HFAStaticImageForName(const char *image,
                                 const struct mach_header **headerOut,
                                 intptr_t *slideOut,
                                 uintptr_t *baseOut) {
    if (!image || !*image) return 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *path = _dyld_get_image_name(i);
        if (!path || strcmp(HFABase(path), image) != 0) continue;
        const struct mach_header *mh = _dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (headerOut) *headerOut = mh;
        if (slideOut) *slideOut = slide;
        if (baseOut) *baseOut = (uintptr_t)mh;
        return mh != NULL;
    }
    return 0;
}

static const char *HFAStaticSkipQualifiers(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static SEL HFAStaticSecretInitializerForClass(Class cls) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned count = 0;
        Method *methods = class_copyMethodList(current, &count);
        for (unsigned i = 0; methods && i < count; i++) {
            Method method = methods[i];
            if (method_getNumberOfArguments(method) != 3) continue;
            char ret[32] = {0}, arg[96] = {0};
            method_getReturnType(method, ret, sizeof(ret));
            method_getArgumentType(method, 2, arg, sizeof(arg));
            const char *r = HFAStaticSkipQualifiers(ret);
            const char *a = HFAStaticSkipQualifiers(arg);
            if (*r != '@' || *a != '^') continue;
            SEL sel = method_getName(method);
            if (!sel || strcmp(sel_getName(sel), "secret") == 0) continue;
            free(methods);
            return sel;
        }
        free(methods);
    }
    return NULL;
}

static id HFAStaticCreateSecretWrapper(const char *image,
                                       uintptr_t secretAddress) {
    if (!image || !*image || !secretAddress) return nil;
    SEL secretSel = sel_registerName("secret");
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return nil;
    Class *classes = (Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return nil;
    classCount = objc_getClassList(classes, classCount);
    id result = nil;
    for (int i = 0; i < classCount && !result; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        Method getter = class_getInstanceMethod(cls, secretSel);
        if (!getter) continue;
        IMP getterIMP = method_getImplementation(getter);
        Dl_info info = {0};
        if (!getterIMP || !dladdr((void *)getterIMP, &info) ||
            !info.dli_fname || strcmp(HFABase(info.dli_fname), image) != 0)
            continue;
        SEL initSel = HFAStaticSecretInitializerForClass(cls);
        if (!initSel) continue;
        id object = ((id(*)(id,SEL))objc_msgSend)((id)cls,
                                                   sel_registerName("alloc"));
        if (!object) continue;
        result = ((id(*)(id,SEL,const void *))objc_msgSend)(
            object, initSel, (const void *)secretAddress);
        if (result) {
            HFALog("[CUSTOM-STATIC-NATIVE-WRAPPER] image=%s class=%s initializer=%s wrapper=%p secret=%p\n",
                   image, class_getName(cls), sel_getName(initSel), result,
                   (void *)secretAddress);
        }
    }
    free(classes);
    return result;
}

static int HFAStaticRegistrationExists(uintptr_t replacement, uintptr_t slot) {
    for (unsigned i = 0; i < gNativeHookRegistrationCount; i++) {
        HFANativeHookRegistration *r = &gNativeHookRegistrations[i];
        if (r->replacement == replacement && r->slot == slot) return 1;
    }
    return 0;
}

static unsigned HFARecoverStaticNativeHooksForImage(const char *image,
                                                     const char *identifier) {
    if (!image || !*image) return 0;
    const struct mach_header *mh = NULL;
    intptr_t slide = 0;
    uintptr_t imageBase = 0, textStart = 0, textEnd = 0;
    if (!HFAStaticImageForName(image, &mh, &slide, &imageBase) ||
        !HFAStaticFindTextSection(mh, slide, &textStart, &textEnd)) {
        HFALog("[CUSTOM-STATIC-NATIVE-SCAN] image=%s status=NO_TEXT\n", image);
        return 0;
    }

    unsigned candidates = 0, recovered = 0;
    for (uintptr_t pc = textStart; pc + 4 <= textEnd; pc += 4) {
        if (!HFAReadable(pc, 4)) break;
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);
        uintptr_t secret = HFAStaticADRTarget(pc, word, 2);
        uint32_t secretLength = 0, secretFlags = 0;
        if (!secret || !HFAStaticLooksLikeIntSecret(secret, &secretLength,
                                                     &secretFlags))
            continue;

        uintptr_t replacement = 0, adr3PC = 0;
        for (uintptr_t p = pc + 4; p < pc + 0x50u && p + 4 <= textEnd; p += 4) {
            uint32_t w = 0; memcpy(&w, (const void *)p, 4);
            uintptr_t candidate = HFAStaticADRTarget(p, w, 3);
            if (candidate && candidate >= textStart && candidate < textEnd) {
                replacement = candidate;
                adr3PC = p;
                break;
            }
        }
        if (!replacement) continue;

        uintptr_t slot = 0, addPC = 0;
        for (uintptr_t p = adr3PC + 4; p < adr3PC + 0x30u &&
             p + 4 <= textEnd; p += 4) {
            uint32_t w = 0; memcpy(&w, (const void *)p, 4);
            uintptr_t page = HFAStaticADRPPage(p, w, 4);
            if (!page) continue;
            for (uintptr_t q = p + 4; q < p + 0x10u &&
                 q + 4 <= textEnd; q += 4) {
                uint32_t aw = 0; memcpy(&aw, (const void *)q, 4);
                uintptr_t add = 0;
                if (!HFAStaticADDImmX4(aw, &add)) continue;
                slot = page + add;
                addPC = q;
                break;
            }
            if (slot) break;
        }
        if (!slot || !HFAReadable(slot, sizeof(uintptr_t))) continue;

        uintptr_t callsite = 0;
        for (uintptr_t p = addPC + 4; p < addPC + 0x20u &&
             p + 4 <= textEnd; p += 4) {
            uint32_t w = 0; memcpy(&w, (const void *)p, 4);
            if ((w & 0xFC000000u) == 0x94000000u) {
                callsite = p;
                break;
            }
        }
        if (!callsite) continue;

        candidates++;
        if (HFAStaticRegistrationExists(replacement, slot)) continue;

        id wrapper = HFAStaticCreateSecretWrapper(image, secret);
        char targetPlain[192] = {0};
        int decoded = wrapper ? HFADecryptWrapper(wrapper, targetPlain,
                                                   sizeof(targetPlain),
                                                   "static-native-hook-target") : 0;

        uintptr_t rawOriginal = 0;
        memcpy(&rawOriginal, (const void *)slot, sizeof(rawOriginal));
        rawOriginal = HFAStripCodePointer(rawOriginal);
        uintptr_t resolvedOriginal = HFAResolveTrampoline(rawOriginal);
        if (!resolvedOriginal) resolvedOriginal = rawOriginal;

        char replacementImage[256] = {0}, slotImage[256] = {0},
             originalImage[256] = {0};
        uintptr_t replacementRVA = 0, slotRVA = 0, originalRVA = 0;
        HFADescribePointer(replacement, replacementImage,
                           sizeof(replacementImage), &replacementRVA);
        HFADescribePointer(slot, slotImage, sizeof(slotImage), &slotRVA);
        HFADescribePointer(resolvedOriginal, originalImage,
                           sizeof(originalImage), &originalRVA);

        HFALog("[CUSTOM-STATIC-NATIVE-HOOK] identifier=%s image=%s callsiteRVA=%llX secretRVA=%llX len=%u flags=%08X decoded=%d target=%s replacement=%p replacementImage=%s replacementRVA=%llX originalSlot=%p slotImage=%s slotRVA=%llX rawOriginal=%p resolvedOriginal=%p originalImage=%s originalRVA=%llX\n",
               identifier && *identifier ? identifier : "?", image,
               (unsigned long long)(callsite - imageBase),
               (unsigned long long)(secret - imageBase), secretLength,
               secretFlags, decoded, decoded ? targetPlain : "?",
               (void *)replacement,
               replacementImage[0] ? replacementImage : "?",
               (unsigned long long)replacementRVA, (void *)slot,
               slotImage[0] ? slotImage : "?",
               (unsigned long long)slotRVA, (void *)rawOriginal,
               (void *)resolvedOriginal,
               originalImage[0] ? originalImage : "?",
               (unsigned long long)originalRVA);

        if (gNativeHookRegistrationCount < 64) {
            HFANativeHookRegistration *r =
                &gNativeHookRegistrations[gNativeHookRegistrationCount++];
            memset(r, 0, sizeof(*r));
            r->sequence = ++gNativeHookSequence;
            r->targetWrapper = wrapper;
            snprintf(r->targetClass, sizeof(r->targetClass), "%s",
                     wrapper ? class_getName(object_getClass(wrapper)) : "?");
            if (decoded)
                snprintf(r->targetPlain, sizeof(r->targetPlain), "%s", targetPlain);
            snprintf(r->apiImage, sizeof(r->apiImage), "%s", image);
            r->apiRVA = callsite - imageBase;
            r->replacement = replacement;
            snprintf(r->replacementImage, sizeof(r->replacementImage), "%s",
                     replacementImage[0] ? replacementImage : "?");
            r->replacementRVA = replacementRVA;
            r->slot = slot;
            snprintf(r->slotImage, sizeof(r->slotImage), "%s",
                     slotImage[0] ? slotImage : "?");
            r->slotRVA = slotRVA;
            r->original = rawOriginal;
            snprintf(r->originalImage, sizeof(r->originalImage), "%s",
                     originalImage[0] ? originalImage : "?");
            r->originalRVA = originalRVA;
            recovered++;
        }
    }

    HFALog("[CUSTOM-STATIC-NATIVE-SCAN] image=%s identifier=%s candidates=%u recovered=%u registrations=%u\n",
           image, identifier && *identifier ? identifier : "?", candidates,
           recovered, gNativeHookRegistrationCount);
    if (identifier && *identifier)
        HFAAssociateNativeHookWithCustomSwitch(identifier);
    return recovered;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected custom block anchor once, found {s.count(anchor)}")
s = s.replace(anchor, insert, 1)

old = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
        HFAInstallBuiltinDispatchHooks(cls, image);
    }
'''
new = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFARecoverStaticNativeHooksForImage(image, gIdentifier);
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
        HFAInstallBuiltinDispatchHooks(cls, image);
    }
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.6 customSwitch action body once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.7 CustomSwitchNativeHookProbe] loaded'
new_marker = '[HFALearn v1.9.8 StaticNativeHookRecovery] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.7 patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.7 CustomSwitchNativeHookProbe] loaded'
new_marker = '[HFALearn UI v1.9.8 StaticNativeHookRecovery] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.7 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
