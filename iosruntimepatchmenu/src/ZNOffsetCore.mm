#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import "ZNExecutablePageProbe.h"
#import "ZNH5GGValueBackend.h"
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <libkern/OSCacheControl.h>
#import <sys/mman.h>
#import <errno.h>
#import <stdlib.h>
#import <string.h>

// M5.11 unified Offset core.
// Address contract remains module + RVA. Switch rows are raw ARM64 bytes;
// Slider/Number rows use ZNTypedValueOffset and do not pass through this class.

static NSString *ZNOCTrim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNOCHex(NSData *data) {
    const uint8_t *p = (const uint8_t *)data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02X", p[i]];
    return s;
}

static BOOL ZNOCParseRVA(NSString *text, uint64_t *out, NSString **error) {
    NSString *s = ZNOCTrim(text).lowercaseString;
    if ([s hasPrefix:@"rva:"]) s = ZNOCTrim([s substringFromIndex:4]);
    if ([s hasPrefix:@"va:"] || [s hasPrefix:@"runtime:"] || [s hasPrefix:@"file:"]) {
        if (error) *error = @"M5.11 只接受 RVA；va/runtime/file 模式已删除";
        return NO;
    }
    if (!s.length) { if (error) *error = @"RVA 不能为空"; return NO; }
    const char *c = s.UTF8String; char *end = NULL; errno = 0;
    unsigned long long v = strtoull(c, &end, 0);
    if (errno || end == c || (end && *end)) { errno = 0; end = NULL; v = strtoull(c, &end, 16); }
    if (errno || end == c || (end && *end)) { if (error) *error = [NSString stringWithFormat:@"RVA 格式无效：%@", text ?: @""]; return NO; }
    if (v & 3ULL) { if (error) *error = @"ARM64 RVA 必须 4-byte 对齐"; return NO; }
    if (out) *out = (uint64_t)v;
    return YES;
}

static NSData *ZNOCParseHex(NSString *text, NSString **error) {
    NSString *raw = ZNOCTrim(text);
    NSMutableString *s = [NSMutableString string];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if ([ws characterIsMember:c] || c == ':' || c == '-') continue;
        [s appendFormat:@"%C", c];
    }
    if ([s hasPrefix:@"0x"] || [s hasPrefix:@"0X"]) [s deleteCharactersInRange:NSMakeRange(0, 2)];
    if (!s.length || (s.length & 1u)) { if (error) *error = @"Enabled HEX 必须为非空偶数字符"; return nil; }
    NSUInteger n = s.length / 2;
    if ((n & 3u) || n > 256) { if (error) *error = @"ARM64 Patch 长度必须为 4-byte 倍数且不超过 256 bytes"; return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:n];
    uint8_t *dst = (uint8_t *)data.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) {
        NSString *pair = [s substringWithRange:NSMakeRange(i * 2, 2)];
        unsigned value = 0; NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&value] || !scanner.isAtEnd) { if (error) *error = [NSString stringWithFormat:@"Enabled HEX 非法：%@", pair]; return nil; }
        dst[i] = (uint8_t)value;
    }
    return data;
}

typedef struct { vm_prot_t protection; char name[17]; } ZNOCExecRange;

static BOOL ZNOCExecutableRange(uintptr_t imageBase, uintptr_t address, NSUInteger length, ZNOCExecRange *out, NSString **error) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)imageBase;
    if (!mh || mh->magic != MH_MAGIC_64) { if (error) *error = @"目标不是有效 64-bit Mach-O"; return NO; }
    const uint8_t *begin = (const uint8_t *)(mh + 1), *limit = begin + mh->sizeofcmds;
    const struct load_command *lc = (const struct load_command *)begin;
    uint64_t vmBase = UINT64_MAX;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if ((const uint8_t *)lc + sizeof(*lc) > limit || lc->cmdsize < sizeof(*lc) || (const uint8_t *)lc + lc->cmdsize > limit) { if (error) *error = @"Mach-O load commands 损坏"; return NO; }
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (!strncmp(seg->segname, SEG_TEXT, 16)) vmBase = seg->vmaddr;
        }
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
    if (vmBase == UINT64_MAX) { if (error) *error = @"目标没有 __TEXT"; return NO; }
    lc = (const struct load_command *)begin;
    uint64_t wantedEnd = (uint64_t)address + length;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (seg->vmaddr >= vmBase) {
                uintptr_t start = imageBase + (uintptr_t)(seg->vmaddr - vmBase), end = start + (uintptr_t)seg->vmsize;
                if (address >= start && wantedEnd <= (uint64_t)end) {
                    if (!(seg->initprot & VM_PROT_EXECUTE)) { if (error) *error = @"Offset 不在可执行 segment"; return NO; }
                    if (out) { memset(out, 0, sizeof(*out)); out->protection = seg->initprot; memcpy(out->name, seg->segname, 16); out->name[16] = 0; }
                    return YES;
                }
            }
        }
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
    if (error) *error = @"RVA 超出目标可执行范围";
    return NO;
}

static BOOL ZNOCRead(uintptr_t address, NSUInteger length, NSData **out, NSString **error) {
    NSMutableData *data = [NSMutableData dataWithLength:length]; mach_vm_size_t copied = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)address, (mach_vm_size_t)length, (mach_vm_address_t)data.mutableBytes, &copied);
    if (kr != KERN_SUCCESS || copied != length) { if (error) *error = [NSString stringWithFormat:@"内存读取失败 kr=%d copied=%llu", kr, copied]; return NO; }
    if (out) *out = data; return YES;
}

static int ZNOCPOSIX(vm_prot_t prot) {
    int p = 0; if (prot & VM_PROT_READ) p |= PROT_READ; if (prot & VM_PROT_WRITE) p |= PROT_WRITE; if (prot & VM_PROT_EXECUTE) p |= PROT_EXEC; return p;
}

static BOOL ZNOCWriteNative(uintptr_t address, NSData *wanted, NSData *rollback, vm_prot_t protection, NSString **error) {
    vm_size_t page = vm_page_size; uintptr_t pageStart = address & ~((uintptr_t)page - 1u);
    uintptr_t pageEnd = (address + wanted.length + page - 1u) & ~((uintptr_t)page - 1u); size_t span = pageEnd - pageStart;
    if (mprotect((void *)pageStart, span, PROT_READ | PROT_WRITE) != 0) { if (error) *error = [NSString stringWithFormat:@"代码页改为 RW 失败 errno=%d", errno]; return NO; }
    memcpy((void *)address, wanted.bytes, wanted.length); sys_icache_invalidate((void *)address, wanted.length);
    NSData *check = nil; BOOL match = ZNOCRead(address, wanted.length, &check, NULL) && [check isEqualToData:wanted];
    if (!match && rollback.length == wanted.length) { memcpy((void *)address, rollback.bytes, rollback.length); sys_icache_invalidate((void *)address, rollback.length); }
    int restore = mprotect((void *)pageStart, span, ZNOCPOSIX(protection));
    if (!match) { if (error) *error = @"写入 read-back 不一致，已回滚"; return NO; }
    if (restore != 0) { if (error) *error = [NSString stringWithFormat:@"恢复代码页权限失败 errno=%d", errno]; return NO; }
    return YES;
}

static BOOL ZNOCWriteBestBackend(uintptr_t address, NSData *wanted, NSData *rollback, vm_prot_t protection, NSString **error) {
    ZNH5GGValueBackend *h5 = [ZNH5GGValueBackend sharedBackend];
    if (h5.available) {
        NSString *local = nil;
        if ([h5 writeRawARM64BytesAtAddress:(uint64_t)address bytes:wanted rollback:rollback error:&local]) {
            sys_icache_invalidate((void *)address, wanted.length);
            NSData *check = nil;
            if (ZNOCRead(address, wanted.length, &check, NULL) && [check isEqualToData:wanted]) return YES;
            if (error) *error = @"H5GG 写入后最终 read-back 不一致";
            return NO;
        }
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-offset] H5GG raw backend failed, fallback native: %@", local ?: @"unknown"]];
    }
    ZNExecutablePageProbe *probe = [ZNExecutablePageProbe sharedProbe];
    if ((!probe.hasRun && ![probe runProbe]) || !probe.supported) {
        if (error) *error = h5.available ? @"H5GG 写入失败且 native 代码页写入不可用" : @"H5GG 不可用，设备也不支持 native 临时代码页写入";
        return NO;
    }
    return ZNOCWriteNative(address, wanted, rollback, protection, error);
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
@property(nonatomic,assign) vm_prot_t znProtection;
@property(nonatomic,copy) NSString *znSegment;
@end

@implementation ZNPatchRuntimeValidator

+ (instancetype)sharedValidator { static ZNPatchRuntimeValidator *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [ZNPatchRuntimeValidator new]; }); return v; }
- (instancetype)init { if ((self = [super init])) { _target = @"UnityFramework"; _lastResult = @"尚未配置"; _znSegment = @"-"; } return self; }

- (BOOL)configureTarget:(NSString *)target offsetString:(NSString *)offsetString patchHex:(NSString *)patchHex error:(NSString **)error {
    @synchronized (self) {
        if (self.applied) { if (error) *error = @"请先恢复当前 Patch"; return NO; }
        NSString *name = ZNOCTrim(target); if (!name.length) { if (error) *error = @"Target 不能为空"; return NO; }
        uint64_t rva = 0; NSString *local = nil; if (!ZNOCParseRVA(offsetString, &rva, &local)) { if (error) *error = local; return NO; }
        NSData *bytes = ZNOCParseHex(patchHex, &local); if (!bytes) { if (error) *error = local; return NO; }
        self.target = name; self.rva = rva; self.patchBytes = bytes; self.capturedOriginalBytes = nil; self.currentBytes = nil; self.runtimeAddress = 0;
        self.configured = YES; self.validated = NO; self.applied = NO; self.znProtection = 0; self.znSegment = @"-"; self.lastResult = @"已配置 · 待读取验证"; return YES;
    }
}

- (BOOL)validate:(NSString **)error {
    @synchronized (self) {
        if (!self.configured || !self.patchBytes.length) { if (error) *error = @"请先配置 Offset Patch"; return NO; }
        NSDictionary *module = [[ZNModuleManager sharedManager] moduleNamed:self.target];
        if (!module) { if (error) *error = [NSString stringWithFormat:@"模块未加载：%@", self.target]; return NO; }
        NSString *canonical = [module[@"name"] isKindOfClass:NSString.class] ? module[@"name"] : nil;
        uintptr_t imageBase = (uintptr_t)[module[@"base"] unsignedLongLongValue];
        uintptr_t address = [[ZNModuleManager sharedManager] runtimeAddressForModule:self.target rva:self.rva];
        if (!imageBase || !address) { if (error) *error = @"Target + RVA 无法解析"; return NO; }
        ZNOCExecRange range = {}; NSString *local = nil;
        if (!ZNOCExecutableRange(imageBase, address, self.patchBytes.length, &range, &local)) { self.validated = NO; if (error) *error = local; return NO; }
        NSData *original = nil; if (!ZNOCRead(address, self.patchBytes.length, &original, &local)) { self.validated = NO; if (error) *error = local; return NO; }
        if (canonical.length) self.target = canonical;
        self.runtimeAddress = address; self.capturedOriginalBytes = original; self.currentBytes = original; self.znProtection = range.protection;
        self.znSegment = [NSString stringWithUTF8String:range.name] ?: @"?"; self.validated = YES; self.applied = NO;
        self.lastResult = [NSString stringWithFormat:@"验证通过 %@+0x%llX · %@ · %lu bytes", self.target, self.rva, self.znSegment, (unsigned long)self.patchBytes.length];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-offset] validated %@+0x%llX address=%p original=%@ enabled=%@", self.target, self.rva, (void *)address, ZNOCHex(original), ZNOCHex(self.patchBytes)]];
        return YES;
    }
}

- (BOOL)applyTemporary:(NSString **)error {
    @synchronized (self) {
        if (!self.validated || !self.runtimeAddress) { if (error) *error = @"请先读取验证"; return NO; }
        if (self.applied) return YES;
        NSData *now = nil; if (!ZNOCRead(self.runtimeAddress, self.patchBytes.length, &now, error)) return NO;
        if (![now isEqualToData:self.capturedOriginalBytes]) { if (error) *error = @"当前字节已变化，拒绝覆盖"; return NO; }
        if (!ZNOCWriteBestBackend(self.runtimeAddress, self.patchBytes, self.capturedOriginalBytes, self.znProtection, error)) return NO;
        self.currentBytes = self.patchBytes; self.applied = YES; self.lastResult = [ZNH5GGValueBackend sharedBackend].available ? @"临时 Patch 已应用 · H5GG" : @"临时 Patch 已应用 · Native"; return YES;
    }
}

- (BOOL)restoreOriginal:(NSString **)error {
    @synchronized (self) {
        if (!self.applied) return YES;
        NSData *now = nil; if (!ZNOCRead(self.runtimeAddress, self.patchBytes.length, &now, error)) return NO;
        if (![now isEqualToData:self.patchBytes]) { if (error) *error = @"当前字节不是本会话 Patch，拒绝覆盖"; return NO; }
        if (!ZNOCWriteBestBackend(self.runtimeAddress, self.capturedOriginalBytes, self.patchBytes, self.znProtection, error)) return NO;
        self.currentBytes = self.capturedOriginalBytes; self.applied = NO; self.lastResult = @"Original 已恢复"; return YES;
    }
}

- (void)clearSession {
    @synchronized (self) { if (self.applied) return; self.patchBytes = nil; self.capturedOriginalBytes = nil; self.currentBytes = nil; self.runtimeAddress = 0; self.configured = NO; self.validated = NO; self.znProtection = 0; self.znSegment = @"-"; self.lastResult = @"会话已清除"; }
}

- (NSArray<NSString *> *)diagnosticLines {
    return @[[NSString stringWithFormat:@"Target: %@", self.target ?: @"-"], [NSString stringWithFormat:@"RVA: 0x%llX", self.rva], [NSString stringWithFormat:@"Runtime: %p", (void *)self.runtimeAddress], [NSString stringWithFormat:@"Segment: %@", self.znSegment ?: @"-"], [NSString stringWithFormat:@"Original: %@", ZNOCHex(self.capturedOriginalBytes)], [NSString stringWithFormat:@"Enabled: %@", ZNOCHex(self.patchBytes)], [NSString stringWithFormat:@"State: configured=%@ validated=%@ applied=%@", self.configured?@"YES":@"NO", self.validated?@"YES":@"NO", self.applied?@"YES":@"NO"], [NSString stringWithFormat:@"Result: %@", self.lastResult ?: @"-"]];
}
- (NSString *)diagnosticReport { return [[self diagnosticLines] componentsJoinedByString:@"\n"]; }

@end
