#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"
#import "ZNTheme.h"

// M4.1 UI/UX repair layer.
// - Default Builder target: UnityFramework when present, otherwise main executable.
// - Builder target is a picker backed by app-local dyld images, not free text.
// - Builder can be generated directly; manual "读取验证" is optional. Build performs
//   the same required validation internally before entering Static Builder V3.
// - renderPage preserves the current UIScrollView position for same-page actions.
// - Menu panel is hosted by a real child UIViewController in the game's existing
//   UIWindow. Its transparent root returns nil from hitTest outside the panel so
//   Unity/game content below keeps receiving touches.

static NSString * const kZNUXSelectedTargetKey = @"ZonoePatch.Builder.SelectedTarget";
static const void *kZNUXAutoTargetInitializedKey = &kZNUXAutoTargetInitializedKey;
static const void *kZNUXOverlayControllerKey = &kZNUXOverlayControllerKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIButton *floatButton;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,assign) BOOL uiReady;
@property(nonatomic,strong) ZNTheme *theme;
- (UIWindow *)currentWindow;
- (void)tick:(NSTimer *)timer;
- (void)renderPage;
- (void)show;
- (void)hide;
- (BOOL)isVisible;
- (void)zn44_buildBinary:(id)sender;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
@end

@interface ZNUXPassthroughRootView : UIView
@end

@implementation ZNUXPassthroughRootView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // When the transparent root itself would consume the event, decline the hit.
    // Because this view is a child in the game's existing UIWindow hierarchy,
    // UIKit continues hit-testing sibling game views underneath it.
    return hit == self ? nil : hit;
}
@end

@interface ZNUXOverlayController : UIViewController
@property(nonatomic,strong) UIView *menuPanel;
- (instancetype)initWithPanel:(UIView *)panel;
@end

@implementation ZNUXOverlayController
- (instancetype)initWithPanel:(UIView *)panel {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _menuPanel = panel;
    return self;
}

- (void)loadView {
    ZNUXPassthroughRootView *root = [ZNUXPassthroughRootView new];
    root.backgroundColor = UIColor.clearColor;
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.menuPanel.superview != self.view) {
        [self.menuPanel removeFromSuperview];
        [self.view addSubview:self.menuPanel];
    }
}
@end

static UIViewController *ZNUXTopController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented = vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZNUXTopController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)vc).visibleViewController;
        return top ? ZNUXTopController(top) : vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
        return selected ? ZNUXTopController(selected) : vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last = ((UISplitViewController *)vc).viewControllers.lastObject;
        return last ? ZNUXTopController(last) : vc;
    }
    return vc;
}

static NSString *ZNUXStandardPath(NSString *path) {
    return path.length ? path.stringByStandardizingPath : @"";
}

static BOOL ZNUXIsAppLocalImage(NSDictionary<NSString *, id> *item) {
    NSString *path = ZNUXStandardPath(item[@"path"]);
    NSString *bundle = ZNUXStandardPath(NSBundle.mainBundle.bundlePath);
    NSString *main = ZNUXStandardPath(NSBundle.mainBundle.executablePath);
    if (!path.length || !bundle.length) return NO;
    if ([path isEqualToString:main]) return YES;
    NSString *frameworks = [bundle stringByAppendingPathComponent:@"Frameworks"];
    NSString *prefix = [frameworks stringByAppendingString:@"/"];
    return [path hasPrefix:prefix];
}

static NSInteger ZNUXImageRank(NSDictionary<NSString *, id> *item) {
    NSString *name = item[@"name"] ?: @"";
    NSString *path = ZNUXStandardPath(item[@"path"]);
    if ([name caseInsensitiveCompare:@"UnityFramework"] == NSOrderedSame ||
        [path hasSuffix:@"/UnityFramework.framework/UnityFramework"]) return 0;
    if ([path isEqualToString:ZNUXStandardPath(NSBundle.mainBundle.executablePath)]) return 1;
    if ([name.pathExtension caseInsensitiveCompare:@"dylib"] == NSOrderedSame) return 2;
    return 3;
}

static NSArray<NSDictionary<NSString *, id> *> *ZNUXAppLocalImages(void) {
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary<NSString *, id> *item in [ZNModuleManager sharedManager].loadedImages) {
        if (!ZNUXIsAppLocalImage(item)) continue;
        NSString *path = ZNUXStandardPath(item[@"path"]);
        if (!path.length || [seen containsObject:path]) continue;
        [seen addObject:path];
        [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> *a, NSDictionary<NSString *,id> *b) {
        NSInteger ra = ZNUXImageRank(a), rb = ZNUXImageRank(b);
        if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        NSString *na = a[@"name"] ?: @"";
        NSString *nb = b[@"name"] ?: @"";
        return [na localizedCaseInsensitiveCompare:nb];
    }];
    return items;
}

static NSString *ZNUXPreferredTarget(void) {
    NSDictionary *unity = [ZNModuleManager sharedManager].unityFramework;
    NSString *unityDiskPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
    BOOL unityExists = [[NSFileManager defaultManager] fileExistsAtPath:unityDiskPath];
    if (unity || unityExists) return @"UnityFramework";
    NSDictionary *main = [ZNModuleManager sharedManager].mainExecutable;
    NSString *name = [main[@"name"] isKindOfClass:NSString.class] ? main[@"name"] : @"";
    if (!name.length) name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    return name.length ? name : @"main";
}

static NSString *ZNUXRelativePath(NSString *path) {
    NSString *bundle = ZNUXStandardPath(NSBundle.mainBundle.bundlePath);
    NSString *full = ZNUXStandardPath(path);
    if (bundle.length && [full hasPrefix:[bundle stringByAppendingString:@"/"]]) {
        return [full substringFromIndex:bundle.length + 1];
    }
    return full;
}

static void ZNUXForEachSubview(UIView *view, void (^block)(UIView *view)) {
    if (!view || !block) return;
    block(view);
    for (UIView *sub in view.subviews) ZNUXForEachSubview(sub, block);
}

static CGFloat ZNUXClampScrollY(UIScrollView *scroll, CGFloat y) {
    if (!scroll) return 0;
    CGFloat minY = -scroll.adjustedContentInset.top;
    CGFloat maxY = MAX(minY, scroll.contentSize.height - CGRectGetHeight(scroll.bounds) + scroll.adjustedContentInset.bottom);
    return MIN(MAX(y, minY), maxY);
}

@interface ZNRuntimeMenuControllerV040 (ZNUXFixesV2)
- (void)znux_renderPage;
- (void)znux_show;
- (void)znux_hide;
- (BOOL)znux_isVisible;
- (void)znux_buildBinary:(id)sender;
- (void)znux_binaryPickerTapped:(UIButton *)sender;
- (void)znux_applyAutoTargetOnce;
- (void)znux_customizeRenderedBuilder;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNUXFixesV2)

- (void)znux_applyAutoTargetOnce {
    if ([objc_getAssociatedObject(self, kZNUXAutoTargetInitializedKey) boolValue]) return;
    objc_setAssociatedObject(self, kZNUXAutoTargetInitializedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kZNUXSelectedTargetKey];
    NSDictionary *savedModule = saved.length ? [[ZNModuleManager sharedManager] moduleNamed:saved] : nil;
    if (savedModule && ZNUXIsAppLocalImage(savedModule)) {
        [workspace updateDefaultTarget:saved];
        return;
    }

    NSString *preferred = ZNUXPreferredTarget();
    if (preferred.length) [workspace updateDefaultTarget:preferred];
}

- (void)znux_customizeRenderedBuilder {
    if (!self.contentView) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];

    // Replace the old free-text target field with a single-tap app-library picker.
    UIView *targetView = [self.contentView viewWithTag:440000];
    if ([targetView isKindOfClass:UITextField.class] && targetView.superview) {
        UIView *container = targetView.superview;
        CGRect frame = targetView.frame;
        [targetView removeFromSuperview];

        NSString *title = workspace.defaultTarget.length ? workspace.defaultTarget : ZNUXPreferredTarget();
        UIButton *picker = [self zn40_button:[NSString stringWithFormat:@"%@   ›", title]
                                    selector:@selector(znux_binaryPickerTapped:)
                                       frame:frame];
        picker.tag = 440000;
        picker.enabled = !workspace.isBuilding && !workspace.hasAnyApplied;
        picker.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        picker.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        picker.titleLabel.adjustsFontSizeToFitWidth = YES;
        picker.titleLabel.minimumScaleFactor = 0.65;
        [container addSubview:picker];
    }

    // Manual read/validate remains available, but it is no longer a prerequisite
    // for enabling the Build button. Build will run the same preflight itself.
    ZNUXForEachSubview(self.contentView, ^(UIView *view) {
        if (![view isKindOfClass:UIButton.class]) return;
        UIButton *button = (UIButton *)view;
        NSArray<NSString *> *actions = [button actionsForTarget:self forControlEvent:UIControlEventTouchUpInside];
        if (![actions containsObject:NSStringFromSelector(@selector(zn44_buildBinary:))]) return;
        button.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && workspace.filledCount > 0;
        button.alpha = button.enabled ? 1.0 : 0.5;
    });
}

- (void)znux_renderPage {
    UIScrollView *scroll = self.contentScroll;
    CGPoint oldOffset = scroll ? scroll.contentOffset : CGPointZero;

    [self znux_applyAutoTargetOnce];
    [self znux_renderPage];
    [self znux_customizeRenderedBuilder];

    if (scroll) {
        CGFloat y = ZNUXClampScrollY(scroll, oldOffset.y);
        [scroll setContentOffset:CGPointMake(oldOffset.x, y) animated:NO];
    }
}

- (void)znux_binaryPickerTapped:(UIButton *)sender {
    NSArray<NSDictionary<NSString *, id> *> *images = ZNUXAppLocalImages();
    if (!images.count) {
        [ZNBinaryPatchWorkspace sharedWorkspace].lastStatus = @"当前 App 没有发现可选择的本地 Mach-O image";
        [self renderPage];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Libraries"
                                                                   message:@"优先 UnityFramework；也可以选择主程序或当前 App 已加载的 Framework / dylib"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary<NSString *, id> *item in images) {
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"";
        if (!name.length) continue;
        NSString *relative = ZNUXRelativePath(path);
        NSString *label = relative.length ? [NSString stringWithFormat:@"%@  ·  %@", name, relative] : name;
        UIAlertAction *action = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
            [workspace updateDefaultTarget:name];
            [NSUserDefaults.standardUserDefaults setObject:name forKey:kZNUXSelectedTargetKey];
            workspace.lastStatus = [NSString stringWithFormat:@"当前二进制：%@", relative.length ? relative : name];
            [weakSelf renderPage];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    UIViewController *presenter = ZNUXTopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender;
        popover.sourceRect = sender.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)znux_buildBinary:(id)sender {
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (!workspace.isBuilding && !workspace.hasAnyApplied && workspace.filledCount > 0 &&
        workspace.validatedCount != workspace.filledCount) {
        NSString *error = nil;
        if (![workspace validateAll:&error]) {
            workspace.lastStatus = [NSString stringWithFormat:@"生成预检失败：%@", error ?: workspace.lastStatus ?: @"未知错误"];
            [self renderPage];
            return;
        }
        [[ZNRuntimeLogger sharedLogger] log:@"[builder] direct build: manual validate skipped; internal preflight passed"];
    }
    [self znux_buildBinary:sender];
}

- (void)znux_show {
    if (!self.uiReady) [self tick:nil];
    if (!self.uiReady || [self isVisible]) return;

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    UIViewController *presenter = ZNUXTopController(window.rootViewController);
    if (!window || !presenter) return;

    ZNUXOverlayController *overlay = [[ZNUXOverlayController alloc] initWithPanel:self.panel];
    [presenter addChildViewController:overlay];
    overlay.view.frame = presenter.view.bounds;
    overlay.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [presenter.view addSubview:overlay.view];
    [overlay didMoveToParentViewController:presenter];

    self.panel.hidden = NO;
    objc_setAssociatedObject(self, kZNUXOverlayControllerKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.floatButton.superview == window) [window bringSubviewToFront:self.floatButton];
    [[ZNRuntimeLogger sharedLogger] log:@"[menu-overlay] child-controller passthrough shell shown"];
}

- (void)znux_hide {
    ZNUXOverlayController *overlay = objc_getAssociatedObject(self, kZNUXOverlayControllerKey);
    if (!overlay) {
        self.panel.hidden = YES;
        [self.panel removeFromSuperview];
        return;
    }

    self.panel.hidden = YES;
    [overlay willMoveToParentViewController:nil];
    [self.panel removeFromSuperview];
    [overlay.view removeFromSuperview];
    [overlay removeFromParentViewController];
    objc_setAssociatedObject(self, kZNUXOverlayControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.floatButton.hidden = NO;
    if (self.floatButton.superview == self.hostWindow) [self.hostWindow bringSubviewToFront:self.floatButton];
    [[ZNRuntimeLogger sharedLogger] log:@"[menu-overlay] child-controller passthrough shell hidden"];
}

- (BOOL)znux_isVisible {
    ZNUXOverlayController *overlay = objc_getAssociatedObject(self, kZNUXOverlayControllerKey);
    return self.uiReady && overlay.parentViewController != nil && !self.panel.hidden;
}

@end

static void ZNUXSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallUXFixesV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNUXSwap(cls, @selector(renderPage), @selector(znux_renderPage));
        ZNUXSwap(cls, @selector(zn44_buildBinary:), @selector(znux_buildBinary:));
        ZNUXSwap(cls, @selector(show), @selector(znux_show));
        ZNUXSwap(cls, @selector(hide), @selector(znux_hide));
        ZNUXSwap(cls, @selector(isVisible), @selector(znux_isVisible));
        [[ZNRuntimeLogger sharedLogger] log:@"[ux-v2] auto target + app libraries picker + direct build preflight + scroll preservation + touch passthrough installed"];
    });
}
