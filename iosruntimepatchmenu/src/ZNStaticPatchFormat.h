#pragma once

#include <stdint.h>
#include <stddef.h>

// v0.4.4 on-disk format written into a writable file-backed gap of an
// app-owned Mach-O. The target's generated thunks/variants live in an
// executable file-backed gap. Runtime only initializes/toggles selectedTarget
// in RW memory; it never modifies executable pages on stock iOS.
#define ZN44_STATIC_MAGIC0 UINT64_C(0x3148435441504E5A) /* "ZNPATCH1" */
#define ZN44_STATIC_MAGIC1 UINT64_C(0x3154495543524944) /* "DIRCUIT1" marker */
#define ZN44_STATIC_VERSION 1u
#define ZN44_STATIC_MAX_ENTRIES 512u

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
    // Runtime absolute pointer. File value is zero. The generic runtime fills
    // this with imageBase + offRVA and later atomically switches OFF/ON.
    uint64_t selectedTarget;
    uint64_t offRVA;
    uint64_t onRVA;
    uint64_t siteRVA;
    uint32_t windowLength;
    uint32_t patchID;
    char title[48];
    char group[24];
    uint32_t enabledLength;
    uint8_t reserved[12];
} ZN44StaticEntry;

#if defined(__cplusplus)
static_assert(sizeof(ZN44StaticHeader) == 64, "ZN44StaticHeader ABI");
static_assert(sizeof(ZN44StaticEntry) == 128, "ZN44StaticEntry ABI");
static_assert(offsetof(ZN44StaticEntry, selectedTarget) == 0, "selectedTarget must stay first");
#endif
