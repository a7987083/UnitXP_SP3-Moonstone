from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")
s = patch_path.read_text()

anchor = r'''static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
'''
helper = r'''
static NSDictionary *HFAMaterializeCodeUnit(HFANativeHookRegistration *r,
                                             NSString *imageName,
                                             NSString *offsetString,
                                             NSString *role) {
    if (!r || !imageName.length || !offsetString.length) return nil;
    uintptr_t requestedRVA = (uintptr_t)strtoull(offsetString.UTF8String, NULL, 16);
    if (!requestedRVA) return nil;
    int imageIndex = HFAImageIndexForName(imageName.UTF8String);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t requestedAddress = (uintptr_t)((intptr_t)slide + (intptr_t)requestedRVA);
    uintptr_t startRVA = 0, endRVA = 0;
    const char *source = NULL;
    if (!HFAPortableFunctionBounds(imageName.UTF8String, requestedAddress,
                                   requestedRVA, &startRVA, &endRVA, &source) ||
        !startRVA || endRVA <= startRVA)
        return nil;
    size_t size = (size_t)(endRVA - startRVA);
    if (!size || size > 0x4000u) return nil;
    uintptr_t startAddress = (uintptr_t)((intptr_t)slide + (intptr_t)startRVA);
    NSString *hex = HFAPortableCodeHex(startAddress, size);
    if (!hex.length) return nil;
    NSDictionary *unit = @{
        @"role": role ?: @"helperCode",
        @"sourceTarget": imageName,
        @"requestedOffset": offsetString,
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @(size),
        @"boundarySource": [NSString stringWithUTF8String:source ? source : "?"],
        @"codeHex": hex
    };
    HFALog("[MATERIALIZE-CODE] identifier=%s role=%s image=%s requested=%s start=%s end=%s size=%zu\n",
           r->identifier,
           [[unit objectForKey:@"role"] UTF8String], imageName.UTF8String,
           offsetString.UTF8String,
           [[unit objectForKey:@"functionStart"] UTF8String],
           [[unit objectForKey:@"functionEnd"] UTF8String], size);
    return unit;
}

static NSDictionary *HFAMaterializeDataWindow(HFANativeHookRegistration *r,
                                               NSDictionary *constant) {
    if (!r || ![constant isKindOfClass:[NSDictionary class]]) return nil;
    NSString *imageName = [constant objectForKey:@"sourceTarget"];
    NSString *offsetString = [constant objectForKey:@"sourceOffset"];
    NSString *segment = [constant objectForKey:@"sourceSegment"];
    NSString *section = [constant objectForKey:@"sourceSection"];
    if (!imageName.length || !offsetString.length) return nil;
    uintptr_t rva = (uintptr_t)strtoull(offsetString.UTF8String, NULL, 16);
    int imageIndex = HFAImageIndexForName(imageName.UTF8String);
    if (imageIndex < 0 || !rva) return nil;
    const struct mach_header *mh = _dyld_get_image_header((uint32_t)imageIndex);
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    if (!mh || mh->magic != MH_MAGIC_64) return nil;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h + 1);
    uintptr_t sectionEnd = 0;
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            const struct section_64 *sec = (const struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                if (rva >= (uintptr_t)sec->addr && rva < (uintptr_t)(sec->addr + sec->size)) {
                    sectionEnd = (uintptr_t)(sec->addr + sec->size);
                    break;
                }
            }
        }
        if (sectionEnd || !lc->cmdsize) break;
        cursor += lc->cmdsize;
    }
    if (!sectionEnd || sectionEnd <= rva) return nil;
    size_t available = (size_t)(sectionEnd - rva);
    size_t size = available < 0x100u ? available : 0x100u;
    uintptr_t address = (uintptr_t)((intptr_t)slide + (intptr_t)rva);
    NSString *hex = HFAPortableCodeHex(address, size);
    if (!hex.length) return nil;
    NSDictionary *unit = @{
        @"sourceTarget": imageName,
        @"sourceOffset": offsetString,
        @"sourceSegment": segment ?: @"?",
        @"sourceSection": section ?: @"?",
        @"windowSize": @(size),
        @"windowHex": hex,
        @"exactExtent": @NO
    };
    HFALog("[MATERIALIZE-DATA] identifier=%s image=%s offset=%s segment=%s section=%s size=%zu exact=0\n",
           r->identifier, imageName.UTF8String, offsetString.UTF8String,
           segment.length ? segment.UTF8String : "?",
           section.length ? section.UTF8String : "?", size);
    return unit;
}

static NSDictionary *HFAMaterializedPayload(HFANativeHookRegistration *r,
                                             NSString *rootCodeHex,
                                             uintptr_t startRVA,
                                             uintptr_t endRVA,
                                             NSDictionary *semantic,
                                             NSDictionary *relocation) {
    if (!r || !rootCodeHex.length || !semantic || !relocation) return nil;
    NSMutableArray *codeUnits = [NSMutableArray array];
    NSMutableArray *dataUnits = [NSMutableArray array];
    NSMutableArray *runtimeDependencies = [NSMutableArray array];
    unsigned failedCode = 0, failedData = 0;

    [codeUnits addObject:@{
        @"role": @"replacement",
        @"sourceTarget": [NSString stringWithUTF8String:r->replacementImage],
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @((unsigned long long)(endRVA - startRVA)),
        @"codeHex": rootCodeHex
    }];

    NSArray *helpers = [semantic objectForKey:@"codeDependencies"];
    for (NSDictionary *dep in helpers) {
        NSDictionary *unit = HFAMaterializeCodeUnit(
            r, [dep objectForKey:@"sourceTarget"],
            [dep objectForKey:@"sourceOffset"], @"helperCode");
        if (unit) [codeUnits addObject:unit];
        else failedCode++;
    }

    NSArray *constants = [semantic objectForKey:@"constants"];
    for (NSDictionary *constant in constants) {
        NSDictionary *unit = HFAMaterializeDataWindow(r, constant);
        if (unit) [dataUnits addObject:unit];
        else failedData++;
    }

    NSArray *globals = [semantic objectForKey:@"globals"];
    for (NSDictionary *global in globals) {
        NSString *role = [global objectForKey:@"role"];
        if ([role isEqualToString:@"originalSlot"]) continue;
        [runtimeDependencies addObject:@{
            @"kind": @"sourceRuntimeGlobal",
            @"role": role ?: @"runtimeGlobal",
            @"sourceTarget": [global objectForKey:@"sourceTarget"] ?: @"?",
            @"sourceOffset": [global objectForKey:@"sourceOffset"] ?: @"?"
        }];
    }

    BOOL relocationReady = [[relocation objectForKey:@"ready"] boolValue];
    BOOL materialized = relocationReady && failedCode == 0 && failedData == 0;
    BOOL standalone = materialized && runtimeDependencies.count == 0;
    HFALog("[MATERIALIZE-SUMMARY] identifier=%s codeUnits=%u dataUnits=%u failedCode=%u failedData=%u runtimeDeps=%u relocationReady=%u materialized=%u standalone=%u\n",
           r->identifier, (unsigned)codeUnits.count, (unsigned)dataUnits.count,
           failedCode, failedData, (unsigned)runtimeDependencies.count,
           relocationReady ? 1u : 0u, materialized ? 1u : 0u,
           standalone ? 1u : 0u);

    return @{
        @"format": @"com.hfa.nativehook.materialized/v1",
        @"entryUnit": @0,
        @"codeUnits": codeUnits,
        @"dataUnits": dataUnits,
        @"imports": [semantic objectForKey:@"imports"] ?: @[],
        @"objcBindings": [semantic objectForKey:@"objcBindings"] ?: @[],
        @"globals": globals ?: @[],
        @"internalRelocations": [semantic objectForKey:@"internalRelocations"] ?: @[],
        @"relocationPlan": relocation,
        @"runtimeDependencies": runtimeDependencies,
        @"materialized": @(materialized),
        @"standalone": @(standalone),
        @"exactDataExtents": @NO
    };
}

''' + anchor
if s.count(anchor) != 1:
    raise SystemExit(f"capture anchor expected once, got {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
    BOOL relocationReady = [[relocation objectForKey:@"ready"] boolValue];
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
'''
new = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
    BOOL relocationReady = [[relocation objectForKey:@"ready"] boolValue];
    NSDictionary *materialized = HFAMaterializedPayload(r, codeHex, startRVA,
                                                        endRVA, semantic,
                                                        relocation);
    BOOL materializedReady = [[materialized objectForKey:@"materialized"] boolValue];
    BOOL standaloneReady = [[materialized objectForKey:@"standalone"] boolValue];
    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
'''
if s.count(old) != 1:
    raise SystemExit(f"capture prelude expected once, got {s.count(old)}")
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
        @"materializedPayload": materialized ?: @{},
        @"materializedPayloadReady": @(materializedReady),
        @"portablePayload": @(standaloneReady),
        @"reason": standaloneReady ? @"standalone-materialized" :
            (materializedReady ? @"materialized-source-runtime-dependencies-remain" :
             (relocationReady ? @"materialization-incomplete" :
              @"relocation-plan-incomplete"))
'''
if s.count(old) != 1:
    raise SystemExit(f"capture dictionary expected once, got {s.count(old)}")
s = s.replace(old, new, 1)

old_marker='[HFALearn v1.9.16 RelocationPlanExporter REDO] loaded'
new_marker='[HFALearn v1.9.17 PayloadMaterializer REDO] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"source marker expected once, got {s.count(old_marker)}")
s=s.replace(old_marker,new_marker,1)
patch_path.write_text(s)

l=legacy_path.read_text()
old_marker='[HFALearn UI v1.9.16 RelocationPlanExporter REDO] loaded'
new_marker='[HFALearn UI v1.9.17 PayloadMaterializer REDO] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"legacy marker expected once, got {l.count(old_marker)}")
l=l.replace(old_marker,new_marker,1)
legacy_path.write_text(l)
