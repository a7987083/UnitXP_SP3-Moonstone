#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#import <dlfcn.h>
#import <errno.h>
#import <limits.h>
#import <stdint.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>

#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPMethodFinderSearchV3.h"
#import "ZNIL2CPPResolver.h"
#import "ZNPatchCore.h"
#import "ZNTheme.h"

// v0.5.8-dev Method Finder V3 Milestone 2.
//
// M1 remains frozen on its own branch. M2 adds:
//   - asynchronous search so class scanning never blocks the menu thread;
//   - cooperative cancellation and shard progress;
//   - broad bare-method search (exact > prefix > suffix > contains);
//   - a compact persistent IL2CPP metadata index keyed by UnityFramework UUID
//     + file size. Runtime VA / MethodInfo / Method Pointer are NEVER persisted.
//
// Structured expressions and Named Offset keep their exact semantics.

static const NSUInteger kZN61ShardClasses = 12000;
static const NSUInteger kZN61HardLimit = 64;
static const NSUInteger kZN61IndexVersion = 1;
static const NSUInteger kZN61MaxExecRanges = 16;
static const NSInteger kZN61SearchFieldTag = 603001;

typedef void *(*ZN61DomainGetFn)(void);
typedef const void **(*ZN61DomainGetAssembliesFn)(const void *, size_t *);
typedef const void *(*ZN61AssemblyGetImageFn)(const void *);
typedef const char *(*ZN61ImageGetNameFn)(const void *);
typedef size_t (*ZN61ImageGetClassCountFn)(const void *);
typedef void *(*ZN61ImageGetClassFn)(const void *, size_t);
typedef const char *(*ZN61ClassGetNameFn)(void *);
typedef const char *(*ZN61ClassGetNamespaceFn)(void *);
typedef const void *(*ZN61ClassGetMethodsFn)(void *, void **);
typedef const char *(*ZN61MethodGetNameFn)(const void *);
typedef uint32_t (*ZN61MethodGetParamCountFn)(const void *);
typedef void *(*ZN61MethodGetPointerFn)(const void *);

typedef struct {
    void *handle;
    const struct mach_header_64 *header;
    char unityPath[PATH_MAX];
    uintptr_t runtimeBase;
    uint64_t preferredBase;
    uintptr_t execStarts[kZN61MaxExecRanges];
    uintptr_t execEnds[kZN61MaxExecRanges];
    NSUInteger execCount;

    ZN61DomainGetFn domainGet;
    ZN61DomainGetAssembliesFn domainGetAssemblies;
    ZN61AssemblyGetImageFn assemblyGetImage;
    ZN61ImageGetNameFn imageGetName;
    ZN61ImageGetClassCountFn imageGetClassCount;
    ZN61ImageGetClassFn imageGetClass;
    ZN61ClassGetNameFn classGetName;
    ZN61ClassGetNamespaceFn classGetNamespace;
    ZN61ClassGetMethodsFn classGetMethods;
    ZN61MethodGetNameFn methodGetName;
    ZN61MethodGetParamCountFn methodGetParamCount;
    ZN61MethodGetPointerFn methodGetPointer;
} ZN61Runtime;

typedef struct __attribute__((packed)) {
    uint32_t assemblyId;
    uint32_t namespaceId;
    uint32_t classId;
    uint32_t methodId;
    int32_t argumentCount;
    uint32_t reserved;
    uint64_t rva;
} ZN61IndexRecord;
static_assert(sizeof(ZN61IndexRecord) == 32, "ZN61IndexRecord must stay compact/stable");

typedef NS_ENUM(NSInteger, ZN61MatchRank) {
    ZN61MatchExact = 0,
    ZN61MatchPrefix = 1,
    ZN61MatchSuffix = 2,
    ZN61MatchContains = 3,
    ZN61MatchNone = 99,
};

typedef void (^ZN61ProgressBlock)(NSDictionary<NSString *, id> *progress);
typedef void (^ZN61CompletionBlock)(NSArray<NSDictionary<NSString *, id> *> * _Nullable results,
                                    NSDictionary<NSString *, id> * _Nullable stats,
                                    NSString * _Nullable error);

static NSString *ZN61Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN61String(const char *value) {
    if (!value) return @"";
    return [NSString stringWithUTF8String:value] ?: @"";
}

static NSString *ZN61NormalizedAssembly(NSString *value) {
    NSString *s = ZN61Trim(value).lowercaseString;
    return [s hasSuffix:@".dll"] ? [s substringToIndex:s.length - 4] : s;
}

static BOOL ZN61AssemblyPreferred(NSString *assembly) {
    return [ZN61NormalizedAssembly(assembly) isEqualToString:@"assembly-csharp"];
}

static BOOL ZN61IsExecutable(const ZN61Runtime *runtime, uintptr_t address) {
    if (!address) return NO;
    for (NSUInteger i = 0; i < runtime->execCount; i++) {
        if (address >= runtime->execStarts[i] && address < runtime->execEnds[i]) return YES;
    }
    return NO;
}

static void *ZN61ResolveSymbol(ZN61Runtime *runtime, const char *name) {
    void *p = runtime->handle ? dlsym(runtime->handle, name) : NULL;
    if (!p) p = dlsym(RTLD_DEFAULT, name);
    return p;
}

static BOOL ZN61LoadRuntime(ZN61Runtime *runtime, NSString **error) {
    memset(runtime, 0, sizeof(*runtime));
    const struct mach_header_64 *unityHeader = NULL;
    const char *unityPath = NULL;

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        NSString *leaf = path.lastPathComponent;
        if ([leaf isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework"
                         options:NSCaseInsensitiveSearch].location != NSNotFound) {
            unityPath = raw;
            unityHeader = (const struct mach_header_64 *)_dyld_get_image_header(i);
            break;
        }
    }

    if (!unityHeader || unityHeader->magic != MH_MAGIC_64 || !unityPath) {
        if (error) *error = @"UnityFramework 尚未加载或不是 arm64 Mach-O";
        return NO;
    }

    runtime->header = unityHeader;
    runtime->runtimeBase = (uintptr_t)unityHeader;
    snprintf(runtime->unityPath, sizeof(runtime->unityPath), "%s", unityPath);

    BOOL textFound = NO;
    const uint8_t *cursor = (const uint8_t *)(unityHeader + 1);
    const uint8_t *commandsEnd = cursor + unityHeader->sizeofcmds;
    for (uint32_t i = 0; i < unityHeader->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commandsEnd) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > commandsEnd) break;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if (strncmp(seg->segname, SEG_TEXT, 16) == 0) {
                runtime->preferredBase = seg->vmaddr;
                textFound = YES;
                break;
            }
        }
        cursor += lc->cmdsize;
    }
    if (!textFound) {
        if (error) *error = @"UnityFramework Mach-O 缺少 __TEXT segment";
        return NO;
    }

    // A zero __TEXT.vmaddr is valid on the device-verified baseline.
    cursor = (const uint8_t *)(unityHeader + 1);
    for (uint32_t i = 0; i < unityHeader->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commandsEnd) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > commandsEnd) break;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if ((seg->initprot & VM_PROT_EXECUTE) &&
                seg->vmaddr >= runtime->preferredBase &&
                runtime->execCount < kZN61MaxExecRanges) {
                uintptr_t start = runtime->runtimeBase + (uintptr_t)(seg->vmaddr - runtime->preferredBase);
                runtime->execStarts[runtime->execCount] = start;
                runtime->execEnds[runtime->execCount] = start + (uintptr_t)seg->vmsize;
                runtime->execCount++;
            }
        }
        cursor += lc->cmdsize;
    }

    if (!runtime->execCount) {
        if (error) *error = @"UnityFramework 没有可验证的 executable segment";
        return NO;
    }

#ifdef RTLD_NOLOAD
    runtime->handle = dlopen(runtime->unityPath, RTLD_LAZY | RTLD_NOLOAD);
#else
    runtime->handle = dlopen(runtime->unityPath, RTLD_LAZY);
#endif
    runtime->domainGet = (ZN61DomainGetFn)ZN61ResolveSymbol(runtime, "il2cpp_domain_get");
    runtime->domainGetAssemblies = (ZN61DomainGetAssembliesFn)ZN61ResolveSymbol(runtime, "il2cpp_domain_get_assemblies");
    runtime->assemblyGetImage = (ZN61AssemblyGetImageFn)ZN61ResolveSymbol(runtime, "il2cpp_assembly_get_image");
    runtime->imageGetName = (ZN61ImageGetNameFn)ZN61ResolveSymbol(runtime, "il2cpp_image_get_name");
    runtime->imageGetClassCount = (ZN61ImageGetClassCountFn)ZN61ResolveSymbol(runtime, "il2cpp_image_get_class_count");
    runtime->imageGetClass = (ZN61ImageGetClassFn)ZN61ResolveSymbol(runtime, "il2cpp_image_get_class");
    runtime->classGetName = (ZN61ClassGetNameFn)ZN61ResolveSymbol(runtime, "il2cpp_class_get_name");
    runtime->classGetNamespace = (ZN61ClassGetNamespaceFn)ZN61ResolveSymbol(runtime, "il2cpp_class_get_namespace");
    runtime->classGetMethods = (ZN61ClassGetMethodsFn)ZN61ResolveSymbol(runtime, "il2cpp_class_get_methods");
    runtime->methodGetName = (ZN61MethodGetNameFn)ZN61ResolveSymbol(runtime, "il2cpp_method_get_name");
    runtime->methodGetParamCount = (ZN61MethodGetParamCountFn)ZN61ResolveSymbol(runtime, "il2cpp_method_get_param_count");
    runtime->methodGetPointer = (ZN61MethodGetPointerFn)ZN61ResolveSymbol(runtime, "il2cpp_method_get_pointer");

    BOOL core = runtime->domainGet && runtime->domainGetAssemblies &&
                runtime->assemblyGetImage && runtime->imageGetName &&
                runtime->imageGetClassCount && runtime->imageGetClass &&
                runtime->classGetName && runtime->classGetNamespace &&
                runtime->classGetMethods && runtime->methodGetName;
    if (!core) {
        if (error) *error = @"IL2CPP Runtime 缺少 M2 索引所需 API";
        if (runtime->handle) dlclose(runtime->handle);
        memset(runtime, 0, sizeof(*runtime));
        return NO;
    }
    return YES;
}

static void ZN61CloseRuntime(ZN61Runtime *runtime) {
    if (runtime->handle) dlclose(runtime->handle);
    runtime->handle = NULL;
}

static const void **ZN61Assemblies(ZN61Runtime *runtime, size_t *count) {
    if (count) *count = 0;
    void *domain = runtime->domainGet ? runtime->domainGet() : NULL;
    if (!domain || !runtime->domainGetAssemblies) return NULL;
    size_t c = 0;
    const void **assemblies = runtime->domainGetAssemblies(domain, &c);
    if (count) *count = c;
    return assemblies;
}

static uintptr_t ZN61MethodPointer(ZN61Runtime *runtime, const void *method) {
    if (!method) return 0;
    if (runtime->methodGetPointer) {
        uintptr_t p = (uintptr_t)runtime->methodGetPointer(method);
        if (ZN61IsExecutable(runtime, p)) return p;
    }
    uintptr_t words[2] = {0, 0};
    memcpy(words, method, sizeof(words));
    if (ZN61IsExecutable(runtime, words[0])) return words[0];
    if (ZN61IsExecutable(runtime, words[1])) return words[1];
    return 0;
}

static NSString *ZN61UUIDString(const struct mach_header_64 *header) {
    if (!header || header->magic != MH_MAGIC_64) return @"";
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > end) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > end) break;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uc = (const struct uuid_command *)cursor;
            const unsigned char *u = uc->uuid;
            return [NSString stringWithFormat:
                    @"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                    u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],
                    u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15]];
        }
        cursor += lc->cmdsize;
    }
    return @"";
}

static NSString *ZN61Fingerprint(ZN61Runtime *runtime) {
    NSString *uuid = ZN61UUIDString(runtime->header);
    NSString *path = [NSString stringWithUTF8String:runtime->unityPath] ?: @"";
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] ?: @{};
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    if (uuid.length) return [NSString stringWithFormat:@"%@-%llu", uuid, size];

    NSDate *date = attrs[NSFileModificationDate];
    long long stamp = date ? (long long)date.timeIntervalSince1970 : 0;
    return [NSString stringWithFormat:@"fallback-%llu-%lld", size, stamp];
}

static NSString *ZN61IndexDirectory(void) {
    NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (!cache.length) cache = NSTemporaryDirectory();
    return [[cache stringByAppendingPathComponent:@"ZonoPatch"] stringByAppendingPathComponent:@"IL2CPPMethodIndex"];
}

static NSString *ZN61IndexPath(NSString *fingerprint) {
    NSString *safe = [[fingerprint ?: @"unknown" stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                      stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return [[ZN61IndexDirectory() stringByAppendingPathComponent:safe] stringByAppendingPathExtension:@"bplist"];
}

static NSDictionary *ZN61LoadIndex(NSString *fingerprint) {
    NSData *data = [NSData dataWithContentsOfFile:ZN61IndexPath(fingerprint)];
    if (!data.length) return nil;
    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:&error];
    if (![plist isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *index = (NSDictionary *)plist;
    if ([index[@"version"] unsignedIntegerValue] != kZN61IndexVersion) return nil;
    if (![index[@"fingerprint"] isEqualToString:fingerprint]) return nil;
    NSData *records = index[@"records"];
    if (![records isKindOfClass:NSData.class] || (records.length % sizeof(ZN61IndexRecord)) != 0) return nil;
    if (![index[@"assemblies"] isKindOfClass:NSArray.class] ||
        ![index[@"namespaces"] isKindOfClass:NSArray.class] ||
        ![index[@"classes"] isKindOfClass:NSArray.class] ||
        ![index[@"methods"] isKindOfClass:NSArray.class]) return nil;
    return index;
}

static BOOL ZN61SaveIndex(NSDictionary *index, NSString *fingerprint, NSString **errorText) {
    NSError *error = nil;
    NSString *dir = ZN61IndexDirectory();
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        if (errorText) *errorText = error.localizedDescription ?: @"无法创建索引目录";
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:index
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&error];
    if (!data.length || error) {
        if (errorText) *errorText = error.localizedDescription ?: @"索引序列化失败";
        return NO;
    }
    if (![data writeToFile:ZN61IndexPath(fingerprint) options:NSDataWritingAtomic error:&error]) {
        if (errorText) *errorText = error.localizedDescription ?: @"索引写入失败";
        return NO;
    }
    return YES;
}

static uint32_t ZN61Intern(NSMutableArray<NSString *> *table,
                           NSMutableDictionary<NSString *, NSNumber *> *map,
                           NSString *value) {
    NSString *s = value ?: @"";
    NSNumber *known = map[s];
    if (known) return known.unsignedIntValue;
    uint32_t idx = (uint32_t)table.count;
    [table addObject:s];
    map[s] = @(idx);
    return idx;
}

static ZN61MatchRank ZN61RankForMethod(NSString *method, NSString *query) {
    NSString *m = ZN61Trim(method);
    NSString *q = ZN61Trim(query);
    if (!m.length || !q.length) return ZN61MatchNone;
    if ([m caseInsensitiveCompare:q] == NSOrderedSame) return ZN61MatchExact;
    if ([m rangeOfString:q options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound)
        return ZN61MatchPrefix;
    if ([m rangeOfString:q options:(NSCaseInsensitiveSearch | NSBackwardsSearch | NSAnchoredSearch)].location != NSNotFound)
        return ZN61MatchSuffix;
    if ([m rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound)
        return ZN61MatchContains;
    return ZN61MatchNone;
}

static NSString *ZN61RankText(ZN61MatchRank rank) {
    switch (rank) {
        case ZN61MatchExact: return @"exact";
        case ZN61MatchPrefix: return @"prefix";
        case ZN61MatchSuffix: return @"suffix";
        case ZN61MatchContains: return @"contains";
        default: return @"none";
    }
}

static NSString *ZN61Canonical(NSString *assembly,
                               NSString *namespaceName,
                               NSString *className,
                               NSString *methodName,
                               NSInteger argc) {
    NSString *classPath = namespaceName.length
        ? [NSString stringWithFormat:@"%@.%@", namespaceName, className ?: @""]
        : (className ?: @"");
    return [NSString stringWithFormat:@"%@!%@::%@%@",
            assembly.length ? assembly : @"?",
            classPath.length ? classPath : @"?",
            methodName.length ? methodName : @"?",
            argc >= 0 ? [NSString stringWithFormat:@"/%ld", (long)argc] : @""];
}

static NSMutableSet<NSString *> *ZN61CancelledTokens(void) {
    static NSMutableSet<NSString *> *tokens;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ tokens = [NSMutableSet set]; });
    return tokens;
}

static void ZN61Cancel(NSString *token) {
    if (!token.length) return;
    @synchronized (ZN61CancelledTokens()) {
        [ZN61CancelledTokens() addObject:token];
    }
}

static BOOL ZN61IsCancelled(NSString *token) {
    if (!token.length) return NO;
    @synchronized (ZN61CancelledTokens()) {
        return [ZN61CancelledTokens() containsObject:token];
    }
}

static void ZN61ClearCancelled(NSString *token) {
    if (!token.length) return;
    @synchronized (ZN61CancelledTokens()) {
        [ZN61CancelledTokens() removeObject:token];
    }
}

static void ZN61EmitProgress(ZN61ProgressBlock block, NSDictionary *progress) {
    if (!block) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(progress ?: @{});
    });
}

static NSComparisonResult ZN61HitCompare(NSDictionary *a, NSDictionary *b) {
    NSInteger ra = [a[@"rank"] integerValue], rb = [b[@"rank"] integerValue];
    if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
    BOOL pa = [a[@"assemblyPreferred"] boolValue], pb = [b[@"assemblyPreferred"] boolValue];
    if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
    NSUInteger la = [a[@"method"] length], lb = [b[@"method"] length];
    if (la != lb) return la < lb ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult byName = [a[@"method"] caseInsensitiveCompare:b[@"method"]];
    if (byName != NSOrderedSame) return byName;
    return [a[@"canonical"] caseInsensitiveCompare:b[@"canonical"]];
}

static void ZN61AddBoundedHit(NSMutableArray<NSDictionary *> *bucket,
                              NSDictionary *hit,
                              NSUInteger limit) {
    [bucket addObject:hit];
    if (bucket.count <= limit) return;
    [bucket sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return ZN61HitCompare(a, b);
    }];
    [bucket removeLastObject];
}

static NSArray<NSDictionary *> *ZN61FlattenBuckets(NSArray<NSMutableArray<NSDictionary *> *> *buckets,
                                                   NSUInteger limit) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:limit];
    for (NSMutableArray<NSDictionary *> *bucket in buckets) {
        [bucket sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return ZN61HitCompare(a, b);
        }];
        for (NSDictionary *hit in bucket) {
            [out addObject:hit];
            if (out.count >= limit) return out;
        }
    }
    return out;
}

static NSDictionary *ZN61HitFromRecord(ZN61IndexRecord record,
                                       NSArray *assemblies,
                                       NSArray *namespaces,
                                       NSArray *classes,
                                       NSArray *methods,
                                       ZN61MatchRank rank) {
    if (record.assemblyId >= assemblies.count ||
        record.namespaceId >= namespaces.count ||
        record.classId >= classes.count ||
        record.methodId >= methods.count) return nil;
    NSString *assembly = assemblies[record.assemblyId];
    NSString *ns = namespaces[record.namespaceId];
    NSString *cls = classes[record.classId];
    NSString *method = methods[record.methodId];
    return @{
        @"assembly": assembly ?: @"",
        @"namespace": ns ?: @"",
        @"class": cls ?: @"",
        @"method": method ?: @"",
        @"argumentCount": @(record.argumentCount),
        @"rva": @(record.rva),
        @"canonical": ZN61Canonical(assembly, ns, cls, method, record.argumentCount),
        @"rank": @(rank),
        @"matchReason": ZN61RankText(rank),
        @"assemblyPreferred": @(ZN61AssemblyPreferred(assembly)),
    };
}

static NSArray<NSDictionary *> *ZN61QueryIndex(NSDictionary *index,
                                               NSString *methodQuery,
                                               BOOL argumentSpecified,
                                               NSInteger wantedArguments,
                                               BOOL reverse,
                                               uint64_t reverseRVA,
                                               NSUInteger limit) {
    NSArray *assemblies = index[@"assemblies"];
    NSArray *namespaces = index[@"namespaces"];
    NSArray *classes = index[@"classes"];
    NSArray *methods = index[@"methods"];
    NSData *recordsData = index[@"records"];
    const ZN61IndexRecord *records = (const ZN61IndexRecord *)recordsData.bytes;
    NSUInteger count = recordsData.length / sizeof(ZN61IndexRecord);

    NSMutableArray<NSDictionary *> *b0 = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *b1 = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *b2 = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *b3 = [NSMutableArray array];
    NSArray *buckets = @[b0,b1,b2,b3];

    for (NSUInteger i = 0; i < count; i++) {
        ZN61IndexRecord r = records[i];
        if (argumentSpecified && r.argumentCount != wantedArguments) continue;
        ZN61MatchRank rank = ZN61MatchNone;
        if (reverse) {
            if (!r.rva || r.rva != reverseRVA) continue;
            rank = ZN61MatchExact;
        } else {
            if (r.methodId >= methods.count) continue;
            rank = ZN61RankForMethod(methods[r.methodId], methodQuery);
            if (rank == ZN61MatchNone) continue;
        }
        NSDictionary *hit = ZN61HitFromRecord(r, assemblies, namespaces, classes, methods, rank);
        if (!hit) continue;
        ZN61AddBoundedHit(buckets[(NSUInteger)rank], hit, limit);
    }
    return ZN61FlattenBuckets(buckets, limit);
}

static NSArray<NSDictionary *> *ZN61ResolveHits(NSArray<NSDictionary *> *hits,
                                                NSUInteger limit,
                                                NSString *mode,
                                                NSDictionary *stats,
                                                NSString *token) {
    NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:MIN(limit, hits.count)];
    ZNIL2CPPHybridFinder *finder = [ZNIL2CPPHybridFinder sharedFinder];
    for (NSDictionary *hit in hits) {
        if (ZN61IsCancelled(token)) break;
        NSString *error = nil;
        NSArray *candidates = [finder zn60_searchCandidates:hit[@"canonical"] limit:2 error:&error];
        for (NSDictionary *candidate in candidates ?: @[]) {
            NSMutableDictionary *item = [candidate mutableCopy];
            item[@"searchMode"] = mode ?: @"m2";
            item[@"searchStats"] = stats ?: @{};
            item[@"matchRank"] = hit[@"rank"] ?: @0;
            item[@"matchReason"] = hit[@"matchReason"] ?: @"exact";
            item[@"indexRVA"] = hit[@"rva"] ?: @0;
            [resolved addObject:[item copy]];
            if (resolved.count >= limit) return resolved;
        }
    }
    return resolved;
}

@interface ZNMethodFinderM2Engine : NSObject
@property(nonatomic,copy) NSString *indexStatusText;
+ (instancetype)shared;
- (NSString *)startSearch:(NSString *)query
                    limit:(NSUInteger)limit
                 progress:(ZN61ProgressBlock)progress
               completion:(ZN61CompletionBlock)completion;
- (void)cancel:(NSString *)token;
@end

@implementation ZNMethodFinderM2Engine

+ (instancetype)shared {
    static ZNMethodFinderM2Engine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [ZNMethodFinderM2Engine new];
        engine.indexStatusText = @"本地索引：待检测（首次宽泛搜索自动建立）";
    });
    return engine;
}

- (void)cancel:(NSString *)token {
    ZN61Cancel(token);
}

- (NSString *)startSearch:(NSString *)query
                    limit:(NSUInteger)limit
                 progress:(ZN61ProgressBlock)progress
               completion:(ZN61CompletionBlock)completion {
    NSString *token = [NSUUID UUID].UUIDString;
    NSString *searchQuery = ZN61Trim(query);
    NSUInteger resultLimit = MAX((NSUInteger)1, MIN(limit ?: 32, kZN61HardLimit));

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        if (!searchQuery.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"请输入搜索内容"); });
            return;
        }

        uint64_t reverseRVA = 0;
        NSString *lower = searchQuery.lowercaseString;
        NSString *rvaText = searchQuery;
        if ([lower hasPrefix:@"rva:"]) rvaText = ZN61Trim([searchQuery substringFromIndex:4]);
        BOOL reverse = NO;
        if ([rvaText.lowercaseString hasPrefix:@"0x"]) {
            const char *c = rvaText.UTF8String;
            char *end = NULL;
            errno = 0;
            unsigned long long value = strtoull(c, &end, 0);
            if (!errno && end != c && (!end || !*end)) {
                reverse = YES;
                reverseRVA = (uint64_t)value;
            }
        }

        NSString *parseError = nil;
        NSDictionary *parsed = reverse ? nil : [ZNIL2CPPResolver parseNamedOffsetExpression:searchQuery error:&parseError];
        if (!reverse && !parsed) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, parseError ?: @"搜索表达式无效"); });
            return;
        }

        NSString *assembly = parsed[@"assembly"] ?: @"";
        NSString *className = parsed[@"class"] ?: @"";
        BOOL namespaceSpecified = [parsed[@"namespaceSpecified"] boolValue];
        BOOL argumentSpecified = [parsed[@"argumentSpecified"] boolValue];
        NSInteger wantedArguments = argumentSpecified ? [parsed[@"argumentCount"] integerValue] : -1;
        int64_t delta = [parsed[@"delta"] longLongValue];
        NSString *methodQuery = parsed[@"method"] ?: @"";
        BOOL broad = !reverse && !assembly.length && !className.length && !namespaceSpecified && delta == 0;

        // Structured queries preserve M1 exact semantics but execute off-main.
        if (!broad && !reverse) {
            ZN61EmitProgress(progress, @{@"phase":@"exact", @"message":@"正在执行精确查询…"});
            if (ZN61IsCancelled(token)) {
                ZN61ClearCancelled(token);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"搜索已取消"); });
                return;
            }
            NSString *error = nil;
            NSArray *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:searchQuery
                                                                                 limit:resultLimit
                                                                                 error:&error];
            if (ZN61IsCancelled(token)) {
                ZN61ClearCancelled(token);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"搜索已取消"); });
                return;
            }
            NSDictionary *stats = @{
                @"mode":@"m2-async-exact",
                @"indexSource":@"not-used",
                @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
                @"candidateCount":@(items.count),
                @"async":@YES
            };
            NSMutableArray *annotated = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *candidate in items ?: @[]) {
                NSMutableDictionary *item = [candidate mutableCopy];
                item[@"searchMode"] = @"m2-async-exact";
                item[@"searchStats"] = stats;
                item[@"matchRank"] = @0;
                item[@"matchReason"] = @"exact";
                [annotated addObject:[item copy]];
            }
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(annotated.count ? annotated : nil, stats, annotated.count ? nil : (error ?: @"没有搜索结果"));
            });
            return;
        }

        ZN61Runtime runtime;
        NSString *runtimeError = nil;
        if (!ZN61LoadRuntime(&runtime, &runtimeError)) {
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, runtimeError ?: @"IL2CPP Runtime 不可用"); });
            return;
        }
        NSString *fingerprint = ZN61Fingerprint(&runtime);
        NSDictionary *index = ZN61LoadIndex(fingerprint);

        // RVA reverse can use the local index when present; otherwise preserve
        // the already-device-verified V3 reverse path instead of forcing a full
        // index build just for one address.
        if (reverse && !index) {
            ZN61CloseRuntime(&runtime);
            self.indexStatusText = @"本地索引：当前版本尚未建立";
            ZN61EmitProgress(progress, @{@"phase":@"reverse", @"message":@"本地索引未命中，使用已验证 RVA 反查…"});
            NSString *error = nil;
            NSArray *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:searchQuery
                                                                                 limit:resultLimit
                                                                                 error:&error];
            NSDictionary *stats = @{
                @"mode":@"m2-reverse-fallback",
                @"indexSource":@"miss",
                @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
                @"candidateCount":@(items.count),
                @"async":@YES
            };
            NSMutableArray *annotated = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *candidate in items ?: @[]) {
                NSMutableDictionary *item = [candidate mutableCopy];
                item[@"searchMode"] = @"m2-reverse-fallback";
                item[@"searchStats"] = stats;
                item[@"matchRank"] = @0;
                item[@"matchReason"] = @"rva";
                [annotated addObject:[item copy]];
            }
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(annotated.count ? annotated : nil, stats, annotated.count ? nil : (error ?: @"没有搜索结果"));
            });
            return;
        }

        if (index) {
            ZN61CloseRuntime(&runtime);
            self.indexStatusText = [NSString stringWithFormat:@"本地索引：已命中 · %@ records",
                                    index[@"recordCount"] ?: @0];
            ZN61EmitProgress(progress, @{@"phase":@"index-hit", @"message":@"正在查询本地 IL2CPP 索引…"});
            NSArray *hits = ZN61QueryIndex(index, methodQuery, argumentSpecified, wantedArguments,
                                           reverse, reverseRVA, resultLimit);
            NSDictionary *stats = @{
                @"mode": reverse ? @"m2-rva-index" : @"m2-wide-index",
                @"indexSource":@"hit",
                @"indexFingerprint":fingerprint ?: @"",
                @"indexRecordCount":index[@"recordCount"] ?: @0,
                @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
                @"candidateCount":@(hits.count),
                @"async":@YES,
                @"wideSearch":@(!reverse)
            };
            ZN61EmitProgress(progress, @{@"phase":@"resolving",
                                        @"message":[NSString stringWithFormat:@"索引命中 %lu 条，正在恢复 Runtime 地址…",
                                                   (unsigned long)hits.count]});
            NSArray *resolved = ZN61ResolveHits(hits, resultLimit,
                                                reverse ? @"m2-rva-index" : @"m2-wide-index",
                                                stats, token);
            BOOL cancelled = ZN61IsCancelled(token);
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (cancelled) completion(nil, stats, @"搜索已取消");
                else completion(resolved.count ? resolved : nil, stats,
                                resolved.count ? nil : @"索引有匹配记录，但当前 Runtime 无法解析对应方法");
            });
            return;
        }

        // No index: broad search builds the complete compact index in the
        // background while simultaneously collecting ranked matches.
        self.indexStatusText = @"本地索引：正在建立…";
        size_t assemblyCount = 0;
        const void **assemblies = ZN61Assemblies(&runtime, &assemblyCount);
        if (!assemblies || !assemblyCount) {
            ZN61CloseRuntime(&runtime);
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"IL2CPP Domain 尚无可用程序集"); });
            return;
        }

        NSUInteger totalClasses = 0;
        for (size_t a = 0; a < assemblyCount; a++) {
            const void *image = runtime.assemblyGetImage(assemblies[a]);
            if (image) totalClasses += runtime.imageGetClassCount(image);
        }

        NSMutableArray<NSString *> *assemblyTable = [NSMutableArray array];
        NSMutableArray<NSString *> *namespaceTable = [NSMutableArray array];
        NSMutableArray<NSString *> *classTable = [NSMutableArray array];
        NSMutableArray<NSString *> *methodTable = [NSMutableArray array];
        NSMutableDictionary *assemblyMap = [NSMutableDictionary dictionary];
        NSMutableDictionary *namespaceMap = [NSMutableDictionary dictionary];
        NSMutableDictionary *classMap = [NSMutableDictionary dictionary];
        NSMutableDictionary *methodMap = [NSMutableDictionary dictionary];
        NSMutableData *recordData = [NSMutableData data];

        NSMutableArray *b0 = [NSMutableArray array];
        NSMutableArray *b1 = [NSMutableArray array];
        NSMutableArray *b2 = [NSMutableArray array];
        NSMutableArray *b3 = [NSMutableArray array];
        NSArray *buckets = @[b0,b1,b2,b3];

        NSUInteger classesDone = 0, shardsDone = 0, methodsDone = 0;
        BOOL cancelled = NO;
        for (NSUInteger pass = 0; pass < 2 && !cancelled; pass++) {
            for (size_t a = 0; a < assemblyCount && !cancelled; a++) {
                const void *image = runtime.assemblyGetImage(assemblies[a]);
                if (!image) continue;
                NSString *assemblyName = ZN61String(runtime.imageGetName(image));
                BOOL preferred = ZN61AssemblyPreferred(assemblyName);
                if ((pass == 0 && !preferred) || (pass == 1 && preferred)) continue;

                size_t classCount = runtime.imageGetClassCount(image);
                for (size_t shardStart = 0; shardStart < classCount && !cancelled; shardStart += kZN61ShardClasses) {
                    size_t shardEnd = MIN(classCount, shardStart + kZN61ShardClasses);
                    for (size_t c = shardStart; c < shardEnd; c++) {
                        if (ZN61IsCancelled(token)) { cancelled = YES; break; }
                        classesDone++;
                        @autoreleasepool {
                            void *klass = runtime.imageGetClass(image, c);
                            if (!klass) continue;
                            NSString *classNameValue = ZN61String(runtime.classGetName(klass));
                            NSString *namespaceName = ZN61String(runtime.classGetNamespace(klass));

                            uint32_t assemblyId = ZN61Intern(assemblyTable, assemblyMap, assemblyName);
                            uint32_t namespaceId = ZN61Intern(namespaceTable, namespaceMap, namespaceName);
                            uint32_t classId = ZN61Intern(classTable, classMap, classNameValue);

                            void *iter = NULL;
                            const void *method = NULL;
                            while ((method = runtime.classGetMethods(klass, &iter)) != NULL) {
                                if ((methodsDone & 0xFF) == 0 && ZN61IsCancelled(token)) {
                                    cancelled = YES;
                                    break;
                                }
                                methodsDone++;
                                NSString *methodName = ZN61String(runtime.methodGetName(method));
                                NSInteger argc = runtime.methodGetParamCount
                                    ? (NSInteger)runtime.methodGetParamCount(method) : -1;
                                uintptr_t pointer = ZN61MethodPointer(&runtime, method);
                                uint64_t rva = (pointer >= runtime.runtimeBase)
                                    ? (uint64_t)(pointer - runtime.runtimeBase) : 0;

                                uint32_t methodId = ZN61Intern(methodTable, methodMap, methodName);
                                ZN61IndexRecord record = {
                                    assemblyId, namespaceId, classId, methodId,
                                    (int32_t)argc, 0, rva
                                };
                                [recordData appendBytes:&record length:sizeof(record)];

                                if (argumentSpecified && argc != wantedArguments) continue;
                                ZN61MatchRank rank = ZN61RankForMethod(methodName, methodQuery);
                                if (rank == ZN61MatchNone) continue;
                                NSDictionary *hit = @{
                                    @"assembly":assemblyName ?: @"",
                                    @"namespace":namespaceName ?: @"",
                                    @"class":classNameValue ?: @"",
                                    @"method":methodName ?: @"",
                                    @"argumentCount":@(argc),
                                    @"rva":@(rva),
                                    @"canonical":ZN61Canonical(assemblyName, namespaceName, classNameValue, methodName, argc),
                                    @"rank":@(rank),
                                    @"matchReason":ZN61RankText(rank),
                                    @"assemblyPreferred":@(preferred)
                                };
                                ZN61AddBoundedHit(buckets[(NSUInteger)rank], hit, resultLimit);
                            }
                        }
                    }
                    shardsDone++;
                    ZN61EmitProgress(progress, @{
                        @"phase":@"index-build",
                        @"classesDone":@(classesDone),
                        @"classesTotal":@(totalClasses),
                        @"shardsDone":@(shardsDone),
                        @"records":@(recordData.length / sizeof(ZN61IndexRecord)),
                        @"message":[NSString stringWithFormat:
                                    @"正在建立索引：%lu/%lu classes · %lu shards · %lu methods",
                                    (unsigned long)classesDone, (unsigned long)totalClasses,
                                    (unsigned long)shardsDone, (unsigned long)methodsDone]
                    });
                    if (!cancelled) [NSThread sleepForTimeInterval:0.001];
                }
            }
        }

        ZN61CloseRuntime(&runtime);
        if (cancelled) {
            self.indexStatusText = @"本地索引：建立已取消（未保存半成品）";
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, @{@"mode":@"m2-wide-build", @"cancelled":@YES}, @"搜索已取消");
            });
            return;
        }

        NSDictionary *newIndex = @{
            @"version":@(kZN61IndexVersion),
            @"fingerprint":fingerprint ?: @"",
            @"builtAt":@([[NSDate date] timeIntervalSince1970]),
            @"recordCount":@(recordData.length / sizeof(ZN61IndexRecord)),
            @"assemblies":assemblyTable,
            @"namespaces":namespaceTable,
            @"classes":classTable,
            @"methods":methodTable,
            @"records":recordData
        };

        ZN61EmitProgress(progress, @{@"phase":@"index-save", @"message":@"扫描完成，正在保存本地索引…"});
        NSString *saveError = nil;
        BOOL saved = ZN61SaveIndex(newIndex, fingerprint, &saveError);
        self.indexStatusText = saved
            ? [NSString stringWithFormat:@"本地索引：已建立 · %@ records", newIndex[@"recordCount"]]
            : [NSString stringWithFormat:@"本地索引：本次可用但保存失败 · %@", saveError ?: @"unknown"];

        NSArray *hits = ZN61FlattenBuckets(buckets, resultLimit);
        NSDictionary *stats = @{
            @"mode":@"m2-wide-build",
            @"indexSource": saved ? @"built-and-saved" : @"built-memory-only",
            @"indexFingerprint":fingerprint ?: @"",
            @"indexRecordCount":newIndex[@"recordCount"] ?: @0,
            @"classesScanned":@(classesDone),
            @"classesTotal":@(totalClasses),
            @"shardsScanned":@(shardsDone),
            @"methodsScanned":@(methodsDone),
            @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
            @"candidateCount":@(hits.count),
            @"async":@YES,
            @"wideSearch":@YES
        };
        ZN61EmitProgress(progress, @{@"phase":@"resolving",
                                    @"message":[NSString stringWithFormat:@"宽泛匹配 %lu 条，正在恢复 Runtime 地址…",
                                               (unsigned long)hits.count]});
        NSArray *resolved = ZN61ResolveHits(hits, resultLimit, @"m2-wide-build", stats, token);
        BOOL wasCancelled = ZN61IsCancelled(token);
        ZN61ClearCancelled(token);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (wasCancelled) completion(nil, stats, @"搜索已取消");
            else completion(resolved.count ? resolved : nil, stats,
                            resolved.count ? nil : [NSString stringWithFormat:@"找不到包含“%@”的方法", methodQuery ?: searchQuery]);
        });
    });

    return token;
}

@end

// ---------- UI integration ----------

static const void *kZN61M2TokenKey = &kZN61M2TokenKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,strong) ZNTheme *theme;
@end

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM2UI)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;

- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items;
- (void)zn60v3_setSelected:(NSDictionary * _Nullable)candidate;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn60v3_setPage:(NSInteger)page;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_startSearch:(id)sender;
- (void)zn60v3_renderSearchAtWidth:(CGFloat)width;

- (void)zn61m2_startSearch:(id)sender;
- (void)zn61m2_renderSearchAtWidth:(CGFloat)width;
- (void)zn61m2_cancelSearch:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM2UI)

- (NSString *)zn61m2_activeToken {
    return objc_getAssociatedObject(self, kZN61M2TokenKey);
}

- (void)zn61m2_setActiveToken:(NSString *)token {
    objc_setAssociatedObject(self, kZN61M2TokenKey, token, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)zn61m2_renderSearchAtWidth:(CGFloat)width {
    // After swizzling this selector calls the original M1 renderer.
    [self zn61m2_renderSearchAtWidth:width];

    for (UIView *card in self.contentView.subviews) {
        for (UIView *child in card.subviews) {
            if (![child isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)child;
            if ([label.text containsString:@"忽略大小写（精确方法名）"]) {
                label.text = @"✓ 裸方法名宽泛搜索    ✓ exact > prefix > suffix > contains";
                label.adjustsFontSizeToFitWidth = YES;
                label.minimumScaleFactor = 0.68;
            } else if ([label.text containsString:@"阶段 1：多候选工作流"]) {
                label.text = @"阶段 2：异步分片 · 进度/取消 · UUID 绑定本地索引";
            }
        }
    }

    NSString *token = [self zn61m2_activeToken];
    if (!token.length) return;

    CGFloat maxY = 0;
    for (UIView *v in self.contentView.subviews) maxY = MAX(maxY, CGRectGetMaxY(v.frame));
    UIView *card = [self cardAtY:maxY + 8 height:48 width:width compact:NO];
    UILabel *label = [self label:@"后台搜索运行中，可随时取消；取消不会保存半成品索引。"
                             size:8.2
                           weight:UIFontWeightRegular
                            color:self.theme.secondaryTextColor];
    label.frame = CGRectMake(13, 8, card.bounds.size.width - 108, 32);
    label.numberOfLines = 2;
    [card addSubview:label];

    UIButton *cancel = [self zn40_button:@"取消"
                                selector:@selector(zn61m2_cancelSearch:)
                                   frame:CGRectMake(card.bounds.size.width - 86, 9, 73, 30)];
    cancel.backgroundColor = [self.theme.controlColor colorWithAlphaComponent:0.85];
    cancel.layer.borderColor = self.theme.borderColor.CGColor;
    [card addSubview:cancel];
    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:CGRectGetMaxY(card.frame) + 8];
}

- (void)zn61m2_startSearch:(id)sender {
    [self.hostWindow endEditing:YES];

    NSString *query = [self zn57mf_query];
    if (!query.length) {
        UITextField *field = (UITextField *)[self.contentView viewWithTag:kZN61SearchFieldTag];
        query = field.text ?: @"";
        [self zn57mf_setQuery:query];
    }
    query = ZN61Trim(query);
    if (!query.length) {
        [self zn60v3_setStatus:@"请输入方法名、Class::Method 或 0xRVA"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    NSString *old = [self zn61m2_activeToken];
    if (old.length) [[ZNMethodFinderM2Engine shared] cancel:old];

    [self zn60v3_setStatus:@"M2 异步搜索已启动…"];
    [self zn60v3_setPage:0];

    __weak typeof(self) weakSelf = self;
    __block NSString *issuedToken = nil;
    issuedToken = [[ZNMethodFinderM2Engine shared] startSearch:query
                                                       limit:[self zn60v3_limit]
                                                    progress:^(NSDictionary *progress) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![[self zn61m2_activeToken] isEqualToString:issuedToken]) return;
        NSString *message = progress[@"message"] ?: @"正在搜索…";
        [self zn60v3_setStatus:message];
        [self renderPage];
    } completion:^(NSArray<NSDictionary<NSString *,id> *> *results,
                   NSDictionary<NSString *,id> *stats,
                   NSString *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![[self zn61m2_activeToken] isEqualToString:issuedToken]) return;
        [self zn61m2_setActiveToken:nil];

        if (!results.count) {
            [self zn60v3_setStatus:error ?: @"没有搜索结果"];
            [[ZNRuntimeLogger sharedLogger] log:
             [NSString stringWithFormat:@"[method-finder-m2] %@ failed: %@",
              query, error ?: @"unknown"]];
            [self zn60v3_setPage:0];
            [self renderPage];
            return;
        }

        [self zn60v3_setCandidates:results];
        [self zn60v3_setSelected:nil];
        NSString *mode = stats[@"mode"] ?: @"m2";
        NSString *source = stats[@"indexSource"] ?: @"not-used";
        [self zn60v3_setStatus:
         [NSString stringWithFormat:@"%@：%lu 个候选 · %@ · index=%@ · %.1fms",
          query, (unsigned long)results.count, mode, source,
          [stats[@"elapsedMs"] doubleValue]]];
        [[ZNRuntimeLogger sharedLogger] log:
         [NSString stringWithFormat:@"[method-finder-m2] %@ -> %lu candidates (%@, index=%@, %.1fms)",
          query, (unsigned long)results.count, mode, source,
          [stats[@"elapsedMs"] doubleValue]]];
        [self zn60v3_setPage:1];
        [self renderPage];
    }];

    [self zn61m2_setActiveToken:issuedToken];
    [self renderPage];
}

- (void)zn61m2_cancelSearch:(id)sender {
    NSString *token = [self zn61m2_activeToken];
    if (!token.length) return;
    [[ZNMethodFinderM2Engine shared] cancel:token];
    [self zn60v3_setStatus:@"正在取消搜索…"];
    [self renderPage];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderM2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method searchOriginal = class_getInstanceMethod(cls, @selector(zn60v3_startSearch:));
        Method searchReplacement = class_getInstanceMethod(cls, @selector(zn61m2_startSearch:));
        if (searchOriginal && searchReplacement) {
            method_exchangeImplementations(searchOriginal, searchReplacement);
        }

        Method renderOriginal = class_getInstanceMethod(cls, @selector(zn60v3_renderSearchAtWidth:));
        Method renderReplacement = class_getInstanceMethod(cls, @selector(zn61m2_renderSearchAtWidth:));
        if (renderOriginal && renderReplacement) {
            method_exchangeImplementations(renderOriginal, renderReplacement);
        }
    });
}
