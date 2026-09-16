#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// v0.5.1 UI hotfix:
// 1) ManualTaskEngineV05 originally placed all status rows/buttons directly on
//    the fixed-height panel, so smaller screens clipped controls and could not scroll.
// 2) The expanded panel itself was fixed in one screen position.
//
// Keep title/close fixed, move operational content into one UIScrollView, and
// make the title area a drag handle for the whole panel. Position is persisted.
// Game-touch passthrough outside the overlay remains unchanged.

#define JCG5_SCROLL_TAG 50501
#define JCG5_HEADER_HEIGHT 42.0
#define JCG5_PANEL_X_KEY @"JCG5PanelX"
#define JCG5_PANEL_Y_KEY @"JCG5PanelY"

static IMP gJCG5OriginalViewDidLoad = NULL;
static SEL gJCG5PanelPanSelector;

static CGRect JCG5ClampPanelFrame(CGRect frame, UIView *host) {
    if (![host isKindOfClass:[UIView class]]) return frame;
    CGRect hb = host.bounds;
    CGFloat margin = 4.0;
    CGFloat maxX = MAX(margin, CGRectGetWidth(hb) - CGRectGetWidth(frame) - margin);
    CGFloat maxY = MAX(margin, CGRectGetHeight(hb) - CGRectGetHeight(frame) - margin);
    frame.origin.x = MIN(MAX(frame.origin.x, margin), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, margin), maxY);
    return frame;
}

static void JCG5HandlePanelPan(id self, SEL _cmd, UIPanGestureRecognizer *pan) {
    (void)_cmd;
    UIView *panel = nil;
    @try { panel = [self valueForKey:@"panel"]; }
    @catch (__unused NSException *e) { return; }
    if (![panel isKindOfClass:[UIView class]] || ![panel.superview isKindOfClass:[UIView class]]) return;

    UIView *host = panel.superview;
    CGPoint delta = [pan translationInView:host];
    CGRect frame = panel.frame;
    frame.origin.x += delta.x;
    frame.origin.y += delta.y;
    panel.frame = JCG5ClampPanelFrame(frame, host);
    [pan setTranslation:CGPointZero inView:host];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setDouble:panel.frame.origin.x forKey:JCG5_PANEL_X_KEY];
        [ud setDouble:panel.frame.origin.y forKey:JCG5_PANEL_Y_KEY];
    }
}

static void JCG5ScrollableViewDidLoad(id self, SEL _cmd) {
    if (gJCG5OriginalViewDidLoad) {
        ((void (*)(id, SEL))gJCG5OriginalViewDidLoad)(self, _cmd);
    }

    UIView *panel = nil;
    @try { panel = [self valueForKey:@"panel"]; }
    @catch (__unused NSException *e) { return; }
    if (![panel isKindOfClass:[UIView class]]) return;
    if ([panel viewWithTag:JCG5_SCROLL_TAG]) return;

    // Restore the user's last expanded-menu position, then clamp it to the
    // current screen (rotation/device-size changes cannot strand the menu).
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:JCG5_PANEL_X_KEY] && [ud objectForKey:JCG5_PANEL_Y_KEY]) {
        CGRect saved = panel.frame;
        saved.origin.x = [ud doubleForKey:JCG5_PANEL_X_KEY];
        saved.origin.y = [ud doubleForKey:JCG5_PANEL_Y_KEY];
        panel.frame = JCG5ClampPanelFrame(saved, panel.superview);
    }

    CGRect bounds = panel.bounds;
    CGFloat header = MIN((CGFloat)JCG5_HEADER_HEIGHT, bounds.size.height);
    UIScrollView *scroll = [[[UIScrollView alloc] initWithFrame:CGRectMake(0, header, bounds.size.width, MAX(1.0, bounds.size.height - header))] autorelease];
    scroll.tag = JCG5_SCROLL_TAG;
    scroll.backgroundColor = UIColor.clearColor;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = YES;
    scroll.directionalLockEnabled = YES;
    scroll.delaysContentTouches = NO;
    scroll.canCancelContentTouches = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    if (@available(iOS 11.0, *)) {
        scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    // Snapshot before adding scroll. Header controls remain fixed; operational
    // content begins at y ~= 42 and is moved into the scroll view.
    NSArray *existing = [[panel.subviews copy] autorelease];
    [panel addSubview:scroll];

    CGFloat maxBottom = 0.0;
    UILabel *titleLabel = nil;
    for (UIView *view in existing) {
        CGRect frame = view.frame;
        if (CGRectGetMinY(frame) < header - 4.0) {
            if (!titleLabel && [view isKindOfClass:[UILabel class]]) titleLabel = (UILabel *)view;
            continue;
        }
        [view removeFromSuperview];
        frame.origin.y -= header;
        view.frame = frame;
        [scroll addSubview:view];
        maxBottom = MAX(maxBottom, CGRectGetMaxY(frame));
    }

    // Add a little bottom padding so the last row/button can be fully revealed.
    CGFloat contentHeight = MAX(maxBottom + 14.0, scroll.bounds.size.height + 1.0);
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, contentHeight);

    // The title becomes a dedicated drag handle. It is separate from the
    // scroll view, so vertical list scrolling and panel dragging do not fight.
    if (titleLabel && gJCG5PanelPanSelector) {
        titleLabel.userInteractionEnabled = YES;
        UIPanGestureRecognizer *move = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:gJCG5PanelPanSelector] autorelease];
        move.maximumNumberOfTouches = 1;
        move.cancelsTouchesInView = YES;
        [titleLabel addGestureRecognizer:move];
    }

    // Preserve fixed header controls above the scroll view.
    for (UIView *view in existing) {
        if (CGRectGetMinY(view.frame) < header - 4.0) [panel bringSubviewToFront:view];
    }
}

__attribute__((constructor)) static void JCG5InstallScrollFix(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"JCG5Controller");
        if (!cls) return;

        gJCG5PanelPanSelector = NSSelectorFromString(@"jcg5_movePanel:");
        class_addMethod(cls, gJCG5PanelPanSelector, (IMP)JCG5HandlePanelPan, "v@:@");

        Method method = class_getInstanceMethod(cls, @selector(viewDidLoad));
        if (!method) return;
        IMP current = method_getImplementation(method);
        if (current == (IMP)JCG5ScrollableViewDidLoad) return;
        gJCG5OriginalViewDidLoad = current;
        method_setImplementation(method, (IMP)JCG5ScrollableViewDidLoad);
    }
}
