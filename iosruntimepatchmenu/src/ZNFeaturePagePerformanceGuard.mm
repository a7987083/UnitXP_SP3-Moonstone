#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M5.9.2 UI performance guard.
// This does not own or render the Feature page. It only replaces the legacy
// M5.8.4 layout helper implementation before that helper is rebound onto the
// controller, so keyboard/layout changes no longer trigger renderPage.

static const CGFloat kZNPGHeaderH = 52.0;
static const CGFloat kZNPGFooterH = 22.0;
static const CGFloat kZNPGSidebarPhoneW = 78.0;
static const CGFloat kZNPGSidebarWideW = 86.0;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIView *headerView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIView *readyDot;
@property(nonatomic,strong) UILabel *readyLabel;
@property(nonatomic,strong) UIButton *themeButton;
@property(nonatomic,strong) UIButton *modeButton;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UIView *sidebarView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIView *footerView;
@property(nonatomic,strong) UILabel *footerLabel;
@property(nonatomic,strong) NSMutableArray<UIButton *> *sidebarButtons;
@property(nonatomic,assign) BOOL compactMode;
@property(nonatomic,strong) ZNTheme *theme;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (void)znm584_layoutSidebar;
- (void)znm584_layoutPanel;
- (void)znm584_renderRuntime:(BOOL)compact;
@end

@interface ZNRuntimeMenuControllerV040 (ZNFeaturePagePerformanceGuard)
- (void)znpg_layoutPanelNoRender;
- (void)znpg_legacyRuntimeNoop:(BOOL)compact;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeaturePagePerformanceGuard)

- (void)znpg_layoutPanelNoRender {
    CGFloat w = CGRectGetWidth(self.panel.bounds);
    CGFloat h = CGRectGetHeight(self.panel.bounds);

    if (self.compactMode) {
        CGFloat headerH = 48.0;
        self.headerView.frame = CGRectMake(0, 0, w, headerH);
        self.titleLabel.text = @"ZN";
        self.titleLabel.frame = CGRectMake(12, 7, 42, 20);
        self.subtitleLabel.hidden = NO;
        self.subtitleLabel.text = @"Compact";
        self.subtitleLabel.frame = CGRectMake(12, 25, 60, 15);
        self.readyDot.hidden = YES;
        self.readyLabel.hidden = YES;
        self.themeButton.hidden = YES;
        self.modeButton.hidden = NO;
        self.closeButton.hidden = NO;
        self.closeButton.frame = CGRectMake(w - 40, 7, 32, 32);
        self.modeButton.frame = CGRectMake(w - 78, 7, 32, 32);
        [self.modeButton setTitle:@"□" forState:UIControlStateNormal];
        self.sidebarView.hidden = YES;
        self.footerView.hidden = YES;
        self.contentScroll.frame = CGRectMake(0, headerH, w, MAX(0.0, h - headerH));
    } else {
        self.headerView.frame = CGRectMake(0, 0, w, kZNPGHeaderH);
        self.titleLabel.text = @"ZONOE PATCH";
        self.subtitleLabel.hidden = YES;
        self.titleLabel.frame = CGRectMake(14, 0, MAX(118.0, w - 252.0), kZNPGHeaderH);
        self.titleLabel.font = [self menuFont:16.0 weight:UIFontWeightHeavy];

        CGFloat buttonSize = 34.0;
        CGFloat buttonGap = 6.0;
        CGFloat right = 8.0;
        self.closeButton.hidden = NO;
        self.modeButton.hidden = NO;
        self.themeButton.hidden = NO;
        self.closeButton.frame = CGRectMake(w - right - buttonSize, 9, buttonSize, buttonSize);
        self.modeButton.frame = CGRectMake(CGRectGetMinX(self.closeButton.frame) - buttonGap - buttonSize, 9, buttonSize, buttonSize);
        self.themeButton.frame = CGRectMake(CGRectGetMinX(self.modeButton.frame) - buttonGap - buttonSize, 9, buttonSize, buttonSize);
        [self.modeButton setTitle:@"—" forState:UIControlStateNormal];
        self.modeButton.titleLabel.font = [self menuFont:15.0 weight:UIFontWeightSemibold];

        CGFloat readyRight = CGRectGetMinX(self.themeButton.frame) - 8.0;
        self.readyLabel.hidden = NO;
        self.readyDot.hidden = NO;
        self.readyLabel.frame = CGRectMake(readyRight - 48.0, 14, 42.0, 24.0);
        self.readyDot.frame = CGRectMake(CGRectGetMinX(self.readyLabel.frame) - 12.0, 22.0, 8.0, 8.0);

        CGFloat sidebarW = w < 430.0 ? kZNPGSidebarPhoneW : kZNPGSidebarWideW;
        CGFloat bodyH = MAX(0.0, h - kZNPGHeaderH - kZNPGFooterH);
        self.sidebarView.hidden = NO;
        self.footerView.hidden = NO;
        self.sidebarView.frame = CGRectMake(0, kZNPGHeaderH, sidebarW, bodyH);
        self.contentScroll.frame = CGRectMake(sidebarW, kZNPGHeaderH, MAX(0.0, w - sidebarW), bodyH);
        self.footerView.frame = CGRectMake(0, h - kZNPGFooterH, w, kZNPGFooterH);
        self.footerLabel.frame = CGRectMake(10, 0, w - 20, kZNPGFooterH);
        self.footerLabel.alpha = 0.82;
        self.footerLabel.font = [self menuFont:8.0 weight:UIFontWeightRegular];
        [self znm584_layoutSidebar];
    }

    // Layout only. Never call renderPage from geometry changes. This is the
    // critical keyboard/open-menu performance invariant for the rebuild.
    self.contentView.frame = CGRectMake(0,
                                        0,
                                        CGRectGetWidth(self.contentScroll.bounds),
                                        MAX(CGRectGetHeight(self.contentScroll.bounds), self.contentView.frame.size.height));
}

- (void)znpg_legacyRuntimeNoop:(BOOL)compact { (void)compact; }
@end

__attribute__((constructor)) static void ZNFeaturePagePerformanceGuardBootstrap(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method legacyLayout = class_getInstanceMethod(cls, @selector(znm584_layoutPanel));
        Method fastLayout = class_getInstanceMethod(cls, @selector(znpg_layoutPanelNoRender));
        if (legacyLayout && fastLayout) {
            method_setImplementation(legacyLayout, method_getImplementation(fastLayout));
        }

        // M5.8.4 later installs the implementation of znm584_renderRuntime: onto
        // zn51_renderRuntime:. Replacing the source helper now guarantees the
        // historical renderer cannot reintroduce a dyld-wide runtime refresh.
        Method legacyRuntime = class_getInstanceMethod(cls, @selector(znm584_renderRuntime:));
        Method runtimeNoop = class_getInstanceMethod(cls, @selector(znpg_legacyRuntimeNoop:));
        if (legacyRuntime && runtimeNoop) {
            method_setImplementation(legacyRuntime, method_getImplementation(runtimeNoop));
        }

        [[ZNRuntimeLogger sharedLogger] log:@"[feature-page-perf] legacy M584 render-on-layout and runtime refresh path disabled"];
    }
}
