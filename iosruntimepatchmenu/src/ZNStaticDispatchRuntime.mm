#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNPatchCore.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>

@interface ZNStaticPatchRecord ()
@property(nonatomic,copy,readwrite) NSString *target;
@property(nonatomic,copy,readwrite) NSString *title;
@property(nonatomic,copy,readwrite) NSString *group;
@property(nonatomic,assign,readwrite) uint64_t siteRVA;
@property(nonatomic,assign,readwrite) uint32_t patchID;
@property(nonatomic,assign,readwrite,getter=isEnabled) BOOL enabled;
@property(nonatomic,assign) uintptr_t imageBase;
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end
@implementation ZNStaticPatchRecord
@end

@interface ZNStaticDispatchRuntime ()
@property(nonatomic,copy,readwrite) NSArray<ZNStaticPatchRecord *> *records;
@end

static NSString *ZN44StringFromFixed(const char *bytes, size_t cap, NSString *fallback) {
    if (!bytes || cap == 0) return fallback ?: @"";
    size_t n = strnlen(bytes, cap);
    if (!n) return fallback ?: @"";
    NSString *s = [[NSString alloc] initWithBytes:bytes length:n encoding:NSUTF8StringEncoding];
    return s.length ? s : (fallback ?: @"");
}

static BOOL ZN44HeaderValid(const ZN44StaticHeader *h, uintptr_t headerAddress, uintptr_t segmentEnd) {
    if (!h) return NO;
    if (h->magic0 != ZN44_STATIC_MAGIC0 || h->magic1 != ZN44_STATIC_MAGIC1) return NO;
    if (h->version != ZN44_STATIC_VERSION || h->entrySize != sizeof(ZN44StaticEntry)) return NO;
    if (h->count == 0 || h->count > ZN44_STATIC_MAX_ENTRIES) return NO;
    uint64_t bytes = sizeof(ZN44StaticHeader) + (uint64_t)h->count * sizeof(ZN44StaticEntry);
    if ((uint64_t)headerAddress + bytes > (uint64_t)segmentEnd) return NO;
    return YES;
}

@implementation ZNStaticDispatchRuntime

+ (instancetype)sharedRuntime {
    static ZNStaticDispatchRuntime *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [ZNStaticDispatchRuntime new];
        s.records = @[];
        [[NSNotificationCenter defaultCenter] addObserver:s selector:@selector(zn44_imageAdded:) name:@"ZNModuleManagerImageAdded" object:nil];
    });
    return s;
}

- (void)zn44_imageAdded:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)refresh {
    NSMutableArray<ZNStaticPatchRecord *> *found = [NSMutableArray array];
    NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    uint32_t imageCount = _dyld_image_count();

    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const char *rawPath = _dyld_get_image_name(imageIndex);
        if (!rawPath) continue;
        NSString *path = [[NSString stringWithUTF8String:rawPath] stringByStandardizingPath];
        if (!path.length || ![path hasPrefix:bundleRoot]) continue; // app-owned images only

        const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(imageIndex);
        if (!mh || mh->magic != MH_MAGIC_64) continue;
        uintptr_t runtimeHeader = (uintptr_t)mh;
        const uint8_t *lcBase = (const uint8_t *)(mh + 1);
        const uint8_t *lcEnd = lcBase + mh->sizeofcmds;
        const struct load_command *lc = (const struct load_command *)lcBase;
        uint64_t imageVMBase = UINT64_MAX;

        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if ((const uint8_t *)lc + sizeof(*lc) > lcEnd || lc->cmdsize < sizeof(*lc) || (const uint8_t *)lc + lc->cmdsize > lcEnd) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                if (strncmp(seg->segname, SEG_TEXT, 16) == 0) imageVMBase = seg->vmaddr;
            }
            lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
        }
        if (imageVMBase == UINT64_MAX) continue;

        NSString *targetName = path.lastPathComponent ?: @"unknown";
        lc = (const struct load_command *)lcBase;
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if ((const uint8_t *)lc + sizeof(*lc) > lcEnd || lc->cmdsize < sizeof(*lc) || (const uint8_t *)lc + lc->cmdsize > lcEnd) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                if ((seg->initprot & VM_PROT_WRITE) && seg->filesize >= sizeof(ZN44StaticHeader) && seg->vmaddr >= imageVMBase) {
                    uintptr_t start = runtimeHeader + (uintptr_t)(seg->vmaddr - imageVMBase);
                    uintptr_t end = start + (uintptr_t)seg->filesize;
                    uintptr_t cursor = (start + 7u) & ~(uintptr_t)7u;
                    for (; cursor + sizeof(ZN44StaticHeader) <= end; cursor += 8) {
                        const ZN44StaticHeader *header = (const ZN44StaticHeader *)cursor;
                        if (header->magic0 != ZN44_STATIC_MAGIC0) continue;
                        if (!ZN44HeaderValid(header, cursor, end)) continue;

                        ZN44StaticEntry *entries = (ZN44StaticEntry *)(cursor + sizeof(ZN44StaticHeader));
                        for (uint32_t e = 0; e < header->count; e++) {
                            ZN44StaticEntry *entry = &entries[e];
                            uintptr_t offTarget = runtimeHeader + (uintptr_t)entry->offRVA;
                            uintptr_t onTarget = runtimeHeader + (uintptr_t)entry->onRVA;
                            uintptr_t current = __atomic_load_n((uintptr_t *)&entry->selectedTarget, __ATOMIC_ACQUIRE);
                            if (current != offTarget && current != onTarget) {
                                __atomic_store_n((uintptr_t *)&entry->selectedTarget, offTarget, __ATOMIC_RELEASE);
                                current = offTarget;
                            }

                            ZNStaticPatchRecord *record = [ZNStaticPatchRecord new];
                            record.target = targetName;
                            record.title = ZN44StringFromFixed(entry->title, sizeof(entry->title), [NSString stringWithFormat:@"Patch #%u", entry->patchID]);
                            record.group = ZN44StringFromFixed(entry->group, sizeof(entry->group), @"Imported");
                            record.siteRVA = entry->siteRVA;
                            record.patchID = entry->patchID;
                            record.imageBase = runtimeHeader;
                            record.entry = entry;
                            record.enabled = (current == onTarget);
                            [found addObject:record];
                        }
                        // Builder writes one header per writable gap; skip the entry body.
                        cursor += sizeof(ZN44StaticHeader) + (uintptr_t)header->count * sizeof(ZN44StaticEntry) - 8;
                    }
                }
            }
            lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
        }
    }

    self.records = found;
    if (found.count) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[static-dispatch] detected %lu generated patch entries", (unsigned long)found.count]];
    }
}

- (BOOL)setEnabled:(BOOL)enabled forRecord:(ZNStaticPatchRecord *)record error:(NSString **)error {
    if (!record || !record.entry || !record.imageBase) {
        if (error) *error = @"Static Dispatch 记录无效";
        return NO;
    }
    uintptr_t target = record.imageBase + (uintptr_t)(enabled ? record.entry->onRVA : record.entry->offRVA);
    __atomic_store_n((uintptr_t *)&record.entry->selectedTarget, target, __ATOMIC_RELEASE);
    uintptr_t readback = __atomic_load_n((uintptr_t *)&record.entry->selectedTarget, __ATOMIC_ACQUIRE);
    if (readback != target) {
        if (error) *error = @"RW selectedTarget read-back 不一致";
        return NO;
    }
    record.enabled = enabled;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[static-dispatch] %@ %@+0x%llX", enabled ? @"ON" : @"OFF", record.target, record.siteRVA]];
    return YES;
}

- (NSArray<NSString *> *)diagnosticLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Static Dispatch：%lu 项", (unsigned long)self.records.count]];
    for (ZNStaticPatchRecord *r in self.records) {
        [lines addObject:[NSString stringWithFormat:@"%@ · %@+0x%llX · %@", r.title, r.target, r.siteRVA, r.enabled ? @"ON" : @"OFF"]];
        if (lines.count >= 12) break;
    }
    return lines;
}

@end

__attribute__((constructor(109))) static void ZN44StaticDispatchBootstrap(void) {
    @autoreleasepool {
        ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [runtime refresh];
        });
    }
}
