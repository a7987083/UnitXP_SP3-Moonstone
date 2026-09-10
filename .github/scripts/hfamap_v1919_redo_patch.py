from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.19-redo: v1.9.18 resolves the root replacement relocation plan and
# runtime globals, but the exported package still lacks the actual bodies of
# helperCode dependencies and the bytes behind constant references. Capture a
# bounded recursive helper-code closure and 4K constant-page snapshots with
# pointer fixups. Analysis/export only; stable AP descriptor path is untouched.

anchor = r'''static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
'''
helper = r'''
static NSDictionary *HFACapturePortableCodeUnitV1919(
    HFANativeHookRegistration *r, NSString *imageName, uintptr_t requestedRVA) {
    if (!r || !imageName.length || !requestedRVA) return nil;
    int imageIndex = HFAImageIndexForName(imageName.UTF8String);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t requestedAddress =
        (uintptr_t)((intptr_t)slide + (intptr_t)requestedRVA);

    uintptr_t startRVA = 0, endRVA = 0;
    const char *boundarySource = NULL;
    if (!HFAPortableFunctionBounds(imageName.UTF8String, requestedAddress,
                                   requestedRVA, &startRVA, &endRVA,
                                   &boundarySource) ||
        !startRVA || endRVA <= startRVA)
        return nil;

    size_t size = (size_t)(endRVA - startRVA);
    if (!size || size > 0x8000u) return nil;
    uintptr_t startAddress =
        (uintptr_t)((intptr_t)slide + (intptr_t)startRVA);
    if (!HFAReadable(startAddress, size)) return nil;

    NSMutableArray *refs = [NSMutableArray array];
    for (size_t off = 0; off + 4 <= size; off += 4) {
        uintptr_t pc = startAddress + off;
        uintptr_t instructionRVA = startRVA + off;
        uint32_t word = 0;
        memcpy(&word, (const void *)pc, 4);

        uint32_t branchClass = word & 0xFC000000u;
        if (branchClass == 0x94000000u || branchClass == 0x14000000u) {
            int64_t displacement = HFAStaticSignExtend(
                ((uint64_t)(word & 0x03FFFFFFu)) << 2, 28);
            uintptr_t target = (uintptr_t)((intptr_t)pc + displacement);
            HFAPortableAppendReference(refs, r->identifier,
                                       branchClass == 0x94000000u ? "BL" : "B",
                                       instructionRVA, target,
                                       startRVA, endRVA);
            continue;
        }

        if ((word & 0x9F000000u) == 0x10000000u) {
            unsigned rd = word & 31u;
            uintptr_t target = HFAStaticADRTarget(pc, word, rd);
            HFAPortableAppendReference(refs, r->identifier, "ADR",
                                       instructionRVA, target,
                                       startRVA, endRVA);
            continue;
        }

        if ((word & 0x9F000000u) == 0x90000000u) {
            unsigned rd = word & 31u;
            uintptr_t page = HFAStaticADRPPage(pc, word, rd);
            if (!page) continue;
            int paired = 0;
            for (size_t ahead = 4;
                 ahead <= 16 && off + ahead + 4 <= size;
                 ahead += 4) {
                uint32_t next = 0;
                memcpy(&next, (const void *)(pc + ahead), 4);
                unsigned rn = (next >> 5) & 31u;
                if (rn != rd) continue;

                if ((next & 0xFF000000u) == 0x91000000u) {
                    uintptr_t imm = (uintptr_t)((next >> 10) & 0xFFFu);
                    if ((next >> 22) & 1u) imm <<= 12;
                    HFAPortableAppendReference(refs, r->identifier,
                                               "ADRP+ADD", instructionRVA,
                                               page + imm, startRVA, endRVA);
                    paired = 1;
                    break;
                }

                if ((next & 0x3B000000u) == 0x39000000u) {
                    unsigned scale = (next >> 30) & 3u;
                    uintptr_t imm =
                        (uintptr_t)((next >> 10) & 0xFFFu) << scale;
                    HFAPortableAppendReference(refs, r->identifier,
                                               "ADRP+LDST", instructionRVA,
                                               page + imm, startRVA, endRVA);
                    paired = 1;
                    break;
                }
            }
            if (!paired)
                HFAPortableAppendReference(refs, r->identifier, "ADRP",
                                           instructionRVA, page,
                                           startRVA, endRVA);
            continue;
        }

        if ((word & 0x3B000000u) == 0x18000000u) {
            int64_t displacement = HFAStaticSignExtend(
                ((uint64_t)((word >> 5) & 0x7FFFFu)) << 2, 21);
            uintptr_t target = (uintptr_t)((intptr_t)pc + displacement);
            HFAPortableAppendReference(refs, r->identifier, "LDR_LITERAL",
                                       instructionRVA, target,
                                       startRVA, endRVA);
        }
    }

    NSString *codeHex = HFAPortableCodeHex(startAddress, size);
    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
    NSMutableDictionary *unit = [NSMutableDictionary dictionaryWithDictionary:@{
        @"sourceTarget": imageName,
        @"requestedOffset": HFANativeOffsetString(requestedRVA),
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @(size),
        @"boundarySource": [NSString stringWithUTF8String:
            boundarySource ? boundarySource : "?"],
        @"references": refs,
        @"referenceCount": @((unsigned)refs.count),
        @"semanticDependencies": semantic ?: @{},
        @"relocationPlan": relocation ?: @{}
    }];
    if (codeHex) unit[@"codeHex"] = codeHex;
    return unit;
}

static NSString *HFAPortableCodeUnitKeyV1919(NSString *imageName,
                                              NSString *functionStart) {
    if (!imageName.length || !functionStart.length) return nil;
    return [NSString stringWithFormat:@"%@:%@", imageName, functionStart];
}

static void HFAEnqueueCodeDependenciesV1919(NSArray *dependencies,
                                             NSMutableArray *queue,
                                             NSMutableSet *queued) {
    if (![dependencies isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *dep in dependencies) {
        if (![dep isKindOfClass:[NSDictionary class]]) continue;
        NSString *image = [dep objectForKey:@"sourceTarget"];
        NSString *offset = [dep objectForKey:@"sourceOffset"];
        if (![image isKindOfClass:[NSString class]] || !image.length ||
            ![offset isKindOfClass:[NSString class]] || !offset.length)
            continue;
        NSString *queueKey = [NSString stringWithFormat:@"%@:%@", image, offset];
        if ([queued containsObject:queueKey]) continue;
        [queued addObject:queueKey];
        [queue addObject:@{ @"sourceTarget": image, @"sourceOffset": offset }];
    }
}

static NSDictionary *HFARecursivePortableCodeClosureV1919(
    HFANativeHookRegistration *r, NSString *rootImage,
    uintptr_t rootStartRVA, uintptr_t rootEndRVA, size_t rootSize,
    NSString *rootCodeHex, NSArray *rootRefs, NSDictionary *rootSemantic,
    NSDictionary *rootRelocation) {
    if (!r || !rootImage.length || !rootStartRVA ||
        rootEndRVA <= rootStartRVA || !rootRefs)
        return nil;

    const unsigned unitLimit = 96u;
    const size_t byteLimit = 0x80000u;
    NSMutableArray *units = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *queued = [NSMutableSet set];
    NSMutableSet *visited = [NSMutableSet set];
    unsigned unresolved = 0;
    size_t totalBytes = rootSize;

    NSMutableDictionary *root = [NSMutableDictionary dictionaryWithDictionary:@{
        @"role": @"replacement",
        @"sourceTarget": rootImage,
        @"requestedOffset": HFANativeOffsetString(rootStartRVA),
        @"functionStart": HFANativeOffsetString(rootStartRVA),
        @"functionEnd": HFANativeOffsetString(rootEndRVA),
        @"functionSize": @(rootSize),
        @"references": rootRefs,
        @"referenceCount": @((unsigned)rootRefs.count),
        @"semanticDependencies": rootSemantic ?: @{},
        @"relocationPlan": rootRelocation ?: @{}
    }];
    if (rootCodeHex) root[@"codeHex"] = rootCodeHex;
    [units addObject:root];
    NSString *rootKey = HFAPortableCodeUnitKeyV1919(
        rootImage, HFANativeOffsetString(rootStartRVA));
    if (rootKey) [visited addObject:rootKey];

    HFAEnqueueCodeDependenciesV1919(
        [rootSemantic objectForKey:@"codeDependencies"], queue, queued);

    unsigned cursor = 0;
    while (cursor < queue.count) {
        if (units.count >= unitLimit || totalBytes >= byteLimit) {
            unresolved += (unsigned)(queue.count - cursor);
            break;
        }
        NSDictionary *request = [queue objectAtIndex:cursor++];
        NSString *image = [request objectForKey:@"sourceTarget"];
        NSString *offset = [request objectForKey:@"sourceOffset"];
        uintptr_t requestedRVA =
            (uintptr_t)strtoull(offset.UTF8String, NULL, 16);
        NSDictionary *unit = HFACapturePortableCodeUnitV1919(
            r, image, requestedRVA);
        if (!unit) {
            unresolved++;
            HFALog("[PAYLOAD-CODE-SKIP] identifier=%s source=%s+%s reason=capture-failed\n",
                   r->identifier, image.UTF8String, offset.UTF8String);
            continue;
        }
        NSString *start = [unit objectForKey:@"functionStart"];
        NSString *canonicalImage = [unit objectForKey:@"sourceTarget"];
        NSString *key = HFAPortableCodeUnitKeyV1919(canonicalImage, start);
        if (key && [visited containsObject:key]) continue;
        size_t unitBytes = [[unit objectForKey:@"functionSize"] unsignedLongLongValue];
        if (totalBytes + unitBytes > byteLimit) {
            unresolved++;
            continue;
        }
        if (key) [visited addObject:key];
        NSMutableDictionary *stored =
            [NSMutableDictionary dictionaryWithDictionary:unit];
        stored[@"role"] = @"helperCode";
        [units addObject:stored];
        totalBytes += unitBytes;

        NSDictionary *semantic = [unit objectForKey:@"semanticDependencies"];
        NSArray *children = [semantic objectForKey:@"codeDependencies"];
        HFAEnqueueCodeDependenciesV1919(children, queue, queued);
        HFALog("[PAYLOAD-CODE-UNIT] identifier=%s image=%s start=%s end=%s size=%zu refs=%u children=%u\n",
               r->identifier, canonicalImage.UTF8String,
               start.UTF8String,
               [[unit objectForKey:@"functionEnd"] UTF8String],
               unitBytes,
               [[unit objectForKey:@"referenceCount"] unsignedIntValue],
               [children isKindOfClass:[NSArray class]] ? (unsigned)children.count : 0u);
    }

    BOOL complete = unresolved == 0 && cursor >= queue.count;
    HFALog("[PAYLOAD-CODE-CLOSURE] identifier=%s units=%u totalBytes=%zu queued=%u unresolved=%u complete=%u\n",
           r->identifier, (unsigned)units.count, totalBytes,
           (unsigned)queue.count, unresolved, complete ? 1u : 0u);
    return @{
        @"codeUnits": units,
        @"codeUnitCount": @((unsigned)units.count),
        @"totalCodeBytes": @(totalBytes),
        @"queuedCodeDependencies": @((unsigned)queue.count),
        @"unresolvedCodeDependencies": @(unresolved),
        @"closureComplete": @(complete)
    };
}

static NSDictionary *HFAPortableConstantPageV1919(NSString *imageName,
                                                   uintptr_t targetRVA) {
    if (!imageName.length || !targetRVA) return nil;
    int imageIndex = HFAImageIndexForName(imageName.UTF8String);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t pageRVA = targetRVA & ~(uintptr_t)0xFFFu;
    uintptr_t pageAddress =
        (uintptr_t)((intptr_t)slide + (intptr_t)pageRVA);
    const size_t pageSize = 0x1000u;
    NSString *pageHex = HFAPortableCodeHex(pageAddress, pageSize);
    if (!pageHex.length) return nil;

    NSMutableArray *fixups = [NSMutableArray array];
    for (size_t off = 0; off + sizeof(uintptr_t) <= pageSize;
         off += sizeof(uintptr_t)) {
        uintptr_t raw = 0;
        memcpy(&raw, (const void *)(pageAddress + off), sizeof(raw));
        raw = HFAStripCodePointer(raw);
        if (!raw) continue;
        char targetImage[256] = {0};
        uintptr_t targetOffset = 0;
        HFADescribePointer(raw, targetImage, sizeof(targetImage), &targetOffset);
        if (!targetImage[0]) continue;
        [fixups addObject:@{
            @"pageOffset": [NSString stringWithFormat:@"0x%04zX", off],
            @"target": [NSString stringWithUTF8String:targetImage],
            @"targetOffset": HFANativeOffsetString(targetOffset)
        }];
    }

    return @{
        @"sourceTarget": imageName,
        @"pageStart": HFANativeOffsetString(pageRVA),
        @"pageSize": @(pageSize),
        @"pageHex": pageHex,
        @"pointerFixups": fixups,
        @"pointerFixupCount": @((unsigned)fixups.count)
    };
}

static void HFACollectConstantPagesFromRelocationV1919(
    NSDictionary *relocation, NSMutableDictionary *pages,
    const char *identifier) {
    NSArray *entries = [relocation objectForKey:@"entries"];
    if (![entries isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *entry in entries) {
        if (![[entry objectForKey:@"bindingKind"] isEqualToString:@"constant"])
            continue;
        NSString *image = [entry objectForKey:@"sourceTarget"];
        NSString *offset = [entry objectForKey:@"sourceOffset"];
        uintptr_t rva = (uintptr_t)strtoull(offset.UTF8String, NULL, 16);
        uintptr_t pageRVA = rva & ~(uintptr_t)0xFFFu;
        NSString *key = [NSString stringWithFormat:@"%@:%08llX", image,
                         (unsigned long long)pageRVA];
        if ([pages objectForKey:key]) continue;
        NSDictionary *page = HFAPortableConstantPageV1919(image, rva);
        if (!page) continue;
        pages[key] = page;
        HFALog("[PAYLOAD-CONSTANT-PAGE] identifier=%s source=%s page=%s fixups=%u\n",
               identifier && *identifier ? identifier : "?",
               image.UTF8String,
               [[page objectForKey:@"pageStart"] UTF8String],
               [[page objectForKey:@"pointerFixupCount"] unsignedIntValue]);
    }
}

static NSArray *HFAPortableConstantPagesV1919(
    NSDictionary *rootRelocation, NSDictionary *closure,
    const char *identifier) {
    NSMutableDictionary *pages = [NSMutableDictionary dictionary];
    HFACollectConstantPagesFromRelocationV1919(rootRelocation, pages,
                                               identifier);
    NSArray *units = [closure objectForKey:@"codeUnits"];
    if ([units isKindOfClass:[NSArray class]]) {
        for (NSDictionary *unit in units) {
            HFACollectConstantPagesFromRelocationV1919(
                [unit objectForKey:@"relocationPlan"], pages, identifier);
        }
    }
    NSArray *result = [[pages allValues] sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSString *ka = [NSString stringWithFormat:@"%@:%@",
                [a objectForKey:@"sourceTarget"], [a objectForKey:@"pageStart"]];
            NSString *kb = [NSString stringWithFormat:@"%@:%@",
                [b objectForKey:@"sourceTarget"], [b objectForKey:@"pageStart"]];
            return [ka compare:kb];
        }];
    HFALog("[PAYLOAD-CONSTANT-SUMMARY] identifier=%s pages=%u\n",
           identifier && *identifier ? identifier : "?", (unsigned)result.count);
    return result;
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected capture anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
    BOOL relocationReady = [[relocation objectForKey:@"ready"] boolValue];
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
'''
new = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
    BOOL relocationReady = [[relocation objectForKey:@"ready"] boolValue];
    NSString *rootImage = [NSString stringWithUTF8String:r->replacementImage];
    NSDictionary *closure = HFARecursivePortableCodeClosureV1919(
        r, rootImage, startRVA, endRVA, size, codeHex, refs, semantic,
        relocation);
    NSArray *constantPages = HFAPortableConstantPagesV1919(
        relocation, closure, r->identifier);
    BOOL codeClosureReady = [[closure objectForKey:@"closureComplete"] boolValue];
    BOOL payloadInputsComplete = relocationReady && codeClosureReady &&
        constantPages.count > 0;
    HFALog("[PAYLOAD-INPUTS] identifier=%s relocationReady=%u codeClosureReady=%u constantPages=%u complete=%u\n",
           r->identifier, relocationReady ? 1u : 0u,
           codeClosureReady ? 1u : 0u, (unsigned)constantPages.count,
           payloadInputsComplete ? 1u : 0u);
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.18 capture prelude once, found {s.count(old)}")
s = s.replace(old, new, 1)

old = r'''        @"semanticDependencies": semantic ?: @{},
        @"relocationPlan": relocation ?: @{},
        @"relocationPlanReady": @(relocationReady),
        @"portablePayload": @NO,
        @"reason": relocationReady ?
            @"relocation-plan-ready-payload-materialization-pending" :
            @"relocation-plan-incomplete"
'''
new = r'''        @"semanticDependencies": semantic ?: @{},
        @"relocationPlan": relocation ?: @{},
        @"relocationPlanReady": @(relocationReady),
        @"recursiveCodeClosure": closure ?: @{},
        @"constantPages": constantPages ?: @[],
        @"payloadInputsComplete": @(payloadInputsComplete),
        @"portablePayload": @NO,
        @"reason": payloadInputsComplete ?
            @"payload-inputs-complete-consumer-materialization-pending" :
            @"payload-inputs-incomplete"
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.18 capture dictionary fields once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
new_marker = '[HFALearn v1.9.19 PayloadDependencyCapture REDO] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.18 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.18 RuntimeGlobalBindingResolver REDO] loaded'
new_marker = '[HFALearn UI v1.9.19 PayloadDependencyCapture REDO] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.18 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
