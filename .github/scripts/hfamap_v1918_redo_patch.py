from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.18-redo: v1.9.16-redo proves every external reference is classifiable,
# but one runtimeGlobal still points back into the source implementation image.
# Resolve writable globals initialized from a zero-argument Objective-C factory
# call by scanning the source image generically:
#   classref -> x0, selref -> x1, BL objc_msgSend, optional retain call,
#   ADRP+STR result into the global.
# No sample-specific identifier, class, selector, image or RVA is hardcoded.

anchor = r'''static NSDictionary *HFAPortableRelocationPlan(HFANativeHookRegistration *r,
                                               NSArray *refs) {
'''
helper = r'''
static int HFAPortableDecodeUnsignedLDRX(uint32_t word,
                                        unsigned *rtOut,
                                        unsigned *rnOut,
                                        uintptr_t *immOut) {
    if ((word & 0xFFC00000u) != 0xF9400000u) return 0;
    if (rtOut) *rtOut = word & 31u;
    if (rnOut) *rnOut = (word >> 5) & 31u;
    if (immOut) *immOut = (uintptr_t)((word >> 10) & 0xFFFu) << 3;
    return 1;
}

static int HFAPortableDecodeUnsignedSTRX(uint32_t word,
                                        unsigned *rtOut,
                                        unsigned *rnOut,
                                        uintptr_t *immOut) {
    if ((word & 0xFFC00000u) != 0xF9000000u) return 0;
    if (rtOut) *rtOut = word & 31u;
    if (rnOut) *rnOut = (word >> 5) & 31u;
    if (immOut) *immOut = (uintptr_t)((word >> 10) & 0xFFFu) << 3;
    return 1;
}

static NSString *HFAPortableBranchImportSymbol(const char *imageName,
                                                uintptr_t pc,
                                                uint32_t word) {
    if (!imageName || !*imageName ||
        (word & 0xFC000000u) != 0x94000000u)
        return nil;
    int64_t displacement =
        HFAStaticSignExtend(((uint64_t)(word & 0x03FFFFFFu)) << 2, 28);
    uintptr_t targetAddress = (uintptr_t)((intptr_t)pc + displacement);
    char targetImage[256] = {0};
    uintptr_t targetRVA = 0;
    HFADescribePointer(targetAddress, targetImage, sizeof(targetImage),
                       &targetRVA);
    if (!targetImage[0] || !targetRVA) return nil;
    return HFAPortableSymbolForIndirectSection(targetImage, targetRVA);
}

static int HFAPortableFindObjCArgRef(const char *imageName,
                                     uintptr_t callPC,
                                     unsigned wantedRegister,
                                     uintptr_t *refRVAOut,
                                     NSString **semanticOut) {
    if (!imageName || !*imageName || !callPC) return 0;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return 0;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);

    const size_t maxBack = 0x30u;
    for (size_t back = 4; back <= maxBack; back += 4) {
        if (callPC < back + 4) break;
        uintptr_t ldrPC = callPC - back;
        uintptr_t adrpPC = ldrPC - 4;
        if (!HFAReadable(adrpPC, 8)) continue;
        uint32_t adrp = 0, ldr = 0;
        memcpy(&adrp, (const void *)adrpPC, 4);
        memcpy(&ldr, (const void *)ldrPC, 4);

        unsigned rt = 0, rn = 0;
        uintptr_t imm = 0;
        if (!HFAPortableDecodeUnsignedLDRX(ldr, &rt, &rn, &imm) ||
            rt != wantedRegister)
            continue;
        uintptr_t page = HFAStaticADRPPage(adrpPC, adrp, rn);
        if (!page) continue;
        uintptr_t refAddress = page + imm;
        if (refAddress < (uintptr_t)slide) continue;
        uintptr_t refRVA = refAddress - (uintptr_t)slide;

        NSString *semantic = wantedRegister == 0 ?
            HFAPortableClassName(imageName, refRVA) :
            HFAPortableSelectorName(imageName, refRVA);
        if (!semantic.length) continue;
        if (refRVAOut) *refRVAOut = refRVA;
        if (semanticOut) *semanticOut = semantic;
        return 1;
    }
    return 0;
}

static NSDictionary *HFAPortableResolveRuntimeGlobalBinding(
    const char *imageName, uintptr_t globalRVA, const char *identifier) {
    if (!imageName || !*imageName || !globalRVA) return nil;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return nil;
    const struct mach_header *mh = _dyld_get_image_header((uint32_t)imageIndex);
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t imageBase = (uintptr_t)mh;
    uintptr_t textStart = 0, textEnd = 0;
    if (!mh || !HFAStaticFindTextSection(mh, slide, &textStart, &textEnd))
        return nil;

    uintptr_t globalAddress = (uintptr_t)((intptr_t)slide +
                                          (intptr_t)globalRVA);
    NSMutableArray *matches = [NSMutableArray array];

    for (uintptr_t pc = textStart; pc + 8 <= textEnd; pc += 4) {
        if (!HFAReadable(pc, 8)) break;
        uint32_t adrp = 0, str = 0;
        memcpy(&adrp, (const void *)pc, 4);
        memcpy(&str, (const void *)(pc + 4), 4);

        unsigned rt = 0, rn = 0;
        uintptr_t imm = 0;
        if (!HFAPortableDecodeUnsignedSTRX(str, &rt, &rn, &imm) || rt != 0)
            continue;
        uintptr_t page = HFAStaticADRPPage(pc, adrp, rn);
        if (!page || page + imm != globalAddress) continue;

        uintptr_t objcCallPC = 0;
        NSString *objcSymbol = nil;
        const size_t maxBack = 0x50u;
        for (size_t back = 4; back <= maxBack; back += 4) {
            if (pc < back) break;
            uintptr_t callPC = pc - back;
            if (!HFAReadable(callPC, 4)) continue;
            uint32_t word = 0;
            memcpy(&word, (const void *)callPC, 4);
            if ((word & 0xFC000000u) != 0x94000000u) continue;
            NSString *symbol = HFAPortableBranchImportSymbol(imageName,
                                                             callPC, word);
            if ([symbol isEqualToString:@"objc_msgSend"]) {
                objcCallPC = callPC;
                objcSymbol = symbol;
                break;
            }
        }
        if (!objcCallPC || !objcSymbol.length) continue;

        uintptr_t classRefRVA = 0, selectorRefRVA = 0;
        NSString *className = nil, *selectorName = nil;
        if (!HFAPortableFindObjCArgRef(imageName, objcCallPC, 0,
                                      &classRefRVA, &className) ||
            !HFAPortableFindObjCArgRef(imageName, objcCallPC, 1,
                                      &selectorRefRVA, &selectorName))
            continue;

        NSDictionary *match = @{
            @"kind": @"objcFactoryResult",
            @"class": className,
            @"selector": selectorName,
            @"classReferenceOffset": HFANativeOffsetString(classRefRVA),
            @"selectorReferenceOffset": HFANativeOffsetString(selectorRefRVA),
            @"callInstructionOffset": HFANativeOffsetString(
                objcCallPC - imageBase),
            @"storeInstructionOffset": HFANativeOffsetString(pc - imageBase),
            @"sourceTarget": [NSString stringWithUTF8String:imageName],
            @"sourceOffset": HFANativeOffsetString(globalRVA)
        };
        [matches addObject:match];
        HFALog("[RUNTIME-GLOBAL-CANDIDATE] identifier=%s source=%s+0x%llX class=%s selector=%s callRVA=%llX storeRVA=%llX\n",
               identifier && *identifier ? identifier : "?", imageName,
               (unsigned long long)globalRVA,
               className.UTF8String, selectorName.UTF8String,
               (unsigned long long)(objcCallPC - imageBase),
               (unsigned long long)(pc - imageBase));
    }

    if (matches.count != 1) {
        HFALog("[RUNTIME-GLOBAL-BINDING] identifier=%s source=%s+0x%llX status=%s candidates=%u\n",
               identifier && *identifier ? identifier : "?", imageName,
               (unsigned long long)globalRVA,
               matches.count ? "AMBIGUOUS" : "NONE",
               (unsigned)matches.count);
        return nil;
    }

    NSDictionary *binding = [matches objectAtIndex:0];
    HFALog("[RUNTIME-GLOBAL-BINDING] identifier=%s source=%s+0x%llX status=UNIQUE kind=%s class=%s selector=%s\n",
           identifier && *identifier ? identifier : "?", imageName,
           (unsigned long long)globalRVA,
           [[binding objectForKey:@"kind"] UTF8String],
           [[binding objectForKey:@"class"] UTF8String],
           [[binding objectForKey:@"selector"] UTF8String]);
    return binding;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected relocation-plan anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''        } else if ([section isEqualToString:@"__common"] ||
                   [section isEqualToString:@"__bss"] ||
                   [section isEqualToString:@"__data"]) {
            NSString *slotImage = r->slotImage[0] ?
                [NSString stringWithUTF8String:r->slotImage] : nil;
            BOOL originalSlot = targetRVA == r->slotRVA && slotImage.length &&
                [targetImage isEqualToString:slotImage];
            entry[@"bindingKind"] = @"writableGlobal";
            entry[@"role"] = originalSlot ? @"originalSlot" : @"runtimeGlobal";
            ok = YES;
'''
new = r'''        } else if ([section isEqualToString:@"__common"] ||
                   [section isEqualToString:@"__bss"] ||
                   [section isEqualToString:@"__data"]) {
            NSString *slotImage = r->slotImage[0] ?
                [NSString stringWithUTF8String:r->slotImage] : nil;
            BOOL originalSlot = targetRVA == r->slotRVA && slotImage.length &&
                [targetImage isEqualToString:slotImage];
            entry[@"bindingKind"] = @"writableGlobal";
            entry[@"role"] = originalSlot ? @"originalSlot" : @"runtimeGlobal";
            if (originalSlot) {
                entry[@"runtimeBinding"] = @{
                    @"kind": @"consumerOriginalSlot"
                };
                ok = YES;
            } else {
                NSDictionary *binding = HFAPortableResolveRuntimeGlobalBinding(
                    targetImage.UTF8String, targetRVA, r->identifier);
                if (binding) {
                    entry[@"runtimeBinding"] = binding;
                    ok = YES;
                }
            }
'''
if s.count(old) != 1:
    raise SystemExit(f"expected writable-global relocation branch once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.16 RelocationPlanExporter REDO] loaded'
new_marker = '[HFALearn v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.16 REDO source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.16 RelocationPlanExporter REDO] loaded'
new_marker = '[HFALearn UI v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.16 REDO legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
