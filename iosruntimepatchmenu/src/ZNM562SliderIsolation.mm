#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNPatchCore.h"

// M5.6.2 diagnostic/stability owner for customer Runtime sliders.
//
// Earlier milestones stacked M5.5 -> M5.3 -> M5.5.1 swizzles on the same
// zn51_runtimeSliderChanged: selector. Even when the hot path was intended to be
// cache-only, release handlers and Runtime refresh/invoke behavior remained
// coupled to that chain. For this build, one final owner replaces the selector
// outright: dragging only updates/quantizes the UISlider. It does not refresh
// Runtime Action tables, render, attach release targets, or invoke IL2CPP.
//
// The existing customer card's explicit "执行" button remains authoritative.
// ZNM51SilentCustomerExecution reads the current UISlider value directly from
// the visible control, so no private cache mutation is required here.

@interface ZNRuntimeMenuControllerV040 : NSObject
- (void)zn51_runtimeSliderChanged:(UISlider *)control;
@end

@interface ZNRuntimeMenuControllerV040 (ZNM562SliderIsolation)
- (void)znm562_sliderChangedIsolated:(UISlider *)control;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM562SliderIsolation)
- (void)znm562_sliderChangedIsolated:(UISlider *)control {
    if (![control isKindOfClass:UISlider.class]) return;
    float value = control.value;
    if (!isfinite(value)) value = control.minimumValue;
    // Product default is integer slider. Clamp + integer quantize only; do not
    // touch Runtime metadata or invoke any method from ValueChanged.
    value = MAX(control.minimumValue, MIN(control.maximumValue, roundf(value)));
    control.value = value;
}
@end

extern "C" void ZNInstallM562SliderIsolationDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method target = class_getInstanceMethod(cls, @selector(zn51_runtimeSliderChanged:));
        Method isolated = class_getInstanceMethod(cls, @selector(znm562_sliderChangedIsolated:));
        if (!target || !isolated) return;
        method_setImplementation(target, method_getImplementation(isolated));
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.6.2-slider] single-owner drag path installed: UI-only, no refresh/invoke; explicit Execute uses current slider value"];
    });
}
