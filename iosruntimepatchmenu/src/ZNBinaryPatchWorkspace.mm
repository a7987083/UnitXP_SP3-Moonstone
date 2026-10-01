#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchJSONImporter.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNTypedValueOffset.h"
#import "ZNPatchCore.h"

@implementation ZNBinaryPatchRow
- (instancetype)init {
    self = [super init]; if (!self) return nil;
    _target = @""; _offsetText = @""; _enabledText = @""; _originalHex = @"";
    _title = @""; _group = @"Imported"; _sourcePath = @""; _statusText = @"";
    _validated = NO; _lowConfidence = NO; _conflict = NO;
    _controlKind = ZNOffsetControlKindSwitch;
    _valueType = @"F32"; _minValue = 0.0; _maxValue = 10.0; _stepValue = 1.0;
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
    NSString *explicitTargetName = ZNOWTrim(row.target);
    if (row.explicitTarget && explicitTargetName.length) return explicitTargetName;
    NSString *base = ZNOWTrim(fallback);
    return base.length ? base : @"main";
}

static BOOL ZNOWRowFilled(ZNBinaryPatchRow *row) {
    return row.offsetText.length || row.enabledText.length;
}

static void ZNOWClearValidation(ZNBinaryPatchRow *row) {
    row.validator = nil;
    row.typedEntry = nil;
    row.validated = NO;
    row.originalHex = @"";
    row.conflict = NO;
    row.statusText = @"待验证";
}

static NSString *ZNOWSiteKey(ZNBinaryPatchRow *row) {
    if (!row.validated) return nil;
    if (row.controlKind == ZNOffsetControlKindSwitch) {
        ZNPatchRuntimeValidator *v = row.validator;
        if (!v || !v.target.length) return nil;
        return [NSString stringWithFormat:@"%@|%016llx", v.target.lowercaseString, v.rva];
    }
    ZNTypedValueOffset *t = row.typedEntry;
    if (!t || !t.target.length) return nil;
    return [NSString stringWithFormat:@"%@|%016llx", t.target.lowercaseString, t.rva];
}

static ZNTypedValueOffset *ZNOWMakeTypedEntry(ZNBinaryPatchRow *row, NSString *target) {
    ZNTypedValueOffset *entry = [ZNTypedValueOffset new];
    entry.title = row.group.length ? row.group : (row.title.length ? row.title : @"Value");
    entry.target = target;
    entry.offsetText = row.offsetText ?: @"";
    entry.valueType = row.valueType.length ? row.valueType : @"F32";
    entry.controlKind = row.controlKind == ZNOffsetControlKindNumber ? ZNTypedValueControlKindNumber : ZNTypedValueControlKindSlider;
    entry.valueText = row.enabledText.length ? row.enabledText : @"0";
    entry.minValue = row.minValue;
    entry.maxValue = row.maxValue;
    entry.stepValue = row.stepValue;
    return entry;
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
    _lastStatus = @"M5.11 Unified Offset · Switch / Slider / Number";
    [self ensureDefaultRows];
    return self;
}

- (void)ensureDefaultRows { while (self.rows.count < 10) [self.rows addObject:[ZNBinaryPatchRow new]]; }

- (void)addEmptyRow {
    if (self.hasAnyApplied || self.isBuilding) { self.lastStatus = @"当前状态不可增加 Offset"; return; }
    [self.rows addObject:[ZNBinaryPatchRow new]];
    self.lastStatus = [NSString stringWithFormat:@"已增加 Offset #%lu", (unsigned long)self.rows.count];
}

- (void)updateOffset:(NSString *)text row:(NSUInteger)index {
    if (self.hasAnyApplied || self.isBuilding || index >= self.rows.count) return;
    ZNBinaryPatchRow *row = self.rows[index]; row.offsetText = text ?: @""; ZNOWClearValidation(row);
}

- (void)updateEnabled:(NSString *)text row:(NSUInteger)index {
    if (self.hasAnyApplied || self.isBuilding || index >= self.rows.count) return;
    ZNBinaryPatchRow *row = self.rows[index]; row.enabledText = text ?: @""; ZNOWClearValidation(row);
}

- (void)updateDefaultTarget:(NSString *)text {
    if (self.hasAnyApplied || self.isBuilding) return;
    NSString *target = ZNOWTrim(text); self.defaultTarget = target.length ? target : @"main";
    for (ZNBinaryPatchRow *row in self.rows) if (!row.explicitTarget) ZNOWClearValidation(row);
}

- (void)refreshJSONFiles {
    self.jsonFiles = [ZNPatchJSONImporter discoverJSONFiles] ?: @[];
    self.lastStatus = self.jsonFiles.count ? [NSString stringWithFormat:@"发现 %lu 个 JSON", (unsigned long)self.jsonFiles.count] : @"游戏数据目录未发现 JSON";
}

- (BOOL)importJSONAtPath:(NSString *)path error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) { if (error) *error = @"当前状态不可导入"; return NO; }
    NSArray<NSDictionary *> *items = [ZNPatchJSONImporter importFile:path error:error]; if (!items) return NO;
    NSMutableArray<ZNBinaryPatchRow *> *imported = [NSMutableArray array]; NSMutableSet<NSString *> *targets = [NSMutableSet set]; NSUInteger low = 0;
    for (NSDictionary *item in items) {
        ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
        row.target = [item[@"target"] isKindOfClass:NSString.class] ? item[@"target"] : @""; row.explicitTarget = row.target.length > 0;
        row.offsetText = [item[@"offset"] isKindOfClass:NSString.class] ? item[@"offset"] : @"";
        row.enabledText = [item[@"enabled"] isKindOfClass:NSString.class] ? item[@"enabled"] : @"";
        row.title = [item[@"title"] isKindOfClass:NSString.class] && [item[@"title"] length] ? item[@"title"] : [NSString stringWithFormat:@"Patch #%lu", (unsigned long)imported.count + 1];
        row.group = [item[@"group"] isKindOfClass:NSString.class] && [item[@"group"] length] ? item[@"group"] : @"Imported";
        row.sourcePath = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"$";
        row.lowConfidence = [item[@"confidence"] doubleValue] < 0.8; row.statusText = row.lowConfidence ? @"⚠ 候选 · 待读取验证" : @"待验证";
        if (row.lowConfidence) low++; if (row.target.length) [targets addObject:row.target]; [imported addObject:row];
    }
    self.rows = imported; [self ensureDefaultRows]; if (targets.count == 1) self.defaultTarget = targets.anyObject; self.showJSONFiles = NO;
    self.lastStatus = [NSString stringWithFormat:@"已导入 %lu 条 Offset · 候选 %lu", (unsigned long)items.count, (unsigned long)low]; return YES;
}

- (NSUInteger)filledCount { NSUInteger count = 0; for (ZNBinaryPatchRow *row in self.rows) if (ZNOWRowFilled(row)) count++; return count; }

- (NSUInteger)validatedCount {
    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in self.rows) {
        BOOL ok = row.controlKind == ZNOffsetControlKindSwitch ? row.validator.isValidated : row.typedEntry.isValidated;
        if (row.validated && ok) count++;
    }
    return count;
}

- (BOOL)hasAnyApplied {
    for (ZNBinaryPatchRow *row in self.rows) {
        if (row.validator.isApplied || row.typedEntry.isApplied) return YES;
    }
    return NO;
}

- (BOOL)validateAll:(NSString **)error {
    if (self.hasAnyApplied) { if (error) *error = @"请先恢复当前临时修改"; return NO; }
    NSUInteger filled = 0, ok = 0, failed = 0; NSString *firstError = nil; NSMutableDictionary<NSString *, ZNBinaryPatchRow *> *sites = [NSMutableDictionary dictionary];

    for (NSUInteger i = 0; i < self.rows.count; i++) {
        ZNBinaryPatchRow *row = self.rows[i]; row.conflict = NO;
        if (!ZNOWRowFilled(row)) { row.validator = nil; row.typedEntry = nil; row.validated = NO; row.originalHex = @""; row.statusText = @""; continue; }
        filled++;
        if (!row.offsetText.length || !row.enabledText.length) {
            ZNOWClearValidation(row); row.statusText = row.controlKind == ZNOffsetControlKindSwitch ? @"❌ Offset / Patch 未填写完整" : @"❌ Offset / Value 未填写完整";
            failed++; if (!firstError) firstError = [NSString stringWithFormat:@"#%lu 输入不完整", (unsigned long)i + 1]; continue;
        }

        NSString *target = ZNOWTargetForRow(row, self.defaultTarget); NSString *local = nil;
        if (row.controlKind == ZNOffsetControlKindSwitch) {
            ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator new];
            if (![validator configureTarget:target offsetString:row.offsetText patchHex:row.enabledText error:&local] || ![validator validate:&local]) {
                ZNOWClearValidation(row); row.statusText = [NSString stringWithFormat:@"❌ %@", local ?: @"验证失败"]; failed++; if (!firstError) firstError = [NSString stringWithFormat:@"#%lu %@", (unsigned long)i + 1, local ?: @"验证失败"]; continue;
            }
            row.validator = validator; row.typedEntry = nil; row.validated = YES; row.offsetText = [NSString stringWithFormat:@"0x%llX", validator.rva]; row.enabledText = ZNOWHex(validator.patchBytes); row.originalHex = ZNOWHex(validator.capturedOriginalBytes);
        } else {
            ZNTypedValueOffset *entry = ZNOWMakeTypedEntry(row, target);
            if (![entry validate:&local]) {
                ZNOWClearValidation(row); row.statusText = [NSString stringWithFormat:@"❌ %@", local ?: @"Typed Value 验证失败"]; failed++; if (!firstError) firstError = [NSString stringWithFormat:@"#%lu %@", (unsigned long)i + 1, local ?: @"验证失败"]; continue;
            }
            row.typedEntry = entry; row.validator = nil; row.validated = YES; row.offsetText = [NSString stringWithFormat:@"0x%llX", entry.rva]; row.originalHex = entry.originalValueText ?: @"";
        }
        row.statusText = row.lowConfidence ? @"✅ 已验证（候选确认）" : @"✅ 已验证";

        NSString *site = ZNOWSiteKey(row); ZNBinaryPatchRow *previous = site.length ? sites[site] : nil;
        if (previous) {
            previous.conflict = YES; row.conflict = YES; previous.statusText = @"❌ 同一物理 Offset 重复"; row.statusText = previous.statusText; previous.validated = NO; row.validated = NO; failed++; if (ok) ok--; if (!firstError) firstError = @"重复物理 Offset";
        } else { if (site.length) sites[site] = row; ok++; }
    }

    if (!filled) { self.lastStatus = @"没有填写 Offset"; if (error) *error = self.lastStatus; return NO; }
    self.lastStatus = [NSString stringWithFormat:@"M5.11 读取验证：%lu/%lu 通过%@", (unsigned long)ok, (unsigned long)filled, failed ? [NSString stringWithFormat:@" · %lu 失败", (unsigned long)failed] : @""];
    if (failed) { if (error) *error = firstError ?: @"存在验证失败项"; return NO; } return YES;
}

- (BOOL)applyAll:(NSString **)error {
    if (!self.filledCount) { if (error) *error = @"没有填写 Offset"; return NO; }
    if (self.hasAnyApplied) { if (error) *error = @"已有临时修改，请先恢复"; return NO; }
    if (self.validatedCount != self.filledCount) { NSString *local = nil; if (![self validateAll:&local]) { if (error) *error = local; return NO; } }

    NSMutableArray<ZNBinaryPatchRow *> *applied = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.rows.count; i++) {
        ZNBinaryPatchRow *row = self.rows[i]; if (!ZNOWRowFilled(row)) continue; NSString *local = nil; BOOL success = NO;
        if (row.controlKind == ZNOffsetControlKindSwitch) success = row.validated && row.validator && [row.validator applyTemporary:&local];
        else success = row.validated && row.typedEntry && [row.typedEntry applyValue:row.enabledText error:&local];
        if (!success) {
            for (ZNBinaryPatchRow *done in applied.reverseObjectEnumerator) {
                if (done.controlKind == ZNOffsetControlKindSwitch) [done.validator restoreOriginal:NULL]; else [done.typedEntry restore:NULL];
            }
            self.lastStatus = [NSString stringWithFormat:@"临时应用失败 #%lu：%@ · 已回滚", (unsigned long)i + 1, local ?: @"未知错误"]; if (error) *error = self.lastStatus; return NO;
        }
        [applied addObject:row]; row.statusText = @"🟢 临时已应用";
    }
    self.lastStatus = [NSString stringWithFormat:@"临时应用成功：%lu 条", (unsigned long)applied.count]; return YES;
}

- (BOOL)restoreAll:(NSString **)error {
    NSString *first = nil; BOOL ok = YES; NSUInteger restored = 0;
    for (ZNBinaryPatchRow *row in self.rows.reverseObjectEnumerator) {
        BOOL applied = row.controlKind == ZNOffsetControlKindSwitch ? row.validator.isApplied : row.typedEntry.isApplied; if (!applied) continue;
        NSString *local = nil; BOOL success = row.controlKind == ZNOffsetControlKindSwitch ? [row.validator restoreOriginal:&local] : [row.typedEntry restore:&local];
        if (!success) { ok = NO; if (!first) first = local ?: @"恢复失败"; row.statusText = @"❌ 恢复失败"; }
        else { restored++; row.statusText = row.validated ? @"✅ 已验证" : @"待验证"; }
    }
    self.lastStatus = ok ? [NSString stringWithFormat:@"已恢复 %lu 条 Offset 修改", (unsigned long)restored] : [NSString stringWithFormat:@"恢复存在失败：%@", first ?: @"未知错误"];
    if (!ok && error) *error = first; return ok;
}

- (void)setBuildOutputs:(NSArray<NSString *> *)paths status:(NSString *)status { self.lastOutputPaths = paths ?: @[]; self.lastStatus = status ?: @""; }

@end
