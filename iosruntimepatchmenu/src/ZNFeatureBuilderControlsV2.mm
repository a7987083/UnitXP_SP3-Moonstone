#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNTheme.h"

// M5.11 unified Offset authoring UI.
// One existing Feature/Offset surface owns all three modes:
//   Switch -> raw ARM64 bytes
//   Slider/Number -> typed H5GG value backend

static const NSInteger kZN64AddPatchTagBase = 461000;
static const NSInteger kZN64OffsetFieldTagBase = 441000;
static const NSInteger kZN64ValueFieldTagBase = 442000;
static const NSInteger kZN64TypeTagBase = 466000;
static const NSInteger kZN64DeleteFeatureTagBase = 467000;
static const NSInteger kZN64DeletePatchTagBase = 468000;
static const NSInteger kZN64ValueTypeTagBase = 469000;
static const NSInteger kZN64RangeTagBase = 470000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
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
    NSString *group = ZN64Trim(row.group), *title = ZN64Trim(row.title);
    return (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) || title.length > 0;
}

static NSArray<NSDictionary *> *ZN64FeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *rows = [NSMutableDictionary dictionary];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZN64RowVisible(row)) continue;
        NSString *name = ZN64Trim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"] == NSOrderedSame) name = ZN64Trim(row.title);
        if (!name.length) name = @"未命名功能";
        NSString *key = name.lowercaseString;
        if (!rows[key]) { rows[key] = [NSMutableArray array]; names[key] = name; [order addObject:key]; }
        [rows[key] addObject:row];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in order) [out addObject:@{@"name":names[key]?:@"功能", @"rows":[rows[key] copy]?:@[]}];
    return out;
}

static UIButton *ZN64Button(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UIButton.class] ? (UIButton *)view : nil;
}
static UITextField *ZN64Field(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UITextField.class] ? (UITextField *)view : nil;
}

static NSString *ZN64ControlName(ZNOffsetControlKind kind) {
    switch (kind) {
        case ZNOffsetControlKindSlider: return @"Slider";
        case ZNOffsetControlKindNumber: return @"Number";
        default: return @"Switch";
    }
}

static NSArray<NSString *> *ZN64ValueTypes(void) {
    return @[@"F32", @"F64", @"I32", @"U32", @"I64", @"U64", @"I16", @"U16", @"I8", @"U8"];
}

static void ZN64InvalidateRow(ZNBinaryPatchRow *row) {
    row.validator = nil;
    row.typedEntry = nil;
    row.validated = NO;
    row.originalHex = @"";
    row.conflict = NO;
    row.statusText = @"待验证";
}

static void ZN64SetLabelText(UIView *root, NSString *from, NSString *to) {
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *l = (UILabel *)v;
            if ([l.text isEqualToString:from]) l.text = to;
        }
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureBuilderControlsV2)
- (void)zn64fb_renderOther;
- (void)zn64fb_cycleControl:(UIButton *)sender;
- (void)zn64fb_cycleValueType:(UIButton *)sender;
- (void)zn64fb_editRange:(UIButton *)sender;
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
        NSArray<ZNBinaryPatchRow *> *rows = features[i][@"rows"];
        ZNOffsetControlKind kind = rows.count ? rows.firstObject.controlKind : ZNOffsetControlKindSwitch;
        UIButton *addPatch = ZN64Button(self.contentView, kZN64AddPatchTagBase + (NSInteger)i);
        UIView *card = addPatch.superview;
        if (!addPatch || !card) continue;
        CGFloat left = 10.0, gap = 6.0;
        CGFloat inner = CGRectGetWidth(card.bounds) - left * 2.0;
        CGFloat w = (inner - gap * 2.0) / 3.0;
        addPatch.frame = CGRectMake(left, 6, w, 32);
        [addPatch setTitle:@"＋ Offset" forState:UIControlStateNormal];

        UIButton *type = [self zn40_button:[NSString stringWithFormat:@"类型 · %@", ZN64ControlName(kind)] selector:@selector(zn64fb_cycleControl:) frame:CGRectMake(left + w + gap, 6, w, 32)];
        type.tag = kZN64TypeTagBase + (NSInteger)i;
        type.enabled = !locked;
        [card addSubview:type];

        UIButton *deleteFeature = [self zn40_button:@"删除功能" selector:@selector(zn64fb_deleteFeature:) frame:CGRectMake(left + (w + gap) * 2.0, 6, w, 32)];
        deleteFeature.tag = kZN64DeleteFeatureTagBase + (NSInteger)i;
        deleteFeature.enabled = !locked;
        deleteFeature.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
        deleteFeature.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.72].CGColor;
        [card addSubview:deleteFeature];
    }

    for (NSUInteger globalIndex = 0; globalIndex < workspace.rows.count; globalIndex++) {
        ZNBinaryPatchRow *row = workspace.rows[globalIndex];
        UITextField *offset = ZN64Field(self.contentView, kZN64OffsetFieldTagBase + (NSInteger)globalIndex);
        UITextField *value = ZN64Field(self.contentView, kZN64ValueFieldTagBase + (NSInteger)globalIndex);
        UIView *patchCard = offset.superview;
        if (!offset || !value || !patchCard) continue;
        offset.placeholder = @"RVA · 0x...";

        UIButton *deletePatch = [self zn40_button:@"删除" selector:@selector(zn64fb_deletePatch:) frame:CGRectMake(CGRectGetWidth(patchCard.bounds) - 58, 3, 45, 19)];
        deletePatch.tag = kZN64DeletePatchTagBase + (NSInteger)globalIndex;
        deletePatch.enabled = !locked;
        deletePatch.titleLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
        deletePatch.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.10];
        deletePatch.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.64].CGColor;
        [patchCard addSubview:deletePatch];

        if (row.controlKind == ZNOffsetControlKindSwitch) {
            value.placeholder = @"ARM64 HEX";
            value.keyboardType = UIKeyboardTypeASCIICapable;
            ZN64SetLabelText(patchCard, @"Value", @"Enabled");
            continue;
        }

        ZN64SetLabelText(patchCard, @"Enabled", @"Value");
        value.placeholder = row.controlKind == ZNOffsetControlKindSlider ? @"Default Value" : @"Value";
        value.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        CGFloat right = CGRectGetWidth(patchCard.bounds) - 13.0;
        CGFloat buttonW = 68.0;
        value.frame = CGRectMake(63, value.frame.origin.y, MAX(70.0, right - 63 - buttonW - 6), value.frame.size.height);
        UIButton *valueType = [self zn40_button:[NSString stringWithFormat:@"值 · %@", row.valueType.length ? row.valueType : @"F32"] selector:@selector(zn64fb_cycleValueType:) frame:CGRectMake(right - buttonW, value.frame.origin.y, buttonW, value.frame.size.height)];
        valueType.tag = kZN64ValueTypeTagBase + (NSInteger)globalIndex;
        valueType.enabled = !locked;
        valueType.titleLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
        [patchCard addSubview:valueType];

        if (row.controlKind == ZNOffsetControlKindSlider) {
            offset.frame = CGRectMake(63, offset.frame.origin.y, MAX(70.0, right - 63 - buttonW - 6), offset.frame.size.height);
            UIButton *range = [self zn40_button:@"范围" selector:@selector(zn64fb_editRange:) frame:CGRectMake(right - buttonW, offset.frame.origin.y, buttonW, offset.frame.size.height)];
            range.tag = kZN64RangeTagBase + (NSInteger)globalIndex;
            range.enabled = !locked;
            range.titleLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
            [patchCard addSubview:range];
        }
    }
}

- (void)zn64fb_cycleControl:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64TypeTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (workspace.hasAnyApplied || workspace.isBuilding) return;
    NSArray *features = ZN64FeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSArray<ZNBinaryPatchRow *> *rows = features[(NSUInteger)index][@"rows"];
    ZNOffsetControlKind current = rows.count ? rows.firstObject.controlKind : ZNOffsetControlKindSwitch;
    ZNOffsetControlKind next = (ZNOffsetControlKind)(((NSInteger)current + 1) % 3);
    for (ZNBinaryPatchRow *row in rows) {
        row.controlKind = next;
        if (next != ZNOffsetControlKindSwitch && !row.valueType.length) row.valueType = @"F32";
        ZN64InvalidateRow(row);
    }
    workspace.lastStatus = [NSString stringWithFormat:@"%@：类型切换为 %@", features[(NSUInteger)index][@"name"] ?: @"功能", ZN64ControlName(next)];
    [self.hostWindow endEditing:YES];
    [self renderPage];
}

- (void)zn64fb_cycleValueType:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64ValueTypeTagBase;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (index < 0 || (NSUInteger)index >= workspace.rows.count || workspace.hasAnyApplied || workspace.isBuilding) return;
    ZNBinaryPatchRow *row = workspace.rows[(NSUInteger)index];
    NSArray<NSString *> *types = ZN64ValueTypes();
    NSUInteger current = [types indexOfObject:row.valueType.uppercaseString ?: @""];
    row.valueType = types[(current == NSNotFound ? 0 : (current + 1) % types.count)];
    ZN64InvalidateRow(row);
    [self renderPage];
}

- (void)zn64fb_editRange:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64RangeTagBase;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (index < 0 || (NSUInteger)index >= workspace.rows.count || workspace.hasAnyApplied || workspace.isBuilding) return;
    ZNBinaryPatchRow *row = workspace.rows[(NSUInteger)index];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Slider 范围" message:@"设置 Min / Max / Step" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Min"; f.text=[NSString stringWithFormat:@"%.10g", row.minValue]; f.keyboardType=UIKeyboardTypeNumbersAndPunctuation; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Max"; f.text=[NSString stringWithFormat:@"%.10g", row.maxValue]; f.keyboardType=UIKeyboardTypeNumbersAndPunctuation; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Step"; f.text=[NSString stringWithFormat:@"%.10g", row.stepValue]; f.keyboardType=UIKeyboardTypeNumbersAndPunctuation; }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a;
        double minv = alert.textFields[0].text.doubleValue;
        double maxv = alert.textFields[1].text.doubleValue;
        double step = alert.textFields[2].text.doubleValue;
        if (maxv <= minv || step <= 0) { workspace.lastStatus = @"Slider 范围无效：Max 必须大于 Min，Step 必须 > 0"; [weakSelf renderPage]; return; }
        row.minValue = minv; row.maxValue = maxv; row.stepValue = step; ZN64InvalidateRow(row); workspace.lastStatus = [NSString stringWithFormat:@"Slider 范围 %.10g ~ %.10g · step %.10g", minv, maxv, step]; [weakSelf renderPage];
    }]];
    UIViewController *vc = self.hostWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:alert animated:YES completion:nil];
}

- (void)zn64fb_deleteFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64DeleteFeatureTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray *features = ZN64FeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    NSString *error = nil;
    if (![workspace removeFeatureNamed:name error:&error]) workspace.lastStatus = [NSString stringWithFormat:@"删除功能失败：%@", error ?: @"未知错误"];
    [self renderPage];
}

- (void)zn64fb_deletePatch:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64DeletePatchTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *error = nil;
    if (![workspace removePatchAtGlobalIndex:(NSUInteger)index error:&error]) workspace.lastStatus = [NSString stringWithFormat:@"删除 Offset 失败：%@", error ?: @"未知错误"];
    [self renderPage];
}

@end

extern "C" void ZNInstallFeatureBuilderControlsV2Deferred(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method replacement = class_getInstanceMethod(cls, @selector(zn64fb_renderOther));
        if (original && replacement) method_exchangeImplementations(original, replacement);
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.11-offset] unified Builder installed: Switch / Slider / Number on original Offset surface"];
    });
}
