from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.16-redo: v1.9.15 already resolves semantic dependency classes, but the
# portable capture still inherits v1.9.13's hard-coded portablePayload=NO path.
# Build an explicit per-instruction relocation plan and only mark the plan ready
# when every external PC-relative reference is resolved to a semantic binding.
# This does NOT claim the payload is self-contained yet; it separates
# "relocation plan complete" from "portable payload materialized".

anchor = r'''static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
'''
helper = r'''
static NSDictionary *HFAPortableRelocationPlan(HFANativeHookRegistration *r,
                                               NSArray *refs) {
    if (!r || !refs) return nil;
    NSMutableArray *plan = [NSMutableArray array];
    NSMutableArray *unresolved = [NSMutableArray array];
    unsigned external = 0, resolved = 0;

    for (NSDictionary *ref in refs) {
        if (![ref isKindOfClass:[NSDictionary class]]) continue;
        if ([[ref objectForKey:@"internal"] boolValue]) continue;
        external++;

        NSString *targetImage = [ref objectForKey:@"target"];
        NSString *targetOffset = [ref objectForKey:@"targetOffset"];
        NSString *segment = [ref objectForKey:@"targetSegment"];
        NSString *section = [ref objectForKey:@"targetSection"];
        NSString *kind = [ref objectForKey:@"kind"];
        NSString *instructionOffset = [ref objectForKey:@"instructionOffset"];
        if (![targetImage isKindOfClass:[NSString class]] ||
            ![targetOffset isKindOfClass:[NSString class]] ||
            ![section isKindOfClass:[NSString class]] ||
            ![kind isKindOfClass:[NSString class]] ||
            ![instructionOffset isKindOfClass:[NSString class]]) {
            [unresolved addObject:ref];
            continue;
        }

        uintptr_t targetRVA =
            (uintptr_t)strtoull(targetOffset.UTF8String, NULL, 16);
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
            @"instructionOffset": instructionOffset,
            @"kind": kind,
            @"sourceTarget": targetImage,
            @"sourceOffset": targetOffset,
            @"sourceSegment": segment ?: @"?",
            @"sourceSection": section
        }];
        BOOL ok = NO;

        if ([section isEqualToString:@"__stubs"] ||
            [section isEqualToString:@"__got"] ||
            [section isEqualToString:@"__la_symbol_ptr"] ||
            [section isEqualToString:@"__nl_symbol_ptr"]) {
            NSString *symbol = HFAPortableSymbolForIndirectSection(
                targetImage.UTF8String, targetRVA);
            if (symbol.length) {
                entry[@"bindingKind"] = @"import";
                entry[@"symbol"] = symbol;
                ok = YES;
            }
        } else if ([section isEqualToString:@"__objc_selrefs"]) {
            NSString *name = HFAPortableSelectorName(targetImage.UTF8String,
                                                      targetRVA);
            if (name.length) {
                entry[@"bindingKind"] = @"objcSelector";
                entry[@"name"] = name;
                ok = YES;
            }
        } else if ([section isEqualToString:@"__objc_classrefs"]) {
            NSString *name = HFAPortableClassName(targetImage.UTF8String,
                                                   targetRVA);
            if (name.length) {
                entry[@"bindingKind"] = @"objcClass";
                entry[@"name"] = name;
                ok = YES;
            }
        } else if ([section isEqualToString:@"__common"] ||
                   [section isEqualToString:@"__bss"] ||
                   [section isEqualToString:@"__data"]) {
            NSString *slotImage = r->slotImage[0] ?
                [NSString stringWithUTF8String:r->slotImage] : nil;
            BOOL originalSlot = targetRVA == r->slotRVA && slotImage.length &&
                [targetImage isEqualToString:slotImage];
            entry[@"bindingKind"] = @"writableGlobal";
            entry[@"role"] = originalSlot ? @"originalSlot" : @"runtimeGlobal";
            ok = YES;
        } else if ([section isEqualToString:@"__text"]) {
            entry[@"bindingKind"] = @"helperCode";
            ok = YES;
        } else if ([section containsString:@"const"] ||
                   [section isEqualToString:@"__cstring"] ||
                   [section containsString:@"literal"]) {
            entry[@"bindingKind"] = @"constant";
            ok = YES;
        }

        if (ok) {
            [plan addObject:entry];
            resolved++;
            HFALog("[RELOCATION-PLAN] identifier=%s instruction=%s kind=%s binding=%s source=%s+%s\n",
                   r->identifier,
                   instructionOffset.UTF8String,
                   kind.UTF8String,
                   [[entry objectForKey:@"bindingKind"] UTF8String],
                   targetImage.UTF8String,
                   targetOffset.UTF8String);
        } else {
            [unresolved addObject:entry];
            HFALog("[RELOCATION-UNRESOLVED] identifier=%s instruction=%s kind=%s source=%s+%s segment=%s section=%s\n",
                   r->identifier,
                   instructionOffset.UTF8String,
                   kind.UTF8String,
                   targetImage.UTF8String,
                   targetOffset.UTF8String,
                   segment.length ? segment.UTF8String : "?",
                   section.UTF8String);
        }
    }

    BOOL ready = external > 0 && resolved == external && unresolved.count == 0;
    HFALog("[RELOCATION-SUMMARY] identifier=%s external=%u resolved=%u unresolved=%u ready=%u\n",
           r->identifier, external, resolved, (unsigned)unresolved.count,
           ready ? 1u : 0u);

    return @{
        @"entries": plan,
        @"externalReferenceCount": @(external),
        @"resolvedReferenceCount": @(resolved),
        @"unresolvedReferenceCount": @((unsigned)unresolved.count),
        @"unresolved": unresolved,
        @"ready": @(ready)
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
    NSDictionary *relocation = HFAPortableRelocationPlan(r, refs);
    BOOL relocationReady = [[relocation objectForKey:@"ready"] boolValue];
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
        @"relocationPlan": relocation ?: @{},
        @"relocationPlanReady": @(relocationReady),
        @"portablePayload": @NO,
        @"reason": relocationReady ?
            @"relocation-plan-ready-payload-materialization-pending" :
            @"relocation-plan-incomplete"
    }];
'''
if s.count(old) != 1:
    raise SystemExit(f"expected v1.9.15 capture dictionary once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.15 SemanticDependencyResolver] loaded'
new_marker = '[HFALearn v1.9.16 RelocationPlanExporter REDO] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.15 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.15 SemanticDependencyResolver] loaded'
new_marker = '[HFALearn UI v1.9.16 RelocationPlanExporter REDO] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.15 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
