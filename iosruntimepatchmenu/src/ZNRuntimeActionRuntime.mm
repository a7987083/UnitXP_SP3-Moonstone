#import "ZNRuntimeActionRuntime.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNStaticPatchFormat.h"
#import "ZNPatchCore.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <string.h>

static uint64_t ZNRARAlign8(uint64_t value) {
    return (value + 7ULL) & ~7ULL;
}

@interface ZNRuntimeMethodActionRecord ()
@property(nonatomic,assign,readwrite) uint32_t actionID;
@property(nonatomic,copy,readwrite) NSString *title;
@property(nonatomic,copy,readwrite) NSString *group;
@property(nonatomic,copy,readwrite) NSString *assembly;
@property(nonatomic,copy,readwrite) NSString *namespaceName;
@property(nonatomic,copy,readwrite) NSString *className;
@property(nonatomic,copy,readwrite) NSString *methodName;
@property(nonatomic,assign,readwrite) NSUInteger argumentCount;
@property(nonatomic,copy,readwrite) NSString *sourceImage;
@end

@implementation ZNRuntimeMethodActionRecord
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _title = @""; _group = @"Runtime Methods"; _assembly = @"";
    _namespaceName = @""; _className = @""; _methodName = @""; _sourceImage = @"";
    return self;
}
- (NSString *)canonicalIdentity {
    NSString *owner = self.namespaceName.length
        ? [NSString stringWithFormat:@"%@.%@", self.namespaceName, self.className]
        : self.className;
    return [NSString stringWithFormat:@"%@!%@::%@/%lu",
            self.assembly ?: @"", owner ?: @"", self.methodName ?: @"", (unsigned long)self.argumentCount];
}
@end

static NSString *ZNRARReadString(const uint8_t *table,
                                 const ZNRuntimeActionHeader *header,
                                 uint32_t offset) {
    if (!table || !header) return nil;
    if (offset < header->stringPoolOffset || offset >= header->totalSize) return nil;
    const uint8_t *start = table + offset;
    const uint8_t *end = table + header->totalSize;
    const uint8_t *nul = (const uint8_t *)memchr(start, 0, (size_t)(end - start));
    if (!nul) return nil;
    NSData *data = [NSData dataWithBytes:start length:(NSUInteger)(nul - start)];
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return value;
}

static void ZNRARParseImage(uint32_t imageIndex,
                            NSMutableArray<ZNRuntimeMethodActionRecord *> *out,
                            NSMutableSet<NSString *> *dedupe,
                            NSMutableArray<NSString *> *diagnostics) {
    const struct mach_header *raw = _dyld_get_image_header(imageIndex);
    if (!raw || raw->magic != MH_MAGIC_64) return;
    const struct mach_header_64 *mh = (const struct mach_header_64 *)raw;
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    const char *cpath = _dyld_get_image_name(imageIndex);
    NSString *path = cpath ? [NSString stringWithUTF8String:cpath] : @"";

    const uint8_t *cursor = (const uint8_t *)(mh + 1);
    const uint8_t *limit = cursor + mh->sizeofcmds;
    if (mh->ncmds > 4096 || mh->sizeofcmds > 16 * 1024 * 1024) return;

    const struct section_64 *zndata = NULL;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > limit) return;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) return;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if (strncmp(seg->segname, "__ZNDATA", 16) == 0) {
                uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
                if (lc->cmdsize < sizeof(*seg) + sectionBytes) return;
                const struct section_64 *sections = (const struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    if (strncmp(sections[j].sectname, "__zndata", 16) == 0) {
                        zndata = &sections[j];
                        break;
                    }
                }
            }
        }
        if (zndata) break;
        cursor += lc->cmdsize;
    }
    if (!zndata || zndata->size < sizeof(ZN44StaticHeader)) return;

    __int128 runtimeAddress = (__int128)zndata->addr + (__int128)slide;
    if (runtimeAddress <= 0 || runtimeAddress > UINTPTR_MAX) return;
    const uint8_t *section = (const uint8_t *)(uintptr_t)runtimeAddress;
    uint64_t sectionSize = zndata->size;

    const ZN44StaticHeader *staticHeader = (const ZN44StaticHeader *)section;
    if (staticHeader->magic0 != ZN44_STATIC_MAGIC0 || staticHeader->magic1 != ZN44_STATIC_MAGIC1 ||
        staticHeader->entrySize != sizeof(ZN44StaticEntry) || staticHeader->count > ZN44_STATIC_MAX_ENTRIES) return;

    uint64_t staticBytes = sizeof(ZN44StaticHeader) + (uint64_t)staticHeader->count * staticHeader->entrySize;
    staticBytes = ZNRARAlign8(staticBytes);
    if (staticBytes > sectionSize || sectionSize - staticBytes < sizeof(ZNRuntimeActionHeader)) return;

    const uint8_t *table = section + staticBytes;
    const ZNRuntimeActionHeader *header = (const ZNRuntimeActionHeader *)table;
    if (header->magic != ZN_RUNTIME_ACTION_MAGIC || header->version != ZN_RUNTIME_ACTION_VERSION ||
        header->entrySize != sizeof(ZNRuntimeMethodCallEntry) || header->count > ZN_RUNTIME_ACTION_MAX_ENTRIES) return;
    if (header->totalSize < sizeof(*header) || header->totalSize > sectionSize - staticBytes) return;

    uint64_t entryBytes = (uint64_t)header->count * header->entrySize;
    uint64_t fixedEnd = sizeof(*header) + entryBytes;
    if (fixedEnd > header->totalSize || header->stringPoolOffset < fixedEnd ||
        header->stringPoolOffset > header->totalSize || header->stringPoolSize > header->totalSize - header->stringPoolOffset) return;

    const ZNRuntimeMethodCallEntry *entries = (const ZNRuntimeMethodCallEntry *)(table + sizeof(*header));
    NSUInteger accepted = 0;
    for (uint32_t i = 0; i < header->count; i++) {
        const ZNRuntimeMethodCallEntry *entry = &entries[i];
        if (entry->kind != ZNRuntimeActionKindIL2CPPMethodCall) continue;
        NSString *title = ZNRARReadString(table, header, entry->titleOffset);
        NSString *group = ZNRARReadString(table, header, entry->groupOffset);
        NSString *assembly = ZNRARReadString(table, header, entry->assemblyOffset);
        NSString *namespaceName = ZNRARReadString(table, header, entry->namespaceOffset);
        NSString *className = ZNRARReadString(table, header, entry->classOffset);
        NSString *methodName = ZNRARReadString(table, header, entry->methodOffset);
        if (!title || !group || !assembly || !namespaceName || !className || !methodName ||
            !assembly.length || !className.length || !methodName.length) continue;

        ZNRuntimeMethodActionRecord *record = [ZNRuntimeMethodActionRecord new];
        record.actionID = entry->actionID;
        record.title = title.length ? title : methodName;
        record.group = group.length ? group : @"Runtime Methods";
        record.assembly = assembly;
        record.namespaceName = namespaceName;
        record.className = className;
        record.methodName = methodName;
        record.argumentCount = entry->argumentCount;
        record.sourceImage = path ?: @"";
        NSString *key = [NSString stringWithFormat:@"%u|%@", record.actionID, record.canonicalIdentity];
        if ([dedupe containsObject:key]) continue;
        [dedupe addObject:key];
        [out addObject:record];
        accepted++;
    }
    if (accepted) {
        [diagnostics addObject:[NSString stringWithFormat:@"%@：Runtime Actions %lu", path.lastPathComponent ?: @"image", (unsigned long)accepted]];
    }
}

@interface ZNRuntimeActionRuntime ()
@property(nonatomic,copy,readwrite) NSArray<ZNRuntimeMethodActionRecord *> *records;
@property(nonatomic,copy,readwrite) NSString *lastStatus;
@property(nonatomic,copy) NSArray<NSString *> *lastDiagnostics;
@end

@implementation ZNRuntimeActionRuntime

+ (instancetype)sharedRuntime {
    static ZNRuntimeActionRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ runtime = [ZNRuntimeActionRuntime new]; });
    return runtime;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _records = @[];
    _lastDiagnostics = @[];
    _lastStatus = @"尚未扫描 Runtime Method Call";
    return self;
}

- (void)refresh {
    NSMutableArray<ZNRuntimeMethodActionRecord *> *found = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    NSMutableArray<NSString *> *diagnostics = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) ZNRARParseImage(i, found, dedupe, diagnostics);
    self.records = [found copy];
    self.lastDiagnostics = [diagnostics copy];
    self.lastStatus = [NSString stringWithFormat:@"Runtime Method Call：%lu actions", (unsigned long)found.count];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] refresh -> %lu actions", (unsigned long)found.count]];
}

- (BOOL)executeRecord:(ZNRuntimeMethodActionRecord *)record error:(NSString **)error {
    if (!record) {
        if (error) *error = @"Runtime Method Call record 为空";
        return NO;
    }
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.actionID = record.actionID;
    action.title = record.title;
    action.group = record.group;
    action.assembly = record.assembly;
    action.namespaceName = record.namespaceName;
    action.className = record.className;
    action.methodName = record.methodName;
    action.argumentCount = record.argumentCount;

    NSString *invokeError = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&invokeError];
    if (!result) {
        self.lastStatus = invokeError ?: @"Runtime Method Call 执行失败";
        if (error) *error = self.lastStatus;
        return NO;
    }
    self.lastStatus = [NSString stringWithFormat:@"%@：SUCCESS", record.title.length ? record.title : record.methodName];
    return YES;
}

- (NSArray<NSString *> *)diagnosticLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:self.lastStatus ?: @""];
    [lines addObjectsFromArray:self.lastDiagnostics ?: @[]];
    NSDictionary *cap = [[ZNIL2CPPInvokeEngine sharedEngine] capabilities];
    [lines addObject:[NSString stringWithFormat:@"Invoke resolver=%@ runtimeInvoke=%@ methodFlags=%@ zeroArgStatic=%@",
                      [cap[@"resolver"] boolValue] ? @"YES" : @"NO",
                      [cap[@"runtimeInvoke"] boolValue] ? @"YES" : @"NO",
                      [cap[@"methodGetFlags"] boolValue] ? @"YES" : @"NO",
                      [cap[@"zeroArgStatic"] boolValue] ? @"YES" : @"NO"]];
    for (ZNRuntimeMethodActionRecord *record in self.records) {
        [lines addObject:[NSString stringWithFormat:@"[%u] %@ · %@ · source=%@",
                          record.actionID,
                          record.title ?: @"",
                          record.canonicalIdentity,
                          record.sourceImage.lastPathComponent ?: @""]];
    }
    return lines;
}

@end
