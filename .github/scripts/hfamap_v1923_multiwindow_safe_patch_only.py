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


# v1.9.23 goal:
# - keep v1.9.22 safety: no _ivarDescription/_methodDescription in automatic scan
# - keep Key2/customSwitch/nativeHook/global UIControl hook disabled
# - restore multi-UIWindow discovery so overlay menus are reachable again
# - recursively walk feature dictionaries/arrays/custom containers via ObjC runtime only
# - stop immediately after one reliable ordinary patch menu is found and export JSON

# 1) Version/mode markers.
s = replace_once(
    s,
    '[HFALearn v1.9.22 SafeMenuPatchOnly] loaded',
    '[HFALearn v1.9.23 MultiWindowSafePatchOnly] loaded',
    'update core marker',
)
s = replace_once(
    s,
    '[PATCH-ONLY-MODE] key2=hard-disabled customSwitch=disabled nativeHook=disabled menuScan=safe-runtime-ivar export=immediate',
    '[PATCH-ONLY-MODE] key2=hard-disabled customSwitch=disabled nativeHook=disabled menuScan=multiwindow-runtime-graph export=immediate',
    'update mode marker',
)

# 2) Replace the v1.9.22 collection/menu parser with a bounded object-graph walker.
#    Dictionaries no longer return after label/identifier discovery; their values
#    are recursively inspected, so descriptors nested under obfuscated keys survive.
pattern = r'static void hfa_scan_collection\(id a,int apply,unsigned int\*features,unsigned int\*descriptors,int depth\)\{.*?\n\}\n\nstatic int hfa_scan_menu_target\(id o\)\{.*?\n\}\n\n'
replacement = r'''static id gSafeVisited[768];
static unsigned int gSafeVisitedCount=0;

static void hfa_safe_reset(void){gSafeVisitedCount=0;}
static int hfa_safe_seen(id o){
    if(!o)return 1;
    for(unsigned int i=0;i<gSafeVisitedCount;i++)if(gSafeVisited[i]==o)return 1;
    if(gSafeVisitedCount<768)gSafeVisited[gSafeVisitedCount++]=o;
    return 0;
}
static int hfa_is_set_name(const char*s){return hfa_name_has(s,"Set");}
static int hfa_skip_leaf_name(const char*s){
    if(!s||!*s)return 1;
    return hfa_is_string_name(s)||hfa_name_has(s,"Number")||hfa_name_has(s,"Data")||
           hfa_name_has(s,"Date")||hfa_name_has(s,"URL")||hfa_name_has(s,"Value")||
           starts(s,"UI")||starts(s,"_UI")||starts(s,"NS")||starts(s,"__NS")||
           starts(s,"CA")||starts(s,"CG")||starts(s,"Unity")||starts(s,"HFAMap");
}

static void hfa_scan_graph(id o,int apply,unsigned int*features,unsigned int*descriptors,int depth){
    if(!o||depth>5||hfa_safe_seen(o))return;
    Class oc=object_getClass(o);const char*ocn=oc?class_getName(oc):"?";

    if(hfa_is_dict_name(ocn)){
        if(hfa_feature_dict(o,apply)){if(features)(*features)++;}
        if(resp(o,"allValues")){
            id values=M0(id,o,"allValues");
            u64 n=values&&resp(values,"count")?M0(u64,values,"count"):0;if(n>64)n=64;
            for(u64 i=0;i<n;i++)
                hfa_scan_graph(M1(id,values,"objectAtIndex:",u64,i),apply,features,descriptors,depth+1);
        }
        return;
    }

    if(hfa_is_array_name(ocn)){
        if(!resp(o,"count")||!resp(o,"objectAtIndex:"))return;
        u64 n=M0(u64,o,"count");if(n>96)n=96;
        for(u64 i=0;i<n;i++)
            hfa_scan_graph(M1(id,o,"objectAtIndex:",u64,i),apply,features,descriptors,depth+1);
        return;
    }

    if(hfa_is_set_name(ocn)&&resp(o,"allObjects")){
        id a=M0(id,o,"allObjects");
        hfa_scan_graph(a,apply,features,descriptors,depth+1);
        return;
    }

    if(hfa_descriptor_signature(o)){
        if(descriptors)(*descriptors)++;
        if(apply){
            HFARegisterPatchObject(o,ocn);
            hfa_collect_descriptor_fields(o,o,0);
        }
        return;
    }

    if(hfa_skip_leaf_name(ocn)||!customcn(ocn))return;

    Class k=oc;
    for(int level=0;k&&level<5;level++,k=class_getSuperclass(k)){
        unsigned int count=0;Ivar*ivars=class_copyIvarList(k,&count);
        if(count>64)count=64;
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*t=ivar_getTypeEncoding(ivars[i]);
            if(!hfa_obj_type(t))continue;
            id v=object_getIvar(o,ivars[i]);
            if(v)hfa_scan_graph(v,apply,features,descriptors,depth+1);
        }
        free(ivars);
    }
}

static int hfa_scan_menu_target(id o){
    if(!o||o==gTarget)return 0;
    Class c=object_getClass(o);const char*cn=c?class_getName(c):"?";
    if(!cn||!*cn||starts(cn,"UI")||starts(cn,"NS")||starts(cn,"HFAMap"))return 0;

    unsigned int features=0,descriptors=0;
    hfa_safe_reset();
    hfa_scan_graph(o,0,&features,&descriptors,0);
    logf("[SAFE-MENU-CANDIDATE] class=%s ptr=%p features=%u descriptors=%u mode=graph\n",
         cn,o,features,descriptors);
    if(!features||!descriptors)return 0;

    unsigned int appliedFeatures=0,appliedDescriptors=0;
    hfa_safe_reset();
    hfa_scan_graph(o,1,&appliedFeatures,&appliedDescriptors,0);
    logf("[SAFE-MENU-FOUND] class=%s ptr=%p features=%u descriptors=%u mode=graph\n",
         cn,o,appliedFeatures,appliedDescriptors);
    return appliedFeatures&&appliedDescriptors;
}

'''
l = regex_once(l, pattern, replacement, 'replace v1.9.22 parser with bounded graph walker')

# 3) Restore multi-window discovery, but keep the safe runtime-only target parser.
#    Scan keyWindow first, then other visible windows, and stop immediately on success.
pattern = r'static unsigned int run_full_scan\(void\)\{.*?\n\}\nstatic void hooksend'
replacement = r'''static unsigned int hfa_scan_window(id w,const char*mode,u64 index){
    if(!w||gAutoMenuFound)return 0;
    if(resp(w,"isHidden")&&M0(BOOL,w,"isHidden"))return 0;
    double alpha=1.0;if(resp(w,"alpha"))alpha=M0(double,w,"alpha");
    if(alpha<=0.01)return 0;
    logf("[SAFE-MENU-WINDOW] index=%llu ptr=%p mode=%s alpha=%.3f\n",index,w,mode?mode:"?",alpha);
    if(resp(w,"rootViewController")){
        id root=M0(id,w,"rootViewController");
        logf("[SAFE-MENU-ROOT] index=%llu ptr=%p\n",index,root);
        auto_controller(root,0);
    }
    if(!gAutoMenuFound)auto_view(w,0);
    return gAutoMenuFound?1:0;
}

static unsigned int run_full_scan(void){
    gAutoTargetCount=0;gAutoControlCount=0;gAutoMenuFound=0;
    Class ac=objc_getClass("UIApplication");id app=ac?M0(id,(id)ac,"sharedApplication"):0;
    if(!app){gAttached=0;return 0;}

    id key=resp(app,"keyWindow")?M0(id,app,"keyWindow"):0;
    if(key)hfa_scan_window(key,"key-first",0);

    id windows=resp(app,"windows")?M0(id,app,"windows"):0;
    u64 n=windows&&resp(windows,"count")?M0(u64,windows,"count"):0;if(n>32)n=32;
    logf("[SAFE-MENU-WINDOWS] count=%llu key=%p\n",n,key);
    for(u64 i=0;i<n&&!gAutoMenuFound;i++){
        id w=M1(id,windows,"objectAtIndex:",u64,i);
        if(!w||w==key||w==gWindow)continue;
        hfa_scan_window(w,"visible-fallback",i);
    }

    logf("[SAFE-MENU-TRAVERSAL-END] menuFound=%d controls=%u targets=%u windows=%llu\n",
         gAutoMenuFound,gAutoControlCount,gAutoTargetCount,n);
    if(!gAutoMenuFound){
        gAttached=0;
        logf("[SAFE-MENU-NOT-FOUND] no-json-export\n");
        return 0;
    }

    logf("[SAFE-MENU-EXPORT-NOW] begin\n");
    unsigned int valid=HFAPatchTraceFinalizeScan();
    logf("[SAFE-MENU-EXPORT-NOW] end validMappings=%u\n",valid);
    gAttached=0;
    return valid;
}
static void hooksend'''
l = regex_once(l, pattern, replacement, 'restore safe multi-window scan')

# 4) UI wording/version.
l = replace_once(
    l,
    '[HFALearn UI v1.9.22 SafeMenuPatchOnly] loaded',
    '[HFALearn UI v1.9.23 MultiWindowSafePatchOnly] loaded',
    'update UI marker',
)
l = l.replace('HFAMap v1.9.22 Patch Only', 'HFAMap v1.9.23 Patch Only')
l = l.replace('Scanning current menu safely...', 'Scanning visible patch-menu windows safely...')

patch_path.write_text(s)
legacy_path.write_text(l)
