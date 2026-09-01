#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { Class cls; SEL sel; IMP imp; } HFAMethodHook;
static HFAMethodHook gHooks[160];
static unsigned gHookCount = 0;
static Class gClasses[24];
static unsigned gClassCount = 0;
static int gArmed = 0, gBusy = 0, gImage = -1, gConfiguredImage = -1;
static unsigned gEvent = 0;
static char gFeature[256] = {0};

static void HFAPLog(const char *fmt, ...) {
    @autoreleasepool {
        NSString *p = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
        FILE *f = fopen(p.fileSystemRepresentation, "a");
        if (!f) return;
        va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
        fflush(f); fclose(f);
    }
}

static const char *HFABase(const char *p) {
    if (!p) return "?";
    const char *q = strrchr(p, '/');
    return q ? q + 1 : p;
}

static int HFANameMatchesImage(const char *value, const char *path, unsigned index) {
    if (!value || !*value || !path) return 0;
    if (strcmp(value, "main") == 0) return index == 0;
    const char *b = HFABase(path);
    if (strcmp(value, b) == 0) return 1;
    char stem[256]; size_t n = strlen(b);
    if (n >= sizeof(stem)) n = sizeof(stem) - 1;
    memcpy(stem, b, n); stem[n] = 0;
    char *dot = strrchr(stem, '.'); if (dot) *dot = 0;
    return strcmp(value, stem) == 0;
}

void HFAPatchTraceBeginEvent(unsigned event) {
    gEvent = event; gArmed = 0; gImage = gConfiguredImage; gFeature[0] = 0;
}

void HFAPatchTraceSetFeature(const char *text) {
    if (!text || !*text || gFeature[0]) return;
    snprintf(gFeature, sizeof(gFeature), "%s", text);
}

void HFAPatchTraceConsiderString(const char *value) {
    if (!value || !*value || gImage >= 0) return;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *path = _dyld_get_image_name(i);
        if (HFANameMatchesImage(value, path, i)) { gImage = (int)i; gConfiguredImage = (int)i; return; }
    }
}

void HFAPatchTraceSetTarget(const char *value) {
    if (!value || !*value) return;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        if (HFANameMatchesImage(value, _dyld_get_image_name(i), i)) {
            gImage = (int)i; gConfiguredImage = (int)i; return;
        }
    }
}

void HFAPatchTraceArm(unsigned event) {
    if (event == gEvent) {
        gArmed = 1;
        HFAPLog("[PATCH-ARM] event=%u feature=%s module=%s\n", event,
                gFeature[0] ? gFeature : "?",
                gImage >= 0 ? HFABase(_dyld_get_image_name((uint32_t)gImage)) : "?");
    }
}

static IMP HFAOriginal(Class cls, SEL sel) {
    for (unsigned i = 0; i < gHookCount; i++)
        if (gHooks[i].cls == cls && gHooks[i].sel == sel) return gHooks[i].imp;
    return NULL;
}

typedef struct { const uint8_t *addr; size_t size; uint8_t *copy; } HFARegion;
static unsigned HFACaptureText(int image, HFARegion *out, unsigned cap) {
    if (image < 0) return 0;
    const struct mach_header_64 *h = (const struct mach_header_64 *)_dyld_get_image_header((uint32_t)image);
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)image);
    if (!h || h->magic != MH_MAGIC_64) return 0;
    const uint8_t *p = (const uint8_t *)(h + 1); unsigned count = 0;
    for (uint32_t i = 0; i < h->ncmds && count < cap; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sg = (const struct segment_command_64 *)p;
            const struct section_64 *sc = (const struct section_64 *)(sg + 1);
            for (uint32_t j = 0; j < sg->nsects && count < cap; j++) {
                if (strcmp(sc[j].sectname, "__text") != 0 || sc[j].size == 0) continue;
                size_t size = (size_t)sc[j].size;
                uint8_t *copy = malloc(size);
                if (!copy) continue;
                const uint8_t *addr = (const uint8_t *)((uintptr_t)slide + sc[j].addr);
                memcpy(copy, addr, size);
                out[count++] = (HFARegion){addr, size, copy};
            }
        }
        if (!lc->cmdsize) break;
        p += lc->cmdsize;
    }
    return count;
}

static void HFAHex(FILE *f, const uint8_t *p, size_t n) {
    for (size_t i = 0; i < n; i++) fprintf(f, "%02X", p[i]);
}

static unsigned HFADiffAndLog(HFARegion *r, unsigned n, SEL sel) {
    unsigned runs = 0;
    NSString *lp = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
    FILE *f = fopen(lp.fileSystemRepresentation, "a"); if (!f) return 0;
    uintptr_t base = gImage >= 0 ? (uintptr_t)_dyld_get_image_header((uint32_t)gImage) : 0;
    for (unsigned k = 0; k < n && runs < 128; k++) {
        size_t i = 0;
        while (i < r[k].size && runs < 128) {
            if (r[k].copy[i] == r[k].addr[i]) { i++; continue; }
            size_t start = i;
            while (i < r[k].size && r[k].copy[i] != r[k].addr[i] && i - start < 128) i++;
            size_t len = i - start;
            fprintf(f, "[PATCH] event=%u feature=%s selector=%s module=%s offset=%llX address=%p len=%llu before=",
                    gEvent, gFeature[0] ? gFeature : "?", sel_getName(sel),
                    gImage >= 0 ? HFABase(_dyld_get_image_name((uint32_t)gImage)) : "?",
                    (unsigned long long)((uintptr_t)(r[k].addr + start) - base), r[k].addr + start,
                    (unsigned long long)len);
            HFAHex(f, r[k].copy + start, len); fprintf(f, " after=");
            HFAHex(f, r[k].addr + start, len); fprintf(f, "\n"); runs++;
        }
    }
    fclose(f); return runs;
}

static void HFAPatchMethodHook(id self, SEL _cmd) {
    Class cls = object_getClass(self); IMP orig = HFAOriginal(cls, _cmd);
    if (!orig) return;
    if (!gArmed || gBusy || gImage < 0) { ((void(*)(id,SEL))orig)(self,_cmd); return; }
    gBusy = 1;
    HFARegion regions[8] = {0}; unsigned n = HFACaptureText(gImage, regions, 8);
    ((void(*)(id,SEL))orig)(self,_cmd);
    unsigned changes = HFADiffAndLog(regions, n, _cmd);
    for (unsigned i = 0; i < n; i++) free(regions[i].copy);
    HFAPLog("[PATCH-CALL] event=%u class=%s selector=%s changes=%u\n",
            gEvent, class_getName(cls), sel_getName(_cmd), changes);
    if (changes) gArmed = 0;
    gBusy = 0;
}

static void HFAPatchMethodHook1(id self, SEL _cmd, uintptr_t arg) {
    Class cls = object_getClass(self); IMP orig = HFAOriginal(cls, _cmd);
    if (!orig) return;
    if (!gArmed || gBusy || gImage < 0) { ((void(*)(id,SEL,uintptr_t))orig)(self,_cmd,arg); return; }
    gBusy = 1;
    HFARegion regions[8] = {0}; unsigned n = HFACaptureText(gImage, regions, 8);
    ((void(*)(id,SEL,uintptr_t))orig)(self,_cmd,arg);
    unsigned changes = HFADiffAndLog(regions, n, _cmd);
    for (unsigned i = 0; i < n; i++) free(regions[i].copy);
    HFAPLog("[PATCH-CALL] event=%u class=%s selector=%s arg=0x%llX changes=%u\n",
            gEvent, class_getName(cls), sel_getName(_cmd), (unsigned long long)arg, changes);
    if (changes) gArmed = 0;
    gBusy = 0;
}

void HFARegisterPatchObject(id obj, const char *actualClass) {
    if (!obj) return; Class cls = object_getClass(obj); if (!cls) return;
    for (unsigned i = 0; i < gClassCount; i++) if (gClasses[i] == cls) return;
    if (gClassCount >= 24) return; gClasses[gClassCount++] = cls;
    unsigned count = 0; Method *methods = class_copyMethodList(cls, &count);
    unsigned installed = 0;
    for (unsigned i = 0; i < count && gHookCount < 160; i++) {
        Method m = methods[i]; SEL s = method_getName(m); const char *name = sel_getName(s);
        char ret[8] = {0}; method_getReturnType(m, ret, sizeof(ret));
        unsigned argc = method_getNumberOfArguments(m);
        if ((argc != 2 && argc != 3) || ret[0] != 'v') continue;
        if (!name || strcmp(name,"dealloc") == 0 || strcmp(name,".cxx_destruct") == 0) continue;
        if (argc == 3) {
            char arg[16] = {0}; method_getArgumentType(m, 2, arg, sizeof(arg));
            if (!strchr("BcCiIqQ@#:^*", arg[0])) continue;
        }
        IMP old = method_setImplementation(m, argc == 2 ? (IMP)HFAPatchMethodHook : (IMP)HFAPatchMethodHook1);
        gHooks[gHookCount++] = (HFAMethodHook){cls,s,old}; installed++;
    }
    free(methods);
    HFAPLog("[PATCH-OBJECT] class=%s object=%p hooks=%u\n",
            actualClass ? actualClass : class_getName(cls), obj, installed);
}

__attribute__((constructor)) static void HFAPatchTraceInit(void) {
    HFAPLog("[HFALearn v1.4.6.1 PatchExecutionTrace] loaded\n");
}
