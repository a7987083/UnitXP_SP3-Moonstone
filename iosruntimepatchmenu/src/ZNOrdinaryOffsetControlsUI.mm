#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNTheme.h"
#import "ZNInputService.h"

// UI-only decorator for Ordinary Offset authoring.
// This file intentionally owns NO patch/write/runtime backend.
// Four public control types:
//   Button = 点击执行
//   Switch = 开关
//   Number = 输入
//   Slider = 滑动条
// Number/Slider additionally expose an independent Value Type selector.

static const NSInteger kZNOOAddPatchTagBase = 461000;
static const NSInteger kZNOOTypeTagBase = 466000;
static const NSInteger kZNOODeleteFeatureTagBase = 467000;
static const NSInteger kZNOODeletePatchTagBase = 468000;
static const NSInteger kZNOOValueTypeTagBase = 469000;
static const NSInteger kZNOOOffsetFieldTagBase = 441000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)renderPage;
- (void)zn50b_renderOther;
@end

static NSString *ZNOOTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNOORowVisible(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *group = ZNOOTrim(row.group);
    NSString *title = ZNOOTrim(row.title);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return YES;
    return title.length > 0;
}

static NSArray<NSDictionary *> *ZNOOFeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNBinaryPatchRow *> *> *rowsByKey = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZNOORowVisible(row)) continue;
        NSString *name = ZNOOTrim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"] == NSOrderedSame) name = ZNOOTrim(row.title);
        if (!name.length) name = @"未命名功能";
        NSString *key = name.lowercaseString;
        if (!rowsByKey[key]) {
            rowsByKey[key] = [NSMutableArray array];
            names[key] = name;
            [order addObject:key];
        }
        [rowsByKey[key] addObject:row];
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        [out addObject:@{@"name": names[key] ?: @"功能", @"rows": [rowsByKey[key] copy] ?: @[]}];
    }
    return out;
}

static UIButton *ZNOOButton(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UIButton.class] ? (UIButton *)view : nil;
}

static UITextField *ZNOOField(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UITextField.class] ? (UITextField *)view : nil;
}

static BOOL ZNOONeedsValueType(ZNFeatureControlType type) {
    return type == ZNFeatureControlTypeNumber || type == ZNFeatureControlTypeSlider;
}

static ZNFeatureControlType ZNOONextControlType(ZNFeatureControlType current) {
    // Explicit UX order requested by the product model:
    // 点击执行 -> 开关 -> 输入 -> 滑动条 -> 点击执行
    switch (current) {
        case ZNFeatureControlTypeButton: return ZNFeatureControlTypeSwitch;
        case ZNFeatureControlTypeSwitch: return ZNFeatureControlTypeNumber;
        case ZNFeatureControlTypeNumber: return ZNFeatureControlTypeSlider;
        case ZNFeatureControlTypeSlider: return ZNFeatureControlTypeButton;
        default: return ZNFeatureControlTypeSwitch;
    }
}

static ZNValueType ZNOONextValueType(ZNValueType current) {
    // Keep Auto for compatibility and cycle through the established numeric set.
    switch (current) {
        case ZNValueTypeAuto: return ZNValueTypeI32;
        case ZNValueTypeI32: return ZNValueTypeU32;
        case ZNValueTypeU32: return ZNValueTypeI64;
        case ZNValueTypeI64: return ZNValueTypeU64;
        case ZNValueTypeU64: return ZNValueTypeF32;
        case ZNValueTypeF32: return ZNValueTypeF64;
        case ZNValueTypeF64: return ZNValueTypeAuto;
        default: return ZNValueTypeAuto;
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNOrdinaryOffsetControlsUI)
- (void)znoo_renderOther;
- (void)znoo_cycleControlType:(UIButton *)sender;
- (void)znoo_cycleValueType:(UIButton *)sender;
- (void)znoo_deleteFeature:(UIButton *)sender;
- (void)znoo_deletePatch:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNOrdinaryOffsetControlsUI)

- (void)znoo_renderOther {
    [self znoo_renderOther];

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    BOOL locked = workspace.hasAnyApplied || workspace.isBuilding;
    NSArray<NSDictionary *> *features = ZNOOFeatureGroups(workspace);

    for (NSUInteger i = 0; i < features.count; i++) {
        NSString *name = features[i][@"name"] ?: @"功能";
        ZNFeatureControlType controlType = [workspace controlTypeForFeature:name];
        ZNValueType valueType = [workspace valueTypeForFeature:name];

        UIButton *addPatch = ZNOOButton(self.contentView, kZNOOAddPatchTagBase + (NSInteger)i);
        UIView *card = addPatch.superview;
        if (!addPatch || !card) continue;

        CGFloat left = 8.0;
        CGFloat gap = 4.0;
        CGFloat inner = CGRectGetWidth(card.bounds) - left * 2.0;
        CGFloat width = (inner - gap * 3.0) / 4.0;

        addPatch.frame = CGRectMake(left, 6, width, 32);
        [addPatch setTitle:@"＋ Offset" forState:UIControlStateNormal];
        addPatch.titleLabel.adjustsFontSizeToFitWidth = YES;
        addPatch.titleLabel.minimumScaleFactor = 0.58;

        UIButton *typeButton = [self zn40_button:[NSString stringWithFormat:@"类型 · %@", ZNFeatureControlTypeName(controlType)]
                                          selector:@selector(znoo_cycleControlType:)
                                             frame:CGRectMake(left + (width + gap), 6, width, 32)];
        typeButton.tag = kZNOOTypeTagBase + (NSInteger)i;
        typeButton.enabled = !locked;
        typeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        typeButton.titleLabel.minimumScaleFactor = 0.50;
        [card addSubview:typeButton];

        BOOL needsValue = ZNOONeedsValueType(controlType);
        NSString *valueTitle = needsValue
            ? [NSString stringWithFormat:@"值类型 · %@", ZNValueTypeName(valueType)]
            : @"值类型 · —";
        UIButton *valueButton = [self zn40_button:valueTitle
                                           selector:@selector(znoo_cycleValueType:)
                                              frame:CGRectMake(left + (width + gap) * 2.0, 6, width, 32)];
        valueButton.tag = kZNOOValueTypeTagBase + (NSInteger)i;
        valueButton.enabled = !locked && needsValue;
        valueButton.alpha = needsValue ? 1.0 : 0.42;
        valueButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        valueButton.titleLabel.minimumScaleFactor = 0.50;
        [card addSubview:valueButton];

        UIButton *deleteFeature = [self zn40_button:@"删除功能"
                                            selector:@selector(znoo_deleteFeature:)
                                               frame:CGRectMake(left + (width + gap) * 3.0, 6, width, 32)];
        deleteFeature.tag = kZNOODeleteFeatureTagBase + (NSInteger)i;
        deleteFeature.enabled = !locked;
        deleteFeature.titleLabel.adjustsFontSizeToFitWidth = YES;
        deleteFeature.titleLabel.minimumScaleFactor = 0.58;
        deleteFeature.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
        deleteFeature.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.72].CGColor;
        [card addSubview:deleteFeature];
    }

    // Keep ordinary Offset/Patch rows unchanged. Only restore per-row delete affordance.
    for (NSUInteger globalIndex = 0; globalIndex < workspace.rows.count; globalIndex++) {
        UITextField *offset = ZNOOField(self.contentView, kZNOOOffsetFieldTagBase + (NSInteger)globalIndex);
        UITextField *enabledHex = ZNOOField(self.contentView, 442000 + (NSInteger)globalIndex);
        UIView *patchCard = offset.superview;
        if (!offset || !patchCard) continue;
        ZNInputServiceBindField(offset, ZNInputModeHexAddress);
        if (enabledHex) ZNInputServiceBindField(enabledHex, ZNInputModeHexBytes);
        UIButton *deletePatch = [self zn40_button:@"删除"
                                          selector:@selector(znoo_deletePatch:)
                                             frame:CGRectMake(CGRectGetWidth(patchCard.bounds) - 58, 3, 45, 19)];
        deletePatch.tag = kZNOODeletePatchTagBase + (NSInteger)globalIndex;
        deletePatch.enabled = !locked;
        deletePatch.titleLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
        deletePatch.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.10];
        deletePatch.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.64].CGColor;
        [patchCard addSubview:deletePatch];
    }
}

- (void)znoo_cycleControlType:(UIButton *)sender {
    NSInteger index = sender.tag - kZNOOTypeTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZNOOFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    ZNFeatureControlType current = [workspace controlTypeForFeature:name];
    ZNFeatureControlType next = ZNOONextControlType(current);
    NSString *error = nil;
    if (![workspace setControlType:next forFeature:name error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"修改按钮类型失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)znoo_cycleValueType:(UIButton *)sender {
    NSInteger index = sender.tag - kZNOOValueTypeTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZNOOFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    ZNFeatureControlType control = [workspace controlTypeForFeature:name];
    if (!ZNOONeedsValueType(control)) return;
    ZNValueType next = ZNOONextValueType([workspace valueTypeForFeature:name]);
    NSString *error = nil;
    if (![workspace setValueType:next forFeature:name error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"修改数值类型失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)znoo_deleteFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZNOODeleteFeatureTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZNOOFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *error = nil;
    if (![workspace removeFeatureNamed:features[(NSUInteger)index][@"name"] ?: @"" error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"删除功能失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)znoo_deletePatch:(UIButton *)sender {
    NSInteger index = sender.tag - kZNOODeletePatchTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *error = nil;
    if (![workspace removePatchAtGlobalIndex:(NSUInteger)index error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"删除 Offset 失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

@end

extern "C" void ZNInstallOrdinaryOffsetControlsUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method replacement = class_getInstanceMethod(cls, @selector(znoo_renderOther));
        if (original && replacement) method_exchangeImplementations(original, replacement);
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.12-offset-ui] ordinary Offset UI installed: 点击执行 / 开关 / 输入 / 滑动条"];
    });
}
