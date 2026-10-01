#pragma once

#include <stdint.h>
#include <stddef.h>

// M5.11 Typed Value metadata is appended after the existing Static Dispatch
// block inside the builder-owned __ZNDATA/__zndata allocation. It is a separate
// ABI: Static Offset remains Switch/raw-byte-patch only.
#define ZNTV_STATIC_MAGIC0 UINT64_C(0x31564C4156544E5A) /* "ZNTVALV1" */
#define ZNTV_STATIC_MAGIC1 UINT64_C(0x3154455346464F56) /* "VOFFSET1" */
#define ZNTV_STATIC_VERSION 1u
#define ZNTV_STATIC_MAX_ENTRIES 256u

typedef enum : uint32_t {
    ZNTVStaticControlSlider = 0,
    ZNTVStaticControlNumber = 1,
} ZNTVStaticControl;

typedef struct {
    uint64_t magic0;
    uint64_t magic1;
    uint32_t version;
    uint32_t count;
    uint32_t entrySize;
    uint32_t flags;
    uint64_t reserved[4];
} ZNTVStaticHeader;

typedef struct {
    uint64_t rva;
    double minValue;
    double maxValue;
    double stepValue;
    double defaultValue;
    uint32_t control;
    char valueType[8];
    char title[64];
    uint8_t reserved[12];
} ZNTVStaticEntry;

#if defined(__cplusplus)
static_assert(sizeof(ZNTVStaticHeader) == 64, "ZNTVStaticHeader ABI");
static_assert(sizeof(ZNTVStaticEntry) == 128, "ZNTVStaticEntry ABI");
static_assert(offsetof(ZNTVStaticEntry, rva) == 0, "typed entry rva ABI");
#endif
