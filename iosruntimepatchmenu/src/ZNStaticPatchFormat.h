#pragma once

#include <stdint.h>
#include <stddef.h>

// Static Dispatch on-disk format. Generated thunks/variants live in an
// executable file-backed gap while metadata lives in a writable file-backed
// gap. Runtime only switches selectedTarget in RW memory; it never writes the
// executable page on stock iOS.
#define ZN44_STATIC_MAGIC0 UINT64_C(0x3148435441504E5A) /* "ZNPATCH1" */
#define ZN44_STATIC_MAGIC1 UINT64_C(0x3154495543524944) /* "DIRCUIT1" marker */
#define ZN44_STATIC_VERSION_V1 1u
#define ZN44_STATIC_VERSION_V2 2u
// Keep the legacy default on v1. ZNStaticBinaryBuilder.mm still uses this
// alias for ordinary, non-shared projects. Shared-Site Builder V2 writes
// ZN44_STATIC_VERSION_V2 explicitly.
#define ZN44_STATIC_VERSION ZN44_STATIC_VERSION_V1
#define ZN44_STATIC_MAX_ENTRIES 512u

// V2 keeps the v1 entry ABI/size (128 bytes). The former 12-byte reserved tail
// is now shared-site metadata so old generated binaries remain readable.
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
    // Runtime absolute pointer. File value is zero. In v2 only the canonical
    // entry for one physical site owns this pointer; all logical variants route
    // through that canonical selectedTarget.
    uint64_t selectedTarget;
    uint64_t offRVA;
    uint64_t onRVA;
    uint64_t siteRVA;
    uint32_t windowLength;
    uint32_t patchID;
    char title[48];
    char group[24];
    uint32_t enabledLength;

    // v2 metadata. v1 binaries contain zeros here and are treated as one
    // physical site per entry.
    uint32_t physicalID;      // 1-based physical-site id inside this header
    uint32_t canonicalIndex;  // 0-based entry index that owns selectedTarget
    uint32_t flags;           // ZN44_STATIC_ENTRY_FLAG_*
} ZN44StaticEntry;

#if defined(__cplusplus)
static_assert(sizeof(ZN44StaticHeader) == 64, "ZN44StaticHeader ABI");
static_assert(sizeof(ZN44StaticEntry) == 128, "ZN44StaticEntry ABI");
static_assert(offsetof(ZN44StaticEntry, selectedTarget) == 0, "selectedTarget must stay first");
static_assert(offsetof(ZN44StaticEntry, physicalID) == 116, "v2 tail must preserve v1 ABI");
#endif
