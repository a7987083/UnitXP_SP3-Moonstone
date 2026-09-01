#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*HFASecretDecryptFn)(void *, void *);
typedef struct { Class cls; SEL sel; IMP imp; } HFAHook;
typedef struct {
    id owner;
    id offsetWrapper;
    id patchWrapper;
    char module[160];
    char key[128];
} HFADescriptor;

static HFAHook gHooks[64];
static unsigned gHookCount;
static HFADescriptor gDescriptors[128];
static unsigned gDescriptorCount;
static unsigned gEvent;
static char gFeature[256];
static char gFeatureDesc[384];
static char gTarget[256];

static void HFALog(const char *fmt, ...) {
    @autoreleasepool {
        NSString *p = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
        FILE *f = fopen(p.fileSystemRepresentation, "a");
        if (!f) return;
        va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
        fflush(f); fclose(f);
    }
}

static const char *HFABase(const char *p) {
    const char *q = p ? strrchr(p, '/') : NULL;
    return q ? q + 1 : (p ? p : "?");
}

static int HFAImageIndexForName(const char *value) {
    if (!value || !*value) return -1;
    if (strcmp(value, "main") == 0) return 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *base = HFABase(_dyld_get_image_name(i));
        if (strcmp(value, base) == 0) return (int)i;
        char stem[256]; snprintf(stem, sizeof(stem), "%s", base);
        char *dot = strrchr(stem, '.'); if (dot) *dot = 0;
        if (strcmp(value, stem) == 0) return (int)i;
    }
    return -1;
}

static HFADescriptor *HFADescriptorFor(id owner, int create) {
    if (!owner) return NULL;
    for (unsigned i = 0; i < gDescriptorCount; i++)
        if (gDescriptors[i].owner == owner) return &gDescriptors[i];
    if (!create || gDescriptorCount >= 128) return NULL;
    HFADescriptor *d = &gDescriptors[gDescriptorCount++];
    memset(d, 0, sizeof(*d));
    d->owner = owner;
    return d;
}

void HFAPatchTraceBeginEvent(unsigned event) {
    gEvent = event;
    gFeature[0] = 0;
    gFeatureDesc[0] = 0;
}

void HFAPatchTraceSetFeature(const char *text) {
    if (!text || !*text) return;
    if (!gFeature[0]) snprintf(gFeature, sizeof(gFeature), "%s", text);
    else if (!gFeatureDesc[0] && strcmp(gFeature, text) != 0)
        snprintf(gFeatureDesc, sizeof(gFeatureDesc), "%s", text);
}

void HFAPatchTraceSetTarget(const char *value) {
    if (value && *value) snprintf(gTarget, sizeof(gTarget), "%s", value);
}

void HFAPatchTraceConsiderString(const char *value) { (void)value; }

void HFAPatchTraceArm(unsigned event) {
    if (event == gEvent)
        HFALog("[MAP-ARM] event=%u title=%s desc=%s target=%s\n", event,
               gFeature[0] ? gFeature : "?",
               gFeatureDesc[0] ? gFeatureDesc : "?",
               gTarget[0] ? gTarget : "?");
}

void HFARegisterPatchSecret(id owner, id wrapper, const char *kind) {
    HFADescriptor *d = HFADescriptorFor(owner, 1);
    if (!d || !wrapper || !kind) return;
    if (strstr(kind, "Int")) d->offsetWrapper = wrapper;
    else if (strstr(kind, "Data")) d->patchWrapper = wrapper;
}

void HFARegisterPatchString(id owner, const char *value) {
    HFADescriptor *d = HFADescriptorFor(owner, 1);
    if (!d || !value || !*value) return;
    if (HFAImageIndexForName(value) >= 0)
        snprintf(d->module, sizeof(d->module), "%s", value);
    else if (!d->key[0] && strchr(value, '-') && !strchr(value, ' '))
        snprintf(d->key, sizeof(d->key), "%s", value);
}

static IMP HFAOriginal(Class cls, SEL sel) {
    for (unsigned i = 0; i < gHookCount; i++)
        if (gHooks[i].cls == cls && gHooks[i].sel == sel) return gHooks[i].imp;
    return NULL;
}

static int HFADecryptWrapper(id wrapper, char *out, size_t outCap, const char *label) {
    if (!wrapper || !out || outCap < 2) return 0;
    SEL secretSel = sel_registerName("secret");
    Method getterMethod = class_getInstanceMethod(object_getClass(wrapper), secretSel);
    if (!getterMethod) return 0;
    void *secret = ((void *(*)(id,SEL))objc_msgSend)(wrapper, secretSel);
    if (!secret) return 0;

    uint32_t len = 0, flags = 0;
    memcpy(&len, secret, 4);
    memcpy(&flags, (uint8_t *)secret + 4, 4);
    size_t blobSize = (size_t)(len & ~0xFu) + 0x28u;
    if (blobSize <= 0x28u) blobSize = 0x28u;
    if (!len || len > 0x10000u || blobSize > 0x11000u) return 0;

    IMP getter = method_getImplementation(getterMethod);
    uintptr_t decryptAddress = (uintptr_t)getter + 0xD00u;
    Dl_info getterInfo = {0}, decryptInfo = {0};
    if (!dladdr((void *)getter, &getterInfo) ||
        !dladdr((void *)decryptAddress, &decryptInfo) ||
        getterInfo.dli_fbase != decryptInfo.dli_fbase) return 0;
    uintptr_t getterRVA = (uintptr_t)getter - (uintptr_t)getterInfo.dli_fbase;
    uintptr_t decryptRVA = decryptAddress - (uintptr_t)decryptInfo.dli_fbase;

    uint32_t insn0 = 0, insn30 = 0, insn40 = 0;
    memcpy(&insn0, (void *)decryptAddress, 4);
    memcpy(&insn30, (void *)(decryptAddress + 0x30), 4);
    memcpy(&insn40, (void *)(decryptAddress + 0x40), 4);
    if (insn0 != 0xD105C3FFu || insn30 != 0xB9400408u || insn40 != 0x53187D00u) {
        HFALog("[MAP-DECRYPT-SKIP] field=%s image=%s getterRVA=%llX candidateRVA=%llX fingerprint=%08X/%08X/%08X\n",
               label, HFABase(getterInfo.dli_fname),
               (unsigned long long)getterRVA, (unsigned long long)decryptRVA,
               insn0, insn30, insn40);
        return 0;
    }

    void *copy = malloc(blobSize);
    void *plain = calloc(1, (size_t)len + 0x20u);
    if (!copy || !plain) {
        free(copy); free(plain); return 0;
    }
    memcpy(copy, secret, blobSize);
    int rc = ((HFASecretDecryptFn)decryptAddress)(copy, plain);
    if (rc == 0) {
        size_t n = len < outCap - 1 ? len : outCap - 1;
        memcpy(out, plain, n);
        out[n] = 0;
    }
    HFALog("[MAP-DECRYPT] field=%s image=%s getterRVA=%llX decryptRVA=%llX len=%u flags=%08X rc=%d plain=%s\n",
           label, HFABase(getterInfo.dli_fname),
           (unsigned long long)getterRVA, (unsigned long long)decryptRVA,
           len, flags, rc, rc == 0 ? out : "?");
    free(plain); free(copy);
    return rc == 0;
}

static int HFAValidOffset(const char *s) {
    if (!s || !*s) return 0;
    const char *p = s;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
    if (!*p) return 0;
    for (; *p; p++)
        if (!strchr("0123456789abcdefABCDEF", *p)) return 0;
    return 1;
}

static int HFAValidPatch(const char *s) {
    if (!s || !*s) return 0;
    size_t n = strlen(s);
    if (n & 1) return 0;
    for (const char *p = s; *p; p++)
        if (!strchr("0123456789abcdefABCDEF", *p)) return 0;
    return 1;
}

static void HFAEmitMapping(id owner, uintptr_t active) {
    HFADescriptor *d = HFADescriptorFor(owner, 0);
    if (!d) {
        HFALog("[MAP-MISS] event=%u owner=%p reason=no-descriptor\n", gEvent, owner);
        return;
    }
    char offset[160] = {0}, patch[512] = {0};
    int haveOffset = HFADecryptWrapper(d->offsetWrapper, offset, sizeof(offset), "offset");
    int havePatch = HFADecryptWrapper(d->patchWrapper, patch, sizeof(patch), "patchData");
    int valid = haveOffset && havePatch && HFAValidOffset(offset) && HFAValidPatch(patch);
    char normalizedOffset[164] = {0};
    if (haveOffset && offset[0] == '0' && (offset[1] == 'x' || offset[1] == 'X'))
        snprintf(normalizedOffset, sizeof(normalizedOffset), "%s", offset);
    else if (haveOffset && HFAValidOffset(offset))
        snprintf(normalizedOffset, sizeof(normalizedOffset), "0x%s", offset);
    HFALog("[MAPPING] title=\"%s\" desc=\"%s\" key=%s module=%s offset=%s patch=%s active=%u valid=%d\n",
           gFeature[0] ? gFeature : "(not found)",
           gFeatureDesc[0] ? gFeatureDesc : "(not found)",
           d->key[0] ? d->key : "?",
           d->module[0] ? d->module : "?",
           normalizedOffset[0] ? normalizedOffset : "?",
           havePatch ? patch : "?",
           (unsigned)(active != 0), valid);
}

static void HFASetActiveHook(id self, SEL _cmd, uintptr_t active) {
    Class cls = object_getClass(self);
    IMP orig = HFAOriginal(cls, _cmd);
    HFAEmitMapping(self, active);
    if (orig) ((void(*)(id,SEL,uintptr_t))orig)(self, _cmd, active);
}

void HFARegisterPatchObject(id obj, const char *actualClass) {
    if (!obj) return;
    Class cls = object_getClass(obj);
    if (!cls) return;
    SEL sel = sel_registerName("setActive:");
    for (unsigned i = 0; i < gHookCount; i++)
        if (gHooks[i].cls == cls && gHooks[i].sel == sel) return;
    if (gHookCount >= 64) return;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != 3) {
        HFALog("[MAP-OBJECT] class=%s object=%p setActive=missing\n",
               actualClass ? actualClass : class_getName(cls), obj);
        return;
    }
    IMP old = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(cls, sel, (IMP)HFASetActiveHook, types))
        method_setImplementation(method, (IMP)HFASetActiveHook);
    gHooks[gHookCount++] = (HFAHook){cls, sel, old};
    HFADescriptorFor(obj, 1);
    HFALog("[MAP-OBJECT] class=%s object=%p selector=setActive: orig=%p\n",
           actualClass ? actualClass : class_getName(cls), obj, old);
}

__attribute__((constructor)) static void HFAInit(void) {
    HFALog("[HFALearn v1.4.6.4 UniversalMapping] loaded\n");
}
