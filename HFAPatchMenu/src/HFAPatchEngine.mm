#import "HFAPatchEngine.h"
#import "HFAPatchLogger.h"

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <libkern/OSCacheControl.h>

#include <vector>

@interface HFAPatchResolvedTarget : NSObject
@property(nonatomic, assign) const struct mach_header_64 *header;
@property(nonatomic, assign) intptr_t slide;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *architecture;
@end

@implementation HFAPatchResolvedTarget
@end

@interface HFAPatchPreparedWrite : NSObject
@property(nonatomic, assign) vm_address_t address;
@property(nonatomic, copy) NSData *before;
@property(nonatomic, copy) NSData *after;
@property(nonatomic, strong) HFAPatchOperation *operation;
@end

@implementation HFAPatchPreparedWrite
@end

@interface HFAPatchEngine ()
@property(nonatomic, strong, readwrite, nullable) HFAPatchConfiguration *configuration;
@property(nonatomic, copy, readwrite, nullable) NSString *configurationError;
@property(nonatomic, assign, readwrite, getter=isReady) BOOL ready;
@property(nonatomic, strong) NSRecursiveLock *lock;
@end

static NSString *HFAPatchArchitecture(const struct mach_header_64 *header)
{
    if (!header || header->cputype != CPU_TYPE_ARM64) return @"unsupported";
#ifdef CPU_SUBTYPE_ARM64E
    cpu_subtype_t subtype = header->cpusubtype & ~CPU_SUBTYPE_MASK;
    if (subtype == CPU_SUBTYPE_ARM64E) return @"arm64e";
#endif
    return @"arm64";
}

static BOOL HFAPatchSegmentContainsAddress(const HFAPatchResolvedTarget *target,
                                           vm_address_t address,
                                           vm_size_t length)
{
    if (!target.header || length == 0 || UINT64_MAX - address < length) return NO;
    const uint8_t *cursor = (const uint8_t *)(target.header + 1);
    for (uint32_t index = 0; index < target.header->ncmds; index++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(struct load_command)) return NO;
        if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            vm_address_t start = (vm_address_t)(target.slide + segment->vmaddr);
            vm_address_t end = start + (vm_size_t)segment->vmsize;
            if (end >= start && address >= start && address + length >= address && address + length <= end) {
                return YES;
            }
        }
        cursor += command->cmdsize;
    }
    return NO;
}

static BOOL HFAPatchReadMemory(vm_address_t address, NSUInteger length, NSData **data, NSString **error)
{
    if (length == 0) {
        if (error) *error = @"Zero-length memory read";
        return NO;
    }
    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    vm_size_t read = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(),
                                              address,
                                              (vm_size_t)length,
                                              (vm_address_t)buffer.mutableBytes,
                                              &read);
    if (result != KERN_SUCCESS || read != length) {
        if (error) *error = [NSString stringWithFormat:@"Memory read failed at 0x%lX (kr=%d)", (unsigned long)address, result];
        return NO;
    }
    if (data) *data = buffer;
    return YES;
}

static BOOL HFAPatchWriteMemory(vm_address_t address, NSData *data, NSString **error)
{
    if (data.length == 0) {
        if (error) *error = @"Refusing zero-length patch";
        return NO;
    }

    vm_address_t pageStart = address & ~((vm_address_t)vm_page_size - 1);
    vm_address_t endAddress = address + data.length;
    if (endAddress < address) {
        if (error) *error = @"Patch address overflow";
        return NO;
    }
    vm_address_t pageEnd = (endAddress + vm_page_size - 1) & ~((vm_address_t)vm_page_size - 1);

    struct PageProtection {
        vm_address_t address;
        vm_prot_t protection;
    };
    std::vector<PageProtection> pages;

    for (vm_address_t page = pageStart; page < pageEnd; page += vm_page_size) {
        vm_address_t regionAddress = page;
        vm_size_t regionSize = 0;
        vm_region_basic_info_data_64_t info = {};
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        kern_return_t query = vm_region_64(mach_task_self(),
                                           &regionAddress,
                                           &regionSize,
                                           VM_REGION_BASIC_INFO_64,
                                           (vm_region_info_t)&info,
                                           &count,
                                           &object);
        if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
        if (query != KERN_SUCCESS || regionAddress > page || page >= regionAddress + regionSize) {
            if (error) *error = [NSString stringWithFormat:@"Protection query failed at 0x%lX (kr=%d)", (unsigned long)page, query];
            return NO;
        }
        pages.push_back({page, info.protection});
    }

    NSUInteger changedPages = 0;
    for (const PageProtection &page : pages) {
        vm_prot_t writable = page.protection | VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY;
        kern_return_t protect = vm_protect(mach_task_self(),
                                           page.address,
                                           vm_page_size,
                                           FALSE,
                                           writable);
        if (protect != KERN_SUCCESS) {
            for (NSUInteger index = 0; index < changedPages; index++) {
                vm_protect(mach_task_self(), pages[index].address, vm_page_size, FALSE, pages[index].protection);
            }
            if (error) *error = [NSString stringWithFormat:@"Write protection failed at 0x%lX (kr=%d)", (unsigned long)page.address, protect];
            return NO;
        }
        changedPages++;
    }

    memcpy((void *)(uintptr_t)address, data.bytes, data.length);
    sys_icache_invalidate((void *)(uintptr_t)address, data.length);

    BOOL restored = YES;
    for (const PageProtection &page : pages) {
        kern_return_t protect = vm_protect(mach_task_self(),
                                           page.address,
                                           vm_page_size,
                                           FALSE,
                                           page.protection);
        if (protect != KERN_SUCCESS) restored = NO;
    }
    if (!restored) {
        if (error) *error = @"Patch written but original page protection could not be fully restored";
        return NO;
    }
    return YES;
}

@implementation HFAPatchEngine

+ (instancetype)sharedEngine
{
    static HFAPatchEngine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[HFAPatchEngine alloc] initPrivate];
    });
    return engine;
}

- (instancetype)init
{
    return HFAPatchEngine.sharedEngine;
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _lock.name = @"com.hfa.patchmenu.engine";
    }
    return self;
}

- (HFAPatchResolvedTarget *)resolveTarget:(HFAPatchTarget *)target error:(NSString **)error
{
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        const char *rawPath = _dyld_get_image_name(index);
        const struct mach_header *rawHeader = _dyld_get_image_header(index);
        if (!rawPath || !rawHeader || rawHeader->magic != MH_MAGIC_64) continue;

        NSString *path = [NSString stringWithUTF8String:rawPath];
        BOOL matches = [target.image isEqualToString:@"@main"] ? index == 0 :
                       [path.lastPathComponent isEqualToString:target.image];
        if (!matches) continue;

        HFAPatchResolvedTarget *resolved = [[HFAPatchResolvedTarget alloc] init];
        resolved.header = (const struct mach_header_64 *)rawHeader;
        resolved.slide = _dyld_get_image_vmaddr_slide(index);
        resolved.path = path;
        resolved.architecture = HFAPatchArchitecture(resolved.header);
        return resolved;
    }
    if (error) *error = [NSString stringWithFormat:@"Target image not loaded: %@", target.image];
    return nil;
}

- (BOOL)validatePackageIdentity:(HFAPatchConfiguration *)configuration error:(NSString **)error
{
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *bundleID = bundle.bundleIdentifier ?: @"";
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    HFAPatchPackageIdentity *expected = configuration.packageIdentity;

    if (![bundleID isEqualToString:expected.bundleIdentifier]) {
        if (error) *error = [NSString stringWithFormat:@"BundleID mismatch: expected %@, got %@",
                             expected.bundleIdentifier, bundleID];
        return NO;
    }
    if (![shortVersion isEqualToString:expected.shortVersion] ||
        ![buildVersion isEqualToString:expected.buildVersion]) {
        if (error) *error = [NSString stringWithFormat:@"Version mismatch: expected %@ (%@), got %@ (%@)",
                             expected.shortVersion, expected.buildVersion, shortVersion, buildVersion];
        return NO;
    }

    const struct mach_header *mainHeader = _dyld_get_image_header(0);
    NSString *architecture = HFAPatchArchitecture((const struct mach_header_64 *)mainHeader);
    if (![expected.architectures containsObject:architecture]) {
        if (error) *error = [NSString stringWithFormat:@"Architecture %@ is not allowed by this config", architecture];
        return NO;
    }
    return YES;
}

- (BOOL)validateTargetsAndOperations:(HFAPatchConfiguration *)configuration error:(NSString **)error
{
    NSMutableDictionary<NSString *, HFAPatchResolvedTarget *> *resolvedTargets = [NSMutableDictionary dictionary];
    for (NSString *identifier in configuration.targets) {
        NSString *resolveError = nil;
        HFAPatchResolvedTarget *resolved = [self resolveTarget:configuration.targets[identifier] error:&resolveError];
        if (!resolved) {
            if (error) *error = resolveError;
            return NO;
        }
        resolvedTargets[identifier] = resolved;
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSValue *> *> *rangesByTarget = [NSMutableDictionary dictionary];
    for (HFAPatchFeature *feature in configuration.features) {
        for (HFAPatchOperation *operation in feature.patches) {
            HFAPatchResolvedTarget *target = resolvedTargets[operation.targetIdentifier];
            if (UINT64_MAX - (uint64_t)(uintptr_t)target.header < operation.offset) {
                if (error) *error = [NSString stringWithFormat:@"Address overflow in feature %@", feature.identifier];
                return NO;
            }
            vm_address_t address = (vm_address_t)(uintptr_t)target.header + operation.offset;
            if (!HFAPatchSegmentContainsAddress(target, address, operation.originalBytes.length)) {
                if (error) *error = [NSString stringWithFormat:@"Offset 0x%llX is outside %@ for feature %@",
                                     operation.offset, target.path.lastPathComponent, feature.identifier];
                return NO;
            }

            NSMutableArray<NSValue *> *ranges = rangesByTarget[operation.targetIdentifier];
            if (!ranges) {
                ranges = [NSMutableArray array];
                rangesByTarget[operation.targetIdentifier] = ranges;
            }
            NSRange candidate = NSMakeRange((NSUInteger)operation.offset, operation.originalBytes.length);
            for (NSValue *value in ranges) {
                if (NSIntersectionRange(candidate, value.rangeValue).length != 0) {
                    if (error) *error = [NSString stringWithFormat:@"Overlapping patches at %@+0x%llX",
                                         operation.targetIdentifier, operation.offset];
                    return NO;
                }
            }
            [ranges addObject:[NSValue valueWithRange:candidate]];
        }
    }
    return YES;
}

- (NSString *)preferenceKeyForFeature:(HFAPatchFeature *)feature
{
    HFAPatchPackageIdentity *identity = self.configuration.packageIdentity;
    return [NSString stringWithFormat:@"HFAPatchMenu.%@.%@.%@.%@",
            identity.bundleIdentifier, identity.shortVersion, identity.buildVersion, feature.identifier];
}

- (BOOL)reloadConfiguration
{
    [self.lock lock];
    self.ready = NO;
    self.configuration = nil;
    self.configurationError = nil;

    NSError *loadError = nil;
    HFAPatchConfiguration *configuration = [HFAPatchConfiguration loadPreferredConfigurationWithError:&loadError];
    if (!configuration) {
        self.configurationError = loadError.localizedDescription ?: @"Configuration load failed";
        HFAPatchLog(@"[CONFIG-FAIL] %@", self.configurationError);
        [self.lock unlock];
        return NO;
    }

    NSString *validationError = nil;
    if (![self validatePackageIdentity:configuration error:&validationError] ||
        ![self validateTargetsAndOperations:configuration error:&validationError]) {
        self.configuration = configuration;
        self.configurationError = validationError ?: @"Configuration validation failed";
        HFAPatchLog(@"[VALIDATION-FAIL] %@", self.configurationError);
        [self.lock unlock];
        return NO;
    }

    self.configuration = configuration;
    self.ready = YES;
    HFAPatchLog(@"[READY] name=%@ source=%@", configuration.name, configuration.sourcePath);

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (HFAPatchFeature *feature in configuration.features) {
        NSString *key = [self preferenceKeyForFeature:feature];
        id saved = [defaults objectForKey:key];
        BOOL shouldEnable = saved ? [saved boolValue] : feature.defaultEnabled;
        if (!shouldEnable) continue;
        NSString *applyError = nil;
        if (![self setFeature:feature enabled:YES error:&applyError]) {
            HFAPatchLog(@"[AUTO-APPLY-FAIL] id=%@ error=%@", feature.identifier, applyError);
        }
    }

    [self.lock unlock];
    return YES;
}

- (HFAPatchPreparedWrite *)preparedWriteForOperation:(HFAPatchOperation *)operation
                                              enable:(BOOL)enable
                                               error:(NSString **)error
{
    HFAPatchTarget *targetDefinition = self.configuration.targets[operation.targetIdentifier];
    HFAPatchResolvedTarget *target = [self resolveTarget:targetDefinition error:error];
    if (!target) return nil;

    vm_address_t address = (vm_address_t)(uintptr_t)target.header + operation.offset;
    if (!HFAPatchSegmentContainsAddress(target, address, operation.originalBytes.length)) {
        if (error) *error = [NSString stringWithFormat:@"Address outside target: %@+0x%llX",
                             operation.targetIdentifier, operation.offset];
        return nil;
    }

    NSData *current = nil;
    if (!HFAPatchReadMemory(address, operation.originalBytes.length, &current, error)) return nil;
    NSData *expected = enable ? operation.originalBytes : operation.enabledBytes;
    NSData *already = enable ? operation.enabledBytes : operation.originalBytes;
    if (![current isEqualToData:expected] && ![current isEqualToData:already]) {
        if (error) *error = [NSString stringWithFormat:@"Original-byte mismatch at %@+0x%llX: got %@",
                             operation.targetIdentifier, operation.offset, HFAPatchHexString(current)];
        return nil;
    }

    HFAPatchPreparedWrite *write = [[HFAPatchPreparedWrite alloc] init];
    write.address = address;
    write.before = current;
    write.after = enable ? operation.enabledBytes : operation.originalBytes;
    write.operation = operation;
    return write;
}

- (HFAPatchFeatureState)stateForFeature:(HFAPatchFeature *)feature error:(NSString **)error
{
    [self.lock lock];
    if (!self.ready || !self.configuration) {
        if (error) *error = self.configurationError ?: @"Patch engine is not ready";
        [self.lock unlock];
        return HFAPatchFeatureStateUnavailable;
    }

    BOOL sawOriginal = NO;
    BOOL sawEnabled = NO;
    for (HFAPatchOperation *operation in feature.patches) {
        HFAPatchTarget *definition = self.configuration.targets[operation.targetIdentifier];
        NSString *resolveError = nil;
        HFAPatchResolvedTarget *target = [self resolveTarget:definition error:&resolveError];
        if (!target) {
            if (error) *error = resolveError;
            [self.lock unlock];
            return HFAPatchFeatureStateUnavailable;
        }
        vm_address_t address = (vm_address_t)(uintptr_t)target.header + operation.offset;
        NSData *current = nil;
        if (!HFAPatchSegmentContainsAddress(target, address, operation.originalBytes.length) ||
            !HFAPatchReadMemory(address, operation.originalBytes.length, &current, &resolveError)) {
            if (error) *error = resolveError ?: @"Patch address invalid";
            [self.lock unlock];
            return HFAPatchFeatureStateUnavailable;
        }
        if ([current isEqualToData:operation.originalBytes]) sawOriginal = YES;
        else if ([current isEqualToData:operation.enabledBytes]) sawEnabled = YES;
        else {
            if (error) *error = [NSString stringWithFormat:@"Unexpected bytes at %@+0x%llX",
                                 operation.targetIdentifier, operation.offset];
            [self.lock unlock];
            return HFAPatchFeatureStateUnavailable;
        }
    }
    [self.lock unlock];
    if (sawOriginal && sawEnabled) return HFAPatchFeatureStateMixed;
    return sawEnabled ? HFAPatchFeatureStateEnabled : HFAPatchFeatureStateDisabled;
}

- (BOOL)setFeature:(HFAPatchFeature *)feature enabled:(BOOL)enabled error:(NSString **)error
{
    [self.lock lock];
    if (!self.ready || !self.configuration) {
        if (error) *error = self.configurationError ?: @"Patch engine is not ready";
        [self.lock unlock];
        return NO;
    }

    NSMutableArray<HFAPatchPreparedWrite *> *writes = [NSMutableArray array];
    for (HFAPatchOperation *operation in feature.patches) {
        NSString *prepareError = nil;
        HFAPatchPreparedWrite *write = [self preparedWriteForOperation:operation enable:enabled error:&prepareError];
        if (!write) {
            if (error) *error = prepareError;
            HFAPatchLog(@"[PATCH-REJECT] id=%@ enabled=%d error=%@", feature.identifier, enabled, prepareError);
            [self.lock unlock];
            return NO;
        }
        [writes addObject:write];
    }

    NSMutableArray<HFAPatchPreparedWrite *> *completed = [NSMutableArray array];
    for (HFAPatchPreparedWrite *write in writes) {
        if ([write.before isEqualToData:write.after]) continue;
        NSString *writeError = nil;
        [completed addObject:write];
        if (!HFAPatchWriteMemory(write.address, write.after, &writeError)) {
            for (HFAPatchPreparedWrite *rollback in completed.reverseObjectEnumerator) {
                NSString *rollbackError = nil;
                if (!HFAPatchWriteMemory(rollback.address, rollback.before, &rollbackError)) {
                    HFAPatchLog(@"[ROLLBACK-FAIL] id=%@ address=0x%lX error=%@",
                                feature.identifier, (unsigned long)rollback.address, rollbackError);
                }
            }
            if (error) *error = writeError;
            HFAPatchLog(@"[PATCH-FAIL] id=%@ enabled=%d error=%@", feature.identifier, enabled, writeError);
            [self.lock unlock];
            return NO;
        }
        HFAPatchLog(@"[PATCH-WRITE] id=%@ target=%@ offset=0x%llX bytes=%@",
                    feature.identifier,
                    write.operation.targetIdentifier,
                    write.operation.offset,
                    HFAPatchHexString(write.after));
    }

    NSString *preferenceKey = [self preferenceKeyForFeature:feature];
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:preferenceKey];
    HFAPatchLog(@"[PATCH-OK] id=%@ enabled=%d parts=%lu",
                feature.identifier, enabled, (unsigned long)writes.count);
    [self.lock unlock];
    return YES;
}

- (void)disableAll
{
    [self.lock lock];
    for (HFAPatchFeature *feature in self.configuration.features) {
        NSString *error = nil;
        [self setFeature:feature enabled:NO error:&error];
        if (error) HFAPatchLog(@"[DISABLE-ALL-SKIP] id=%@ error=%@", feature.identifier, error);
    }
    [self.lock unlock];
}

@end
