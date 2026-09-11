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
@property(nonatomic,assign) ZN44StaticEntry *dispatchEntry;
@property(nonatomic,copy) NSString *siteKey;
@property(nonatomic,assign) uint32_t physicalID;
@property(nonatomic,assign) uint32_t headerVersion;
@end
@implementation ZNStaticPatchRecord
@end

@interface ZNStaticDispatchRuntime ()
@property(nonatomic,copy,readwrite) NSArray<ZNStaticPatchRecord *> *records;
// Per physical site, stores logical patchIDs in activation order. The last
// owner wins. Disabling the last owner automatically falls back to the
// previous active owner; an empty stack selects OFF/Original.
@property(nonatomic,strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *ownerOrderBySite;
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
    if ((h->version != ZN44_STATIC_VERSION_V1 && h->version != ZN44_STATIC_VERSION_V2) ||
        h->entrySize != sizeof(ZN44StaticEntry)) return NO;
    if (h->count == 0 || h->count > ZN44_STATIC_MAX_ENTRIES) return NO;
    uint64_t bytes = sizeof(ZN44StaticHeader) + (uint64_t)h->count * sizeof(ZN44StaticEntry);
    if ((uint64_t)headerAddress + bytes > (uint64_t)segmentEnd) return NO;
    return YES;
}

static uint32_t ZN44CanonicalIndex(const ZN44StaticHeader *header,
                                   const ZN44StaticEntry *entry,
                                   uint32_t entryIndex) {
    if (header && header->version >= ZN44_STATIC_VERSION_V2 && entry &&
        entry->canonicalIndex < header->count) {
        return entry->canonicalIndex;
    }
    return entryIndex;
}

static BOOL ZN44CurrentTargetValid(const ZN44StaticHeader *header,
                                   ZN44StaticEntry *entries,
                                   uint32_t canonicalIndex,
                                   uintptr_t imageBase,
                                   uintptr_t current) {
    if (!header || !entries || canonicalIndex >= header->count) return NO;
    ZN44StaticEntry *canonical = &entries[canonicalIndex];
    uintptr_t offTarget = imageBase + (uintptr_t)canonical->offRVA;
    if (current == offTarget) return YES;

    for (uint32_t i = 0; i < header->count; i++) {
        ZN44StaticEntry *candidate = &entries[i];
        if (ZN44CanonicalIndex(header, candidate, i) != canonicalIndex) continue;
        uintptr_t onTarget = imageBase + (uintptr_t)candidate->onRVA;
        if (current == onTarget) return YES;
    }
    return NO;
}

@implementation ZNStaticDispatchRuntime

+ (instancetype)sharedRuntime {
    static ZNStaticDispatchRuntime *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [ZNStaticDispatchRuntime new];
        s.records = @[];
        s.ownerOrderBySite = [NSMutableDictionary dictionary];
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
    NSMutableSet<NSString *> *liveSiteKeys = [NSMutableSet set];
    NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    uint32_t imageCount = _dyld_image_count();

    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const char *rawPath = _dyld_get_image_name(imageIndex);
        if (!rawPath) continue;
        NSString *path = [[NSString stringWithUTF8String:rawPath] stringByStandardizingPath];
        if (!path.length || ![path hasPrefix:bundleRoot]) continue;

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
                            uint32_t canonicalIndex = ZN44CanonicalIndex(header, entry, e);
                            ZN44StaticEntry *dispatchEntry = &entries[canonicalIndex];
                            NSString *siteKey = [NSString stringWithFormat:@"%p:%p:%u", (void *)runtimeHeader, (void *)cursor, canonicalIndex];
                            [liveSiteKeys addObject:siteKey];

                            uintptr_t offTarget = runtimeHeader + (uintptr_t)dispatchEntry->offRVA;
                            uintptr_t current = __atomic_load_n((uintptr_t *)&dispatchEntry->selectedTarget, __ATOMIC_ACQUIRE);
                            if (!ZN44CurrentTargetValid(header, entries, canonicalIndex, runtimeHeader, current)) {
                                __atomic_store_n((uintptr_t *)&dispatchEntry->selectedTarget, offTarget, __ATOMIC_RELEASE);
                                current = offTarget;
                            }

                            NSMutableArray<NSNumber *> *owners = self.ownerOrderBySite[siteKey];
                            if (!owners) {
                                owners = [NSMutableArray array];
                                // Normally generated binaries boot in OFF. If refresh is
                                // reached after an external pointer initialization, infer
                                // only the selected top owner; earlier owner history cannot
                                // be reconstructed from one pointer and is intentionally not guessed.
                                if (current != offTarget) {
                                    for (uint32_t j = 0; j < header->count; j++) {
                                        ZN44StaticEntry *candidate = &entries[j];
                                        if (ZN44CanonicalIndex(header, candidate, j) != canonicalIndex) continue;
                                        if (current == runtimeHeader + (uintptr_t)candidate->onRVA) {
                                            [owners addObject:@(candidate->patchID)];
                                            break;
                                        }
                                    }
                                }
                                self.ownerOrderBySite[siteKey] = owners;
                            }

                            ZNStaticPatchRecord *record = [ZNStaticPatchRecord new];
                            record.target = targetName;
                            record.title = ZN44StringFromFixed(entry->title, sizeof(entry->title), [NSString stringWithFormat:@"Patch #%u", entry->patchID]);
                            record.group = ZN44StringFromFixed(entry->group, sizeof(entry->group), @"Imported");
                            record.siteRVA = entry->siteRVA;
                            record.patchID = entry->patchID;
                            record.imageBase = runtimeHeader;
                            record.entry = entry;
                            record.dispatchEntry = dispatchEntry;
                            record.siteKey = siteKey;
                            record.physicalID = (header->version >= ZN44_STATIC_VERSION_V2 && entry->physicalID) ? entry->physicalID : (e + 1);
                            record.headerVersion = header->version;
                            record.enabled = [owners containsObject:@(entry->patchID)];
                            [found addObject:record];
                        }
                        cursor += sizeof(ZN44StaticHeader) + (uintptr_t)header->count * sizeof(ZN44StaticEntry) - 8;
                    }
                }
            }
            lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
        }
    }

    // Drop stale owner stacks only for sites that belonged to the previous
    // record set and disappeared after an image refresh.
    NSMutableSet<NSString *> *previousKeys = [NSMutableSet set];
    for (ZNStaticPatchRecord *r in self.records) if (r.siteKey.length) [previousKeys addObject:r.siteKey];
    for (NSString *key in previousKeys) if (![liveSiteKeys containsObject:key]) [self.ownerOrderBySite removeObjectForKey:key];

    self.records = found;
    if (found.count) {
        NSUInteger shared = 0;
        NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
        for (ZNStaticPatchRecord *r in found) counts[r.siteKey] = @([counts[r.siteKey] unsignedIntegerValue] + 1);
        for (NSNumber *n in counts.allValues) if (n.unsignedIntegerValue > 1) shared++;
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[static-dispatch] detected %lu logical entries · %lu physical sites · %lu shared", (unsigned long)found.count, (unsigned long)counts.count, (unsigned long)shared]];
    }
}

- (ZNStaticPatchRecord *)zn44_recordForPatchID:(uint32_t)patchID siteKey:(NSString *)siteKey {
    for (ZNStaticPatchRecord *candidate in self.records) {
        if ([candidate.siteKey isEqualToString:siteKey] && candidate.patchID == patchID) return candidate;
    }
    return nil;
}

- (BOOL)setEnabled:(BOOL)enabled forRecord:(ZNStaticPatchRecord *)record error:(NSString **)error {
    if (!record || !record.entry || !record.dispatchEntry || !record.imageBase || !record.siteKey.length) {
        if (error) *error = @"Static Dispatch 记录无效";
        return NO;
    }

    NSMutableArray<NSNumber *> *owners = self.ownerOrderBySite[record.siteKey];
    if (!owners) {
        owners = [NSMutableArray array];
        self.ownerOrderBySite[record.siteKey] = owners;
    }
    NSArray<NSNumber *> *previousOwners = [owners copy];
    uintptr_t previousTarget = __atomic_load_n((uintptr_t *)&record.dispatchEntry->selectedTarget, __ATOMIC_ACQUIRE);
    NSNumber *ownerID = @(record.patchID);

    [owners removeObject:ownerID];
    if (enabled) [owners addObject:ownerID];

    uintptr_t target = record.imageBase + (uintptr_t)record.dispatchEntry->offRVA;
    ZNStaticPatchRecord *selectedRecord = nil;
    if (owners.count) {
        uint32_t selectedID = owners.lastObject.unsignedIntValue;
        selectedRecord = [self zn44_recordForPatchID:selectedID siteKey:record.siteKey];
        if (!selectedRecord || !selectedRecord.entry->onRVA) {
            [owners setArray:previousOwners];
            if (error) *error = @"Shared Site Owner Stack 无法解析当前 Variant";
            return NO;
        }
        target = record.imageBase + (uintptr_t)selectedRecord.entry->onRVA;
    }

    __atomic_store_n((uintptr_t *)&record.dispatchEntry->selectedTarget, target, __ATOMIC_RELEASE);
    uintptr_t readback = __atomic_load_n((uintptr_t *)&record.dispatchEntry->selectedTarget, __ATOMIC_ACQUIRE);
    if (readback != target) {
        [owners setArray:previousOwners];
        __atomic_store_n((uintptr_t *)&record.dispatchEntry->selectedTarget, previousTarget, __ATOMIC_RELEASE);
        if (error) *error = @"RW selectedTarget read-back 不一致";
        return NO;
    }

    for (ZNStaticPatchRecord *candidate in self.records) {
        if ([candidate.siteKey isEqualToString:record.siteKey]) {
            candidate.enabled = [owners containsObject:@(candidate.patchID)];
        }
    }

    NSString *selected = selectedRecord ? (selectedRecord.group.length ? selectedRecord.group : selectedRecord.title) : @"Original";
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[static-dispatch-v2] %@ %@+0x%llX owner=%u owners=%lu selected=%@ physical=%u",
                                          enabled ? @"ON" : @"OFF",
                                          record.target,
                                          record.siteRVA,
                                          record.patchID,
                                          (unsigned long)owners.count,
                                          selected,
                                          record.physicalID]];
    return YES;
}

- (NSArray<NSString *> *)diagnosticLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableSet<NSString *> *sites = [NSMutableSet set];
    for (ZNStaticPatchRecord *r in self.records) if (r.siteKey.length) [sites addObject:r.siteKey];
    [lines addObject:[NSString stringWithFormat:@"Static Dispatch：%lu 逻辑项 / %lu 物理 Site", (unsigned long)self.records.count, (unsigned long)sites.count]];
    for (ZNStaticPatchRecord *r in self.records) {
        NSArray *owners = self.ownerOrderBySite[r.siteKey] ?: @[];
        [lines addObject:[NSString stringWithFormat:@"%@ · %@+0x%llX · %@ · owners=%lu", r.title, r.target, r.siteRVA, r.enabled ? @"ON" : @"OFF", (unsigned long)owners.count]];
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
