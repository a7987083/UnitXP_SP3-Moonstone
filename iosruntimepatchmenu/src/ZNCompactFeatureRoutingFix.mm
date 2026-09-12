#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Compact mode is a feature-only surface. The expanded menu may currently be
// on Theme/Settings/Diagnostics, but collapsing it must still render the same
// ZNF1-backed Feature list instead of falling back to the legacy compact page.
// Keep selectedCategory untouched so expanding returns to the previous page.

@interface ZNRuntimeMenuControllerV040 : NSObject
- (void)renderCompactPage;
- (void)zn50_renderFeatureGroupsCompact;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNCompactFeatureRoutingFix)

- (void)zn51_renderCompactPage {
    [self zn50_renderFeatureGroupsCompact];
}

@end

static void ZN51SwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(122))) static void ZNInstallCompactFeatureRoutingFix(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN51SwapInstanceMethod(cls,
                               @selector(renderCompactPage),
                               @selector(zn51_renderCompactPage));
        NSLog(@"[ZonoPatch] compact mode pinned to ZNF1 feature renderer");
    }
}
