#import "ZNFeatureMetadataCodec.h"
#include <string.h>

static const uint8_t kZNFMMarker0 = 0xA5;
static const uint8_t kZNFMMarker1 = 0x5A;
static const uint8_t kZNFMVersion = 1;
static const NSUInteger kZNFMNameCapacity = 57;

// title/group are contiguous in ZN44StaticEntry: 48 + 24 bytes.
// Layout inside that 72-byte region:
//   [0]      = 0 (legacy title C-string sentinel)
//   [1..2]   = marker A5 5A
//   [3]      = codec version
//   [4]      = flags (bit0 = explicit Feature group)
//   [5..12]  = stable featureID, little-endian
//   [13]     = UTF-8 display-name byte length (0..57)
//   [14..47] = encoded payload bytes 0..33
//   [48]     = 0 (legacy group C-string sentinel)
//   [49..71] = encoded payload bytes 34..56

static NSString *ZNFMTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNFMNormalize(NSString *value) {
    NSString *trimmed = ZNFMTrim(value);
    return [[trimmed precomposedStringWithCanonicalMapping] lowercaseString];
}

static uint64_t ZNFMHash64(NSData *data) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    uint64_t hash = UINT64_C(1469598103934665603) ^ UINT64_C(0x5A4F4E4F50415443);
    for (NSUInteger i = 0; i < data.length; i++) {
        hash ^= bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    // One extra avalanche step keeps short names from exposing FNV structure.
    hash ^= hash >> 33;
    hash *= UINT64_C(0xff51afd7ed558ccd);
    hash ^= hash >> 33;
    if (!hash) hash = UINT64_C(0x5A4E464541545552);
    return hash;
}

static uint8_t ZNFMKeyByte(uint64_t featureID, NSUInteger index) {
    uint64_t x = featureID ^ UINT64_C(0x9E3779B97F4A7C15) ^
                 ((uint64_t)index * UINT64_C(0xD6E8FEB86659FD93));
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    x *= UINT64_C(0x2545F4914F6CDD1D);
    return (uint8_t)(x >> 56);
}

static NSData *ZNFMUTF8Prefix(NSString *value, NSUInteger capacity) {
    NSData *full = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (full.length <= capacity) return full ?: [NSData data];

    NSUInteger length = capacity;
    while (length > 0) {
        NSData *candidate = [full subdataWithRange:NSMakeRange(0, length)];
        if ([[NSString alloc] initWithData:candidate encoding:NSUTF8StringEncoding]) return candidate;
        length--;
    }
    return [NSData data];
}

static void ZNFMWritePayloadByte(uint8_t *storage, NSUInteger index, uint8_t value) {
    if (index < 34) storage[14 + index] = value;
    else storage[49 + (index - 34)] = value;
}

static uint8_t ZNFMReadPayloadByte(const uint8_t *storage, NSUInteger index) {
    if (index < 34) return storage[14 + index];
    return storage[49 + (index - 34)];
}

static uint64_t ZNFMFeatureID(NSString *target,
                              NSString *displayName,
                              BOOL explicitGroup,
                              uint64_t siteRVA,
                              uint32_t patchID) {
    NSString *normalizedName = ZNFMNormalize(displayName);
    NSString *identity = nil;
    if (explicitGroup) {
        // Explicit Feature groups intentionally share one identity across
        // targets and across Patch ordering changes.
        identity = [NSString stringWithFormat:@"feature|%@", normalizedName];
    } else {
        // Legacy/no-group rows remain one logical Feature per Patch. Include
        // target/RVA/patchID so equal fallback labels never collapse together.
        identity = [NSString stringWithFormat:@"patch|%@|%016llx|%u|%@",
                    ZNFMNormalize(target), siteRVA, patchID, normalizedName];
    }
    NSData *data = [identity dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return ZNFMHash64(data);
}

BOOL ZNFeatureMetadataEncodeEntry(ZN44StaticEntry *entry,
                                  NSString *target,
                                  NSString *title,
                                  NSString *group) {
    if (!entry) return NO;

    NSString *cleanTitle = ZNFMTrim(title);
    NSString *cleanGroup = ZNFMTrim(group);
    BOOL explicitGroup = cleanGroup.length && [cleanGroup caseInsensitiveCompare:@"Imported"] != NSOrderedSame;

    NSString *displayName = explicitGroup ? cleanGroup : cleanTitle;
    if (!displayName.length || [displayName hasPrefix:@"Patch #"]) {
        displayName = [NSString stringWithFormat:@"功能 #%u", entry->patchID];
    }

    uint64_t featureID = ZNFMFeatureID(target ?: @"",
                                       displayName,
                                       explicitGroup,
                                       entry->siteRVA,
                                       entry->patchID);
    NSData *nameData = ZNFMUTF8Prefix(displayName, kZNFMNameCapacity);
    if (nameData.length > UINT8_MAX) return NO;

    uint8_t *storage = (uint8_t *)entry->title;
    memset(storage, 0, sizeof(entry->title) + sizeof(entry->group));
    storage[0] = 0;
    storage[1] = kZNFMMarker0;
    storage[2] = kZNFMMarker1;
    storage[3] = kZNFMVersion;
    storage[4] = explicitGroup ? 0x01 : 0x00;
    memcpy(storage + 5, &featureID, sizeof(featureID));
    storage[13] = (uint8_t)nameData.length;
    storage[48] = 0;

    const uint8_t *plain = (const uint8_t *)nameData.bytes;
    for (NSUInteger i = 0; i < nameData.length; i++) {
        ZNFMWritePayloadByte(storage, i, plain[i] ^ ZNFMKeyByte(featureID, i));
    }
    return YES;
}

NSDictionary<NSString *, id> *ZNFeatureMetadataDecodeEntry(const ZN44StaticEntry *entry) {
    if (!entry) return nil;
    const uint8_t *storage = (const uint8_t *)entry->title;
    if (storage[0] != 0 || storage[48] != 0 ||
        storage[1] != kZNFMMarker0 || storage[2] != kZNFMMarker1 ||
        storage[3] != kZNFMVersion) return nil;

    uint64_t featureID = 0;
    memcpy(&featureID, storage + 5, sizeof(featureID));
    uint8_t length = storage[13];
    if (!featureID || length > kZNFMNameCapacity) return nil;

    NSMutableData *decoded = [NSMutableData dataWithLength:length];
    uint8_t *out = (uint8_t *)decoded.mutableBytes;
    for (NSUInteger i = 0; i < length; i++) {
        out[i] = ZNFMReadPayloadByte(storage, i) ^ ZNFMKeyByte(featureID, i);
    }

    NSString *name = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    if (!name.length) return nil;
    BOOL explicitGroup = (storage[4] & 0x01) != 0;
    return @{
        @"featureID": @(featureID),
        @"title": name,
        @"group": explicitGroup ? name : @"Imported",
        @"explicitGroup": @(explicitGroup),
        @"source": @"embedded-znf1"
    };
}
