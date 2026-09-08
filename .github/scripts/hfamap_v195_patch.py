from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.5 traces the dynamic apply executor at action time. Discovery is by
# Objective-C method signature inside the same image as the customSwitch action;
# no obfuscated class/selector or identifier is hardcoded.
anchor = "void HFAPatchTraceObserveAction(id target, SEL action) {\n"
helper = r'''typedef struct {
    Class owner;
    SEL sel;
    IMP original;
    unsigned stage;
    char image[256];
    uintptr_t rva;
} HFADynamicApplyHook;

static HFADynamicApplyHook gDynamicApplyHooks[64];
static unsigned gDynamicApplyHookCount;
static char gDynamicApplyInstalledImage[256];
static __thread long long gDynamicApplyQ;
static __thread unsigned gDynamicApplyDepth;
static __thread char gDynamicApplyIdentifier[96];

static HFADynamicApplyHook *HFADynamicApplyHookFor(Class owner, SEL sel) {
    for (Class cls = owner; cls; cls = class_getSuperclass(cls)) {
        for (unsigned i = 0; i < gDynamicApplyHookCount; i++) {
            HFADynamicApplyHook *hook = &gDynamicApplyHooks[i];
            if (hook->owner == cls && hook->sel == sel) return hook;
        }
    }
    return NULL;
}

static void HFAHexBytes(uintptr_t address, size_t count, char *out, size_t cap) {
    if (!out || !cap) return;
    out[0] = 0;
    if (!address || !count || !HFAReadable(address, count)) {
        snprintf(out, cap, "?");
        return;
    }
    const unsigned char *bytes = (const unsigned char *)address;
    size_t maxBytes = (cap - 1) / 2;
    if (count > maxBytes) count = maxBytes;
    for (size_t i = 0; i < count; i++)
        snprintf(out + i * 2, cap - i * 2, "%02X", bytes[i]);
}

static const char *HFADynamicApplyIdentifier(HFADynamicApplyHook *hook) {
    (void)hook;
    if (gActiveCustomIdentifier[0]) return gActiveCustomIdentifier;
    if (gIdentifier[0] && HFAIdentifierIsCustomSwitch(gIdentifier)) return gIdentifier;
    if (gDynamicApplyIdentifier[0]) return gDynamicApplyIdentifier;
    return "?";
}

static void HFADynamicApplyOffset(id self, SEL _cmd, BOOL enabled,
                                  long long q, void *target, void **context) {
    HFADynamicApplyHook *hook = HFADynamicApplyHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;

    const char *identifier = HFADynamicApplyIdentifier(hook);
    char targetBytes[65] = {0}, contextBytes[65] = {0};
    uintptr_t contextValue = 0;
    if (context && HFAReadable((uintptr_t)context, sizeof(void *)))
        contextValue = (uintptr_t)*context;
    HFAHexBytes((uintptr_t)target, 16, targetBytes, sizeof(targetBytes));
    HFAHexBytes(contextValue, 16, contextBytes, sizeof(contextBytes));

    unsigned outer = gDynamicApplyDepth++;
    if (outer == 0) {
        gDynamicApplyQ = q;
        snprintf(gDynamicApplyIdentifier, sizeof(gDynamicApplyIdentifier), "%s",
                 identifier);
    }

    HFALog("[CUSTOM-DYNAMIC-APPLY] phase=begin stage=offset event=%u identifier=%s class=%s selector=%s image=%s rva=%llX enabled=%u q=%lld qHex=%llX target=%p targetBytes=%s context=%p contextValue=%p contextBytes=%s depth=%u\n",
           gEvent, identifier, class_getName((Class)self), sel_getName(_cmd),
           hook->image, (unsigned long long)hook->rva,
           enabled ? 1u : 0u, q, (unsigned long long)q,
           target, targetBytes, context, (void *)contextValue, contextBytes,
           gDynamicApplyDepth);

    ((void(*)(id,SEL,BOOL,long long,void *,void **))hook->original)(
        self, _cmd, enabled, q, target, context);

    HFALog("[CUSTOM-DYNAMIC-APPLY] phase=end stage=offset event=%u identifier=%s class=%s selector=%s enabled=%u q=%lld qHex=%llX target=%p context=%p depth=%u\n",
           gEvent, identifier, class_getName((Class)self), sel_getName(_cmd),
           enabled ? 1u : 0u, q, (unsigned long long)q, target, context,
           gDynamicApplyDepth);

    if (gDynamicApplyDepth && --gDynamicApplyDepth == 0) {
        gDynamicApplyQ = 0;
        gDynamicApplyIdentifier[0] = 0;
    }
}

static void HFADynamicApplyResolved(id self, SEL _cmd, BOOL enabled,
                                    void *resolvedAddress, void *target,
                                    void **context) {
    HFADynamicApplyHook *hook = HFADynamicApplyHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;

    const char *identifier = HFADynamicApplyIdentifier(hook);
    long long q = gDynamicApplyQ;
    uintptr_t resolved = (uintptr_t)resolvedAddress;
    uintptr_t base = q ? resolved - (uintptr_t)q : 0;
    uintptr_t contextValue = 0;
    if (context && HFAReadable((uintptr_t)context, sizeof(void *)))
        contextValue = (uintptr_t)*context;

    char before[129] = {0}, after[129] = {0};
    char targetBytes[65] = {0}, contextBytes[65] = {0};
    HFAHexBytes(resolved, 32, before, sizeof(before));
    HFAHexBytes((uintptr_t)target, 16, targetBytes, sizeof(targetBytes));
    HFAHexBytes(contextValue, 16, contextBytes, sizeof(contextBytes));

    Dl_info resolvedInfo = {0};
    dladdr(resolvedAddress, &resolvedInfo);
    uintptr_t resolvedRVA = resolvedInfo.dli_fbase
        ? resolved - (uintptr_t)resolvedInfo.dli_fbase : 0;

    HFALog("[CUSTOM-DYNAMIC-APPLY] phase=begin stage=resolved event=%u identifier=%s class=%s selector=%s image=%s rva=%llX enabled=%u q=%lld qHex=%llX base=%p resolved=%p resolvedImage=%s resolvedRVA=%llX before=%s target=%p targetBytes=%s context=%p contextValue=%p contextBytes=%s depth=%u\n",
           gEvent, identifier, class_getName((Class)self), sel_getName(_cmd),
           hook->image, (unsigned long long)hook->rva,
           enabled ? 1u : 0u, q, (unsigned long long)q, (void *)base,
           resolvedAddress,
           resolvedInfo.dli_fname ? HFABase(resolvedInfo.dli_fname) : "?",
           (unsigned long long)resolvedRVA, before,
           target, targetBytes, context, (void *)contextValue, contextBytes,
           gDynamicApplyDepth);

    ((void(*)(id,SEL,BOOL,void *,void *,void **))hook->original)(
        self, _cmd, enabled, resolvedAddress, target, context);

    HFAHexBytes(resolved, 32, after, sizeof(after));
    HFALog("[CUSTOM-DYNAMIC-APPLY] phase=end stage=resolved event=%u identifier=%s class=%s selector=%s enabled=%u q=%lld qHex=%llX base=%p resolved=%p resolvedImage=%s resolvedRVA=%llX after=%s target=%p context=%p depth=%u\n",
           gEvent, identifier, class_getName((Class)self), sel_getName(_cmd),
           enabled ? 1u : 0u, q, (unsigned long long)q, (void *)base,
           resolvedAddress,
           resolvedInfo.dli_fname ? HFABase(resolvedInfo.dli_fname) : "?",
           (unsigned long long)resolvedRVA, after, target, context,
           gDynamicApplyDepth);
}

static int HFADynamicApplyStageForMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 6) return 0;
    char ret[32] = {0}, a1[32] = {0}, a2[32] = {0}, a3[32] = {0}, a4[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    method_getArgumentType(method, 2, a1, sizeof(a1));
    method_getArgumentType(method, 3, a2, sizeof(a2));
    method_getArgumentType(method, 4, a3, sizeof(a3));
    method_getArgumentType(method, 5, a4, sizeof(a4));
    const char *r = HFASkipObjCTypeQualifiers(ret);
    const char *t1 = HFASkipObjCTypeQualifiers(a1);
    const char *t2 = HFASkipObjCTypeQualifiers(a2);
    const char *t3 = HFASkipObjCTypeQualifiers(a3);
    const char *t4 = HFASkipObjCTypeQualifiers(a4);
    if (*r != 'v' || *t1 != 'B' || strcmp(t4, "^^v") != 0) return 0;
    if ((*t2 == 'q' || *t2 == 'Q') && strcmp(t3, "^v") == 0) return 1;
    if (strcmp(t2, "^v") == 0 && strcmp(t3, "^v") == 0) return 2;
    return 0;
}

static unsigned HFAInstallDynamicApplyHooksForImage(const char *image) {
    if (!image || !*image) return 0;
    if (gDynamicApplyInstalledImage[0] &&
        strcmp(gDynamicApplyInstalledImage, image) == 0)
        return 0;

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return 0;
    Class *classes = (Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return 0;
    classCount = objc_getClassList(classes, classCount);
    unsigned candidates = 0, installed = 0;

    for (int ci = 0; ci < classCount && gDynamicApplyHookCount < 64; ci++) {
        Class cls = classes[ci];
        if (!cls) continue;
        Class meta = object_getClass(cls);
        if (!meta) continue;
        unsigned methodCount = 0;
        Method *methods = class_copyMethodList(meta, &methodCount);
        for (unsigned mi = 0; methods && mi < methodCount &&
             gDynamicApplyHookCount < 64; mi++) {
            Method method = methods[mi];
            int stage = HFADynamicApplyStageForMethod(method);
            if (!stage) continue;
            IMP original = method_getImplementation(method);
            Dl_info info = {0};
            if (!original || !dladdr((void *)original, &info) ||
                !info.dli_fname || !info.dli_fbase)
                continue;
            if (strcmp(HFABase(info.dli_fname), image) != 0) continue;
            candidates++;
            SEL sel = method_getName(method);
            if (!sel || HFADynamicApplyHookFor(meta, sel)) continue;

            HFADynamicApplyHook *hook = &gDynamicApplyHooks[gDynamicApplyHookCount++];
            memset(hook, 0, sizeof(*hook));
            hook->owner = meta;
            hook->sel = sel;
            hook->original = original;
            hook->stage = (unsigned)stage;
            hook->rva = (uintptr_t)original - (uintptr_t)info.dli_fbase;
            snprintf(hook->image, sizeof(hook->image), "%s", image);

            IMP replacement = stage == 1 ? (IMP)HFADynamicApplyOffset
                                         : (IMP)HFADynamicApplyResolved;
            method_setImplementation(method, replacement);
            installed++;
            HFALog("[CUSTOM-DYNAMIC-APPLY-HOOK] image=%s class=%s selector=%s stage=%s rva=%llX installed=1\n",
                   image, class_getName(cls), sel_getName(sel),
                   stage == 1 ? "offset" : "resolved",
                   (unsigned long long)hook->rva);
        }
        free(methods);
    }
    free(classes);
    snprintf(gDynamicApplyInstalledImage, sizeof(gDynamicApplyInstalledImage),
             "%s", image);
    HFALog("[CUSTOM-DYNAMIC-APPLY-SCAN] image=%s classes=%d candidates=%u installed=%u\n",
           image, classCount, candidates, installed);
    return installed;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected ObserveAction anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
    }
'''
new = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
    }
'''
if s.count(old) != 1:
    raise SystemExit(f"expected customSwitch ObserveAction body once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.4 CustomSwitchDynamicBlockProbe] loaded'
new_marker = '[HFALearn v1.9.5 CustomDynamicApplyProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.4 patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)

patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.4 CustomSwitchDynamicBlockProbe] loaded'
new_marker = '[HFALearn UI v1.9.5 CustomDynamicApplyProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.4 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
