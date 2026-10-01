#import "ZNTypedValueBinaryPersistence.h"
#import "ZNTypedValueStaticFormat.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNTypedValueOffset.h"
#import "ZNStaticPatchFormat.h"
#import "ZNPatchCore.h"
#import <mach-o/loader.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <algorithm>

static uint64_t ZNTVAlign8(uint64_t value) { return (value + 7ULL) & ~7ULL; }

static NSString *ZNTVCleanOutputName(NSString *path) {
    NSString *name = path.lastPathComponent ?: @"";
    if ([name hasSuffix:@".znpatched"]) name = [name substringToIndex:name.length - @".znpatched".length];
    return name;
}

static NSString *ZNTVResolvedTarget(NSString *target) {
    NSString *t = [target ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length || [t caseInsensitiveCompare:@"main"] == NSOrderedSame) {
        NSString *name = [ZNModuleManager sharedManager].mainExecutable[@"name"];
        return name.length ? name : @"main";
    }
    return t.lastPathComponent.length ? t.lastPathComponent : t;
}

static NSArray<ZNTypedValueOffset *> *ZNTVEntriesForOutput(NSString *path) {
    NSString *outputName = ZNTVCleanOutputName(path);
    NSMutableArray *matches = [NSMutableArray array];
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        if (row.controlKind == ZNOffsetControlKindSwitch) continue;
        ZNTypedValueOffset *entry = row.typedEntry;
        if (!row.validated || !entry.isValidated) continue;
        NSString *target = ZNTVResolvedTarget(entry.target);
        if ([target caseInsensitiveCompare:outputName] == NSOrderedSame) [matches addObject:entry];
    }
    return matches;
}

static void ZNTVCopyFixed(char *dst, size_t cap, NSString *value) {
    memset(dst, 0, cap);
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length || !cap) return;
    memcpy(dst, data.bytes, std::min(cap - 1, (size_t)data.length));
}

static BOOL ZNTVEmbedOne(NSString *path, NSArray<ZNTypedValueOffset *> *values, NSString **error) {
    if (!values.count) return YES;
    if (values.count > ZNTV_STATIC_MAX_ENTRIES) { if (error) *error = @"Typed Value 条目超过 256"; return NO; }

    int fd = open(path.fileSystemRepresentation, O_RDWR);
    if (fd < 0) { if (error) *error = @"无法打开生成后二进制"; return NO; }
    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) { close(fd); if (error) *error = @"无法读取生成后二进制大小"; return NO; }
    size_t size = (size_t)st.st_size;
    uint8_t *base = (uint8_t *)mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (base == MAP_FAILED) { close(fd); if (error) *error = @"mmap 生成后二进制失败"; return NO; }

    BOOL ok = NO;
    NSString *local = nil;
    do {
        if (size < sizeof(struct mach_header_64)) { local = @"Mach-O 太小"; break; }
        struct mach_header_64 *mh = (struct mach_header_64 *)base;
        if (mh->magic != MH_MAGIC_64) { local = @"Typed Value persistence 仅支持 thin 64-bit Mach-O"; break; }
        uint8_t *cursor = base + sizeof(*mh), *limit = cursor + mh->sizeofcmds;
        if (limit > base + size) { local = @"load commands 越界"; break; }

        struct section_64 *ownedSection = NULL;
        struct segment_command_64 *ownedSegment = NULL;
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > limit) break;
            struct load_command *lc = (struct load_command *)cursor;
            if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
                if (strncmp(seg->segname, "__ZNDATA", 16) == 0) {
                    uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
                    if (lc->cmdsize >= sizeof(*seg) + sectionBytes) {
                        struct section_64 *secs = (struct section_64 *)(seg + 1);
                        for (uint32_t j = 0; j < seg->nsects; j++) {
                            if (strncmp(secs[j].sectname, "__zndata", 16) == 0) { ownedSegment = seg; ownedSection = &secs[j]; break; }
                        }
                    }
                }
            }
            if (ownedSection) break;
            cursor += lc->cmdsize;
        }
        if (!ownedSection || !ownedSegment) { local = @"输出文件没有 __ZNDATA/__zndata"; break; }
        if (ownedSegment->fileoff > size || ownedSegment->filesize > size - ownedSegment->fileoff) { local = @"__ZNDATA file range 越界"; break; }
        if (ownedSection->offset < ownedSegment->fileoff || ownedSection->offset > ownedSegment->fileoff + ownedSegment->filesize) { local = @"__zndata offset 异常"; break; }
        if (ownedSection->size < sizeof(ZN44StaticHeader)) { local = @"__zndata 缺少 Static Header"; break; }

        ZN44StaticHeader *staticHeader = (ZN44StaticHeader *)(base + ownedSection->offset);
        if (staticHeader->magic0 != ZN44_STATIC_MAGIC0 || staticHeader->magic1 != ZN44_STATIC_MAGIC1 || staticHeader->entrySize != sizeof(ZN44StaticEntry) || staticHeader->count > ZN44_STATIC_MAX_ENTRIES) { local = @"__zndata Static Header 无效"; break; }
        uint64_t staticUsed = sizeof(ZN44StaticHeader) + (uint64_t)staticHeader->count * sizeof(ZN44StaticEntry);
        uint64_t typedOffsetInSection = ZNTVAlign8(staticUsed);
        uint64_t typedBytes = sizeof(ZNTVStaticHeader) + (uint64_t)values.count * sizeof(ZNTVStaticEntry);
        uint64_t required = typedOffsetInSection + typedBytes;
        uint64_t sectionRelative = (uint64_t)ownedSection->offset - ownedSegment->fileoff;
        if (required > ownedSegment->filesize - sectionRelative) { local = [NSString stringWithFormat:@"__ZNDATA 剩余空间不足：need=0x%llX capacity=0x%llX", required, ownedSegment->filesize - sectionRelative]; break; }

        uint8_t *typedBase = base + ownedSection->offset + typedOffsetInSection;
        memset(typedBase, 0, typedBytes);
        ZNTVStaticHeader *header = (ZNTVStaticHeader *)typedBase;
        header->magic0 = ZNTV_STATIC_MAGIC0;
        header->magic1 = ZNTV_STATIC_MAGIC1;
        header->version = ZNTV_STATIC_VERSION;
        header->count = (uint32_t)values.count;
        header->entrySize = sizeof(ZNTVStaticEntry);
        ZNTVStaticEntry *entries = (ZNTVStaticEntry *)(header + 1);

        for (NSUInteger i = 0; i < values.count; i++) {
            ZNTypedValueOffset *source = values[i];
            ZNTVStaticEntry *entry = &entries[i];
            entry->rva = source.rva;
            entry->minValue = source.minValue;
            entry->maxValue = source.maxValue;
            entry->stepValue = source.stepValue;
            entry->defaultValue = source.valueText.doubleValue;
            entry->control = source.controlKind == ZNTypedValueControlKindNumber ? ZNTVStaticControlNumber : ZNTVStaticControlSlider;
            ZNTVCopyFixed(entry->valueType, sizeof(entry->valueType), source.valueType.uppercaseString ?: @"F32");
            ZNTVCopyFixed(entry->title, sizeof(entry->title), source.title.length ? source.title : [NSString stringWithFormat:@"Value #%lu", (unsigned long)i + 1]);
        }

        ownedSection->size = required;
        if (msync(base, size, MS_SYNC) != 0) { local = @"Typed Value metadata msync 失败"; break; }
        ok = YES;
    } while (0);

    munmap(base, size);
    close(fd);
    if (!ok && error) *error = local ?: @"Typed Value metadata 写入失败";
    return ok;
}

BOOL ZNTypedValueEmbedIntoGeneratedOutputs(NSArray<NSString *> *outputs, NSString **report, NSString **error) {
    NSUInteger embeddedFiles = 0, embeddedEntries = 0;
    for (NSString *path in outputs ?: @[]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        NSArray<ZNTypedValueOffset *> *entries = ZNTVEntriesForOutput(path);
        if (!entries.count) continue;
        NSString *local = nil;
        if (!ZNTVEmbedOne(path, entries, &local)) { if (error) *error = [NSString stringWithFormat:@"%@：%@", path.lastPathComponent, local ?: @"Typed Value 写入失败"]; return NO; }
        embeddedFiles++;
        embeddedEntries += entries.count;
    }
    if (report) *report = [NSString stringWithFormat:@"M5.11 Unified Typed metadata：%lu files / %lu entries", (unsigned long)embeddedFiles, (unsigned long)embeddedEntries];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-unified-persist] files=%lu entries=%lu", (unsigned long)embeddedFiles, (unsigned long)embeddedEntries]];
    return YES;
}
