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

# v1.9.22 goal:
# - keep only ordinary patchDescriptor extraction/export
# - never use private _ivarDescription/_methodDescription in automatic menu scan
# - scan only the current key/fallback window, not every UIApplication window
# - identify a menu target structurally with Objective-C runtime ivar metadata
# - once found, extract descriptors + feature dictionaries and immediately export
# - keyId=2 is a hard skip: do not call the decrypt routine at all

# 1) Key2 hard stop before decrypt.
old = r'''    if ((flags >> 24) == 2u)
        HFALog("[PATCH-ONLY-KEY2-SKIP] field=%s image=%s getterRVA=%llX reason=disabled\n",
               label, HFABase(getterInfo.dli_fname),
               (unsigned long long)getterRVA);
    int rc = ((HFASecretDecryptFn)decryptAddress)(copy, plain);
'''
new = r'''    if ((flags >> 24) == 2u) {
        HFALog("[PATCH-ONLY-KEY2-SKIP] field=%s image=%s getterRVA=%llX reason=disabled-no-decrypt\n",
               label, HFABase(getterInfo.dli_fname),
               (unsigned long long)getterRVA);
        free(plain);
        free(copy);
        return 0;
    }
    int rc = ((HFASecretDecryptFn)decryptAddress)(copy, plain);
'''
s = replace_once(s, old, new, "hard-disable Key2 decrypt")

old = '[HFALearn v1.9.21 PatchOnlyImmediateExport] loaded'
new = '[HFALearn v1.9.22 SafeMenuPatchOnly] loaded'
s = replace_once(s, old, new, "update core marker")

old = '[PATCH-ONLY-MODE] key2=disabled customSwitch=disabled nativeHook=disabled export=immediate'
new = '[PATCH-ONLY-MODE] key2=hard-disabled customSwitch=disabled nativeHook=disabled menuScan=safe-runtime-ivar export=immediate'
s = replace_once(s, old, new, "update patch-only mode marker")

# 2) Add only the runtime APIs needed for safe ivar metadata/object access.
decl_anchor = 'extern Class objc_allocateClassPair(Class,const char*,size_t); extern BOOL class_addMethod(Class,SEL,IMP,const char*); extern void objc_registerClassPair(Class);\n'
decl_insert = decl_anchor + (
    'typedef struct objc_ivar* Ivar;\n'
    'extern Class object_getClass(id); extern Class class_getSuperclass(Class); '
    'extern Ivar* class_copyIvarList(Class,unsigned int*); '
    'extern const char* ivar_getTypeEncoding(Ivar); extern id object_getIvar(id,Ivar);\n'
)
l = replace_once(l, decl_anchor, decl_insert, "add runtime ivar declarations")

# 3) Safe structural menu parser. It never calls _ivarDescription/_methodDescription.
anchor = 'static id gAutoTargets[256];static unsigned int gAutoTargetCount=0,gAutoControlCount=0;static int gAutoMenuFound=0;\n'
helpers = r'''static int hfa_obj_type(const char*t){return t&&t[0]=='@'&&t[1]!='?';}
static int hfa_name_has(const char*s,const char*n){return s&&n&&strstr(s,n)!=0;}
static int hfa_is_array_name(const char*s){return hfa_name_has(s,"Array");}
static int hfa_is_dict_name(const char*s){return hfa_name_has(s,"Dictionary");}
static int hfa_is_string_name(const char*s){return hfa_name_has(s,"String");}

static int hfa_feature_dict(id d,int apply){
    if(!d||!resp(d,"objectForKey:"))return 0;
    id labelObj=M1(id,d,"objectForKey:",id,ns("label"));
    id identObj=M1(id,d,"objectForKey:",id,ns("identifier"));
    const char*label=utf8(labelObj),*ident=utf8(identObj);
    if(!label||!*label||!ident||!*ident)return 0;
    if(apply)HFARegisterFeatureDefinition(label,ident);
    return 1;
}

static int hfa_descriptor_signature(id o){
    if(!o)return 0;
    Class c=object_getClass(o);
    int signature=0;
    for(int level=0;c&&level<6&&!signature;level++,c=class_getSuperclass(c)){
        unsigned int count=0;Ivar*ivars=class_copyIvarList(c,&count);
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*t=ivar_getTypeEncoding(ivars[i]);
            if(!t)continue;
            if(hfa_name_has(t,"IGSecretData")||hfa_name_has(t,"IGSecretInt")||
               hfa_name_has(t,"APColorModifier")||hfa_name_has(t,"APSubpatchManager")){
                signature=1;break;
            }
        }
        free(ivars);
    }
    return signature;
}

static void hfa_collect_descriptor_fields(id owner,id o,int depth){
    if(!owner||!o||depth>4)return;
    Class c=object_getClass(o);
    for(int level=0;c&&level<6;level++,c=class_getSuperclass(c)){
        unsigned int count=0;Ivar*ivars=class_copyIvarList(c,&count);
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*t=ivar_getTypeEncoding(ivars[i]);
            if(!hfa_obj_type(t))continue;
            id v=object_getIvar(o,ivars[i]);
            if(!v)continue;
            Class vc=object_getClass(v);
            const char*vcn=vc?class_getName(vc):"?";
            if(hfa_is_string_name(vcn)){
                const char*sv=utf8(v);
                if(sv&&*sv)HFARegisterPatchString(owner,sv);
                continue;
            }
            if(hfa_name_has(t,"IGSecretData")){
                HFARegisterPatchSecret(owner,v,"IGSecretData");
                hfa_collect_descriptor_fields(owner,v,depth+1);
                continue;
            }
            if(hfa_name_has(t,"IGSecretInt")){
                HFARegisterPatchSecret(owner,v,"IGSecretInt");
                hfa_collect_descriptor_fields(owner,v,depth+1);
                continue;
            }
        }
        free(ivars);
    }
}

static void hfa_scan_collection(id a,int apply,unsigned int*features,unsigned int*descriptors,int depth){
    if(!a||depth>3)return;
    Class ac=object_getClass(a);const char*acn=ac?class_getName(ac):"?";
    if(hfa_is_dict_name(acn)){
        if(hfa_feature_dict(a,apply)){if(features)(*features)++;}
        return;
    }
    if(!hfa_is_array_name(acn)||!resp(a,"count")||!resp(a,"objectAtIndex:"))return;
    u64 n=M0(u64,a,"count");if(n>96)n=96;
    for(u64 i=0;i<n;i++){
        id item=M1(id,a,"objectAtIndex:",u64,i);if(!item)continue;
        Class ic=object_getClass(item);const char*icn=ic?class_getName(ic):"?";
        if(hfa_is_dict_name(icn)){
            if(hfa_feature_dict(item,apply)){if(features)(*features)++;}
            continue;
        }
        if(hfa_is_array_name(icn)){
            hfa_scan_collection(item,apply,features,descriptors,depth+1);
            continue;
        }
        if(hfa_descriptor_signature(item)){
            if(descriptors)(*descriptors)++;
            if(apply){
                HFARegisterPatchObject(item,icn);
                hfa_collect_descriptor_fields(item,item,0);
            }
        }
    }
}

static int hfa_scan_menu_target(id o){
    if(!o||o==gTarget)return 0;
    Class c=object_getClass(o);const char*cn=c?class_getName(c):"?";
    if(!cn||!*cn||starts(cn,"UI")||starts(cn,"NS")||starts(cn,"HFAMap"))return 0;

    unsigned int features=0,descriptors=0;
    Class k=c;
    for(int intLevel=0;k&&intLevel<6;intLevel++,k=class_getSuperclass(k)){
        unsigned int count=0;Ivar*ivars=class_copyIvarList(k,&count);
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*t=ivar_getTypeEncoding(ivars[i]);
            if(!hfa_obj_type(t))continue;
            id v=object_getIvar(o,ivars[i]);if(!v)continue;
            Class vc=object_getClass(v);const char*vcn=vc?class_getName(vc):"?";
            if(hfa_is_array_name(vcn)||hfa_is_dict_name(vcn))
                hfa_scan_collection(v,0,&features,&descriptors,0);
        }
        free(ivars);
    }
    logf("[SAFE-MENU-CANDIDATE] class=%s ptr=%p features=%u descriptors=%u\n",
         cn,o,features,descriptors);
    if(!features||!descriptors)return 0;

    unsigned int appliedFeatures=0,appliedDescriptors=0;
    k=c;
    for(int intLevel=0;k&&intLevel<6;intLevel++,k=class_getSuperclass(k)){
        unsigned int count=0;Ivar*ivars=class_copyIvarList(k,&count);
        for(unsigned int i=0;ivars&&i<count;i++){
            const char*t=ivar_getTypeEncoding(ivars[i]);
            if(!hfa_obj_type(t))continue;
            id v=object_getIvar(o,ivars[i]);if(!v)continue;
            Class vc=object_getClass(v);const char*vcn=vc?class_getName(vc):"?";
            if(hfa_is_array_name(vcn)||hfa_is_dict_name(vcn))
                hfa_scan_collection(v,1,&appliedFeatures,&appliedDescriptors,0);
        }
        free(ivars);
    }
    logf("[SAFE-MENU-FOUND] class=%s ptr=%p features=%u descriptors=%u\n",
         cn,o,appliedFeatures,appliedDescriptors);
    return appliedFeatures&&appliedDescriptors;
}

'''
l = replace_once(l, anchor, helpers + anchor, "insert safe menu runtime helpers")

# 4) Replace auto_target with safe structural probing only.
pattern = r'static void auto_target\(id o\)\{.*?\n\}\nstatic void auto_view\(id v,int depth\)\{'
replacement = r'''static void auto_target(id o){
    if(!o||o==gTarget||auto_seen(o)||gAutoTargetCount>=256)return;
    gAutoTargets[gAutoTargetCount++]=o;
    if(hfa_scan_menu_target(o))gAutoMenuFound=1;
}
static void auto_view(id v,int depth){'''
l = regex_once(l, pattern, replacement, "replace unsafe auto_target")

# 5) Scan only the current key window (single fallback window if keyWindow is nil).
pattern = r'static unsigned int run_full_scan\(void\)\{.*?\n\}\nstatic void hooksend'
replacement = r'''static unsigned int run_full_scan(void){
    gAutoTargetCount=0;gAutoControlCount=0;gAutoMenuFound=0;
    Class ac=objc_getClass("UIApplication");id app=ac?M0(id,(id)ac,"sharedApplication"):0;
    id w=app&&resp(app,"keyWindow")?M0(id,app,"keyWindow"):0;
    if(!w){
        id windows=app&&resp(app,"windows")?M0(id,app,"windows"):0;
        u64 n=windows&&resp(windows,"count")?M0(u64,windows,"count"):0;
        if(n)w=M1(id,windows,"objectAtIndex:",u64,n-1);
    }
    logf("[SAFE-MENU-WINDOW] ptr=%p mode=current-key-window\n",w);
    if(!w){gAttached=0;return 0;}

    if(resp(w,"rootViewController")){
        id root=M0(id,w,"rootViewController");
        logf("[SAFE-MENU-ROOT] ptr=%p\n",root);
        auto_controller(root,0);
    }
    if(!gAutoMenuFound)auto_view(w,0);

    logf("[SAFE-MENU-TRAVERSAL-END] menuFound=%d controls=%u targets=%u\n",
         gAutoMenuFound,gAutoControlCount,gAutoTargetCount);
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
l = regex_once(l, pattern, replacement, "replace all-window full scan")

# 6) Patch-only scan has no need for global UIControl sendAction swizzling.
l = replace_once(
    l,
    'static void tick(id self,SEL c,id timer){(void)self;(void)c;(void)timer;tryhook();id w=win();',
    'static void tick(id self,SEL c,id timer){(void)self;(void)c;(void)timer;id w=win();',
    "disable global UIControl hook"
)
l = replace_once(
    l,
    'static void tryhook(void){',
    'static __attribute__((unused)) void tryhook(void){',
    "mark disabled tryhook unused"
)

# 7) UI/status/version wording.
l = replace_once(
    l,
    '[HFALearn UI v1.9.21 PatchOnlyImmediateExport] loaded',
    '[HFALearn UI v1.9.22 SafeMenuPatchOnly] loaded',
    "update UI marker"
)
l = l.replace('HFAMap v1.8.7 Key Register', 'HFAMap v1.9.22 Patch Only')
l = l.replace('Auto Detect / Full Scan', 'Scan Menu / Export JSON')
l = l.replace('Scanning the complete menu...', 'Scanning current menu safely...')
l = l.replace('Full scan completed.\\nMappings saved to HFAMap_Mapping.log',
              'Patch scan completed.\\nStandard .hfapatch.json exported')
l = l.replace('No Patch descriptors found.\\nOpen the game menu and scan again.',
              'Menu/Patch descriptors not found.\\nOpen the patch menu and scan again.')
l = l.replace('Key registration is fingerprinted without table guesses.\\nOpen the menu, scan, then repeat user recognition.',
              'Patch-only safe scan.\\nOpen the patch menu, then scan/export JSON.')

patch_path.write_text(s)
legacy_path.write_text(l)
