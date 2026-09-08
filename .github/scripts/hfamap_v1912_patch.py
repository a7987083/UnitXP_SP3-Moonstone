from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.12: v1.9.11 attempted package-time native-hook recovery by scanning
# loaded images for menu fingerprint strings. SuperStarSMTOWN proves that those
# strings can be visible through runtime objects without living in the menu
# dylib's __cstring, so package prep saw scannedMenuImages=0 and exported before
# the first customSwitch action recovered the hook.
#
# Fix: use the descriptor source images already discovered by the stable scanner
# as the primary package-time native-hook recovery roots. These are the images
# that own the menu patch descriptors and therefore the strongest generic
# bootstrap candidates. Keep the fingerprint scan only as a fallback. No
# identifier, image name, selector or sample RVA is hardcoded.

old = r'''static void HFAPrepareNativeHooksForPackageExport(void) {
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
'''

new = r'''static void HFAPrepareNativeHooksForPackageExport(void) {
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
    if (!definition || !definition->identifier[0]) return;
    if (HFANativeRegistrationForIdentifier(definition->identifier)) {
        HFALog("[PACKAGE-NATIVEHOOK-PREP] customSwitches=%u descriptorImages=0 fingerprintImages=0 associated=1 source=existing\n",
               customCount);
        return;
    }

    // Primary route: stable scanner already knows which dylib owns every patch
    // descriptor. Scan each unique source image once. This does not assume that
    // customSwitch itself has a descriptor; it uses neighboring descriptor
    // ownership as a generic menu/bootstrap image identity.
    unsigned descriptorImages = 0;
    for (unsigned i = 0; i < gDescriptorCount; i++) {
        const char *image = gDescriptors[i].sourceImage;
        if (!image || !*image || strstr(image, "HFAMapUniversal")) continue;
        int duplicate = 0;
        for (unsigned j = 0; j < i; j++) {
            if (gDescriptors[j].sourceImage[0] &&
                strcmp(gDescriptors[j].sourceImage, image) == 0) {
                duplicate = 1;
                break;
            }
        }
        if (duplicate) continue;
        descriptorImages++;
        HFALog("[PACKAGE-NATIVEHOOK-SOURCE] identifier=%s source=descriptor image=%s\n",
               definition->identifier, image);
        HFARecoverStaticNativeHooksForImage(image, definition->identifier);
        if (HFANativeRegistrationForIdentifier(definition->identifier)) break;
    }

    // Fallback for menus with no neighboring descriptors: retain the v1.9.11
    // fingerprint route, but do not rescan descriptor source images.
    unsigned fingerprintImages = 0;
    if (!HFANativeRegistrationForIdentifier(definition->identifier)) {
        uint32_t imageCount = _dyld_image_count();
        for (uint32_t i = 0; i < imageCount; i++) {
            const struct mach_header *mh = _dyld_get_image_header(i);
            const char *path = _dyld_get_image_name(i);
            if (!mh || !path) continue;
            const char *image = HFABase(path);
            if (!image || !*image || strstr(image, "HFAMapUniversal")) continue;
            int descriptorSource = 0;
            for (unsigned j = 0; j < gDescriptorCount; j++) {
                if (gDescriptors[j].sourceImage[0] &&
                    strcmp(gDescriptors[j].sourceImage, image) == 0) {
                    descriptorSource = 1;
                    break;
                }
            }
            if (descriptorSource) continue;
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            if (!HFAImageHasMenuFingerprint(mh, slide)) continue;
            fingerprintImages++;
            HFALog("[PACKAGE-NATIVEHOOK-SOURCE] identifier=%s source=fingerprint image=%s\n",
                   definition->identifier, image);
            HFARecoverStaticNativeHooksForImage(image, definition->identifier);
            if (HFANativeRegistrationForIdentifier(definition->identifier)) break;
        }
    }

    HFALog("[PACKAGE-NATIVEHOOK-PREP] customSwitches=%u descriptorImages=%u fingerprintImages=%u associated=%u source=%s\n",
           customCount, descriptorImages, fingerprintImages,
           HFANativeRegistrationForIdentifier(definition->identifier) ? 1u : 0u,
           descriptorImages ? "descriptor" : (fingerprintImages ? "fingerprint" : "none"));
}
'''

if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.11 package prep once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.11 CustomSwitchNativeHookExport] loaded'
new_marker = '[HFALearn v1.9.12 NativeHookExportTimingFix] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.11 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.11 CustomSwitchNativeHookExport] loaded'
new_marker = '[HFALearn UI v1.9.12 NativeHookExportTimingFix] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.11 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
