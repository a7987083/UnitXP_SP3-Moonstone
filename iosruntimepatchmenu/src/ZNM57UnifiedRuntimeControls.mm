#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNRuntimeActionFormat.h"
#import "ZNPatchCore.h"

// M5.7: one public event owner for Runtime Method controls.
//
// Interaction contract shared with Static/Offset Feature controls:
//   Switch  -> commit immediately.
//   Button  -> existing Execute button commits immediately.
//   Number  -> editing only updates the visible value; Return/Done dismisses
//              keyboard; explicit Execute commits.
//   Slider  -> ValueChanged is UI-only; TouchUp commits exactly once.
//
// The implementation intentionally does NOT call any historical
// zn51/znm53/znm55/znm551 handler. This prevents the previous layered swizzle
// chain from owning the same event more than once.

static const NSInteger kZNM57ExecTag   = 796000;
static const NSInteger kZNM57FieldTag  = 797000;
static const NSInteger kZNM57SwitchTag = 798000;
static const NSInteger kZNM57SliderTag = 799000;
static const void *kZNM57NumberReturnInstalledKey = &kZNM57NumberReturnInstalledKey;
static const void *kZNM57SliderCommitInstalledKey = &kZNM57SliderCommitInstalledKey;
static const void *kZNM57SliderCommittingKey = &kZNM57SliderCommittingKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
- (void)zn51_runtimeExecute:(UIButton *)sender;
- (void)zn51_runtimeNumberChanged:(UITextField *)field;
- (void)zn51_runtimeSwitchChanged:(UISwitch *)control;
- (void)zn51_runtimeSliderChanged:(UISlider *)control;
@end

@interface ZNRuntimeMenuControllerV040 (ZNM57UnifiedRuntimeControls)
- (void)znm57_runtimeNumberChanged:(UITextField *)field;
- (void)znm57_runtimeNumberReturn:(UITextField *)field;
- (void)znm57_runtimeSwitchChanged:(UISwitch *)control;
- (void)znm57_runtimeSliderChanged:(UISlider *)control;
- (void)znm57_runtimeSliderCommitted:(UISlider *)control;
@end

static UIButton *ZNM57ExecuteProxy(NSUInteger recordIndex) {
    UIButton *proxy = [UIButton buttonWithType:UIButtonTypeCustom];
    proxy.tag = kZNM57ExecTag + (NSInteger)recordIndex;
    return proxy;
}

@implementation ZNRuntimeMenuControllerV040 (ZNM57UnifiedRuntimeControls)

- (void)znm57_runtimeNumberChanged:(UITextField *)field {
    if (![field isKindOfClass:UITextField.class]) return;
    field.returnKeyType = UIReturnKeyDone;
    if (![objc_getAssociatedObject(field, kZNM57NumberReturnInstalledKey) boolValue]) {
        [field addTarget:self
                  action:@selector(znm57_runtimeNumberReturn:)
        forControlEvents:UIControlEventEditingDidEndOnExit];
        objc_setAssociatedObject(field, kZNM57NumberReturnInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Deliberately no Invoke here. The current text remains the source of truth;
    // zn51_runtimeExecute:/silent execution reads the visible UITextField.
}

- (void)znm57_runtimeNumberReturn:(UITextField *)field {
    [self znm57_runtimeNumberChanged:field];
    [field resignFirstResponder];
}

- (void)znm57_runtimeSwitchChanged:(UISwitch *)control {
    if (![control isKindOfClass:UISwitch.class]) return;
    NSInteger slot = control.tag - kZNM57SwitchTag;
    if (slot < 0) return;
    NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    // Switch is an immediate control by product contract.
    [self zn51_runtimeExecute:ZNM57ExecuteProxy(recordIndex)];
}

- (void)znm57_runtimeSliderChanged:(UISlider *)control {
    if (![control isKindOfClass:UISlider.class]) return;
    float value = control.value;
    if (!isfinite(value)) value = control.minimumValue;
    // Customer sliders are integer-step by product contract. Do not refresh the
    // Runtime Action table here: this method is the drag hot path.
    value = roundf(value);
    value = MAX(control.minimumValue, MIN(control.maximumValue, value));
    control.value = value;

    if (![objc_getAssociatedObject(control, kZNM57SliderCommitInstalledKey) boolValue]) {
        [control addTarget:self
                    action:@selector(znm57_runtimeSliderCommitted:)
          forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside)];
        objc_setAssociatedObject(control, kZNM57SliderCommitInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)znm57_runtimeSliderCommitted:(UISlider *)control {
    if (![control isKindOfClass:UISlider.class]) return;
    if ([objc_getAssociatedObject(control, kZNM57SliderCommittingKey) boolValue]) return;
    objc_setAssociatedObject(control, kZNM57SliderCommittingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self znm57_runtimeSliderChanged:control];
    NSInteger slot = control.tag - kZNM57SliderTag;
    if (slot >= 0) {
        NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
        // Commit once after the gesture. The customer execution path reads the
        // current visible UISlider value and performs the actual IL2CPP Invoke.
        [self zn51_runtimeExecute:ZNM57ExecuteProxy(recordIndex)];
    }

    objc_setAssociatedObject(control, kZNM57SliderCommittingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

static void ZNM57Replace(Class cls, SEL selector, SEL replacement) {
    Method current = class_getInstanceMethod(cls, selector);
    Method next = class_getInstanceMethod(cls, replacement);
    if (current && next) method_setImplementation(current, method_getImplementation(next));
}

extern "C" void ZNInstallM57UnifiedRuntimeControlsDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM57Replace(cls, @selector(zn51_runtimeNumberChanged:), @selector(znm57_runtimeNumberChanged:));
        ZNM57Replace(cls, @selector(zn51_runtimeSwitchChanged:), @selector(znm57_runtimeSwitchChanged:));
        ZNM57Replace(cls, @selector(zn51_runtimeSliderChanged:), @selector(znm57_runtimeSliderChanged:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.7-controls] Runtime single-owner installed: Number=save/Return-dismiss/manual Execute, Slider=UI-only drag/single TouchUp commit, Switch=immediate"];
    });
}
