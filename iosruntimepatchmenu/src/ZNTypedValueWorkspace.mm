#import "ZNTypedValueWorkspace.h"
#import "ZNPatchCore.h"

@implementation ZNTypedValueRow
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _entry = [ZNTypedValueOffset new];
    _statusText = @"待填写";
    return self;
}
@end

@interface ZNTypedValueWorkspace ()
@property(nonatomic,strong,readwrite) NSMutableArray<ZNTypedValueRow *> *rows;
@end

@implementation ZNTypedValueWorkspace

+ (instancetype)sharedWorkspace {
    static ZNTypedValueWorkspace *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZNTypedValueWorkspace new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _rows = [NSMutableArray array];
    _lastStatus = @"M5.11 Typed Value Offset";
    return self;
}

- (BOOL)hasAnyApplied {
    for (ZNTypedValueRow *row in self.rows) if (row.entry.isApplied) return YES;
    return NO;
}

- (ZNTypedValueRow *)addRow {
    ZNTypedValueRow *row = [ZNTypedValueRow new];
    NSString *mainName = [ZNModuleManager sharedManager].mainExecutable[@"name"];
    row.entry.target = mainName.length ? mainName : @"main";
    [self.rows addObject:row];
    self.lastStatus = [NSString stringWithFormat:@"已增加 Value Offset #%lu", (unsigned long)self.rows.count];
    return row;
}

- (BOOL)removeRowAtIndex:(NSUInteger)index error:(NSString **)error {
    if (index >= self.rows.count) {
        if (error) *error = @"Value Offset 不存在";
        return NO;
    }
    ZNTypedValueRow *row = self.rows[index];
    if (row.entry.isApplied) {
        if (error) *error = @"请先恢复当前 Value Offset";
        return NO;
    }
    [self.rows removeObjectAtIndex:index];
    self.lastStatus = @"已删除 Value Offset";
    return YES;
}

- (BOOL)validateRowAtIndex:(NSUInteger)index error:(NSString **)error {
    if (index >= self.rows.count) {
        if (error) *error = @"Value Offset 不存在";
        return NO;
    }
    ZNTypedValueRow *row = self.rows[index];
    NSString *local = nil;
    BOOL ok = [row.entry validate:&local];
    row.statusText = ok ? [NSString stringWithFormat:@"✅ 原值 %@ · 0x%llX", row.entry.originalValueText, row.entry.resolvedAddress]
                        : [NSString stringWithFormat:@"❌ %@", local ?: @"验证失败"];
    self.lastStatus = row.statusText;
    if (!ok && error) *error = local;
    return ok;
}

- (BOOL)applyRowAtIndex:(NSUInteger)index value:(NSString *)value error:(NSString **)error {
    if (index >= self.rows.count) {
        if (error) *error = @"Value Offset 不存在";
        return NO;
    }
    ZNTypedValueRow *row = self.rows[index];
    NSString *local = nil;
    BOOL ok = [row.entry applyValue:value error:&local];
    row.statusText = ok ? [NSString stringWithFormat:@"🟢 已应用 %@ %@", row.entry.valueType, row.entry.valueText]
                        : [NSString stringWithFormat:@"❌ %@", local ?: @"应用失败"];
    self.lastStatus = row.statusText;
    if (!ok && error) *error = local;
    return ok;
}

- (BOOL)restoreRowAtIndex:(NSUInteger)index error:(NSString **)error {
    if (index >= self.rows.count) {
        if (error) *error = @"Value Offset 不存在";
        return NO;
    }
    ZNTypedValueRow *row = self.rows[index];
    NSString *local = nil;
    BOOL ok = [row.entry restore:&local];
    row.statusText = ok ? [NSString stringWithFormat:@"↩ 已恢复 %@", row.entry.originalValueText]
                        : [NSString stringWithFormat:@"❌ %@", local ?: @"恢复失败"];
    self.lastStatus = row.statusText;
    if (!ok && error) *error = local;
    return ok;
}

- (BOOL)restoreAll:(NSString **)error {
    NSString *first = nil;
    BOOL ok = YES;
    for (ZNTypedValueRow *row in self.rows.reverseObjectEnumerator) {
        if (!row.entry.isApplied) continue;
        NSString *local = nil;
        if (![row.entry restore:&local]) {
            ok = NO;
            if (!first) first = local ?: @"恢复失败";
            row.statusText = [NSString stringWithFormat:@"❌ %@", local ?: @"恢复失败"];
        } else {
            row.statusText = [NSString stringWithFormat:@"↩ 已恢复 %@", row.entry.originalValueText];
        }
    }
    self.lastStatus = ok ? @"所有 Value Offset 已恢复" : [NSString stringWithFormat:@"恢复存在失败：%@", first ?: @"未知错误"];
    if (!ok && error) *error = first;
    return ok;
}

@end
