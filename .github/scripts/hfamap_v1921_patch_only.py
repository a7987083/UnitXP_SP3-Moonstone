from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()
l = legacy_path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)

# v1.9.21 goal:
# - patchDescriptor only
# - no Key2 live probe/hook
# - no customSwitch/nativeHook discovery or export
# - export JSON as soon as the existing automatic menu traversal finishes

# 1) Never enter Key2PathProbe. KeyId=2 descriptors remain unresolved and are
# intentionally excluded from export instead of risking a live hook/crash.
old = '''    if ((flags >> 24) == 2u)\n        HFAProbeKey2Path((uintptr_t)getter);\n'''
new = '''    if ((flags >> 24) == 2u)\n        HFALog("[PATCH-ONLY-KEY2-SKIP] field=%s image=%s getterRVA=%llX reason=disabled\\n",\n               label, HFABase(getterInfo.dli_fname),\n               (unsigned long long)getterRVA);\n'''
s = replace_once(s, old, new, "disable Key2PathProbe")

# 2) Feature-type discovery may still record customSwitch metadata, but must not
# resolve dynamic registration candidates or associate native hooks.
old = '''        snprintf(definition->type, sizeof(definition->type), "%s", type);\n        HFAResolveDynamicRegistrationCandidates(identifier, type);\n        if (strcmp(type, "customSwitch") == 0)\n            HFAAssociateNativeHookWithCustomSwitch(identifier);\n        return;\n'''
new = '''        snprintf(definition->type, sizeof(definition->type), "%s", type);\n        if (strcmp(type, "customSwitch") == 0)\n            HFALog("[PATCH-ONLY-CUSTOM-SKIP] identifier=%s stage=feature-type\\n", identifier);\n        return;\n'''
s = replace_once(s, old, new, "disable customSwitch association")

# 3) Disable every action-time customSwitch-only branch. Ordinary descriptor
# observation remains untouched.
needle = 'if (HFACurrentFeatureIsCustomSwitch()) {'
count = s.count(needle)
if count < 1:
    raise SystemExit("disable customSwitch action path: no branch found")
s = s.replace(needle, 'if (0 && HFACurrentFeatureIsCustomSwitch()) {')

# 4) Constructor must not install process-wide dynamic registration hooks or
# dyld native-hook scanners. This removes accidental FBSDK/OneSignal/etc hooks.
old = '''__attribute__((constructor)) static void HFAInit(void) {\n    HFALog("[HFALearn v1.9.20 MenuSemanticSummary] loaded\\n");\n    _dyld_register_func_for_add_image(HFANativeImageAdded);\n    HFAInstallDynamicRegistrationHooks();\n}\n'''
new = '''__attribute__((constructor)) static void HFAInit(void) {\n    HFALog("[HFALearn v1.9.21 PatchOnlyImmediateExport] loaded\\n");\n    HFALog("[PATCH-ONLY-MODE] key2=disabled customSwitch=disabled nativeHook=disabled export=immediate\\n");\n}\n'''
s = replace_once(s, old, new, "disable native/dynamic constructor hooks")

# 5) Finalization should not spend time preparing native hooks or semantic native
# summaries. It goes directly from descriptor scan to package construction.
old = '''    HFAPrepareNativeHooksForPackageExport();\n    HFALogMenuSemanticSummary();\n    NSMutableArray *exportFeatures = [NSMutableArray array];\n'''
new = '''    HFALog("[PATCH-ONLY-EXPORT-BEGIN] features=%u descriptors=%u\\n",\n           gFeatureDefinitionCount, gDescriptorCount);\n    NSMutableArray *exportFeatures = [NSMutableArray array];\n'''
s = replace_once(s, old, new, "remove native export preparation")

# 6) Even if a customSwitch happens to own descriptor-looking state, do not put
# it into the JSON. Only standard patchDescriptor features are exported.
old = '''        if (definition && exportPatches.count) {\n'''
new = '''        if (definition && exportPatches.count &&\n            (!definition->type[0] || strcmp(definition->type, "customSwitch") != 0)) {\n'''
s = replace_once(s, old, new, "filter export to ordinary descriptors")

# 7) Remove native-hook append from the package tail. Existing automatic menu
# traversal already calls HFAPatchTraceFinalizeScan() immediately after it finds
# the menu, so HFAWritePatchPackage() now becomes the immediate terminal action.
old = '''    unsigned nativeHooks =\n        HFAAppendNativeHookPackageFeatures(exportFeatures, exportTargets);\n    HFALog("[FULL-SCAN-END] groups=%u mappings=%u valid=%u unresolved=%u nativeHooks=%u packageFeatures=%u\\n",\n           groups, emitted, validParts, emitted - validParts, nativeHooks,\n           (unsigned)exportFeatures.count);\n    HFAWritePatchPackage(exportFeatures, exportTargets);\n    return validParts + nativeHooks;\n}\n'''
new = '''    HFALog("[FULL-SCAN-END] groups=%u mappings=%u valid=%u unresolved=%u packageFeatures=%u mode=patch-only\\n",\n           groups, emitted, validParts, emitted - validParts,\n           (unsigned)exportFeatures.count);\n    HFAWritePatchPackage(exportFeatures, exportTargets);\n    HFALog("[PATCH-ONLY-EXPORT-END] valid=%u packageFeatures=%u\\n",\n           validParts, (unsigned)exportFeatures.count);\n    return validParts;\n}\n'''
s = replace_once(s, old, new, "remove native package append")

# 8) During automatic menu traversal, do not hook callback blocks. They are only
# needed by customSwitch/nativeHook diagnostics, which v1.9.21 intentionally drops.
old = 'if(ident[0]&&strstr(vcn,"Block"))HFARegisterCustomBlock(v,ident);'
new = 'if(ident[0]&&strstr(vcn,"Block"))logf("        [PATCH-ONLY-BLOCK-SKIP] identifier=%s\\n",ident);'
l = replace_once(l, old, new, "disable menu block hooking")

# Version marker in the lightweight UI/logger.
old = '[HFALearn UI v1.9.20 MenuSemanticSummary] loaded'
new = '[HFALearn UI v1.9.21 PatchOnlyImmediateExport] loaded'
l = replace_once(l, old, new, "update UI marker")

patch_path.write_text(s)
legacy_path.write_text(l)
