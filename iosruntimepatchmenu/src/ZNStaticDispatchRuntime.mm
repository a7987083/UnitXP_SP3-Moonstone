#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNStaticRVAProtection.h"
#import "ZNPatchCore.h"
#import "ZNActivationTrace.h"
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
@property(nonatomic,assign) uint64_t offRVA;
@property(nonatomic,assign) uint64_t onRVA;
@property(nonatomic,assign) BOOL payloadProtectionV2;
@end
@implementation ZNStaticPatchRecord
@end

@interface ZNStaticDispatchRuntime ()
@property(nonatomic,copy,readwrite) NSArray<ZNStaticPatchRecord *> *records;
@property(nonatomic,assign) double lastRefreshMilliseconds;
@property(nonatomic,copy) NSString *lastDiscoverySummary;
@property(nonatomic,assign) BOOL refreshScheduled;
@property(nonatomic,assign) NSUInteger refreshRequestCount;
@property(nonatomic,assign) NSUInteger refreshExecutionCount;
@property(nonatomic,assign) NSUInteger refreshCoalescedCount;
@end

static NSString *ZN44StringFromFixed(const char *bytes, size_t cap, NSString *fallback) {
    if (!bytes || cap == 0) return fallback ?: @"";
    size_t n = strnlen(bytes, cap);
    if (!n) return fallback ?: @"";
    NSString *s = [[NSString alloc] initWithBytes:bytes length:n encoding:NSUTF8StringEncoding];
    return s.length ? s : (fallback ?: @"");
}

static BOOL ZN44HeaderValid(const ZN44StaticHeader *header,
                            uintptr_t headerAddress,
                            uintptr_t segmentEnd) {
    if (!header) return NO;
    if (header->magic0 != ZN44_STATIC_MAGIC0 || header->magic1 != ZN44_STATIC_MAGIC1) return NO;
    if ((header->version != ZN44_STATIC_VERSION_V1 && header->version != ZN44_STATIC_VERSION_V2) ||
        header->entrySize != sizeof(ZN44StaticEntry)) return NO;
    if (header->count == 0 || header->count > ZN44_STATIC_MAX_ENTRIES) return NO;
    uint64_t bytes = sizeof(ZN44StaticHeader) + (uint64_t)header->count * sizeof(ZN44StaticEntry);
    return (uint64_t)headerAddress + bytes <= (uint64_t)segmentEnd;
}

@implementation ZNStaticDispatchRuntime

+ (instancetype)sharedRuntime {
    static ZNStaticDispatchRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime = [ZNStaticDispatchRuntime new];
        runtime.records = @[];
        [[NSNotificationCenter defaultCenter] addObserver:runtime
                                                 selector:@selector(zn44_imageAdded:)
                                                     name:@"ZNModuleManagerImageAdded"
                                                   object:nil];
    });
    return runtime;
}

- (void)zn44_scheduleRefreshAfter:(NSTimeInterval)delay reason:(NSString *)reason {
    void (^scheduleBlock)(void) = ^{
        self.refreshRequestCount += 1;
        if (self.refreshScheduled) {
            self.refreshCoalescedCount += 1;
            return;
        }
        self.refreshScheduled = YES;
        NSUInteger requestID = self.refreshRequestCount;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.0, delay) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self.refreshScheduled = NO;
            self.refreshExecutionCount += 1;
            ZNActivationTraceLog([NSString stringWithFormat:@"[static-dispatch-m510] refresh=%lu request=%lu reason=%@",
                                  (unsigned long)self.refreshExecutionCount,
                                  (unsigned long)requestID,
                                  reason ?: @"unknown"]);
            [self refresh];
        });
    };
    if (NSThread.isMainThread) scheduleBlock();
    else dispatch_async(dispatch_get_main_queue(), scheduleBlock);
}

- (void)zn44_imageAdded:(NSNotification *)note {
    (void)note;
    [self zn44_scheduleRefreshAfter:0.20 reason:@"image-added"];
}

- (BOOL)zn44_consumeOwnedHeader:(const ZN44StaticHeader *)header
                         address:(uintptr_t)headerAddress
                       regionEnd:(uintptr_t)regionEnd
                   runtimeHeader:(uintptr_t)runtimeHeader
                      targetName:(NSString *)targetName
                           found:(NSMutableArray<ZNStaticPatchRecord *> *)found {
    if (!ZN44HeaderValid(header, headerAddress, regionEnd)) return NO;
    ZN44StaticEntry *entries = (ZN44StaticEntry *)(headerAddress + sizeof(ZN44StaticHeader));
    if (!ZN55ValidateProtectedHeader(header, entries)) {
        ZNActivationTraceLog([NSString stringWithFormat:@"[static-dispatch-m510] integrity FAIL target=%@", targetName]);
        return NO;
    }

    for (uint32_t index = 0; index < header->count; index++) {
        ZN44StaticEntry *entry = &entries[index];
        ZN55DecodedRVAs rvas = {};
        if (!ZN55DecodeEntryRVAs(header, entry, index, &rvas)) continue;
        if (!rvas.offRVA || !rvas.onRVA || !rvas.siteRVA) continue;

        uintptr_t offTarget = runtimeHeader + (uintptr_t)rvas.offRVA;
        uintptr_t onTarget = runtimeHeader + (uintptr_t)rvas.onRVA;
        uintptr_t current = __atomic_load_n((uintptr_t *)&entry->selectedTarget, __ATOMIC_ACQUIRE);
        if (current != offTarget && current != onTarget) {
            __atomic_store_n((uintptr_t *)&entry->selectedTarget, offTarget, __ATOMIC_RELEASE);
            current = offTarget;
        }

        ZNStaticPatchRecord *record = [ZNStaticPatchRecord new];
        record.target = targetName ?: @"unknown";
        record.title = ZN44StringFromFixed(entry->title, sizeof(entry->title), [NSString stringWithFormat:@"Patch #%u", entry->patchID]);
        record.group = ZN44StringFromFixed(entry->group, sizeof(entry->group), @"Imported");
        record.siteRVA = rvas.siteRVA;
        record.patchID = entry->patchID;
        record.imageBase = runtimeHeader;
        record.entry = entry;
        record.offRVA = rvas.offRVA;
        record.onRVA = rvas.onRVA;
        record.payloadProtectionV2 = (header->flags & ZN44_STATIC_HEADER_FLAG_PAYLOAD_PROTECTION_V2) != 0;
        record.enabled = (current == onTarget);
        [found addObject:record];
    }
    return YES;
}

- (void)refresh {
    double started = ZNActivationTraceNow();
    NSMutableArray<ZNStaticPatchRecord *> *found = [NSMutableArray array];
    NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    uint32_t imageCount = _dyld_image_count();
    NSUInteger bundleImages = 0;
    NSUInteger ownedSections = 0;
    NSUInteger acceptedSections = 0;

    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const char *rawPath = _dyld_get_image_name(imageIndex);
        if (!rawPath) continue;
        NSString *path = [[NSString stringWithUTF8String:rawPath] stringByStandardizingPath];
        if (!path.length || ![path hasPrefix:bundleRoot]) continue;
        bundleImages++;

        const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(imageIndex);
        if (!mh || mh->magic != MH_MAGIC_64) continue;
        uintptr_t runtimeHeader = (uintptr_t)mh;
        const uint8_t *lcBase = (const uint8_t *)(mh + 1);
        const uint8_t *lcEnd = lcBase + mh->sizeofcmds;
        const struct load_command *lc = (const struct load_command *)lcBase;
        uint64_t imageVMBase = UINT64_MAX;

        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if ((const uint8_t *)lc + sizeof(*lc) > lcEnd ||
                lc->cmdsize < sizeof(*lc) ||
                (const uint8_t *)lc + lc->cmdsize > lcEnd) break;
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
            if ((const uint8_t *)lc + sizeof(*lc) > lcEnd ||
                lc->cmdsize < sizeof(*lc) ||
                (const uint8_t *)lc + lc->cmdsize > lcEnd) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
                if (strncmp(seg->segname, "__ZNDATA", 16) == 0 &&
                    lc->cmdsize >= sizeof(struct segment_command_64) + sectionBytes) {
                    const struct section_64 *sections = (const struct section_64 *)(seg + 1);
                    for (uint32_t j = 0; j < seg->nsects; j++) {
                        const struct section_64 *sec = &sections[j];
                        if (strncmp(sec->sectname, "__zndata", 16) != 0) continue;
                        ownedSections++;
                        if (sec->addr < imageVMBase || sec->size < sizeof(ZN44StaticHeader)) break;
                        uintptr_t start = runtimeHeader + (uintptr_t)(sec->addr - imageVMBase);
                        uintptr_t end = start + (uintptr_t)sec->size;
                        if ([self zn44_consumeOwnedHeader:(const ZN44StaticHeader *)start
                                                 address:start
                                               regionEnd:end
                                           runtimeHeader:runtimeHeader
                                              targetName:targetName
                                                   found:found]) {
                            acceptedSections++;
                        }
                        break;
                    }
                }
            }
            lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
        }
    }

    self.records = found;
    self.lastRefreshMilliseconds = (ZNActivationTraceNow() - started) * 1000.0;
    self.lastDiscoverySummary = [NSString stringWithFormat:@"owned-only bundle=%lu sections=%lu accepted=%lu records=%lu requests=%lu executions=%lu coalesced=%lu",
                                 (unsigned long)bundleImages,
                                 (unsigned long)ownedSections,
                                 (unsigned long)acceptedSections,
                                 (unsigned long)found.count,
                                 (unsigned long)self.refreshRequestCount,
                                 (unsigned long)self.refreshExecutionCount,
                                 (unsigned long)self.refreshCoalescedCount];
    ZNActivationTraceLog([NSString stringWithFormat:@"[static-dispatch-m510] refresh end %.1fms · %@",
                          self.lastRefreshMilliseconds,
                          self.lastDiscoverySummary]);
}

- (BOOL)setEnabled:(BOOL)enabled forRecord:(ZNStaticPatchRecord *)record error:(NSString **)error {
    if (!record || !record.entry || !record.imageBase || !record.offRVA || !record.onRVA) {
        if (error) *error = @"Static Dispatch 记录无效";
        return NO;
    }

    uintptr_t previous = __atomic_load_n((uintptr_t *)&record.entry->selectedTarget, __ATOMIC_ACQUIRE);
    uintptr_t target = record.imageBase + (uintptr_t)(enabled ? record.onRVA : record.offRVA);
    __atomic_store_n((uintptr_t *)&record.entry->selectedTarget, target, __ATOMIC_RELEASE);
    uintptr_t readback = __atomic_load_n((uintptr_t *)&record.entry->selectedTarget, __ATOMIC_ACQUIRE);
    if (readback != target) {
        __atomic_store_n((uintptr_t *)&record.entry->selectedTarget, previous, __ATOMIC_RELEASE);
        if (error) *error = @"RW selectedTarget read-back 不一致";
        return NO;
    }

    record.enabled = enabled;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[static-dispatch-m510] %@ %@+0x%llX patch=%u",
                                          enabled ? @"ON" : @"OFF",
                                          record.target,
                                          record.siteRVA,
                                          record.patchID]];
    return YES;
}

- (NSArray<NSString *> *)diagnosticLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSUInteger payloadV2 = 0;
    for (ZNStaticPatchRecord *record in self.records) if (record.payloadProtectionV2) payloadV2++;
    [lines addObject:[NSString stringWithFormat:@"Static Dispatch：%lu Site · Switch/byte patch only · Payload V2 %lu/%lu",
                      (unsigned long)self.records.count,
                      (unsigned long)payloadV2,
                      (unsigned long)self.records.count]];
    [lines addObject:[NSString stringWithFormat:@"最近扫描：%.1fms · %@",
                      self.lastRefreshMilliseconds,
                      self.lastDiscoverySummary.length ? self.lastDiscoverySummary : @"尚未执行"]];
    for (ZNStaticPatchRecord *record in self.records) {
        [lines addObject:[NSString stringWithFormat:@"%@ · %@+0x%llX · %@",
                          record.title,
                          record.target,
                          record.siteRVA,
                          record.enabled ? @"ON" : @"OFF"]];
        if (lines.count >= 12) break;
    }
    return lines;
}

@end

extern "C" void ZNPrepareStaticDispatchRuntimeDeferred(void) {
    @autoreleasepool {
        ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
        ZNActivationTraceLog(@"[static-dispatch-m510] prepare complete; owned-section-only refresh +350ms");
        [runtime zn44_scheduleRefreshAfter:0.35 reason:@"first-activation"];
    }
}
