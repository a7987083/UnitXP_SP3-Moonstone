from pathlib import Path

patch_path = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
legacy_path = Path("hfamap/src/HFAMapLegacy.m")

s = patch_path.read_text()

replacements = [
    (
        "    char identifier[16];\n",
        "    char identifier[96];\n",
    ),
    (
        """typedef struct {
    char label[256];
    char identifier[96];
    char key[128];
} HFAFeatureDefinition;
""",
        """typedef struct {
    char label[256];
    char identifier[96];
    char key[128];
    char type[64];
} HFAFeatureDefinition;
""",
    ),
    (
        """static HFAFeatureDefinition *HFAFeatureDefinitionForKey(const char *key) {
    if (!key || !*key) return NULL;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++)
        if (strcmp(gFeatureDefinitions[i].key, key) == 0)
            return &gFeatureDefinitions[i];
    return NULL;
}
""",
        """static HFAFeatureDefinition *HFAFeatureDefinitionForKey(const char *key) {
    if (!key || !*key) return NULL;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++)
        if (strcmp(gFeatureDefinitions[i].key, key) == 0)
            return &gFeatureDefinitions[i];
    return NULL;
}

static HFAFeatureDefinition *HFAFeatureDefinitionForIdentifier(const char *identifier) {
    if (!identifier || !*identifier) return NULL;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++)
        if (strcmp(gFeatureDefinitions[i].identifier, identifier) == 0)
            return &gFeatureDefinitions[i];
    return NULL;
}

static int HFAKnownFeatureIdentifier(const char *identifier) {
    return HFAFeatureDefinitionForIdentifier(identifier) != NULL;
}

static int HFACurrentFeatureIsCustomSwitch(void) {
    HFAFeatureDefinition *definition = HFAFeatureDefinitionForIdentifier(gIdentifier);
    return definition && definition->type[0] &&
           strcmp(definition->type, "customSwitch") == 0;
}
""",
    ),
    (
        """    snprintf(definition->key, sizeof(definition->key), "%s", key);
}

static HFAFeatureDefinition *HFAFeatureDefinitionForKey""",
        """    snprintf(definition->key, sizeof(definition->key), "%s", key);
}

void HFARegisterFeatureType(const char *identifier, const char *type) {
    if (!identifier || !*identifier || !type || !*type) return;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        HFAFeatureDefinition *definition = &gFeatureDefinitions[i];
        if (strcmp(definition->identifier, identifier) != 0) continue;
        snprintf(definition->type, sizeof(definition->type), "%s", type);
        return;
    }
}

static HFAFeatureDefinition *HFAFeatureDefinitionForKey""",
    ),
    (
        """void HFARegisterCustomBlock(id value, const char *identifier) {
    if (!value || !identifier ||
        (strcmp(identifier, "Fuel") != 0 && strcmp(identifier, "Boost") != 0))
        return;
""",
        """void HFARegisterCustomBlock(id value, const char *identifier) {
    if (!value || !identifier || !HFAKnownFeatureIdentifier(identifier))
        return;
""",
    ),
    (
        """static HFAStateSite *HFAStateSiteFor(uintptr_t caller, SEL query,
                                     const char *identifier) {
""",
        """void HFARegisterMenuAnchorBlock(id value, const char *ownerClass) {
    if (!value || !gIdentifier[0] || !HFACurrentFeatureIsCustomSwitch()) return;
    HFALog("[MENU-ANCHOR-BLOCK] event=%u identifier=%s ownerClass=%s block=%p\\n",
           gEvent, gIdentifier, ownerClass && *ownerClass ? ownerClass : "?", value);
    HFARegisterCustomBlock(value, gIdentifier);
}

static HFAStateSite *HFAStateSiteFor(uintptr_t caller, SEL query,
                                     const char *identifier) {
""",
    ),
    (
        """    char identifier[16] = {0};
    if (argument && [argument isKindOfClass:[NSString class]]) {
        const char *s = [(NSString *)argument UTF8String];
        if (s && (strcmp(s, "Fuel") == 0 || strcmp(s, "Boost") == 0))
            snprintf(identifier, sizeof(identifier), "%s", s);
    }
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    uintptr_t result = ((uintptr_t(*)(id,SEL,id))hook->original)(self, _cmd, argument);
    if (!identifier[0]) return result;

    HFAStateSite *site = HFAStateSiteFor(caller, _cmd, identifier);
""",
        """    char identifier[96] = {0};
    const char *identifierSource = "none";
    if (argument && [argument isKindOfClass:[NSString class]]) {
        const char *s = [(NSString *)argument UTF8String];
        if (s && HFAKnownFeatureIdentifier(s)) {
            snprintf(identifier, sizeof(identifier), "%s", s);
            identifierSource = "argument";
        }
    }
    if (!identifier[0] && gIdentifier[0] &&
        HFAKnownFeatureIdentifier(gIdentifier) && HFACurrentFeatureIsCustomSwitch()) {
        snprintf(identifier, sizeof(identifier), "%s", gIdentifier);
        identifierSource = "armed-customSwitch";
    }
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    uintptr_t result = ((uintptr_t(*)(id,SEL,id))hook->original)(self, _cmd, argument);
    if (!identifier[0]) return result;

    HFALog("[CUSTOM-IDENTIFIER] identifier=%s source=%s selector=%s\\n",
           identifier, identifierSource, sel_getName(_cmd));
    HFAStateSite *site = HFAStateSiteFor(caller, _cmd, identifier);
""",
    ),
    (
        "[HFALearn v1.8.7 KeyRegisterProbe] loaded",
        "[HFALearn v1.8.9 MenuFrameworkAnchorProbe] loaded",
    ),
]

for old, new in replacements:
    count = s.count(old)
    if count != 1:
        raise SystemExit(
            f"HFAMapPatchExecutionTrace.m expected exactly one source fragment, "
            f"found {count}: {old[:120]!r}"
        )
    s = s.replace(old, new, 1)

patch_path.write_text(s)

l = legacy_path.read_text()

legacy_replacements = [
    (
        "extern void HFARegisterFeatureDefinition(const char*,const char*); extern void HFARegisterCustomBlock(id,const char*);",
        "extern void HFARegisterFeatureDefinition(const char*,const char*); extern void HFARegisterFeatureType(const char*,const char*); extern void HFARegisterCustomBlock(id,const char*); extern void HFARegisterMenuAnchorBlock(id,const char*);",
    ),
    (
        'char ident[96]={0},label[256]={0};',
        'char ident[96]={0},label[256]={0},type[64]={0};',
    ),
    (
        'else if(ks&&vs&&ceq(ks,"label"))copyc(label,vs,sizeof(label));',
        'else if(ks&&vs&&ceq(ks,"label"))copyc(label,vs,sizeof(label));else if(ks&&vs&&ceq(ks,"type"))copyc(type,vs,sizeof(type));',
    ),
    (
        'if(label[0]&&ident[0])HFARegisterFeatureDefinition(label,ident);',
        'if(label[0]&&ident[0]){HFARegisterFeatureDefinition(label,ident);if(type[0])HFARegisterFeatureType(ident,type);logf("[FEATURE-SCHEMA] identifier=%s label=%s type=%s\\n",ident,label,type[0]?type:"?");}',
    ),
    (
        """static void dump_own(id o,const char*tag,int depth){const char*dsname=(depth==2)?"_methodDescription":"_ivarDescription";if(!o||depth>2||!resp(o,dsname))return;Class c=M0(Class,o,"class");const char*cn=c?class_getName(c):"?";id ds=M0(id,o,dsname);const char*s=ds?(const char*)M0(void*,ds,"UTF8String"):0;if(!s)return;const char*p=strstr(s,"\\nin ");if(!p)return;p++;const char*hdrEnd=p;while(*hdrEnd&&*hdrEnd!='\\n')hdrEnd++;if(!*hdrEnd)return;p=hdrEnd+1;logf("  [%s-OWN] class=%s ptr=%p depth=%d\\n",tag,cn,o,depth);int lines=0;while(*p&&lines<96){const char*e=p;while(*e&&*e!='\\n')e++;if(starts(p,"in "))break;size_t n=(size_t)(e-p);if(n){if(n>220)logf("    %.*s ... [lineLen=%llu]\\n",180,p,(u64)n);else {logf("    %.*s\\n",(int)n,p);maybe_expand_line(o,cn,p,e,depth);}lines++;}if(!*e)break;p=e+1;}}
""",
        """static void maybe_anchor_block(const char*ownerClass,const char*s,const char*e){const char*q=findn(s,e,"): <");if(!q)return;const char*lt=q+4;const char*colon=lt;while(colon<e&&*colon!=':')colon++;if(colon>=e)return;char cn[96];size_t n=(size_t)(colon-lt);if(n>=sizeof(cn))n=sizeof(cn)-1;memcpy(cn,lt,n);cn[n]=0;if(!strstr(cn,"Block"))return;const char*px=findn(colon,e,"0x");if(!px)return;u64 v=hexptr(px);if(!v)return;HFARegisterMenuAnchorBlock((id)(size_t)v,ownerClass);}
static void dump_own(id o,const char*tag,int depth){const char*dsname=(depth==2)?"_methodDescription":"_ivarDescription";if(!o||depth>2||!resp(o,dsname))return;Class c=M0(Class,o,"class");const char*cn=c?class_getName(c):"?";id ds=M0(id,o,dsname);const char*s=ds?(const char*)M0(void*,ds,"UTF8String"):0;if(!s)return;int menuAnchor=strstr(s,"Made by Laxus for iOSGods.com!")&&strstr(s,"Made for iOSGods.com");if(menuAnchor)logf("[MENU-ANCHOR] class=%s ptr=%p depth=%d\\n",cn,o,depth);const char*p=strstr(s,"\\nin ");if(!p)return;p++;const char*hdrEnd=p;while(*hdrEnd&&*hdrEnd!='\\n')hdrEnd++;if(!*hdrEnd)return;p=hdrEnd+1;logf("  [%s-OWN] class=%s ptr=%p depth=%d\\n",tag,cn,o,depth);int lines=0;while(*p&&lines<96){const char*e=p;while(*e&&*e!='\\n')e++;if(starts(p,"in "))break;size_t n=(size_t)(e-p);if(n){if(n>220)logf("    %.*s ... [lineLen=%llu]\\n",180,p,(u64)n);else {logf("    %.*s\\n",(int)n,p);maybe_expand_line(o,cn,p,e,depth);if(menuAnchor)maybe_anchor_block(cn,p,e);}lines++;}if(!*e)break;p=e+1;}}
""",
    ),
    (
        "[HFALearn UI v1.8.7 KeyRegisterProbe] loaded",
        "[HFALearn UI v1.8.9 MenuFrameworkAnchorProbe] loaded",
    ),
]

for old, new in legacy_replacements:
    count = l.count(old)
    if count != 1:
        raise SystemExit(
            f"HFAMapLegacy.m expected exactly one source fragment, "
            f"found {count}: {old[:120]!r}"
        )
    l = l.replace(old, new, 1)

legacy_path.write_text(l)
