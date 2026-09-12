#pragma once

#include <stdint.h>
#include <stddef.h>

// Static Dispatch on-disk format. Runtime only switches selectedTarget in RW
// memory; it never writes executable pages after launch.
//
// Builder V3 changes allocation, not the entry ABI: generated executable code
// lives in an owned __ZNTEXT segment and metadata/selectedTarget live in an
// owned __ZNDATA segment. Therefore V3 intentionally reuses the V2 on-disk ABI.
#define ZN44_STATIC_MAGIC0 UINT64_C(0x3148435441504E5A) /* "ZNPATCH1" */
#define ZN44_STATIC_MAGIC1 UINT64_C(0x3154495543524944) /* "DIRCUIT1" marker */
#define ZN44_STATIC_VERSION_V1 1u
#define ZN44_STATIC_VERSION_V2 2u
#define ZN44_STATIC_VERSION_V3 ZN44_STATIC_VERSION_V2
// Keep the legacy default on v1. ZNStaticBinaryBuilder.mm still uses this
// alias. Owned-Segment Builder V3 writes ZN44_STATIC_VERSION_V3 explicitly,
// which is ABI-compatible with V2.
#define ZN44_STATIC_VERSION ZN44_STATIC_VERSION_V1
#define ZN44_STATIC_MAX_ENTRIES 512u

// Header flags are backward-compatible because older runtimes ignore them.
// When FEATURE_METADATA_V1 is set, title/group plaintext has been replaced by
// the ZNF1 opaque FeatureID + encoded display-name representation. The 128-byte
// entry ABI is unchanged.
#define ZN44_STATIC_HEADER_FLAG_FEATURE_METADATA_V1 UINT32_C(0x00000001)

// V2/V3 keep the v1 entry ABI/size (128 bytes). The former 12-byte reserved
// tail is shared-site metadata so old generated binaries remain readable.
#define ZN44_STATIC_ENTRY_FLAG_CANONICAL UINT32_C(0x00000001)
#define ZN44_STATIC_ENTRY_FLAG_SHARED    UINT32_C(0x00000002)

typedef struct {
    uint64_t magic0;
    uint64_t magic1;
    uint32_t version;
    uint32_t count;
    uint32_t entrySize;
    uint32_t flags;
    uint64_t reserved[4];
} ZN44StaticHeader;

typedef struct {
    // Runtime absolute pointer. File value is zero. In v2/v3 only the
    // canonical entry for one physical site owns this pointer; all logical
    // variants route through that canonical selectedTarget.
    uint64_t selectedTarget;
    uint64_t offRVA;
    uint64_t onRVA;
    uint64_t siteRVA;
    uint32_t windowLength;
    uint32_t patchID;
    char title[48];
    char group[24];
    uint32_t enabledLength;

    // v2/v3 metadata. v1 binaries contain zeros here and are treated as one
    // physical site per entry.
    uint32_t physicalID;      // 1-based physical-site id inside this header
    uint32_t canonicalIndex;  // 0-based entry index that owns selectedTarget
    uint32_t flags;           // ZN44_STATIC_ENTRY_FLAG_*
} ZN44StaticEntry;

#if defined(__cplusplus)
static_assert(sizeof(ZN44StaticHeader) == 64, "ZN44StaticHeader ABI");
static_assert(sizeof(ZN44StaticEntry) == 128, "ZN44StaticEntry ABI");
static_assert(offsetof(ZN44StaticEntry, selectedTarget) == 0, "selectedTarget must stay first");
static_assert(offsetof(ZN44StaticEntry, physicalID) == 116, "v2/v3 tail must preserve v1 ABI");
static_assert(offsetof(ZN44StaticEntry, group) == offsetof(ZN44StaticEntry, title) + 48, "title/group must remain contiguous for ZNF1 metadata");
#endif
