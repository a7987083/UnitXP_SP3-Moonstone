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


# v1.9.25 hard compatibility rule:
# - legacy iOSGods discovery + ordinary Patch Descriptor exporter stay unchanged
# - iGMM feature definitions are registered separately and exported only when
#   the legacy scan has zero valid ordinary patch mappings
# - export every valid iGMM menu definition (modtext/customSwitch/button/etc.)
# - never invent module/offset/patch bytes for runtime/native-hook features

# Version markers.
s = replace_once(
    s,
    '[HFALearn v1.9.24 DualIOSGodsAdapterProbe] loaded',
    '[HFALearn v1.9.25 DualIOSGodsJSONExport] loaded',
    'update core marker',
)
l = replace_once(
    l,
    '[HFALearn UI v1.9.24 DualIOSGodsAdapterProbe] loaded',
    '[HFALearn UI v1.9.25 DualIOSGodsJSONExport] loaded',
    'update UI marker',
)
l = replace_once(
    l,
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=readonly-runtime-graph export=legacy-only',
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-definition export=legacy-v1+igmm-v1',
    'update mode marker',
)

# Legacy scanner calls this only after it has positively identified an array
# whose every item is a {label, identifier, type} dictionary.
macro_anchor = '#define M0(r,o,s) ((r(*)(id,SEL))objc_msgSend)((id)(o),sel_registerName(s))\n'
l = replace_once(
    l,
    macro_anchor,
    'extern void HFARegisterIGMMFeatureArray(id,id);\n' + macro_anchor,
    'declare iGMM feature registration',
)

# Core: pending iGMM manifest + safe runtime metadata exporter. This is kept
# separate from HFAWritePatchPackage so the proven legacy v1 package writer is
# not rewritten.
anchor = 'static void HFAWritePatchPackage(NSArray *features, NSDictionary *targets) {\n'
helper = r'''static id gPendingIGMMMenuTarget = nil;
static NSArray *gPendingIGMMFeatures = nil;

static BOOL HFAIGMMValidFeatureDictionary(id value) {
    if (![value isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *d = (NSDictionary *)value;
    id label = d[@"label"], identifier = d[@"identifier"], type = d[@"type"];
    return [label isKindOfClass:[NSString class]] && [(NSString *)label length] &&
           [identifier isKindOfClass:[NSString class]] && [(NSString *)identifier length] &&
           [type isKindOfClass:[NSString class]] && [(NSString *)type length];
}

void HFARegisterIGMMFeatureArray(id menuTarget, id featureArray) {
    if (!menuTarget || ![featureArray isKindOfClass:[NSArray class]]) return;
    NSArray *a = (NSArray *)featureArray;
    if (!a.count || a.count > 64) return;
    for (id item in a)
        if (!HFAIGMMValidFeatureDictionary(item)) return;
    if (gPendingIGMMFeatures && gPendingIGMMFeatures.count >= a.count) return;
    gPendingIGMMMenuTarget = menuTarget;
    gPendingIGMMFeatures = a;
    const char *cn = class_getName(object_getClass(menuTarget));
    const char *image = class_getImageName(object_getClass(menuTarget));
    HFALog("[IGMM-REGISTER] class=%s image=%s features=%u\n",
           cn ? cn : "?", image ? HFABase(image) : "?", (unsigned)a.count);
}

static id HFAIGMMJSONValue(id value) {
    if (!value || value == [NSNull null]) return value;
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSArray class]] ||
        [value isKindOfClass:[NSDictionary class]]) {
        NSArray *wrapper = @[value];
        return [NSJSONSerialization isValidJSONObject:wrapper] ? value : nil;
    }
    return nil;
}

static NSDictionary *HFAIGMMBlockMetadata(id block) {
    if (!block) return nil;
    Class cls = object_getClass(block);
    const char *cn = cls ? class_getName(cls) : NULL;
    if (!cn || !strstr(cn, "Block")) return nil;
    HFABlockLiteral *literal = (HFABlockLiteral *)(void *)block;
    uintptr_t invoke = (uintptr_t)literal->invoke;
#if __has_feature(ptrauth_calls)
    invoke = (uintptr_t)ptrauth_strip((void *)invoke, ptrauth_key_function_pointer);
#endif
    if (!invoke) return nil;
    Dl_info info = {0};
    if (!dladdr((void *)invoke, &info) || !info.dli_fbase || !info.dli_fname)
        return @{ @"kind": @"block", @"class": [NSString stringWithUTF8String:cn] };
    uintptr_t rva = invoke - (uintptr_t)info.dli_fbase;
    return @{ @"kind": @"block",
              @"class": [NSString stringWithUTF8String:cn],
              @"image": [NSString stringWithUTF8String:HFABase(info.dli_fname)],
              @"offset": [NSString stringWithFormat:@"0x%llX", (unsigned long long)rva] };
}

static void HFAWriteIGMMPackage(id menuTarget, NSArray *rawFeatures) {
    if (!menuTarget || !rawFeatures.count) return;
    NSMutableArray *features = [NSMutableArray array];
    const char *menuClassC = class_getName(object_getClass(menuTarget));
    const char *menuImageC = class_getImageName(object_getClass(menuTarget));
    NSString *menuClass = menuClassC ? [NSString stringWithUTF8String:menuClassC] : @"?";
    NSString *menuImage = menuImageC ? [NSString stringWithUTF8String:HFABase(menuImageC)] : @"?";

    NSArray *configKeys = @[ @"desc", @"defaultValue", @"offsets", @"distance",
                             @"patched", @"offsetDifference", @"typecfg" ];
    unsigned index = 0;
    for (id item in rawFeatures) {
        if (!HFAIGMMValidFeatureDictionary(item)) continue;
        NSDictionary *d = (NSDictionary *)item;
        NSString *title = d[@"label"];
        NSString *identifier = d[@"identifier"];
        NSString *type = d[@"type"];
        NSMutableDictionary *config = [NSMutableDictionary dictionary];
        for (NSString *key in configKeys) {
            id safe = HFAIGMMJSONValue(d[key]);
            if (safe) config[key] = safe;
        }

        NSMutableDictionary *runtime = [@{ @"backend": @"iGMM",
                                            @"menuClass": menuClass,
                                            @"menuImage": menuImage,
                                            @"representation": @"runtime-definition" } mutableCopy];
        NSDictionary *handler = HFAIGMMBlockMetadata(d[@"kButtonTapHandler"]);
        if (handler) runtime[@"handler"] = handler;

        NSMutableDictionary *feature = [@{ @"id": identifier,
                                            @"title": title,
                                            @"group": @"Imported",
                                            @"type": type,
                                            @"backend": @"iGMM",
                                            @"patches": @[],
                                            @"runtime": runtime } mutableCopy];
        if (config.count) feature[@"config"] = config;
        if ([type isEqualToString:@"customSwitch"])
            feature[@"defaultEnabled"] = @NO;
        [features addObject:feature];

        NSString *handlerImage = handler[@"image"] ?: @"?";
        NSString *handlerOffset = handler[@"offset"] ?: @"?";
        HFALog("[IGMM-PACKAGE-FEATURE] index=%u title=\"%s\" identifier=%s type=%s handler=%s+%s\n",
               index++, title.UTF8String, identifier.UTF8String, type.UTF8String,
               handlerImage.UTF8String, handlerOffset.UTF8String);
    }
    if (!features.count) return;

    NSBundle *bundle = NSBundle.mainBundle;
    NSString *bundleID = bundle.bundleIdentifier ?: @"unknown.game";
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
#ifdef CPU_SUBTYPE_ARM64E
    const struct mach_header *header = _dyld_get_image_header(0);
    cpu_subtype_t subtype = header ? (header->cpusubtype & ~CPU_SUBTYPE_MASK) : 0;
    NSString *architecture = subtype == CPU_SUBTYPE_ARM64E ? @"arm64e" : @"arm64";
#else
    NSString *architecture = @"arm64";
#endif
    NSDictionary *targets = @{ @"igmm": @{ @"image": menuImage } };
    NSDictionary *root = @{
        @"schema": @"com.hfa.patch/v1",
        @"name": [NSString stringWithFormat:@"%@ %@", bundleID, shortVersion],
        @"package": @{ @"bundleIdentifier": bundleID,
                        @"shortVersion": shortVersion,
                        @"buildVersion": buildVersion,
                        @"architectures": @[architecture] },
        @"targets": targets,
        @"features": features,
        @"menuFamily": @"iGMM",
        @"extensions": @[ @"com.hfa.igmm/runtime-definition-v1" ]
    };
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&error];
    if (!json) {
        HFALog("[IGMM-PACKAGE-EXPORT-FAIL] reason=%s\n", error.localizedDescription.UTF8String ?: "json");
        return;
    }
    NSString *safeID = [bundleID stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *name = [NSString stringWithFormat:@"%@_%@_%@.hfapatch.json", safeID, shortVersion, buildVersion];
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:name];
    if ([json writeToFile:path options:NSDataWritingAtomic error:&error])
        HFALog("[IGMM-PACKAGE-EXPORT] path=%s features=%u menuClass=%s menuImage=%s\n",
               path.UTF8String, (unsigned)features.count,
               menuClass.UTF8String, menuImage.UTF8String);
    else
        HFALog("[IGMM-PACKAGE-EXPORT-FAIL] reason=%s\n", error.localizedDescription.UTF8String ?: "write");
}

''' + anchor
s = replace_once(s, anchor, helper, 'insert iGMM package exporter')

# Keep the original legacy package call exactly in place; only append an iGMM
# fallback when the legacy scan produced zero valid ordinary mappings.
old_finalize = '''    HFAWritePatchPackage(exportFeatures, exportTargets);\n    return validParts;\n}\n'''
new_finalize = '''    HFAWritePatchPackage(exportFeatures, exportTargets);\n    if (!validParts && gPendingIGMMFeatures.count) {\n        HFAWriteIGMMPackage(gPendingIGMMMenuTarget, gPendingIGMMFeatures);\n        gPendingIGMMMenuTarget = nil;\n        gPendingIGMMFeatures = nil;\n    }\n    return validParts;\n}\n'''
s = replace_once(s, old_finalize, new_finalize, 'append iGMM fallback export')

# Legacy side: locate the feature-definition array generically. Do not depend on
# the obfuscated current ivar name (haTfDfsM); validate content instead.
anchor = 'static void igmm_probe_target(id o){\n'
feature_finder = r'''static unsigned int igmm_feature_array_score(id a){
    if(!a||!resp(a,"count")||!resp(a,"objectAtIndex:"))return 0;
    u64 n=M0(u64,a,"count");if(!n||n>64)return 0;
    for(u64 i=0;i<n;i++){
        id d=M1(id,a,"objectAtIndex:",u64,i);if(!d||!resp(d,"objectForKey:"))return 0;
        id label=M1(id,d,"objectForKey:",id,ns("label"));
        id ident=M1(id,d,"objectForKey:",id,ns("identifier"));
        id type=M1(id,d,"objectForKey:",id,ns("type"));
        const char*ls=utf8(label),*is=utf8(ident),*ts=utf8(type);
        if(!ls||!*ls||!is||!*is||!ts||!*ts)return 0;
    }
    return (unsigned int)n;
}
static id igmm_find_feature_array(id o,unsigned int*countOut,const char**ivarOut){
    if(countOut)*countOut=0;if(ivarOut)*ivarOut=0;if(!o)return 0;
    id best=0;unsigned int bestCount=0;const char*bestName=0;
    Class k=object_getClass(o);
    for(int level=0;k&&level<3;level++,k=class_getSuperclass(k)){
        const char*kcn=class_getName(k);
        if(level>0&&(starts(kcn,"UI")||starts(kcn,"NS")))break;
        unsigned int count=0;Ivar*ivars=class_copyIvarList(k,&count);if(count>64)count=64;
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*t=ivar_getTypeEncoding(ivars[i]);if(!igmm_obj_type(t))continue;
            id v=object_getIvar(o,ivars[i]);unsigned int score=igmm_feature_array_score(v);
            if(score>bestCount){best=v;bestCount=score;bestName=ivar_getName(ivars[i]);}
        }
        free(ivars);
    }
    if(countOut)*countOut=bestCount;if(ivarOut)*ivarOut=bestName;return best;
}

''' + anchor
l = replace_once(l, anchor, feature_finder, 'insert generic iGMM feature-array finder')

old_probe_tail = '''    logf("[IGMM-PROBE-TARGET] phase=end class=%s ptr=%p interesting=%u strings=%u objects=%u\\n",\n         cn,o,gIGMMInterestingCount,gIGMMStringCount,gIGMMObjectCount);\n    if(gIGMMInterestingCount)\n        logf("[IGMM-CANDIDATE] class=%s ptr=%p score=%u mode=readonly-runtime-graph\\n",cn,o,gIGMMInterestingCount);\n}\n'''
new_probe_tail = '''    logf("[IGMM-PROBE-TARGET] phase=end class=%s ptr=%p interesting=%u strings=%u objects=%u\\n",\n         cn,o,gIGMMInterestingCount,gIGMMStringCount,gIGMMObjectCount);\n    if(gIGMMInterestingCount)\n        logf("[IGMM-CANDIDATE] class=%s ptr=%p score=%u mode=readonly-runtime-graph\\n",cn,o,gIGMMInterestingCount);\n    unsigned int featureCount=0;const char*featureIvar=0;\n    id featureArray=igmm_find_feature_array(o,&featureCount,&featureIvar);\n    if(featureArray&&featureCount){\n        logf("[IGMM-FEATURE-ARRAY] class=%s ptr=%p ivar=%s count=%u\\n",\n             cn,o,featureIvar?featureIvar:"?",featureCount);\n        HFARegisterIGMMFeatureArray(o,featureArray);\n    }\n}\n'''
l = replace_once(l, old_probe_tail, new_probe_tail, 'register discovered iGMM feature array')

patch_path.write_text(s)
legacy_path.write_text(l)
