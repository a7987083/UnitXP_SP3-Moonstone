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


# v1.9.25 goal:
# - preserve the legacy iOSGods ordinary-patch scanner/exporter exactly
# - keep the v1.9.24 iGMM runtime graph discovery
# - collect every real iGMM menu feature dictionary generically (no game labels hardcoded)
# - when legacy mapping count is zero and iGMM features exist, emit the same
#   .hfapatch.json filename with schema com.hfa.patch/v1
# - represent iGMM entries honestly as runtime/config features with an empty
#   static patches array; do not invent offset/patchData for native-hook features
# - include kTypeButton entries and record the presence of kButtonTapHandler

# Version markers. Core behavior is intentionally untouched except for this marker.
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
    '[DUAL-IOSGODS-MODE] legacy=unchanged igmm=runtime-config export=dual-json',
    'update dual mode marker',
)

# snprintf is used only to build the same bundle/version based output filename.
old_decl = 'extern FILE* fopen(const char*,const char*); extern int fclose(FILE*); extern int fflush(FILE*); extern int vfprintf(FILE*,const char*,__builtin_va_list);\n'
new_decl = old_decl + 'extern int snprintf(char*,size_t,const char*,...);\n'
l = replace_once(l, old_decl, new_decl, 'declare snprintf')

# Runtime/config feature collector and JSON writer. This is independent from the
# legacy HFAWritePatchPackage() implementation in HFAMapPatchExecutionTrace.m.
anchor = 'static void igmm_probe_dictionary(id d,int depth){\n'
helper = r'''static id gIGMMFeatureDicts[64];static unsigned int gIGMMFeatureCount=0;

static id igmm_dict_value(id d,const char*key){
    if(!d||!key||!resp(d,"objectForKey:"))return 0;
    return M1(id,d,"objectForKey:",id,ns(key));
}
static int igmm_feature_seen(id d){
    for(unsigned int i=0;i<gIGMMFeatureCount;i++)if(gIGMMFeatureDicts[i]==d)return 1;
    return 0;
}
static int igmm_exportable_type(const char*t){
    return t&&(ceq(t,"modtext")||ceq(t,"modslider")||ceq(t,"customSwitch")||
               ceq(t,"kTypeCustomHex")||ceq(t,"kTypeButton"));
}
static void igmm_capture_feature(id d){
    if(!d||igmm_feature_seen(d)||gIGMMFeatureCount>=64)return;
    id labelObj=igmm_dict_value(d,"label");
    id identObj=igmm_dict_value(d,"identifier");
    id typeObj=igmm_dict_value(d,"type");
    const char*label=utf8(labelObj),*ident=utf8(identObj),*type=utf8(typeObj);
    if(!label||!*label||!ident||!*ident||!type||!*type||!igmm_exportable_type(type))return;
    gIGMMFeatureDicts[gIGMMFeatureCount++]=d;
    logf("[IGMM-FEATURE-CAPTURE] index=%u label=%s identifier=%s type=%s\n",
         gIGMMFeatureCount-1,label,ident,type);
}
static id igmm_mdict(void){Class c=objc_getClass("NSMutableDictionary");return c?M0(id,(id)c,"dictionary"):0;}
static id igmm_marray(void){Class c=objc_getClass("NSMutableArray");return c?M0(id,(id)c,"array"):0;}
static id igmm_array(void){Class c=objc_getClass("NSArray");return c?M0(id,(id)c,"array"):0;}
static id igmm_array1(id o){Class c=objc_getClass("NSArray");return c&&o?M1(id,(id)c,"arrayWithObject:",id,o):0;}
static id igmm_number_u64(u64 v){Class c=objc_getClass("NSNumber");return c?M1(id,(id)c,"numberWithUnsignedLongLong:",u64,v):0;}
static void igmm_set(id d,const char*key,id value){if(d&&key&&value)M2(void,d,"setObject:forKey:",id,value,id,ns(key));}
static void igmm_copy_if_present(id src,id dst,const char*key){id v=igmm_dict_value(src,key);if(v)igmm_set(dst,key,v);}

static unsigned int igmm_export_json(void){
    if(!gIGMMFeatureCount)return 0;
    Class bundleClass=objc_getClass("NSBundle");
    id bundle=bundleClass?M0(id,(id)bundleClass,"mainBundle"):0;
    id bundleIDObj=bundle&&resp(bundle,"bundleIdentifier")?M0(id,bundle,"bundleIdentifier"):0;
    id info=bundle&&resp(bundle,"infoDictionary")?M0(id,bundle,"infoDictionary"):0;
    id shortObj=info?M1(id,info,"objectForKey:",id,ns("CFBundleShortVersionString")):0;
    id buildObj=info?M1(id,info,"objectForKey:",id,ns("CFBundleVersion")):0;
    const char*bundleID=utf8(bundleIDObj);const char*shortVersion=utf8(shortObj);const char*buildVersion=utf8(buildObj);
    if(!bundleID||!*bundleID)bundleID="unknown.bundle";
    if(!shortVersion||!*shortVersion)shortVersion="0";
    if(!buildVersion||!*buildVersion)buildVersion="0";

    id features=igmm_marray();
    if(!features)return 0;
    unsigned int emitted=0;
    for(unsigned int i=0;i<gIGMMFeatureCount;i++){
        id cfg=gIGMMFeatureDicts[i];if(!cfg)continue;
        id labelObj=igmm_dict_value(cfg,"label");
        id identObj=igmm_dict_value(cfg,"identifier");
        id typeObj=igmm_dict_value(cfg,"type");
        const char*label=utf8(labelObj),*ident=utf8(identObj),*type=utf8(typeObj);
        if(!label||!ident||!type)continue;

        id feature=igmm_mdict();id runtime=igmm_mdict();
        if(!feature||!runtime)continue;
        igmm_set(feature,"title",labelObj);
        igmm_set(feature,"identifier",identObj);
        igmm_set(feature,"type",typeObj);
        igmm_set(feature,"patches",igmm_array());
        igmm_set(runtime,"adapter",ns("iGMM"));
        igmm_set(runtime,"kind",typeObj);
        igmm_copy_if_present(cfg,runtime,"defaultValue");
        igmm_copy_if_present(cfg,runtime,"desc");
        igmm_copy_if_present(cfg,runtime,"offsets");
        igmm_copy_if_present(cfg,runtime,"distance");
        igmm_copy_if_present(cfg,runtime,"patched");
        igmm_copy_if_present(cfg,runtime,"offsetDifference");
        igmm_copy_if_present(cfg,runtime,"typecfg");
        id buttonHandler=igmm_dict_value(cfg,"kButtonTapHandler");
        if(buttonHandler)igmm_set(runtime,"handlerType",ns("block"));
        igmm_set(feature,"runtime",runtime);
        M1(void,features,"addObject:",id,feature);
        emitted++;
        logf("[IGMM-JSON-FEATURE] index=%u label=%s identifier=%s type=%s buttonHandler=%u\n",
             emitted-1,label,ident,type,buttonHandler?1u:0u);
    }
    if(!emitted)return 0;

    id package=igmm_mdict();id root=igmm_mdict();id meta=igmm_mdict();
    if(!package||!root||!meta)return 0;
    igmm_set(package,"bundleIdentifier",bundleIDObj?bundleIDObj:ns(bundleID));
    igmm_set(package,"shortVersion",shortObj?shortObj:ns(shortVersion));
    igmm_set(package,"buildVersion",buildObj?buildObj:ns(buildVersion));
    igmm_set(package,"architectures",igmm_array1(ns("arm64")));

    char namebuf[640]={0};snprintf(namebuf,sizeof(namebuf),"%s %s",bundleID,shortVersion);
    igmm_set(root,"schema",ns("com.hfa.patch/v1"));
    igmm_set(root,"name",ns(namebuf));
    igmm_set(root,"package",package);
    igmm_set(root,"targets",igmm_array());
    igmm_set(root,"features",features);
    igmm_set(meta,"adapter",ns("iGMM"));
    igmm_set(meta,"representation",ns("runtime-config"));
    igmm_set(meta,"featureCount",igmm_number_u64(emitted));
    igmm_set(root,"metadata",meta);

    Class jsonClass=objc_getClass("NSJSONSerialization");id error=0;
    id data=jsonClass?M3(id,(id)jsonClass,"dataWithJSONObject:options:error:",id,root,u64,1,id*,&error):0;
    if(!data){
        const char*reason=error?objtext(error,"localizedDescription"):0;
        logf("[IGMM-PACKAGE-EXPORT-FAIL] reason=%s\n",reason?reason:"json");
        return 0;
    }
    char pathbuf[1280]={0};const char*home=getenv("HOME");if(!home||!*home)return 0;
    snprintf(pathbuf,sizeof(pathbuf),"%s/Documents/%s_%s_%s.hfapatch.json",home,bundleID,shortVersion,buildVersion);
    BOOL ok=M2(BOOL,data,"writeToFile:atomically:",id,ns(pathbuf),BOOL,1);
    if(!ok){logf("[IGMM-PACKAGE-EXPORT-FAIL] reason=write path=%s\n",pathbuf);return 0;}
    logf("[IGMM-PACKAGE-EXPORT] path=%s features=%u schema=com.hfa.patch/v1\n",pathbuf,emitted);
    return emitted;
}

''' + anchor
l = replace_once(l, anchor, helper, 'insert iGMM feature collector/exporter')

# Capture dictionary-shaped menu entries during the already bounded v1.9.24 graph walk.
old = '    logf("[IGMM-DICT] depth=%d ptr=%p count=%llu\\n",depth,d,n);\n'
new = old + '    igmm_capture_feature(d);\n'
l = replace_once(l, old, new, 'capture iGMM feature dictionaries')

# Reset only v1.9.24/v1.9.25 probe state at the beginning of each manual scan.
# Legacy gAuto* behavior and legacy descriptor state are unchanged.
old = '    gAutoTargetCount=0;gAutoControlCount=0;gAutoMenuFound=0;\n'
new = old + '    gIGMMProbeTargetCount=0;gIGMMVisitedCount=0;gIGMMFeatureCount=0;\n'
l = replace_once(l, old, new, 'reset iGMM scan state')

# Preserve the legacy exporter as the first and authoritative path. Only when it
# returns zero valid mappings do we emit iGMM runtime/config JSON.
old = r'''    unsigned int valid=HFAPatchTraceFinalizeScan();
    logf("[AUTO-SCAN] windows=%llu controls=%u targets=%u validMappings=%u\n",n,gAutoControlCount,gAutoTargetCount,valid);
    return valid;
'''
new = r'''    unsigned int valid=HFAPatchTraceFinalizeScan();
    if(!valid&&gIGMMFeatureCount){
        unsigned int exported=igmm_export_json();
        logf("[DUAL-JSON-RESULT] legacyValid=0 igmmCaptured=%u igmmExported=%u\n",gIGMMFeatureCount,exported);
        if(exported)valid=exported;
    }else{
        logf("[DUAL-JSON-RESULT] legacyValid=%u igmmCaptured=%u igmmExported=0\n",valid,gIGMMFeatureCount);
    }
    logf("[AUTO-SCAN] windows=%llu controls=%u targets=%u validMappings=%u\n",n,gAutoControlCount,gAutoTargetCount,valid);
    return valid;
'''
l = replace_once(l, old, new, 'add fallback iGMM JSON export')

patch_path.write_text(s)
legacy_path.write_text(l)
