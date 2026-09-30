#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <string.h>
#import "ZNRuntimeActionRuntime.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNStaticPatchFormat.h"

static const void *kZNRDRDescriptionKey = &kZNRDRDescriptionKey;

@implementation ZNRuntimeMethodActionRecord (ZNRDRDescription)
- (NSString *)descriptionText {
    NSString *value = objc_getAssociatedObject(self, kZNRDRDescriptionKey);
    return [value isKindOfClass:NSString.class] ? value : @"";
}
@end

static uint64_t ZNRDRAlign8(uint64_t value) { return (value + 7ULL) & ~7ULL; }

static NSString *ZNRDRReadString(const uint8_t *table, const ZNRuntimeActionHeader *header, uint32_t offset) {
    if (!table || !header || offset < header->stringPoolOffset || offset >= header->totalSize) return nil;
    const uint8_t *start = table + offset, *end = table + header->totalSize;
    const uint8_t *nul = (const uint8_t *)memchr(start, 0, (size_t)(end - start));
    if (!nul) return nil;
    return [[NSString alloc] initWithBytes:start length:(NSUInteger)(nul - start) encoding:NSUTF8StringEncoding];
}

static NSDictionary<NSNumber *, NSString *> *ZNRDRDescriptionMap(void) {
    NSMutableDictionary<NSNumber *, NSString *> *map = [NSMutableDictionary dictionary];
    for (uint32_t imageIndex = 0; imageIndex < _dyld_image_count(); imageIndex++) {
        const struct mach_header *raw = _dyld_get_image_header(imageIndex);
        if (!raw || raw->magic != MH_MAGIC_64) continue;
        const struct mach_header_64 *mh = (const struct mach_header_64 *)raw;
        intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
        const uint8_t *cursor = (const uint8_t *)(mh + 1), *limit = cursor + mh->sizeofcmds;
        const struct section_64 *zndata = NULL;
        if (mh->ncmds > 4096 || mh->sizeofcmds > 16 * 1024 * 1024) continue;
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > limit) break;
            const struct load_command *lc = (const struct load_command *)cursor;
            if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
                if (strncmp(seg->segname, "__ZNDATA", 16) == 0) {
                    if (lc->cmdsize < sizeof(*seg) + (uint64_t)seg->nsects * sizeof(struct section_64)) break;
                    const struct section_64 *sections = (const struct section_64 *)(seg + 1);
                    for (uint32_t j = 0; j < seg->nsects; j++) if (strncmp(sections[j].sectname, "__zndata", 16) == 0) { zndata = &sections[j]; break; }
                }
            }
            if (zndata) break;
            cursor += lc->cmdsize;
        }
        if (!zndata || zndata->size < sizeof(ZN44StaticHeader)) continue;
        __int128 runtimeAddress = (__int128)zndata->addr + (__int128)slide;
        if (runtimeAddress <= 0 || runtimeAddress > UINTPTR_MAX) continue;
        const uint8_t *section = (const uint8_t *)(uintptr_t)runtimeAddress;
        const ZN44StaticHeader *sh = (const ZN44StaticHeader *)section;
        if (sh->magic0 != ZN44_STATIC_MAGIC0 || sh->magic1 != ZN44_STATIC_MAGIC1 || sh->entrySize != sizeof(ZN44StaticEntry) || sh->count > ZN44_STATIC_MAX_ENTRIES) continue;
        uint64_t staticBytes = ZNRDRAlign8(sizeof(ZN44StaticHeader) + (uint64_t)sh->count * sh->entrySize);
        if (staticBytes > zndata->size || zndata->size - staticBytes < sizeof(ZNRuntimeActionHeader)) continue;
        const uint8_t *table = section + staticBytes;
        const ZNRuntimeActionHeader *header = (const ZNRuntimeActionHeader *)table;
        if (header->magic != ZN_RUNTIME_ACTION_MAGIC || header->version != ZN_RUNTIME_ACTION_VERSION || header->entrySize != sizeof(ZNRuntimeMethodCallEntry) || header->count > ZN_RUNTIME_ACTION_MAX_ENTRIES || header->totalSize > zndata->size - staticBytes) continue;
        const ZNRuntimeMethodCallEntry *entries = (const ZNRuntimeMethodCallEntry *)(table + sizeof(*header));
        for (uint32_t i = 0; i < header->count; i++) {
            const ZNRuntimeMethodCallEntry *entry = &entries[i];
            if (!(entry->flags & ZNRuntimeActionFlagDescriptionText) || !entry->reserved[5]) continue;
            NSString *description = ZNRDRReadString(table, header, entry->reserved[5]);
            if (description.length) map[@(entry->actionID)] = description;
        }
    }
    return map;
}

@interface ZNRuntimeActionRuntime (ZNRDRDescriptionBridge)
- (void)znrdr_refresh;
@end

@implementation ZNRuntimeActionRuntime (ZNRDRDescriptionBridge)
- (void)znrdr_refresh {
    [self znrdr_refresh];
    NSDictionary<NSNumber *, NSString *> *map = ZNRDRDescriptionMap();
    for (ZNRuntimeMethodActionRecord *record in self.records ?: @[]) {
        NSString *description = map[@(record.actionID)];
        if (description.length) objc_setAssociatedObject(record, kZNRDRDescriptionKey, description, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}
@end

__attribute__((constructor)) static void ZNRDRInstall(void) {
    @autoreleasepool {
        Class cls = ZNRuntimeActionRuntime.class;
        Method original = class_getInstanceMethod(cls, @selector(refresh));
        Method replacement = class_getInstanceMethod(cls, @selector(znrdr_refresh));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
