#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

// M5.1 customer runtime UX: successful customer actions execute silently.
// Builder / finder test surfaces remain unchanged so developer return inspection is preserved.
static const NSInteger kZN51SExecTag = 796000;
static const NSInteger kZN51SFieldTag = 797000;
static const NSInteger kZN51SSwitchTag = 798000;
static const NSInteger kZN51SSliderTag = 799000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)zn51_runtimeExecute:(UIButton *)sender;
@end

static UIViewController *ZN51STop(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static NSString *ZN51SValueForControl(ZNRuntimeMenuControllerV040 *controller,
                                      NSUInteger recordIndex,
                                      NSUInteger argIndex,
                                      NSDictionary *cfg,
                                      NSString *fallback) {
    NSInteger slot = (NSInteger)(recordIndex * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + argIndex);
    ZNRuntimeArgumentControlType type = ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);

    if (type == ZNRuntimeArgumentControlTypeSwitch) {
        UIView *view = [controller.contentView viewWithTag:kZN51SSwitchTag + slot];
        if ([view isKindOfClass:UISwitch.class]) return ((UISwitch *)view).on ? @"true" : @"false";
    } else if (type == ZNRuntimeArgumentControlTypeSlider) {
        UIView *view = [controller.contentView viewWithTag:kZN51SSliderTag + slot];
        if ([view isKindOfClass:UISlider.class]) {
            float value = ((UISlider *)view).value;
            float step = [cfg[@"step"] floatValue];
            if (step > 0) value = roundf(value / step) * step;
            return [NSString stringWithFormat:@"%.7g", value];
        }
    } else if (type == ZNRuntimeArgumentControlTypeNumber) {
        UIView *view = [controller.contentView viewWithTag:kZN51SFieldTag + slot];
        if ([view isKindOfClass:UITextField.class]) return ((UITextField *)view).text ?: fallback ?: @"";
    }

    // Button controls trigger execution but do not replace their underlying argument value.
    return fallback ?: @"";
}

@interface ZNRuntimeMenuControllerV040 (ZNM51SilentCustomerExecution)
- (void)zn51s_runtimeExecuteSilent:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM51SilentCustomerExecution)

- (void)zn51s_runtimeExecuteSilent:(UIButton *)sender {
    NSInteger index = sender.tag - kZN51SExecTag;
    if (index < 0) return;

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) return;

    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithArray:record.argumentValues ?: @[]];
    while (values.count < record.argumentCount) [values addObject:@""];

    if (record.argumentControlConfigs.count == record.argumentCount) {
        for (NSUInteger arg = 0; arg < record.argumentCount; arg++) {
            NSDictionary *cfg = record.argumentControlConfigs[arg];
            if (![cfg[@"enabled"] boolValue]) continue;
            NSString *fallback = arg < record.argumentValues.count ? record.argumentValues[arg] : @"";
            values[arg] = ZN51SValueForControl(self, (NSUInteger)index, arg, cfg, fallback);
        }
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
    action.argumentValues = values;
    action.parameterTypeNames = record.parameterTypeNames;
    action.signatureAvailable = record.signatureAvailable;
    action.argumentControlConfigs = record.argumentControlConfigs;
    action.immediateChain = record.immediateChain;

    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    if (result) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.1-silent] %@ SUCCESS", action.canonicalIdentity ?: @"?"]];
        return;
    }

    // Failure remains visible. Success is deliberately silent for customer-facing controls.
    UIViewController *top = ZN51STop(self.hostWindow);
    if (!top) return;
    UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"执行失败"
                                                                    message:(error.length ? error : @"执行失败")
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [failed addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:failed animated:YES completion:nil];
}

@end

static void ZN51SSwapSilentCustomerExecution(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
    if (!cls) return;
    Method original = class_getInstanceMethod(cls, @selector(zn51_runtimeExecute:));
    Method silent = class_getInstanceMethod(cls, @selector(zn51s_runtimeExecuteSilent:));
    if (!original || !silent) return;
    method_exchangeImplementations(original, silent);
    [[ZNRuntimeLogger sharedLogger] log:@"[m5.1-silent] customer runtime success dialogs disabled; failure dialogs preserved"];
}

__attribute__((constructor)) static void ZN51SInstallSilentCustomerExecution(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ ZN51SSwapSilentCustomerExecution(); });
    });
}
