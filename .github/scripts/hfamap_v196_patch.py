from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.6: identify the built-in customSwitch dispatcher dynamically on the
# current menu host. We intentionally do not hardcode the obfuscated selector
# or the identifier (k1). Exact void(id) methods are wrapped, but logging/probing
# only activates when the argument is a known type=customSwitch identifier.
anchor = r'''static const char *HFAObjectString(id value) {
    if (!value) return NULL;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value UTF8String];
    return NULL;
}
'''
insert = anchor + r'''

typedef struct {
    Class owner;
    SEL sel;
    IMP chainOriginal;
    IMP targetOriginal;
    char image[256];
    uintptr_t rva;
    unsigned probed;
} HFABuiltinDispatchHook;

static HFABuiltinDispatchHook gBuiltinDispatchHooks[128];
static unsigned gBuiltinDispatchHookCount;
static __thread unsigned gBuiltinDispatchDepth;
static __thread unsigned gBuiltinDispatchEvent;
static __thread char gBuiltinDispatchIdentifier[96];

static HFABuiltinDispatchHook *HFABuiltinDispatchHookFor(Class owner, SEL sel) {
    for (Class cls = owner; cls; cls = class_getSuperclass(cls)) {
        for (unsigned i = 0; i < gBuiltinDispatchHookCount; i++) {
            HFABuiltinDispatchHook *hook = &gBuiltinDispatchHooks[i];
            if (hook->owner == cls && hook->sel == sel) return hook;
        }
    }
    return NULL;
}

static void HFABuiltinDispatchVoid1(id self, SEL _cmd, id argument) {
    HFABuiltinDispatchHook *hook =
        HFABuiltinDispatchHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->chainOriginal) return;

    const char *identifier = HFAObjectString(argument);
    if (!identifier || !*identifier || !HFAIdentifierIsCustomSwitch(identifier)) {
        ((void(*)(id,SEL,id))hook->chainOriginal)(self, _cmd, argument);
        return;
    }

    uintptr_t caller = HFAStripCodePointer((uintptr_t)__builtin_return_address(0));
    Dl_info callerInfo = {0};
    dladdr((void *)caller, &callerInfo);
    uintptr_t callerRVA = callerInfo.dli_fbase
        ? caller - (uintptr_t)callerInfo.dli_fbase : 0;

    unsigned outer = gBuiltinDispatchDepth++;
    if (outer == 0) {
        gBuiltinDispatchEvent = gEvent;
        snprintf(gBuiltinDispatchIdentifier, sizeof(gBuiltinDispatchIdentifier),
                 "%s", identifier);
    }

    HFALog("[CUSTOM-BUILTIN-DISPATCH] phase=begin event=%u identifier=%s class=%s selector=%s image=%s rva=%llX self=%p arg=%p callerImage=%s callerRVA=%llX depth=%u\n",
           gEvent, identifier, HFAObjectClassName(self), sel_getName(_cmd),
           hook->image, (unsigned long long)hook->rva, self, argument,
           callerInfo.dli_fname ? HFABase(callerInfo.dli_fname) : "?",
           (unsigned long long)callerRVA, gBuiltinDispatchDepth);

    if (!hook->probed && hook->targetOriginal) {
        hook->probed = 1;
        HFAProbeCodePath("builtin", identifier,
                         (uintptr_t)hook->targetOriginal, 0, 0x1400u);
    }

    ((void(*)(id,SEL,id))hook->chainOriginal)(self, _cmd, argument);

    HFALog("[CUSTOM-BUILTIN-DISPATCH] phase=end event=%u identifier=%s class=%s selector=%s image=%s rva=%llX self=%p arg=%p depth=%u\n",
           gEvent, identifier, HFAObjectClassName(self), sel_getName(_cmd),
           hook->image, (unsigned long long)hook->rva, self, argument,
           gBuiltinDispatchDepth);

    if (gBuiltinDispatchDepth && --gBuiltinDispatchDepth == 0) {
        gBuiltinDispatchEvent = 0;
        gBuiltinDispatchIdentifier[0] = 0;
    }
}

static unsigned HFAInstallBuiltinDispatchHooks(Class owner, const char *image) {
    if (!owner || !image || !*image) return 0;
    unsigned methodCount = 0, candidates = 0, installed = 0;
    Method *methods = class_copyMethodList(owner, &methodCount);
    for (unsigned i = 0; methods && i < methodCount &&
         gBuiltinDispatchHookCount < 128; i++) {
        Method method = methods[i];
        if (method_getNumberOfArguments(method) != 3) continue;

        char ret[32] = {0}, arg[32] = {0};
        method_getReturnType(method, ret, sizeof(ret));
        method_getArgumentType(method, 2, arg, sizeof(arg));
        const char *r = ret;
        const char *a = arg;
        while (*r && strchr("rnNoORV", *r)) r++;
        while (*a && strchr("rnNoORV", *a)) a++;
        if (*r != 'v' || *a != '@') continue;

        SEL sel = method_getName(method);
        if (!sel || HFAActionRuntimeHookFor(owner, sel) ||
            HFABuiltinDispatchHookFor(owner, sel))
            continue;

        IMP current = method_getImplementation(method);
        if (!current) continue;

        // HFAInstallActionFlowMethods may already have wrapped this method.
        // Preserve that wrapper as the chain target, while using the underlying
        // real IMP for image/RVA reporting and static code probing.
        IMP target = current;
        HFAActionFlowHook *flow = HFAActionFlowHookFor(owner, sel);
        if (flow && flow->original) target = flow->original;

        Dl_info info = {0};
        if (!target || !dladdr((void *)target, &info) ||
            !info.dli_fname || !info.dli_fbase)
            continue;
        if (strcmp(HFABase(info.dli_fname), image) != 0) continue;
        candidates++;

        HFABuiltinDispatchHook *hook =
            &gBuiltinDispatchHooks[gBuiltinDispatchHookCount++];
        memset(hook, 0, sizeof(*hook));
        hook->owner = owner;
        hook->sel = sel;
        hook->chainOriginal = current;
        hook->targetOriginal = target;
        hook->rva = (uintptr_t)target - (uintptr_t)info.dli_fbase;
        snprintf(hook->image, sizeof(hook->image), "%s", image);

        method_setImplementation(method, (IMP)HFABuiltinDispatchVoid1);
        installed++;
        HFALog("[CUSTOM-BUILTIN-HOOK] class=%s selector=%s image=%s rva=%llX installed=1\n",
               class_getName(owner), sel_getName(sel), image,
               (unsigned long long)hook->rva);
    }
    free(methods);
    HFALog("[CUSTOM-BUILTIN-SCAN] class=%s image=%s candidates=%u installed=%u\n",
           class_getName(owner), image, candidates, installed);
    return installed;
}
'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected object-string helper once, found {s.count(anchor)}")
s = s.replace(anchor, insert, 1)

# Allow the existing lightweight flow wrappers to keep tracing when the built-in
# dispatcher runs outside the UI action wrapper. This keeps the old marker for
# backwards compatibility, but uses the builtin event/identifier when needed.
old = r'''    if (!gCustomActionDepth || !gActiveCustomIdentifier[0]) return;
    Dl_info callerInfo = {0};
'''
new = r'''    const char *flowIdentifier = NULL;
    unsigned flowEvent = 0;
    if (gCustomActionDepth && gActiveCustomIdentifier[0]) {
        flowIdentifier = gActiveCustomIdentifier;
        flowEvent = gCustomActionEvent;
    } else if (gBuiltinDispatchDepth && gBuiltinDispatchIdentifier[0]) {
        flowIdentifier = gBuiltinDispatchIdentifier;
        flowEvent = gBuiltinDispatchEvent;
    } else {
        return;
    }
    Dl_info callerInfo = {0};
'''
if s.count(old) != 1:
    raise SystemExit(f"expected action-flow guard once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''           phase, gCustomActionEvent, gActiveCustomIdentifier,
'''
new = r'''           phase, flowEvent, flowIdentifier,
'''
if s.count(old) != 1:
    raise SystemExit(f"expected action-flow identifier args once, found {s.count(old)}")
s = s.replace(old, new, 1)

# Install the builtin dispatcher hooks only after the action-runtime hook has
# installed its lightweight flow wrappers, so our chain preserves both layers.
old = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
    }
'''
new = r'''    if (HFACurrentFeatureIsCustomSwitch()) {
        HFAInstallDynamicApplyHooksForImage(image);
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
        HFAInstallBuiltinDispatchHooks(cls, image);
    }
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.5 custom action body once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.5 CustomDynamicApplyProbe] loaded'
new_marker = '[HFALearn v1.9.6 CustomSwitchBuiltinDispatchProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.5 patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)

patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.5 CustomDynamicApplyProbe] loaded'
new_marker = '[HFALearn UI v1.9.6 CustomSwitchBuiltinDispatchProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.5 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
