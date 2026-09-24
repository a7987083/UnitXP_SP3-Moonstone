#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNTheme.h"

// M5.5.1 recovery baseline: keep the proven M5.4 Builder layout intact.
// Typed value selection is layered by M5.5 as a separate overlay instead of
// replacing the base Builder geometry.

static const NSInteger kZN64AddPatchTagBase = 461000;
static const NSInteger kZN64OffsetFieldTagBase = 441000;
static const NSInteger kZN64TypeTagBase = 466000;
static const NSInteger kZN64DeleteFeatureTagBase = 467000;
static const NSInteger kZN64DeletePatchTagBase = 468000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)renderPage;
- (void)zn50b_renderOther;
@end

static NSString *ZN64Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZN64RowVisible(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *group = ZN64Trim(row.group);
    NSString *title = ZN64Trim(row.title);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return YES;
    return title.length > 0;
}

static NSArray<NSDictionary *> *ZN64FeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNBinaryPatchRow *> *> *rowsByKey = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];

    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZN64RowVisible(row)) continue;
        NSString *name = ZN64Trim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"] == NSOrderedSame) name = ZN64Trim(row.title);
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
        [out addObject:@{
            @"key": key,
            @"name": names[key] ?: @"功能",
            @"rows": [rowsByKey[key] copy] ?: @[]
        }];
    }
    return out;
}

static UIButton *ZN64ButtonWithTag(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UIButton.class] ? (UIButton *)view : nil;
}

static UITextField *ZN64FieldWithTag(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UITextField.class] ? (UITextField *)view : nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureBuilderControlsV2)
- (void)zn64fb_renderOther;
- (void)zn64fb_cycleType:(UIButton *)sender;
- (void)zn64fb_deleteFeature:(UIButton *)sender;
- (void)zn64fb_deletePatch:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureBuilderControlsV2)

- (void)zn64fb_renderOther {
    [self zn64fb_renderOther];

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    BOOL locked = workspace.hasAnyApplied || workspace.isBuilding;
    NSArray<NSDictionary *> *features = ZN64FeatureGroups(workspace);

    for (NSUInteger i = 0; i < features.count; i++) {
        UIButton *addPatch = ZN64ButtonWithTag(self.contentView, kZN64AddPatchTagBase + (NSInteger)i);
        UIView *card = addPatch.superview;
        if (!addPatch || !card) continue;

        CGFloat left = 10.0;
        CGFloat gap = 6.0;
        CGFloat inner = CGRectGetWidth(card.bounds) - left * 2.0;
        CGFloat w = (inner - gap * 2.0) / 3.0;
        addPatch.frame = CGRectMake(left, 6, w, 32);
        [addPatch setTitle:@"＋ Patch" forState:UIControlStateNormal];

        NSString *name = features[i][@"name"] ?: @"功能";
        ZNFeatureControlType type = [workspace controlTypeForFeature:name];
        UIButton *typeButton = [self zn40_button:[NSString stringWithFormat:@"类型 · %@", ZNFeatureControlTypeName(type)]
                                          selector:@selector(zn64fb_cycleType:)
                                             frame:CGRectMake(left + w + gap, 6, w, 32)];
        typeButton.tag = kZN64TypeTagBase + (NSInteger)i;
        typeButton.enabled = !locked;
        typeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        typeButton.titleLabel.minimumScaleFactor = 0.65;
        [card addSubview:typeButton];

        UIButton *deleteFeature = [self zn40_button:@"删除功能"
                                            selector:@selector(zn64fb_deleteFeature:)
                                               frame:CGRectMake(left + (w + gap) * 2.0, 6, w, 32)];
        deleteFeature.tag = kZN64DeleteFeatureTagBase + (NSInteger)i;
        deleteFeature.enabled = !locked;
        deleteFeature.titleLabel.adjustsFontSizeToFitWidth = YES;
        deleteFeature.titleLabel.minimumScaleFactor = 0.7;
        deleteFeature.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
        deleteFeature.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.72].CGColor;
        [card addSubview:deleteFeature];
    }

    for (NSUInteger globalIndex = 0; globalIndex < workspace.rows.count; globalIndex++) {
        UITextField *offset = ZN64FieldWithTag(self.contentView, kZN64OffsetFieldTagBase + (NSInteger)globalIndex);
        UIView *patchCard = offset.superview;
        if (!offset || !patchCard) continue;

        UIButton *deletePatch = [self zn40_button:@"删除"
                                          selector:@selector(zn64fb_deletePatch:)
                                             frame:CGRectMake(CGRectGetWidth(patchCard.bounds) - 58, 3, 45, 19)];
        deletePatch.tag = kZN64DeletePatchTagBase + (NSInteger)globalIndex;
        deletePatch.enabled = !locked;
        deletePatch.titleLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
        deletePatch.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.10];
        deletePatch.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.64].CGColor;
        [patchCard addSubview:deletePatch];

        for (UIView *child in patchCard.subviews) {
            if (![child isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)child;
            if (CGRectGetMinY(label.frame) <= 6.0 && CGRectGetMinX(label.frame) <= 20.0) {
                CGRect f = label.frame;
                f.size.width = MAX(40.0, CGRectGetWidth(patchCard.bounds) - CGRectGetMinX(f) - 76.0);
                label.frame = f;
                break;
            }
        }
    }
}

- (void)zn64fb_cycleType:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64TypeTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN64FeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    ZNFeatureControlType current = [workspace controlTypeForFeature:name];
    ZNFeatureControlType next = (ZNFeatureControlType)(((uint32_t)current + 1u) % 4u);
    NSString *error = nil;
    if (![workspace setControlType:next forFeature:name error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"修改控件类型失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)zn64fb_deleteFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64DeleteFeatureTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN64FeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    NSString *error = nil;
    if (![workspace removeFeatureNamed:name error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"删除功能失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)zn64fb_deletePatch:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64DeletePatchTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *error = nil;
    if (![workspace removePatchAtGlobalIndex:(NSUInteger)index error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"删除 Patch 失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

@end

extern "C" void ZNInstallFeatureBuilderControlsV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method replacement = class_getInstanceMethod(cls, @selector(zn64fb_renderOther));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}
