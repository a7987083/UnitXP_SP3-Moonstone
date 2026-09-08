from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.11: export uniquely-associated customSwitch/nativeHook registrations into
# the existing com.hfa.patch/v1 package without changing the normal descriptor
# path. The native feature keeps patches=[] for backwards compatibility and adds
# a typed hook extension. No feature identifier, image name, selector, or RVA is
# hardcoded.
anchor = r'''unsigned HFAPatchTraceFinalizeScan(void) {
'''
helper = r'''
static HFANativeHookRegistration *HFANativeRegistrationForIdentifier(
    const char *identifier) {
    if (!identifier || !*identifier) return NULL;
    for (unsigned i = 0; i < gNativeHookRegistrationCount; i++) {
        HFANativeHookRegistration *r = &gNativeHookRegistrations[i];
        if (r->identifier[0] && strcmp(r->identifier, identifier) == 0)
            return r;
    }
    return NULL;
}

static unsigned HFACustomSwitchDefinitionCount(void) {
    unsigned count = 0;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        if (definition->type[0] &&
            strcmp(definition->type, "customSwitch") == 0)
            count++;
    }
    return count;
}

static void HFAPrepareNativeHooksForPackageExport(void) {
    unsigned customCount = HFACustomSwitchDefinitionCount();
    if (!customCount) return;

    // Existing runtime/static associations are always safe to keep. Automatic
    // static association is only attempted when there is exactly one unresolved
    // customSwitch; with multiple customSwitch definitions we refuse to guess.
    if (customCount != 1) {
        HFALog("[PACKAGE-NATIVEHOOK-PREP] customSwitches=%u mode=existing-only\n",
               customCount);
        return;
    }

    HFAFeatureDefinition *definition = NULL;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *candidate = &gFeatureDefinitions[i];
        if (candidate->type[0] &&
            strcmp(candidate->type, "customSwitch") == 0) {
            definition = candidate;
            break;
        }
    }
    if (!definition || !definition->identifier[0] ||
        HFANativeRegistrationForIdentifier(definition->identifier))
        return;

    uint32_t imageCount = _dyld_image_count();
    unsigned scanned = 0;
    for (uint32_t i = 0; i < imageCount; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        const char *path = _dyld_get_image_name(i);
        if (!mh || !path) continue;
        const char *image = HFABase(path);
        if (!image || !*image || strstr(image, "HFAMapUniversal")) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (!HFAImageHasMenuFingerprint(mh, slide)) continue;
        scanned++;
        HFARecoverStaticNativeHooksForImage(image, definition->identifier);
        if (HFANativeRegistrationForIdentifier(definition->identifier)) break;
    }

    HFALog("[PACKAGE-NATIVEHOOK-PREP] customSwitches=%u scannedMenuImages=%u associated=%u\n",
           customCount, scanned,
           HFANativeRegistrationForIdentifier(definition->identifier) ? 1u : 0u);
}

static NSString *HFAEnsureNativeExportTarget(NSMutableDictionary *targets,
                                             const char *imageName) {
    if (!targets || !imageName || !*imageName) return nil;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return nil;
    const char *loaded = HFABase(_dyld_get_image_name((uint32_t)imageIndex));
    NSString *targetID = imageIndex == 0 ? @"main" :
        [NSString stringWithUTF8String:(loaded && *loaded) ? loaded : imageName];
    NSString *image = imageIndex == 0 ? @"@main" : targetID;
    if (!targetID || !image) return nil;
    targets[targetID] = @{ @"image": image };
    return targetID;
}

static NSString *HFANativeOffsetString(uintptr_t rva) {
    return [NSString stringWithFormat:@"0x%08llX", (unsigned long long)rva];
}

static int HFAExportFeatureExists(NSArray *features, NSString *featureID) {
    if (!featureID.length) return 0;
    for (id value in features) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        id existing = [(NSDictionary *)value objectForKey:@"id"];
        if ([existing isKindOfClass:[NSString class]] &&
            [(NSString *)existing isEqualToString:featureID])
            return 1;
    }
    return 0;
}

static unsigned HFAAppendNativeHookPackageFeatures(NSMutableArray *features,
                                                    NSMutableDictionary *targets) {
    if (!features || !targets) return 0;
    unsigned exported = 0;

    for (unsigned i = 0; i < gNativeHookRegistrationCount; i++) {
        HFANativeHookRegistration *r = &gNativeHookRegistrations[i];
        if (!r->identifier[0]) continue;
        HFAFeatureDefinition *definition =
            HFAFeatureDefinitionForIdentifier(r->identifier);
        if (!definition || !definition->type[0] ||
            strcmp(definition->type, "customSwitch") != 0)
            continue;

        if (!r->targetImage[0] || r->targetCandidates != 1 || !r->targetRVA ||
            !r->replacementImage[0] || !r->replacementRVA ||
            !r->slotImage[0] || !r->slotRVA ||
            !r->originalImage[0] || !r->originalRVA) {
            HFALog("[PACKAGE-NATIVEHOOK-SKIP] identifier=%s reason=incomplete targetImage=%s targetRVA=%llX candidates=%u replacement=%s+%llX slot=%s+%llX original=%s+%llX\n",
                   r->identifier,
                   r->targetImage[0] ? r->targetImage : "?",
                   (unsigned long long)r->targetRVA, r->targetCandidates,
                   r->replacementImage[0] ? r->replacementImage : "?",
                   (unsigned long long)r->replacementRVA,
                   r->slotImage[0] ? r->slotImage : "?",
                   (unsigned long long)r->slotRVA,
                   r->originalImage[0] ? r->originalImage : "?",
                   (unsigned long long)r->originalRVA);
            continue;
        }

        NSString *featureID = [NSString stringWithUTF8String:r->identifier];
        NSString *title = [NSString stringWithUTF8String:
            definition->label[0] ? definition->label : r->identifier];
        if (!featureID || !title || HFAExportFeatureExists(features, featureID))
            continue;

        NSString *targetID = HFAEnsureNativeExportTarget(targets, r->targetImage);
        NSString *replacementID = HFAEnsureNativeExportTarget(targets, r->replacementImage);
        NSString *slotID = HFAEnsureNativeExportTarget(targets, r->slotImage);
        NSString *originalID = HFAEnsureNativeExportTarget(targets, r->originalImage);
        if (!targetID || !replacementID || !slotID || !originalID) {
            HFALog("[PACKAGE-NATIVEHOOK-SKIP] identifier=%s reason=target-identity-unavailable\n",
                   r->identifier);
            continue;
        }

        NSDictionary *hook = @{
            @"target": @{ @"target": targetID,
                           @"offset": HFANativeOffsetString(r->targetRVA) },
            @"replacement": @{ @"target": replacementID,
                                @"offset": HFANativeOffsetString(r->replacementRVA) },
            @"originalSlot": @{ @"target": slotID,
                                 @"offset": HFANativeOffsetString(r->slotRVA) },
            @"original": @{ @"target": originalID,
                             @"offset": HFANativeOffsetString(r->originalRVA) }
        };

        [features addObject:@{
            @"id": featureID,
            @"title": title,
            @"group": @"Imported",
            @"defaultEnabled": @NO,
            @"patches": @[],
            @"type": @"customSwitch",
            @"implementation": @"nativeHook",
            @"hook": hook
        }];
        exported++;
        HFALog("[PACKAGE-NATIVEHOOK-EXPORT] title=\"%s\" identifier=%s target=%s+0x%llX replacement=%s+0x%llX originalSlot=%s+0x%llX original=%s+0x%llX\n",
               definition->label[0] ? definition->label : r->identifier,
               r->identifier,
               r->targetImage, (unsigned long long)r->targetRVA,
               r->replacementImage, (unsigned long long)r->replacementRVA,
               r->slotImage, (unsigned long long)r->slotRVA,
               r->originalImage, (unsigned long long)r->originalRVA);
    }
    return exported;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected FinalizeScan anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''unsigned HFAPatchTraceFinalizeScan(void) {
    unsigned groups = 0, emitted = 0, validParts = 0;
    NSMutableArray *exportFeatures = [NSMutableArray array];
'''
new = r'''unsigned HFAPatchTraceFinalizeScan(void) {
    unsigned groups = 0, emitted = 0, validParts = 0;
    HFAPrepareNativeHooksForPackageExport();
    NSMutableArray *exportFeatures = [NSMutableArray array];
'''
if s.count(old) != 1:
    raise SystemExit(f"expected FinalizeScan prelude once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''    HFALog("[FULL-SCAN-END] groups=%u mappings=%u valid=%u unresolved=%u\n",
           groups, emitted, validParts, emitted - validParts);
    HFAWritePatchPackage(exportFeatures, exportTargets);
    return validParts;
}
'''
new = r'''    unsigned nativeHooks =
        HFAAppendNativeHookPackageFeatures(exportFeatures, exportTargets);
    HFALog("[FULL-SCAN-END] groups=%u mappings=%u valid=%u unresolved=%u nativeHooks=%u packageFeatures=%u\n",
           groups, emitted, validParts, emitted - validParts, nativeHooks,
           (unsigned)exportFeatures.count);
    HFAWritePatchPackage(exportFeatures, exportTargets);
    return validParts + nativeHooks;
}
'''
if s.count(old) != 1:
    raise SystemExit(f"expected FinalizeScan tail once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.10 NativeTargetResolveProbe] loaded'
new_marker = '[HFALearn v1.9.11 CustomSwitchNativeHookExport] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.10 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.10 NativeTargetResolveProbe] loaded'
new_marker = '[HFALearn UI v1.9.11 CustomSwitchNativeHookExport] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.10 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
