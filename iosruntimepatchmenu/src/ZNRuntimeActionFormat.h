#pragma once

#include <stdint.h>
#include <stddef.h>

#define ZN_RUNTIME_ACTION_MAGIC UINT64_C(0x00314E5443414E5A) /* "ZNACTN1" */
#define ZN_RUNTIME_ACTION_VERSION 1u
#define ZN_RUNTIME_ACTION_MAX_ENTRIES 128u

typedef uint32_t ZNRuntimeActionKind;
enum {
    ZNRuntimeActionKindInvalid = 0,
    ZNRuntimeActionKindIL2CPPMethodCall = 1,
};

typedef uint32_t ZNRuntimeActionFlags;
enum {
    ZNRuntimeActionFlagNone = 0,
    // M4.2 keeps the 64-byte entry ABI intact. For /1 actions, reserved[0]
    // stores an absolute string-pool offset containing the textual argument.
    // Runtime resolves the actual IL2CPP parameter type again before invoke.
    ZNRuntimeActionFlagArgument0Text = 1u << 0,
};

typedef struct {
    uint64_t magic;
    uint32_t version;
    uint32_t count;
    uint32_t entrySize;
    uint32_t totalSize;
    uint32_t stringPoolOffset;
    uint32_t stringPoolSize;
    uint32_t flags;
    uint32_t reserved32;
    uint64_t reserved[3];
} ZNRuntimeActionHeader;

typedef struct {
    uint32_t actionID;
    uint32_t kind;
    uint32_t flags;
    uint32_t argumentCount;

    uint32_t titleOffset;
    uint32_t groupOffset;
    uint32_t assemblyOffset;
    uint32_t namespaceOffset;
    uint32_t classOffset;
    uint32_t methodOffset;

    // M4.2 /1 ABI:
    // reserved[0] = argument0 text string-pool offset when
    //               ZNRuntimeActionFlagArgument0Text is set.
    uint32_t reserved[6];
} ZNRuntimeMethodCallEntry;

#if defined(__cplusplus)
static_assert(sizeof(ZNRuntimeActionHeader) == 64, "ZNRuntimeActionHeader ABI");
static_assert(sizeof(ZNRuntimeMethodCallEntry) == 64, "ZNRuntimeMethodCallEntry ABI");
static_assert(offsetof(ZNRuntimeMethodCallEntry, titleOffset) == 16, "ZNRuntimeMethodCallEntry string offsets ABI");
static_assert(offsetof(ZNRuntimeMethodCallEntry, reserved) == 40, "ZNRuntimeMethodCallEntry reserved ABI");
#endif
