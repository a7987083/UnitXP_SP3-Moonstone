from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.16: recursively capture semantic helper-code dependencies discovered by
# v1.9.15. The recursion is intentionally seeded only from codeDependencies,
# canonicalized by LC_FUNCTION_STARTS, deduplicated by image+function start, and
# bounded by unit/byte limits. Raw references and per-unit semantic tables are
# preserved so later relocation generation can be evidence-backed.

anchor = r'''static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
'''
helper = r'''
static NSDictionary *HFACapturePortableCodeUnit(HFANativeHookRegistration *r,
                                                NSString *imageName,
                                                uintptr_t requestedRVA) {
    if (!r || !imageName.length || !requestedRVA) return nil;
    int imageIndex = HFAImageIndexForName(imageName.UTF8String);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t requestedAddress =
        (uintptr_t)((intptr_t)slide + (intptr_t)requestedRVA);

    uintptr_t startRVA = 0, endRVA = 0;
    const char *boundarySource = NULL;
    if (!HFAPortableFunctionBounds(imageName.UTF8String,
                                   requestedAddress,
                                   requestedRVA,
                                   &startRVA,
                                   &endRVA,
                                   &boundarySource) ||
        !startRVA || endRVA <= startRVA)
        return nil;

    size_t size = (size_t)(endRVA - startRVA);
    if (!size || size > 0x4000u) return nil;
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
            int64_t displacement =
                HFAStaticSignExtend(((uint64_t)(word & 0x03FFFFFFu)) << 2, 28);
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
                                               "ADRP+ADD",
                                               instructionRVA,
                                               page + imm,
                                               startRVA, endRVA);
                    paired = 1;
                    break;
                }

                if ((next & 0x3B000000u) == 0x39000000u) {
                    unsigned scale = (next >> 30) & 3u;
                    uintptr_t imm =
                        (uintptr_t)((next >> 10) & 0xFFFu) << scale;
                    HFAPortableAppendReference(refs, r->identifier,
                                               "ADRP+LDST",
                                               instructionRVA,
                                               page + imm,
                                               startRVA, endRVA);
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
        @"semanticDependencies": semantic ?: @{}
    }];
    if (codeHex) unit[@"codeHex"] = codeHex;
    return unit;
}

static NSString *HFAPortableCodeUnitKey(NSString *imageName,
                                        NSString *functionStart) {
    if (!imageName.length || !functionStart.length) return nil;
    return [NSString stringWithFormat:@"%@:%@", imageName, functionStart];
}

static void HFAEnqueueCodeDependencies(NSArray *dependencies,
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
        [queue addObject:@{
            @"sourceTarget": image,
            @"sourceOffset": offset
        }];
    }
}

static NSDictionary *HFARecursivePortableCodeClosure(
    HFANativeHookRegistration *r,
    NSString *rootImage,
    uintptr_t rootStartRVA,
    uintptr_t rootEndRVA,
    size_t rootSize,
    NSString *rootCodeHex,
    NSArray *rootRefs,
    NSDictionary *rootSemantic) {
    if (!r || !rootImage.length || !rootStartRVA ||
        rootEndRVA <= rootStartRVA || !rootRefs)
        return nil;

    const unsigned unitLimit = 64u;
    const size_t byteLimit = 0x40000u;
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
        @"semanticDependencies": rootSemantic ?: @{}
    }];
    if (rootCodeHex) root[@"codeHex"] = rootCodeHex;
    [units addObject:root];
    NSString *rootKey = HFAPortableCodeUnitKey(
        rootImage, HFANativeOffsetString(rootStartRVA));
    if (rootKey) [visited addObject:rootKey];

    HFAEnqueueCodeDependencies(
        [rootSemantic objectForKey:@"codeDependencies"], queue, queued);

    unsigned cursor = 0;
    while (cursor < queue.count) {
        if (units.count >= unitLimit || totalBytes >= byteLimit) {
            unresolved += (unsigned)(queue.count - cursor);
            HFALog("[RECURSIVE-CODE-SKIP] identifier=%s reason=limit units=%u totalBytes=%zu remaining=%u\n",
                   r->identifier, (unsigned)units.count, totalBytes,
                   (unsigned)(queue.count - cursor));
            break;
        }

        NSDictionary *request = [queue objectAtIndex:cursor++];
        NSString *image = [request objectForKey:@"sourceTarget"];
        NSString *offset = [request objectForKey:@"sourceOffset"];
        uintptr_t requestedRVA =
            (uintptr_t)strtoull(offset.UTF8String, NULL, 16);
        if (!image.length || !requestedRVA) {
            unresolved++;
            continue;
        }

        NSDictionary *unit = HFACapturePortableCodeUnit(r, image, requestedRVA);
        if (!unit) {
            unresolved++;
            HFALog("[RECURSIVE-CODE-SKIP] identifier=%s reason=capture-failed source=%s+%s\n",
                   r->identifier, image.UTF8String, offset.UTF8String);
            continue;
        }

        NSString *start = [unit objectForKey:@"functionStart"];
        NSString *canonicalImage = [unit objectForKey:@"sourceTarget"];
        NSString *key = HFAPortableCodeUnitKey(canonicalImage, start);
        if (key && [visited containsObject:key]) {
            HFALog("[RECURSIVE-CODE-EDGE] identifier=%s source=%s+%s canonical=%s status=visited\n",
                   r->identifier, image.UTF8String, offset.UTF8String,
                   key.UTF8String);
            continue;
        }

        size_t unitBytes = [[unit objectForKey:@"functionSize"] unsignedLongLongValue];
        if (totalBytes + unitBytes > byteLimit) {
            unresolved++;
            HFALog("[RECURSIVE-CODE-SKIP] identifier=%s reason=byte-limit source=%s+%s size=%zu totalBytes=%zu\n",
                   r->identifier, image.UTF8String, offset.UTF8String,
                   unitBytes, totalBytes);
            continue;
        }

        if (key) [visited addObject:key];
        NSMutableDictionary *stored = [NSMutableDictionary dictionaryWithDictionary:unit];
        stored[@"role"] = @"helperCode";
        [units addObject:stored];
        totalBytes += unitBytes;

        NSDictionary *semantic = [unit objectForKey:@"semanticDependencies"];
        NSArray *children = [semantic objectForKey:@"codeDependencies"];
        HFALog("[RECURSIVE-CODE-UNIT] identifier=%s image=%s requested=%s start=%s end=%s size=%zu refs=%u childCode=%u totalUnits=%u totalBytes=%zu\n",
               r->identifier,
               canonicalImage.UTF8String,
               [[unit objectForKey:@"requestedOffset"] UTF8String],
               start.UTF8String,
               [[unit objectForKey:@"functionEnd"] UTF8String],
               unitBytes,
               [[unit objectForKey:@"referenceCount"] unsignedIntValue],
               [children isKindOfClass:[NSArray class]] ? (unsigned)children.count : 0u,
               (unsigned)units.count,
               totalBytes);
        HFAEnqueueCodeDependencies(children, queue, queued);
    }

    BOOL complete = unresolved == 0 && cursor >= queue.count;
    HFALog("[RECURSIVE-CLOSURE] identifier=%s codeUnits=%u totalBytes=%zu queued=%u unresolved=%u complete=%u\n",
           r->identifier, (unsigned)units.count, totalBytes,
           (unsigned)queue.count, unresolved, complete ? 1u : 0u);

    return @{
        @"codeUnits": units,
        @"codeUnitCount": @((unsigned)units.count),
        @"totalCodeBytes": @(totalBytes),
        @"queuedCodeDependencies": @((unsigned)queue.count),
        @"unresolvedCodeDependencies": @(unresolved),
        @"closureComplete": @(complete),
        @"limits": @{
            @"codeUnitLimit": @(unitLimit),
            @"totalByteLimit": @(byteLimit)
        }
    };
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected capture anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
        @"status": @"captured",
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @(size),
        @"boundarySource": [NSString stringWithUTF8String:
            boundarySource ? boundarySource : "?"],
        @"references": refs,
        @"referenceCount": @((unsigned)refs.count),
        @"externalReferenceCount": @(externalRefs),
        @"semanticDependencies": semantic ?: @{},
        @"portablePayload": @NO,
        @"reason": @"semantic-dependencies-resolved-relocations-pending"
    }];
'''
new = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSString *rootImage = [NSString stringWithUTF8String:r->replacementImage];
    NSDictionary *closure = HFARecursivePortableCodeClosure(
        r, rootImage, startRVA, endRVA, size, codeHex, refs, semantic);
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
        @"status": @"captured",
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @(size),
        @"boundarySource": [NSString stringWithUTF8String:
            boundarySource ? boundarySource : "?"],
        @"references": refs,
        @"referenceCount": @((unsigned)refs.count),
        @"externalReferenceCount": @(externalRefs),
        @"semanticDependencies": semantic ?: @{},
        @"recursiveCodeClosure": closure ?: @{},
        @"portablePayload": @NO,
        @"reason": @"recursive-code-closure-captured-relocations-pending"
    }];
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.15 capture dictionary once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.15 SemanticDependencyResolver] loaded'
new_marker = '[HFALearn v1.9.16 RecursiveCodeDependencyCapture] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.15 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.15 SemanticDependencyResolver] loaded'
new_marker = '[HFALearn UI v1.9.16 RecursiveCodeDependencyCapture] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.15 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
