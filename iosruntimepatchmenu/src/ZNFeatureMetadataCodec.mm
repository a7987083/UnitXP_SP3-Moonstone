#import "ZNFeatureMetadataCodec.h"
#import "ZNFeatureControlModel.h"
#import "ZNFeatureDescriptionStore.h"
#import "ZNPatchCore.h"
#import "ZNValueTypeModel.h"
#include <string.h>

static const uint8_t kZNFMMarker0 = 0xA5;
static const uint8_t kZNFMMarker1 = 0x5A;
static const uint8_t kZNFMVersionV1 = 1;
static const uint8_t kZNFMVersionV2 = 2;
static const NSUInteger kZNFMNameCapacity = 57;
static const NSUInteger kZNFMDescriptionPreferredCapacity = 24;

static NSString *ZNFMTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static NSString *ZNFMNormalize(NSString *value) {
    return [[ZNFMTrim(value) precomposedStringWithCanonicalMapping] lowercaseString];
}
static uint64_t ZNFMHash64(NSData *data) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    uint64_t hash = UINT64_C(1469598103934665603) ^ UINT64_C(0x5A4F4E4F50415443);
    for (NSUInteger i = 0; i < data.length; i++) { hash ^= bytes[i]; hash *= UINT64_C(1099511628211); }
    hash ^= hash >> 33; hash *= UINT64_C(0xff51afd7ed558ccd); hash ^= hash >> 33;
    return hash ?: UINT64_C(0x5A4E464541545552);
}
static uint8_t ZNFMKeyByte(uint64_t featureID, NSUInteger index) {
    uint64_t x = featureID ^ UINT64_C(0x9E3779B97F4A7C15) ^ ((uint64_t)index * UINT64_C(0xD6E8FEB86659FD93));
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27; x *= UINT64_C(0x2545F4914F6CDD1D);
    return (uint8_t)(x >> 56);
}
static NSData *ZNFMUTF8Prefix(NSString *value, NSUInteger capacity) {
    NSData *full = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    if (full.length <= capacity) return full;
    for (NSUInteger length = capacity; length > 0; length--) {
        NSData *candidate = [full subdataWithRange:NSMakeRange(0, length)];
        if ([[NSString alloc] initWithData:candidate encoding:NSUTF8StringEncoding]) return candidate;
    }
    return [NSData data];
}
static void ZNFMWritePayloadByte(uint8_t *storage, NSUInteger index, uint8_t value) {
    if (index < 34) storage[14 + index] = value;
    else storage[49 + (index - 34)] = value;
}
static uint8_t ZNFMReadPayloadByte(const uint8_t *storage, NSUInteger index) {
    return index < 34 ? storage[14 + index] : storage[49 + (index - 34)];
}
static uint64_t ZNFMFeatureID(NSString *target, NSString *displayName, BOOL explicitGroup, uint64_t siteRVA, uint32_t patchID) {
    NSString *identity = explicitGroup
        ? [NSString stringWithFormat:@"feature|%@", ZNFMNormalize(displayName)]
        : [NSString stringWithFormat:@"patch|%@|%016llx|%u|%@", ZNFMNormalize(target), siteRVA, patchID, ZNFMNormalize(displayName)];
    return ZNFMHash64([identity dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
}

BOOL ZNFeatureMetadataEncodeEntry(ZN44StaticEntry *entry, NSString *target, NSString *title, NSString *group) {
    if (!entry) return NO;
    NSString *cleanTitle = ZNFMTrim(title), *cleanGroup = ZNFMTrim(group);
    BOOL explicitGroup = cleanGroup.length && [cleanGroup caseInsensitiveCompare:@"Imported"] != NSOrderedSame;
    NSString *displayName = explicitGroup ? cleanGroup : cleanTitle;
    if (!displayName.length || [displayName hasPrefix:@"Patch #"]) displayName = [NSString stringWithFormat:@"功能 #%u", entry->patchID];

    NSString *featureLookupName = explicitGroup ? cleanGroup : cleanTitle;
    ZNFeatureControlType controlType = ZNFeatureControlTypeForFeatureName(featureLookupName);
    ZNValueType valueType = ZNFeatureValueTypeForFeatureName(featureLookupName);
    entry->flags = (entry->flags & ~(ZN_FEATURE_CONTROL_FLAG_MASK | ZN_FEATURE_VALUE_FLAG_MASK)) |
                   ZNFeatureControlFlags(controlType) |
                   ZNFeatureValueTypeFlags(valueType);

    uint64_t featureID = ZNFMFeatureID(target ?: @"", displayName, explicitGroup, entry->siteRVA, entry->patchID);
    NSString *descriptionText = ZNFeatureDescriptionForName(featureLookupName);
    NSData *descriptionData = ZNFMUTF8Prefix(descriptionText, kZNFMDescriptionPreferredCapacity);
    NSData *nameData = ZNFMUTF8Prefix(displayName, kZNFMNameCapacity - descriptionData.length);
    if (!nameData.length) { descriptionData = [NSData data]; nameData = ZNFMUTF8Prefix(displayName, kZNFMNameCapacity); }
    if (!nameData.length || descriptionData.length > 63 || nameData.length + descriptionData.length > kZNFMNameCapacity) return NO;

    uint8_t *storage = (uint8_t *)entry->title;
    memset(storage, 0, sizeof(entry->title) + sizeof(entry->group));
    storage[0] = 0; storage[1] = kZNFMMarker0; storage[2] = kZNFMMarker1;
    storage[3] = descriptionData.length ? kZNFMVersionV2 : kZNFMVersionV1;
    storage[4] = (explicitGroup ? 0x01 : 0x00) | ((uint8_t)descriptionData.length << 1);
    memcpy(storage + 5, &featureID, sizeof(featureID));
    storage[13] = (uint8_t)nameData.length; storage[48] = 0;

    const uint8_t *nameBytes = (const uint8_t *)nameData.bytes;
    for (NSUInteger i = 0; i < nameData.length; i++) ZNFMWritePayloadByte(storage, i, nameBytes[i] ^ ZNFMKeyByte(featureID, i));
    const uint8_t *descriptionBytes = (const uint8_t *)descriptionData.bytes;
    for (NSUInteger i = 0; i < descriptionData.length; i++) {
        NSUInteger p = nameData.length + i;
        ZNFMWritePayloadByte(storage, p, descriptionBytes[i] ^ ZNFMKeyByte(featureID, p));
    }
    return YES;
}

NSDictionary<NSString *, id> *ZNFeatureMetadataDecodeEntry(const ZN44StaticEntry *entry) {
    if (!entry) return nil;
    const uint8_t *storage = (const uint8_t *)entry->title;
    uint8_t version = storage[3];
    if (storage[0] != 0 || storage[48] != 0 || storage[1] != kZNFMMarker0 || storage[2] != kZNFMMarker1 ||
        (version != kZNFMVersionV1 && version != kZNFMVersionV2)) return nil;
    uint64_t featureID = 0; memcpy(&featureID, storage + 5, sizeof(featureID));
    uint8_t nameLength = storage[13];
    uint8_t descriptionLength = version >= kZNFMVersionV2 ? (storage[4] >> 1) : 0;
    if (!featureID || nameLength > kZNFMNameCapacity || descriptionLength > 63 || nameLength + descriptionLength > kZNFMNameCapacity) return nil;

    NSMutableData *nameData = [NSMutableData dataWithLength:nameLength];
    uint8_t *nameOut = (uint8_t *)nameData.mutableBytes;
    for (NSUInteger i = 0; i < nameLength; i++) nameOut[i] = ZNFMReadPayloadByte(storage, i) ^ ZNFMKeyByte(featureID, i);
    NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
    if (!name.length) return nil;

    NSString *description = @"";
    if (descriptionLength) {
        NSMutableData *data = [NSMutableData dataWithLength:descriptionLength];
        uint8_t *out = (uint8_t *)data.mutableBytes;
        for (NSUInteger i = 0; i < descriptionLength; i++) {
            NSUInteger p = nameLength + i; out[i] = ZNFMReadPayloadByte(storage, p) ^ ZNFMKeyByte(featureID, p);
        }
        NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (decoded.length) description = decoded;
    }
    BOOL explicitGroup = (storage[4] & 0x01) != 0;
    ZNFeatureControlType controlType = ZNFeatureControlTypeFromFlags(entry->flags);
    ZNValueType valueType = ZNFeatureValueTypeFromFlags(entry->flags);
    return @{
        @"featureID": @(featureID),
        @"title": name,
        @"group": explicitGroup ? name : @"Imported",
        @"explicitGroup": @(explicitGroup),
        @"description": description ?: @"",
        @"controlType": @(controlType),
        @"controlTypeName": ZNFeatureControlTypeName(controlType),
        @"valueType": @(valueType),
        @"valueTypeName": ZNValueTypeName(valueType),
        @"source": version >= kZNFMVersionV2 ? @"embedded-znf2-m512" : @"embedded-znf1-m512"
    };
}
