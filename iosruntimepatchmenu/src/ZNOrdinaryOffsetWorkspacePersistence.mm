#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNPatchCore.h"

static NSString * const kZNWorkspaceDefaultsKey = @"zonoe.ordinary-offset-authoring.v1";
static BOOL gZNWorkspaceRestoring = NO;

static NSString *ZNWPTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNWPRowHasAuthoringData(ZNBinaryPatchRow *row) {
    if (row.explicitTarget || row.target.length || row.offsetText.length || row.enabledText.length || row.title.length) return YES;
    NSString *group = ZNWPTrim(row.group);
    return group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame;
}

static void ZNWPSave(ZNBinaryPatchWorkspace *workspace) {
    if (!workspace || gZNWorkspaceRestoring) return;
    NSMutableArray *items = [NSMutableArray array];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZNWPRowHasAuthoringData(row)) continue;
        [items addObject:@{
            @"target": row.target ?: @"",
            @"explicitTarget": @(row.explicitTarget),
            @"offset": row.offsetText ?: @"",
            @"patch": row.enabledText ?: @"",
            @"title": row.title ?: @"",
            @"group": row.group ?: @"Imported",
            @"sourcePath": row.sourcePath ?: @"",
            @"lowConfidence": @(row.lowConfidence),
            @"controlType": @((NSInteger)row.featureControlType),
            @"valueType": @((NSInteger)row.featureValueType),
        }];
    }
    NSDictionary *root = @{
        @"version": @1,
        @"defaultTarget": workspace.defaultTarget ?: @"main",
        @"rows": items,
    };
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNWorkspaceDefaultsKey];
}

static void ZNWPRestore(ZNBinaryPatchWorkspace *workspace) {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults objectForKey:kZNWorkspaceDefaultsKey];
    if (![root isKindOfClass:NSDictionary.class] || [root[@"version"] integerValue] != 1) return;
    NSArray *items = [root[@"rows"] isKindOfClass:NSArray.class] ? root[@"rows"] : nil;
    if (!items.count) return;

    gZNWorkspaceRestoring = YES;
    [workspace.rows removeAllObjects];
    NSString *defaultTarget = [root[@"defaultTarget"] isKindOfClass:NSString.class] ? root[@"defaultTarget"] : @"";
    if (defaultTarget.length) workspace.defaultTarget = defaultTarget;

    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
        row.target = [item[@"target"] isKindOfClass:NSString.class] ? item[@"target"] : @"";
        row.explicitTarget = [item[@"explicitTarget"] boolValue];
        row.offsetText = [item[@"offset"] isKindOfClass:NSString.class] ? item[@"offset"] : @"";
        row.enabledText = [item[@"patch"] isKindOfClass:NSString.class] ? item[@"patch"] : @"";
        row.title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"";
        row.group = [item[@"group"] isKindOfClass:NSString.class] ? item[@"group"] : @"Imported";
        row.sourcePath = [item[@"sourcePath"] isKindOfClass:NSString.class] ? item[@"sourcePath"] : @"";
        row.lowConfidence = [item[@"lowConfidence"] boolValue];
        NSInteger controlType = [item[@"controlType"] integerValue];
        NSInteger valueType = [item[@"valueType"] integerValue];
        if (controlType >= ZNFeatureControlTypeSwitch && controlType <= ZNFeatureControlTypeNumber) row.featureControlType = (ZNFeatureControlType)controlType;
        if (valueType >= ZNValueTypeAuto && valueType <= ZNValueTypeF64) row.featureValueType = (ZNValueType)valueType;
        row.validated = NO;
        row.validator = nil;
        row.originalHex = @"";
        row.statusText = @"已恢复制作数据";
        [workspace.rows addObject:row];
    }
    [workspace ensureDefaultRows];
    workspace.lastStatus = [NSString stringWithFormat:@"已恢复普通 Offset 制作进度：%lu 项", (unsigned long)items.count];
    gZNWorkspaceRestoring = NO;
}

@interface ZNBinaryPatchWorkspace (ZNWorkspacePersistence)
- (void)znwp_updateOffset:(NSString *)text row:(NSUInteger)index;
- (void)znwp_updateEnabled:(NSString *)text row:(NSUInteger)index;
- (void)znwp_updateDefaultTarget:(NSString *)text;
- (BOOL)znwp_importJSONAtPath:(NSString *)path error:(NSString **)error;
- (NSString *)znwp_addFeature;
- (void)znwp_addPatchToFeature:(NSString *)featureName;
- (BOOL)znwp_renameFeature:(NSString *)oldName to:(NSString *)newName error:(NSString **)error;
- (BOOL)znwp_setControlType:(ZNFeatureControlType)type forFeature:(NSString *)featureName error:(NSString **)error;
- (BOOL)znwp_setValueType:(ZNValueType)type forFeature:(NSString *)featureName error:(NSString **)error;
- (BOOL)znwp_removeFeatureNamed:(NSString *)featureName error:(NSString **)error;
- (BOOL)znwp_removePatchAtGlobalIndex:(NSUInteger)index error:(NSString **)error;
@end

@implementation ZNBinaryPatchWorkspace (ZNWorkspacePersistence)
- (void)znwp_updateOffset:(NSString *)text row:(NSUInteger)index { [self znwp_updateOffset:text row:index]; ZNWPSave(self); }
- (void)znwp_updateEnabled:(NSString *)text row:(NSUInteger)index { [self znwp_updateEnabled:text row:index]; ZNWPSave(self); }
- (void)znwp_updateDefaultTarget:(NSString *)text { [self znwp_updateDefaultTarget:text]; ZNWPSave(self); }
- (BOOL)znwp_importJSONAtPath:(NSString *)path error:(NSString **)error { BOOL ok=[self znwp_importJSONAtPath:path error:error]; if(ok)ZNWPSave(self); return ok; }
- (NSString *)znwp_addFeature { NSString *name=[self znwp_addFeature]; if(name.length)ZNWPSave(self); return name; }
- (void)znwp_addPatchToFeature:(NSString *)featureName { [self znwp_addPatchToFeature:featureName]; ZNWPSave(self); }
- (BOOL)znwp_renameFeature:(NSString *)oldName to:(NSString *)newName error:(NSString **)error { BOOL ok=[self znwp_renameFeature:oldName to:newName error:error]; if(ok)ZNWPSave(self); return ok; }
- (BOOL)znwp_setControlType:(ZNFeatureControlType)type forFeature:(NSString *)featureName error:(NSString **)error { BOOL ok=[self znwp_setControlType:type forFeature:featureName error:error]; if(ok)ZNWPSave(self); return ok; }
- (BOOL)znwp_setValueType:(ZNValueType)type forFeature:(NSString *)featureName error:(NSString **)error { BOOL ok=[self znwp_setValueType:type forFeature:featureName error:error]; if(ok)ZNWPSave(self); return ok; }
- (BOOL)znwp_removeFeatureNamed:(NSString *)featureName error:(NSString **)error { BOOL ok=[self znwp_removeFeatureNamed:featureName error:error]; if(ok)ZNWPSave(self); return ok; }
- (BOOL)znwp_removePatchAtGlobalIndex:(NSUInteger)index error:(NSString **)error { BOOL ok=[self znwp_removePatchAtGlobalIndex:index error:error]; if(ok)ZNWPSave(self); return ok; }
@end

static void ZNWPSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallOrdinaryOffsetWorkspacePersistenceDeferred(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = ZNBinaryPatchWorkspace.class;
        ZNWPSwap(cls, @selector(updateOffset:row:), @selector(znwp_updateOffset:row:));
        ZNWPSwap(cls, @selector(updateEnabled:row:), @selector(znwp_updateEnabled:row:));
        ZNWPSwap(cls, @selector(updateDefaultTarget:), @selector(znwp_updateDefaultTarget:));
        ZNWPSwap(cls, @selector(importJSONAtPath:error:), @selector(znwp_importJSONAtPath:error:));
        ZNWPSwap(cls, @selector(addFeature), @selector(znwp_addFeature));
        ZNWPSwap(cls, @selector(addPatchToFeature:), @selector(znwp_addPatchToFeature:));
        ZNWPSwap(cls, @selector(renameFeature:to:error:), @selector(znwp_renameFeature:to:error:));
        ZNWPSwap(cls, @selector(setControlType:forFeature:error:), @selector(znwp_setControlType:forFeature:error:));
        ZNWPSwap(cls, @selector(setValueType:forFeature:error:), @selector(znwp_setValueType:forFeature:error:));
        ZNWPSwap(cls, @selector(removeFeatureNamed:error:), @selector(znwp_removeFeatureNamed:error:));
        ZNWPSwap(cls, @selector(removePatchAtGlobalIndex:error:), @selector(znwp_removePatchAtGlobalIndex:error:));
        ZNWPRestore([ZNBinaryPatchWorkspace sharedWorkspace]);
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.12-offset-persistence] ordinary Offset authoring workspace persistence installed"];
    });
}
