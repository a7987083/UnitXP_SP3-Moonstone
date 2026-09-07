from pathlib import Path

legacy_path = Path("hfamap/src/HFAMapLegacy.m")
patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")

l = legacy_path.read_text()

replacements = [
    (
        'static void dump_own(id o,const char*tag,int depth);\nstatic void dump_dictionary(id d,int depth){',
        'static void dump_own(id o,const char*tag,int depth);\nstatic void dump_collection(id o,const char*cn,int depth);\nstatic void dump_dictionary(id d,int depth){',
    ),
    (
        'char ident[96]={0},label[256]={0},type[64]={0};',
        'char ident[96]={0},label[256]={0},type[64]={0};long long selected=-1;id dynamicTarget=0;',
    ),
    (
        'else if(ks&&vs&&ceq(ks,"label"))copyc(label,vs,sizeof(label));else if(ks&&vs&&ceq(ks,"type"))copyc(type,vs,sizeof(type));',
        'else if(ks&&vs&&ceq(ks,"label"))copyc(label,vs,sizeof(label));else if(ks&&vs&&ceq(ks,"type"))copyc(type,vs,sizeof(type));else if(ks&&ceq(ks,"selected")&&v&&resp(v,"longLongValue"))selected=M0(long long,v,"longLongValue");else if(ks&&ceq(ks,"dynamicTarget"))dynamicTarget=v;',
    ),
    (
        'if(label[0]&&ident[0]){HFARegisterFeatureDefinition(label,ident);if(type[0])HFARegisterFeatureType(ident,type);logf("[FEATURE-SCHEMA] identifier=%s label=%s type=%s\\n",ident,label,type[0]?type:"?");}',
        'if(label[0]&&ident[0]){HFARegisterFeatureDefinition(label,ident);if(type[0])HFARegisterFeatureType(ident,type);logf("[FEATURE-SCHEMA] identifier=%s label=%s type=%s\\n",ident,label,type[0]?type:"?");if(selected>=0)logf("[SELECTED] identifier=%s selected=%lld type=%s\\n",ident,selected,type[0]?type:"?");if(dynamicTarget){Class dc=M0(Class,dynamicTarget,"class");const char*dcn=dc?class_getName(dc):"?";const char*dvs=utf8(dynamicTarget);logf("[DYNAMIC-TARGET] identifier=%s selected=%lld type=%s class=%s ptr=%p value=%s\\n",ident,selected,type[0]?type:"?",dcn,dynamicTarget,dvs?dvs:"?");if(selected==1)logf("[DYNAMIC-TARGET-ACTIVE] identifier=%s class=%s ptr=%p\\n",ident,dcn,dynamicTarget);}}',
    ),
    (
        'if(ident[0]&&strstr(vcn,"Block"))HFARegisterCustomBlock(v,ident);',
        'if(ident[0]&&strstr(vcn,"Block"))HFARegisterCustomBlock(v,ident);if(ident[0]&&ks&&ceq(ks,"dynamicTarget")&&v){logf("[DYNAMIC-TARGET-KV] identifier=%s selected=%lld class=%s ptr=%p value=%s\\n",ident,selected,vcn,v,vs?vs:"?");if(strstr(vcn,"Dictionary"))dump_dictionary(v,depth+1);else if(strstr(vcn,"Array"))dump_collection(v,vcn,depth+1);else if(customcn(vcn))dump_own(v,"DYNAMIC-TARGET",depth+1);}',
    ),
    (
        'static void maybe_expand_line(id owner,const char*ownerClass,const char*s,const char*e,int depth){if(depth>1)return;',
        'static void maybe_expand_line(id owner,const char*ownerClass,const char*s,const char*e,int depth){if(depth>1)return;if(findn(s,e,"selected"))logf("[SELECTED-LINE] ownerClass=%s owner=%p line=%.*s\\n",ownerClass?ownerClass:"?",owner,(int)(e-s),s);if(findn(s,e,"dynamicTarget"))logf("[DYNAMIC-TARGET-LINE] ownerClass=%s owner=%p line=%.*s\\n",ownerClass?ownerClass:"?",owner,(int)(e-s),s);',
    ),
    (
        '[HFALearn UI v1.8.9 MenuFrameworkAnchorProbe] loaded',
        '[HFALearn UI v1.9.1 DynamicTargetProbe] loaded',
    ),
]

for old, new in replacements:
    count = l.count(old)
    if count != 1:
        raise SystemExit(f"HFAMapLegacy.m expected one fragment, found {count}: {old[:140]!r}")
    l = l.replace(old, new, 1)

legacy_path.write_text(l)

s = patch_path.read_text()
old_marker = '[HFALearn v1.8.9 MenuFrameworkAnchorProbe] loaded'
new_marker = '[HFALearn v1.9.1 DynamicTargetProbe] loaded'
if s.count(old_marker) != 1:
    raise SystemExit(f"HFAMapPatchExecutionTrace.m expected marker once, found {s.count(old_marker)}")
s = s.replace(old_marker, new_marker, 1)
patch_path.write_text(s)
