from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# v1.9.15: turn the raw v1.9.14 portable reference list into a semantic
# dependency table using Mach-O metadata and ObjC runtime information. The raw
# references remain in the package as evidence. No sample-specific feature id,
# image name, symbol, selector, class or RVA is hardcoded.

anchor = r'''static NSDictionary *HFACapturePortableNativeHook(HFANativeHookRegistration *r) {
'''
helper = r'''
static NSString *HFAPortableSymbolForIndirectSection(const char *imageName,
                                                      uintptr_t rva) {
    if (!imageName || !*imageName) return nil;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return nil;
    const char *path = _dyld_get_image_name((uint32_t)imageIndex);
    if (!path || !*path) return nil;
    NSData *imageData = [NSData dataWithContentsOfFile:
        [NSString stringWithUTF8String:path]];
    if (!imageData || imageData.length < sizeof(struct mach_header_64)) return nil;

    const uint8_t *bytes = (const uint8_t *)imageData.bytes;
    size_t length = imageData.length;
    const struct mach_header_64 *h = (const struct mach_header_64 *)bytes;
    if (h->magic != MH_MAGIC_64 || sizeof(*h) + h->sizeofcmds > length) return nil;

    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const struct section_64 *matched = NULL;
    const uint8_t *cursor = bytes + sizeof(*h);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        if ((size_t)(cursor - bytes) + sizeof(struct load_command) > length) return nil;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (!lc->cmdsize || (size_t)(cursor - bytes) + lc->cmdsize > length) return nil;
        if (lc->cmd == LC_SYMTAB && lc->cmdsize >= sizeof(struct symtab_command))
            symtab = (const struct symtab_command *)cursor;
        else if (lc->cmd == LC_DYSYMTAB && lc->cmdsize >= sizeof(struct dysymtab_command))
            dysymtab = (const struct dysymtab_command *)cursor;
        else if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if (lc->cmdsize >= sizeof(*seg) + (size_t)seg->nsects * sizeof(struct section_64)) {
                const struct section_64 *sec = (const struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                    if (rva >= (uintptr_t)sec->addr && rva < (uintptr_t)(sec->addr + sec->size)) {
                        uint32_t type = sec->flags & SECTION_TYPE;
                        if (type == S_SYMBOL_STUBS || type == S_LAZY_SYMBOL_POINTERS ||
                            type == S_NON_LAZY_SYMBOL_POINTERS ||
                            type == S_THREAD_LOCAL_VARIABLE_POINTERS)
                            matched = sec;
                    }
                }
            }
        }
        cursor += lc->cmdsize;
    }
    if (!matched || !symtab || !dysymtab) return nil;
    if ((uint64_t)symtab->symoff + (uint64_t)symtab->nsyms * sizeof(struct nlist_64) > length ||
        (uint64_t)symtab->stroff + symtab->strsize > length ||
        (uint64_t)dysymtab->indirectsymoff +
            ((uint64_t)dysymtab->nindirectsyms * sizeof(uint32_t)) > length)
        return nil;

    uint64_t stride = 0;
    uint32_t type = matched->flags & SECTION_TYPE;
    if (type == S_SYMBOL_STUBS) stride = matched->reserved2;
    else stride = sizeof(uintptr_t);
    if (!stride || rva < matched->addr) return nil;
    uint64_t element = (rva - matched->addr) / stride;
    if (element >= (matched->size / stride)) return nil;
    uint64_t indirectIndex = (uint64_t)matched->reserved1 + element;
    if (indirectIndex >= dysymtab->nindirectsyms) return nil;

    const uint32_t *indirect =
        (const uint32_t *)(bytes + dysymtab->indirectsymoff);
    uint32_t symbolIndex = indirect[indirectIndex];
    if (symbolIndex == INDIRECT_SYMBOL_ABS ||
        symbolIndex == INDIRECT_SYMBOL_LOCAL ||
        symbolIndex == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS) ||
        symbolIndex >= symtab->nsyms)
        return nil;

    const struct nlist_64 *symbols =
        (const struct nlist_64 *)(bytes + symtab->symoff);
    uint32_t stringIndex = symbols[symbolIndex].n_un.n_strx;
    if (!stringIndex || stringIndex >= symtab->strsize) return nil;
    const char *name = (const char *)(bytes + symtab->stroff + stringIndex);
    size_t remain = symtab->strsize - stringIndex;
    if (!memchr(name, 0, remain)) return nil;
    if (name[0] == '_') name++;
    return [NSString stringWithUTF8String:name];
}

static NSString *HFAPortableSelectorName(const char *imageName, uintptr_t rva) {
    if (!imageName || !*imageName || !rva) return nil;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t address = (uintptr_t)((intptr_t)slide + (intptr_t)rva);
    if (!HFAReadable(address, sizeof(uintptr_t))) return nil;
    uintptr_t value = 0;
    memcpy(&value, (const void *)address, sizeof(value));
    value = HFAStripCodePointer(value);
    if (!value) return nil;
    const char *name = sel_getName((SEL)value);
    return name && *name ? [NSString stringWithUTF8String:name] : nil;
}

static NSString *HFAPortableClassName(const char *imageName, uintptr_t rva) {
    if (!imageName || !*imageName || !rva) return nil;
    int imageIndex = HFAImageIndexForName(imageName);
    if (imageIndex < 0) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t address = (uintptr_t)((intptr_t)slide + (intptr_t)rva);
    if (!HFAReadable(address, sizeof(uintptr_t))) return nil;
    uintptr_t value = 0;
    memcpy(&value, (const void *)address, sizeof(value));
    value = HFAStripCodePointer(value);
    if (!value) return nil;
    Class cls = (__bridge Class)(void *)value;
    const char *name = class_getName(cls);
    return name && *name ? [NSString stringWithUTF8String:name] : nil;
}

static int HFAPortableArrayContainsDictionary(NSArray *array,
                                              NSString *key,
                                              NSString *value) {
    if (!array || !key.length || !value.length) return 0;
    for (NSDictionary *entry in array) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        id current = [entry objectForKey:key];
        if ([current isKindOfClass:[NSString class]] &&
            [(NSString *)current isEqualToString:value])
            return 1;
    }
    return 0;
}

static NSDictionary *HFAPortableSemanticDependencies(
    HFANativeHookRegistration *r, NSArray *refs) {
    if (!r || !refs) return nil;
    NSMutableArray *imports = [NSMutableArray array];
    NSMutableArray *objcBindings = [NSMutableArray array];
    NSMutableArray *globals = [NSMutableArray array];
    NSMutableArray *codeDependencies = [NSMutableArray array];
    NSMutableArray *constants = [NSMutableArray array];
    NSMutableArray *internalRelocations = [NSMutableArray array];

    for (NSDictionary *ref in refs) {
        if (![ref isKindOfClass:[NSDictionary class]]) continue;
        NSString *targetImage = [ref objectForKey:@"target"];
        NSString *targetOffset = [ref objectForKey:@"targetOffset"];
        NSString *segment = [ref objectForKey:@"targetSegment"];
        NSString *section = [ref objectForKey:@"targetSection"];
        NSString *kind = [ref objectForKey:@"kind"];
        NSNumber *internalValue = [ref objectForKey:@"internal"];
        if (![targetImage isKindOfClass:[NSString class]] ||
            ![targetOffset isKindOfClass:[NSString class]] ||
            ![section isKindOfClass:[NSString class]] ||
            ![kind isKindOfClass:[NSString class]])
            continue;
        uintptr_t targetRVA =
            (uintptr_t)strtoull(targetOffset.UTF8String, NULL, 16);

        if ([internalValue boolValue]) {
            [internalRelocations addObject:@{
                @"kind": kind,
                @"instructionOffset": [ref objectForKey:@"instructionOffset"] ?: @"?",
                @"targetOffset": targetOffset
            }];
            continue;
        }

        if ([section isEqualToString:@"__stubs"] ||
            [section isEqualToString:@"__got"] ||
            [section isEqualToString:@"__la_symbol_ptr"] ||
            [section isEqualToString:@"__nl_symbol_ptr"]) {
            NSString *symbol = HFAPortableSymbolForIndirectSection(
                targetImage.UTF8String, targetRVA);
            if (symbol.length &&
                !HFAPortableArrayContainsDictionary(imports, @"symbol", symbol)) {
                [imports addObject:@{
                    @"symbol": symbol,
                    @"sourceTarget": targetImage,
                    @"sourceOffset": targetOffset,
                    @"sourceSection": section
                }];
                HFALog("[SEMANTIC-IMPORT] identifier=%s symbol=%s source=%s+%s section=%s\n",
                       r->identifier, symbol.UTF8String,
                       targetImage.UTF8String, targetOffset.UTF8String,
                       section.UTF8String);
            }
            continue;
        }

        if ([section isEqualToString:@"__objc_selrefs"]) {
            NSString *name = HFAPortableSelectorName(targetImage.UTF8String,
                                                      targetRVA);
            if (name.length &&
                !HFAPortableArrayContainsDictionary(objcBindings, @"name", name)) {
                [objcBindings addObject:@{
                    @"kind": @"selector",
                    @"name": name,
                    @"sourceTarget": targetImage,
                    @"sourceOffset": targetOffset
                }];
                HFALog("[SEMANTIC-OBJC] identifier=%s kind=selector name=%s source=%s+%s\n",
                       r->identifier, name.UTF8String, targetImage.UTF8String,
                       targetOffset.UTF8String);
            }
            continue;
        }

        if ([section isEqualToString:@"__objc_classrefs"]) {
            NSString *name = HFAPortableClassName(targetImage.UTF8String,
                                                   targetRVA);
            if (name.length &&
                !HFAPortableArrayContainsDictionary(objcBindings, @"name", name)) {
                [objcBindings addObject:@{
                    @"kind": @"class",
                    @"name": name,
                    @"sourceTarget": targetImage,
                    @"sourceOffset": targetOffset
                }];
                HFALog("[SEMANTIC-OBJC] identifier=%s kind=class name=%s source=%s+%s\n",
                       r->identifier, name.UTF8String, targetImage.UTF8String,
                       targetOffset.UTF8String);
            }
            continue;
        }

        if ([section isEqualToString:@"__common"] ||
            [section isEqualToString:@"__bss"] ||
            [section isEqualToString:@"__data"]) {
            NSString *slotImage = r->slotImage[0] ?
                [NSString stringWithUTF8String:r->slotImage] : nil;
            NSString *role = (targetRVA == r->slotRVA &&
                              slotImage.length &&
                              [targetImage isEqualToString:slotImage]) ?
                              @"originalSlot" : @"writableGlobal";
            if (!HFAPortableArrayContainsDictionary(globals,
                                                     @"sourceOffset",
                                                     targetOffset)) {
                [globals addObject:@{
                    @"role": role,
                    @"sourceTarget": targetImage,
                    @"sourceOffset": targetOffset,
                    @"sourceSection": section
                }];
                HFALog("[SEMANTIC-GLOBAL] identifier=%s role=%s source=%s+%s section=%s\n",
                       r->identifier, role.UTF8String,
                       targetImage.UTF8String, targetOffset.UTF8String,
                       section.UTF8String);
            }
            continue;
        }

        if ([section isEqualToString:@"__text"]) {
            if (!HFAPortableArrayContainsDictionary(codeDependencies,
                                                     @"sourceOffset",
                                                     targetOffset)) {
                [codeDependencies addObject:@{
                    @"role": @"helperCode",
                    @"sourceTarget": targetImage,
                    @"sourceOffset": targetOffset,
                    @"referenceKind": kind
                }];
                HFALog("[SEMANTIC-CODE] identifier=%s source=%s+%s kind=%s\n",
                       r->identifier, targetImage.UTF8String,
                       targetOffset.UTF8String, kind.UTF8String);
            }
            continue;
        }

        if ([section containsString:@"const"] ||
            [section isEqualToString:@"__cstring"] ||
            [section containsString:@"literal"]) {
            if (!HFAPortableArrayContainsDictionary(constants,
                                                     @"sourceOffset",
                                                     targetOffset)) {
                [constants addObject:@{
                    @"sourceTarget": targetImage,
                    @"sourceOffset": targetOffset,
                    @"sourceSegment": segment ?: @"?",
                    @"sourceSection": section
                }];
                HFALog("[SEMANTIC-CONST] identifier=%s source=%s+%s segment=%s section=%s\n",
                       r->identifier, targetImage.UTF8String,
                       targetOffset.UTF8String,
                       segment.length ? segment.UTF8String : "?",
                       section.UTF8String);
            }
            continue;
        }
    }

    HFALog("[SEMANTIC-SUMMARY] identifier=%s imports=%u objcBindings=%u globals=%u codeDependencies=%u constants=%u internalRelocations=%u\n",
           r->identifier, (unsigned)imports.count,
           (unsigned)objcBindings.count, (unsigned)globals.count,
           (unsigned)codeDependencies.count, (unsigned)constants.count,
           (unsigned)internalRelocations.count);

    return @{
        @"imports": imports,
        @"objcBindings": objcBindings,
        @"globals": globals,
        @"codeDependencies": codeDependencies,
        @"constants": constants,
        @"internalRelocations": internalRelocations
    };
}

''' + anchor

if s.count(anchor) != 1:
    raise SystemExit(f"expected capture anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

old = r'''    NSMutableDictionary *capture = [NSMutableDictionary dictionaryWithDictionary:@{
        @"status": @"captured",
        @"functionStart": HFANativeOffsetString(startRVA),
        @"functionEnd": HFANativeOffsetString(endRVA),
        @"functionSize": @(size),
        @"boundarySource": [NSString stringWithUTF8String:
            boundarySource ? boundarySource : "?"],
        @"references": refs,
        @"referenceCount": @((unsigned)refs.count),
        @"externalReferenceCount": @(externalRefs),
        @"portablePayload": @NO,
        @"reason": @"relocations-required"
    }];
'''
new = r'''    NSDictionary *semantic = HFAPortableSemanticDependencies(r, refs);
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
if s.count(old) != 1:
    raise SystemExit(f"expected capture dictionary once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.9.14 FunctionStartsFileFallback] loaded'
new_marker = '[HFALearn v1.9.15 SemanticDependencyResolver] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.14 source marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.9.14 FunctionStartsFileFallback] loaded'
new_marker = '[HFALearn UI v1.9.15 SemanticDependencyResolver] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected v1.9.14 legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
