from pathlib import Path
import re

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()
l = legacy_path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


def regex_once(text, pattern, replacement, label):
    new_text, count = re.subn(pattern, lambda _m: replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 regex match, got {count}")
    return new_text


# v1.9.25 goals:
# - DO NOT change the legacy ordinary-patch scanner/exporter or its v1 JSON shape.
# - Add a separate iGMM feature collector and exporter.
# - Export every iGMM menu item (including modtext/customSwitch/kTypeButton).
# - Only fall back to the iGMM exporter when the legacy scan produced zero valid mappings.
# - Never fabricate module/offset/patchData for runtime-native iGMM features.

s = replace_once(
    s,
    '[HFALearn v1.9.24 DualIOSGodsAdapterProbe] loaded',
    '[HFALearn v1.9.25 DualIOSGodsJsonExport] loaded',
    'update core marker',
)
l = replace_once(
    l,
    '[HFALearn UI v1.9.24 DualIOSGodsAdapterProbe] loaded',
    '[HFALearn UI v1.9.25 DualIOSGodsJsonExport] loaded',
    'update UI marker',
)

# ---------------------------------------------------------------------------
# Core-side iGMM storage. This is entirely separate from legacy HFADescriptor.
# ---------------------------------------------------------------------------
old_globals = '''static HFAFeatureDefinition gFeatureDefinitions[128];
static unsigned gFeatureDefinitionCount;
'''
new_globals = old_globals + r'''typedef struct {
    char label[256];
    char identifier[96];
    char type[64];
    char desc[384];
    char defaultValue[128];
    char handlerImage[256];
    uintptr_t handlerRVA;
    unsigned hasHandler;
} HFAIGMMFeature;
static HFAIGMMFeature gIGMMFeatures[128];
static unsigned gIGMMFeatureCount;
'''
s = replace_once(s, old_globals, new_globals, 'add iGMM storage')

anchor = 'static HFAFeatureDefinition *HFAFeatureDefinitionForKey(const char *key) {\n'
helper = r'''static HFAIGMMFeature *HFAIGMMFeatureFor(const char *label,
                                         const char *identifier,
                                         const char *type,
                                         int create) {
    if (!label || !*label || !identifier || !*identifier || !type || !*type)
        return NULL;
    for (unsigned i = 0; i < gIGMMFeatureCount; i++) {
        HFAIGMMFeature *f = &gIGMMFeatures[i];
        if (strcmp(f->label, label) == 0 &&
            strcmp(f->identifier, identifier) == 0 &&
            strcmp(f->type, type) == 0)
            return f;
    }
    if (!create || gIGMMFeatureCount >= 128) return NULL;
    HFAIGMMFeature *f = &gIGMMFeatures[gIGMMFeatureCount++];
    memset(f, 0, sizeof(*f));
    snprintf(f->label, sizeof(f->label), "%s", label);
    snprintf(f->identifier, sizeof(f->identifier), "%s", identifier);
    snprintf(f->type, sizeof(f->type), "%s", type);
    return f;
}

void HFAResetIGMMFeatures(void) {
    memset(gIGMMFeatures, 0, sizeof(gIGMMFeatures));
    gIGMMFeatureCount = 0;
}

unsigned int HFAIGMMFeatureCount(void) {
    return gIGMMFeatureCount;
}

void HFARegisterIGMMFeature(const char *label,
                            const char *identifier,
                            const char *type,
                            const char *desc,
                            id defaultValue,
                            id handlerBlock) {
    HFAIGMMFeature *f = HFAIGMMFeatureFor(label, identifier, type, 1);
    if (!f) return;
    if (desc && *desc)
        snprintf(f->desc, sizeof(f->desc), "%s", desc);
    if (defaultValue) {
        NSString *text = [[defaultValue description] description];
        if (text.length)
            snprintf(f->defaultValue, sizeof(f->defaultValue), "%s", text.UTF8String);
    }
    if (handlerBlock) {
        HFABlockLiteral *literal = (HFABlockLiteral *)handlerBlock;
        uintptr_t invoke = literal ? (uintptr_t)literal->invoke : 0;
        Dl_info info = {0};
        if (invoke && dladdr((void *)invoke, &info) && info.dli_fbase) {
            f->hasHandler = 1;
            f->handlerRVA = invoke - (uintptr_t)info.dli_fbase;
            if (info.dli_fname)
                snprintf(f->handlerImage, sizeof(f->handlerImage), "%s",
                         HFABase(info.dli_fname));
        }
    }
    HFALog("[IGMM-FEATURE-REGISTER] label=%s identifier=%s type=%s default=%s handler=%u image=%s rva=%llX\n",
           f->label, f->identifier, f->type,
           f->defaultValue[0] ? f->defaultValue : "?",
           f->hasHandler,
           f->handlerImage[0] ? f->handlerImage : "?",
           (unsigned long long)f->handlerRVA);
}

''' + anchor
s = replace_once(s, anchor, helper, 'insert iGMM registration API')

# Separate exporter. The existing HFAWritePatchPackage() is intentionally untouched.
export_anchor = 'static void HFAWriteCompactMapping(const char *feature, const char *module,\n'
exporter = r'''unsigned int HFAExportIGMMPackage(void) {
    if (!gIGMMFeatureCount) return 0;
    @autoreleasepool {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *bundleID = bundle.bundleIdentifier ?: @"unknown.bundle";
        NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
        NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
        NSMutableArray *features = [NSMutableArray array];

        for (unsigned i = 0; i < gIGMMFeatureCount; i++) {
            HFAIGMMFeature *f = &gIGMMFeatures[i];
            NSMutableDictionary *runtime = [@{
                @"family": @"iGMM",
                @"representation": @"runtimeNative",
                @"mappingStatus": @"menuConfigCaptured"
            } mutableCopy];
            if (f->hasHandler) {
                runtime[@"handler"] = @{
                    @"kind": @"block",
                    @"module": f->handlerImage[0] ?
                        [NSString stringWithUTF8String:f->handlerImage] : @"?",
                    @"offset": [NSString stringWithFormat:@"0x%llX",
                        (unsigned long long)f->handlerRVA]
                };
            }

            NSMutableDictionary *entry = [@{
                @"title": [NSString stringWithUTF8String:f->label],
                @"identifier": [NSString stringWithUTF8String:f->identifier],
                @"type": [NSString stringWithUTF8String:f->type],
                @"runtime": runtime
            } mutableCopy];
            if (f->desc[0])
                entry[@"description"] = [NSString stringWithUTF8String:f->desc];
            if (f->defaultValue[0])
                entry[@"defaultValue"] = [NSString stringWithUTF8String:f->defaultValue];
            [features addObject:entry];
        }

#if defined(__arm64e__)
        NSString *architecture = @"arm64e";
#else
        NSString *architecture = @"arm64";
#endif
        NSDictionary *root = @{
            @"schema": @"com.hfa.patch/v2",
            @"adapter": @"iGMM",
            @"name": [NSString stringWithFormat:@"%@ %@", bundleID, shortVersion],
            @"package": @{
                @"bundleIdentifier": bundleID,
                @"shortVersion": shortVersion,
                @"buildVersion": buildVersion,
                @"architectures": @[architecture]
            },
            @"features": features
        };

        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:root
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
        if (!json) {
            HFALog("[IGMM-PACKAGE-EXPORT-FAIL] reason=%s\n",
                   error.localizedDescription.UTF8String ?: "json");
            return 0;
        }
        NSString *safeID = [bundleID stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        NSString *name = [NSString stringWithFormat:@"%@_%@_%@.hfapatch.json",
                          safeID, shortVersion, buildVersion];
        NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                          stringByAppendingPathComponent:name];
        if (![json writeToFile:path options:NSDataWritingAtomic error:&error]) {
            HFALog("[IGMM-PACKAGE-EXPORT-FAIL] reason=%s\n",
                   error.localizedDescription.UTF8String ?: "write");
            return 0;
        }
        HFALog("[IGMM-PACKAGE-EXPORT] path=%s features=%u schema=com.hfa.patch/v2 adapter=iGMM\n",
               path.UTF8String, (unsigned)features.count);
        return (unsigned)features.count;
    }
}

''' + export_anchor
s = replace_once(s, export_anchor, exporter, 'insert iGMM exporter')

# ---------------------------------------------------------------------------
# Legacy UI-side bridge and 4/4 feature collection from iGMM dictionaries.
# ---------------------------------------------------------------------------
old_extern = 'extern void HFARegisterPatchString(id,const char*); extern void HFARegisterFeatureDefinition(const char*,const char*); extern void HFARegisterCustomBlock(id,const char*);\n'
new_extern = old_extern + (
    'extern void HFAResetIGMMFeatures(void); '
    'extern unsigned int HFAIGMMFeatureCount(void); '
    'extern void HFARegisterIGMMFeature(const char*,const char*,const char*,const char*,id,id); '
    'extern unsigned int HFAExportIGMMPackage(void);\n'
)
l = replace_once(l, old_extern, new_extern, 'add iGMM bridge declarations')

pattern = r'static void igmm_probe_dictionary\(id d,int depth\)\{.*?\n\}\n\nstatic void igmm_probe_collection'
replacement = r'''static void igmm_probe_dictionary(id d,int depth){
    if(!d||depth>5||!resp(d,"allKeys")||!resp(d,"objectForKey:"))return;
    id keys=M0(id,d,"allKeys");u64 n=keys&&resp(keys,"count")?M0(u64,keys,"count"):0;if(n>64)n=64;
    char label[256]={0},identifier[96]={0},type[64]={0},desc[384]={0};
    id defaultValue=0,handlerBlock=0;
    logf("[IGMM-DICT] depth=%d ptr=%p count=%llu\n",depth,d,n);
    for(u64 i=0;i<n;i++){
        id k=M1(id,keys,"objectAtIndex:",u64,i);id v=M1(id,d,"objectForKey:",id,k);
        const char*ks=utf8(k);Class vc=v?object_getClass(v):0;const char*vcn=vc?class_getName(vc):"(nil)";const char*vs=utf8(v);
        if(ks&&ceq(ks,"label")&&vs)copyc(label,vs,sizeof(label));
        else if(ks&&ceq(ks,"identifier")&&vs)copyc(identifier,vs,sizeof(identifier));
        else if(ks&&ceq(ks,"type")&&vs)copyc(type,vs,sizeof(type));
        else if(ks&&ceq(ks,"desc")&&vs)copyc(desc,vs,sizeof(desc));
        else if(ks&&ceq(ks,"defaultValue"))defaultValue=v;
        else if(ks&&ceq(ks,"kButtonTapHandler"))handlerBlock=v;

        if(ks&&igmm_interesting_key(ks)){
            gIGMMInterestingCount++;
            logf("[IGMM-KEY] depth=%d key=%s valueClass=%s ptr=%p\n",depth,ks,vcn,v);
        }else if(ks){
            logf("[IGMM-KV] depth=%d key=%s valueClass=%s ptr=%p\n",depth,ks,vcn,v);
        }
        if(v&&igmm_is_string(vcn))igmm_log_string(v,"NSDictionary",ks?ks:"?",depth);
    }
    if(label[0]&&identifier[0]&&type[0]){
        HFARegisterIGMMFeature(label,identifier,type,desc,defaultValue,handlerBlock);
        logf("[IGMM-FEATURE] label=%s identifier=%s type=%s handler=%u\n",
             label,identifier,type,handlerBlock?1u:0u);
    }
    for(u64 i=0;i<n;i++){
        id k=M1(id,keys,"objectAtIndex:",u64,i);id v=M1(id,d,"objectForKey:",id,k);
        (void)k;igmm_probe_graph(v,depth+1);
    }
}

static void igmm_probe_collection'''
l = regex_once(l, pattern, replacement, 'collect complete iGMM feature dictionaries')

# Reset the iGMM collector at each explicit full scan. Legacy state remains untouched.
pattern = r'(static unsigned int run_full_scan\(void\)\{)'
l = regex_once(l, pattern, r'\1HFAResetIGMMFeatures();', 'reset iGMM feature collector per scan')

# Legacy export always gets first chance. Only if it produced zero valid mappings do
# we export the independently collected iGMM package.
old_finalize = 'unsigned int valid=HFAPatchTraceFinalizeScan();'
new_finalize = (
    'unsigned int valid=HFAPatchTraceFinalizeScan();'
    'if(!valid&&HFAIGMMFeatureCount()){' 
    'unsigned int igmm=HFAExportIGMMPackage();'
    'logf("[DUAL-JSON-EXPORT] legacyValid=%u igmmFeatures=%u exported=%u\\n",valid,HFAIGMMFeatureCount(),igmm);'
    'if(igmm)valid=igmm;'
    '}'
)
l = replace_once(l, old_finalize, new_finalize, 'add iGMM export fallback without touching legacy export')

old_mode = '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=readonly-runtime-graph export=legacy-only'
new_mode = '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-graph export=legacy-v1-or-igmm-v2'
l = replace_once(l, old_mode, new_mode, 'update dual export mode marker')

patch_path.write_text(s)
legacy_path.write_text(l)
