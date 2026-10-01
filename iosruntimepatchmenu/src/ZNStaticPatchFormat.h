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
#define ZN44_STATIC_VERSION ZN44_STATIC_VERSION_V1
#define ZN44_STATIC_MAX_ENTRIES 512u

#define ZN44_STATIC_HEADER_FLAG_FEATURE_METADATA_V1 UINT32_C(0x00000001)
#define ZN44_STATIC_HEADER_FLAG_RVA_PROTECTION_V1   UINT32_C(0x00000002)
#define ZN44_STATIC_HEADER_FLAG_PAYLOAD_PROTECTION_V2 UINT32_C(0x00000004)
#define ZN44_STATIC_HEADER_FLAG_VALUE_CELLS_V1      UINT32_C(0x00000008)

#define ZN44_STATIC_ENTRY_FLAG_CANONICAL UINT32_C(0x00000001)
#define ZN44_STATIC_ENTRY_FLAG_SHARED    UINT32_C(0x00000002)

// M5.6 Runtime-safe typed Static values. Value cells live in owned __ZNDATA
// segment tail and are loaded by build-time generated LDR-literal instructions.
// Runtime updates only RW cells; executable pages are never changed.
#define ZN44_STATIC_ENTRY_FLAG_VALUE_CELL_V1 UINT32_C(0x00004000)
#define ZN44_STATIC_ENTRY_VALUE_CELL_TYPE_SHIFT 15u
#define ZN44_STATIC_ENTRY_VALUE_CELL_TYPE_MASK UINT32_C(0x00038000)

static inline uint32_t ZN44StaticValueCellTypeFlags(uint32_t type) {
    return (type << ZN44_STATIC_ENTRY_VALUE_CELL_TYPE_SHIFT) & ZN44_STATIC_ENTRY_VALUE_CELL_TYPE_MASK;
}
static inline uint32_t ZN44StaticValueCellTypeFromFlags(uint32_t flags) {
    return (flags & ZN44_STATIC_ENTRY_VALUE_CELL_TYPE_MASK) >> ZN44_STATIC_ENTRY_VALUE_CELL_TYPE_SHIFT;
}

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
