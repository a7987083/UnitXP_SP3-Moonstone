from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# Runtime action/flow hook state. These hooks are installed only for the target
# class of a feature already identified as type=customSwitch.
anchor = "static unsigned gPathProbeSiteCount;\n"
insert = r'''static unsigned gPathProbeSiteCount;

typedef struct {
    Class owner;
    SEL sel;
    IMP original;
    unsigned argc;
    char identifier[96];
    char image[256];
    uintptr_t rva;
} HFAActionRuntimeHook;

typedef struct {
    Class owner;
    SEL sel;
    IMP original;
    unsigned kind;
} HFAActionFlowHook;

static HFAActionRuntimeHook gActionRuntimeHooks[32];
static unsigned gActionRuntimeHookCount;
static HFAActionFlowHook gActionFlowHooks[256];
static unsigned gActionFlowHookCount;
static unsigned gCustomActionDepth;
static unsigned gCustomActionEvent;
static char gActiveCustomIdentifier[96];
'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected path-probe global anchor once, found {s.count(anchor)}")
s = s.replace(anchor, insert, 1)

# Insert the runtime action wrapper and lightweight object-flow hooks immediately
# after the customSwitch type helper added by v1.9.2.
anchor = r'''static int HFAIdentifierIsCustomSwitch(const char *identifier) {
    HFAFeatureDefinition *definition = HFAFeatureDefinitionForIdentifier(identifier);
    return definition && definition->type[0] &&
           strcmp(definition->type, "customSwitch") == 0;
}
'''
helper = anchor + r'''
static HFAActionRuntimeHook *HFAActionRuntimeHookFor(Class owner, SEL sel) {
    for (unsigned i = 0; i < gActionRuntimeHookCount; i++) {
        HFAActionRuntimeHook *hook = &gActionRuntimeHooks[i];
        if (hook->owner == owner && hook->sel == sel) return hook;
    }
    return NULL;
}

static HFAActionFlowHook *HFAActionFlowHookFor(Class owner, SEL sel) {
    for (unsigned i = 0; i < gActionFlowHookCount; i++) {
        HFAActionFlowHook *hook = &gActionFlowHooks[i];
        if (hook->owner == owner && hook->sel == sel) return hook;
    }
    return NULL;
}

static const char *HFAObjectClassName(id value) {
    if (!value) return "(nil)";
    Class cls = object_getClass(value);
    return cls ? class_getName(cls) : "?";
}

static const char *HFAObjectString(id value) {
    if (!value) return NULL;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value UTF8String];
    return NULL;
}

static void HFALogActionFlow(const char *phase, const char *kind,
                             id self, SEL sel, id argument, id result,
                             uintptr_t caller) {
    if (!gCustomActionDepth || !gActiveCustomIdentifier[0]) return;
    Dl_info callerInfo = {0};
    dladdr((void *)caller, &callerInfo);
    uintptr_t callerRVA = callerInfo.dli_fbase
        ? caller - (uintptr_t)callerInfo.dli_fbase : 0;
    const char *argText = HFAObjectString(argument);
    const char *resultText = HFAObjectString(result);
    HFALog("[CUSTOM-ACTION-FLOW] phase=%s event=%u identifier=%s kind=%s class=%s selector=%s self=%p arg=%p argClass=%s argText=%s result=%p resultClass=%s resultText=%s callerImage=%s callerRVA=%llX\n",
           phase, gCustomActionEvent, gActiveCustomIdentifier,
           kind ? kind : "?", HFAObjectClassName(self),
           sel ? sel_getName(sel) : "?", self,
           argument, HFAObjectClassName(argument), argText ? argText : "?",
           result, HFAObjectClassName(result), resultText ? resultText : "?",
           callerInfo.dli_fname ? HFABase(callerInfo.dli_fname) : "?",
           (unsigned long long)callerRVA);
}

static id HFAActionFlowObject0(id self, SEL _cmd) {
    HFAActionFlowHook *hook = HFAActionFlowHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return nil;
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    id result = ((id(*)(id,SEL))hook->original)(self, _cmd);
    HFALogActionFlow("return", "object0", self, _cmd, nil, result, caller);
    return result;
}

static id HFAActionFlowObject1(id self, SEL _cmd, id argument) {
    HFAActionFlowHook *hook = HFAActionFlowHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return nil;
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    id result = ((id(*)(id,SEL,id))hook->original)(self, _cmd, argument);
    HFALogActionFlow("return", "object1", self, _cmd, argument, result, caller);
    return result;
}

static void HFAActionFlowVoid1(id self, SEL _cmd, id argument) {
    HFAActionFlowHook *hook = HFAActionFlowHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    HFALogActionFlow("enter", "void1", self, _cmd, argument, nil, caller);
    ((void(*)(id,SEL,id))hook->original)(self, _cmd, argument);
    HFALogActionFlow("leave", "void1", self, _cmd, argument, nil, caller);
}

static unsigned HFAInstallActionFlowMethods(Class owner) {
    if (!owner) return 0;
    unsigned methodCount = 0, installed = 0;
    Method *methods = class_copyMethodList(owner, &methodCount);
    for (unsigned i = 0; methods && i < methodCount && gActionFlowHookCount < 256; i++) {
        Method method = methods[i];
        SEL sel = method_getName(method);
        if (!sel || HFAActionRuntimeHookFor(owner, sel) || HFAActionFlowHookFor(owner, sel))
            continue;
        unsigned argc = method_getNumberOfArguments(method);
        if (argc != 2 && argc != 3) continue;

        char returnType[32] = {0}, argumentType[32] = {0};
        method_getReturnType(method, returnType, sizeof(returnType));
        const char *r = returnType;
        while (*r && strchr("rnNoORV", *r)) r++;
        if (argc == 3) {
            method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
            const char *a = argumentType;
            while (*a && strchr("rnNoORV", *a)) a++;
            if (*a != '@') continue;
        }

        IMP replacement = NULL;
        unsigned kind = 0;
        if (*r == '@' && argc == 2) {
            replacement = (IMP)HFAActionFlowObject0; kind = 1;
        } else if (*r == '@' && argc == 3) {
            replacement = (IMP)HFAActionFlowObject1; kind = 2;
        } else if (*r == 'v' && argc == 3) {
            replacement = (IMP)HFAActionFlowVoid1; kind = 3;
        } else {
            continue;
        }

        IMP original = method_getImplementation(method);
        if (!original || original == replacement) continue;
        HFAActionFlowHook *hook = &gActionFlowHooks[gActionFlowHookCount++];
        hook->owner = owner;
        hook->sel = sel;
        hook->original = original;
        hook->kind = kind;
        method_setImplementation(method, replacement);
        installed++;
    }
    free(methods);
    return installed;
}

static void HFAActionRuntimeEnter(HFAActionRuntimeHook *hook, id self, id sender) {
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

static void HFAActionRuntimeLeave(HFAActionRuntimeHook *hook, id self, id sender) {
    if (!hook) return;
    HFALog("[CUSTOM-ACTION-RUNTIME] phase=end event=%u identifier=%s class=%s selector=%s self=%p sender=%p depth=%u\n",
           gEvent, hook->identifier, HFAObjectClassName(self),
           sel_getName(hook->sel), self, sender, gCustomActionDepth);
    if (gCustomActionDepth && --gCustomActionDepth == 0) {
        gActiveCustomIdentifier[0] = 0;
        gCustomActionEvent = 0;
    }
}

static void HFAActionRuntime0(id self, SEL _cmd) {
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

static void HFAInstallActionRuntimeHook(Class owner, SEL sel, IMP implementation,
                                        const char *image, uintptr_t rva) {
    if (!owner || !sel || !implementation || !gIdentifier[0] ||
        !HFACurrentFeatureIsCustomSwitch()) return;

    HFAActionRuntimeHook *existing = HFAActionRuntimeHookFor(owner, sel);
    if (existing) {
        snprintf(existing->identifier, sizeof(existing->identifier), "%s", gIdentifier);
        return;
    }
    if (gActionRuntimeHookCount >= 32) return;

    Method method = class_getInstanceMethod(owner, sel);
    if (!method) return;
    unsigned argc = method_getNumberOfArguments(method);
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char *r = returnType;
    while (*r && strchr("rnNoORV", *r)) r++;
    if (*r != 'v' || (argc != 2 && argc != 3)) {
        HFALog("[CUSTOM-ACTION-HOOK] identifier=%s class=%s selector=%s installed=0 reason=signature argc=%u return=%s\n",
               gIdentifier, class_getName(owner), sel_getName(sel), argc, returnType);
        return;
    }

    IMP replacement = argc == 2 ? (IMP)HFAActionRuntime0 : (IMP)HFAActionRuntime1;
    HFAActionRuntimeHook *hook = &gActionRuntimeHooks[gActionRuntimeHookCount];
    memset(hook, 0, sizeof(*hook));
    hook->owner = owner;
    hook->sel = sel;
    hook->original = implementation;
    hook->argc = argc;
    hook->rva = rva;
    snprintf(hook->identifier, sizeof(hook->identifier), "%s", gIdentifier);
    snprintf(hook->image, sizeof(hook->image), "%s", image ? image : "?");

    const char *types = method_getTypeEncoding(method);
    IMP replaced = class_replaceMethod(owner, sel, replacement, types);
    if (replaced) hook->original = replaced;
    gActionRuntimeHookCount++;

    unsigned flowInstalled = HFAInstallActionFlowMethods(owner);
    flowInstalled += HFAInstallActionFlowMethods(object_getClass(owner));
    HFALog("[CUSTOM-ACTION-HOOK] identifier=%s class=%s selector=%s installed=1 argc=%u original=%p actionImage=%s actionRVA=%llX flowMethods=%u\n",
           hook->identifier, class_getName(owner), sel_getName(sel), argc,
           hook->original, hook->image, (unsigned long long)hook->rva,
           flowInstalled);
}
'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected customSwitch helper once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

# Upgrade ObserveAction: if the action was already wrapped, analyze the original IMP;
# then install the runtime wrapper after the static action path is emitted.
old = r'''void HFAPatchTraceObserveAction(id target, SEL action) {
    if (!target || !action) return;
    Class cls = object_getClass(target);
    Method method = class_getInstanceMethod(cls, action);
    if (!method) return;
    IMP implementation = method_getImplementation(method);
    Dl_info info = {0};
    if (!implementation || !dladdr((void *)implementation, &info) ||
        !info.dli_fbase || !info.dli_fname) return;
    const char *image = HFABase(info.dli_fname);
    uintptr_t rva = (uintptr_t)implementation - (uintptr_t)info.dli_fbase;
    HFALog("[ACTION-IMP] event=%u targetClass=%s selector=%s image=%s rva=%llX\n",
           gEvent, class_getName(cls), sel_getName(action), image,
           (unsigned long long)rva);
    HFAInstallStateQueriesForImage(image);
    if (HFACurrentFeatureIsCustomSwitch())
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x600u);
}
'''
new = r'''void HFAPatchTraceObserveAction(id target, SEL action) {
    if (!target || !action) return;
    Class cls = object_getClass(target);
    Method method = class_getInstanceMethod(cls, action);
    if (!method) return;
    HFAActionRuntimeHook *existingAction = HFAActionRuntimeHookFor(cls, action);
    IMP implementation = existingAction ? existingAction->original
                                        : method_getImplementation(method);
    Dl_info info = {0};
    if (!implementation || !dladdr((void *)implementation, &info) ||
        !info.dli_fbase || !info.dli_fname) return;
    const char *image = HFABase(info.dli_fname);
    uintptr_t rva = (uintptr_t)implementation - (uintptr_t)info.dli_fbase;
    HFALog("[ACTION-IMP] event=%u targetClass=%s selector=%s image=%s rva=%llX\n",
           gEvent, class_getName(cls), sel_getName(action), image,
           (unsigned long long)rva);
    HFAInstallStateQueriesForImage(image);
    if (HFACurrentFeatureIsCustomSwitch()) {
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x1000u);
        HFAInstallActionRuntimeHook(cls, action, implementation, image, rva);
    }
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.2 ObserveAction once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.2 CustomSwitchActionPathProbe] loaded'
new_marker = '[HFALearn v1.9.3 CustomSwitchActionRuntimeProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.2 patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()

# Crucial ordering fix: identifier must be armed before ObserveAction, otherwise
# HFACurrentFeatureIsCustomSwitch() is false when the action IMP is inspected.
old = 'HFAPatchTraceBeginEvent(ev);HFAPatchTraceObserveAction(target,action);const char*ident=objtext(self,"identifier");if(ident&&*ident)HFAPatchTraceSetIdentifier(ident);'
new = 'HFAPatchTraceBeginEvent(ev);const char*ident=objtext(self,"identifier");if(ident&&*ident)HFAPatchTraceSetIdentifier(ident);'
if l.count(old) != 1:
    raise SystemExit(f"expected old hooksend ordering once, found {l.count(old)}")
l = l.replace(old, new, 1)

old = 'if(target&&target!=self)dump_own(target,"TARGET",0);logf("[EVENT-END %u]\\n",ev);HFAPatchTraceArm(ev);'
new = 'if(target&&target!=self)dump_own(target,"TARGET",0);logf("[EVENT-END %u]\\n",ev);HFAPatchTraceArm(ev);HFAPatchTraceObserveAction(target,action);'
if l.count(old) != 1:
    raise SystemExit(f"expected EVENT-END arm anchor once, found {l.count(old)}")
l = l.replace(old, new, 1)

old_marker = '[HFALearn UI v1.9.2 CustomSwitchActionPathProbe] loaded'
new_marker = '[HFALearn UI v1.9.3 CustomSwitchActionRuntimeProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.2 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
