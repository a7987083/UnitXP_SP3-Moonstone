#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// v0.5.1 UI hotfix: ManualTaskEngineV05 originally placed all status rows and
// buttons directly on the fixed-height panel. On smaller screens the lower
// controls were clipped and there was no UIScrollView to receive pan gestures.
// Keep the title/close button fixed, move the operational content into one
// scroll view, and leave the existing passthrough-window behavior unchanged.

#define JCG5_SCROLL_TAG 50501
#define JCG5_HEADER_HEIGHT 42.0

static IMP gJCG5OriginalViewDidLoad = NULL;

static void JCG5ScrollableViewDidLoad(id self, SEL _cmd) {
    if (gJCG5OriginalViewDidLoad) {
        ((void (*)(id, SEL))gJCG5OriginalViewDidLoad)(self, _cmd);
    }

    UIView *panel = nil;
    @try { panel = [self valueForKey:@"panel"]; }
    @catch (__unused NSException *e) { return; }
    if (![panel isKindOfClass:[UIView class]]) return;
    if ([panel viewWithTag:JCG5_SCROLL_TAG]) return;

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

    // Snapshot before adding scroll. The first two views are the fixed title
    // and close button; operational content begins at y ~= 42.
    NSArray *existing = [[panel.subviews copy] autorelease];
    [panel addSubview:scroll];

    CGFloat maxBottom = 0.0;
    for (UIView *view in existing) {
        CGRect frame = view.frame;
        if (CGRectGetMinY(frame) < header - 4.0) continue;
        [view removeFromSuperview];
        frame.origin.y -= header;
        view.frame = frame;
        [scroll addSubview:view];
        maxBottom = MAX(maxBottom, CGRectGetMaxY(frame));
    }

    // Add a little bottom padding so the last row can be fully revealed.
    CGFloat contentHeight = MAX(maxBottom + 14.0, scroll.bounds.size.height + 1.0);
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, contentHeight);

    // Preserve fixed header controls above the scroll view.
    for (UIView *view in existing) {
        if (CGRectGetMinY(view.frame) < header - 4.0) [panel bringSubviewToFront:view];
    }
}

__attribute__((constructor)) static void JCG5InstallScrollFix(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"JCG5Controller");
        if (!cls) return;
        Method method = class_getInstanceMethod(cls, @selector(viewDidLoad));
        if (!method) return;
        IMP current = method_getImplementation(method);
        if (current == (IMP)JCG5ScrollableViewDidLoad) return;
        gJCG5OriginalViewDidLoad = current;
        method_setImplementation(method, (IMP)JCG5ScrollableViewDidLoad);
    }
}
