from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# Registration-hook state. v1.9.4 discovers customSwitch registration methods by
# Objective-C signature instead of hardcoding the obfuscated selector or k1.
anchor = "static char gActiveCustomIdentifier[96];\n"
insert = r'''static char gActiveCustomIdentifier[96];

typedef struct {
    Class owner;
    SEL sel;
    IMP original;
} HFADynamicRegistrationHook;

typedef struct {
    Class owner;
    SEL sel;
    id block;
    char arg1[256];
    char arg2[256];
    char arg3[256];
    char invokeImage[256];
    uintptr_t invokeRVA;
    unsigned resolved;
} HFADynamicRegistrationCandidate;

static HFADynamicRegistrationHook gDynamicRegistrationHooks[128];
static unsigned gDynamicRegistrationHookCount;
static HFADynamicRegistrationCandidate gDynamicRegistrationCandidates[128];
static unsigned gDynamicRegistrationCandidateCount;
static void HFAResolveDynamicRegistrationCandidates(const char *identifier,
                                                    const char *type);
'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected v1.9.3 runtime global anchor once, found {s.count(anchor)}")
s = s.replace(anchor, insert, 1)

# Resolve a previously observed registration candidate as soon as its feature type
# is learned from the menu schema. The copied block is the same heap block passed
# onward to the menu, so the existing block-invoke hook can observe the real call.
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
new = r'''void HFARegisterFeatureType(const char *identifier, const char *type) {
    if (!identifier || !*identifier || !type || !*type) return;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        if (strcmp(definition->identifier, identifier) != 0) continue;
        snprintf(definition->type, sizeof(definition->type), "%s", type);
        HFAResolveDynamicRegistrationCandidates(identifier, type);
        return;
    }
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected feature-type function once, found {s.count(old)}")
s = s.replace(old, new, 1)

# Add a dedicated customSwitch marker on top of the generic block hook. For the
# discovered callback ABI, a1 is the BOOL enabled state.
old = r'''    HFALog("[CUSTOM-INVOKE] phase=begin event=%u identifier=%s block=%p image=%s invokeRVA=%llX args=%llX/%llX/%llX/%llX/%llX/%llX\n",
           gEvent, hook->identifier, block, hook->image,
           (unsigned long long)hook->rva,
           (unsigned long long)a1, (unsigned long long)a2,
           (unsigned long long)a3, (unsigned long long)a4,
           (unsigned long long)a5, (unsigned long long)a6);
    uintptr_t result = hook->original(block, a1, a2, a3, a4, a5, a6);
'''
new = r'''    HFALog("[CUSTOM-INVOKE] phase=begin event=%u identifier=%s block=%p image=%s invokeRVA=%llX args=%llX/%llX/%llX/%llX/%llX/%llX\n",
           gEvent, hook->identifier, block, hook->image,
           (unsigned long long)hook->rva,
           (unsigned long long)a1, (unsigned long long)a2,
           (unsigned long long)a3, (unsigned long long)a4,
           (unsigned long long)a5, (unsigned long long)a6);
    HFAFeatureDefinition *dynamicDefinition =
        HFAFeatureDefinitionForIdentifier(hook->identifier);
    if (dynamicDefinition && dynamicDefinition->type[0] &&
        strcmp(dynamicDefinition->type, "customSwitch") == 0) {
        HFALog("[CUSTOM-DYNAMIC-INVOKE] phase=begin event=%u identifier=%s block=%p image=%s invokeRVA=%llX state=%llu\n",
               gEvent, hook->identifier, block, hook->image,
               (unsigned long long)hook->rva,
               (unsigned long long)(a1 & 1u));
    }
    uintptr_t result = hook->original(block, a1, a2, a3, a4, a5, a6);
'''
if s.count(old) != 1:
    raise SystemExit(f"expected custom block begin once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''    HFALog("[CUSTOM-INVOKE] phase=end event=%u identifier=%s block=%p image=%s invokeRVA=%llX result=%llX\n",
           gEvent, hook->identifier, block, hook->image,
           (unsigned long long)hook->rva, (unsigned long long)result);
    return result;
}
'''
new = r'''    HFALog("[CUSTOM-INVOKE] phase=end event=%u identifier=%s block=%p image=%s invokeRVA=%llX result=%llX\n",
           gEvent, hook->identifier, block, hook->image,
           (unsigned long long)hook->rva, (unsigned long long)result);
    if (dynamicDefinition && dynamicDefinition->type[0] &&
        strcmp(dynamicDefinition->type, "customSwitch") == 0) {
        HFALog("[CUSTOM-DYNAMIC-INVOKE] phase=end event=%u identifier=%s block=%p image=%s invokeRVA=%llX state=%llu\n",
               gEvent, hook->identifier, block, hook->image,
               (unsigned long long)hook->rva,
               (unsigned long long)(a1 & 1u));
    }
    return result;
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected custom block end once, found {s.count(old)}")
s = s.replace(old, new, 1)

# Insert generic registration discovery after the v1.9.3 object-string helper.
anchor = r'''static const char *HFAObjectString(id value) {
    if (!value) return NULL;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value UTF8String];
    return NULL;
}
'''
helper = anchor + r'''

static const char *HFASkipObjCTypeQualifiers(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static HFADynamicRegistrationHook *HFADynamicRegistrationHookFor(Class owner,
                                                                  SEL sel) {
    for (Class cls = owner; cls; cls = class_getSuperclass(cls)) {
        for (unsigned i = 0; i < gDynamicRegistrationHookCount; i++) {
            HFADynamicRegistrationHook *hook = &gDynamicRegistrationHooks[i];
            if (hook->owner == cls && hook->sel == sel) return hook;
        }
    }
    return NULL;
}

static void HFACopyNSString(char *out, size_t cap, id value) {
    if (!out || !cap) return;
    out[0] = 0;
    const char *text = HFAObjectString(value);
    if (text && *text) snprintf(out, cap, "%s", text);
}

static int HFADynamicCandidateMatches(HFADynamicRegistrationCandidate *candidate,
                                      const char *identifier) {
    if (!candidate || !identifier || !*identifier) return 0;
    return (candidate->arg1[0] && strcmp(candidate->arg1, identifier) == 0) ||
           (candidate->arg2[0] && strcmp(candidate->arg2, identifier) == 0) ||
           (candidate->arg3[0] && strcmp(candidate->arg3, identifier) == 0);
}

static void HFAResolveDynamicRegistrationCandidates(const char *identifier,
                                                    const char *type) {
    if (!identifier || !*identifier || !type || strcmp(type, "customSwitch") != 0)
        return;
    for (unsigned i = 0; i < gDynamicRegistrationCandidateCount; i++) {
        HFADynamicRegistrationCandidate *candidate =
            &gDynamicRegistrationCandidates[i];
        if (candidate->resolved || !candidate->block ||
            !HFADynamicCandidateMatches(candidate, identifier))
            continue;
        candidate->resolved = 1;
        HFALog("[CUSTOM-DYNAMIC-RESOLVE] identifier=%s class=%s selector=%s block=%p invokeImage=%s invokeRVA=%llX args=%s/%s/%s\n",
               identifier,
               candidate->owner ? class_getName(candidate->owner) : "?",
               candidate->sel ? sel_getName(candidate->sel) : "?",
               candidate->block,
               candidate->invokeImage[0] ? candidate->invokeImage : "?",
               (unsigned long long)candidate->invokeRVA,
               candidate->arg1[0] ? candidate->arg1 : "?",
               candidate->arg2[0] ? candidate->arg2 : "?",
               candidate->arg3[0] ? candidate->arg3 : "?");
        HFARegisterCustomBlock(candidate->block, identifier);
    }
}

static void HFARecordDynamicRegistration(Class owner, SEL sel,
                                         id a1, id a2, id a3, id block) {
    if (!owner || !sel || !block ||
        gDynamicRegistrationCandidateCount >= 128) return;
    const char *blockClass = HFAObjectClassName(block);
    if (!blockClass || !strstr(blockClass, "Block")) return;

    HFABlockLiteral *literal = (HFABlockLiteral *)block;
    if (!HFAReadable((uintptr_t)literal, sizeof(*literal)) || !literal->invoke)
        return;
    uintptr_t invoke = HFAStripCodePointer((uintptr_t)literal->invoke);
    Dl_info invokeInfo = {0};
    if (!invoke || !dladdr((void *)invoke, &invokeInfo) || !invokeInfo.dli_fbase)
        return;

    HFADynamicRegistrationCandidate *candidate =
        &gDynamicRegistrationCandidates[gDynamicRegistrationCandidateCount++];
    memset(candidate, 0, sizeof(*candidate));
    candidate->owner = owner;
    candidate->sel = sel;
    candidate->block = block;
    candidate->invokeRVA = invoke - (uintptr_t)invokeInfo.dli_fbase;
    snprintf(candidate->invokeImage, sizeof(candidate->invokeImage), "%s",
             invokeInfo.dli_fname ? HFABase(invokeInfo.dli_fname) : "?");
    HFACopyNSString(candidate->arg1, sizeof(candidate->arg1), a1);
    HFACopyNSString(candidate->arg2, sizeof(candidate->arg2), a2);
    HFACopyNSString(candidate->arg3, sizeof(candidate->arg3), a3);

    Dl_info methodInfo = {0};
    HFADynamicRegistrationHook *hook = HFADynamicRegistrationHookFor(owner, sel);
    if (hook && hook->original) dladdr((void *)hook->original, &methodInfo);
    uintptr_t methodRVA = methodInfo.dli_fbase && hook
        ? (uintptr_t)hook->original - (uintptr_t)methodInfo.dli_fbase : 0;
    HFALog("[CUSTOM-DYNAMIC-REGISTER] class=%s selector=%s methodImage=%s methodRVA=%llX block=%p blockClass=%s invokeImage=%s invokeRVA=%llX args=%s/%s/%s\n",
           class_getName(owner), sel_getName(sel),
           methodInfo.dli_fname ? HFABase(methodInfo.dli_fname) : "?",
           (unsigned long long)methodRVA,
           block, blockClass, candidate->invokeImage,
           (unsigned long long)candidate->invokeRVA,
           candidate->arg1[0] ? candidate->arg1 : "?",
           candidate->arg2[0] ? candidate->arg2 : "?",
           candidate->arg3[0] ? candidate->arg3 : "?");

    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        if (definition->type[0] &&
            strcmp(definition->type, "customSwitch") == 0 &&
            HFADynamicCandidateMatches(candidate, definition->identifier)) {
            HFAResolveDynamicRegistrationCandidates(definition->identifier,
                                                    definition->type);
            break;
        }
    }
}

static void HFADynamicRegistration4(id self, SEL _cmd,
                                    id a1, id a2, id a3, id block) {
    HFADynamicRegistrationHook *hook =
        HFADynamicRegistrationHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;

    id effectiveBlock = block;
    if (block) {
        const char *blockClass = HFAObjectClassName(block);
        if (blockClass && strstr(blockClass, "Block")) {
            // Intentionally retain the heap block for the lifetime of this
            // diagnostic dylib. The same object is passed into the menu so the
            // later invoke-slot hook observes the actual callback.
            id copied = [block copy];
            if (copied) effectiveBlock = copied;
            HFARecordDynamicRegistration(hook->owner, _cmd,
                                         a1, a2, a3, effectiveBlock);
        }
    }
    ((void(*)(id,SEL,id,id,id,id))hook->original)(self, _cmd,
                                                  a1, a2, a3, effectiveBlock);
}

static unsigned HFAInstallDynamicRegistrationHooks(void) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return 0;
    Class *classes = (Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return 0;
    classCount = objc_getClassList(classes, classCount);
    unsigned candidates = 0, installed = 0;

    for (int ci = 0; ci < classCount && gDynamicRegistrationHookCount < 128; ci++) {
        Class cls = classes[ci];
        if (!cls) continue;
        unsigned methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned mi = 0; methods && mi < methodCount &&
             gDynamicRegistrationHookCount < 128; mi++) {
            Method method = methods[mi];
            if (method_getNumberOfArguments(method) != 6) continue;
            char ret[32] = {0}, a1[32] = {0}, a2[32] = {0},
                 a3[32] = {0}, a4[32] = {0};
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
            if (*r != 'v' || *t1 != '@' || *t2 != '@' || *t3 != '@' ||
                t4[0] != '@' || t4[1] != '?')
                continue;

            IMP original = method_getImplementation(method);
            Dl_info info = {0};
            if (!original || !dladdr((void *)original, &info) || !info.dli_fname)
                continue;
            const char *path = info.dli_fname;
            if (strstr(path, "/System/Library/") || strstr(path, "/usr/lib/") ||
                strstr(path, "HFAMapUniversal"))
                continue;
            candidates++;

            SEL sel = method_getName(method);
            if (!sel || HFADynamicRegistrationHookFor(cls, sel)) continue;
            HFADynamicRegistrationHook *hook =
                &gDynamicRegistrationHooks[gDynamicRegistrationHookCount++];
            hook->owner = cls;
            hook->sel = sel;
            hook->original = original;
            method_setImplementation(method, (IMP)HFADynamicRegistration4);
            installed++;
            uintptr_t rva = info.dli_fbase
                ? (uintptr_t)original - (uintptr_t)info.dli_fbase : 0;
            HFALog("[CUSTOM-DYNAMIC-HOOK] class=%s selector=%s image=%s rva=%llX installed=1\n",
                   class_getName(cls), sel_getName(sel), HFABase(path),
                   (unsigned long long)rva);
        }
        free(methods);
    }
    free(classes);
    HFALog("[CUSTOM-DYNAMIC-SCAN] classes=%d candidates=%u installed=%u\n",
           classCount, candidates, installed);
    return installed;
}
'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected v1.9.3 object-string helper once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

# The action selector is shared by custom and ordinary features. Only enter the
# runtime flow window when the current event itself is a customSwitch.
old = r'''static void HFAActionRuntimeEnter(HFAActionRuntimeHook *hook, id self, id sender) {
    if (!hook) return;
    if (gCustomActionDepth++ == 0) {
        gCustomActionEvent = gEvent;
        snprintf(gActiveCustomIdentifier, sizeof(gActiveCustomIdentifier), "%s",
                 hook->identifier);
    }
    HFALog("[CUSTOM-ACTION-RUNTIME] phase=begin event=%u identifier=%s class=%s selector=%s actionImage=%s actionRVA=%llX self=%p sender=%p senderClass=%s depth=%u\n",
           gEvent, hook->identifier, HFAObjectClassName(self),
           sel_getName(hook->sel), hook->image,
           (unsigned long long)hook->rva, self, sender,
           HFAObjectClassName(sender), gCustomActionDepth);
}
'''
new = r'''static void HFAActionRuntimeEnter(HFAActionRuntimeHook *hook, id self, id sender) {
    if (!hook) return;
    if (gCustomActionDepth++ == 0) {
        gCustomActionEvent = gEvent;
        snprintf(gActiveCustomIdentifier, sizeof(gActiveCustomIdentifier), "%s",
                 gIdentifier);
    }
    HFALog("[CUSTOM-ACTION-RUNTIME] phase=begin event=%u identifier=%s class=%s selector=%s actionImage=%s actionRVA=%llX self=%p sender=%p senderClass=%s depth=%u\n",
           gEvent, gActiveCustomIdentifier, HFAObjectClassName(self),
           sel_getName(hook->sel), hook->image,
           (unsigned long long)hook->rva, self, sender,
           HFAObjectClassName(sender), gCustomActionDepth);
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected action enter once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''    HFALog("[CUSTOM-ACTION-RUNTIME] phase=end event=%u identifier=%s class=%s selector=%s self=%p sender=%p depth=%u\n",
           gEvent, hook->identifier, HFAObjectClassName(self),
           sel_getName(hook->sel), self, sender, gCustomActionDepth);
'''
new = r'''    HFALog("[CUSTOM-ACTION-RUNTIME] phase=end event=%u identifier=%s class=%s selector=%s self=%p sender=%p depth=%u\n",
           gEvent, gActiveCustomIdentifier, HFAObjectClassName(self),
           sel_getName(hook->sel), self, sender, gCustomActionDepth);
'''
if s.count(old) != 1:
    raise SystemExit(f"expected action leave log once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''static void HFAActionRuntime0(id self, SEL _cmd) {
    HFAActionRuntimeHook *hook = HFAActionRuntimeHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;
    HFAActionRuntimeEnter(hook, self, nil);
    ((void(*)(id,SEL))hook->original)(self, _cmd);
    HFAActionRuntimeLeave(hook, self, nil);
}

static void HFAActionRuntime1(id self, SEL _cmd, id sender) {
    HFAActionRuntimeHook *hook = HFAActionRuntimeHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;
    HFAActionRuntimeEnter(hook, self, sender);
    ((void(*)(id,SEL,id))hook->original)(self, _cmd, sender);
    HFAActionRuntimeLeave(hook, self, sender);
}
'''
new = r'''static void HFAActionRuntime0(id self, SEL _cmd) {
    HFAActionRuntimeHook *hook = HFAActionRuntimeHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;
    if (!gIdentifier[0] || !HFAIdentifierIsCustomSwitch(gIdentifier)) {
        ((void(*)(id,SEL))hook->original)(self, _cmd);
        return;
    }
    HFAActionRuntimeEnter(hook, self, nil);
    ((void(*)(id,SEL))hook->original)(self, _cmd);
    HFAActionRuntimeLeave(hook, self, nil);
}

static void HFAActionRuntime1(id self, SEL _cmd, id sender) {
    HFAActionRuntimeHook *hook = HFAActionRuntimeHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;
    if (!gIdentifier[0] || !HFAIdentifierIsCustomSwitch(gIdentifier)) {
        ((void(*)(id,SEL,id))hook->original)(self, _cmd, sender);
        return;
    }
    HFAActionRuntimeEnter(hook, self, sender);
    ((void(*)(id,SEL,id))hook->original)(self, _cmd, sender);
    HFAActionRuntimeLeave(hook, self, sender);
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected action wrappers once, found {s.count(old)}")
s = s.replace(old, new, 1)

# Install registration hooks from the constructor so registration-time blocks are
# captured before the user opens the HFAMap diagnostics UI.
old = r'''__attribute__((constructor)) static void HFAInit(void) {
    HFALog("[HFALearn v1.9.3 CustomSwitchActionRuntimeProbe] loaded\n");
}
'''
new = r'''__attribute__((constructor)) static void HFAInit(void) {
    HFALog("[HFALearn v1.9.4 CustomSwitchDynamicBlockProbe] loaded\n");
    HFAInstallDynamicRegistrationHooks();
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.3 constructor once, found {s.count(old)}")
s = s.replace(old, new, 1)

patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.3 CustomSwitchActionRuntimeProbe] loaded'
new_marker = '[HFALearn UI v1.9.4 CustomSwitchDynamicBlockProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.3 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
