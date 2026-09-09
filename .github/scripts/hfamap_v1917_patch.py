from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.17: convert the evidence-backed recursive code closure into an explicit
# per-instruction relocation plan. Every relocation records the original
# instruction word(s), instruction offset(s), target identity, and a resolved
# semantic binding. Unknown references remain explicit unresolved entries; no
# feature id, image name, symbol, selector, class, or RVA is hardcoded.
anchor = r'''static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
'''
helper = r'''
static uintptr_t HFAExplicitHexValue(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || !value.length) return 0;
    return (uintptr_t)strtoull(value.UTF8String, NULL, 16);
}

static NSDictionary *HFAExplicitSemanticMatch(NSDictionary *semantic,
                                              NSString *target,
                                              NSString *targetOffset) {
    if (![semantic isKindOfClass:[NSDictionary class]] ||
        !target.length || !targetOffset.length)
        return nil;

    NSArray *imports = [semantic objectForKey:@"imports"];
    for (NSDictionary *entry in imports) {
        if (![[entry objectForKey:@"sourceTarget"] isEqualToString:target] ||
            ![[entry objectForKey:@"sourceOffset"] isEqualToString:targetOffset])
            continue;
        NSString *symbol = [entry objectForKey:@"symbol"] ?: @"?";
        return @{
            @"type": @"importSymbol",
            @"symbol": symbol,
            @"sourceTarget": target,
            @"sourceOffset": targetOffset,
            @"sourceSection": [entry objectForKey:@"sourceSection"] ?: @"?"
        };
    }

    NSArray *objc = [semantic objectForKey:@"objcBindings"];
    for (NSDictionary *entry in objc) {
        if (![[entry objectForKey:@"sourceTarget"] isEqualToString:target] ||
            ![[entry objectForKey:@"sourceOffset"] isEqualToString:targetOffset])
            continue;
        NSString *kind = [entry objectForKey:@"kind"] ?: @"?";
        NSString *bindingType = [kind isEqualToString:@"class"] ?
            @"objcClass" : ([kind isEqualToString:@"selector"] ?
            @"objcSelector" : @"objcBinding");
        return @{
            @"type": bindingType,
            @"name": [entry objectForKey:@"name"] ?: @"?",
            @"sourceTarget": target,
            @"sourceOffset": targetOffset
        };
    }

    NSArray *globals = [semantic objectForKey:@"globals"];
    for (NSDictionary *entry in globals) {
        if (![[entry objectForKey:@"sourceTarget"] isEqualToString:target] ||
            ![[entry objectForKey:@"sourceOffset"] isEqualToString:targetOffset])
            continue;
        return @{
            @"type": @"global",
            @"role": [entry objectForKey:@"role"] ?: @"writableGlobal",
            @"sourceTarget": target,
            @"sourceOffset": targetOffset,
            @"sourceSection": [entry objectForKey:@"sourceSection"] ?: @"?"
        };
    }

    NSArray *code = [semantic objectForKey:@"codeDependencies"];
    for (NSDictionary *entry in code) {
        if (![[entry objectForKey:@"sourceTarget"] isEqualToString:target] ||
            ![[entry objectForKey:@"sourceOffset"] isEqualToString:targetOffset])
            continue;
        return @{
            @"type": @"codeUnit",
            @"role": [entry objectForKey:@"role"] ?: @"helperCode",
            @"referenceKind": [entry objectForKey:@"referenceKind"] ?: @"?",
            @"sourceTarget": target,
            @"sourceOffset": targetOffset
        };
    }

    NSArray *constants = [semantic objectForKey:@"constants"];
    for (NSDictionary *entry in constants) {
        if (![[entry objectForKey:@"sourceTarget"] isEqualToString:target] ||
            ![[entry objectForKey:@"sourceOffset"] isEqualToString:targetOffset])
            continue;
        return @{
            @"type": @"constant",
            @"sourceTarget": target,
            @"sourceOffset": targetOffset,
            @"sourceSegment": [entry objectForKey:@"sourceSegment"] ?: @"?",
            @"sourceSection": [entry objectForKey:@"sourceSection"] ?: @"?"
        };
    }
    return nil;
}

static NSArray *HFAExplicitInstructionDescriptor(NSString *imageName,
                                                 uintptr_t instructionRVA,
                                                 NSString *kind) {
    if (!imageName.length || !instructionRVA || !kind.length) return @[];
    int imageIndex = HFAImageIndexForName(imageName.UTF8String);
    if (imageIndex < 0) return @[];
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t address = (uintptr_t)((intptr_t)slide + (intptr_t)instructionRVA);
    if (!HFAReadable(address, 4)) return @[];

    uint32_t first = 0;
    memcpy(&first, (const void *)address, 4);
    NSMutableArray *result = [NSMutableArray arrayWithObject:@{
        @"offset": HFANativeOffsetString(instructionRVA),
        @"word": [NSString stringWithFormat:@"0x%08X", first]
    }];

    if (![kind hasPrefix:@"ADRP+"]) return result;
    if ((first & 0x9F000000u) != 0x90000000u) return result;
    unsigned rd = first & 31u;
    BOOL wantAdd = [kind isEqualToString:@"ADRP+ADD"];
    BOOL wantLdst = [kind isEqualToString:@"ADRP+LDST"];
    for (uintptr_t ahead = 4; ahead <= 16; ahead += 4) {
        uintptr_t pairAddress = address + ahead;
        if (!HFAReadable(pairAddress, 4)) break;
        uint32_t next = 0;
        memcpy(&next, (const void *)pairAddress, 4);
        unsigned rn = (next >> 5) & 31u;
        if (rn != rd) continue;
        BOOL isAdd = (next & 0xFF000000u) == 0x91000000u;
        BOOL isLdst = (next & 0x3B000000u) == 0x39000000u;
        if ((wantAdd && !isAdd) || (wantLdst && !isLdst)) continue;
        [result addObject:@{
            @"offset": HFANativeOffsetString(instructionRVA + ahead),
            @"word": [NSString stringWithFormat:@"0x%08X", next]
        }];
        break;
    }
    return result;
}

static NSDictionary *HFAExplicitRelocationPlan(HFANativeHookRegistration *r,
                                                NSDictionary *closure) {
    if (!r || ![closure isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *units = [closure objectForKey:@"codeUnits"];
    if (![units isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray *relocations = [NSMutableArray array];
    unsigned unresolved = 0;
    unsigned internalCount = 0;
    unsigned externalCount = 0;

    for (NSDictionary *unit in units) {
        if (![unit isKindOfClass:[NSDictionary class]]) continue;
        NSString *unitTarget = [unit objectForKey:@"sourceTarget"];
        NSString *unitStartString = [unit objectForKey:@"functionStart"];
        uintptr_t unitStart = HFAExplicitHexValue(unitStartString);
        NSDictionary *semantic = [unit objectForKey:@"semanticDependencies"];
        NSArray *refs = [unit objectForKey:@"references"];
        if (!unitTarget.length || !unitStart ||
            ![refs isKindOfClass:[NSArray class]])
            continue;

        for (NSDictionary *ref in refs) {
            if (![ref isKindOfClass:[NSDictionary class]]) continue;
            NSString *kind = [ref objectForKey:@"kind"] ?: @"?";
            NSString *instructionOffsetString =
                [ref objectForKey:@"instructionOffset"] ?: @"0x00000000";
            uintptr_t instructionRVA =
                HFAExplicitHexValue(instructionOffsetString);
            NSString *target = [ref objectForKey:@"target"] ?: @"?";
            NSString *targetOffset =
                [ref objectForKey:@"targetOffset"] ?: @"0x00000000";
            BOOL internal = [[ref objectForKey:@"internal"] boolValue];

            NSDictionary *binding = nil;
            if (internal) {
                binding = @{
                    @"type": @"internalCode",
                    @"target": target,
                    @"targetOffset": targetOffset
                };
                internalCount++;
            } else {
                binding = HFAExplicitSemanticMatch(semantic, target, targetOffset);
                externalCount++;
            }

            BOOL resolved = binding != nil;
            if (!resolved) {
                unresolved++;
                binding = @{
                    @"type": @"unresolved",
                    @"target": target,
                    @"targetOffset": targetOffset,
                    @"targetSegment": [ref objectForKey:@"targetSegment"] ?: @"?",
                    @"targetSection": [ref objectForKey:@"targetSection"] ?: @"?"
                };
            }

            NSArray *instructions =
                HFAExplicitInstructionDescriptor(unitTarget, instructionRVA, kind);
            NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
                @"unitTarget": unitTarget,
                @"unitFunctionStart": unitStartString,
                @"instructionOffset": instructionOffsetString,
                @"instructionDelta": @(instructionRVA >= unitStart ?
                    instructionRVA - unitStart : 0),
                @"kind": kind,
                @"instructions": instructions ?: @[],
                @"target": target,
                @"targetOffset": targetOffset,
                @"binding": binding,
                @"resolved": @(resolved)
            }];
            if ([ref objectForKey:@"targetSegment"])
                entry[@"targetSegment"] = [ref objectForKey:@"targetSegment"];
            if ([ref objectForKey:@"targetSection"])
                entry[@"targetSection"] = [ref objectForKey:@"targetSection"];
            [relocations addObject:entry];

            HFALog("[EXPLICIT-RELOC] identifier=%s unit=%s+%s instruction=%s kind=%s target=%s+%s binding=%s resolved=%u words=%u\n",
                   r->identifier,
                   unitTarget.UTF8String,
                   unitStartString.UTF8String,
                   instructionOffsetString.UTF8String,
                   kind.UTF8String,
                   target.UTF8String,
                   targetOffset.UTF8String,
                   [[binding objectForKey:@"type"] UTF8String],
                   resolved ? 1u : 0u,
                   (unsigned)instructions.count);
        }
    }

    BOOL complete = relocations.count > 0 && unresolved == 0;
    HFALog("[EXPLICIT-RELOC-SUMMARY] identifier=%s relocations=%u internal=%u external=%u unresolved=%u complete=%u\n",
           r->identifier, (unsigned)relocations.count, internalCount,
           externalCount, unresolved, complete ? 1u : 0u);
    return @{
        @"relocations": relocations,
        @"relocationCount": @((unsigned)relocations.count),
        @"internalRelocationCount": @(internalCount),
        @"externalRelocationCount": @(externalCount),
        @"unresolvedRelocationCount": @(unresolved),
        @"complete": @(complete),
        @"method": @"explicitSemanticBinding"
    };
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected capture anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    NSDictionary *closure = HFARecursivePortableCodeClosure(
        r, rootImage, startRVA, endRVA, size, codeHex, refs, semantic);
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
'''
new = r'''    NSDictionary *closure = HFARecursivePortableCodeClosure(
        r, rootImage, startRVA, endRVA, size, codeHex, refs, semantic);
    NSDictionary *relocationPlan = HFAExplicitRelocationPlan(r, closure);
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
'''
if s.count(old) != 1:
    raise SystemExit(f"expected closure capture anchor once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''        @"recursiveCodeClosure": closure ?: @{},
        @"portablePayload": @NO,
        @"reason": @"recursive-code-closure-captured-relocations-pending"
'''
new = r'''        @"recursiveCodeClosure": closure ?: @{},
        @"explicitRelocationPlan": relocationPlan ?: @{},
        @"portablePayload": @NO,
        @"reason": @"explicit-relocation-plan-captured-payload-materialization-pending"
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.16 capture fields once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.16 RecursiveCodeDependencyCapture] loaded'
new_marker = '[HFALearn v1.9.17 ExplicitRelocationPlan] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.16 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.16 RecursiveCodeDependencyCapture] loaded'
new_marker = '[HFALearn UI v1.9.17 ExplicitRelocationPlan] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.16 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
