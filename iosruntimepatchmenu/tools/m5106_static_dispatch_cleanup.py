from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "iosruntimepatchmenu" / "src" / "ZNStaticBinaryBuilderV3.mm"
text = PATH.read_text(encoding="utf-8")
original = text


def replace_once(old: str, new: str, label: str):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    text = text.replace(old, new, 1)

replace_once(
'''struct ZNV3Physical {
    uint64_t rva;
    uint64_t fileoff;
    uint64_t window;
    size_t segIndex;
    std::vector<size_t> members;
    NSData *original;
    uint64_t thunkRVA;
    uint64_t offRVA;
};''',
'''struct ZNV3Physical {
    uint64_t rva;
    uint64_t fileoff;
    uint64_t window;
    size_t segIndex;
    size_t logicalIndex;
    NSData *original;
    uint64_t thunkRVA;
    uint64_t offRVA;
};''',
"physical struct")

replace_once(
'''    std::vector<ZNV3Logical> logicals;
    std::vector<ZNV3Physical> physicals;
    std::vector<size_t> logicalToPhysical;
''',
'''    std::vector<ZNV3Logical> logicals;
    std::vector<ZNV3Physical> physicals;
''',
"logical mapping declaration")

start = text.index('        logicalToPhysical.assign(logicals.size(),0);\n')
end = text.index('        for(size_t p=0;p<physicals.size();p++) {\n', start)
text = text[:start] + '''        // M5.10.6: one authored row owns one physical Target+RVA site. The
        // Workspace already rejects duplicates; Builder repeats the check so
        // imported/programmatic rows cannot revive shared-site semantics.
        physicals.reserve(logicals.size());
        for (size_t i = 0; i < logicals.size(); i++) {
            ZNV3Logical &logical = logicals[i];
            for (const ZNV3Physical &existing : physicals) {
                if (existing.rva == logical.rva) {
                    localError = [NSString stringWithFormat:@"重复 Target+RVA：%@+0x%llX；M5.10 Static Offset 不支持 Shared Site", target, logical.rva];
                    break;
                }
            }
            if (localError) break;
            ZNV3Physical physical = {};
            physical.rva = logical.rva;
            physical.fileoff = logical.fileoff;
            physical.window = logical.length;
            physical.segIndex = logical.segIndex;
            physical.logicalIndex = i;
            physical.original = nil;
            physical.thunkRVA = 0;
            physical.offRVA = 0;
            physicals.push_back(physical);
        }
        if (localError) break;

''' + text[end:]

old = '''        const uint64_t thunkStride=ZN60_PAYLOAD_THUNK_STRIDE;
        for(const ZNV3Physical &physical:physicals){
            uint64_t variantStride=ZN60VariantStrideBytes(physical.window);
            if(!variantStride){localError=@"Protection V2 Variant stride 计算失败";break;}
            NSMutableArray<NSData *> *unique=[NSMutableArray array];
            for(size_t logicalIndex:physical.members){
                NSData *source=ZNV3ComposedVariant(physical,logicals[logicalIndex]);
                if(!source){localError=@"Variant 合成失败";break;}
                BOOL exists=NO; for(NSData *x in unique)if([x isEqualToData:source]){exists=YES;break;}
                if(!exists)[unique addObject:source];
            }
            if(localError)break;
            codeNeeded=ZNV3Align(codeNeeded,16)+thunkStride+variantStride*(1+unique.count);
        }
'''
new = '''        const uint64_t thunkStride=ZN60_PAYLOAD_THUNK_STRIDE;
        for(const ZNV3Physical &physical:physicals){
            uint64_t variantStride=ZN60VariantStrideBytes(physical.window);
            if(!variantStride){localError=@"Protection V2 Variant stride 计算失败";break;}
            NSData *source=ZNV3ComposedVariant(physical,logicals[physical.logicalIndex]);
            if(!source){localError=@"Enabled Variant 合成失败";break;}
            // Exactly two relocated paths per site: OFF/Original + ON/Enabled.
            codeNeeded=ZNV3Align(codeNeeded,16)+thunkStride+variantStride*2u;
        }
'''
replace_once(old, new, "code budget")

start = text.index('                        NSMutableArray<NSData *> *writtenSources=[NSMutableArray array];\n')
end_marker = '                        size_t canonicalLogical=physical.members.front();\n'
end = text.index(end_marker, start)
replacement = '''                        size_t logicalIndex=physical.logicalIndex;
                        NSData *source=ZNV3ComposedVariant(physical,logicals[logicalIndex]);
                        if(!source){localError=@"Enabled Variant 合成失败";break;}
                        uint64_t onState=ZN60DeriveLayoutState(protectionV2Nonce,physical.rva,1u);
                        uint64_t onRegionBase=ZNV3Align(codeCursor,16);
                        uint64_t onPad=(ZN60NextLayoutWord(&onState)%5u)*16u;
                        uint64_t onFileOffset=onRegionBase+onPad;
                        uint64_t onRegionRVA=codeRVA+(onFileOffset-codeFileOffset);
                        codeCursor=onRegionBase+variantStride;
                        uint64_t onEntryRVA=0;
                        uint32_t onFragments=0;
                        if(!ZNV3WriteVariantV2(base,onFileOffset,onRegionRVA,variantReserved,source,physical.rva,
                                               physical.rva,physical.rva+physical.window,physical.rva+physical.window,
                                               onState,&onEntryRVA,&onFragments,&localError))break;
                        protectionV2Variants++;
                        protectionV2Fragments+=onFragments;
                        onRVAs[logicalIndex]=onEntryRVA;

                        size_t canonicalLogical=physical.logicalIndex;
'''
text = text[:start] + replacement + text[end + len(end_marker):]

replace_once(
'''                        ZNV3Physical &physical=physicals[logicalToPhysical[i]];
''',
'''                        ZNV3Physical &physical=physicals[i];
''',
"entry physical mapping")
replace_once(
'''                        entry.physicalID=(uint32_t)logicalToPhysical[i]+1;
                        entry.canonicalIndex=(uint32_t)physical.members.front();
                        entry.flags=(i==physical.members.front()?ZN44_STATIC_ENTRY_FLAG_CANONICAL:0u) |
                                    (physical.members.size()>1?ZN44_STATIC_ENTRY_FLAG_SHARED:0u);
''',
'''                        entry.physicalID=(uint32_t)i+1;
                        entry.canonicalIndex=(uint32_t)i;
                        entry.flags=ZN44_STATIC_ENTRY_FLAG_CANONICAL;
''',
"entry shared flags")
replace_once(
'''                    NSUInteger sharedSites=0;
                    for(const ZNV3Physical &p:physicals)if(p.members.size()>1)sharedSites++;
''',
'''                    // One entry == one physical site; no shared-site ownership layer.
''',
"shared count")
replace_once('''                        @"sharedSiteCount":@(sharedSites),
''', '', "shared metadata")
replace_once('''                        @"ownerPolicy":@"last-enabled-active-owner-wins",
''', '''                        @"stateModel":@"one-site-two-state-off-on",
''', "owner metadata")

for old, new in (
    ('@"Same Target + same starting RVA is one physical site",', '@"Duplicate Target + RVA is rejected before generation",'),
    ('@"Different Enabled values become logical variants",', '@"Each physical site has exactly OFF/Original and ON/Enabled relocated paths",'),
    ('@"Short variants are composed with the current validated Original tail before relocation",', '@"Enabled bytes are composed with the validated Original tail before relocation when needed",'),
    ('@"Runtime owner policy: most recently enabled active owner wins",', '@"Runtime state is a direct OFF/ON selectedTarget switch",'),
    ('@"No active owner selects relocated Original",', '@"OFF selects relocated Original",'),
    ('@"Shared-site owner fallback remains correct",', '@"Each site toggles independently between OFF and ON",'),
):
    if old not in text:
        raise SystemExit(f"report wording missing: {old}")
    text = text.replace(old, new, 1)

# No shared-site implementation vocabulary may survive in active Builder code.
for forbidden in (
    'logicalToPhysical',
    '.members',
    'ZN44_STATIC_ENTRY_FLAG_SHARED',
    'sharedSiteCount',
    'last-enabled-active-owner-wins',
    'most recently enabled active owner',
    'Shared-site owner fallback',
):
    if forbidden in text:
        raise SystemExit(f"legacy shared-site residue remains: {forbidden}")

if text == original:
    raise SystemExit("no changes produced")
PATH.write_text(text, encoding="utf-8")
print("M5.10.6 Builder V3 one-site/two-state cleanup applied")
