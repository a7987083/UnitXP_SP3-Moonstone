#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTypedValueWorkspace.h"
#import "ZNH5GGValueBackend.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn44_renderOther;
@end

static const NSInteger kZNTVTargetTag = 571000;
static const NSInteger kZNTVRVATag = 572000;
static const NSInteger kZNTVTypeTag = 573000;
static const NSInteger kZNTVControlTag = 574000;
static const NSInteger kZNTVValueTag = 575000;
static const NSInteger kZNTVMinTag = 576000;
static const NSInteger kZNTVMaxTag = 577000;
static const NSInteger kZNTVStepTag = 578000;
static const NSInteger kZNTVSliderTag = 579000;
static const NSInteger kZNTVValidateTag = 580000;
static const NSInteger kZNTVApplyTag = 581000;
static const NSInteger kZNTVRestoreTag = 582000;
static const NSInteger kZNTVDeleteTag = 583000;

static NSArray<NSString *> *ZNTVTypes(void) {
    return @[@"F32", @"F64", @"I32", @"U32", @"I64", @"U64", @"I16", @"U16", @"I8", @"U8"];
}

static UITextField *ZNTVField(CGRect frame, NSString *text, NSString *placeholder, NSInteger tag, ZNTheme *theme) {
    UITextField *f = [[UITextField alloc] initWithFrame:frame];
    f.tag = tag;
    f.text = text ?: @"";
    f.placeholder = placeholder;
    f.textColor = theme.primaryTextColor;
    f.backgroundColor = theme.controlColor;
    f.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium];
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.layer.cornerRadius = 6;
    f.layer.borderWidth = 1;
    f.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
    f.leftView = pad;
    f.leftViewMode = UITextFieldViewModeAlways;
    return f;
}

static NSUInteger ZNTVIndexFromTag(NSInteger tag, NSInteger base) {
    return tag >= base ? (NSUInteger)(tag - base) : NSNotFound;
}

static UITextField *ZNTVFindField(UIView *root, NSInteger tag) {
    UIView *v = [root viewWithTag:tag];
    return [v isKindOfClass:UITextField.class] ? (UITextField *)v : nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNTypedValueAuthoringUI)
- (void)zn511_renderOther;
- (void)zn511_add:(id)sender;
- (void)zn511_cycleType:(UIButton *)sender;
- (void)zn511_cycleControl:(UIButton *)sender;
- (void)zn511_slider:(UISlider *)sender;
- (void)zn511_validate:(UIButton *)sender;
- (void)zn511_apply:(UIButton *)sender;
- (void)zn511_restore:(UIButton *)sender;
- (void)zn511_delete:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNTypedValueAuthoringUI)

- (BOOL)zn511_syncRow:(NSUInteger)index fromCard:(UIView *)card error:(NSString **)error {
    ZNTypedValueWorkspace *ws = [ZNTypedValueWorkspace sharedWorkspace];
    if (index >= ws.rows.count) {
        if (error) *error = @"Value Offset 不存在";
        return NO;
    }
    ZNTypedValueOffset *entry = ws.rows[index].entry;
    entry.target = ZNTVFindField(card, kZNTVTargetTag + (NSInteger)index).text ?: @"main";
    entry.offsetText = ZNTVFindField(card, kZNTVRVATag + (NSInteger)index).text ?: @"";
    entry.valueText = ZNTVFindField(card, kZNTVValueTag + (NSInteger)index).text ?: @"0";
    UITextField *minF = ZNTVFindField(card, kZNTVMinTag + (NSInteger)index);
    UITextField *maxF = ZNTVFindField(card, kZNTVMaxTag + (NSInteger)index);
    UITextField *stepF = ZNTVFindField(card, kZNTVStepTag + (NSInteger)index);
    if (minF) entry.minValue = minF.text.doubleValue;
    if (maxF) entry.maxValue = maxF.text.doubleValue;
    if (stepF) entry.stepValue = stepF.text.doubleValue;
    return YES;
}

- (void)zn511_renderOther {
    [self zn511_renderOther];

    ZNTypedValueWorkspace *ws = [ZNTypedValueWorkspace sharedWorkspace];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = MAX(self.contentScroll.contentSize.height, CGRectGetHeight(self.contentView.bounds)) + 8.0;

    UIView *header = [self cardAtY:y height:54 width:width compact:NO];
    UILabel *title = [self label:@"Typed Value Offset · H5GG" size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, header.bounds.size.width - 126, 18);
    [header addSubview:title];
    UILabel *sub = [self label:[ZNH5GGValueBackend sharedBackend].availabilityText size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    sub.frame = CGRectMake(13, 27, header.bounds.size.width - 126, 17);
    [header addSubview:sub];
    UIButton *add = [self zn40_button:@"＋ Value" selector:@selector(zn511_add:) frame:CGRectMake(header.bounds.size.width - 104, 11, 92, 32)];
    [header addSubview:add];
    [self.contentView addSubview:header];
    y += 62.0;

    for (NSUInteger i = 0; i < ws.rows.count; i++) {
        ZNTypedValueRow *row = ws.rows[i];
        ZNTypedValueOffset *e = row.entry;
        CGFloat cardH = e.controlKind == ZNTypedValueControlKindSlider ? 242.0 : 200.0;
        UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

        UILabel *name = [self label:[NSString stringWithFormat:@"Value #%lu · %@", (unsigned long)i + 1, row.statusText ?: @""] size:9.3 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(12, 7, card.bounds.size.width - 72, 18);
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:name];
        UIButton *del = [self zn40_button:@"删除" selector:@selector(zn511_delete:) frame:CGRectMake(card.bounds.size.width - 58, 5, 47, 23)];
        del.tag = kZNTVDeleteTag + (NSInteger)i;
        [card addSubview:del];

        CGFloat inner = card.bounds.size.width - 24;
        CGFloat half = (inner - 7) * 0.5;
        UITextField *target = ZNTVField(CGRectMake(12, 34, half, 31), e.target, @"Target / main", kZNTVTargetTag + (NSInteger)i, self.theme);
        UITextField *rva = ZNTVField(CGRectMake(19 + half, 34, half, 31), e.offsetText, @"RVA · 0x...", kZNTVRVATag + (NSInteger)i, self.theme);
        [card addSubview:target]; [card addSubview:rva];

        UIButton *type = [self zn40_button:[NSString stringWithFormat:@"类型 · %@", e.valueType] selector:@selector(zn511_cycleType:) frame:CGRectMake(12, 72, half, 30)];
        type.tag = kZNTVTypeTag + (NSInteger)i;
        UIButton *control = [self zn40_button:(e.controlKind == ZNTypedValueControlKindSlider ? @"控件 · Slider" : @"控件 · Number") selector:@selector(zn511_cycleControl:) frame:CGRectMake(19 + half, 72, half, 30)];
        control.tag = kZNTVControlTag + (NSInteger)i;
        [card addSubview:type]; [card addSubview:control];

        UITextField *value = ZNTVField(CGRectMake(12, 109, inner, 31), e.valueText, @"Value", kZNTVValueTag + (NSInteger)i, self.theme);
        value.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        [card addSubview:value];

        CGFloat actionY = 147;
        if (e.controlKind == ZNTypedValueControlKindSlider) {
            CGFloat third = (inner - 12) / 3.0;
            UITextField *minF = ZNTVField(CGRectMake(12, 147, third, 29), [NSString stringWithFormat:@"%.10g", e.minValue], @"Min", kZNTVMinTag + (NSInteger)i, self.theme);
            UITextField *maxF = ZNTVField(CGRectMake(18 + third, 147, third, 29), [NSString stringWithFormat:@"%.10g", e.maxValue], @"Max", kZNTVMaxTag + (NSInteger)i, self.theme);
            UITextField *stepF = ZNTVField(CGRectMake(24 + third * 2, 147, third, 29), [NSString stringWithFormat:@"%.10g", e.stepValue], @"Step", kZNTVStepTag + (NSInteger)i, self.theme);
            minF.keyboardType = maxF.keyboardType = stepF.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            [card addSubview:minF]; [card addSubview:maxF]; [card addSubview:stepF];

            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(12, 180, inner, 24)];
            slider.tag = kZNTVSliderTag + (NSInteger)i;
            slider.minimumValue = (float)e.minValue;
            slider.maximumValue = (float)e.maxValue;
            double current = e.valueText.doubleValue;
            slider.value = (float)MIN(MAX(current, e.minValue), e.maxValue);
            [slider addTarget:self action:@selector(zn511_slider:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:slider];
            actionY = 207;
        }

        CGFloat bw = (inner - 14) / 3.0;
        UIButton *validate = [self zn40_button:@"读取验证" selector:@selector(zn511_validate:) frame:CGRectMake(12, actionY, bw, 28)];
        validate.tag = kZNTVValidateTag + (NSInteger)i;
        UIButton *apply = [self zn40_button:@"临时应用" selector:@selector(zn511_apply:) frame:CGRectMake(19 + bw, actionY, bw, 28)];
        apply.tag = kZNTVApplyTag + (NSInteger)i;
        UIButton *restore = [self zn40_button:@"恢复原值" selector:@selector(zn511_restore:) frame:CGRectMake(26 + bw * 2, actionY, bw, 28)];
        restore.tag = kZNTVRestoreTag + (NSInteger)i;
        [card addSubview:validate]; [card addSubview:apply]; [card addSubview:restore];

        [self.contentView addSubview:card];
        y += cardH + 8;
    }

    [self zn40_updateContentHeight:y + 8];
}

- (void)zn511_add:(id)sender {
    (void)sender;
    [[ZNTypedValueWorkspace sharedWorkspace] addRow];
    [self renderPage];
}

- (void)zn511_cycleType:(UIButton *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVTypeTag);
    ZNTypedValueWorkspace *ws = [ZNTypedValueWorkspace sharedWorkspace];
    if (index >= ws.rows.count) return;
    ZNTypedValueOffset *e = ws.rows[index].entry;
    NSArray *types = ZNTVTypes();
    NSUInteger current = [types indexOfObject:e.valueType.uppercaseString];
    e.valueType = types[(current == NSNotFound ? 0 : (current + 1) % types.count)];
    [self renderPage];
}

- (void)zn511_cycleControl:(UIButton *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVControlTag);
    ZNTypedValueWorkspace *ws = [ZNTypedValueWorkspace sharedWorkspace];
    if (index >= ws.rows.count) return;
    ZNTypedValueOffset *e = ws.rows[index].entry;
    e.controlKind = e.controlKind == ZNTypedValueControlKindSlider ? ZNTypedValueControlKindNumber : ZNTypedValueControlKindSlider;
    [self renderPage];
}

- (void)zn511_slider:(UISlider *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVSliderTag);
    ZNTypedValueWorkspace *ws = [ZNTypedValueWorkspace sharedWorkspace];
    if (index >= ws.rows.count) return;
    ZNTypedValueOffset *e = ws.rows[index].entry;
    double step = e.stepValue > 0 ? e.stepValue : 1.0;
    double v = round(sender.value / step) * step;
    v = MIN(MAX(v, e.minValue), e.maxValue);
    e.valueText = [NSString stringWithFormat:@"%.10g", v];
    UIView *card = sender.superview;
    UITextField *value = ZNTVFindField(card, kZNTVValueTag + (NSInteger)index);
    value.text = e.valueText;
}

- (void)zn511_validate:(UIButton *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVValidateTag);
    UIView *card = sender.superview;
    NSString *error = nil;
    [self zn511_syncRow:index fromCard:card error:&error];
    [[ZNTypedValueWorkspace sharedWorkspace] validateRowAtIndex:index error:&error];
    [self.hostWindow endEditing:YES];
    [self renderPage];
}

- (void)zn511_apply:(UIButton *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVApplyTag);
    UIView *card = sender.superview;
    NSString *error = nil;
    [self zn511_syncRow:index fromCard:card error:&error];
    ZNTypedValueWorkspace *ws = [ZNTypedValueWorkspace sharedWorkspace];
    if (index < ws.rows.count) [ws applyRowAtIndex:index value:ws.rows[index].entry.valueText error:&error];
    [self.hostWindow endEditing:YES];
    [self renderPage];
}

- (void)zn511_restore:(UIButton *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVRestoreTag);
    NSString *error = nil;
    [[ZNTypedValueWorkspace sharedWorkspace] restoreRowAtIndex:index error:&error];
    [self renderPage];
}

- (void)zn511_delete:(UIButton *)sender {
    NSUInteger index = ZNTVIndexFromTag(sender.tag, kZNTVDeleteTag);
    NSString *error = nil;
    [[ZNTypedValueWorkspace sharedWorkspace] removeRowAtIndex:index error:&error];
    [self renderPage];
}

@end

static void ZNTVSwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a);
    Method mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallTypedValueAuthoringUIDeferred(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
    if (!cls) return;
    ZNTVSwap(cls, @selector(zn44_renderOther), @selector(zn511_renderOther));
    [[ZNRuntimeLogger sharedLogger] log:@"[m5.11-value] Typed Value Offset authoring UI installed"];
}
