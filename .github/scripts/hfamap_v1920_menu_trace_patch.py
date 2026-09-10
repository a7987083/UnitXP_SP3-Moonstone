from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

anchor = r'''static NSDictionary *HFAPortableRelocationPlan(HFANativeHookRegistration *r,
                                               NSArray *refs) {
'''
helper = r'''
typedef struct {
    Class owner;
    SEL sel;
    IMP original;
    unsigned returnKind;
} HFAMenuTraceHook;

static HFAMenuTraceHook gMenuTraceHooks[128];
static unsigned gMenuTraceHookCount;

static HFAMenuTraceHook *HFAMenuTraceHookFor(Class owner, SEL sel) {
    for (unsigned i = 0; i < gMenuTraceHookCount; i++) {
        HFAMenuTraceHook *hook = &gMenuTraceHooks[i];
        if (hook->owner == owner && hook->sel == sel) return hook;
    }
    return NULL;
}

static const char *HFAMenuTraceIdentifierForArgument(id argument,
                                                      char *scratch,
                                                      size_t scratchSize) {
    const char *text = HFAObjectString(argument);
    if (!text || !*text) return NULL;
    if (HFAIdentifierIsCustomSwitch(text)) return text;

    static const char suffix[] = "-switch";
    size_t length = strlen(text);
    size_t suffixLength = sizeof(suffix) - 1;
    if (length <= suffixLength ||
        strcmp(text + length - suffixLength, suffix) != 0 ||
        !scratch || scratchSize <= length - suffixLength)
        return NULL;
    size_t baseLength = length - suffixLength;
    memcpy(scratch, text, baseLength);
    scratch[baseLength] = 0;
    return HFAIdentifierIsCustomSwitch(scratch) ? scratch : NULL;
}

static void HFAMenuTraceDescribeCaller(uintptr_t caller,
                                       char *image, size_t imageSize,
                                       uintptr_t *rvaOut) {
    if (image && imageSize) image[0] = 0;
    if (rvaOut) *rvaOut = 0;
    caller = HFAStripCodePointer(caller);
    Dl_info info = {0};
    if (!caller || !dladdr((void *)caller, &info) || !info.dli_fbase) return;
    if (image && imageSize)
        snprintf(image, imageSize, "%s",
                 info.dli_fname ? HFABase(info.dli_fname) : "?");
    if (rvaOut) *rvaOut = caller - (uintptr_t)info.dli_fbase;
}

static id HFAMenuTraceObject1(id self, SEL _cmd, id argument) {
    HFAMenuTraceHook *hook = HFAMenuTraceHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return nil;
    char normalized[96] = {0};
    const char *identifier = HFAMenuTraceIdentifierForArgument(
        argument, normalized, sizeof(normalized));
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    id result = ((id(*)(id,SEL,id))hook->original)(self, _cmd, argument);
    if (identifier) {
        char callerImage[256] = {0};
        uintptr_t callerRVA = 0;
        HFAMenuTraceDescribeCaller(caller, callerImage, sizeof(callerImage),
                                   &callerRVA);
        const char *argText = HFAObjectString(argument);
        const char *resultText = HFAObjectString(result);
        long long resultNumber = [result isKindOfClass:[NSNumber class]] ?
            [(NSNumber *)result longLongValue] : 0;
        HFALog("[MENU-STATE-CALL] identifier=%s class=%s selector=%s return=object arg=%s result=%p resultClass=%s resultText=%s resultNumber=%lld callerImage=%s callerRVA=%llX\n",
               identifier, HFAObjectClassName(self), sel_getName(_cmd),
               argText ? argText : "?", result, HFAObjectClassName(result),
               resultText ? resultText : "?", resultNumber,
               callerImage[0] ? callerImage : "?",
               (unsigned long long)callerRVA);
    }
    return result;
}

static uintptr_t HFAMenuTraceInteger1(id self, SEL _cmd, id argument) {
    HFAMenuTraceHook *hook = HFAMenuTraceHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return 0;
    char normalized[96] = {0};
    const char *identifier = HFAMenuTraceIdentifierForArgument(
        argument, normalized, sizeof(normalized));
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    uintptr_t result = ((uintptr_t(*)(id,SEL,id))hook->original)(self, _cmd,
                                                                 argument);
    if (identifier) {
        char callerImage[256] = {0};
        uintptr_t callerRVA = 0;
        HFAMenuTraceDescribeCaller(caller, callerImage, sizeof(callerImage),
                                   &callerRVA);
        const char *argText = HFAObjectString(argument);
        HFALog("[MENU-STATE-CALL] identifier=%s class=%s selector=%s return=integer arg=%s result=%llu resultHex=0x%llX callerImage=%s callerRVA=%llX\n",
               identifier, HFAObjectClassName(self), sel_getName(_cmd),
               argText ? argText : "?", (unsigned long long)result,
               (unsigned long long)result,
               callerImage[0] ? callerImage : "?",
               (unsigned long long)callerRVA);
    }
    return result;
}

static void HFAMenuTraceVoid1(id self, SEL _cmd, id argument) {
    HFAMenuTraceHook *hook = HFAMenuTraceHookFor(object_getClass(self), _cmd);
    if (!hook || !hook->original) return;
    char normalized[96] = {0};
    const char *identifier = HFAMenuTraceIdentifierForArgument(
        argument, normalized, sizeof(normalized));
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    if (identifier) {
        char callerImage[256] = {0};
        uintptr_t callerRVA = 0;
        HFAMenuTraceDescribeCaller(caller, callerImage, sizeof(callerImage),
                                   &callerRVA);
        const char *argText = HFAObjectString(argument);
        HFALog("[MENU-STATE-CALL] identifier=%s class=%s selector=%s return=void phase=begin arg=%s callerImage=%s callerRVA=%llX\n",
               identifier, HFAObjectClassName(self), sel_getName(_cmd),
               argText ? argText : "?",
               callerImage[0] ? callerImage : "?",
               (unsigned long long)callerRVA);
    }
    ((void(*)(id,SEL,id))hook->original)(self, _cmd, argument);
    if (identifier)
        HFALog("[MENU-STATE-CALL] identifier=%s class=%s selector=%s return=void phase=end\n",
               identifier, HFAObjectClassName(self), sel_getName(_cmd));
}

static unsigned HFAMenuTraceInstallSelector(Class owner, NSString *name,
                                             const char *identifier) {
    if (!owner || !name.length || gMenuTraceHookCount >= 128) return 0;
    SEL sel = sel_registerName(name.UTF8String);
    if (!sel || HFAMenuTraceHookFor(owner, sel)) return 0;
    Method method = class_getInstanceMethod(owner, sel);
    if (!method || method_getNumberOfArguments(method) != 3) return 0;

    char arg[32] = {0}, ret[32] = {0};
    method_getArgumentType(method, 2, arg, sizeof(arg));
    method_getReturnType(method, ret, sizeof(ret));
    const char *a = arg, *r = ret;
    while (*a && strchr("rnNoORV", *a)) a++;
    while (*r && strchr("rnNoORV", *r)) r++;
    if (*a != '@') return 0;

    IMP replacement = NULL;
    unsigned returnKind = 0;
    if (*r == '@' || *r == '#') {
        replacement = (IMP)HFAMenuTraceObject1;
        returnKind = 1;
    } else if (strchr("cCsSiIlLqQB^:*", *r)) {
        replacement = (IMP)HFAMenuTraceInteger1;
        returnKind = 2;
    } else if (*r == 'v') {
        replacement = (IMP)HFAMenuTraceVoid1;
        returnKind = 3;
    } else {
        return 0;
    }

    IMP current = method_getImplementation(method);
    if (!current || current == replacement) return 0;
    HFAMenuTraceHook *hook = &gMenuTraceHooks[gMenuTraceHookCount++];
    memset(hook, 0, sizeof(*hook));
    hook->owner = owner;
    hook->sel = sel;
    hook->original = current;
    hook->returnKind = returnKind;
    method_setImplementation(method, replacement);

    Dl_info info = {0};
    dladdr((void *)current, &info);
    uintptr_t rva = info.dli_fbase ?
        (uintptr_t)current - (uintptr_t)info.dli_fbase : 0;
    HFALog("[MENU-BEHAVIOR-HOOK] identifier=%s class=%s selector=%s returnKind=%u originalImage=%s originalRVA=%llX installed=1\n",
           identifier && *identifier ? identifier : "?",
           class_getName(owner), sel_getName(sel), returnKind,
           info.dli_fname ? HFABase(info.dli_fname) : "?",
           (unsigned long long)rva);
    return 1;
}

static unsigned HFAInstallMenuImplementationTrace(HFANativeHookRegistration *r,
                                                   NSArray *refs) {
    if (!r || !r->identifier[0] || !refs) return 0;

    NSString *ownerClassName = nil;
    for (NSDictionary *ref in refs) {
        if (![ref isKindOfClass:[NSDictionary class]] ||
            [[ref objectForKey:@"internal"] boolValue])
            continue;
        NSString *targetImage = [ref objectForKey:@"target"];
        NSString *targetOffset = [ref objectForKey:@"targetOffset"];
        NSString *section = [ref objectForKey:@"targetSection"];
        if (![targetImage isKindOfClass:[NSString class]] ||
            ![targetOffset isKindOfClass:[NSString class]] ||
            ![section isKindOfClass:[NSString class]])
            continue;
        if (![section isEqualToString:@"__common"] &&
            ![section isEqualToString:@"__bss"] &&
            ![section isEqualToString:@"__data"])
            continue;
        uintptr_t targetRVA =
            (uintptr_t)strtoull(targetOffset.UTF8String, NULL, 16);
        NSString *slotImage = r->slotImage[0] ?
            [NSString stringWithUTF8String:r->slotImage] : nil;
        BOOL originalSlot = targetRVA == r->slotRVA && slotImage.length &&
            [targetImage isEqualToString:slotImage];
        if (originalSlot) continue;
        NSDictionary *binding = HFAPortableResolveRuntimeGlobalBinding(
            targetImage.UTF8String, targetRVA, r->identifier);
        NSString *candidate = [binding objectForKey:@"class"];
        if ([candidate isKindOfClass:[NSString class]] && candidate.length) {
            ownerClassName = candidate;
            break;
        }
    }

    if (!ownerClassName.length) {
        HFALog("[MENU-BEHAVIOR-SCAN] identifier=%s status=NO_OWNER_CLASS\n",
               r->identifier);
        return 0;
    }
    Class owner = objc_getClass(ownerClassName.UTF8String);
    if (!owner) {
        HFALog("[MENU-BEHAVIOR-SCAN] identifier=%s ownerClass=%s status=CLASS_NOT_FOUND\n",
               r->identifier, ownerClassName.UTF8String);
        return 0;
    }

    unsigned selectorRefs = 0, installed = 0;
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *ref in refs) {
        if (![ref isKindOfClass:[NSDictionary class]]) continue;
        NSString *section = [ref objectForKey:@"targetSection"];
        NSString *targetImage = [ref objectForKey:@"target"];
        NSString *targetOffset = [ref objectForKey:@"targetOffset"];
        if (![section isEqualToString:@"__objc_selrefs"] ||
            ![targetImage isKindOfClass:[NSString class]] ||
            ![targetOffset isKindOfClass:[NSString class]])
            continue;
        uintptr_t targetRVA =
            (uintptr_t)strtoull(targetOffset.UTF8String, NULL, 16);
        NSString *name = HFAPortableSelectorName(targetImage.UTF8String,
                                                  targetRVA);
        if (!name.length || [seen containsObject:name]) continue;
        [seen addObject:name];
        selectorRefs++;
        installed += HFAMenuTraceInstallSelector(owner, name, r->identifier);
    }

    HFALog("[MENU-BEHAVIOR-SCAN] identifier=%s ownerClass=%s selectorRefs=%u installed=%u\n",
           r->identifier, ownerClassName.UTF8String, selectorRefs, installed);
    return installed;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected relocation plan anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
'''
new = r'''    unsigned menuTraceHooks = HFAInstallMenuImplementationTrace(r, refs);
    HFALog("[MENU-IMPLEMENTATION-TRACE] identifier=%s hooks=%u replacement=%s+0x%llX\n",
           r->identifier, menuTraceHooks, r->replacementImage,
           (unsigned long long)r->replacementRVA);
    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
'''
if s.count(old) != 1:
    raise SystemExit(f"expected capture semantic anchor once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
new_marker = '[HFALearn v1.9.20 MenuImplementationTrace] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.18 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
new_marker = '[HFALearn UI v1.9.20 MenuImplementationTrace] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.18 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
