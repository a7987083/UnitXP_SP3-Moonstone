#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM551ExecTag = 796000;
static const NSInteger kZNM551SliderTag = 799000;
static const void *kZNM551CommitInstalledKey = &kZNM551CommitInstalledKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
- (void)zn51_runtimeSliderChanged:(UISlider *)control;
- (void)znm55_runtimeSliderChanged:(UISlider *)control;
- (void)zn51_runtimeExecute:(UIButton *)sender;
@end

@interface ZNRuntimeMenuControllerV040 (ZNM551RuntimeSliderStability)
- (void)znm551_runtimeSliderChanged:(UISlider *)control;
- (void)znm551_runtimeSliderCommitted:(UISlider *)control;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM551RuntimeSliderStability)

- (void)znm551_runtimeSliderChanged:(UISlider *)control {
    // M5.5 previously refreshed/parsing the Runtime Action table on every
    // UIControlEventValueChanged. A drag can emit dozens/hundreds of events.
    // Keep the hot path identical to the old M5.1 cache-only handler by calling
    // the post-M5.5 alias, which points at the lightweight base implementation.
    [self znm55_runtimeSliderChanged:control];

    if (![objc_getAssociatedObject(control, kZNM551CommitInstalledKey) boolValue]) {
        [control addTarget:self
                    action:@selector(znm551_runtimeSliderCommitted:)
          forControlEvents:(UIControlEventTouchUpInside |
                            UIControlEventTouchUpOutside |
                            UIControlEventTouchCancel)];
        objc_setAssociatedObject(control, kZNM551CommitInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)znm551_runtimeSliderCommitted:(UISlider *)control {
    NSInteger slot = control.tag - kZNM551SliderTag;
    if (slot < 0) return;

    NSUInteger recordIndex = (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS;
    NSUInteger arg = (NSUInteger)slot % ZN_RUNTIME_ACTION_MAX_ARGUMENTS;

    // Expensive table refresh happens once per gesture, never in ValueChanged.
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if (recordIndex >= runtime.records.count) return;

    ZNRuntimeMethodActionRecord *record = runtime.records[recordIndex];
    if (arg >= record.argumentCount || record.argumentControlConfigs.count != record.argumentCount) return;

    NSDictionary *cfg = record.argumentControlConfigs[arg];
    double step = [cfg[@"step"] doubleValue];
    double min = [cfg[@"min"] doubleValue];
    double max = [cfg[@"max"] doubleValue];
    if (!(step > 0.0) || !isfinite(step)) step = 1.0;
    if (!isfinite(min)) min = control.minimumValue;
    if (!isfinite(max) || max < min) max = control.maximumValue;

    double q = min + round(((double)control.value - min) / step) * step;
    q = MAX((double)control.minimumValue, MIN((double)control.maximumValue, q));
    q = MAX(min, MIN(max, q));
    control.value = (float)q;

    // Cache the final quantized value exactly once using the lightweight base
    // handler, then execute once. No renderPage and no repeated invoke while drag.
    [self znm55_runtimeSliderChanged:control];

    UIButton *proxy = [UIButton buttonWithType:UIButtonTypeCustom];
    proxy.tag = kZNM551ExecTag + (NSInteger)recordIndex;
    [self zn51_runtimeExecute:proxy];
}

@end

extern "C" void ZNInstallM551RuntimeSliderStabilityDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        // Install last, after M5.5 + M5.3. This makes ValueChanged land here.
        // znm55_runtimeSliderChanged: remains the lightweight M5.1 base alias.
        Method current = class_getInstanceMethod(cls, @selector(zn51_runtimeSliderChanged:));
        Method stable = class_getInstanceMethod(cls, @selector(znm551_runtimeSliderChanged:));
        if (current && stable) method_exchangeImplementations(current, stable);

        [[ZNRuntimeLogger sharedLogger] log:@"[m5.5.1-slider] ValueChanged cache-only; quantize+refresh+invoke on release"];
    });
}
