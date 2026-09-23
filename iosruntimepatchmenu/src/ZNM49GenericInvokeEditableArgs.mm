#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionRuntime.h"
#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M4.9.1: render Runtime Method Actions from the outermost runtime-menu layer.
// This deliberately does not depend on the legacy znrmc_executeAction: selector,
// because later/earlier renderer swizzles can leave that path invisible in the
// generated-binary runtime UI. The buttons below bind directly to M4.9.
static const NSInteger kZN49RuntimeButtonTagBase = 784000;
static const NSInteger kZN49RuntimeCardTagBase = 786000;
static const NSInteger kZN49LegacyFullTagBase = 672000;
static const NSInteger kZN49LegacyCompactTagBase = 673000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static UIViewController *ZN49TopController(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static CGFloat ZN49MaxY(UIView *view) {
    CGFloat y = 0.0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

static UIKeyboardType ZN49KeyboardForType(NSString *typeName) {
    NSString *n = (typeName ?: @"").lowercaseString;
    if ([n containsString:@"int"] || [n containsString:@"uint"] || [n containsString:@"enum"] ||
        [n containsString:@"byte"] || [n containsString:@"sbyte"] || [n containsString:@"short"] ||
        [n containsString:@"long"]) return UIKeyboardTypeNumbersAndPunctuation;
    if ([n containsString:@"single"] || [n containsString:@"float"] || [n containsString:@"double"] ||
        [n containsString:@"decimal"]) return UIKeyboardTypeDecimalPad;
    return UIKeyboardTypeDefault;
}

static NSString *ZN49ReturnSummary(NSDictionary *result) {
    NSString *type = [result[@"returnType"] isKindOfClass:NSString.class] ? result[@"returnType"] : @"";
    NSString *value = [result[@"returnValue"] isKindOfClass:NSString.class] ? result[@"returnValue"] : @"";
    NSString *raw = [result[@"returnRawObject"] isKindOfClass:NSString.class] ? result[@"returnRawObject"] : @"";
    if (!type.length && !value.length) return @"执行成功";
    if (raw.length) return [NSString stringWithFormat:@"返回 %@ = %@\nraw=%@", type.length ? type : @"?", value.length ? value : @"?", raw];
    return [NSString stringWithFormat:@"返回 %@ = %@", type.length ? type : @"?", value.length ? value : @"?"];
}

static NSDictionary *ZN49ExecuteRecordWithValues(ZNRuntimeMethodActionRecord *record,
                                                   NSArray<NSString *> *values,
                                                   NSString **error) {
    if (!record) {
        if (error) *error = @"Runtime Method Call record 为空";
        return nil;
    }
    if (record.argumentCount != values.count) {
        if (error) *error = [NSString stringWithFormat:@"参数数量不匹配：需要 %lu，当前 %lu",
                             (unsigned long)record.argumentCount,
                             (unsigned long)values.count];
        return nil;
    }

    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.actionID = record.actionID;
    action.title = record.title;
    action.group = record.group;
    action.assembly = record.assembly;
    action.namespaceName = record.namespaceName;
    action.className = record.className;
    action.methodName = record.methodName;
    action.argumentCount = record.argumentCount;
    action.argumentValues = values ?: @[];
    action.parameterTypeNames = record.parameterTypeNames ?: @[];
    action.signatureAvailable = record.signatureAvailable;

    NSString *invokeError = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&invokeError];
    if (!result) {
        if (error) *error = invokeError ?: @"Runtime Method Call 执行失败";
        return nil;
    }
    return result;
}

static void ZN49RemoveLegacyRuntimeRows(UIView *contentView) {
    if (!contentView) return;
    for (UIView *card in [contentView.subviews copy]) {
        BOOL remove = NO;
        for (UIView *child in card.subviews) {
            NSInteger tag = child.tag;
            if ((tag >= kZN49LegacyFullTagBase && tag < kZN49LegacyFullTagBase + 512) ||
                (tag >= kZN49LegacyCompactTagBase && tag < kZN49LegacyCompactTagBase + 512) ||
                (tag >= kZN49RuntimeButtonTagBase && tag < kZN49RuntimeButtonTagBase + 512) ||
                (card.tag >= kZN49RuntimeCardTagBase && card.tag < kZN49RuntimeCardTagBase + 512)) {
                remove = YES;
                break;
            }
        }
        if (remove) [card removeFromSuperview];
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNM49GenericInvokeEditableArgs)
- (void)zn49_renderFull;
- (void)zn49_renderCompact;
- (void)zn49_runtimeActionTapped:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM49GenericInvokeEditableArgs)

- (void)zn49_renderRuntimeActionsCompact:(BOOL)compact {
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *records = runtime.records ?: @[];

    ZN49RemoveLegacyRuntimeRows(self.contentView);

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.9-generic] render scan actions=%lu compact=%@",
                                         (unsigned long)records.count,
                                         compact ? @"YES" : @"NO"]];
    if (!records.count) return;

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZN49MaxY(self.contentView) + (compact ? 6.0 : 8.0);
    for (NSUInteger i = 0; i < records.count; i++) {
        ZNRuntimeMethodActionRecord *record = records[i];
        CGFloat height = compact ? 40.0 : 46.0;
        UIView *card = [self cardAtY:y height:height width:width compact:compact];
        card.tag = kZN49RuntimeCardTagBase + (NSInteger)i;

        NSString *nameText = record.title.length ? record.title : record.methodName;
        UILabel *name = [self label:nameText
                                size:(compact ? 10.7 : 11.4)
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = compact
            ? CGRectMake(9, 10, card.bounds.size.width - 82, 20)
            : CGRectMake(13, 13, card.bounds.size.width - 100, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        UIButton *execute = [self zn40_button:@"执行"
                                      selector:@selector(zn49_runtimeActionTapped:)
                                         frame:(compact
                                                ? CGRectMake(card.bounds.size.width - 69, 6, 60, 28)
                                                : CGRectMake(card.bounds.size.width - 78, 8, 66, 30))];
        execute.tag = kZN49RuntimeButtonTagBase + (NSInteger)i;
        execute.accessibilityLabel = [NSString stringWithFormat:@"执行 %@", nameText ?: @"Runtime Action"];
        if (compact) execute.titleLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightSemibold];
        execute.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
        execute.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:execute];
        [self.contentView addSubview:card];
        y += compact ? 46.0 : 52.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn49_renderFull {
    [self zn49_renderFull];
    [self zn49_renderRuntimeActionsCompact:NO];
}

- (void)zn49_renderCompact {
    [self zn49_renderCompact];
    [self zn49_renderRuntimeActionsCompact:YES];
}

- (void)zn49_presentResultForButton:(UIButton *)button
                              record:(ZNRuntimeMethodActionRecord *)record
                              values:(NSArray<NSString *> *)values {
    NSString *oldTitle = [button titleForState:UIControlStateNormal] ?: @"执行";
    [button setTitle:@"执行中" forState:UIControlStateNormal];

    NSString *invokeError = nil;
    NSDictionary *result = ZN49ExecuteRecordWithValues(record, values ?: @[], &invokeError);
    BOOL ok = result != nil;
    [button setTitle:(ok ? @"完成" : @"失败") forState:UIControlStateNormal];

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.9-generic] %@ id=%u %@ args=%@%@",
                                         ok ? @"SUCCESS" : @"FAILED",
                                         record.actionID,
                                         record.canonicalIdentity ?: @"",
                                         values ?: @[],
                                         invokeError.length ? [@" · " stringByAppendingString:invokeError] : @""]];

    UIViewController *top = ZN49TopController(self.hostWindow);
    if (top) {
        NSString *resultMessage = ok ? ZN49ReturnSummary(result) : (invokeError ?: @"执行失败");
        UIAlertController *done = [UIAlertController alertControllerWithTitle:(ok ? @"执行完成" : @"执行失败")
                                                                        message:resultMessage
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:done animated:YES completion:nil];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [button setTitle:oldTitle forState:UIControlStateNormal];
    });
}

- (void)zn49_runtimeActionTapped:(UIButton *)sender {
    NSInteger index = sender.tag - kZN49RuntimeButtonTagBase;
    if (index < 0) return;

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.9-generic] tap stale index=%ld actions=%lu",
                                             (long)index,
                                             (unsigned long)runtime.records.count]];
        return;
    }

    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    if (record.argumentCount == 0) {
        [self zn49_presentResultForButton:sender record:record values:@[]];
        return;
    }
    if (record.argumentCount > 8) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.9-generic] reject argc=%lu %@",
                                             (unsigned long)record.argumentCount,
                                             record.canonicalIdentity ?: @""]];
        return;
    }

    UIViewController *presenter = ZN49TopController(self.hostWindow);
    if (!presenter) return;

    NSString *title = record.title.length ? record.title : record.methodName;
    NSString *message = [NSString stringWithFormat:@"%@\n修改需要变化的参数；其他参数保持默认值。",
                         record.canonicalIdentity ?: @""];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    for (NSUInteger i = 0; i < record.argumentCount; i++) {
        NSString *typeName = (i < record.parameterTypeNames.count) ? record.parameterTypeNames[i] : @"?";
        NSString *defaultValue = (i < record.argumentValues.count) ? record.argumentValues[i] : @"";
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = [NSString stringWithFormat:@"arg[%lu] · %@", (unsigned long)i, typeName ?: @"?"];
            field.text = defaultValue ?: @"";
            field.keyboardType = ZN49KeyboardForType(typeName);
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIButton *weakSender = sender;
    [alert addAction:[UIAlertAction actionWithTitle:@"执行" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) selfRef = weakSelf;
        UIButton *button = weakSender;
        if (!selfRef || !button) return;

        NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:record.argumentCount];
        for (NSUInteger i = 0; i < record.argumentCount; i++) {
            UITextField *field = (i < alert.textFields.count) ? alert.textFields[i] : nil;
            [values addObject:field.text ?: @""];
        }
        [selfRef zn49_presentResultForButton:button record:record values:values];
    }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

static void ZN49Swap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a);
    Method mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM49GenericInvokeEditableArgsDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        // Install last/outermost so generated-binary Runtime Actions are always
        // materialized as visible buttons after the rest of Feature UI renders.
        ZN49Swap(cls, @selector(zn50_renderFeatureGroupsFull), @selector(zn49_renderFull));
        ZN49Swap(cls, @selector(zn50_renderFeatureGroupsCompact), @selector(zn49_renderCompact));
        [[ZNRuntimeActionRuntime sharedRuntime] refresh];
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.9-generic] outer runtime renderer installed (/0-/8 + editable args)"];
    });
}
