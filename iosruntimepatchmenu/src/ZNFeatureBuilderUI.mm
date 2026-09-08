#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// ZonoPatch v0.5 Feature/Patch Builder UI.
//
// `其他` is the developer authoring surface:
//   Feature -> one or more Patch rows -> validate -> temporary test -> build.
// JSON is only an optional import source. Once built, Feature metadata and
// Static Dispatch records are embedded in the generated Mach-O and runtime no
// longer needs the JSON file.

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UITextField *)zn44_field:(CGRect)frame text:(NSString *)text placeholder:(NSString *)placeholder tag:(NSInteger)tag enabled:(BOOL)enabled;
- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn44_renderOther;
- (void)zn44_importJSON:(id)sender;
- (void)zn44_jsonTapped:(UIButton *)sender;
- (void)zn44_validateAll:(id)sender;
- (void)zn44_applyAll:(id)sender;
- (void)zn44_restoreAll:(id)sender;
- (void)zn44_buildBinary:(id)sender;
@end

static const void *kZN50BExpandedFeatureKeys = &kZN50BExpandedFeatureKeys;
static const NSInteger kZN50BExpandTagBase = 460000;
static const NSInteger kZN50BAddPatchTagBase = 461000;
static const NSInteger kZN50BRenameTagBase = 462000;

static NSString *ZN50BTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN50BFeatureKey(NSString *name) {
    return ZN50BTrim(name).lowercaseString;
}

static void ZN50BNormalizeImportedGroups(ZNBinaryPatchWorkspace *workspace) {
    for (ZNBinaryPatchRow *row in workspace.rows) {
        NSString *group = ZN50BTrim(row.group);
        NSString *title = ZN50BTrim(row.title);
        if ((!group.length || [group caseInsensitiveCompare:@"Imported"] == NSOrderedSame) && title.length) {
            // Legacy/universal JSON often has only a feature/title field. Make
            // that title the durable group name so Builder writes it into the
            // Static Dispatch table and runtime can expose one Feature switch.
            row.group = title;
        }
    }
}

static BOOL ZN50BRowVisible(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *group = ZN50BTrim(row.group);
    NSString *title = ZN50BTrim(row.title);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return YES;
    return title.length > 0;
}

static NSArray<NSDictionary *> *ZN50BFeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    ZN50BNormalizeImportedGroups(workspace);
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNBinaryPatchRow *> *> *rowsByKey = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *nameByKey = [NSMutableDictionary dictionary];

    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZN50BRowVisible(row)) continue;
        NSString *name = ZN50BTrim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"] == NSOrderedSame) {
            name = ZN50BTrim(row.title);
        }
        if (!name.length) name = @"未命名功能";
        NSString *key = ZN50BFeatureKey(name);
        if (!rowsByKey[key]) {
            rowsByKey[key] = [NSMutableArray array];
            nameByKey[key] = name;
            [order addObject:key];
        }
        [rowsByKey[key] addObject:row];
    }

    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        [out addObject:@{
            @"key": key,
            @"name": nameByKey[key] ?: @"Feature",
            @"rows": [rowsByKey[key] copy] ?: @[],
        }];
    }
    return out;
}

static NSMutableSet<NSString *> *ZN50BExpandedKeys(ZNRuntimeMenuControllerV040 *controller) {
    NSMutableSet<NSString *> *set = objc_getAssociatedObject(controller, kZN50BExpandedFeatureKeys);
    if (!set) {
        set = [NSMutableSet set];
        objc_setAssociatedObject(controller, kZN50BExpandedFeatureKeys, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return set;
}

@implementation ZNBinaryPatchWorkspace (ZNFeatureEditing)

- (NSString *)addFeature {
    if (self.hasAnyApplied || self.isBuilding) {
        self.lastStatus = @"当前状态不可增加功能，请先恢复 Runtime Patch 或等待生成结束";
        return @"";
    }

    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (ZNBinaryPatchRow *row in self.rows) {
        NSString *group = ZN50BTrim(row.group);
        if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) {
            [used addObject:group.lowercaseString];
        }
    }

    NSUInteger serial = 1;
    NSString *name = nil;
    do {
        name = [NSString stringWithFormat:@"新功能 %lu", (unsigned long)serial++];
    } while ([used containsObject:name.lowercaseString]);

    ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
    row.group = name;
    row.title = @"Patch #1";
    row.statusText = @"待填写";
    [self.rows addObject:row];
    self.lastStatus = [NSString stringWithFormat:@"已增加功能：%@", name];
    return name;
}

- (void)addPatchToFeature:(NSString *)featureName {
    if (self.hasAnyApplied || self.isBuilding) {
        self.lastStatus = @"当前状态不可增加 Patch，请先恢复 Runtime Patch 或等待生成结束";
        return;
    }
    NSString *name = ZN50BTrim(featureName);
    if (!name.length) return;

    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in self.rows) {
        if ([ZN50BTrim(row.group) caseInsensitiveCompare:name] == NSOrderedSame) count++;
    }

    ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
    row.group = name;
    row.title = [NSString stringWithFormat:@"Patch #%lu", (unsigned long)count + 1];
    row.statusText = @"待填写";
    [self.rows addObject:row];
    self.lastStatus = [NSString stringWithFormat:@"%@：已增加 Patch #%lu", name, (unsigned long)count + 1];
}

- (BOOL)renameFeature:(NSString *)oldName to:(NSString *)newName error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) {
        if (error) *error = @"当前状态不可重命名功能";
        return NO;
    }
    NSString *oldValue = ZN50BTrim(oldName);
    NSString *newValue = ZN50BTrim(newName);
    if (!newValue.length) {
        if (error) *error = @"功能名称不能为空";
        return NO;
    }
    if ([oldValue caseInsensitiveCompare:newValue] == NSOrderedSame) return YES;

    for (ZNBinaryPatchRow *row in self.rows) {
        NSString *group = ZN50BTrim(row.group);
        if ([group caseInsensitiveCompare:newValue] == NSOrderedSame &&
            [group caseInsensitiveCompare:oldValue] != NSOrderedSame) {
            if (error) *error = @"已存在同名功能，避免意外合并";
            return NO;
        }
    }

    BOOL changed = NO;
    for (ZNBinaryPatchRow *row in self.rows) {
        if ([ZN50BTrim(row.group) caseInsensitiveCompare:oldValue] == NSOrderedSame) {
            row.group = newValue;
            changed = YES;
        }
    }
    if (!changed) {
        if (error) *error = @"找不到要重命名的功能";
        return NO;
    }
    self.lastStatus = [NSString stringWithFormat:@"功能已重命名：%@ → %@", oldValue, newValue];
    return YES;
}

@end

@interface ZNRuntimeMenuControllerV040 (ZNFeatureBuilderUI)
- (void)zn50b_renderOther;
- (void)zn50b_expandFeature:(UIButton *)sender;
- (void)zn50b_addFeature:(id)sender;
- (void)zn50b_addPatch:(UIButton *)sender;
- (void)zn50b_featureNameEnd:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureBuilderUI)

- (void)zn50b_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 9.0;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    [workspace ensureDefaultRows];
    ZN50BNormalizeImportedGroups(workspace);
    BOOL locked = workspace.hasAnyApplied || workspace.isBuilding;

    // Target + JSON import. JSON is authoring-time only; it is not a runtime dependency.
    UIView *targetCard = [self cardAtY:y height:56 width:width compact:NO];
    UILabel *binaryLabel = [self label:@"二进制" size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    binaryLabel.frame = CGRectMake(13, 11, 50, 32);
    [targetCard addSubview:binaryLabel];
    CGFloat importW = 78.0;
    UITextField *target = [self zn44_field:CGRectMake(65, 11, targetCard.bounds.size.width - 65 - importW - 18, 32)
                                        text:workspace.defaultTarget
                                 placeholder:@"UnityFramework"
                                         tag:440000
                                     enabled:!locked];
    [targetCard addSubview:target];
    UIButton *import = [self zn40_button:(workspace.showJSONFiles ? @"收起 JSON" : @"导入 JSON")
                                selector:@selector(zn44_importJSON:)
                                   frame:CGRectMake(targetCard.bounds.size.width - importW - 9, 11, importW, 32)];
    import.enabled = !locked;
    [targetCard addSubview:import];
    [self.contentView addSubview:targetCard];
    y += 64;

    if (workspace.showJSONFiles) {
        NSUInteger shown = workspace.jsonFiles.count;
        CGFloat h = 32.0 + shown * 34.0;
        UIView *jsonCard = [self cardAtY:y height:h width:width compact:NO];
        UILabel *title = [self label:[NSString stringWithFormat:@"与 1 同目录 JSON · %lu", (unsigned long)shown]
                                  size:10.5
                                weight:UIFontWeightSemibold
                                 color:self.theme.primaryTextColor];
        title.frame = CGRectMake(13, 7, jsonCard.bounds.size.width - 26, 17);
        [jsonCard addSubview:title];
        for (NSUInteger i = 0; i < shown; i++) {
            NSString *path = workspace.jsonFiles[i];
            UIButton *button = [self zn40_button:path.lastPathComponent
                                        selector:@selector(zn44_jsonTapped:)
                                           frame:CGRectMake(13, 27 + i * 34, jsonCard.bounds.size.width - 26, 28)];
            button.tag = 446000 + (NSInteger)i;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [jsonCard addSubview:button];
        }
        [self.contentView addSubview:jsonCard];
        y += h + 8;
    }

    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    NSMutableSet<NSString *> *expanded = ZN50BExpandedKeys(self);

    for (NSUInteger featureIndex = 0; featureIndex < features.count; featureIndex++) {
        NSDictionary *feature = features[featureIndex];
        NSString *key = feature[@"key"];
        NSString *name = feature[@"name"];
        NSArray<ZNBinaryPatchRow *> *rows = feature[@"rows"];
        BOOL isExpanded = [expanded containsObject:key];

        UIView *featureCard = [self cardAtY:y height:48 width:width compact:NO];
        UILabel *featureName = [self label:name size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        featureName.frame = CGRectMake(13, 8, featureCard.bounds.size.width - 142, 30);
        featureName.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [featureCard addSubview:featureName];

        NSString *countTitle = [NSString stringWithFormat:@"%lu Patch %@", (unsigned long)rows.count, isExpanded ? @"▲" : @"▼"];
        UIButton *expand = [self zn40_button:countTitle
                                    selector:@selector(zn50b_expandFeature:)
                                       frame:CGRectMake(featureCard.bounds.size.width - 124, 8, 112, 32)];
        expand.tag = kZN50BExpandTagBase + (NSInteger)featureIndex;
        [featureCard addSubview:expand];
        [self.contentView addSubview:featureCard];
        y += 54;

        if (!isExpanded) continue;

        // Feature name editor. Group name is what Builder persists for the
        // final runtime Feature switch.
        UIView *nameCard = [self cardAtY:y height:50 width:width compact:NO];
        UILabel *label = [self label:@"功能名" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(18, 9, 45, 30);
        [nameCard addSubview:label];
        UITextField *nameField = [[UITextField alloc] initWithFrame:CGRectMake(63, 9, nameCard.bounds.size.width - 78, 31)];
        nameField.tag = kZN50BRenameTagBase + (NSInteger)featureIndex;
        nameField.text = name;
        nameField.enabled = !locked;
        nameField.textColor = self.theme.primaryTextColor;
        nameField.backgroundColor = self.theme.controlColor;
        nameField.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
        nameField.autocorrectionType = UITextAutocorrectionTypeNo;
        nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        nameField.returnKeyType = UIReturnKeyDone;
        nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
        nameField.layer.cornerRadius = 7;
        nameField.layer.borderWidth = 1;
        nameField.layer.borderColor = self.theme.borderColor.CGColor;
        UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
        nameField.leftView = pad;
        nameField.leftViewMode = UITextFieldViewModeAlways;
        [nameField addTarget:self action:@selector(zn50b_featureNameEnd:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
        [nameCard addSubview:nameField];
        [self.contentView addSubview:nameCard];
        y += 56;

        for (NSUInteger patchIndex = 0; patchIndex < rows.count; patchIndex++) {
            ZNBinaryPatchRow *row = rows[patchIndex];
            NSUInteger globalIndex = [workspace.rows indexOfObjectIdenticalTo:row];
            if (globalIndex == NSNotFound) continue;
            UIView *patchCard = [self cardAtY:y height:94 width:width compact:NO];
            NSString *effectiveTarget = (row.explicitTarget && row.target.length) ? row.target : workspace.defaultTarget;
            NSString *patchTitle = ZN50BTrim(row.title);
            if (!patchTitle.length || [patchTitle caseInsensitiveCompare:name] == NSOrderedSame) {
                patchTitle = [NSString stringWithFormat:@"Patch #%lu", (unsigned long)patchIndex + 1];
            }
            UILabel *head = [self label:[NSString stringWithFormat:@"#%lu · %@ · %@", (unsigned long)patchIndex + 1, effectiveTarget, patchTitle]
                                    size:9.8
                                  weight:UIFontWeightSemibold
                                   color:self.theme.primaryTextColor];
            head.frame = CGRectMake(18, 5, patchCard.bounds.size.width - 31, 16);
            head.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [patchCard addSubview:head];

            UILabel *offsetLabel = [self label:@"Offset" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
            offsetLabel.frame = CGRectMake(18, 24, 45, 28);
            [patchCard addSubview:offsetLabel];
            UITextField *offset = [self zn44_field:CGRectMake(63, 23, patchCard.bounds.size.width - 78, 29)
                                               text:row.offsetText
                                        placeholder:@"0x..."
                                                tag:441000 + (NSInteger)globalIndex
                                            enabled:!locked];
            [patchCard addSubview:offset];

            UILabel *enabledLabel = [self label:@"Enabled" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
            enabledLabel.frame = CGRectMake(18, 54, 45, 28);
            [patchCard addSubview:enabledLabel];
            UITextField *enabled = [self zn44_field:CGRectMake(63, 53, patchCard.bounds.size.width - 78, 29)
                                                text:row.enabledText
                                         placeholder:@"ARM64 HEX"
                                                 tag:442000 + (NSInteger)globalIndex
                                             enabled:!locked];
            enabled.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
            [patchCard addSubview:enabled];

            NSString *original = row.originalHex.length ? row.originalHex : @"-";
            NSString *status = row.statusText.length ? row.statusText : @"待验证";
            UILabel *originalLine = [self label:[NSString stringWithFormat:@"Original  %@   %@", original, status]
                                            size:8.2
                                          weight:UIFontWeightRegular
                                           color:row.conflict ? UIColor.systemOrangeColor : self.theme.secondaryTextColor];
            originalLine.frame = CGRectMake(18, 82, patchCard.bounds.size.width - 31, 11);
            originalLine.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [patchCard addSubview:originalLine];

            [self.contentView addSubview:patchCard];
            y += 100;
        }

        UIView *addPatchCard = [self cardAtY:y height:44 width:width compact:NO];
        UIButton *addPatch = [self zn40_button:@"＋ 增加 Patch"
                                      selector:@selector(zn50b_addPatch:)
                                         frame:CGRectMake(18, 6, addPatchCard.bounds.size.width - 36, 32)];
        addPatch.tag = kZN50BAddPatchTagBase + (NSInteger)featureIndex;
        addPatch.enabled = !locked;
        [addPatchCard addSubview:addPatch];
        [self.contentView addSubview:addPatchCard];
        y += 50;
    }

    UIView *addFeatureCard = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *addFeature = [self zn40_button:@"＋ 增加功能"
                                    selector:@selector(zn50b_addFeature:)
                                       frame:CGRectMake(13, 7, addFeatureCard.bounds.size.width - 26, 34)];
    addFeature.enabled = !locked;
    [addFeatureCard addSubview:addFeature];
    [self.contentView addSubview:addFeatureCard];
    y += 56;

    CGFloat gap = 8.0;
    CGFloat inner = width - 26.0;
    CGFloat buttonW = (inner - gap) / 2.0;

    UIView *actions1 = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *validate = [self zn40_button:@"读取验证" selector:@selector(zn44_validateAll:) frame:CGRectMake(13, 9, buttonW, 34)];
    UIButton *apply = [self zn40_button:@"临时应用" selector:@selector(zn44_applyAll:) frame:CGRectMake(13 + buttonW + gap, 9, buttonW, 34)];
    validate.enabled = !workspace.isBuilding && !workspace.hasAnyApplied;
    apply.enabled = !workspace.isBuilding && !workspace.hasAnyApplied;
    [actions1 addSubview:validate];
    [actions1 addSubview:apply];
    [self.contentView addSubview:actions1];
    y += 60;

    UIView *actions2 = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *restore = [self zn40_button:@"恢复全部" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13, 9, buttonW, 34)];
    UIButton *build = [self zn40_button:(workspace.isBuilding ? @"正在生成…" : @"生成新二进制")
                                   selector:@selector(zn44_buildBinary:)
                                      frame:CGRectMake(13 + buttonW + gap, 9, buttonW, 34)];
    restore.enabled = !workspace.isBuilding && workspace.hasAnyApplied;
    build.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && workspace.filledCount > 0 && workspace.validatedCount == workspace.filledCount;
    [actions2 addSubview:restore];
    [actions2 addSubview:build];
    [self.contentView addSubview:actions2];
    y += 60;

    if (workspace.lastStatus.length) {
        UIView *statusCard = [self cardAtY:y height:38 width:width compact:NO];
        UILabel *status = [self label:workspace.lastStatus size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 8, statusCard.bounds.size.width - 26, 22);
        status.numberOfLines = 2;
        status.lineBreakMode = NSLineBreakByTruncatingTail;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 46;
    }

    if (workspace.lastOutputPaths.count) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (NSUInteger i = 0; i < MIN((NSUInteger)4, workspace.lastOutputPaths.count); i++) {
            NSString *path = workspace.lastOutputPaths[i];
            [lines addObject:[path hasPrefix:NSHomeDirectory()] ? [path substringFromIndex:NSHomeDirectory().length] : path];
        }
        [self zn40_addInfoCard:@"最近输出" lines:lines y:&y width:width];
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn50b_expandFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN50BExpandTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *key = features[(NSUInteger)index][@"key"];
    NSMutableSet<NSString *> *expanded = ZN50BExpandedKeys(self);
    if ([expanded containsObject:key]) [expanded removeObject:key];
    else [expanded addObject:key];
    [self renderPage];
}

- (void)zn50b_addFeature:(id)sender {
    (void)sender;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *name = [workspace addFeature];
    if (name.length) [ZN50BExpandedKeys(self) addObject:ZN50BFeatureKey(name)];
    [self renderPage];
}

- (void)zn50b_addPatch:(UIButton *)sender {
    NSInteger index = sender.tag - kZN50BAddPatchTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"];
    [workspace addPatchToFeature:name];
    [ZN50BExpandedKeys(self) addObject:ZN50BFeatureKey(name)];
    [self renderPage];
}

- (void)zn50b_featureNameEnd:(UITextField *)field {
    NSInteger index = field.tag - kZN50BRenameTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *oldName = features[(NSUInteger)index][@"name"];
    NSString *newName = ZN50BTrim(field.text);
    NSString *error = nil;
    if ([workspace renameFeature:oldName to:newName error:&error]) {
        NSMutableSet<NSString *> *expanded = ZN50BExpandedKeys(self);
        [expanded removeObject:ZN50BFeatureKey(oldName)];
        [expanded addObject:ZN50BFeatureKey(newName)];
    } else {
        workspace.lastStatus = [NSString stringWithFormat:@"重命名失败：%@", error ?: @"未知错误"];
        field.text = oldName;
    }
    [self.hostWindow endEditing:YES];
    [self renderPage];
}

@end

static void ZN50BSwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(121))) static void ZNInstallFeatureBuilderUI(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN50BSwapInstanceMethod(cls, @selector(zn44_renderOther), @selector(zn50b_renderOther));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5 Feature Builder installed: Feature -> Patches -> validate/build; JSON optional"];
    }
}
