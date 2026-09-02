#import "HFAPatchConfig.h"
#import "HFAPatchLogger.h"

#include <errno.h>
#include <stdlib.h>

static NSString *const HFAPatchConfigErrorDomain = @"com.hfa.patchmenu.config";

typedef NS_ENUM(NSInteger, HFAPatchConfigErrorCode) {
    HFAPatchConfigErrorMissing = 1,
    HFAPatchConfigErrorJSON,
    HFAPatchConfigErrorSchema,
    HFAPatchConfigErrorField,
};

@implementation HFAPatchTarget
@end

@implementation HFAPatchOperation
@end

@implementation HFAPatchFeature
@end

@implementation HFAPatchPackageIdentity
@end

static NSError *HFAPatchConfigError(HFAPatchConfigErrorCode code, NSString *message)
{
    return [NSError errorWithDomain:HFAPatchConfigErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid configuration"}];
}

static NSString *HFAPatchRequiredString(NSDictionary *dictionary,
                                        NSString *key,
                                        NSString *context,
                                        NSError **error)
{
    id value = dictionary[key];
    if (![value isKindOfClass:NSString.class] || [(NSString *)value length] == 0) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                [NSString stringWithFormat:@"%@.%@ must be a non-empty string", context, key]);
        return nil;
    }
    return value;
}

NSString *HFAPatchNormalizedUUID(NSString *value)
{
    NSString *normalized = [[value stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
    return normalized ?: @"";
}

static BOOL HFAPatchIsValidNormalizedUUID(NSString *value)
{
    if (value.length != 32) return NO;
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"];
    return [value rangeOfCharacterFromSet:hexSet.invertedSet].location == NSNotFound;
}

static NSData *HFAPatchDataFromHex(NSString *hex, NSString *context, NSError **error)
{
    NSString *clean = [[[hex stringByReplacingOccurrencesOfString:@" " withString:@""]
                        stringByReplacingOccurrencesOfString:@"\n" withString:@""] uppercaseString];
    if ([clean hasPrefix:@"0X"]) clean = [clean substringFromIndex:2];
    if (clean.length == 0 || (clean.length % 2) != 0) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                [NSString stringWithFormat:@"%@ must contain complete hexadecimal bytes", context]);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithCapacity:clean.length / 2];
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"];
    for (NSUInteger index = 0; index < clean.length; index += 2) {
        NSString *pair = [clean substringWithRange:NSMakeRange(index, 2)];
        if ([pair rangeOfCharacterFromSet:hexSet.invertedSet].location != NSNotFound) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                    [NSString stringWithFormat:@"%@ contains non-hexadecimal characters", context]);
            return nil;
        }
        unsigned value = 0;
        [[NSScanner scannerWithString:pair] scanHexInt:&value];
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

static BOOL HFAPatchParseOffset(id raw, uint64_t *result)
{
    if ([raw isKindOfClass:NSNumber.class]) {
        long long signedValue = [raw longLongValue];
        if (signedValue < 0) return NO;
        *result = [raw unsignedLongLongValue];
        return YES;
    }
    if (![raw isKindOfClass:NSString.class]) return NO;

    NSString *string = [(NSString *)raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (string.length == 0 || [string hasPrefix:@"-"]) return NO;
    const char *start = string.UTF8String;
    int base = 10;
    if ([string.lowercaseString hasPrefix:@"0x"]) {
        start += 2;
        base = 16;
    }
    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(start, &end, base);
    if (errno == ERANGE || end == start || !end || *end != '\0') return NO;
    *result = value;
    return YES;
}

NSString *HFAPatchHexString(NSData *data)
{
    const uint8_t *bytes = data.bytes;
    NSMutableString *result = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger index = 0; index < data.length; index++) {
        [result appendFormat:@"%02X", bytes[index]];
    }
    return result;
}

@implementation HFAPatchConfiguration

+ (instancetype)loadPreferredConfigurationWithError:(NSError **)error
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *external = HFAPatchExternalConfigPath();
    NSString *selected = nil;

    if ([manager fileExistsAtPath:external]) {
        selected = external;
    } else {
        selected = [NSBundle.mainBundle pathForResource:@"default.hfapatch"
                                                 ofType:@"json"
                                            inDirectory:@"HFAPatch"];
        if (selected.length == 0) {
            selected = [NSBundle.mainBundle pathForResource:@"default.hfapatch" ofType:@"json"];
        }
    }

    if (selected.length == 0) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorMissing,
                                                [NSString stringWithFormat:@"No config at %@ or in the app bundle", external]);
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:selected options:0 error:error];
    if (!data) return nil;
    return [self configurationWithData:data sourcePath:selected error:error];
}

+ (instancetype)configurationWithData:(NSData *)data
                             sourcePath:(NSString *)sourcePath
                                  error:(NSError **)error
{
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = HFAPatchConfigError(HFAPatchConfigErrorJSON, @"Root JSON value must be an object");
        return nil;
    }

    NSDictionary *dictionary = root;
    NSString *schema = HFAPatchRequiredString(dictionary, @"schema", @"root", error);
    if (!schema) return nil;
    if (![schema isEqualToString:@"com.hfa.patch/v1"]) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorSchema,
                                                [NSString stringWithFormat:@"Unsupported schema: %@", schema]);
        return nil;
    }

    NSDictionary *packageJSON = dictionary[@"package"];
    if (![packageJSON isKindOfClass:NSDictionary.class]) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField, @"root.package must be an object");
        return nil;
    }

    HFAPatchPackageIdentity *identity = [[HFAPatchPackageIdentity alloc] init];
    identity.bundleIdentifier = HFAPatchRequiredString(packageJSON, @"bundleIdentifier", @"package", error);
    identity.shortVersion = HFAPatchRequiredString(packageJSON, @"shortVersion", @"package", error);
    identity.buildVersion = HFAPatchRequiredString(packageJSON, @"buildVersion", @"package", error);
    if (!identity.bundleIdentifier || !identity.shortVersion || !identity.buildVersion) return nil;

    NSArray *architectures = packageJSON[@"architectures"];
    if (![architectures isKindOfClass:NSArray.class] || architectures.count == 0) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField, @"package.architectures must be a non-empty array");
        return nil;
    }
    NSMutableArray *validatedArchitectures = [NSMutableArray array];
    for (id architecture in architectures) {
        if (![architecture isKindOfClass:NSString.class] || [architecture length] == 0 ||
            (![(NSString *)architecture isEqualToString:@"arm64"] && ![(NSString *)architecture isEqualToString:@"arm64e"])) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                    @"package.architectures supports only arm64 and arm64e in v1");
            return nil;
        }
        [validatedArchitectures addObject:architecture];
    }
    identity.architectures = validatedArchitectures;

    NSDictionary *targetsJSON = dictionary[@"targets"];
    if (![targetsJSON isKindOfClass:NSDictionary.class] || targetsJSON.count == 0) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField, @"root.targets must be a non-empty object");
        return nil;
    }

    NSMutableDictionary *targets = [NSMutableDictionary dictionary];
    for (id rawIdentifier in targetsJSON) {
        if (![rawIdentifier isKindOfClass:NSString.class] || [rawIdentifier length] == 0) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField, @"Target identifier must be a non-empty string");
            return nil;
        }
        NSDictionary *targetJSON = targetsJSON[rawIdentifier];
        if (![targetJSON isKindOfClass:NSDictionary.class]) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                    [NSString stringWithFormat:@"targets.%@ must be an object", rawIdentifier]);
            return nil;
        }
        HFAPatchTarget *target = [[HFAPatchTarget alloc] init];
        target.identifier = rawIdentifier;
        target.image = HFAPatchRequiredString(targetJSON, @"image", [@"targets." stringByAppendingString:rawIdentifier], error);
        target.uuid = HFAPatchNormalizedUUID(HFAPatchRequiredString(targetJSON, @"uuid", [@"targets." stringByAppendingString:rawIdentifier], error));
        if (!target.image || !HFAPatchIsValidNormalizedUUID(target.uuid)) {
            if (error && !*error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                               [NSString stringWithFormat:@"targets.%@.uuid must contain 16 bytes", rawIdentifier]);
            return nil;
        }
        targets[rawIdentifier] = target;
    }

    NSArray *featuresJSON = dictionary[@"features"];
    if (![featuresJSON isKindOfClass:NSArray.class] || featuresJSON.count == 0) {
        if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField, @"root.features must be a non-empty array");
        return nil;
    }

    NSMutableArray *features = [NSMutableArray array];
    NSMutableSet *featureIdentifiers = [NSMutableSet set];
    NSUInteger featureIndex = 0;
    for (id rawFeature in featuresJSON) {
        NSString *featureContext = [NSString stringWithFormat:@"features[%lu]", (unsigned long)featureIndex];
        if (![rawFeature isKindOfClass:NSDictionary.class]) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                    [featureContext stringByAppendingString:@" must be an object"]);
            return nil;
        }
        NSDictionary *featureJSON = rawFeature;
        HFAPatchFeature *feature = [[HFAPatchFeature alloc] init];
        feature.identifier = HFAPatchRequiredString(featureJSON, @"id", featureContext, error);
        feature.title = HFAPatchRequiredString(featureJSON, @"title", featureContext, error);
        feature.group = HFAPatchRequiredString(featureJSON, @"group", featureContext, error);
        if (!feature.identifier || !feature.title || !feature.group) return nil;
        if ([featureIdentifiers containsObject:feature.identifier]) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                    [NSString stringWithFormat:@"Duplicate feature id: %@", feature.identifier]);
            return nil;
        }
        [featureIdentifiers addObject:feature.identifier];
        id defaultEnabled = featureJSON[@"defaultEnabled"];
        feature.defaultEnabled = [defaultEnabled isKindOfClass:NSNumber.class] ? [defaultEnabled boolValue] : NO;

        NSArray *patchesJSON = featureJSON[@"patches"];
        if (![patchesJSON isKindOfClass:NSArray.class] || patchesJSON.count == 0) {
            if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                    [featureContext stringByAppendingString:@".patches must be a non-empty array"]);
            return nil;
        }

        NSMutableArray *patches = [NSMutableArray array];
        NSUInteger patchIndex = 0;
        for (id rawPatch in patchesJSON) {
            NSString *patchContext = [NSString stringWithFormat:@"%@.patches[%lu]", featureContext, (unsigned long)patchIndex];
            if (![rawPatch isKindOfClass:NSDictionary.class]) {
                if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                        [patchContext stringByAppendingString:@" must be an object"]);
                return nil;
            }
            NSDictionary *patchJSON = rawPatch;
            HFAPatchOperation *operation = [[HFAPatchOperation alloc] init];
            operation.targetIdentifier = HFAPatchRequiredString(patchJSON, @"target", patchContext, error);
            if (!operation.targetIdentifier) return nil;
            if (!targets[operation.targetIdentifier]) {
                if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                        [NSString stringWithFormat:@"%@ references unknown target %@",
                                                         patchContext, operation.targetIdentifier]);
                return nil;
            }
            uint64_t parsedOffset = 0;
            if (!HFAPatchParseOffset(patchJSON[@"offset"], &parsedOffset)) {
                if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                        [patchContext stringByAppendingString:@".offset must be a non-negative integer or 0x-prefixed string"]);
                return nil;
            }
            operation.offset = parsedOffset;
            NSString *original = HFAPatchRequiredString(patchJSON, @"original", patchContext, error);
            NSString *enabled = HFAPatchRequiredString(patchJSON, @"enabled", patchContext, error);
            if (!original || !enabled) return nil;
            operation.originalBytes = HFAPatchDataFromHex(original, [patchContext stringByAppendingString:@".original"], error);
            operation.enabledBytes = HFAPatchDataFromHex(enabled, [patchContext stringByAppendingString:@".enabled"], error);
            if (!operation.originalBytes || !operation.enabledBytes) return nil;
            if (operation.originalBytes.length != operation.enabledBytes.length) {
                if (error) *error = HFAPatchConfigError(HFAPatchConfigErrorField,
                                                        [patchContext stringByAppendingString:@" original/enabled byte lengths differ"]);
                return nil;
            }
            [patches addObject:operation];
            patchIndex++;
        }
        feature.patches = patches;
        [features addObject:feature];
        featureIndex++;
    }

    HFAPatchConfiguration *configuration = [[HFAPatchConfiguration alloc] init];
    configuration.schema = schema;
    configuration.name = [dictionary[@"name"] isKindOfClass:NSString.class] ? dictionary[@"name"] : @"HFAPatch";
    configuration.packageIdentity = identity;
    configuration.targets = targets;
    configuration.features = features;
    configuration.sourcePath = sourcePath ?: @"<memory>";
    HFAPatchLog(@"[CONFIG-OK] source=%@ targets=%lu features=%lu",
                configuration.sourcePath,
                (unsigned long)configuration.targets.count,
                (unsigned long)configuration.features.count);
    return configuration;
}

@end
