#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// HFAMap v1.4.6 PatchObject Discovery
// Read-only logger: hooks -setActive: on runtime classes and dumps likely Patch Object fields.

#define HFA_MAX_HOOKS 768

typedef void (*HFASetActiveFn)(id, SEL, BOOL);

typedef struct {
    Class cls;
    IMP original;
    char name[128];
} HFAHookEntry;

static HFAHookEntry gHFAHooks[HFA_MAX_HOOKS];
static unsigned gHFAHookCount = 0;
static BOOL gHFAInstalled = NO;
static unsigned gHFAMapNo = 0;
static unsigned gHFAUIEvent = 0;
static char gHFALastTitle[256];
static char gHFALastDesc[512];
static id gHFALastSender = nil;
static SEL gHFALastAction = NULL;
static IMP gHFAOrigUIControlSend = NULL;

static const char *HFA_CSTR(id obj) {
    if (!obj) return NULL;
    if ([obj respondsToSelector:@selector(UTF8String)]) return [(id)obj UTF8String];
    if ([obj respondsToSelector:@selector(description)]) return [[obj description] UTF8String];
    return NULL;
}

static void HFALog(const char *fmt, ...) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
        FILE *f = fopen(path.fileSystemRepresentation, "a");
        if (!f) return;
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fflush(f);
        fclose(f);
    }
}

static const char *HFABaseName(const char *path) {
    if (!path) return "?";
    const char *p = strrchr(path, '/');
    return p ? p + 1 : path;
}

static void HFAImageForAddress(uintptr_t addr, uintptr_t *baseOut, const char **nameOut) {
    uintptr_t best = 0;
    const char *bestName = NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t base = (uintptr_t)_dyld_get_image_header(i);
        if (base <= addr && base > best) {
            best = base;
            bestName = _dyld_get_image_name(i);
        }
    }
    if (baseOut) *baseOut = best;
    if (nameOut) *nameOut = bestName;
}

static BOOL HFAStarts(const char *s, const char *p) {
    if (!s || !p) return NO;
    while (*p) { if (*s++ != *p++) return NO; }
    return YES;
}

static BOOL HFASystemClassName(const char *n) {
    if (!n || !*n) return YES;
    return HFAStarts(n, "UI") || HFAStarts(n, "_UI") || HFAStarts(n, "NS") ||
           HFAStarts(n, "__NS") || HFAStarts(n, "CA") || HFAStarts(n, "CG") ||
           HFAStarts(n, "OS_") || HFAStarts(n, "HFAMap") || HFAStarts(n, "Swift");
}

static id HFACall0(id obj, const char *selName) {
    if (!obj || !selName) return nil;
    SEL sel = sel_registerName(selName);
    if (![obj respondsToSelector:sel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [obj performSelector:sel];
#pragma clang diagnostic pop
}

static void HFACopyTextFromObject(id obj, char *dst, size_t cap) {
    if (!obj || !dst || !cap) return;
    const char *s = NULL;
    if ([obj respondsToSelector:@selector(text)]) s = HFA_CSTR([obj performSelector:@selector(text)]);
    if ((!s || !*s) && [obj respondsToSelector:@selector(currentTitle)]) s = HFA_CSTR([obj performSelector:@selector(currentTitle)]);
    if ((!s || !*s) && [obj respondsToSelector:@selector(accessibilityLabel)]) s = HFA_CSTR([obj performSelector:@selector(accessibilityLabel)]);
    if (s && *s) {
        strncpy(dst, s, cap - 1);
        dst[cap - 1] = 0;
    }
}

static void HFAWalkText(id root, int depth) {
    if (!root || depth > 3) return;
    char buf[512] = {0};
    HFACopyTextFromObject(root, buf, sizeof(buf));
    if (buf[0]) {
        if (!gHFALastTitle[0]) strncpy(gHFALastTitle, buf, sizeof(gHFALastTitle) - 1);
        else if (!gHFALastDesc[0] && strcmp(gHFALastTitle, buf) != 0) strncpy(gHFALastDesc, buf, sizeof(gHFALastDesc) - 1);
    }
    if ([root respondsToSelector:@selector(subviews)]) {
        NSArray *subviews = [root performSelector:@selector(subviews)];
        NSUInteger count = MIN((NSUInteger)24, subviews.count);
        for (NSUInteger i = 0; i < count; i++) HFAWalkText(subviews[i], depth + 1);
    }
    if (depth < 2 && [root respondsToSelector:@selector(superview)]) HFAWalkText([root performSelector:@selector(superview)], depth + 1);
}

static void HFARecordUIEvent(id sender, SEL action) {
    if (!sender) return;
    gHFAUIEvent++;
    gHFALastSender = sender;
    gHFALastAction = action;
    gHFALastTitle[0] = 0;
    gHFALastDesc[0] = 0;
    HFAWalkText(sender, 0);
    const char *sn = object_getClassName(sender) ?: "?";
    HFALog("\n[PD-UI] event=%u sender=%p class=%s action=%s title=\"%s\" desc=\"%s\"\n",
           gHFAUIEvent, sender, sn, action ? sel_getName(action) : "?", gHFALastTitle, gHFALastDesc);
}

static void HFA_UIControl_sendAction(id self, SEL _cmd, SEL action, id target, id event) {
    const char *sn = object_getClassName(self) ?: "?";
    if (!HFAStarts(sn, "HFAMap")) HFARecordUIEvent(self, action);
    if (gHFAOrigUIControlSend) ((void(*)(id,SEL,SEL,id,id))gHFAOrigUIControlSend)(self, _cmd, action, target, event);
}

static BOOL HFAStringLike(id obj, char *out, size_t cap) {
    if (!obj || !out || !cap) return NO;
    const char *s = HFA_CSTR(obj);
    if (!s || !*s) return NO;
    strncpy(out, s, cap - 1);
    out[cap - 1] = 0;
    return YES;
}

static void HFADumpSecretBlob(id wrapper, const char *label) {
    if (!wrapper) { HFALog("  [%s] (nil)\n", label); return; }
    const char *cn = object_getClassName(wrapper) ?: "?";
    HFALog("  [%s] class=%s self=%p desc=%s\n", label, cn, wrapper, [[[wrapper description] copy] UTF8String]);
    id secretObj = HFACall0(wrapper, "secret");
    if (!secretObj) return;
    const uint8_t *p = (const uint8_t *)secretObj;
    uint32_t len = 0, flags = 0;
    memcpy(&len, p, 4);
    memcpy(&flags, p + 4, 4);
    uint32_t keyId = (flags >> 24) & 0xff;
    uint32_t encrypted = flags & 1;
    uint32_t bit4 = (flags >> 4) & 1;
    uint32_t blobSize = (len & ~0xFU) + 0x28U;
    if (blobSize <= 0x28U) blobSize = 0x28U;
    if (blobSize > 0x120) blobSize = 0x120;
    HFALog("  [%s.secret] ptr=%p len=%u flags=0x%08X keyId=%u encrypted=%u bit4=%u blobSize=%u\n",
           label, secretObj, len, flags, keyId, encrypted, bit4, blobSize);
    HFALog("  [%s.raw]=", label);
    for (uint32_t i = 0; i < blobSize; i++) HFALog("%02X", p[i]);
    HFALog("\n");
}

static void HFADumpSelector(id obj, const char *label, const char *selName) {
    id value = HFACall0(obj, selName);
    if (!value) return;
    char text[512] = {0};
    if (HFAStringLike(value, text, sizeof(text))) {
        HFALog("  [%s] sel=%s value=%s\n", label, selName, text);
        return;
    }
    const char *cn = object_getClassName(value) ?: "?";
    HFALog("  [%s] sel=%s class=%s self=%p desc=%s\n", label, selName, value, [[[value description] copy] UTF8String]);
}

static void HFADumpPatchObject(id obj, BOOL active) {
    if (!obj) return;
    Class cls = object_getClass(obj);
    const char *cn = class_getName(cls) ?: "?";
    uintptr_t base = 0;
    const char *image = NULL;
    HFAImageForAddress((uintptr_t)cls, &base, &image);
    gHFAMapNo++;
    HFALog("\n===== PD-MAP #%u class=%s self=%p active=%d uiEvent=%u image=%s base=%p =====\n",
           gHFAMapNo, cn, obj, active ? 1 : 0, gHFAUIEvent, HFABaseName(image), (void *)base);
    HFALog("  [ui] sender=%p action=%s title=\"%s\" desc=\"%s\"\n",
           gHFALastSender, gHFALastAction ? sel_getName(gHFALastAction) : "?", gHFALastTitle, gHFALastDesc);

    HFADumpSelector(obj, "identifier", "identifier");
    HFADumpSelector(obj, "key", "eWvJvwodzK");
    HFADumpSelector(obj, "module", "module");
    HFADumpSelector(obj, "module", "DWQRhnhfqEhVoLQ");
    HFADumpSelector(obj, "signature", "signature");

    id offsetWrap = HFACall0(obj, "offset");
    if (offsetWrap) HFADumpSecretBlob(offsetWrap, "offset");

    id patchWrap = HFACall0(obj, "patchData");
    if (!patchWrap) patchWrap = HFACall0(obj, "iuVdEYvN");
    if (patchWrap) HFADumpSecretBlob(patchWrap, "patchData");

    unsigned int mcount = 0;
    Method *methods = class_copyMethodList(cls, &mcount);
    if (methods) {
        unsigned found = 0;
        for (unsigned int i = 0; i < mcount && found < 32; i++) {
            SEL s = method_getName(methods[i]);
            const char *sn = sel_getName(s);
            if (!sn || strchr(sn, ':')) continue;
            if (!strcmp(sn, "self") || !strcmp(sn, "class") || !strcmp(sn, "description") || !strcmp(sn, "debugDescription")) continue;
            id v = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            @try { v = [obj performSelector:s]; } @catch (__unused NSException *e) { v = nil; }
#pragma clang diagnostic pop
            if (!v) continue;
            if ([v respondsToSelector:sel_registerName("secret")]) {
                HFALog("  [secret-candidate] selector=%s class=%s self=%p\n", sn, object_getClassName(v) ?: "?", v);
                HFADumpSecretBlob(v, sn);
                found++;
            }
        }
        free(methods);
    }
    HFALog("===== PD-END #%u =====\n", gHFAMapNo);
}

static IMP HFAOriginalForClass(Class cls) {
    for (unsigned i = 0; i < gHFAHookCount; i++) {
        if (gHFAHooks[i].cls == cls) return gHFAHooks[i].original;
    }
    return NULL;
}

static void HFA_setActive(id self, SEL _cmd, BOOL active) {
    HFADumpPatchObject(self, active);
    IMP orig = HFAOriginalForClass(object_getClass(self));
    if (orig) ((HFASetActiveFn)orig)(self, _cmd, active);
}

static BOOL HFAShouldHookClass(Class cls) {
    if (!cls) return NO;
    const char *name = class_getName(cls);
    if (HFASystemClassName(name)) return NO;
    Method m = class_getInstanceMethod(cls, sel_registerName("setActive:"));
    if (!m) return NO;
    return YES;
}

static void HFAInstallPatchHooks(void) {
    if (gHFAInstalled) return;
    gHFAInstalled = YES;

    Class uic = objc_getClass("UIControl");
    Method uim = class_getInstanceMethod(uic, sel_registerName("sendAction:to:forEvent:"));
    if (uim) {
        gHFAOrigUIControlSend = method_setImplementation(uim, (IMP)HFA_UIControl_sendAction);
        HFALog("[PD-HOOK] UIControl sendAction orig=%p\n", gHFAOrigUIControlSend);
    }

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (!classes) return;
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count && gHFAHookCount < HFA_MAX_HOOKS; i++) {
        Class cls = classes[i];
        if (!HFAShouldHookClass(cls)) continue;
        Method m = class_getInstanceMethod(cls, sel_registerName("setActive:"));
        IMP old = method_getImplementation(m);
        if (!old || old == (IMP)HFA_setActive) continue;
        gHFAHooks[gHFAHookCount].cls = cls;
        gHFAHooks[gHFAHookCount].original = old;
        strncpy(gHFAHooks[gHFAHookCount].name, class_getName(cls) ?: "?", sizeof(gHFAHooks[gHFAHookCount].name) - 1);
        method_setImplementation(m, (IMP)HFA_setActive);
        HFALog("[PD-HOOK] setActive class=%s orig=%p\n", gHFAHooks[gHFAHookCount].name, old);
        gHFAHookCount++;
    }
    free(classes);
    HFALog("[PD-HOOK-END] hooked=%u\n", gHFAHookCount);
}

@interface HFAMapPatchObjectDiscoveryTicker : NSObject
@end
@implementation HFAMapPatchObjectDiscoveryTicker
- (void)tick:(NSTimer *)timer {
    (void)timer;
    HFAInstallPatchHooks();
}
@end

__attribute__((constructor))
static void HFAPatchObjectDiscoveryInit(void) {
    @autoreleasepool {
        HFALog("[HFALearn v1.4.6 PatchObjectDiscovery] loaded\n");
        dispatch_async(dispatch_get_main_queue(), ^{
            static HFAMapPatchObjectDiscoveryTicker *ticker = nil;
            ticker = [HFAMapPatchObjectDiscoveryTicker new];
            [NSTimer scheduledTimerWithTimeInterval:0.75
                                             target:ticker
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];
            HFAInstallPatchHooks();
        });
    }
}
