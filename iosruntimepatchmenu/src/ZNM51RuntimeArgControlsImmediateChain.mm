#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZN51Arg1Tag = 674000;
static const NSInteger kZN51MultiArgTag = 690000;
static const NSInteger kZN51CheckTag = 812000;
static const NSInteger kZN51TypeTag = 813000;
static const NSInteger kZN51ChainTag = 814000;
static const NSInteger kZN51CardTag = 795000;
static const NSInteger kZN51ExecTag = 796000;
static const NSInteger kZN51FieldTag = 797000;
static const NSInteger kZN51SwitchTag = 798000;
static const NSInteger kZN51SliderTag = 799000;
static const NSInteger kZN49CardTag = 786000;

static const void *kZN51CandidateKey = &kZN51CandidateKey;
static const void *kZN51ActionKey = &kZN51ActionKey;
static const void *kZN51ArgKey = &kZN51ArgKey;
static const void *kZN51ValuesKey = &kZN51ValuesKey;
static const void *kZN51RecordKey = &kZN51RecordKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn50b_renderOther;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static CGFloat ZN51MaxY(UIView *root) {
    CGFloat y = 0;
    for (UIView *v in root.subviews) y = MAX(y, CGRectGetMaxY(v.frame));
    return y;
}

static UIViewController *ZN51Top(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static NSString *ZN51ShortType(NSString *type) {
    NSArray<NSString *> *parts = [(type ?: @"") componentsSeparatedByString:@"."];
    NSString *last = [parts.lastObject isKindOfClass:NSString.class] ? parts.lastObject : @"";
    return last.length ? last : (type ?: @"?");
}

static NSArray<NSDictionary *> *ZN51Visible(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [out addObject:candidate];
    }
    return out;
}

static void ZN51CollectButtons(UIView *root, NSString *title, NSMutableArray<UIButton *> *out) {
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UIButton.class] && [[(UIButton *)view titleForState:UIControlStateNormal] isEqualToString:title]) [out addObject:(UIButton *)view];
        ZN51CollectButtons(view, title, out);
    }
}

static NSMutableDictionary<NSString *, NSString *> *ZN51Values(ZNRuntimeMenuControllerV040 *controller) {
    NSMutableDictionary *values = objc_getAssociatedObject(controller, kZN51ValuesKey);
    if (!values) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(controller, kZN51ValuesKey, values, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return values;
}

static NSString *ZN51ValueKey(uint32_t actionID, NSUInteger arg) {
    return [NSString stringWithFormat:@"%u:%lu", actionID, (unsigned long)arg];
}

@interface ZNRuntimeMenuControllerV040 (ZNM51)
- (void)zn51_builderRender;
- (void)zn51_toggleArg:(UIButton *)sender;
- (void)zn51_cycleArgType:(UIButton *)sender;
- (void)zn51_finderRender:(CGFloat)width;
- (void)zn51_chainTapped:(UIButton *)sender;
- (void)zn51_runtimeFull;
- (void)zn51_runtimeCompact;
- (void)zn51_renderRuntime:(BOOL)compact;
- (void)zn51_runtimeExecute:(UIButton *)sender;
- (void)zn51_runtimeNumberChanged:(UITextField *)field;
- (void)zn51_runtimeSwitchChanged:(UISwitch *)control;
- (void)zn51_runtimeSliderChanged:(UISlider *)control;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM51)

- (void)zn51_builderRender {
    [self zn51_builderRender];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodAction *action = actions[i];
        for (NSUInteger arg = 0; arg < action.argumentCount; arg++) {
            NSInteger tag = action.argumentCount == 1 ? kZN51Arg1Tag + (NSInteger)i : kZN51MultiArgTag + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            UIView *found = [self.contentView viewWithTag:tag];
            if (![found isKindOfClass:UITextField.class]) continue;
            UITextField *field = (UITextField *)found;
            UIView *card = field.superview;
            if (!card) continue;
            CGRect f = field.frame;
            CGFloat right = CGRectGetWidth(card.bounds) - 12.0;
            CGFloat typeW = 56.0, checkW = 34.0, gap = 4.0;
            CGFloat available = right - CGRectGetMinX(f) - typeW - checkW - gap * 2.0;
            if (available > 70.0) f.size.width = available;
            field.frame = f;

            NSDictionary *cfg = action.argumentControlConfigs.count == action.argumentCount ? action.argumentControlConfigs[arg] : @{@"enabled": @NO, @"type": @"fixed"};
            BOOL enabled = [cfg[@"enabled"] boolValue];
            ZNRuntimeArgumentControlType type = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);

            UIButton *check = [self zn40_button:(enabled ? @"☑" : @"☐") selector:@selector(zn51_toggleArg:) frame:CGRectMake(CGRectGetMaxX(f) + gap, CGRectGetMinY(f), checkW, CGRectGetHeight(f))];
            check.tag = kZN51CheckTag + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            objc_setAssociatedObject(check, kZN51ActionKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(check, kZN51ArgKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [card addSubview:check];

            UIButton *typeButton = [self zn40_button:(enabled ? ZNRuntimeArgumentControlTypeName(type) : @"固定") selector:@selector(zn51_cycleArgType:) frame:CGRectMake(CGRectGetMaxX(check.frame) + gap, CGRectGetMinY(f), typeW, CGRectGetHeight(f))];
            typeButton.tag = kZN51TypeTag + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            typeButton.enabled = enabled;
            typeButton.alpha = enabled ? 1.0 : 0.5;
            typeButton.titleLabel.font = [UIFont systemFontOfSize:7.8 weight:UIFontWeightSemibold];
            objc_setAssociatedObject(typeButton, kZN51ActionKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(typeButton, kZN51ArgKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [card addSubview:typeButton];
        }
    }
    [self zn40_updateContentHeight:ZN51MaxY(self.contentView) + 8.0];
}

- (void)zn51_toggleArg:(UIButton *)sender {
    NSUInteger actionIndex = [objc_getAssociatedObject(sender, kZN51ActionKey) unsignedIntegerValue];
    NSUInteger argIndex = [objc_getAssociatedObject(sender, kZN51ArgKey) unsignedIntegerValue];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (actionIndex >= actions.count) return;
    ZNRuntimeMethodAction *action = actions[actionIndex];
    if (argIndex >= action.argumentCount) return;
    NSMutableArray<NSDictionary *> *configs = [NSMutableArray arrayWithArray:(action.argumentControlConfigs.count == action.argumentCount ? action.argumentControlConfigs : @[])];
    while (configs.count < action.argumentCount) [configs addObject:@{@"enabled": @NO, @"type": @"fixed", @"min": @0, @"max": @100, @"step": @1}];
    NSMutableDictionary *cfg = [configs[argIndex] mutableCopy];
    BOOL enabled = ![cfg[@"enabled"] boolValue];
    cfg[@"enabled"] = @(enabled);
    cfg[@"type"] = enabled ? @"number" : @"fixed";
    configs[argIndex] = cfg;
    [[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:configs atIndex:actionIndex error:nil];
    [self renderPage];
}

- (void)zn51_cycleArgType:(UIButton *)sender {
    NSUInteger actionIndex = [objc_getAssociatedObject(sender, kZN51ActionKey) unsignedIntegerValue];
    NSUInteger argIndex = [objc_getAssociatedObject(sender, kZN51ArgKey) unsignedIntegerValue];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (actionIndex >= actions.count) return;
    ZNRuntimeMethodAction *action = actions[actionIndex];
    if (argIndex >= action.argumentCount || action.argumentControlConfigs.count != action.argumentCount) return;
    NSMutableArray<NSDictionary *> *configs = [action.argumentControlConfigs mutableCopy];
    NSMutableDictionary *cfg = [configs[argIndex] mutableCopy];
    if (![cfg[@"enabled"] boolValue]) return;
    ZNRuntimeArgumentControlType current = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
    ZNRuntimeArgumentControlType next = current < ZNRuntimeArgumentControlTypeSwitch || current >= ZNRuntimeArgumentControlTypeSlider ? ZNRuntimeArgumentControlTypeSwitch : (ZNRuntimeArgumentControlType)(current + 1);
    cfg[@"type"] = ZNRuntimeArgumentControlTypeKey(next);
    configs[argIndex] = cfg;
    [[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:configs atIndex:actionIndex error:nil];
    [self renderPage];
}

- (void)zn51_finderRender:(CGFloat)width {
    [self zn51_finderRender:width];
    NSArray<NSDictionary *> *visible = ZN51Visible(self);
    NSMutableArray<UIButton *> *createButtons = [NSMutableArray array];
    ZN51CollectButtons(self.contentView, @"创建方法", createButtons);
    if (!visible.count || createButtons.count != visible.count) return;
    for (NSUInteger i = 0; i < visible.count; i++) {
        UIButton *create = createButtons[i];
        UIView *card = create.superview;
        if (!card) continue;
        CGFloat y = CGRectGetMaxY(create.frame) + 5.0;
        CGFloat needed = y + CGRectGetHeight(create.frame) + 7.0;
        CGFloat oldBottom = CGRectGetMaxY(card.frame);
        if (needed > CGRectGetHeight(card.frame)) {
            CGFloat delta = needed - CGRectGetHeight(card.frame);
            CGRect cf = card.frame; cf.size.height = needed; card.frame = cf;
            for (UIView *sibling in self.contentView.subviews) {
                if (sibling == card || CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
                CGRect sf = sibling.frame; sf.origin.y += delta; sibling.frame = sf;
            }
        }
        UIButton *chain = [self zn40_button:@"链式调用" selector:@selector(zn51_chainTapped:) frame:CGRectMake(CGRectGetMinX(create.frame), y, CGRectGetWidth(create.frame), CGRectGetHeight(create.frame))];
        chain.tag = kZN51ChainTag + (NSInteger)i;
        chain.titleLabel.font = [UIFont systemFontOfSize:8.2 weight:UIFontWeightSemibold];
        objc_setAssociatedObject(chain, kZN51CandidateKey, visible[i], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [card addSubview:chain];
    }
    [self zn40_updateContentHeight:ZN51MaxY(self.contentView) + 8.0];
}

- (void)zn51_chainTapped:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZN51CandidateKey);
    if (!candidate) return;
    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    NSDictionary *ret = [abi[@"return"] isKindOfClass:NSDictionary.class] ? abi[@"return"] : @{};
    NSString *returnType = [ret[@"name"] isKindOfClass:NSString.class] ? ret[@"name"] : @"";
    if ((ZNIL2CPPABIValueKind)[ret[@"kind"] integerValue] != ZNIL2CPPABIValueKindObjectReference) {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"链式调用需要 managed-reference 返回值；当前=%@", returnType.length ? returnType : @"?"]];
        [self renderPage];
        return;
    }
    NSString *targetNS = @"";
    NSString *targetClass = returnType;
    NSRange dot = [returnType rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound) {
        targetNS = [returnType substringToIndex:dot.location];
        targetClass = [returnType substringFromIndex:dot.location + 1];
    }
    UIViewController *top = ZN51Top(self.hostWindow);
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"返回对象 → 立即调用方法" message:[NSString stringWithFormat:@"%@::%@/%@\n返回类型：%@\n链式目标 V1 使用 argc=0。", candidate[@"class"] ?: @"?", candidate[@"method"] ?: @"?", candidate[@"argumentCount"] ?: @0, returnType ?: @"?"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = @"Namespace（可空）"; f.text = targetNS; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = @"Class"; f.text = targetClass; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = @"Method"; f.text = @"ToString"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"创建链式方法" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        __strong typeof(weakSelf) selfRef = weakSelf;
        if (!selfRef) return;
        NSString *ns = alert.textFields.count > 0 ? alert.textFields[0].text : @"";
        NSString *cls = alert.textFields.count > 1 ? alert.textFields[1].text : @"";
        NSString *method = alert.textFields.count > 2 ? alert.textFields[2].text : @"";
        if (!cls.length || !method.length) { [selfRef zn60v3_setStatus:@"链式 Class/Method 不能为空"]; [selfRef renderPage]; return; }
        NSArray<NSString *> *values = [selfRef znm43_argumentValues:candidate] ?: @[];
        NSString *err = nil;
        ZNRuntimeMethodAction *created = [[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate title:candidate[@"method"] argumentValues:values error:&err];
        if (!created) { [selfRef zn60v3_setStatus:err ?: @"创建主 Runtime Method 失败"]; [selfRef renderPage]; return; }
        NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
        NSUInteger index = NSNotFound;
        for (NSUInteger j = 0; j < actions.count; j++) {
            ZNRuntimeMethodAction *existing = actions[j];
            if (existing.actionID == created.actionID) { index = j; break; }
        }
        NSDictionary *chain = @{@"assembly": candidate[@"assembly"] ?: @"Assembly-CSharp.dll", @"namespace": ns ?: @"", @"class": cls, @"method": method, @"argumentCount": @0, @"argumentValues": @[]};
        if (index == NSNotFound || ![[ZNRuntimeActionStore sharedStore] updateImmediateChain:chain atIndex:index error:&err]) { [selfRef zn60v3_setStatus:err ?: @"保存 Immediate Chain 失败"]; [selfRef renderPage]; return; }
        [selfRef zn60v3_setStatus:[NSString stringWithFormat:@"已创建链式方法：%@ → %@::%@/0", created.canonicalIdentity, cls, method]];
        [selfRef renderPage];
    }]];
    [top presentViewController:alert animated:YES completion:nil];
}

- (void)zn51_removeRuntimeCards {
    for (UIView *view in [self.contentView.subviews copy]) {
        if ((view.tag >= kZN49CardTag && view.tag < kZN49CardTag + 512) || (view.tag >= kZN51CardTag && view.tag < kZN51CardTag + 512)) [view removeFromSuperview];
    }
}

- (void)zn51_renderRuntime:(BOOL)compact {
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    [self zn51_removeRuntimeCards];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZN51MaxY(self.contentView) + (compact ? 6.0 : 8.0);
    NSArray<ZNRuntimeMethodActionRecord *> *records = runtime.records ?: @[];
    for (NSUInteger i = 0; i < records.count; i++) {
        ZNRuntimeMethodActionRecord *record = records[i];
        NSArray<NSDictionary *> *configs = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs : @[];
        NSUInteger exposed = 0;
        for (NSDictionary *cfg in configs) if ([cfg[@"enabled"] boolValue]) exposed++;
        CGFloat rowH = 34.0, baseH = compact ? 42.0 : 48.0, height = baseH + exposed * rowH;
        UIView *card = [self cardAtY:y height:height width:width compact:compact];
        card.tag = kZN51CardTag + (NSInteger)i;
        UILabel *name = [self label:(record.title.length ? record.title : record.methodName) size:(compact ? 10.5 : 11.2) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(compact ? 9 : 13, 8, card.bounds.size.width - 92, 24);
        [card addSubview:name];
        UIButton *execute = [self zn40_button:@"执行" selector:@selector(zn51_runtimeExecute:) frame:CGRectMake(card.bounds.size.width - 76, 7, 64, 29)];
        execute.tag = kZN51ExecTag + (NSInteger)i;
        [card addSubview:execute];
        CGFloat rowY = baseH;
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            NSDictionary *cfg = configs.count ? configs[arg] : nil;
            if (![cfg[@"enabled"] boolValue]) continue;
            NSString *type = arg < record.parameterTypeNames.count ? record.parameterTypeNames[arg] : @"?";
            UILabel *label = [self label:[NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, ZN51ShortType(type)] size:8.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
            label.frame = CGRectMake(13, rowY, 82, 28);
            [card addSubview:label];
            NSString *key = ZN51ValueKey(record.actionID, arg);
            NSString *defaultValue = arg < record.argumentValues.count ? record.argumentValues[arg] : @"";
            NSString *stored = ZN51Values(self)[key] ?: defaultValue;
            ZNRuntimeArgumentControlType controlType = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
            if (controlType == ZNRuntimeArgumentControlTypeSwitch) {
                UISwitch *control = [[UISwitch alloc] initWithFrame:CGRectZero];
                control.on = stored.boolValue || [stored.lowercaseString isEqualToString:@"true"];
                control.tag = kZN51SwitchTag + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
                objc_setAssociatedObject(control, kZN51RecordKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(control, kZN51ArgKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [control addTarget:self action:@selector(zn51_runtimeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                control.center = CGPointMake(card.bounds.size.width - 38, rowY + 14);
                [card addSubview:control];
            } else if (controlType == ZNRuntimeArgumentControlTypeSlider) {
                UISlider *control = [[UISlider alloc] initWithFrame:CGRectMake(96, rowY, card.bounds.size.width - 109, 28)];
                control.minimumValue = [cfg[@"min"] floatValue];
                control.maximumValue = [cfg[@"max"] floatValue];
                if (control.maximumValue <= control.minimumValue) control.maximumValue = control.minimumValue + 100;
                control.value = stored.floatValue;
                control.tag = kZN51SliderTag + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
                objc_setAssociatedObject(control, kZN51RecordKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(control, kZN51ArgKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [control addTarget:self action:@selector(zn51_runtimeSliderChanged:) forControlEvents:UIControlEventValueChanged];
                [card addSubview:control];
            } else if (controlType == ZNRuntimeArgumentControlTypeButton) {
                UIButton *button = [self zn40_button:@"触发" selector:@selector(zn51_runtimeExecute:) frame:CGRectMake(card.bounds.size.width - 70, rowY, 58, 28)];
                button.tag = kZN51ExecTag + (NSInteger)i;
                [card addSubview:button];
            } else {
                UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(96, rowY, card.bounds.size.width - 109, 28)];
                field.text = stored; field.placeholder = defaultValue; field.textColor = self.theme.primaryTextColor; field.backgroundColor = self.theme.controlColor;
                field.layer.cornerRadius = 6; field.layer.borderWidth = 1; field.layer.borderColor = self.theme.borderColor.CGColor;
                field.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium]; field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                field.tag = kZN51FieldTag + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
                objc_setAssociatedObject(field, kZN51RecordKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(field, kZN51ArgKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [field addTarget:self action:@selector(zn51_runtimeNumberChanged:) forControlEvents:UIControlEventEditingChanged | UIControlEventEditingDidEnd];
                [card addSubview:field];
            }
            rowY += rowH;
        }
        [self.contentView addSubview:card];
        y += height + (compact ? 6.0 : 8.0);
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn51_runtimeFull { [self zn51_runtimeFull]; [self zn51_renderRuntime:NO]; }
- (void)zn51_runtimeCompact { [self zn51_runtimeCompact]; [self zn51_renderRuntime:YES]; }

- (void)zn51_runtimeNumberChanged:(UITextField *)field {
    NSUInteger recordIndex = [objc_getAssociatedObject(field, kZN51RecordKey) unsignedIntegerValue];
    NSUInteger arg = [objc_getAssociatedObject(field, kZN51ArgKey) unsignedIntegerValue];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    if (recordIndex >= runtime.records.count) return;
    ZN51Values(self)[ZN51ValueKey(runtime.records[recordIndex].actionID, arg)] = field.text ?: @"";
}

- (void)zn51_runtimeSwitchChanged:(UISwitch *)control {
    NSUInteger recordIndex = [objc_getAssociatedObject(control, kZN51RecordKey) unsignedIntegerValue];
    NSUInteger arg = [objc_getAssociatedObject(control, kZN51ArgKey) unsignedIntegerValue];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    if (recordIndex >= runtime.records.count) return;
    ZN51Values(self)[ZN51ValueKey(runtime.records[recordIndex].actionID, arg)] = control.on ? @"true" : @"false";
}

- (void)zn51_runtimeSliderChanged:(UISlider *)control {
    NSUInteger recordIndex = [objc_getAssociatedObject(control, kZN51RecordKey) unsignedIntegerValue];
    NSUInteger arg = [objc_getAssociatedObject(control, kZN51ArgKey) unsignedIntegerValue];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    if (recordIndex >= runtime.records.count) return;
    ZNRuntimeMethodActionRecord *record = runtime.records[recordIndex];
    NSDictionary *cfg = record.argumentControlConfigs.count == record.argumentCount ? record.argumentControlConfigs[arg] : @{};
    float step = [cfg[@"step"] floatValue];
    float value = control.value;
    if (step > 0) value = roundf(value / step) * step;
    ZN51Values(self)[ZN51ValueKey(record.actionID, arg)] = [NSString stringWithFormat:@"%.7g", value];
}

- (void)zn51_runtimeExecute:(UIButton *)sender {
    NSInteger index = sender.tag - kZN51ExecTag;
    if (index < 0) return;
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) return;
    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithArray:record.argumentValues ?: @[]];
    while (values.count < record.argumentCount) [values addObject:@""];
    if (record.argumentControlConfigs.count == record.argumentCount) {
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            if (![record.argumentControlConfigs[arg][@"enabled"] boolValue]) continue;
            NSString *value = ZN51Values(self)[ZN51ValueKey(record.actionID, arg)];
            if (value) values[arg] = value;
        }
    }
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.actionID = record.actionID; action.title = record.title; action.group = record.group; action.assembly = record.assembly; action.namespaceName = record.namespaceName; action.className = record.className; action.methodName = record.methodName;
    action.argumentCount = record.argumentCount; action.argumentValues = values; action.parameterTypeNames = record.parameterTypeNames; action.signatureAvailable = record.signatureAvailable; action.argumentControlConfigs = record.argumentControlConfigs; action.immediateChain = record.immediateChain;
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    UIViewController *top = ZN51Top(self.hostWindow);
    if (top) {
        NSString *message = result ? [NSString stringWithFormat:@"返回 %@ = %@", result[@"returnType"] ?: @"?", result[@"returnValue"] ?: @"?"] : (error ?: @"执行失败");
        UIAlertController *done = [UIAlertController alertControllerWithTitle:(result ? @"执行完成" : @"执行失败") message:message preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:done animated:YES completion:nil];
    }
}
@end

@interface ZNIL2CPPInvokeEngine (ZNM51ImmediateChain)
- (NSDictionary<NSString *,id> *)znm51_executeAction:(ZNRuntimeMethodAction *)action error:(NSString **)error;
@end

@implementation ZNIL2CPPInvokeEngine (ZNM51ImmediateChain)
- (NSDictionary<NSString *,id> *)znm51_executeAction:(ZNRuntimeMethodAction *)action error:(NSString **)error {
    NSDictionary *primary = [self znm51_executeAction:action error:error];
    if (!primary || !action.immediateChain.count) return primary;
    NSString *kind = [primary[@"returnKind"] isKindOfClass:NSString.class] ? primary[@"returnKind"] : @"";
    uintptr_t raw = [primary[@"returnRawObject"] unsignedLongLongValue];
    if (!raw || ![kind containsString:@"managed reference"]) { if (error) *error = @"Immediate Chain：主方法没有返回 managed-reference"; return nil; }
    NSDictionary *chain = action.immediateChain;
    ZNRuntimeMethodAction *next = [ZNRuntimeMethodAction new];
    next.title = @"Immediate Chain";
    next.assembly = [chain[@"assembly"] isKindOfClass:NSString.class] ? chain[@"assembly"] : action.assembly;
    next.namespaceName = [chain[@"namespace"] isKindOfClass:NSString.class] ? chain[@"namespace"] : @"";
    next.className = [chain[@"class"] isKindOfClass:NSString.class] ? chain[@"class"] : @"";
    next.methodName = [chain[@"method"] isKindOfClass:NSString.class] ? chain[@"method"] : @"";
    next.argumentCount = [chain[@"argumentCount"] unsignedIntegerValue];
    next.argumentValues = [chain[@"argumentValues"] isKindOfClass:NSArray.class] ? chain[@"argumentValues"] : @[];
    next.signatureAvailable = NO;
    NSString *chainError = nil;
    NSDictionary *second = [self znm51_executeAction:next error:&chainError];
    if (!second) { if (error) *error = chainError ?: @"Immediate Chain 第二跳失败"; return nil; }
    NSMutableDictionary *merged = [second mutableCopy];
    merged[@"immediateChain"] = @YES;
    merged[@"chainPrimaryReturnType"] = primary[@"returnType"] ?: @"?";
    merged[@"chainPrimaryRawObject"] = primary[@"returnRawObject"] ?: @0;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.1-chain] %@ -> %@::%@/%lu SUCCESS", action.canonicalIdentity, next.className, next.methodName, (unsigned long)next.argumentCount]];
    return [merged copy];
}
@end

static void ZN51Swap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM51RuntimeArgControlsImmediateChainDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (menu) {
            ZN51Swap(menu, @selector(zn50b_renderOther), @selector(zn51_builderRender));
            ZN51Swap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(zn51_finderRender:));
            ZN51Swap(menu, @selector(zn50_renderFeatureGroupsFull), @selector(zn51_runtimeFull));
            ZN51Swap(menu, @selector(zn50_renderFeatureGroupsCompact), @selector(zn51_runtimeCompact));
        }
        ZN51Swap(ZNIL2CPPInvokeEngine.class, @selector(executeAction:error:), @selector(znm51_executeAction:error:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.1] per-argument runtime controls + Immediate Chain installed"];
    });
}
