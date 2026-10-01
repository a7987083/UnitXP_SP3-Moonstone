#pragma once

#include <stdint.h>
#include <stddef.h>

// Static Dispatch on-disk format for M5.10+ Offset Switch/byte patches.
// One metadata entry owns exactly one physical Target+RVA site and has only two
// runtime states: relocated Original (OFF) and relocated Enabled bytes (ON).
// Static Offset typed controls, shared-site variants, arbitrary-site
// instrumentation, and RW value-cell backends are not part of this ABI.
//
// Builder V3 changes allocation, not the entry ABI: generated executable code
// lives in an owned __ZNTEXT segment and metadata/selectedTarget live in an
// owned __ZNDATA segment. The historical tail fields remain layout-compatible
// but are self-identifying only: physicalID=index+1, canonicalIndex=index.
#define ZN44_STATIC_MAGIC0 UINT64_C(0x3148435441504E5A) /* "ZNPATCH1" */
#define ZN44_STATIC_MAGIC1 UINT64_C(0x3154495543524944) /* "DIRCUIT1" marker */
#define ZN44_STATIC_VERSION_V1 1u
#define ZN44_STATIC_VERSION_V2 2u
#define ZN44_STATIC_VERSION_V3 ZN44_STATIC_VERSION_V2
#define ZN44_STATIC_VERSION ZN44_STATIC_VERSION_V1
#define ZN44_STATIC_MAX_ENTRIES 512u

#define ZN44_STATIC_HEADER_FLAG_FEATURE_METADATA_V1 UINT32_C(0x00000001)
#define ZN44_STATIC_HEADER_FLAG_RVA_PROTECTION_V1   UINT32_C(0x00000002)
#define ZN44_STATIC_HEADER_FLAG_PAYLOAD_PROTECTION_V2 UINT32_C(0x00000004)

#define ZN44_STATIC_ENTRY_FLAG_CANONICAL UINT32_C(0x00000001)

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
    uint64_t selectedTarget;
    uint64_t offRVA;
    uint64_t onRVA;
    uint64_t siteRVA;
    uint32_t windowLength;
    uint32_t patchID;
    char title[48];
    char group[24];
    uint32_t enabledLength;
    uint32_t physicalID;
    uint32_t canonicalIndex;
    uint32_t flags;
} ZN44StaticEntry;

#if defined(__cplusplus)
static_assert(sizeof(ZN44StaticHeader) == 64, "ZN44StaticHeader ABI");
static_assert(sizeof(ZN44StaticEntry) == 128, "ZN44StaticEntry ABI");
static_assert(offsetof(ZN44StaticEntry, selectedTarget) == 0, "selectedTarget must stay first");
static_assert(offsetof(ZN44StaticEntry, physicalID) == 116, "v2/v3 tail must preserve v1 ABI");
static_assert(offsetof(ZN44StaticEntry, group) == offsetof(ZN44StaticEntry, title) + 48, "title/group must remain contiguous for ZNF1 metadata");
#endif
