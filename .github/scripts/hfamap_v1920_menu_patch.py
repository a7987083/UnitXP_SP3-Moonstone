from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

anchor = r'''unsigned HFAPatchTraceFinalizeScan(void) {
'''
helper = r'''
static void HFALogMenuSemanticSummary(void) {
    HFALog("[MENU-SEMANTIC-BEGIN] features=%u descriptors=%u nativeHooks=%u stateSites=%u\n",
           gFeatureDefinitionCount, gDescriptorCount,
           gNativeHookRegistrationCount, gStateSiteCount);

    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        unsigned descriptorCount = 0;
        const char *descriptorImage = "?";
        const char *descriptorModule = "?";
        for (unsigned j = 0; j < gDescriptorCount; j++) {
            HFADescriptor *d = &gDescriptors[j];
            if (!d->key[0] || strcmp(d->key, definition->key) != 0) continue;
            descriptorCount++;
            if (d->sourceImage[0]) descriptorImage = d->sourceImage;
            if (d->module[0]) descriptorModule = d->module;
        }

        HFANativeHookRegistration *native =
            HFANativeRegistrationForIdentifier(definition->identifier);
        const char *implementation = native ? "nativeHook" :
            (descriptorCount ? "patchDescriptor" :
             ((definition->type[0] && strcmp(definition->type, "customSwitch") == 0)
                ? "customSwitch-unresolved" : "definition-only"));

        HFALog("[MENU-SEMANTIC-FEATURE] index=%u title=\"%s\" identifier=%s type=%s stateKey=%s implementation=%s descriptors=%u descriptorImage=%s descriptorModule=%s\n",
               i,
               definition->label[0] ? definition->label : "?",
               definition->identifier[0] ? definition->identifier : "?",
               definition->type[0] ? definition->type : "standard",
               definition->key[0] ? definition->key : "?",
               implementation, descriptorCount,
               descriptorImage, descriptorModule);

        if (native) {
            HFALog("[MENU-SEMANTIC-NATIVE] identifier=%s target=%s targetImage=%s targetRVA=0x%llX replacement=%s+0x%llX originalSlot=%s+0x%llX original=%s+0x%llX\n",
                   definition->identifier,
                   native->targetPlain[0] ? native->targetPlain : "?",
                   native->targetImage[0] ? native->targetImage : "?",
                   (unsigned long long)native->targetRVA,
                   native->replacementImage[0] ? native->replacementImage : "?",
                   (unsigned long long)native->replacementRVA,
                   native->slotImage[0] ? native->slotImage : "?",
                   (unsigned long long)native->slotRVA,
                   native->originalImage[0] ? native->originalImage : "?",
                   (unsigned long long)native->originalRVA);
        }
    }

    for (unsigned i = 0; i < gStateSiteCount; i++) {
        HFAStateSite *site = &gStateSites[i];
        if (!site->identifier[0]) continue;
        Dl_info callerInfo = {0};
        dladdr((void *)site->caller, &callerInfo);
        uintptr_t callerRVA = callerInfo.dli_fbase
            ? site->caller - (uintptr_t)callerInfo.dli_fbase : 0;
        HFALog("[MENU-SEMANTIC-STATE] identifier=%s calls=%u lastResult=%llu callerImage=%s callerRVA=0x%llX selector=%s\n",
               site->identifier, site->calls,
               (unsigned long long)site->lastResult,
               callerInfo.dli_fname ? HFABase(callerInfo.dli_fname) : "?",
               (unsigned long long)callerRVA,
               site->query ? sel_getName(site->query) : "?");
    }

    HFALog("[MENU-SEMANTIC-END] features=%u descriptors=%u nativeHooks=%u stateSites=%u\n",
           gFeatureDefinitionCount, gDescriptorCount,
           gNativeHookRegistrationCount, gStateSiteCount);
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected FinalizeScan anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    HFAPrepareNativeHooksForPackageExport();
    NSMutableArray *exportFeatures = [NSMutableArray array];
'''
new = r'''    HFAPrepareNativeHooksForPackageExport();
    HFALogMenuSemanticSummary();
    NSMutableArray *exportFeatures = [NSMutableArray array];
'''
if s.count(old) != 1:
    raise SystemExit(f"expected package prep prelude once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
new_marker = '[HFALearn v1.9.20 MenuSemanticSummary] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.18 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
new_marker = '[HFALearn UI v1.9.20 MenuSemanticSummary] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.18 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
