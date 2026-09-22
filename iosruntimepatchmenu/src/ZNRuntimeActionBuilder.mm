#import "ZNRuntimeActionBuilder.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNStaticPatchFormat.h"
#import "ZNPatchCore.h"
#import <mach-o/loader.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#include <string.h>

static uint64_t ZNRABAlign8(uint64_t value) {
    return (value + 7ULL) & ~7ULL;
}

static BOOL ZNRABAppendString(NSMutableData *data, NSString *value, uint32_t *offset, NSString **error) {
    NSData *utf8 = [(value ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) utf8 = [NSData data];
    if ((uint64_t)data.length + (uint64_t)utf8.length + 1ULL > UINT32_MAX) {
        if (error) *error = @"Runtime Action string pool 超过 32-bit offset 范围";
        return NO;
    }
    if (offset) *offset = (uint32_t)data.length;
    [data appendData:utf8];
    uint8_t zero = 0;
    [data appendBytes:&zero length:1];
    return YES;
}

static NSData *ZNRABSerialize(NSArray<ZNRuntimeMethodAction *> *actions, NSString **error) {
    if (!actions.count) return [NSData data];
    if (actions.count > ZN_RUNTIME_ACTION_MAX_ENTRIES) {
        if (error) *error = [NSString stringWithFormat:@"Runtime Method Call 数量超过上限 %u", ZN_RUNTIME_ACTION_MAX_ENTRIES];
        return nil;
    }

    uint64_t fixed = sizeof(ZNRuntimeActionHeader) + actions.count * sizeof(ZNRuntimeMethodCallEntry);
    if (fixed > UINT32_MAX) {
        if (error) *error = @"Runtime Action 固定表过大";
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)fixed];
    ZNRuntimeActionHeader *header = (ZNRuntimeActionHeader *)data.mutableBytes;
    header->magic = ZN_RUNTIME_ACTION_MAGIC;
    header->version = ZN_RUNTIME_ACTION_VERSION;
    header->count = (uint32_t)actions.count;
    header->entrySize = sizeof(ZNRuntimeMethodCallEntry);
    header->stringPoolOffset = (uint32_t)fixed;

    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodAction *action = actions[i];
        if (action.argumentCount != 0) {
            if (error) *error = [NSString stringWithFormat:@"%@：M4.1 仅能导出 0 参数 Runtime Method Call", action.canonicalIdentity];
            return nil;
        }
        uint32_t titleOffset = 0, groupOffset = 0, assemblyOffset = 0;
        uint32_t namespaceOffset = 0, classOffset = 0, methodOffset = 0;
        NSString *stringError = nil;
        if (!ZNRABAppendString(data, action.title, &titleOffset, &stringError) ||
            !ZNRABAppendString(data, action.group, &groupOffset, &stringError) ||
            !ZNRABAppendString(data, action.assembly, &assemblyOffset, &stringError) ||
            !ZNRABAppendString(data, action.namespaceName, &namespaceOffset, &stringError) ||
            !ZNRABAppendString(data, action.className, &classOffset, &stringError) ||
            !ZNRABAppendString(data, action.methodName, &methodOffset, &stringError)) {
            if (error) *error = stringError ?: @"Runtime Action string pool 写入失败";
            return nil;
        }
        ZNRuntimeMethodCallEntry *entries = (ZNRuntimeMethodCallEntry *)((uint8_t *)data.mutableBytes + sizeof(ZNRuntimeActionHeader));
        ZNRuntimeMethodCallEntry *entry = &entries[i];
        entry->actionID = action.actionID;
        entry->kind = ZNRuntimeActionKindIL2CPPMethodCall;
        entry->argumentCount = (uint32_t)action.argumentCount;
        entry->titleOffset = titleOffset;
        entry->groupOffset = groupOffset;
        entry->assemblyOffset = assemblyOffset;
        entry->namespaceOffset = namespaceOffset;
        entry->classOffset = classOffset;
        entry->methodOffset = methodOffset;
    }

    while (data.length & 7u) {
        uint8_t zero = 0;
        [data appendBytes:&zero length:1];
    }
    if (data.length > UINT32_MAX) {
        if (error) *error = @"Runtime Action table 超过 4GB";
        return nil;
    }
    // data.mutableBytes can move after append, so reacquire pointers only now.
    header = (ZNRuntimeActionHeader *)data.mutableBytes;
    header->totalSize = (uint32_t)data.length;
    header->stringPoolSize = header->totalSize - header->stringPoolOffset;
    return [data copy];
}

static BOOL ZNRABIsZeroRange(const uint8_t *p, size_t n) {
    for (size_t i = 0; i < n; i++) if (p[i] != 0) return NO;
    return YES;
}


static void ZNRABUpdateBuildReport(NSArray<NSString *> *builderOutputs,
                                  NSArray<ZNRuntimeMethodAction *> *actions,
                                  NSUInteger tableBytes) {
    NSString *reportPath = nil;
    for (NSString *path in builderOutputs) {
        if ([path.lastPathComponent isEqualToString:@"build_report.json"]) { reportPath = path; break; }
    }
    if (!reportPath.length) return;
    NSData *json = [NSData dataWithContentsOfFile:reportPath];
    if (!json.length) return;
    NSMutableDictionary *object = [[NSJSONSerialization JSONObjectWithData:json
                                                                    options:NSJSONReadingMutableContainers
                                                                      error:nil] mutableCopy];
    if (![object isKindOfClass:NSMutableDictionary.class]) return;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:actions.count];
    for (ZNRuntimeMethodAction *action in actions) {
        [items addObject:@{
            @"actionID": @(action.actionID),
            @"title": action.title ?: @"",
            @"identity": action.canonicalIdentity ?: @"",
            @"argumentCount": @(action.argumentCount),
        }];
    }
    object[@"runtimeMethodCall"] = @{
        @"format": @"com.zonoe.runtime-action/v1",
        @"version": @1,
        @"storage": @"__ZNDATA/__zndata after Static Dispatch table",
        @"staticEntryABIPreserved": @YES,
        @"count": @(actions.count),
        @"bytes": @(tableBytes),
        @"m41ZeroArgOnly": @YES,
        @"actions": items,
    };
    NSData *updated = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    if (updated) [updated writeToFile:reportPath atomically:YES];
}

static BOOL ZNRABEmbedTableAtPath(NSString *path, NSData *table, NSString **error) {
    int fd = open(path.fileSystemRepresentation, O_RDWR);
    if (fd < 0) {
        if (error) *error = [NSString stringWithFormat:@"打开 %@ 失败 errno=%d", path.lastPathComponent, errno];
        return NO;
    }
    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        close(fd);
        if (error) *error = @"读取生成物大小失败";
        return NO;
    }
    size_t fileSize = (size_t)st.st_size;
    uint8_t *base = (uint8_t *)mmap(NULL, fileSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (base == MAP_FAILED) {
        close(fd);
        if (error) *error = @"mmap 生成物失败";
        return NO;
    }

    BOOL ok = NO;
    NSString *localError = nil;
    do {
        if (fileSize < sizeof(struct mach_header_64)) { localError = @"生成物不是完整 Mach-O"; break; }
        struct mach_header_64 *mh = (struct mach_header_64 *)base;
        if (mh->magic != MH_MAGIC_64) { localError = @"Runtime Action Builder 仅支持 thin 64-bit Mach-O"; break; }
        uint64_t commandEnd = sizeof(*mh) + (uint64_t)mh->sizeofcmds;
        if (commandEnd > fileSize) { localError = @"Mach-O load commands 越界"; break; }

        struct segment_command_64 *owned = NULL;
        struct section_64 *zndata = NULL;
        uint8_t *cursor = base + sizeof(*mh);
        uint8_t *limit = base + commandEnd;
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > limit) { localError = @"load command 损坏"; break; }
            struct load_command *lc = (struct load_command *)cursor;
            if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) { localError = @"load command size 损坏"; break; }
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
                if (strncmp(seg->segname, "__ZNDATA", 16) == 0) {
                    owned = seg;
                    uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
                    if (lc->cmdsize < sizeof(*seg) + sectionBytes) { localError = @"__ZNDATA section table 越界"; break; }
                    struct section_64 *sections = (struct section_64 *)(seg + 1);
                    for (uint32_t j = 0; j < seg->nsects; j++) {
                        if (strncmp(sections[j].sectname, "__zndata", 16) == 0) { zndata = &sections[j]; break; }
                    }
                }
            }
            cursor += lc->cmdsize;
        }
        if (localError) break;
        if (!owned || !zndata) { localError = @"生成物缺少 V3-owned __ZNDATA/__zndata"; break; }
        if (owned->fileoff > fileSize || owned->filesize > fileSize - owned->fileoff) { localError = @"__ZNDATA file range 越界"; break; }
        if (zndata->offset > fileSize || zndata->size > fileSize - zndata->offset) { localError = @"__zndata section range 越界"; break; }
        if (zndata->size < sizeof(ZN44StaticHeader)) { localError = @"__zndata 太小，缺少 Static Header"; break; }

        ZN44StaticHeader *staticHeader = (ZN44StaticHeader *)(base + zndata->offset);
        if (staticHeader->magic0 != ZN44_STATIC_MAGIC0 || staticHeader->magic1 != ZN44_STATIC_MAGIC1 ||
            staticHeader->entrySize != sizeof(ZN44StaticEntry) || staticHeader->count > ZN44_STATIC_MAX_ENTRIES) {
            localError = @"__zndata Static Dispatch Header 无效";
            break;
        }
        uint64_t staticBytes = sizeof(ZN44StaticHeader) + (uint64_t)staticHeader->count * staticHeader->entrySize;
        staticBytes = ZNRABAlign8(staticBytes);
        uint64_t sectionStart = zndata->offset;
        uint64_t actionOffset = sectionStart + staticBytes;
        uint64_t segmentEnd = owned->fileoff + owned->filesize;
        if (actionOffset < sectionStart || actionOffset > segmentEnd || table.length > segmentEnd - actionOffset) {
            localError = [NSString stringWithFormat:@"__ZNDATA owned capacity 不足：action=%lu bytes", (unsigned long)table.length];
            break;
        }
        if (actionOffset + table.length > fileSize) { localError = @"Runtime Action 写入范围超出文件"; break; }
        if (!ZNRABIsZeroRange(base + actionOffset, table.length)) {
            localError = @"Runtime Action 目标区域不是 V3-owned zero padding；拒绝覆盖未知数据";
            break;
        }

        memcpy(base + actionOffset, table.bytes, table.length);
        uint64_t newSectionSize = (actionOffset - sectionStart) + table.length;
        if (newSectionSize > owned->filesize) { localError = @"Runtime Action section size 超出 owned segment"; break; }
        zndata->size = newSectionSize;
        if (msync(base, fileSize, MS_SYNC) != 0) {
            localError = [NSString stringWithFormat:@"Runtime Action msync 失败 errno=%d", errno];
            break;
        }
        ok = YES;
    } while (0);

    munmap(base, fileSize);
    close(fd);
    if (!ok && error) *error = localError ?: @"Runtime Action 写入失败";
    return ok;
}

BOOL ZNRuntimeActionEmbedIntoGeneratedOutputs(NSArray<NSString *> *builderOutputs,
                                              NSString **report,
                                              NSString **error) {
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (!actions.count) {
        if (report) *report = @"Runtime Method Call：无待导出 action";
        return YES;
    }

    NSString *serializeError = nil;
    NSData *table = ZNRABSerialize(actions, &serializeError);
    if (!table.length) {
        if (error) *error = serializeError ?: @"Runtime Action 序列化失败";
        return NO;
    }

    NSString *unityOutput = nil;
    for (NSString *path in builderOutputs) {
        NSString *name = path.lastPathComponent.lowercaseString;
        if ([name hasSuffix:@".znpatched"] && [name containsString:@"unityframework"]) {
            unityOutput = path;
            break;
        }
    }
    if (!unityOutput.length) {
        if (error) *error = @"存在 Runtime Method Call，但本次 Builder 没有 UnityFramework.znpatched 输出。M4.1 首版请至少保留一个已验证的 UnityFramework Static Patch 再生成。";
        return NO;
    }

    NSString *embedError = nil;
    if (!ZNRABEmbedTableAtPath(unityOutput, table, &embedError)) {
        if (error) *error = embedError ?: @"Runtime Action 嵌入失败";
        return NO;
    }

    ZNRABUpdateBuildReport(builderOutputs, actions, table.length);
    if (report) {
        *report = [NSString stringWithFormat:@"Runtime Method Call：已嵌入 %lu 个 0 参数 action · %lu bytes · %@",
                   (unsigned long)actions.count,
                   (unsigned long)table.length,
                   unityOutput.lastPathComponent];
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] embedded count=%lu bytes=%lu output=%@",
                                         (unsigned long)actions.count,
                                         (unsigned long)table.length,
                                         unityOutput.lastPathComponent]];
    return YES;
}
