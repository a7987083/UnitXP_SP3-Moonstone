from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

# Add a small dedup table for action/caller code-path probes.
anchor = "static unsigned gExecutedEvent;\n"
insert = """static unsigned gExecutedEvent;\n\ntypedef struct {\n    uintptr_t address;\n    char identifier[96];\n    char kind[16];\n} HFAPathProbeSite;\nstatic HFAPathProbeSite gPathProbeSites[128];\nstatic unsigned gPathProbeSiteCount;\n"""
if s.count(anchor) != 1:
    raise SystemExit(f"expected global anchor once, found {s.count(anchor)}")
s = s.replace(anchor, insert, 1)

# Insert generalized ARM64 path decoder after trampoline helpers and before hook-target logging.
anchor = "static void HFAEmitHookTarget(HFAStateSite *site, uintptr_t caller) {\n"
helper = r'''static int HFAIdentifierIsCustomSwitch(const char *identifier) {
    HFAFeatureDefinition *definition = HFAFeatureDefinitionForIdentifier(identifier);
    return definition && definition->type[0] &&
           strcmp(definition->type, "customSwitch") == 0;
}

static int HFAPathProbeSeen(const char *kind, const char *identifier,
                            uintptr_t address) {
    if (!kind || !identifier || !address) return 1;
    for (unsigned i = 0; i < gPathProbeSiteCount; i++) {
        HFAPathProbeSite *site = &gPathProbeSites[i];
        if (site->address == address && strcmp(site->kind, kind) == 0 &&
            strcmp(site->identifier, identifier) == 0)
            return 1;
    }
    if (gPathProbeSiteCount >= 128) return 1;
    HFAPathProbeSite *site = &gPathProbeSites[gPathProbeSiteCount++];
    memset(site, 0, sizeof(*site));
    site->address = address;
    snprintf(site->kind, sizeof(site->kind), "%s", kind);
    snprintf(site->identifier, sizeof(site->identifier), "%s", identifier);
    return 0;
}

static uintptr_t HFAResolveBranchStub(uintptr_t target) {
    if (!target || !HFAReadable(target, 16)) return target;
    uint32_t w0 = *(const uint32_t *)target;
    uint32_t w1 = *(const uint32_t *)(target + 4);
    uint32_t w2 = *(const uint32_t *)(target + 8);

    if ((w0 & 0xFC000000u) == 0x14000000u) {
        int64_t displacement = HFASignExtend(w0 & 0x03FFFFFFu, 26) << 2;
        return target + (uintptr_t)displacement;
    }

    if ((w0 & 0x9F000000u) == 0x90000000u &&
        (w1 & 0xFFC00000u) == 0xF9400000u &&
        (w2 & 0xFFFFFC1Fu) == 0xD61F0000u) {
        unsigned adrpReg = w0 & 31u;
        unsigned ldrReg = w1 & 31u;
        unsigned ldrBase = (w1 >> 5) & 31u;
        unsigned brReg = (w2 >> 5) & 31u;
        if (adrpReg == ldrBase && ldrReg == brReg) {
            uint64_t immediate = (((uint64_t)(w0 >> 5) & 0x7FFFFu) << 2) |
                                 ((w0 >> 29) & 3u);
            int64_t pageDelta = HFASignExtend(immediate, 21) << 12;
            uintptr_t page = (target & ~(uintptr_t)0xFFFu) +
                             (uintptr_t)pageDelta;
            uintptr_t slot = page + (((w1 >> 10) & 0xFFFu) * 8u);
            if (HFAReadable(slot, sizeof(uintptr_t)))
                return HFAStripCodePointer(*(const uintptr_t *)slot);
        }
    }

    if ((w0 & 0xFF000000u) == 0x58000000u &&
        (w1 & 0xFFFFFC1Fu) == 0xD61F0000u) {
        unsigned ldrReg = w0 & 31u;
        unsigned brReg = (w1 >> 5) & 31u;
        if (ldrReg == brReg) {
            int64_t displacement = HFASignExtend((w0 >> 5) & 0x7FFFFu, 19) << 2;
            uintptr_t literal = target + (uintptr_t)displacement;
            if (HFAReadable(literal, sizeof(uintptr_t)))
                return HFAStripCodePointer(*(const uintptr_t *)literal);
        }
    }
    return target;
}

static void HFAEmitObjCContext(const char *kind, const char *identifier,
                               uintptr_t pc, uintptr_t base) {
    uint32_t words[8] = {0};
    uintptr_t start = pc >= 0x20u ? pc - 0x20u : pc;
    for (unsigned i = 0; i < 8; i++) {
        uintptr_t p = start + (uintptr_t)i * 4u;
        if (HFAReadable(p, 4)) memcpy(&words[i], (const void *)p, 4);
    }
    HFALog("[CUSTOM-OBJC-CONTEXT] kind=%s identifier=%s pcRVA=%llX words=%08X/%08X/%08X/%08X/%08X/%08X/%08X/%08X\n",
           kind, identifier, (unsigned long long)(pc - base),
           words[0], words[1], words[2], words[3],
           words[4], words[5], words[6], words[7]);
}

static void HFAProbeCodePath(const char *kind, const char *identifier,
                             uintptr_t center, uintptr_t before,
                             uintptr_t after) {
    if (!kind || !identifier || !*identifier || !center ||
        !HFAIdentifierIsCustomSwitch(identifier) ||
        HFAPathProbeSeen(kind, identifier, center))
        return;

    Dl_info centerInfo = {0};
    if (!dladdr((void *)center, &centerInfo) || !centerInfo.dli_fbase) return;
    uintptr_t base = (uintptr_t)centerInfo.dli_fbase;
    uintptr_t start = center > before ? center - before : center;
    uintptr_t end = center + after;

    HFALog("[CUSTOM-PATH-BEGIN] kind=%s identifier=%s image=%s center=%p centerRVA=%llX before=%llX after=%llX\n",
           kind, identifier,
           centerInfo.dli_fname ? HFABase(centerInfo.dli_fname) : "?",
           (void *)center, (unsigned long long)(center - base),
           (unsigned long long)before, (unsigned long long)after);

    for (uintptr_t row = start; row < end; row += 0x20u) {
        uint32_t words[8] = {0};
        unsigned have = 0;
        for (unsigned j = 0; j < 8; j++) {
            uintptr_t pc = row + (uintptr_t)j * 4u;
            if (pc >= end || !HFAReadable(pc, 4)) break;
            memcpy(&words[j], (const void *)pc, 4);
            have++;
        }
        if (!have) continue;
        HFALog("[CUSTOM-PATH-CODE] kind=%s identifier=%s rowRVA=%llX words=%08X/%08X/%08X/%08X/%08X/%08X/%08X/%08X\n",
               kind, identifier, (unsigned long long)(row - base),
               words[0], words[1], words[2], words[3],
               words[4], words[5], words[6], words[7]);
    }

    for (uintptr_t pc = start; pc < end; pc += 4u) {
        if (!HFAReadable(pc, 4)) continue;
        uint32_t word = *(const uint32_t *)pc;
        const char *branchKind = NULL;
        uintptr_t rawTarget = 0;

        if ((word & 0xFC000000u) == 0x94000000u) {
            branchKind = "BL";
            int64_t displacement = HFASignExtend(word & 0x03FFFFFFu, 26) << 2;
            rawTarget = pc + (uintptr_t)displacement;
        } else if ((word & 0xFC000000u) == 0x14000000u) {
            branchKind = "B";
            int64_t displacement = HFASignExtend(word & 0x03FFFFFFu, 26) << 2;
            rawTarget = pc + (uintptr_t)displacement;
        } else if ((word & 0xFFFFFC1Fu) == 0xD63F0000u) {
            HFALog("[CUSTOM-PATH-INDIRECT] kind=%s identifier=%s pcRVA=%llX op=BLR reg=x%u word=%08X\n",
                   kind, identifier, (unsigned long long)(pc - base),
                   (word >> 5) & 31u, word);
            continue;
        } else {
            continue;
        }

        uintptr_t resolved = HFAResolveBranchStub(rawTarget);
        Dl_info rawInfo = {0}, resolvedInfo = {0};
        dladdr((void *)rawTarget, &rawInfo);
        dladdr((void *)resolved, &resolvedInfo);
        uintptr_t rawRVA = rawInfo.dli_fbase
            ? rawTarget - (uintptr_t)rawInfo.dli_fbase : 0;
        uintptr_t resolvedRVA = resolvedInfo.dli_fbase
            ? resolved - (uintptr_t)resolvedInfo.dli_fbase : 0;
        const char *symbol = resolvedInfo.dli_sname ? resolvedInfo.dli_sname : "?";
        HFALog("[CUSTOM-PATH-CALL] kind=%s identifier=%s pcRVA=%llX op=%s word=%08X raw=%p rawImage=%s rawRVA=%llX resolved=%p resolvedImage=%s resolvedRVA=%llX symbol=%s\n",
               kind, identifier, (unsigned long long)(pc - base), branchKind,
               word, (void *)rawTarget,
               rawInfo.dli_fname ? HFABase(rawInfo.dli_fname) : "?",
               (unsigned long long)rawRVA, (void *)resolved,
               resolvedInfo.dli_fname ? HFABase(resolvedInfo.dli_fname) : "?",
               (unsigned long long)resolvedRVA, symbol);
        if (strstr(symbol, "objc_msgSend") || strstr(symbol, "objc_msgLookup"))
            HFAEmitObjCContext(kind, identifier, pc, base);
    }

    HFALog("[CUSTOM-PATH-END] kind=%s identifier=%s image=%s centerRVA=%llX\n",
           kind, identifier,
           centerInfo.dli_fname ? HFABase(centerInfo.dli_fname) : "?",
           (unsigned long long)(center - base));
}

static void HFAEmitHookTarget(HFAStateSite *site, uintptr_t caller) {
'''
if s.count(anchor) != 1:
    raise SystemExit(f"expected hook target anchor once, found {s.count(anchor)}")
s = s.replace(anchor, helper, 1)

# Probe the first customSwitch state caller site. This catches the local path around
# the state query without hardcoding k1 or any obfuscated class/selector.
old = """    site->calls++;
    site->lastResult = result;
    if (!site->hookLogged) {
"""
new = """    site->calls++;
    site->lastResult = result;
    if (site->calls == 1 && HFAIdentifierIsCustomSwitch(identifier))
        HFAProbeCodePath("caller", identifier, caller, 0x100u, 0x180u);
    if (!site->hookLogged) {
"""
if s.count(old) != 1:
    raise SystemExit(f"expected state site fragment once, found {s.count(old)}")
s = s.replace(old, new, 1)

# Probe the action implementation itself only when the currently armed feature is
# a customSwitch. Query hooks are installed first so the action execution remains
# observable through the existing state-query path.
old = """    HFAInstallStateQueriesForImage(image);
}

static int HFAValidOffset"""
new = """    HFAInstallStateQueriesForImage(image);
    if (HFACurrentFeatureIsCustomSwitch())
        HFAProbeCodePath("action", gIdentifier, (uintptr_t)implementation, 0, 0x600u);
}

static int HFAValidOffset"""
if s.count(old) != 1:
    raise SystemExit(f"expected action fragment once, found {s.count(old)}")
s = s.replace(old, new, 1)

old_marker = '[HFALearn v1.8.9 MenuFrameworkAnchorProbe] loaded'
new_marker = '[HFALearn v1.9.2 CustomSwitchActionPathProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"expected patch marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)

l = legacy_path.read_text()
old_marker = '[HFALearn UI v1.8.9 MenuFrameworkAnchorProbe] loaded'
new_marker = '[HFALearn UI v1.9.2 CustomSwitchActionPathProbe] loaded'
if l.count(old_marker) != 1:
    raise SystemExit(f"expected legacy marker once, found {l.count(old_marker)}")
l = l.replace(old_marker, new_marker, 1)
legacy_path.write_text(l)
