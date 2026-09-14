#import "ZNFeatureControlModel.h"
#import <objc/runtime.h>

NSNotificationName const ZNFeatureNumberValueDidChangeNotification = @"ZNFeatureNumberValueDidChangeNotification";
NSNotificationName const ZNFeatureSliderValueDidChangeNotification = @"ZNFeatureSliderValueDidChangeNotification";
NSNotificationName const ZNFeatureActionRequestedNotification = @"ZNFeatureActionRequestedNotification";

static const void *kZNFeatureControlTypeKey = &kZNFeatureControlTypeKey;

static NSString *ZNFCTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNFCFeatureMatches(ZNBinaryPatchRow *row, NSString *featureName) {
    NSString *wanted = ZNFCTrim(featureName);
    if (!wanted.length) return NO;
    NSString *group = ZNFCTrim(row.group);
    if (!group.length || [group caseInsensitiveCompare:@"Imported"] == NSOrderedSame) {
        group = ZNFCTrim(row.title);
    }
    return [group caseInsensitiveCompare:wanted] == NSOrderedSame;
}

NSString *ZNFeatureControlTypeName(ZNFeatureControlType type) {
    switch (type) {
        case ZNFeatureControlTypeNumber: return @"数值";
        case ZNFeatureControlTypeAction: return @"按钮";
        case ZNFeatureControlTypeSlider: return @"滑杆";
        case ZNFeatureControlTypeToggle:
        default: return @"开关";
    }
}

@implementation ZNBinaryPatchRow (ZNFeatureControlModel)

- (ZNFeatureControlType)featureControlType {
    NSNumber *value = objc_getAssociatedObject(self, kZNFeatureControlTypeKey);
    if (!value) return ZNFeatureControlTypeToggle;
    NSInteger raw = value.integerValue;
    return (raw >= ZNFeatureControlTypeToggle && raw <= ZNFeatureControlTypeSlider)
        ? (ZNFeatureControlType)raw : ZNFeatureControlTypeToggle;
}

- (void)setFeatureControlType:(ZNFeatureControlType)type {
    if (type < ZNFeatureControlTypeToggle || type > ZNFeatureControlTypeSlider) {
        type = ZNFeatureControlTypeToggle;
    }
    objc_setAssociatedObject(self, kZNFeatureControlTypeKey, @(type), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation ZNBinaryPatchWorkspace (ZNFeatureControlEditingV2)

- (ZNFeatureControlType)controlTypeForFeature:(NSString *)featureName {
    for (ZNBinaryPatchRow *row in self.rows) {
        if (ZNFCFeatureMatches(row, featureName)) return row.featureControlType;
    }
    return ZNFeatureControlTypeToggle;
}

- (BOOL)setControlType:(ZNFeatureControlType)type
            forFeature:(NSString *)featureName
                 error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) {
        if (error) *error = @"当前状态不可修改控件类型，请先恢复 Runtime Patch 或等待生成结束";
        return NO;
    }
    if (type < ZNFeatureControlTypeToggle || type > ZNFeatureControlTypeSlider) {
        if (error) *error = @"控件类型无效";
        return NO;
    }
    NSString *name = ZNFCTrim(featureName);
    if (!name.length) {
        if (error) *error = @"功能名称为空";
        return NO;
    }

    NSUInteger changed = 0;
    for (ZNBinaryPatchRow *row in self.rows) {
        if (!ZNFCFeatureMatches(row, name)) continue;
        row.featureControlType = type;
        changed++;
    }
    if (!changed) {
        if (error) *error = @"找不到要修改的功能";
        return NO;
    }
    self.lastStatus = [NSString stringWithFormat:@"%@：控件类型 → %@", name, ZNFeatureControlTypeName(type)];
    return YES;
}

- (BOOL)removeFeatureNamed:(NSString *)featureName error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) {
        if (error) *error = @"当前状态不可删除功能，请先恢复 Runtime Patch 或等待生成结束";
        return NO;
    }
    NSString *name = ZNFCTrim(featureName);
    if (!name.length) {
        if (error) *error = @"功能名称为空";
        return NO;
    }

    NSIndexSet *indexes = [self.rows indexesOfObjectsPassingTest:^BOOL(ZNBinaryPatchRow *row, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        return ZNFCFeatureMatches(row, name);
    }];
    if (!indexes.count) {
        if (error) *error = @"找不到要删除的功能";
        return NO;
    }
    NSUInteger count = indexes.count;
    [self.rows removeObjectsAtIndexes:indexes];
    [self ensureDefaultRows];
    self.lastStatus = [NSString stringWithFormat:@"已删除功能：%@（%lu Patch）", name, (unsigned long)count];
    return YES;
}

- (BOOL)removePatchAtGlobalIndex:(NSUInteger)index error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) {
        if (error) *error = @"当前状态不可删除 Patch，请先恢复 Runtime Patch 或等待生成结束";
        return NO;
    }
    if (index >= self.rows.count) {
        if (error) *error = @"Patch 索引越界";
        return NO;
    }

    ZNBinaryPatchRow *victim = self.rows[index];
    NSString *featureName = ZNFCTrim(victim.group);
    if (!featureName.length || [featureName caseInsensitiveCompare:@"Imported"] == NSOrderedSame) {
        featureName = ZNFCTrim(victim.title);
    }
    ZNFeatureControlType preservedType = [self controlTypeForFeature:featureName];
    NSString *title = ZNFCTrim(victim.title);
    if (!title.length) title = [NSString stringWithFormat:@"Patch #%lu", (unsigned long)index + 1];

    [self.rows removeObjectAtIndex:index];

    NSUInteger serial = 1;
    for (ZNBinaryPatchRow *row in self.rows) {
        if (!ZNFCFeatureMatches(row, featureName)) continue;
        row.featureControlType = preservedType;
        NSString *rowTitle = ZNFCTrim(row.title);
        if (!rowTitle.length || [rowTitle hasPrefix:@"Patch #"]) {
            row.title = [NSString stringWithFormat:@"Patch #%lu", (unsigned long)serial];
        }
        serial++;
    }
    [self ensureDefaultRows];
    self.lastStatus = [NSString stringWithFormat:@"已删除 %@ · %@", featureName.length ? featureName : @"功能", title];
    return YES;
}

@end

ZNFeatureControlType ZNFeatureControlTypeForFeatureName(NSString *featureName) {
    return [[ZNBinaryPatchWorkspace sharedWorkspace] controlTypeForFeature:featureName ?: @""];
}
