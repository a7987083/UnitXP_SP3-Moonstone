#include "ZonoeRuntimeMenuV0401.mm"

// v0.4.0b touch-policy scope fix.
// Diagnostic/Debug pages keep immediate button response; all other pages restore
// UIScrollView's delayed-touch behavior so theme grids and sliders scroll normally.

@interface ZNRuntimeMenuControllerV040 (V0402)
- (void)zn402_applyTouchPolicy;
- (void)zn402_makeUI:(UIWindow *)window;
- (void)zn402_renderPage;
@end

@implementation ZNRuntimeMenuControllerV040 (V0402)

- (void)zn402_applyTouchPolicy {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count)
        ? self.categories[self.selectedCategory]
        : @"";
    BOOL developerPage = [cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"];

    // Developer pages: buttons should highlight/dispatch immediately.
    // Normal pages (especially 主题): restore UIScrollView's gesture arbitration.
    self.contentScroll.delaysContentTouches = !developerPage;
    self.contentScroll.canCancelContentTouches = YES;
}

- (void)zn402_makeUI:(UIWindow *)window {
    [self zn402_makeUI:window];
    [self zn402_applyTouchPolicy];
}

- (void)zn402_renderPage {
    [self zn402_applyTouchPolicy];
    [self zn402_renderPage];
}

@end

static void ZNSwapInstanceMethodV0402(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(103))) static void ZNInstallV0402TouchPolicyFix(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV0402(cls, @selector(makeUI:), @selector(zn402_makeUI:));
        ZNSwapInstanceMethodV0402(cls, @selector(renderPage), @selector(zn402_renderPage));
        [[ZNRuntimeLogger sharedLogger] log:@"v0.4.0b touch policy installed：诊断/Debug 即时触摸，其余页面恢复滚动优先"];
    }
}
