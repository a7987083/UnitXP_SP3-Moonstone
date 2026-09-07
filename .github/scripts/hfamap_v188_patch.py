from pathlib import Path

p = Path("hfamap/src/HFAMapPatchExecutionTrace.m")
s = p.read_text()

replacements = [
    (
        "    char identifier[16];\n",
        "    char identifier[96];\n",
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

static int HFAKnownFeatureIdentifier(const char *identifier) {
    if (!identifier || !*identifier) return 0;
    for (unsigned i = 0; i < gFeatureDefinitionCount; i++) {
        if (strcmp(gFeatureDefinitions[i].identifier, identifier) == 0)
            return 1;
    }
    return 0;
}
""",
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
        """    char identifier[16] = {0};
    if (argument && [argument isKindOfClass:[NSString class]]) {
        const char *s = [(NSString *)argument UTF8String];
        if (s && (strcmp(s, "Fuel") == 0 || strcmp(s, "Boost") == 0))
            snprintf(identifier, sizeof(identifier), "%s", s);
    }
""",
        """    char identifier[96] = {0};
    if (argument && [argument isKindOfClass:[NSString class]]) {
        const char *s = [(NSString *)argument UTF8String];
        if (s && HFAKnownFeatureIdentifier(s))
            snprintf(identifier, sizeof(identifier), "%s", s);
    }
""",
    ),
    (
        """    if (!identifier[0]) return result;

    HFAStateSite *site = HFAStateSiteFor(caller, _cmd, identifier);
""",
        """    if (!identifier[0]) return result;

    HFALog("[CUSTOM-IDENTIFIER] identifier=%s source=state-query\\n", identifier);
    HFAStateSite *site = HFAStateSiteFor(caller, _cmd, identifier);
""",
    ),
    (
        "[HFALearn v1.8.7 KeyRegisterProbe] loaded",
        "[HFALearn v1.8.8 GenericCustomSwitchProbe] loaded",
    ),
]

for old, new in replacements:
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one source fragment, found {count}: {old[:100]!r}")
    s = s.replace(old, new, 1)

p.write_text(s)
