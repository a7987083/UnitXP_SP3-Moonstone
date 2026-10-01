#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchJSONImporter.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"

// M5.10.0 Offset Workspace V1
// The workspace never parses addresses. Address authority belongs exclusively to
// ZNPatchRuntimeValidator. Duplicate physical sites are rejected in V1 instead
// of reintroducing the old Shared-Site/variant merge stack.

@implementation ZNBinaryPatchRow
- (instancetype)init {
    self = [super init]; if (!self) return nil;
    _target = @""; _offsetText = @""; _enabledText = @""; _originalHex = @"";
    _title = @""; _group = @"Imported"; _sourcePath = @""; _statusText = @"";
    _validated = NO; _lowConfidence = NO; _conflict = NO;
    return self;
}
@end

static NSString *ZNOWHex(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [out appendFormat:@"%02X", bytes[i]];
    return out;
}

static NSString *ZNOWTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNOWTargetForRow(ZNBinaryPatchRow *row, NSString *fallback) {
    NSString *explicit = ZNOWTrim(row.target);
    if (row.explicitTarget && explicit.length) return explicit;
    NSString *base = ZNOWTrim(fallback);
    return base.length ? base : @"main";
}

static NSString *ZNOWSiteKey(ZNBinaryPatchRow *row) {
    ZNPatchRuntimeValidator *v = row.validator;
    if (!row.validated || !v || !v.target.length) return nil;
    return [NSString stringWithFormat:@"%@|%016llx", v.target.lowercaseString, v.rva];
}

@interface ZNBinaryPatchWorkspace ()
@property(nonatomic,strong,readwrite) NSMutableArray<ZNBinaryPatchRow *> *rows;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *jsonFiles;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *lastOutputPaths;
@end

@implementation ZNBinaryPatchWorkspace

+ (instancetype)sharedWorkspace {
    static ZNBinaryPatchWorkspace *shared; static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZNBinaryPatchWorkspace new]; });
    return shared;
}

- (instancetype)init {
    self = [super init]; if (!self) return nil;
    _rows = [NSMutableArray array]; _jsonFiles = @[]; _lastOutputPaths = @[];
    NSString *name = [ZNModuleManager sharedManager].mainExecutable[@"name"];
    if (!name.length) name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    _defaultTarget = name.length ? name : @"main";
    _lastStatus = @"M5.10 Offset Core · Switch/byte patch only";
    [self ensureDefaultRows];
    return self;
}

- (void)ensureDefaultRows {
    while (self.rows.count < 10) [self.rows addObject:[ZNBinaryPatchRow new]];
}

- (void)addEmptyRow {
    if (self.hasAnyApplied || self.isBuilding) { self.lastStatus = @"当前状态不可增加 Patch"; return; }
    [self.rows addObject:[ZNBinaryPatchRow new]];
    self.lastStatus = [NSString stringWithFormat:@"已增加 Patch #%lu", (unsigned long)self.rows.count];
}

- (void)updateOffset:(NSString *)text row:(NSUInteger)index {
    if (self.hasAnyApplied || self.isBuilding || index >= self.rows.count) return;
    ZNBinaryPatchRow *row = self.rows[index];
    row.offsetText = text ?: @""; row.validator = nil; row.validated = NO; row.originalHex = @""; row.conflict = NO; row.statusText = @"待验证";
}

- (void)updateEnabled:(NSString *)text row:(NSUInteger)index {
    if (self.hasAnyApplied || self.isBuilding || index >= self.rows.count) return;
    ZNBinaryPatchRow *row = self.rows[index];
    row.enabledText = text ?: @""; row.validator = nil; row.validated = NO; row.originalHex = @""; row.conflict = NO; row.statusText = @"待验证";
}

- (void)updateDefaultTarget:(NSString *)text {
    if (self.hasAnyApplied || self.isBuilding) return;
    NSString *target = ZNOWTrim(text);
    self.defaultTarget = target.length ? target : @"main";
    for (ZNBinaryPatchRow *row in self.rows) {
        if (!row.explicitTarget) { row.validator = nil; row.validated = NO; row.originalHex = @""; row.conflict = NO; row.statusText = @"待验证"; }
    }
}

- (void)refreshJSONFiles {
    self.jsonFiles = [ZNPatchJSONImporter discoverJSONFiles] ?: @[];
    self.lastStatus = self.jsonFiles.count
        ? [NSString stringWithFormat:@"发现 %lu 个 JSON", (unsigned long)self.jsonFiles.count]
        : @"游戏数据目录未发现 JSON";
}

- (BOOL)importJSONAtPath:(NSString *)path error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) { if (error) *error = @"当前状态不可导入"; return NO; }
    NSArray<NSDictionary *> *items = [ZNPatchJSONImporter importFile:path error:error];
    if (!items) return NO;
    NSMutableArray<ZNBinaryPatchRow *> *imported = [NSMutableArray array];
    NSMutableSet<NSString *> *targets = [NSMutableSet set];
    NSUInteger low = 0;
    for (NSDictionary *item in items) {
        ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
        row.target = [item[@"target"] isKindOfClass:NSString.class] ? item[@"target"] : @"";
        row.explicitTarget = row.target.length > 0;
        row.offsetText = [item[@"offset"] isKindOfClass:NSString.class] ? item[@"offset"] : @"";
        row.enabledText = [item[@"enabled"] isKindOfClass:NSString.class] ? item[@"enabled"] : @"";
        row.title = [item[@"title"] isKindOfClass:NSString.class] && [item[@"title"] length] ? item[@"title"] : [NSString stringWithFormat:@"Patch #%lu", (unsigned long)imported.count + 1];
        row.group = [item[@"group"] isKindOfClass:NSString.class] && [item[@"group"] length] ? item[@"group"] : @"Imported";
        row.sourcePath = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"$";
        row.lowConfidence = [item[@"confidence"] doubleValue] < 0.8;
        row.statusText = row.lowConfidence ? @"⚠ 候选 · 待读取验证" : @"待验证";
        if (row.lowConfidence) low++;
        if (row.target.length) [targets addObject:row.target];
        [imported addObject:row];
    }
    self.rows = imported; [self ensureDefaultRows];
    if (targets.count == 1) self.defaultTarget = targets.anyObject;
    self.showJSONFiles = NO;
    self.lastStatus = [NSString stringWithFormat:@"已导入 %lu 条普通 Offset Patch · 候选 %lu · JSON original 忽略", (unsigned long)items.count, (unsigned long)low];
    return YES;
}

- (NSUInteger)filledCount {
    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in self.rows) if (row.offsetText.length || row.enabledText.length) count++;
    return count;
}

- (NSUInteger)validatedCount {
    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in self.rows) if (row.validated && row.validator.isValidated) count++;
    return count;
}

- (BOOL)hasAnyApplied {
    for (ZNBinaryPatchRow *row in self.rows) if (row.validator.isApplied) return YES;
    return NO;
}

- (BOOL)validateAll:(NSString **)error {
    if (self.hasAnyApplied) { if (error) *error = @"请先恢复当前临时 Patch"; return NO; }
    NSUInteger filled = 0, ok = 0, failed = 0;
    NSString *firstError = nil;
    NSMutableDictionary<NSString *, ZNBinaryPatchRow *> *sites = [NSMutableDictionary dictionary];

    for (NSUInteger i = 0; i < self.rows.count; i++) {
        ZNBinaryPatchRow *row = self.rows[i];
        row.conflict = NO;
        if (!row.offsetText.length && !row.enabledText.length) {
            row.validator = nil; row.validated = NO; row.originalHex = @""; row.statusText = @"";
            continue;
        }
        filled++;
        if (!row.offsetText.length || !row.enabledText.length) {
            row.validator = nil; row.validated = NO; row.originalHex = @""; row.statusText = @"❌ Offset / Enabled 未填写完整";
            failed++; if (!firstError) firstError = [NSString stringWithFormat:@"#%lu 输入不完整", (unsigned long)i + 1];
            continue;
        }

        NSString *target = ZNOWTargetForRow(row, self.defaultTarget);
        ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator new];
        NSString *local = nil;
        if (![validator configureTarget:target offsetString:row.offsetText patchHex:row.enabledText error:&local] || ![validator validate:&local]) {
            row.validator = nil; row.validated = NO; row.originalHex = @""; row.statusText = [NSString stringWithFormat:@"❌ %@", local ?: @"验证失败"];
            failed++; if (!firstError) firstError = [NSString stringWithFormat:@"#%lu %@", (unsigned long)i + 1, local ?: @"验证失败"];
            continue;
        }

        row.validator = validator; row.validated = YES;
        row.offsetText = [NSString stringWithFormat:@"0x%llX", validator.rva];
        row.enabledText = ZNOWHex(validator.patchBytes);
        row.originalHex = ZNOWHex(validator.capturedOriginalBytes);
        row.statusText = row.lowConfidence ? @"✅ 已验证（候选确认）" : @"✅ 已验证";

        NSString *site = ZNOWSiteKey(row);
        ZNBinaryPatchRow *previous = site.length ? sites[site] : nil;
        if (previous) {
            previous.conflict = YES; row.conflict = YES;
            previous.statusText = @"❌ M5.10 V1 不允许同一物理 Offset 多 Variant";
            row.statusText = previous.statusText;
            previous.validated = NO; row.validated = NO;
            failed++; if (ok) ok--;
            if (!firstError) firstError = [NSString stringWithFormat:@"重复物理 Offset：%@+0x%llX", validator.target, validator.rva];
        } else {
            if (site.length) sites[site] = row;
            ok++;
        }
    }

    if (!filled) { self.lastStatus = @"没有填写 Patch"; if (error) *error = self.lastStatus; return NO; }
    self.lastStatus = [NSString stringWithFormat:@"M5.10 读取验证：%lu/%lu 通过%@", (unsigned long)ok, (unsigned long)filled,
                       failed ? [NSString stringWithFormat:@" · %lu 失败", (unsigned long)failed] : @""];
    if (failed) { if (error) *error = firstError ?: @"存在验证失败项"; return NO; }
    return YES;
}

- (BOOL)applyAll:(NSString **)error {
    if (!self.filledCount) { if (error) *error = @"没有填写 Patch"; return NO; }
    if (self.hasAnyApplied) { if (error) *error = @"已有临时 Patch，请先恢复"; return NO; }
    if (self.validatedCount != self.filledCount) {
        NSString *local = nil; if (![self validateAll:&local]) { if (error) *error = local; return NO; }
    }

    NSMutableArray<ZNPatchRuntimeValidator *> *applied = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.rows.count; i++) {
        ZNBinaryPatchRow *row = self.rows[i];
        if (!row.offsetText.length && !row.enabledText.length) continue;
        NSString *local = nil;
        if (!row.validated || !row.validator || ![row.validator applyTemporary:&local]) {
            for (ZNPatchRuntimeValidator *validator in applied.reverseObjectEnumerator) [validator restoreOriginal:NULL];
            self.lastStatus = [NSString stringWithFormat:@"临时应用失败 #%lu：%@ · 已回滚", (unsigned long)i + 1, local ?: @"未知错误"];
            if (error) *error = self.lastStatus;
            return NO;
        }
        [applied addObject:row.validator]; row.statusText = @"🟢 临时已应用";
    }
    self.lastStatus = [NSString stringWithFormat:@"临时应用成功：%lu 条", (unsigned long)applied.count];
    return YES;
}

- (BOOL)restoreAll:(NSString **)error {
    NSString *first = nil; BOOL ok = YES; NSUInteger restored = 0;
    for (ZNBinaryPatchRow *row in self.rows.reverseObjectEnumerator) {
        if (!row.validator.isApplied) continue;
        NSString *local = nil;
        if (![row.validator restoreOriginal:&local]) { ok = NO; if (!first) first = local ?: @"恢复失败"; row.statusText = @"❌ 恢复失败"; }
        else { restored++; row.statusText = row.validated ? @"✅ 已验证" : @"待验证"; }
    }
    self.lastStatus = ok ? [NSString stringWithFormat:@"已恢复 %lu 条 Offset Patch", (unsigned long)restored]
                         : [NSString stringWithFormat:@"恢复存在失败：%@", first ?: @"未知错误"];
    if (!ok && error) *error = first;
    return ok;
}

- (void)setBuildOutputs:(NSArray<NSString *> *)paths status:(NSString *)status {
    self.lastOutputPaths = paths ?: @[];
    self.lastStatus = status ?: @"";
}

@end
