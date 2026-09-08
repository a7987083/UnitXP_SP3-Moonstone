from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# Forward declaration so feature-type discovery can associate a customSwitch
# with a native-hook registration captured earlier during image initialization.
old = r'''void HFARegisterFeatureType(const char *identifier, const char *type) {
    if (!identifier || !*identifier || !type || !*type) return;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        if (strcmp(definition->identifier, identifier) != 0) continue;
        snprintf(definition->type, sizeof(definition->type), "%s", type);
        return;
    }
}
'''
new = r'''static void HFAAssociateNativeHookWithCustomSwitch(const char *identifier);

void HFARegisterFeatureType(const char *identifier, const char *type) {
    if (!identifier || !*identifier || !type || !*type) return;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        if (strcmp(definition->identifier, identifier) != 0) continue;
        snprintf(definition->type, sizeof(definition->type), "%s", type);
        if (strcmp(type, "customSwitch") == 0)
            HFAAssociateNativeHookWithCustomSwitch(identifier);
        return;
    }
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected feature type function once, found {s.count(old)}")
s = s.replace(old, new, 1)

# Insert the native-hook API probe after the existing secret-wrapper decoder so
# the captured target wrapper can be decrypted immediately while it is valid.
anchor = r'''static uintptr_t HFACustomBlockInvoke(void *block, uintptr_t a1, uintptr_t a2,
'''
insert = r'''
typedef void (*HFANativeHookAPIIMP)(id, SEL, id, void *, void **);

typedef struct {
    Class owner;
    SEL sel;
    IMP original;
    char image[256];
    uintptr_t apiRVA;
} HFANativeHookAPIHook;

typedef struct {
    unsigned sequence;
    id targetWrapper;
    char targetClass[128];
    char targetPlain[192];
    char apiImage[256];
    uintptr_t apiRVA;
    char replacementImage[256];
    uintptr_t replacementRVA;
    uintptr_t replacement;
    char slotImage[256];
    uintptr_t slotRVA;
    uintptr_t slot;
    char originalImage[256];
    uintptr_t originalRVA;
    uintptr_t original;
    char identifier[96];
} HFANativeHookRegistration;

static HFANativeHookAPIHook gNativeHookAPIs[32];
static unsigned gNativeHookAPICount;
static HFANativeHookRegistration gNativeHookRegistrations[64];
static unsigned gNativeHookRegistrationCount;
static unsigned gNativeHookSequence;

static const char *HFAImageNameForHeader(const struct mach_header *mh) {
    if (!mh) return NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++)
        if (_dyld_get_image_header(i) == mh) return _dyld_get_image_name(i);
    return NULL;
}

static int HFASectionContains(const char *bytes, size_t size, const char *needle) {
    if (!bytes || !needle) return 0;
    size_t n = strlen(needle);
    if (!n || size < n) return 0;
    for (size_t i = 0; i + n <= size; i++)
        if (memcmp(bytes + i, needle, n) == 0) return 1;
    return 0;
}

static int HFAImageHasMenuFingerprint(const struct mach_header *mh, intptr_t slide) {
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    const char *a = "Made by Laxus for iOSGods.com!";
    const char *b = "Made for iOSGods.com";
    int haveA = 0, haveB = 0;
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg =
                (const struct segment_command_64 *)cursor;
            const struct section_64 *sec =
                (const struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                if (strncmp(sec->sectname, "__cstring", 16) != 0) continue;
                const char *bytes = (const char *)(uintptr_t)(sec->addr + slide);
                size_t size = (size_t)sec->size;
                if (HFASectionContains(bytes, size, a)) haveA = 1;
                if (HFASectionContains(bytes, size, b)) haveB = 1;
                if (haveA && haveB) return 1;
            }
        }
        if (!lc->cmdsize) break;
        cursor += lc->cmdsize;
    }
    return 0;
}

static HFANativeHookAPIHook *HFANativeHookAPIFor(Class owner, SEL sel) {
    for (unsigned i = 0; i < gNativeHookAPICount; i++)
        if (gNativeHookAPIs[i].owner == owner && gNativeHookAPIs[i].sel == sel)
            return &gNativeHookAPIs[i];
    return NULL;
}

static void HFADescribePointer(uintptr_t value, char *image, size_t imageCap,
                               uintptr_t *rvaOut) {
    if (image && imageCap) image[0] = 0;
    if (rvaOut) *rvaOut = 0;
    if (!value) return;
    Dl_info info = {0};
    if (!dladdr((void *)value, &info) || !info.dli_fbase) return;
    if (image && imageCap)
        snprintf(image, imageCap, "%s", HFABase(info.dli_fname));
    if (rvaOut) *rvaOut = value - (uintptr_t)info.dli_fbase;
}

static void HFANativeHookAPIWrapper(id self, SEL _cmd, id targetWrapper,
                                    void *replacement, void **originalOut) {
    HFANativeHookAPIHook *hook = HFANativeHookAPIFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;

    char targetPlain[192] = {0};
    int decoded = HFADecryptWrapper(targetWrapper, targetPlain,
                                    sizeof(targetPlain), "native-hook-target");
    char replacementImage[256] = {0}, slotImage[256] = {0};
    uintptr_t replacementRVA = 0, slotRVA = 0;
    HFADescribePointer((uintptr_t)replacement, replacementImage,
                       sizeof(replacementImage), &replacementRVA);
    HFADescribePointer((uintptr_t)originalOut, slotImage,
                       sizeof(slotImage), &slotRVA);

    HFALog("[CUSTOM-NATIVE-HOOK-REGISTER] phase=begin apiClass=%s selector=%s apiImage=%s apiRVA=%llX wrapper=%p wrapperClass=%s decoded=%d target=%s replacement=%p replacementImage=%s replacementRVA=%llX originalSlot=%p slotImage=%s slotRVA=%llX\n",
           class_getName(object_getClass(self)), sel_getName(_cmd),
           hook->image, (unsigned long long)hook->apiRVA,
           targetWrapper,
           targetWrapper ? class_getName(object_getClass(targetWrapper)) : "?",
           decoded, decoded ? targetPlain : "?", replacement,
           replacementImage[0] ? replacementImage : "?",
           (unsigned long long)replacementRVA, originalOut,
           slotImage[0] ? slotImage : "?", (unsigned long long)slotRVA);

    ((HFANativeHookAPIIMP)hook->original)(self, _cmd, targetWrapper,
                                         replacement, originalOut);

    uintptr_t original = originalOut ? (uintptr_t)*originalOut : 0;
    char originalImage[256] = {0};
    uintptr_t originalRVA = 0;
    HFADescribePointer(original, originalImage, sizeof(originalImage), &originalRVA);

    HFALog("[CUSTOM-NATIVE-HOOK-REGISTER] phase=end apiClass=%s selector=%s target=%s replacementImage=%s replacementRVA=%llX original=%p originalImage=%s originalRVA=%llX\n",
           class_getName(object_getClass(self)), sel_getName(_cmd),
           decoded ? targetPlain : "?",
           replacementImage[0] ? replacementImage : "?",
           (unsigned long long)replacementRVA, (void *)original,
           originalImage[0] ? originalImage : "?",
           (unsigned long long)originalRVA);

    if (gNativeHookRegistrationCount < 64) {
        HFANativeHookRegistration *r =
            &gNativeHookRegistrations[gNativeHookRegistrationCount++];
        memset(r, 0, sizeof(*r));
        r->sequence = ++gNativeHookSequence;
        r->targetWrapper = targetWrapper;
        snprintf(r->targetClass, sizeof(r->targetClass), "%s",
                 targetWrapper ? class_getName(object_getClass(targetWrapper)) : "?");
        if (decoded) snprintf(r->targetPlain, sizeof(r->targetPlain), "%s", targetPlain);
        snprintf(r->apiImage, sizeof(r->apiImage), "%s", hook->image);
        r->apiRVA = hook->apiRVA;
        r->replacement = (uintptr_t)replacement;
        snprintf(r->replacementImage, sizeof(r->replacementImage), "%s",
                 replacementImage[0] ? replacementImage : "?");
        r->replacementRVA = replacementRVA;
        r->slot = (uintptr_t)originalOut;
        snprintf(r->slotImage, sizeof(r->slotImage), "%s",
                 slotImage[0] ? slotImage : "?");
        r->slotRVA = slotRVA;
        r->original = original;
        snprintf(r->originalImage, sizeof(r->originalImage), "%s",
                 originalImage[0] ? originalImage : "?");
        r->originalRVA = originalRVA;
    }
}

static int HFATypeIsObject(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type && *type == '@';
}

static int HFATypeIsVoidPointer(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type && strcmp(type, "^v") == 0;
}

static int HFATypeIsVoidPointerPointer(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type && strcmp(type, "^^v") == 0;
}

static unsigned HFAInstallNativeHookAPIsOnOwner(Class owner,
                                                 const char *image) {
    if (!owner || !image || !*image) return 0;
    unsigned count = 0, installed = 0;
    Method *methods = class_copyMethodList(owner, &count);
    for (unsigned i = 0; methods && i < count && gNativeHookAPICount < 32; i++) {
        Method method = methods[i];
        if (method_getNumberOfArguments(method) != 5) continue;
        char ret[16] = {0}, a2[32] = {0}, a3[32] = {0}, a4[32] = {0};
        method_getReturnType(method, ret, sizeof(ret));
        method_getArgumentType(method, 2, a2, sizeof(a2));
        method_getArgumentType(method, 3, a3, sizeof(a3));
        method_getArgumentType(method, 4, a4, sizeof(a4));
        const char *r = ret;
        while (*r && strchr("rnNoORV", *r)) r++;
        if (*r != 'v' || !HFATypeIsObject(a2) ||
            !HFATypeIsVoidPointer(a3) || !HFATypeIsVoidPointerPointer(a4))
            continue;

        SEL sel = method_getName(method);
        if (!sel || HFANativeHookAPIFor(owner, sel)) continue;
        IMP imp = method_getImplementation(method);
        Dl_info info = {0};
        if (!imp || !dladdr((void *)imp, &info) || !info.dli_fbase ||
            !info.dli_fname || strcmp(HFABase(info.dli_fname), image) != 0)
            continue;

        HFANativeHookAPIHook *hook = &gNativeHookAPIs[gNativeHookAPICount++];
        memset(hook, 0, sizeof(*hook));
        hook->owner = owner;
        hook->sel = sel;
        hook->original = imp;
        snprintf(hook->image, sizeof(hook->image), "%s", image);
        hook->apiRVA = (uintptr_t)imp - (uintptr_t)info.dli_fbase;
        method_setImplementation(method, (IMP)HFANativeHookAPIWrapper);
        installed++;
        HFALog("[CUSTOM-NATIVE-HOOK-API] class=%s selector=%s image=%s rva=%llX installed=1 types=%s\n",
               class_getName(owner), sel_getName(sel), image,
               (unsigned long long)hook->apiRVA,
               method_getTypeEncoding(method) ? method_getTypeEncoding(method) : "?");
    }
    free(methods);
    return installed;
}

static void HFAInstallNativeHookAPIsForImage(const char *image) {
    if (!image || !*image) return;
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return;
    classCount = objc_getClassList(classes, classCount);
    unsigned installed = 0;
    for (int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        installed += HFAInstallNativeHookAPIsOnOwner(cls, image);
        Class meta = object_getClass(cls);
        if (meta) installed += HFAInstallNativeHookAPIsOnOwner(meta, image);
    }
    free(classes);
    HFALog("[CUSTOM-NATIVE-HOOK-SCAN] image=%s installed=%u totalAPIs=%u\n",
           image, installed, gNativeHookAPICount);
}

static void HFANativeImageAdded(const struct mach_header *mh, intptr_t slide) {
    const char *path = HFAImageNameForHeader(mh);
    const char *image = path ? HFABase(path) : "?";
    if (!HFAImageHasMenuFingerprint(mh, slide)) return;
    HFALog("[CUSTOM-NATIVE-HOOK-IMAGE] image=%s slide=%llX fingerprint=1\n",
           image, (unsigned long long)slide);
    HFAInstallNativeHookAPIsForImage(image);
}

static void HFAAssociateNativeHookWithCustomSwitch(const char *identifier) {
    if (!identifier || !*identifier) return;
    for (unsigned i = 0; i < gNativeHookRegistrationCount; i++) {
        HFANativeHookRegistration *r = &gNativeHookRegistrations[i];
        if (r->identifier[0] && strcmp(r->identifier, identifier) == 0) return;
    }

    unsigned unmatched = 0;
    HFANativeHookRegistration *candidate = NULL;
    for (unsigned i = 0; i < gNativeHookRegistrationCount; i++) {
        HFANativeHookRegistration *r = &gNativeHookRegistrations[i];
        if (r->identifier[0]) continue;
        unmatched++;
        candidate = r;
    }
    if (unmatched != 1 || !candidate) {
        HFALog("[CUSTOM-NATIVE-HOOK-ASSOC] identifier=%s candidates=%u status=%s\n",
               identifier, unmatched, unmatched ? "AMBIGUOUS" : "NONE");
        return;
    }

    snprintf(candidate->identifier, sizeof(candidate->identifier), "%s", identifier);
    HFAFeatureDefinition *definition = HFAFeatureDefinitionForIdentifier(identifier);
    HFALog("[CUSTOM-NATIVE-HOOK-ASSOC] identifier=%s label=%s candidates=1 status=ASSOCIATED sequence=%u target=%s replacementImage=%s replacementRVA=%llX originalSlotImage=%s originalSlotRVA=%llX originalImage=%s originalRVA=%llX\n",
           identifier,
           definition && definition->label[0] ? definition->label : "?",
           candidate->sequence,
           candidate->targetPlain[0] ? candidate->targetPlain : "?",
           candidate->replacementImage[0] ? candidate->replacementImage : "?",
           (unsigned long long)candidate->replacementRVA,
           candidate->slotImage[0] ? candidate->slotImage : "?",
           (unsigned long long)candidate->slotRVA,
           candidate->originalImage[0] ? candidate->originalImage : "?",
           (unsigned long long)candidate->originalRVA);
    HFALog("[CUSTOM-NATIVE-HOOK-MAPPING] title=\"%s\" identifier=%s type=customSwitch/nativeHook target=%s replacement=%s+0x%llX originalSlot=%s+0x%llX original=%s+0x%llX\n",
           definition && definition->label[0] ? definition->label : "?",
           identifier,
           candidate->targetPlain[0] ? candidate->targetPlain : "?",
           candidate->replacementImage[0] ? candidate->replacementImage : "?",
           (unsigned long long)candidate->replacementRVA,
           candidate->slotImage[0] ? candidate->slotImage : "?",
           (unsigned long long)candidate->slotRVA,
           candidate->originalImage[0] ? candidate->originalImage : "?",
           (unsigned long long)candidate->originalRVA);
}

'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected custom block invoke anchor once, found {s.count(anchor)}")
s = s.replace(anchor, insert + anchor, 1)

old = r'''__attribute__((constructor)) static void HFAInit(void) {
    HFALog("[HFALearn v1.9.6 CustomSwitchBuiltinDispatchProbe] loaded\n");
}
'''
new = r'''__attribute__((constructor)) static void HFAInit(void) {
    HFALog("[HFALearn v1.9.7 CustomSwitchNativeHookProbe] loaded\n");
    _dyld_register_func_for_add_image(HFANativeImageAdded);
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.6 constructor once, found {s.count(old)}")
s = s.replace(old, new, 1)

patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.6 CustomSwitchBuiltinDispatchProbe] loaded'
new_marker = '[HFALearn UI v1.9.7 CustomSwitchNativeHookProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.6 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
