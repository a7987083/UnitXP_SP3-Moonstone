#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionRuntime.h"
#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNPatchCore.h"

static const NSInteger kZN49FeatureExecuteTagBase = 672000;
static const NSInteger kZN49FeatureCompactExecuteTagBase = 673000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)znrmc_executeAction:(UIButton *)sender;
@end

static UIViewController *ZN49TopController(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
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

@interface ZNRuntimeMenuControllerV040 (ZNM49GenericInvokeEditableArgs)
- (void)zn49_executeAction:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM49GenericInvokeEditableArgs)

- (void)zn49_executeAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZN49FeatureExecuteTagBase;
    if (sender.tag >= kZN49FeatureCompactExecuteTagBase) index = sender.tag - kZN49FeatureCompactExecuteTagBase;
    if (index < 0) {
        [self zn49_executeAction:sender];
        return;
    }

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) {
        [self zn49_executeAction:sender];
        return;
    }

    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    if (record.argumentCount == 0) {
        [self zn49_executeAction:sender];
        return;
    }

    if (record.argumentCount > 8) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.9-generic] reject argc=%lu %@",
                                             (unsigned long)record.argumentCount,
                                             record.canonicalIdentity]];
        return;
    }

    UIViewController *presenter = ZN49TopController(self.hostWindow);
    if (!presenter) return;

    NSString *title = record.title.length ? record.title : record.methodName;
    NSString *message = [NSString stringWithFormat:@"%@\n可修改任意参数；未修改项继续使用保存值。",
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

        NSString *oldTitle = [button titleForState:UIControlStateNormal] ?: @"执行";
        [button setTitle:@"执行中" forState:UIControlStateNormal];

        NSString *invokeError = nil;
        NSDictionary *result = ZN49ExecuteRecordWithValues(record, values, &invokeError);
        BOOL ok = result != nil;
        [button setTitle:(ok ? @"完成" : @"失败") forState:UIControlStateNormal];

        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.9-generic] %@ %@ args=%@%@",
                                             ok ? @"SUCCESS" : @"FAILED",
                                             record.canonicalIdentity ?: @"",
                                             values,
                                             invokeError.length ? [@" · " stringByAppendingString:invokeError] : @""]];

        UIViewController *top = ZN49TopController(selfRef.hostWindow);
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
    }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

extern "C" void ZNInstallM49GenericInvokeEditableArgsDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(znrmc_executeAction:));
        Method replacement = class_getInstanceMethod(cls, @selector(zn49_executeAction:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.9-generic] Runtime editable args installed (/1-/8)"];
    });
}
