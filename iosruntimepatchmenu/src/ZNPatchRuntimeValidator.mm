#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import "ZNExecutablePageProbe.h"
#import <mach/mach.h>
#import <libkern/OSCacheControl.h>
#import <sys/mman.h>
#import <errno.h>
#import <stdlib.h>
#import <string.h>

static NSString *ZN43Hex(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = (const uint8_t *)data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02X", p[i]];
    return s;
}

static NSData *ZN43DataFromHex(NSString *input, NSString **error) {
    if (!input.length) { if (error) *error = @"Patch 不能为空"; return nil; }
    NSMutableString *clean = [NSMutableString string];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];
        if ([ws characterIsMember:c] || c == ':' || c == '-') continue;
        [clean appendFormat:@"%C", c];
    }
    if ([clean hasPrefix:@"0x"] || [clean hasPrefix:@"0X"]) [clean deleteCharactersInRange:NSMakeRange(0, 2)];
    if (!clean.length || (clean.length & 1)) { if (error) *error = @"Patch HEX 长度必须为偶数"; return nil; }
    if (clean.length / 2 > 256) { if (error) *error = @"首版运行时验证限制 Patch <= 256 bytes"; return nil; }

    NSMutableData *data = [NSMutableData dataWithLength:clean.length / 2];
    uint8_t *out = (uint8_t *)data.mutableBytes;
    for (NSUInteger i = 0; i < clean.length; i += 2) {
        NSString *pair = [clean substringWithRange:NSMakeRange(i, 2)];
        unsigned value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&value] || !scanner.isAtEnd) {
            if (error) *error = [NSString stringWithFormat:@"Patch HEX 非法：%@", pair];
            return nil;
        }
        out[i / 2] = (uint8_t)value;
    }
    return data;
}

static BOOL ZN43ParseRVA(NSString *input, uint64_t *outRVA, NSString **error) {
    NSString *s = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (!s.length) { if (error) *error = @"Offset 不能为空"; return NO; }

    const char *c = s.UTF8String;
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(c, &end, 0);
    if (errno != 0 || end == c || (end && *end != '\0')) {
        // Existing patch JSON commonly stores hex without a 0x prefix.
        errno = 0;
        end = NULL;
        value = strtoull(c, &end, 16);
    }
    if (errno != 0 || end == c || (end && *end != '\0')) {
        if (error) *error = [NSString stringWithFormat:@"Offset 格式无效：%@", input];
        return NO;
    }
    if (outRVA) *outRVA = (uint64_t)value;
    return YES;
}

static NSString *ZN43ProtectionString(vm_prot_t p) {
    return [NSString stringWithFormat:@"%@%@%@",
            (p & VM_PROT_READ) ? @"R" : @"-",
            (p & VM_PROT_WRITE) ? @"W" : @"-",
            (p & VM_PROT_EXECUTE) ? @"X" : @"-"];
}

static int ZN43POSIXProtection(vm_prot_t p) {
    int result = PROT_NONE;
    if (p & VM_PROT_READ) result |= PROT_READ;
    if (p & VM_PROT_WRITE) result |= PROT_WRITE;
    if (p & VM_PROT_EXECUTE) result |= PROT_EXEC;
    return result;
}

typedef struct {
    vm_address_t start;
    vm_size_t size;
    vm_prot_t protection;
    vm_prot_t maxProtection;
} ZN43RegionInfo;

static BOOL ZN43QueryRegion(uintptr_t address, NSUInteger length, ZN43RegionInfo *outInfo, NSString **error) {
    vm_address_t region = (vm_address_t)address;
    vm_size_t regionSize = 0;
    vm_region_basic_info_data_t info = {};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t kr = vm_region(mach_task_self(), &region, &regionSize,
                                 VM_REGION_BASIC_INFO,
                                 (vm_region_info_t)&info, &count, &objectName);
    if (objectName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objectName);
    if (kr != KERN_SUCCESS) {
        if (error) *error = [NSString stringWithFormat:@"vm_region 失败：%s (%d)", mach_error_string(kr), kr];
        return NO;
    }

    uint64_t end = (uint64_t)address + (uint64_t)length;
    uint64_t regionEnd = (uint64_t)region + (uint64_t)regionSize;
    if ((uint64_t)address < (uint64_t)region || end > regionEnd) {
        if (error) *error = @"Patch 跨越不同 VM region，首版验证拒绝执行";
        return NO;
    }
    if (outInfo) {
        outInfo->start = region;
        outInfo->size = regionSize;
        outInfo->protection = info.protection;
        outInfo->maxProtection = info.max_protection;
    }
    return YES;
}

static BOOL ZN43Read(uintptr_t address, NSUInteger length, NSData **outData, NSString **error) {
    if (!address || !length) { if (error) *error = @"读取地址或长度无效"; return NO; }
    NSMutableData *data = [NSMutableData dataWithLength:length];
    vm_size_t readSize = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                         (vm_address_t)address,
                                         (vm_size_t)length,
                                         (vm_address_t)data.mutableBytes,
                                         &readSize);
    if (kr != KERN_SUCCESS || readSize != (vm_size_t)length) {
        if (error) *error = [NSString stringWithFormat:@"读取失败：%s (%d)，read=%llu/%lu",
                             mach_error_string(kr), kr,
                             (unsigned long long)readSize, (unsigned long)length];
        return NO;
    }
    if (outData) *outData = data;
    return YES;
}

static void ZN43RefreshCurrent(uintptr_t address, NSUInteger length, void (^setter)(NSData *)) {
    NSData *fresh = nil;
    if (ZN43Read(address, length, &fresh, NULL) && setter) setter(fresh);
}

// Writes one already-loaded code range on a capable developer device. The original
// protection is restored exactly. If the restore step fails, rollback bytes are
// immediately copied back while the range is still writable, then protection
// restoration is attempted once more before returning failure.
static BOOL ZN43WriteTransition(uintptr_t address,
                                NSData *target,
                                NSData *rollback,
                                vm_prot_t originalProtection,
                                NSString **error) {
    vm_size_t pageSize = vm_page_size;
    uintptr_t pageStart = address & ~((uintptr_t)pageSize - 1);
    uintptr_t rawEnd = address + target.length;
    uintptr_t pageEnd = (rawEnd + pageSize - 1) & ~((uintptr_t)pageSize - 1);
    size_t protectSize = (size_t)(pageEnd - pageStart);

    if (mprotect((void *)pageStart, protectSize, PROT_READ | PROT_WRITE) != 0) {
        int e = errno;
        if (error) *error = [NSString stringWithFormat:@"RX→RW 失败：errno=%d (%s)", e, strerror(e)];
        return NO;
    }

    memcpy((void *)address, target.bytes, target.length);
    sys_icache_invalidate((void *)address, target.length);

    NSData *written = nil;
    NSString *readError = nil;
    BOOL writeVerified = ZN43Read(address, target.length, &written, &readError) && [written isEqualToData:target];
    if (!writeVerified) {
        if (rollback.length == target.length) {
            memcpy((void *)address, rollback.bytes, rollback.length);
            sys_icache_invalidate((void *)address, rollback.length);
        }
        mprotect((void *)pageStart, protectSize, ZN43POSIXProtection(originalProtection));
        if (error) *error = readError.length ? [NSString stringWithFormat:@"写入 read-back 失败：%@；已回滚", readError] : @"写入 read-back 不一致；已回滚";
        return NO;
    }

    int restoreRC = mprotect((void *)pageStart, protectSize, ZN43POSIXProtection(originalProtection));
    if (restoreRC != 0) {
        int firstError = errno;
        if (rollback.length == target.length) {
            memcpy((void *)address, rollback.bytes, rollback.length);
            sys_icache_invalidate((void *)address, rollback.length);
        }
        int secondRC = mprotect((void *)pageStart, protectSize, ZN43POSIXProtection(originalProtection));
        int secondError = errno;
        if (error) {
            *error = [NSString stringWithFormat:@"写入后恢复 %@ 失败 errno=%d (%s)；原字节已回滚；二次恢复=%@%@",
                      ZN43ProtectionString(originalProtection), firstError, strerror(firstError),
                      secondRC == 0 ? @"成功" : @"失败",
                      secondRC == 0 ? @"" : [NSString stringWithFormat:@" errno=%d (%s)", secondError, strerror(secondError)]];
        }
        return NO;
    }

    NSData *final = nil;
    if (!ZN43Read(address, target.length, &final, &readError) || ![final isEqualToData:target]) {
        if (error) *error = readError.length ? [NSString stringWithFormat:@"恢复权限后 read-back 失败：%@", readError] : @"恢复权限后 read-back 不一致";
        return NO;
    }
    return YES;
}

@interface ZNPatchRuntimeValidator ()
@property(nonatomic,copy,readwrite) NSString *target;
@property(nonatomic,assign,readwrite) uint64_t rva;
@property(nonatomic,copy,readwrite) NSData *patchBytes;
@property(nonatomic,copy,readwrite) NSData *capturedOriginalBytes;
@property(nonatomic,copy,readwrite) NSData *currentBytes;
@property(nonatomic,assign,readwrite) uintptr_t runtimeAddress;
@property(nonatomic,assign,readwrite,getter=isConfigured) BOOL configured;
@property(nonatomic,assign,readwrite,getter=isValidated) BOOL validated;
@property(nonatomic,assign,readwrite,getter=isApplied) BOOL applied;
@property(nonatomic,copy,readwrite) NSString *lastResult;
@property(nonatomic,copy) NSString *protectionDescription;
@end

@implementation ZNPatchRuntimeValidator

+ (instancetype)sharedValidator {
    static ZNPatchRuntimeValidator *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNPatchRuntimeValidator new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _target = @"UnityFramework";
    _lastResult = @"尚未配置";
    _protectionDescription = @"未知";
    return self;
}

- (BOOL)configureTarget:(NSString *)target offsetString:(NSString *)offsetString patchHex:(NSString *)patchHex error:(NSString **)error {
    @synchronized (self) {
        if (self.applied) {
            if (error) *error = @"当前临时 Patch 尚未恢复，请先恢复原始字节";
            return NO;
        }
        NSString *name = [target stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) { if (error) *error = @"Target 不能为空"; return NO; }

        uint64_t parsedRVA = 0;
        NSString *e = nil;
        if (!ZN43ParseRVA(offsetString, &parsedRVA, &e)) { if (error) *error = e; return NO; }
        NSData *patch = ZN43DataFromHex(patchHex, &e);
        if (!patch) { if (error) *error = e; return NO; }
        if ((parsedRVA & 3ULL) != 0) { if (error) *error = @"Offset 不是 4-byte ARM64 对齐"; return NO; }
        if ((patch.length & 3U) != 0) { if (error) *error = @"代码 Patch 长度必须是 4 bytes 的倍数"; return NO; }

        self.target = name;
        self.rva = parsedRVA;
        self.patchBytes = patch;
        self.capturedOriginalBytes = nil;
        self.currentBytes = nil;
        self.runtimeAddress = 0;
        self.configured = YES;
        self.validated = NO;
        self.applied = NO;
        self.protectionDescription = @"未知";
        self.lastResult = @"已配置，等待读取验证";
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] configured target=%@ rva=0x%llX patch=%@",
                                             self.target, self.rva, ZN43Hex(self.patchBytes)]];
        return YES;
    }
}

- (BOOL)validate:(NSString **)error {
    @synchronized (self) {
        if (!self.configured || !self.patchBytes.length) {
            if (error) *error = @"请先配置 target / offset / patch";
            return NO;
        }

        NSDictionary *module = [[ZNModuleManager sharedManager] moduleNamed:self.target];
        if (!module) {
            self.validated = NO;
            self.lastResult = [NSString stringWithFormat:@"目标模块未加载：%@", self.target];
            if (error) *error = self.lastResult;
            return NO;
        }

        uintptr_t address = [[ZNModuleManager sharedManager] runtimeAddressForModule:self.target rva:self.rva];
        if (!address) {
            self.validated = NO;
            self.lastResult = @"Runtime Address 解析失败";
            if (error) *error = self.lastResult;
            return NO;
        }

        ZN43RegionInfo region = {};
        NSString *e = nil;
        if (!ZN43QueryRegion(address, self.patchBytes.length, &region, &e)) {
            self.validated = NO;
            self.lastResult = e ?: @"VM region 查询失败";
            if (error) *error = self.lastResult;
            return NO;
        }
        self.runtimeAddress = address;
        self.protectionDescription = [NSString stringWithFormat:@"%@  max=%@",
                                      ZN43ProtectionString(region.protection),
                                      ZN43ProtectionString(region.maxProtection)];
        if ((region.protection & VM_PROT_EXECUTE) == 0) {
            self.validated = NO;
            self.lastResult = [NSString stringWithFormat:@"目标不是 executable region：%@", self.protectionDescription];
            if (error) *error = self.lastResult;
            return NO;
        }

        NSData *now = nil;
        if (!ZN43Read(address, self.patchBytes.length, &now, &e)) {
            self.validated = NO;
            self.lastResult = e ?: @"读取失败";
            if (error) *error = self.lastResult;
            return NO;
        }
        self.currentBytes = now;

        if ([now isEqualToData:self.patchBytes]) {
            if (!self.capturedOriginalBytes.length) {
                self.validated = NO;
                self.lastResult = @"当前位置已经等于 Patch，无法现场推断 Original；请用原版进程重新验证";
                if (error) *error = self.lastResult;
                return NO;
            }
            self.applied = YES;
        } else if (!self.capturedOriginalBytes.length) {
            // This is the only trusted OFF baseline: bytes read live from the user's
            // original binary. JSON "original" is intentionally ignored.
            self.capturedOriginalBytes = now;
            self.applied = NO;
        } else if ([now isEqualToData:self.capturedOriginalBytes]) {
            self.applied = NO;
        } else {
            self.validated = NO;
            self.lastResult = [NSString stringWithFormat:@"现场字节与本会话 Original/Patch 均不一致，拒绝更新基线。Original=%@ Current=%@ Patch=%@",
                               ZN43Hex(self.capturedOriginalBytes), ZN43Hex(now), ZN43Hex(self.patchBytes)];
            if (error) *error = self.lastResult;
            return NO;
        }

        self.validated = YES;
        self.lastResult = [NSString stringWithFormat:@"Binary/Runtime 预检 PASS：%@ + 0x%llX，现场 Original=%@",
                           self.target, self.rva, ZN43Hex(self.capturedOriginalBytes)];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] %@", self.lastResult]];
        return YES;
    }
}

- (BOOL)applyTemporary:(NSString **)error {
    @synchronized (self) {
        NSString *e = nil;
        if (!self.validated && ![self validate:&e]) {
            if (error) *error = e;
            return NO;
        }
        if (!self.capturedOriginalBytes.length || self.capturedOriginalBytes.length != self.patchBytes.length) {
            self.lastResult = @"没有可用的现场 Original，拒绝临时应用";
            if (error) *error = self.lastResult;
            return NO;
        }

        NSData *now = nil;
        if (!ZN43Read(self.runtimeAddress, self.patchBytes.length, &now, &e)) {
            self.lastResult = e ?: @"读取失败";
            if (error) *error = self.lastResult;
            return NO;
        }
        self.currentBytes = now;
        if ([now isEqualToData:self.patchBytes]) {
            self.applied = YES;
            self.lastResult = @"Patch 已经处于临时应用状态";
            return YES;
        }
        if (![now isEqualToData:self.capturedOriginalBytes]) {
            self.lastResult = [NSString stringWithFormat:@"当前字节已变化，拒绝覆盖。Original=%@ Current=%@",
                               ZN43Hex(self.capturedOriginalBytes), ZN43Hex(now)];
            if (error) *error = self.lastResult;
            return NO;
        }

        ZNExecutablePageProbe *probe = [ZNExecutablePageProbe sharedProbe];
        BOOL capable = probe.hasRun ? probe.supported : [probe runProbe];
        if (!capable) {
            self.lastResult = [NSString stringWithFormat:@"Executable Page Probe 未通过，拒绝触碰真实目标：%@",
                               probe.lastResult ?: @"unsupported"];
            if (error) *error = self.lastResult;
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] %@", self.lastResult]];
            return NO;
        }

        ZN43RegionInfo region = {};
        if (!ZN43QueryRegion(self.runtimeAddress, self.patchBytes.length, &region, &e)) {
            self.lastResult = e ?: @"VM region 查询失败";
            if (error) *error = self.lastResult;
            return NO;
        }
        if (!ZN43WriteTransition(self.runtimeAddress,
                                 self.patchBytes,
                                 self.capturedOriginalBytes,
                                 region.protection,
                                 &e)) {
            self.applied = NO;
            __weak typeof(self) weakSelf = self;
            ZN43RefreshCurrent(self.runtimeAddress, self.patchBytes.length, ^(NSData *fresh) { weakSelf.currentBytes = fresh; });
            self.lastResult = [NSString stringWithFormat:@"Runtime Patch FAIL：%@", e ?: @"写入失败"];
            if (error) *error = self.lastResult;
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] %@", self.lastResult]];
            return NO;
        }

        self.applied = YES;
        __weak typeof(self) weakSelf = self;
        ZN43RefreshCurrent(self.runtimeAddress, self.patchBytes.length, ^(NSData *fresh) { weakSelf.currentBytes = fresh; });
        self.lastResult = [NSString stringWithFormat:@"Runtime Patch PASS：write / read-back / %@ restore / icache",
                           ZN43ProtectionString(region.protection)];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] %@", self.lastResult]];
        return YES;
    }
}

- (BOOL)restoreOriginal:(NSString **)error {
    @synchronized (self) {
        if (!self.configured || !self.capturedOriginalBytes.length || !self.runtimeAddress) {
            if (error) *error = @"当前会话没有可恢复的现场 Original";
            return NO;
        }

        NSString *e = nil;
        NSData *now = nil;
        if (!ZN43Read(self.runtimeAddress, self.patchBytes.length, &now, &e)) {
            self.lastResult = e ?: @"读取失败";
            if (error) *error = self.lastResult;
            return NO;
        }
        self.currentBytes = now;
        if ([now isEqualToData:self.capturedOriginalBytes]) {
            self.applied = NO;
            self.validated = YES;
            self.lastResult = @"当前已经是现场 Original，无需恢复";
            return YES;
        }
        if (![now isEqualToData:self.patchBytes]) {
            self.lastResult = @"当前位置不是本会话 Patch，检测到第三方变化，拒绝恢复";
            if (error) *error = self.lastResult;
            return NO;
        }

        ZN43RegionInfo region = {};
        if (!ZN43QueryRegion(self.runtimeAddress, self.patchBytes.length, &region, &e)) {
            self.lastResult = e ?: @"VM region 查询失败";
            if (error) *error = self.lastResult;
            return NO;
        }
        if (!ZN43WriteTransition(self.runtimeAddress,
                                 self.capturedOriginalBytes,
                                 self.patchBytes,
                                 region.protection,
                                 &e)) {
            self.lastResult = [NSString stringWithFormat:@"恢复 FAIL：%@", e ?: @"写入失败"];
            if (error) *error = self.lastResult;
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] %@", self.lastResult]];
            return NO;
        }

        self.applied = NO;
        self.validated = YES;
        __weak typeof(self) weakSelf = self;
        ZN43RefreshCurrent(self.runtimeAddress, self.patchBytes.length, ^(NSData *fresh) { weakSelf.currentBytes = fresh; });
        self.lastResult = @"恢复 PASS：现场 Original 已写回并验证";
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] %@", self.lastResult]];
        return YES;
    }
}

- (void)clearSession {
    @synchronized (self) {
        if (self.applied) {
            self.lastResult = @"临时 Patch 尚未恢复，拒绝清除会话";
            return;
        }
        self.target = @"UnityFramework";
        self.rva = 0;
        self.patchBytes = nil;
        self.capturedOriginalBytes = nil;
        self.currentBytes = nil;
        self.runtimeAddress = 0;
        self.configured = NO;
        self.validated = NO;
        self.applied = NO;
        self.protectionDescription = @"未知";
        self.lastResult = @"尚未配置";
    }
}

- (NSArray<NSString *> *)diagnosticLines {
    @synchronized (self) {
        if (!self.configured) {
            return @[
                @"状态：尚未配置",
                @"输入：target + offset + patch；JSON original 不参与验证",
                @"临时应用前会先要求 Executable Page Probe PASS"
            ];
        }
        return @[
            [NSString stringWithFormat:@"Target：%@", self.target ?: @""],
            [NSString stringWithFormat:@"Offset：0x%llX    Runtime：%@",
             self.rva,
             self.runtimeAddress ? [NSString stringWithFormat:@"0x%llX", (unsigned long long)self.runtimeAddress] : @"未解析"],
            [NSString stringWithFormat:@"Patch：%@", ZN43Hex(self.patchBytes)],
            [NSString stringWithFormat:@"Live Original：%@", self.capturedOriginalBytes.length ? ZN43Hex(self.capturedOriginalBytes) : @"未捕获"],
            [NSString stringWithFormat:@"Current：%@", self.currentBytes.length ? ZN43Hex(self.currentBytes) : @"未读取"],
            [NSString stringWithFormat:@"VM：%@    Applied：%@", self.protectionDescription ?: @"未知", self.applied ? @"YES" : @"NO"],
            [NSString stringWithFormat:@"结果：%@", self.lastResult ?: @""]
        ];
    }
}

- (NSString *)diagnosticReport {
    return [[self diagnosticLines] componentsJoinedByString:@"\n"];
}

@end
