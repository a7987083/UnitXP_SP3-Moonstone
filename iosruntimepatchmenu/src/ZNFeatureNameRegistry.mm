#import "ZNFeatureNameRegistry.h"

static NSString * const kZNFeatureNameRegistryDefaultsKey = @"zonoe.feature-name-registry.v1";

static NSString *ZNFeatureNameTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNFeatureNameRegistryKey(NSString *target, uint64_t siteRVA, uint32_t patchID) {
    NSString *normalized = ZNFeatureNameTrim(target).lowercaseString;
    return [NSString stringWithFormat:@"%@|%016llx|%u", normalized, siteRVA, patchID];
}

void ZNFeatureNameRegistryStore(NSString *target,
                                uint64_t siteRVA,
                                uint32_t patchID,
                                NSString *title,
                                NSString *group) {
    if (!target.length || !patchID) return;

    NSString *cleanTitle = ZNFeatureNameTrim(title);
    NSString *cleanGroup = ZNFeatureNameTrim(group);
    if (!cleanTitle.length && !cleanGroup.length) return;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    @synchronized (defaults) {
        NSMutableDictionary *registry = [[defaults dictionaryForKey:kZNFeatureNameRegistryDefaultsKey] mutableCopy];
        if (!registry) registry = [NSMutableDictionary dictionary];

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        if (cleanTitle.length) entry[@"title"] = cleanTitle;
        if (cleanGroup.length) entry[@"group"] = cleanGroup;
        registry[ZNFeatureNameRegistryKey(target, siteRVA, patchID)] = entry;
        [defaults setObject:registry forKey:kZNFeatureNameRegistryDefaultsKey];
    }
}

NSDictionary<NSString *, NSString *> *ZNFeatureNameRegistryLookup(NSString *target,
                                                                   uint64_t siteRVA,
                                                                   uint32_t patchID) {
    if (!target.length || !patchID) return nil;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    @synchronized (defaults) {
        NSDictionary *registry = [defaults dictionaryForKey:kZNFeatureNameRegistryDefaultsKey];
        NSDictionary *entry = registry[ZNFeatureNameRegistryKey(target, siteRVA, patchID)];
        return [entry isKindOfClass:NSDictionary.class] ? [entry copy] : nil;
    }
}
