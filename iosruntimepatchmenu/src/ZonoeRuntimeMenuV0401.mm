#include "ZonoeRuntimeMenuV040.mm"

// v0.4.0a UI hotfix layer.
// Keep the v0.4.0 runtime foundation unchanged and patch only navigation/touch behavior.

@interface ZNRuntimeMenuControllerV040 (V0401)
- (NSArray<NSString *> *)zn401_baseCategories;
- (NSArray<NSString *> *)zn401_baseSymbols;
- (void)zn401_makeUI:(UIWindow *)window;
- (void)zn401_themeTapped:(id)sender;
- (CGSize)zn401_fullSizeForWindow:(UIWindow *)window;
- (UIButton *)zn401_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
@end

@implementation ZNRuntimeMenuControllerV040 (V0401)

- (NSArray<NSString *> *)zn401_baseCategories {
    return @[@"玩家", @"战斗", @"移动", @"其他", @"设置", @"主题"];
}

- (NSArray<NSString *> *)zn401_baseSymbols {
    return @[@"person.fill", @"bolt.fill", @"location.north.fill", @"square.grid.2x2.fill", @"gearshape.fill", @"paintpalette.fill"];
}

- (void)zn401_makeUI:(UIWindow *)window {
    [self zn401_makeUI:window];
    // UIScrollView defaults to delayed content touches. That makes the diagnostic
    // buttons look as if they only react after a press-and-hold. Disable the delay
    // so a normal tap highlights and dispatches immediately.
    self.contentScroll.delaysContentTouches = NO;
    self.contentScroll.canCancelContentTouches = YES;
}

- (void)zn401_themeTapped:(id)sender {
    (void)sender;
    if (self.compactMode) return;
    NSInteger idx = [self.categories indexOfObject:@"主题"];
    if (idx == NSNotFound) return;
    self.selectedCategory = idx;
    [NSUserDefaults.standardUserDefaults setInteger:idx forKey:@"ZonoePatch.SelectedCategory"];
    self.contentScroll.contentOffset = CGPointZero;
    [self layoutForWindow:self.hostWindow initial:NO];
    [self updateSidebar];
    [self renderPage];
}

- (CGSize)zn401_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn401_fullSizeForWindow:window];
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    CGFloat desired = size.height;
    if ([cat isEqualToString:@"玩家"]) desired = 370.0;
    else if ([cat isEqualToString:@"战斗"] || [cat isEqualToString:@"移动"]) desired = 390.0;
    else if ([cat isEqualToString:@"其他"]) desired = 340.0;
    else if ([cat isEqualToString:@"设置"]) desired = 415.0;
    else if ([cat isEqualToString:@"主题"]) {
        BOOL landscape = CGRectGetWidth(window.bounds) >= CGRectGetHeight(window.bounds);
        desired = landscape ? 410.0 : 430.0;
    } else if ([cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"]) {
        desired = MAX(desired, 470.0);
    }
    UIEdgeInsets insets = window.safeAreaInsets;
    CGFloat available = MAX(300.0, CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0);
    size.height = MIN(desired, available);
    return size;
}

- (UIButton *)zn401_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
    UIButton *button = [self zn401_button:title selector:selector frame:frame];
    button.showsTouchWhenHighlighted = YES;
    button.exclusiveTouch = YES;
    return button;
}

@end

static void ZNSwapInstanceMethodV0401(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(102))) static void ZNInstallV0401UIFixes(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV0401(cls, @selector(zn40_baseCategories), @selector(zn401_baseCategories));
        ZNSwapInstanceMethodV0401(cls, @selector(zn40_baseSymbols), @selector(zn401_baseSymbols));
        ZNSwapInstanceMethodV0401(cls, @selector(makeUI:), @selector(zn401_makeUI:));
        ZNSwapInstanceMethodV0401(cls, @selector(themeTapped:), @selector(zn401_themeTapped:));
        ZNSwapInstanceMethodV0401(cls, @selector(fullSizeForWindow:), @selector(zn401_fullSizeForWindow:));
        ZNSwapInstanceMethodV0401(cls, @selector(zn40_button:selector:frame:), @selector(zn401_button:selector:frame:));
        [[ZNRuntimeLogger sharedLogger] log:@"v0.4.0a UI fixes installed：首页已移除，诊断按钮即时触摸已启用"];
    }
}
