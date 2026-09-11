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


# v1.9.24 first-stage goal:
# - preserve the proven legacy iOSGods scanner/export path unchanged
# - add a second, read-only iGMM/APPatch structure probe beside it
# - never patch or invoke discovered iGMM objects
# - never require UIBetterScrollView / IGSecretInt / IGSecretData for the new probe
# - collect enough runtime structure to map type/offsets/identifier/APPatch in the next step

# Version markers only; behavior of the legacy adapter remains intact.
s = replace_once(
    s,
    '[HFALearn v1.9.14 FunctionStartsFileFallback] loaded',
    '[HFALearn v1.9.24 DualIOSGodsAdapterProbe] loaded',
    'update core marker',
)
l = replace_once(
    l,
    '[HFALearn UI v1.9.14 FunctionStartsFileFallback] loaded',
    '[HFALearn UI v1.9.24 DualIOSGodsAdapterProbe] loaded',
    'update UI marker',
)

# Objective-C runtime APIs used only for bounded, read-only ivar inspection.
old_decl = 'extern IMP class_replaceMethod(Class,SEL,IMP,const char*); extern const char* class_getName(Class); extern const char* sel_getName(SEL);\n'
new_decl = old_decl + (
    'typedef struct objc_ivar* Ivar; '
    'extern Ivar* class_copyIvarList(Class,unsigned int*); '
    'extern Class class_getSuperclass(Class); '
    'extern const char* ivar_getName(Ivar); '
    'extern const char* ivar_getTypeEncoding(Ivar); '
    'extern id object_getIvar(id,Ivar); '
    'extern Class object_getClass(id);\n'
)
l = replace_once(l, old_decl, new_decl, 'add readonly ObjC runtime declarations')

anchor = 'static id gAutoTargets[256];static unsigned int gAutoTargetCount=0,gAutoControlCount=0;static int gAutoMenuFound=0;\n'
helper = r'''/* v1.9.24 iGMM / APPatch read-only adapter probe. */
static id gIGMMProbeTargets[256];static unsigned int gIGMMProbeTargetCount=0;
static id gIGMMVisited[768];static unsigned int gIGMMVisitedCount=0;
static unsigned int gIGMMInterestingCount=0,gIGMMStringCount=0,gIGMMObjectCount=0;

static int igmm_target_seen(id o){
    for(unsigned int i=0;i<gIGMMProbeTargetCount;i++)if(gIGMMProbeTargets[i]==o)return 1;
    return 0;
}
static int igmm_graph_seen(id o){
    if(!o)return 1;
    for(unsigned int i=0;i<gIGMMVisitedCount;i++)if(gIGMMVisited[i]==o)return 1;
    if(gIGMMVisitedCount<768)gIGMMVisited[gIGMMVisitedCount++]=o;
    return 0;
}
static int igmm_has(const char*s,const char*needle){return s&&needle&&strstr(s,needle)!=0;}
static int igmm_is_array(const char*s){return igmm_has(s,"Array")||igmm_has(s,"Set");}
static int igmm_is_dict(const char*s){return igmm_has(s,"Dictionary");}
static int igmm_is_string(const char*s){return igmm_has(s,"String");}
static int igmm_is_number(const char*s){return igmm_has(s,"Number")||igmm_has(s,"Boolean");}
static int igmm_interesting_key(const char*s){
    return s&&(ceq(s,"type")||ceq(s,"offsets")||ceq(s,"distance")||ceq(s,"patched")||
               ceq(s,"desc")||ceq(s,"identifier")||ceq(s,"offsetDifference")||
               ceq(s,"defaultValue")||ceq(s,"typecfg")||ceq(s,"modtext")||
               ceq(s,"modslider")||ceq(s,"customSwitch")||ceq(s,"kTypeCustomHex")||
               ceq(s,"kTypeButton"));
}
static int igmm_obj_type(const char*t){return t&&t[0]=='@';}
static int igmm_skip_custom(const char*cn){
    if(!cn||!*cn)return 1;
    return starts(cn,"UI")||starts(cn,"_UI")||starts(cn,"NS")||starts(cn,"__NS")||
           starts(cn,"CA")||starts(cn,"CG")||starts(cn,"Unity")||starts(cn,"HFAMap");
}
static void igmm_probe_graph(id o,int depth);

static void igmm_log_string(id o,const char*owner,const char*slot,int depth){
    if(!o||!resp(o,"UTF8String"))return;
    const char*s=(const char*)M0(void*,o,"UTF8String");
    if(!s||!*s)return;
    gIGMMStringCount++;
    size_t n=strlen(s);
    if(n>180)logf("[IGMM-STRING] depth=%d owner=%s slot=%s value=%.160s... len=%llu\n",depth,owner?owner:"?",slot?slot:"?",s,(u64)n);
    else logf("[IGMM-STRING] depth=%d owner=%s slot=%s value=%s\n",depth,owner?owner:"?",slot?slot:"?",s);
}

static void igmm_probe_dictionary(id d,int depth){
    if(!d||depth>5||!resp(d,"allKeys")||!resp(d,"objectForKey:"))return;
    id keys=M0(id,d,"allKeys");u64 n=keys&&resp(keys,"count")?M0(u64,keys,"count"):0;if(n>64)n=64;
    logf("[IGMM-DICT] depth=%d ptr=%p count=%llu\n",depth,d,n);
    for(u64 i=0;i<n;i++){
        id k=M1(id,keys,"objectAtIndex:",u64,i);id v=M1(id,d,"objectForKey:",id,k);
        const char*ks=utf8(k);Class vc=v?object_getClass(v):0;const char*vcn=vc?class_getName(vc):"(nil)";
        if(ks&&igmm_interesting_key(ks)){
            gIGMMInterestingCount++;
            logf("[IGMM-KEY] depth=%d key=%s valueClass=%s ptr=%p\n",depth,ks,vcn,v);
        }else if(ks){
            logf("[IGMM-KV] depth=%d key=%s valueClass=%s ptr=%p\n",depth,ks,vcn,v);
        }
        if(v&&igmm_is_string(vcn))igmm_log_string(v,"NSDictionary",ks?ks:"?",depth);
        igmm_probe_graph(v,depth+1);
    }
}

static void igmm_probe_collection(id a,int depth){
    if(!a||depth>5)return;
    id list=a;
    Class c=object_getClass(a);const char*cn=c?class_getName(c):"?";
    if(igmm_has(cn,"Set")&&resp(a,"allObjects"))list=M0(id,a,"allObjects");
    if(!list||!resp(list,"count")||!resp(list,"objectAtIndex:"))return;
    u64 n=M0(u64,list,"count");if(n>96)n=96;
    logf("[IGMM-COLLECTION] depth=%d class=%s ptr=%p count=%llu\n",depth,cn,a,n);
    for(u64 i=0;i<n;i++)igmm_probe_graph(M1(id,list,"objectAtIndex:",u64,i),depth+1);
}

static void igmm_probe_object_ivars(id o,const char*cn,int depth){
    Class k=object_getClass(o);
    for(int level=0;k&&level<5;level++,k=class_getSuperclass(k)){
        const char*kcn=class_getName(k);unsigned int count=0;Ivar*ivars=class_copyIvarList(k,&count);if(count>64)count=64;
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*name=ivar_getName(ivars[i]);const char*type=ivar_getTypeEncoding(ivars[i]);
            if(!igmm_obj_type(type))continue;
            id v=object_getIvar(o,ivars[i]);Class vc=v?object_getClass(v):0;const char*vcn=vc?class_getName(vc):"(nil)";
            logf("[IGMM-IVAR] depth=%d owner=%s declaring=%s ivar=%s type=%s valueClass=%s ptr=%p\n",
                 depth,cn?cn:"?",kcn?kcn:"?",name?name:"?",type?type:"?",vcn,v);
            if(v&&igmm_is_string(vcn))igmm_log_string(v,cn,name,depth);
            igmm_probe_graph(v,depth+1);
        }
        free(ivars);
    }
}

static void igmm_probe_graph(id o,int depth){
    if(!o||depth>5||igmm_graph_seen(o))return;
    gIGMMObjectCount++;
    Class c=object_getClass(o);const char*cn=c?class_getName(c):"?";
    if(igmm_is_string(cn)){igmm_log_string(o,"graph","value",depth);return;}
    if(igmm_is_number(cn))return;
    if(igmm_is_dict(cn)){igmm_probe_dictionary(o,depth);return;}
    if(igmm_is_array(cn)){igmm_probe_collection(o,depth);return;}
    if(igmm_skip_custom(cn))return;
    logf("[IGMM-OBJECT] depth=%d class=%s ptr=%p\n",depth,cn,o);
    igmm_probe_object_ivars(o,cn,depth);
}

static void igmm_probe_target(id o){
    if(!o||o==gTarget||igmm_target_seen(o)||gIGMMProbeTargetCount>=256)return;
    gIGMMProbeTargets[gIGMMProbeTargetCount++]=o;
    gIGMMVisitedCount=0;gIGMMInterestingCount=0;gIGMMStringCount=0;gIGMMObjectCount=0;
    Class c=object_getClass(o);const char*cn=c?class_getName(c):"?";
    logf("[IGMM-PROBE-TARGET] phase=begin class=%s ptr=%p\n",cn,o);
    @try { igmm_probe_graph(o,0); }
    @catch(id exception) { logf("[IGMM-PROBE-EXCEPTION] class=%s ptr=%p\n",cn,o); }
    logf("[IGMM-PROBE-TARGET] phase=end class=%s ptr=%p interesting=%u strings=%u objects=%u\n",
         cn,o,gIGMMInterestingCount,gIGMMStringCount,gIGMMObjectCount);
    if(gIGMMInterestingCount)
        logf("[IGMM-CANDIDATE] class=%s ptr=%p score=%u mode=readonly-runtime-graph\n",cn,o,gIGMMInterestingCount);
}

'''
l = replace_once(l, anchor, helper + anchor, 'insert iGMM read-only probe')

old_auto = r'''        Class c=M0(Class,o,"class");const char*cn=c?class_getName(c):"?";
        if(!customcn(cn)||strstr(cn,".")||!resp(o,"_ivarDescription"))return;
'''
new_auto = r'''        Class c=M0(Class,o,"class");const char*cn=c?class_getName(c):"?";
        if(customcn(cn))igmm_probe_target(o);
        if(!customcn(cn)||strstr(cn,".")||!resp(o,"_ivarDescription"))return;
'''
l = replace_once(l, old_auto, new_auto, 'attach iGMM probe beside legacy auto_target')

# Add a mode line at startup so a device log unambiguously identifies the build.
old_init = 'logf("[HFALearn UI v1.9.24 DualIOSGodsAdapterProbe] loaded\\n");'
new_init = old_init + 'logf("[DUAL-IOSGODS-MODE] legacy=unchanged igmm=readonly-runtime-graph export=legacy-only\\n");'
l = replace_once(l, old_init, new_init, 'add dual adapter mode marker')

patch_path.write_text(s)
legacy_path.write_text(l)
