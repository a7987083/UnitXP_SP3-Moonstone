#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import "ZNExecutablePageProbe.h"
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <libkern/OSCacheControl.h>
#import <sys/mman.h>
#import <errno.h>
#import <string.h>

// M5.10.0 Offset Core V1
// One address model only: Target Mach-O + RVA.
// Supported authoring forms: 0x1234 / 1234 / rva:0x1234.
// Preferred-VA/runtime-VA/file-offset guessing is deliberately removed.

static NSString *ZNOCTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNOCHex(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [out appendFormat:@"%02X", bytes[i]];
    return out;
}

static BOOL ZNOCParseRVA(NSString *input, uint64_t *outRVA, NSString **error) {
    NSString *s = ZNOCTrim(input).lowercaseString;
    if (!s.length) { if (error) *error = @"Offset 不能为空"; return NO; }
    if ([s hasPrefix:@"rva:"]) s = ZNOCTrim([s substringFromIndex:4]);
    else if ([s hasPrefix:@"va:"] || [s hasPrefix:@"runtime:"] || [s hasPrefix:@"file:"]) {
        if (error) *error = @"M5.10 Offset Core 只接受 RVA，不再猜测 VA/runtime/file 地址语义";
        return NO;
    }
    if (!s.length) { if (error) *error = @"RVA 不能为空"; return NO; }

    const char *c = s.UTF8String;
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(c, &end, 0);
    if (errno || end == c || (end && *end)) {
        errno = 0; end = NULL;
        value = strtoull(c, &end, 16);
    }
    if (errno || end == c || (end && *end)) {
        if (error) *error = [NSString stringWithFormat:@"RVA 格式无效：%@", input ?: @""];
        return NO;
    }
    if (outRVA) *outRVA = (uint64_t)value;
    return YES;
}

static NSData *ZNOCDataFromHex(NSString *input, NSString **error) {
    NSString *raw = ZNOCTrim(input);
    if (!raw.length) { if (error) *error = @"Enabled HEX 不能为空"; return nil; }
    NSMutableString *clean = [NSMutableString string];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if ([ws characterIsMember:c] || c == ':' || c == '-') continue;
        [clean appendFormat:@"%C", c];
    }
    if ([clean hasPrefix:@"0x"] || [clean hasPrefix:@"0X"]) [clean deleteCharactersInRange:NSMakeRange(0, 2)];
    if (!clean.length || (clean.length & 1u)) { if (error) *error = @"Enabled HEX 长度必须为偶数"; return nil; }
    if (clean.length / 2 > 256) { if (error) *error = @"单条 Offset Patch 最多 256 bytes"; return nil; }

    NSMutableData *data = [NSMutableData dataWithLength:clean.length / 2];
    uint8_t *dst = data.mutableBytes;
    for (NSUInteger i = 0; i < clean.length; i += 2) {
        NSString *pair = [clean substringWithRange:NSMakeRange(i, 2)];
        unsigned value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&value] || !scanner.isAtEnd) {
            if (error) *error = [NSString stringWithFormat:@"Enabled HEX 非法：%@", pair];
            return nil;
        }
        dst[i / 2] = (uint8_t)value;
    }
    return data;
}

typedef struct {
    uintptr_t start;
    uintptr_t end;
    vm_prot_t initprot;
    char name[17];
} ZNOCSegment;

static BOOL ZNOCFindSegment(uintptr_t imageBase, uintptr_t address, NSUInteger length, ZNOCSegment *out, NSString **error) {
    if (!imageBase || !address || !length) { if (error) *error = @"目标 image / 地址 / 长度无效"; return NO; }
    const struct mach_header_64 *mh = (const struct mach_header_64 *)imageBase;
    if (mh->magic != MH_MAGIC_64) { if (error) *error = @"目标不是 64-bit Mach-O"; return NO; }

    const uint8_t *cursor = (const uint8_t *)(mh + 1);
    const uint8_t *end = cursor + mh->sizeofcmds;
    const struct load_command *lc = (const struct load_command *)cursor;
    uint64_t vmBase = UINT64_MAX;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if ((const uint8_t *)lc + sizeof(*lc) > end || lc->cmdsize < sizeof(*lc) || (const uint8_t *)lc + lc->cmdsize > end) {
            if (error) *error = @"Mach-O load commands 损坏"; return NO;
        }
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, SEG_TEXT, 16) == 0) vmBase = seg->vmaddr;
        }
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
    if (vmBase == UINT64_MAX) { if (error) *error = @"目标 Mach-O 没有 __TEXT"; return NO; }

    lc = (const struct load_command *)cursor;
    uint64_t wantedEnd = (uint64_t)address + (uint64_t)length;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (seg->vmaddr >= vmBase) {
                uintptr_t start = imageBase + (uintptr_t)(seg->vmaddr - vmBase);
                uintptr_t finish = start + (uintptr_t)seg->vmsize;
                if (address >= start && wantedEnd <= (uint64_t)finish) {
                    if (!(seg->initprot & VM_PROT_EXECUTE)) {
                        if (error) *error = @"普通 Offset Patch 只允许可执行代码 segment";
                        return NO;
                    }
                    if (out) {
                        memset(out, 0, sizeof(*out));
                        out->start = start; out->end = finish; out->initprot = seg->initprot;
                        memcpy(out->name, seg->segname, 16); out->name[16] = 0;
                    }
                    return YES;
                }
            }
        }
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
    if (error) *error = @"RVA 不落在目标 Mach-O 的可执行 segment";
    return NO;
}

static BOOL ZNOCRead(uintptr_t address, NSUInteger length, NSData **outData, NSString **error) {
    if (!address || !length) { if (error) *error = @"读取参数无效"; return NO; }
    NSMutableData *data = [NSMutableData dataWithLength:length];
    mach_vm_size_t copied = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)address, (mach_vm_size_t)length,
                                              (mach_vm_address_t)data.mutableBytes, &copied);
    if (kr != KERN_SUCCESS || copied != length) {
        if (error) *error = [NSString stringWithFormat:@"读取目标内存失败 kr=%d copied=%llu", kr, copied];
        return NO;
    }
    if (outData) *outData = data;
    return YES;
}

static int ZNOCPOSIXProt(vm_prot_t prot) {
    int p = PROT_NONE;
    if (prot & VM_PROT_READ) p |= PROT_READ;
    if (prot & VM_PROT_WRITE) p |= PROT_WRITE;
    if (prot & VM_PROT_EXECUTE) p |= PROT_EXEC;
    return p;
}

static BOOL ZNOCWrite(uintptr_t address, NSData *wanted, NSData *rollback, vm_prot_t originalProt, NSString **error) {
    if (!address || !wanted.length) { if (error) *error = @"写入参数无效"; return NO; }
    vm_size_t page = vm_page_size;
    uintptr_t pageStart = address & ~((uintptr_t)page - 1u);
    uintptr_t rawEnd = address + wanted.length;
    uintptr_t pageEnd = (rawEnd + page - 1u) & ~((uintptr_t)page - 1u);
    size_t span = (size_t)(pageEnd - pageStart);

    if (mprotect((void *)pageStart, span, PROT_READ | PROT_WRITE) != 0) {
        int e = errno; if (error) *error = [NSString stringWithFormat:@"代码页 RX→RW 失败 errno=%d (%s)", e, strerror(e)]; return NO;
    }
    memcpy((void *)address, wanted.bytes, wanted.length);
    sys_icache_invalidate((void *)address, wanted.length);

    NSData *check = nil; NSString *readError = nil;
    BOOL good = ZNOCRead(address, wanted.length, &check, &readError) && [check isEqualToData:wanted];
    if (!good && rollback.length == wanted.length) {
        memcpy((void *)address, rollback.bytes, rollback.length);
        sys_icache_invalidate((void *)address, rollback.length);
    }
    int restoreRC = mprotect((void *)pageStart, span, ZNOCPOSIXProt(originalProt));
    if (!good) { if (error) *error = readError ?: @"写入 read-back 不一致，已回滚"; return NO; }
    if (restoreRC != 0) {
        int e = errno;
        if (rollback.length == wanted.length) {
            if (mprotect((void *)pageStart, span, PROT_READ | PROT_WRITE) == 0) {
                memcpy((void *)address, rollback.bytes, rollback.length);
                sys_icache_invalidate((void *)address, rollback.length);
                mprotect((void *)pageStart, span, ZNOCPOSIXProt(originalProt));
            }
        }
        if (error) *error = [NSString stringWithFormat:@"写入后恢复代码页权限失败 errno=%d (%s)，已尝试回滚", e, strerror(e)];
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
@property(nonatomic,assign) vm_prot_t originalProtection;
@property(nonatomic,copy) NSString *segmentName;
@end

@implementation ZNPatchRuntimeValidator

+ (instancetype)sharedValidator {
    static ZNPatchRuntimeValidator *shared; static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZNPatchRuntimeValidator new]; });
    return shared;
}

- (instancetype)init {
    self = [super init]; if (!self) return nil;
    _target = @"UnityFramework"; _lastResult = @"尚未配置"; _segmentName = @"-";
    return self;
}

- (BOOL)configureTarget:(NSString *)target offsetString:(NSString *)offsetString patchHex:(NSString *)patchHex error:(NSString **)error {
    @synchronized (self) {
        if (self.applied) { if (error) *error = @"请先恢复当前临时 Patch"; return NO; }
        NSString *name = ZNOCTrim(target);
        if (!name.length) { if (error) *error = @"Target 不能为空"; return NO; }
        uint64_t rva = 0; NSString *local = nil;
        if (!ZNOCParseRVA(offsetString, &rva, &local)) { if (error) *error = local; return NO; }
        NSData *patch = ZNOCDataFromHex(patchHex, &local);
        if (!patch) { if (error) *error = local; return NO; }
        if (rva & 3u) { if (error) *error = @"ARM64 RVA 必须 4-byte 对齐"; return NO; }
        if (patch.length & 3u) { if (error) *error = @"ARM64 Enabled 长度必须是 4-byte 倍数"; return NO; }

        self.target = name; self.rva = rva; self.patchBytes = patch;
        self.capturedOriginalBytes = nil; self.currentBytes = nil; self.runtimeAddress = 0;
        self.configured = YES; self.validated = NO; self.applied = NO;
        self.originalProtection = 0; self.segmentName = @"-";
        self.lastResult = @"已配置 · 待读取验证";
        return YES;
    }
}

- (BOOL)validate:(NSString **)error {
    @synchronized (self) {
        if (!self.configured || !self.patchBytes.length) { if (error) *error = @"请先配置 Offset Patch"; return NO; }
        NSDictionary *module = [[ZNModuleManager sharedManager] moduleNamed:self.target];
        if (!module) { self.validated = NO; self.lastResult = [NSString stringWithFormat:@"目标模块未加载：%@", self.target]; if (error) *error = self.lastResult; return NO; }
        uintptr_t imageBase = (uintptr_t)[module[@"base"] unsignedLongLongValue];
        uintptr_t address = [[ZNModuleManager sharedManager] runtimeAddressForModule:self.target rva:self.rva];
        if (!imageBase || !address) { self.validated = NO; self.lastResult = @"Target + RVA 无法解析"; if (error) *error = self.lastResult; return NO; }

        ZNOCSegment seg = {}; NSString *local = nil;
        if (!ZNOCFindSegment(imageBase, address, self.patchBytes.length, &seg, &local)) {
            self.validated = NO; self.lastResult = local ?: @"Offset segment 验证失败"; if (error) *error = self.lastResult; return NO;
        }
        NSData *live = nil;
        if (!ZNOCRead(address, self.patchBytes.length, &live, &local)) {
            self.validated = NO; self.lastResult = local ?: @"读取 Original 失败"; if (error) *error = self.lastResult; return NO;
        }

        self.runtimeAddress = address; self.capturedOriginalBytes = live; self.currentBytes = live;
        self.originalProtection = seg.initprot; self.segmentName = [NSString stringWithUTF8String:seg.name] ?: @"?";
        self.validated = YES; self.applied = NO;
        self.lastResult = [NSString stringWithFormat:@"验证通过 %@+0x%llX · %@ · %lu bytes", self.target, self.rva, self.segmentName, (unsigned long)self.patchBytes.length];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.10-offset] validate target=%@ rva=0x%llX address=%p segment=%@ original=%@ enabled=%@",
                                             self.target, self.rva, (void *)address, self.segmentName, ZNOCHex(live), ZNOCHex(self.patchBytes)]];
        return YES;
    }
}

- (BOOL)applyTemporary:(NSString **)error {
    @synchronized (self) {
        if (!self.validated || !self.runtimeAddress || !self.capturedOriginalBytes.length) { if (error) *error = @"请先读取验证"; return NO; }
        if (self.applied) return YES;
        NSData *now = nil; NSString *local = nil;
        if (!ZNOCRead(self.runtimeAddress, self.patchBytes.length, &now, &local)) { if (error) *error = local; return NO; }
        if (![now isEqualToData:self.capturedOriginalBytes]) {
            self.lastResult = @"拒绝应用：当前字节已偏离验证时 Original"; if (error) *error = self.lastResult; return NO;
        }
        ZNExecutablePageProbe *probe = [ZNExecutablePageProbe sharedProbe];
        if (!probe.hasRun && ![probe runProbe]) { self.lastResult = @"设备代码页写入探针失败，拒绝临时 Patch"; if (error) *error = self.lastResult; return NO; }
        if (!probe.supported) { self.lastResult = @"当前设备不支持安全临时代码页写入"; if (error) *error = self.lastResult; return NO; }
        if (!ZNOCWrite(self.runtimeAddress, self.patchBytes, self.capturedOriginalBytes, self.originalProtection, &local)) {
            self.lastResult = local ?: @"临时应用失败"; if (error) *error = self.lastResult; return NO;
        }
        self.currentBytes = self.patchBytes; self.applied = YES; self.lastResult = @"临时 Patch 已应用";
        return YES;
    }
}

- (BOOL)restoreOriginal:(NSString **)error {
    @synchronized (self) {
        if (!self.applied) return YES;
        NSData *now = nil; NSString *local = nil;
        if (!ZNOCRead(self.runtimeAddress, self.patchBytes.length, &now, &local)) { if (error) *error = local; return NO; }
        if (![now isEqualToData:self.patchBytes]) {
            self.lastResult = @"拒绝恢复：当前字节不是本会话写入值，避免覆盖第三方修改"; if (error) *error = self.lastResult; return NO;
        }
        if (!ZNOCWrite(self.runtimeAddress, self.capturedOriginalBytes, self.patchBytes, self.originalProtection, &local)) {
            self.lastResult = local ?: @"恢复失败"; if (error) *error = self.lastResult; return NO;
        }
        self.currentBytes = self.capturedOriginalBytes; self.applied = NO; self.lastResult = @"Original 已恢复";
        return YES;
    }
}

- (void)clearSession {
    @synchronized (self) {
        if (self.applied) return;
        self.patchBytes = nil; self.capturedOriginalBytes = nil; self.currentBytes = nil; self.runtimeAddress = 0;
        self.configured = NO; self.validated = NO; self.originalProtection = 0; self.segmentName = @"-"; self.lastResult = @"会话已清除";
    }
}

- (NSArray<NSString *> *)diagnosticLines {
    return @[
        [NSString stringWithFormat:@"Target: %@", self.target ?: @"-"],
        [NSString stringWithFormat:@"RVA: 0x%llX", self.rva],
        [NSString stringWithFormat:@"Runtime: %p", (void *)self.runtimeAddress],
        [NSString stringWithFormat:@"Segment: %@", self.segmentName ?: @"-"],
        [NSString stringWithFormat:@"Original: %@", ZNOCHex(self.capturedOriginalBytes)],
        [NSString stringWithFormat:@"Enabled: %@", ZNOCHex(self.patchBytes)],
        [NSString stringWithFormat:@"State: configured=%@ validated=%@ applied=%@", self.configured?@"YES":@"NO", self.validated?@"YES":@"NO", self.applied?@"YES":@"NO"],
        [NSString stringWithFormat:@"Result: %@", self.lastResult ?: @"-"]
    ];
}

- (NSString *)diagnosticReport { return [[self diagnosticLines] componentsJoinedByString:@"\n"]; }

@end
