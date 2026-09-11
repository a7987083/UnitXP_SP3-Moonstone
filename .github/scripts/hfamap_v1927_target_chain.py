from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()
l = legacy_path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


# v1.9.27:
# - preserve the proven legacy ordinary Patch JSON writer byte-for-byte
# - preserve v1.9.25 iGMM 4/4 menu-definition export
# - preserve v1.9.26 identifier -> native handler discovery
# - distinguish original-slot trampoline entries from final hook targets
# - emulate the narrow ARM64 indirect trampoline pattern used by the current
#   CodeSwap/Jailpatch backend (ADRP/ADD/LDR/ROR/ADD/SUB/BR) using live memory
# - recover generic hook-registration metadata (descriptor + original slot)
# - fix short button handlers so ADRP+ADD global-block references near the end
#   of the function are still inspected
# - no game class names, feature labels, obfuscated ivar names, or sample RVAs
#   are hardcoded

s = replace_once(
    s,
    '[HFALearn v1.9.26 iGMMImplementationResolver] loaded',
    '[HFALearn v1.9.27 iGMMTargetChainResolver] loaded',
    'update core marker',
)
l = replace_once(
    l,
    '[HFALearn UI v1.9.26 iGMMImplementationResolver] loaded',
    '[HFALearn UI v1.9.27 iGMMTargetChainResolver] loaded',
    'update UI marker',
)
l = replace_once(
    l,
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-implementation export=legacy-v1+igmm-v1',
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-target-chain export=legacy-v1+igmm-v1',
    'update dual mode marker',
)

anchor = '''static NSDictionary *HFAIGMM26OriginalDispatch(uint32_t imageIndex,\n'''
helper = r'''static NSDictionary *HFAIGMM27AddressInfo(uintptr_t address) {
    if (!address) return nil;
#if __has_feature(ptrauth_calls)
    address = (uintptr_t)ptrauth_strip((void *)address,
                                       ptrauth_key_function_pointer);
#endif
    Dl_info info = {0};
    if (!dladdr((void *)address, &info) || !info.dli_fbase || !info.dli_fname)
        return nil;
    const char *imageName = HFAIGMM26Base(info.dli_fname);
    uintptr_t rva = address - (uintptr_t)info.dli_fbase;
    NSString *segmentName = @"?";
    NSString *sectionName = @"?";
    int imageIndex = HFAIGMM26ImageIndex(imageName);
    if (imageIndex >= 0) {
        const struct mach_header *mh = _dyld_get_image_header((uint32_t)imageIndex);
        if (mh && mh->magic == MH_MAGIC_64) {
            const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
            const uint8_t *cursor = (const uint8_t *)(h + 1);
            for (uint32_t i = 0; i < h->ncmds; i++) {
                const struct load_command *lc = (const struct load_command *)cursor;
                if (!lc->cmdsize) break;
                if (lc->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *seg =
                        (const struct segment_command_64 *)cursor;
                    if (rva >= (uintptr_t)seg->vmaddr &&
                        rva < (uintptr_t)(seg->vmaddr + seg->vmsize)) {
                        char segbuf[17] = {0};
                        memcpy(segbuf, seg->segname, 16);
                        segmentName = [NSString stringWithUTF8String:segbuf] ?: @"?";
                        const struct section_64 *sec =
                            (const struct section_64 *)(seg + 1);
                        for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
                            if (rva >= (uintptr_t)sec->addr &&
                                rva < (uintptr_t)(sec->addr + sec->size)) {
                                char secbuf[17] = {0};
                                memcpy(secbuf, sec->sectname, 16);
                                sectionName = [NSString stringWithUTF8String:secbuf] ?: @"?";
                                break;
                            }
                        }
                        break;
                    }
                }
                cursor += lc->cmdsize;
            }
        }
    }
    return @{
        @"image": [NSString stringWithUTF8String:imageName],
        @"offset": [NSString stringWithFormat:@"0x%llX",
                    (unsigned long long)rva],
        @"segment": segmentName,
        @"section": sectionName
    };
}

static uintptr_t HFAIGMM27ROR64(uintptr_t value, unsigned amount) {
    amount &= 63u;
    if (!amount) return value;
    return (value >> amount) | (value << (64u - amount));
}

static uintptr_t HFAIGMM27ADR(uintptr_t pc, uint32_t word) {
    if ((word & 0x9F000000u) != 0x10000000u) return 0;
    uint64_t immlo = (word >> 29) & 3u;
    uint64_t immhi = (word >> 5) & 0x7FFFFu;
    int64_t imm = HFAIGMM26SignExtend((immhi << 2) | immlo, 21);
    return (uintptr_t)((intptr_t)pc + imm);
}

static uintptr_t HFAIGMM27EmulateIndirectTrampoline(uintptr_t entry) {
    if (!entry || !HFAReadable(entry, 4)) return 0;
    uintptr_t regs[32] = {0};
    uint8_t valid[32] = {0};
    for (unsigned i = 0; i < 96; i++) {
        uintptr_t pc = entry + (uintptr_t)i * 4u;
        if (!HFAReadable(pc, 4)) break;
        uint32_t w = 0;
        memcpy(&w, (const void *)pc, 4);

        uintptr_t adrp = HFAIGMM26ADRP(pc, w);
        if (adrp) {
            unsigned rd = w & 31u;
            regs[rd] = adrp;
            valid[rd] = 1;
            continue;
        }
        uintptr_t adr = HFAIGMM27ADR(pc, w);
        if (adr) {
            unsigned rd = w & 31u;
            regs[rd] = adr;
            valid[rd] = 1;
            continue;
        }

        if ((w & 0xFF000000u) == 0x91000000u ||
            (w & 0xFF000000u) == 0xD1000000u) {
            unsigned rd = w & 31u;
            unsigned rn = (w >> 5) & 31u;
            uintptr_t imm = (uintptr_t)((w >> 10) & 0xFFFu);
            if ((w >> 22) & 1u) imm <<= 12;
            if (valid[rn]) {
                regs[rd] = ((w & 0xFF000000u) == 0x91000000u) ?
                    regs[rn] + imm : regs[rn] - imm;
                valid[rd] = 1;
            } else {
                valid[rd] = 0;
            }
            continue;
        }

        if ((w & 0xFFC00000u) == 0xF9400000u) {
            unsigned rt = w & 31u;
            unsigned rn = (w >> 5) & 31u;
            uintptr_t imm = (uintptr_t)((w >> 10) & 0xFFFu) << 3;
            if (valid[rn]) {
                uintptr_t p = regs[rn] + imm;
                if (HFAReadable(p, sizeof(uintptr_t))) {
                    uintptr_t value = 0;
                    memcpy(&value, (const void *)p, sizeof(value));
                    regs[rt] = value;
                    valid[rt] = 1;
                } else {
                    valid[rt] = 0;
                }
            } else {
                valid[rt] = 0;
            }
            continue;
        }

        if ((w & 0xFFE00000u) == 0x93C00000u) {
            unsigned rd = w & 31u;
            unsigned rn = (w >> 5) & 31u;
            unsigned rm = (w >> 16) & 31u;
            unsigned amount = (w >> 10) & 0x3Fu;
            if (rn == rm && valid[rn]) {
                regs[rd] = HFAIGMM27ROR64(regs[rn], amount);
                valid[rd] = 1;
            } else {
                valid[rd] = 0;
            }
            continue;
        }

        if ((w & 0xFFFFFC1Fu) == 0xD61F0000u) {
            unsigned rn = (w >> 5) & 31u;
            if (!valid[rn] || !regs[rn]) return 0;
            uintptr_t target = regs[rn];
#if __has_feature(ptrauth_calls)
            target = (uintptr_t)ptrauth_strip((void *)target,
                                              ptrauth_key_function_pointer);
#endif
            return target;
        }
    }
    return 0;
}

static NSString *HFAIGMM27HexBytes(uintptr_t address, size_t length) {
    if (!address || !length || length > 64 || !HFAReadable(address, length))
        return nil;
    const uint8_t *bytes = (const uint8_t *)address;
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (size_t i = 0; i < length; i++) [hex appendFormat:@"%02X", bytes[i]];
    return hex;
}

static int HFAIGMM27PairAddress(uintptr_t text, size_t words, size_t index,
                                unsigned reg, uintptr_t *addressOut) {
    if (index >= words) return 0;
    uintptr_t pc = text + index * 4;
    uint32_t first = 0;
    memcpy(&first, (const void *)pc, 4);
    uintptr_t page = HFAIGMM26ADRP(pc, first);
    if (!page || (first & 31u) != reg) return 0;
    for (size_t ahead = 1; ahead <= 4 && index + ahead < words; ahead++) {
        uint32_t add = 0;
        memcpy(&add, (const void *)(text + (index + ahead) * 4), 4);
        unsigned rn = 0;
        uintptr_t imm = 0;
        if (!HFAIGMM26ADDImmediate(add, &rn, &imm)) continue;
        if (rn != reg || (add & 31u) != reg) continue;
        if (addressOut) *addressOut = page + imm;
        return 1;
    }
    return 0;
}

static NSDictionary *HFAIGMM27RegistrationMetadata(const char *imageName,
                                                    uintptr_t handlerRVA) {
    int imageIndex = HFAIGMM26ImageIndex(imageName);
    if (imageIndex < 0 || !handlerRVA) return nil;
    uintptr_t text = 0, textRVA = 0;
    size_t textSize = 0;
    if (!HFAIGMM26Section((uint32_t)imageIndex, "__text", &text, &textRVA,
                          &textSize) || !HFAReadable(text, textSize)) return nil;
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t handlerAddress =
        (uintptr_t)((intptr_t)slide + (intptr_t)handlerRVA);
    size_t words = textSize / 4;
    for (size_t i = 0; i < words; i++) {
        uint32_t w = 0;
        uintptr_t pc = text + i * 4;
        memcpy(&w, (const void *)pc, 4);
        if ((w & 31u) != 3u || HFAIGMM27ADR(pc, w) != handlerAddress)
            continue;

        uintptr_t descriptor = 0, slot = 0;
        size_t back = i > 16 ? i - 16 : 0;
        for (size_t j = i; j-- > back;) {
            uintptr_t candidate = 0;
            if (!HFAIGMM27PairAddress(text, words, j, 2, &candidate)) continue;
            NSDictionary *info = HFAIGMM27AddressInfo(candidate);
            if ([[info objectForKey:@"section"] isEqualToString:@"__data"]) {
                descriptor = candidate;
                break;
            }
        }
        for (size_t j = i + 1; j < words && j <= i + 8; j++) {
            uintptr_t candidate = 0;
            if (HFAIGMM27PairAddress(text, words, j, 4, &candidate)) {
                slot = candidate;
                break;
            }
        }
        if (!descriptor && !slot) continue;

        NSMutableDictionary *registration = [NSMutableDictionary dictionary];
        registration[@"site"] = @{
            @"image": [NSString stringWithUTF8String:imageName],
            @"offset": [NSString stringWithFormat:@"0x%llX",
                       (unsigned long long)(textRVA + i * 4)]
        };
        if (descriptor) {
            NSMutableDictionary *d =
                [[HFAIGMM27AddressInfo(descriptor) ?: @{} mutableCopy] mutableCopy];
            NSString *raw = HFAIGMM27HexBytes(descriptor, 32);
            if (raw) d[@"headerHex"] = raw;
            registration[@"descriptor"] = d;
        }
        if (slot) {
            NSDictionary *si = HFAIGMM27AddressInfo(slot);
            if (si) registration[@"originalSlot"] = si;
        }
        HFALog("[IGMM-IMPL-REGISTRATION] handler=%s+0x%llX site=0x%llX descriptor=%s slot=%s\n",
               imageName, (unsigned long long)handlerRVA,
               (unsigned long long)(textRVA + i * 4),
               [[[registration objectForKey:@"descriptor"] objectForKey:@"offset"] UTF8String] ?: "?",
               [[[registration objectForKey:@"originalSlot"] objectForKey:@"offset"] UTF8String] ?: "?");
        return registration;
    }
    return nil;
}

''' + anchor
s = replace_once(s, anchor, helper, 'insert v1.9.27 target-chain helpers')

old = r'''                if (target && dladdr((void *)target, &info) &&
                    info.dli_fbase && info.dli_fname) {
                    uintptr_t rva = target - (uintptr_t)info.dli_fbase;
                    result[@"target"] = @{
                        @"image": [NSString stringWithUTF8String:
                            HFAIGMM26Base(info.dli_fname)],
                        @"offset": [NSString stringWithFormat:@"0x%llX",
                            (unsigned long long)rva]
                    };
                    HFALog("[IGMM-IMPL-ORIGINAL] handler=%s+0x%llX slot=%s+%s target=%s+0x%llX\n",
                           imageName, (unsigned long long)startRVA,
                           imageName, slotOffset.UTF8String,
                           HFAIGMM26Base(info.dli_fname),
                           (unsigned long long)rva);
                } else {
'''
new = r'''                if (target && dladdr((void *)target, &info) &&
                    info.dli_fbase && info.dli_fname) {
                    NSDictionary *direct = HFAIGMM27AddressInfo(target);
                    uintptr_t finalTarget = 0;
                    NSString *directSection = [direct objectForKey:@"section"];
                    if (direct && ![directSection isEqualToString:@"__text"])
                        finalTarget = HFAIGMM27EmulateIndirectTrampoline(target);
                    NSDictionary *finalInfo =
                        (finalTarget && finalTarget != target) ?
                            HFAIGMM27AddressInfo(finalTarget) : nil;
                    if (finalInfo) {
                        result[@"trampoline"] = direct;
                        result[@"target"] = finalInfo;
                        result[@"targetResolution"] = @"live-indirect-trampoline";
                        HFALog("[IGMM-IMPL-TRAMPOLINE] handler=%s+0x%llX entry=%s+%s section=%s final=%s+%s\n",
                               imageName, (unsigned long long)startRVA,
                               [[direct objectForKey:@"image"] UTF8String] ?: "?",
                               [[direct objectForKey:@"offset"] UTF8String] ?: "?",
                               [[direct objectForKey:@"section"] UTF8String] ?: "?",
                               [[finalInfo objectForKey:@"image"] UTF8String] ?: "?",
                               [[finalInfo objectForKey:@"offset"] UTF8String] ?: "?");
                    } else if (direct) {
                        result[@"target"] = direct;
                        result[@"targetResolution"] = @"direct-slot-target";
                    }
                    NSDictionary *loggedTarget = [result objectForKey:@"target"];
                    HFALog("[IGMM-IMPL-ORIGINAL] handler=%s+0x%llX slot=%s+%s target=%s+%s resolution=%s\n",
                           imageName, (unsigned long long)startRVA,
                           imageName, slotOffset.UTF8String,
                           [[loggedTarget objectForKey:@"image"] UTF8String] ?: "?",
                           [[loggedTarget objectForKey:@"offset"] UTF8String] ?: "?",
                           [[result objectForKey:@"targetResolution"] UTF8String] ?: "?");
                } else {
'''
s = replace_once(s, old, new, 'follow original-slot trampoline')

old = r'''    NSDictionary *dispatch =
        HFAIGMM26OriginalDispatch((uint32_t)imageIndex, imageName,
                                  startRVA, endRVA);
    if (dispatch) [impl addEntriesFromDictionary:dispatch];
    HFALog("[IGMM-IMPL-XREF] identifier=%s handler=%s+0x%llX end=0x%llX xrefs=%u\n",
'''
new = r'''    NSDictionary *dispatch =
        HFAIGMM26OriginalDispatch((uint32_t)imageIndex, imageName,
                                  startRVA, endRVA);
    if (dispatch) [impl addEntriesFromDictionary:dispatch];
    NSDictionary *registration =
        HFAIGMM27RegistrationMetadata(imageName, startRVA);
    if (registration) impl[@"registration"] = registration;
    HFALog("[IGMM-IMPL-XREF] identifier=%s handler=%s+0x%llX end=0x%llX xrefs=%u\n",
'''
s = replace_once(s, old, new, 'attach registration metadata')

# v1.9.26 required at least 20 bytes after the current scan position, which
# skipped an ADRP+ADD pair near the end of a short direct block. Scan the last
# complete instruction too; the inner look-ahead still performs strict bounds.
old = '    for (size_t off = 0; off + 20 <= size; off += 4) {\n'
new = '    for (size_t off = 0; off + 4 <= size; off += 4) {\n'
if s.count(old) < 1:
    raise SystemExit('short-block scan anchor not found')
# Only the nested-block resolver has the nearby `candidate + 16` block layout.
needle = 'static NSDictionary *HFAIGMM26NestedBlockImplementation('
pos = s.index(needle)
pre, tail = s[:pos], s[pos:]
if tail.count(old) != 1:
    raise SystemExit(f'nested block loop expected 1 match, got {tail.count(old)}')
tail = tail.replace(old, new, 1)
s = pre + tail

patch_path.write_text(s)
legacy_path.write_text(l)
