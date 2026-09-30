#import "ZNFeatureDescriptionStore.h"

static NSString * const kZNFeatureDescriptionDefaultsKey = @"zonoe.feature-description.v1";

static NSString *ZNFDTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *ZNFeatureDescriptionNormalizedKey(NSString *featureName) {
    NSString *trimmed = ZNFDTrim(featureName);
    return [[trimmed precomposedStringWithCanonicalMapping] lowercaseString];
}

static NSMutableDictionary<NSString *, NSString *> *ZNFDMutableRoot(void) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:kZNFeatureDescriptionDefaultsKey];
    return [raw isKindOfClass:NSDictionary.class] ? [raw mutableCopy] : [NSMutableDictionary dictionary];
}

NSString *ZNFeatureDescriptionForName(NSString *featureName) {
    NSString *key = ZNFeatureDescriptionNormalizedKey(featureName);
    if (!key.length) return @"";
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:kZNFeatureDescriptionDefaultsKey];
    id value = [raw isKindOfClass:NSDictionary.class] ? raw[key] : nil;
    return [value isKindOfClass:NSString.class] ? value : @"";
}

void ZNSetFeatureDescriptionForName(NSString *featureName, NSString *descriptionText) {
    NSString *key = ZNFeatureDescriptionNormalizedKey(featureName);
    if (!key.length) return;
    NSMutableDictionary *root = ZNFDMutableRoot();
    NSString *clean = ZNFDTrim(descriptionText);
    if (clean.length) root[key] = clean;
    else [root removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNFeatureDescriptionDefaultsKey];
}

void ZNMoveFeatureDescription(NSString *oldFeatureName, NSString *newFeatureName) {
    NSString *oldKey = ZNFeatureDescriptionNormalizedKey(oldFeatureName);
    NSString *newKey = ZNFeatureDescriptionNormalizedKey(newFeatureName);
    if (!oldKey.length || !newKey.length || [oldKey isEqualToString:newKey]) return;
    NSMutableDictionary *root = ZNFDMutableRoot();
    id value = root[oldKey];
    if ([value isKindOfClass:NSString.class] && [value length]) root[newKey] = value;
    [root removeObjectForKey:oldKey];
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNFeatureDescriptionDefaultsKey];
}
