#import "ZNTypedOnlyBinaryBuilder.h"
#import "ZNStaticPatchFormat.h"
#import "ZNPatchCore.h"
#import <mach-o/loader.h>
#import <mach/machine.h>
#import <mach/vm_prot.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

static const uint64_t kZNTBDataBytes = 0x10000ULL;
struct ZNTBOwnedDataCommand { struct segment_command_64 segment; struct section_64 section; };
struct ZNTBLayout {
    uint64_t imageVMBase;
    uint64_t firstFileSectionOffset;
    uint64_t oldCommandEnd;
    uint64_t linkeditCommandOffset;
    uint64_t linkeditVMAddr;
    uint64_t linkeditFileOffset;
    uint64_t linkeditFileSize;
};
static_assert(sizeof(ZNTBOwnedDataCommand) == sizeof(struct segment_command_64) + sizeof(struct section_64), "typed-only owned segment ABI");

static BOOL ZNTBShiftU32(uint32_t *field, uint64_t threshold, uint64_t delta, NSString **error) {
    if (!field || !*field || (uint64_t)*field < threshold) return YES;
    uint64_t value = (uint64_t)*field + delta;
    if (value > UINT32_MAX) { if (error) *error = @"Typed-only Builder：__LINKEDIT offset 超过 32-bit 字段范围"; return NO; }
    *field = (uint32_t)value;
    return YES;
}

static BOOL ZNTBParse(uint8_t *base, size_t size, ZNTBLayout *layout, NSString **error) {
    if (!base || !layout || size < sizeof(struct mach_header_64)) { if (error) *error = @"Typed-only Builder：Mach-O 太小"; return NO; }
    struct mach_header_64 *mh = (struct mach_header_64 *)base;
    if (mh->magic != MH_MAGIC_64 || mh->cputype != CPU_TYPE_ARM64) { if (error) *error = @"Typed-only Builder：仅支持 thin arm64 Mach-O"; return NO; }
    uint64_t commandEnd = sizeof(*mh) + (uint64_t)mh->sizeofcmds;
    if (commandEnd > size) { if (error) *error = @"Typed-only Builder：load commands 越界"; return NO; }
    memset(layout, 0, sizeof(*layout));
    layout->imageVMBase = UINT64_MAX;
    layout->firstFileSectionOffset = UINT64_MAX;
    layout->oldCommandEnd = commandEnd;
    layout->linkeditCommandOffset = UINT64_MAX;
    uint8_t *cursor = base + sizeof(*mh), *limit = base + commandEnd;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > limit) { if (error) *error = @"Typed-only Builder：load command 损坏"; return NO; }
        struct load_command *lc = (struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) { if (error) *error = @"Typed-only Builder：load command size 损坏"; return NO; }
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
            if (seg->fileoff > size || seg->filesize > size - seg->fileoff) { if (error) *error = @"Typed-only Builder：segment file range 越界"; return NO; }
            if (strncmp(seg->segname, SEG_TEXT, 16) == 0) layout->imageVMBase = seg->vmaddr;
            if (strncmp(seg->segname, SEG_LINKEDIT, 16) == 0) {
                layout->linkeditCommandOffset = (uint64_t)(cursor - base);
                layout->linkeditVMAddr = seg->vmaddr;
                layout->linkeditFileOffset = seg->fileoff;
                layout->linkeditFileSize = seg->filesize;
            }
            uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
            if (lc->cmdsize < sizeof(*seg) + sectionBytes) { if (error) *error = @"Typed-only Builder：section table 越界"; return NO; }
            struct section_64 *sections = (struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++) {
                uint32_t type = sections[j].flags & SECTION_TYPE;
                BOOL zero = type == S_ZEROFILL || type == S_GB_ZEROFILL || type == S_THREAD_LOCAL_ZEROFILL;
                if (!zero && sections[j].size && sections[j].offset) layout->firstFileSectionOffset = MIN(layout->firstFileSectionOffset, (uint64_t)sections[j].offset);
            }
        }
        cursor += lc->cmdsize;
    }
    if (layout->imageVMBase == UINT64_MAX || layout->linkeditCommandOffset == UINT64_MAX || !layout->linkeditFileOffset || !layout->linkeditFileSize || layout->firstFileSectionOffset == UINT64_MAX) {
        if (error) *error = @"Typed-only Builder：缺少 __TEXT/__LINKEDIT 或 header layout";
        return NO;
    }
    if (layout->linkeditFileOffset + layout->linkeditFileSize > size) { if (error) *error = @"Typed-only Builder：__LINKEDIT 超出文件"; return NO; }
    return YES;
}

static BOOL ZNTBShiftLinkedit(uint8_t *base, size_t size, uint64_t threshold, uint64_t delta, NSString **error) {
    struct mach_header_64 *mh = (struct mach_header_64 *)base;
    uint8_t *cursor = base + sizeof(*mh), *limit = cursor + mh->sizeofcmds;
    if (limit > base + size) { if (error) *error = @"Typed-only Builder：扩展后 load commands 越界"; return NO; }
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > limit) return NO;
        struct load_command *lc = (struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) return NO;
        switch (lc->cmd) {
            case LC_SEGMENT_64: {
                struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
                if (strncmp(seg->segname, SEG_LINKEDIT, 16) == 0) { seg->fileoff += delta; seg->vmaddr += delta; }
                break;
            }
            case LC_DYLD_INFO: case LC_DYLD_INFO_ONLY: {
                struct dyld_info_command *d=(struct dyld_info_command *)cursor;
                if(!ZNTBShiftU32(&d->rebase_off,threshold,delta,error)||!ZNTBShiftU32(&d->bind_off,threshold,delta,error)||!ZNTBShiftU32(&d->weak_bind_off,threshold,delta,error)||!ZNTBShiftU32(&d->lazy_bind_off,threshold,delta,error)||!ZNTBShiftU32(&d->export_off,threshold,delta,error)) return NO;
                break;
            }
            case LC_SYMTAB: {
                struct symtab_command *s=(struct symtab_command *)cursor;
                if(!ZNTBShiftU32(&s->symoff,threshold,delta,error)||!ZNTBShiftU32(&s->stroff,threshold,delta,error)) return NO;
                break;
            }
            case LC_DYSYMTAB: {
                struct dysymtab_command *d=(struct dysymtab_command *)cursor;
                if(!ZNTBShiftU32(&d->tocoff,threshold,delta,error)||!ZNTBShiftU32(&d->modtaboff,threshold,delta,error)||!ZNTBShiftU32(&d->extrefsymoff,threshold,delta,error)||!ZNTBShiftU32(&d->indirectsymoff,threshold,delta,error)||!ZNTBShiftU32(&d->extreloff,threshold,delta,error)||!ZNTBShiftU32(&d->locreloff,threshold,delta,error)) return NO;
                break;
            }
            case LC_TWOLEVEL_HINTS: {
                struct twolevel_hints_command *h=(struct twolevel_hints_command *)cursor;
                if(!ZNTBShiftU32(&h->offset,threshold,delta,error)) return NO;
                break;
            }
            case LC_CODE_SIGNATURE: case LC_SEGMENT_SPLIT_INFO: case LC_FUNCTION_STARTS: case LC_DATA_IN_CODE:
#ifdef LC_DYLIB_CODE_SIGN_DRS
            case LC_DYLIB_CODE_SIGN_DRS:
#endif
#ifdef LC_LINKER_OPTIMIZATION_HINT
            case LC_LINKER_OPTIMIZATION_HINT:
#endif
#ifdef LC_DYLD_EXPORTS_TRIE
            case LC_DYLD_EXPORTS_TRIE:
#endif
#ifdef LC_DYLD_CHAINED_FIXUPS
            case LC_DYLD_CHAINED_FIXUPS:
#endif
            {
                struct linkedit_data_command *d=(struct linkedit_data_command *)cursor;
                if(!ZNTBShiftU32(&d->dataoff,threshold,delta,error)) return NO;
                break;
            }
#ifdef LC_NOTE
            case LC_NOTE: {
                struct note_command *n=(struct note_command *)cursor;
                if(n->offset && n->offset >= threshold) n->offset += delta;
                break;
            }
#endif
            default: break;
        }
        cursor += lc->cmdsize;
    }
    return YES;
}

static BOOL ZNTBBuildTarget(NSString *target, NSString *folder, NSString **outPath, NSDictionary **metadata, NSString **error) {
    NSDictionary *module = [[ZNModuleManager sharedManager] moduleNamed:target];
    if (!module) { if (error) *error = [NSString stringWithFormat:@"Typed-only Builder：目标模块未加载：%@", target ?: @""]; return NO; }
    NSString *inputPath = [module[@"path"] isKindOfClass:NSString.class] ? module[@"path"] : @"";
    if (!inputPath.length) { if (error) *error = @"Typed-only Builder：无法取得目标 Mach-O 路径"; return NO; }
    NSString *name = inputPath.lastPathComponent.length ? inputPath.lastPathComponent : target;
    NSString *outputPath = [folder stringByAppendingPathComponent:name];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:outputPath error:nil];
    NSError *copyError = nil;
    if (![fm copyItemAtPath:inputPath toPath:outputPath error:&copyError]) { if (error) *error = [NSString stringWithFormat:@"Typed-only Builder：复制目标失败：%@", copyError.localizedDescription ?: @"未知错误"]; return NO; }

    int fd = open(outputPath.fileSystemRepresentation, O_RDWR);
    if (fd < 0) { [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：打开输出失败"; return NO; }
    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：输出大小无效"; return NO; }
    uint64_t oldSize = (uint64_t)st.st_size;
    uint8_t *oldBase = (uint8_t *)mmap(NULL, (size_t)oldSize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (oldBase == MAP_FAILED) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：mmap 原始输出失败"; return NO; }
    ZNTBLayout layout = {};
    NSString *localError = nil;
    BOOL parsed = ZNTBParse(oldBase, (size_t)oldSize, &layout, &localError);
    munmap(oldBase, (size_t)oldSize);
    if (!parsed) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = localError; return NO; }

    const uint64_t extraCommands = sizeof(ZNTBOwnedDataCommand);
    if (layout.oldCommandEnd + extraCommands > layout.firstFileSectionOffset) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：Mach-O header slack 不足以加入 __ZNDATA"; return NO; }
    if (layout.linkeditFileOffset > UINT32_MAX) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：__ZNDATA section.offset 超过 32-bit"; return NO; }

    uint64_t newSize = oldSize + kZNTBDataBytes;
    if (newSize > SIZE_MAX || ftruncate(fd, (off_t)newSize) != 0) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：扩展输出失败"; return NO; }
    uint8_t *base = (uint8_t *)mmap(NULL, (size_t)newSize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (base == MAP_FAILED) { close(fd); [fm removeItemAtPath:outputPath error:nil]; if (error) *error = @"Typed-only Builder：mmap 扩展输出失败"; return NO; }

    BOOL ok = NO;
    do {
        memmove(base + layout.linkeditFileOffset + kZNTBDataBytes, base + layout.linkeditFileOffset, oldSize - layout.linkeditFileOffset);
        memset(base + layout.linkeditFileOffset, 0, kZNTBDataBytes);
        memmove(base + layout.linkeditCommandOffset + extraCommands, base + layout.linkeditCommandOffset, layout.oldCommandEnd - layout.linkeditCommandOffset);
        memset(base + layout.linkeditCommandOffset, 0, extraCommands);

        struct mach_header_64 *mh = (struct mach_header_64 *)base;
        uint64_t newSizeOfCmds = (uint64_t)mh->sizeofcmds + extraCommands;
        if (newSizeOfCmds > UINT32_MAX) { localError = @"Typed-only Builder：sizeofcmds 溢出"; break; }
        mh->ncmds += 1;
        mh->sizeofcmds = (uint32_t)newSizeOfCmds;

        ZNTBOwnedDataCommand command = {};
        command.segment.cmd = LC_SEGMENT_64;
        command.segment.cmdsize = sizeof(command);
        strncpy(command.segment.segname, "__ZNDATA", 16);
        command.segment.vmaddr = layout.linkeditVMAddr;
        command.segment.vmsize = kZNTBDataBytes;
        command.segment.fileoff = layout.linkeditFileOffset;
        command.segment.filesize = kZNTBDataBytes;
        command.segment.maxprot = VM_PROT_READ|VM_PROT_WRITE;
        command.segment.initprot = VM_PROT_READ|VM_PROT_WRITE;
        command.segment.nsects = 1;
        strncpy(command.section.sectname, "__zndata", 16);
        strncpy(command.section.segname, "__ZNDATA", 16);
        command.section.addr = layout.linkeditVMAddr;
        command.section.size = sizeof(ZN44StaticHeader);
        command.section.offset = (uint32_t)layout.linkeditFileOffset;
        command.section.align = 3;
        command.section.flags = S_REGULAR;
        memcpy(base + layout.linkeditCommandOffset, &command, sizeof(command));

        if (!ZNTBShiftLinkedit(base, (size_t)newSize, layout.linkeditFileOffset, kZNTBDataBytes, &localError)) break;

        ZN44StaticHeader *header = (ZN44StaticHeader *)(base + layout.linkeditFileOffset);
        memset(header, 0, sizeof(*header));
        header->magic0 = ZN44_STATIC_MAGIC0;
        header->magic1 = ZN44_STATIC_MAGIC1;
        header->version = ZN44_STATIC_VERSION_V3;
        header->count = 0;
        header->entrySize = sizeof(ZN44StaticEntry);
        if (msync(base, (size_t)newSize, MS_SYNC) != 0) { localError = [NSString stringWithFormat:@"Typed-only Builder：msync 失败 errno=%d", errno]; break; }
        ok = YES;
    } while (0);

    munmap(base, (size_t)newSize);
    close(fd);
    if (!ok) { [fm removeItemAtPath:outputPath error:nil]; if (error) *error = localError ?: @"Typed-only Builder 生成失败"; return NO; }
    if (outPath) *outPath = outputPath;
    if (metadata) *metadata = @{
        @"target": target ?: @"",
        @"input": inputPath,
        @"output": outputPath,
        @"builder": @"M5.11 Typed-only Generic Target Container",
        @"staticPatchCount": @0,
        @"ownedDataBytes": @(kZNTBDataBytes),
        @"keepsOriginalFilename": @YES,
        @"needsResign": @YES
    };
    return YES;
}

BOOL ZNTypedOnlyBinaryBuilderBuild(NSArray<NSString *> *targets, NSArray<NSString *> **outputs, NSString **report, NSString **error) {
    NSMutableOrderedSet<NSString *> *unique = [NSMutableOrderedSet orderedSet];
    for (NSString *target in targets ?: @[]) {
        NSString *t = [target ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) continue;
        if ([t caseInsensitiveCompare:@"main"] == NSOrderedSame) {
            NSString *mainName = [ZNModuleManager sharedManager].mainExecutable[@"name"];
            if (mainName.length) t = mainName;
        }
        [unique addObject:t.lastPathComponent.length ? t.lastPathComponent : t];
    }
    if (!unique.count) { if (error) *error = @"Typed-only Builder：没有目标"; return NO; }

    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ZonoePatchOutput"];
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *folder = [root stringByAppendingPathComponent:[[formatter stringFromDate:[NSDate date]] stringByAppendingString:@"-typed"]];
    NSError *directoryError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&directoryError]) { if (error) *error = directoryError.localizedDescription ?: @"Typed-only Builder：创建目录失败"; return NO; }

    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *meta = [NSMutableArray array];
    for (NSString *target in unique) {
        NSString *path = nil, *local = nil; NSDictionary *m = nil;
        if (!ZNTBBuildTarget(target, folder, &path, &m, &local)) {
            [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
            if (error) *error = [NSString stringWithFormat:@"%@：%@", target, local ?: @"生成失败"];
            return NO;
        }
        if (path.length) [paths addObject:path];
        if (m) [meta addObject:m];
    }

    NSDictionary *reportObject = @{
        @"format": @"com.zonoe.typed-only-builder/v1",
        @"generatedAt": [[NSDate date] description],
        @"typedOnly": @YES,
        @"targets": meta,
        @"notes": @[
            @"No Static Patch row is required",
            @"Each target receives an owned RW __ZNDATA/__zndata container",
            @"No executable site is modified by the Typed-only Builder",
            @"Typed Value metadata is appended by the M5.11 persistence stage"
        ]
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:reportObject options:NSJSONWritingPrettyPrinted error:nil];
    NSString *reportPath = [folder stringByAppendingPathComponent:@"build_report.json"];
    if (json) [json writeToFile:reportPath atomically:YES];
    [paths addObject:reportPath];
    if (outputs) *outputs = paths;
    if (report) *report = [NSString stringWithFormat:@"M5.11 Typed-only Builder：%lu targets · 输出：%@", (unsigned long)unique.count, folder];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-typed-only-build] targets=%lu folder=%@", (unsigned long)unique.count, folder]];
    return YES;
}
