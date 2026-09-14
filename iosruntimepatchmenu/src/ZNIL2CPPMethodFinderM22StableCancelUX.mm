#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// M2.2 stabilizes the M2.1 Search->Cancel UX. M2 progress currently calls
// renderPage for every shard/status update; rebuilding the complete page makes
// the primary button visibly flash on fast devices. This overlay permits the
// first full render (so M2.1 can turn Search into Cancel), then updates only the
// existing status label until completion/cancellation clears the active token.

static const void *kZN63SuppressProgressRenderKey = &kZN63SuppressProgressRenderKey;
static const void *kZN63StatusLabelKey = &kZN63StatusLabelKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
- (void)renderPage;
- (void)zn60v3_startSearch:(id)sender;
- (NSString *)zn60v3_status;
- (NSString *)zn61m2_activeToken;
@end

static BOOL ZN63IsFinderVisible(ZNRuntimeMenuControllerV040 *controller) {
    NSInteger index = controller.selectedCategory;
    if (index < 0 || index >= (NSInteger)controller.categories.count) return NO;
    return [controller.categories[(NSUInteger)index] isEqualToString:@"方法查找"];
}

static UILabel *ZN63FindLabelWithText(UIView *root, NSString *text) {
    if (!root || !text.length) return nil;
    if ([root isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)root;
        if ([label.text isEqualToString:text]) return label;
    }
    for (UIView *child in root.subviews) {
        UILabel *found = ZN63FindLabelWithText(child, text);
        if (found) return found;
    }
    return nil;
}

static BOOL ZN63ViewBelongsToRoot(UIView *view, UIView *root) {
    if (!view || !root) return NO;
    UIView *cursor = view;
    while (cursor) {
        if (cursor == root) return YES;
        cursor = cursor.superview;
    }
    return NO;
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM22StableCancelUX)
- (void)zn63m22_startSearch:(id)sender;
- (void)zn63m22_renderPage;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM22StableCancelUX)

- (void)zn63m22_startSearch:(id)sender {
    objc_setAssociatedObject(self, kZN63SuppressProgressRenderKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kZN63StatusLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);

    // After swizzling this selector reaches the complete M2 startSearch path.
    [self zn63m22_startSearch:sender];

    if ([self zn61m2_activeToken].length && ZN63IsFinderVisible(self)) {
        objc_setAssociatedObject(self, kZN63SuppressProgressRenderKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *status = [self zn60v3_status];
        UILabel *label = ZN63FindLabelWithText(self.contentView, status);
        if (label) objc_setAssociatedObject(self, kZN63StatusLabelKey, label, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)zn63m22_renderPage {
    NSString *token = [self zn61m2_activeToken];
    BOOL suppress = [objc_getAssociatedObject(self, kZN63SuppressProgressRenderKey) boolValue];
    UILabel *cached = objc_getAssociatedObject(self, kZN63StatusLabelKey);

    if (token.length && suppress && ZN63IsFinderVisible(self) &&
        cached && ZN63ViewBelongsToRoot(cached, self.contentView)) {
        cached.text = [self zn60v3_status] ?: @"正在搜索…";
        return;
    }

    // First search render, navigation changes, and completion still use the
    // normal renderer. M2.1 therefore gets one stable chance to install Cancel.
    [self zn63m22_renderPage];

    token = [self zn61m2_activeToken];
    if (token.length && ZN63IsFinderVisible(self)) {
        NSString *status = [self zn60v3_status];
        UILabel *label = ZN63FindLabelWithText(self.contentView, status);
        if (label) objc_setAssociatedObject(self, kZN63StatusLabelKey, label, OBJC_ASSOCIATION_ASSIGN);
    } else {
        objc_setAssociatedObject(self, kZN63SuppressProgressRenderKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kZN63StatusLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method startOriginal = class_getInstanceMethod(cls, @selector(zn60v3_startSearch:));
        Method startReplacement = class_getInstanceMethod(cls, @selector(zn63m22_startSearch:));
        if (startOriginal && startReplacement) method_exchangeImplementations(startOriginal, startReplacement);

        Method renderOriginal = class_getInstanceMethod(cls, @selector(renderPage));
        Method renderReplacement = class_getInstanceMethod(cls, @selector(zn63m22_renderPage));
        if (renderOriginal && renderReplacement) method_exchangeImplementations(renderOriginal, renderReplacement);
    });
}
