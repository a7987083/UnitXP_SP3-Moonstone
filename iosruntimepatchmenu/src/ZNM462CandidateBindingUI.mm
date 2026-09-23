#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"

// M4.6.2 removes the fragile "sort test buttons by Y and assume candidate order"
// execution route. M4.3 already creates result cards in candidate order and
// stores the real candidate on each button. This outer render layer walks the
// freshly-created result hierarchy in insertion order once, gives every test
// button an explicit M4.6.2 candidate association, then replaces its target
// with a handler that never performs geometric lookup.
static const void *kZNM462BoundCandidateKey = &kZNM462BoundCandidateKey;
static const uint32_t kZNM462MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM462MethodGetFlagsFn)(const void *, uint32_t *);

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (UIWindow *)currentWindow;
- (void)renderPage;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (void)zn60v3_setStatus:(NSString *)status;
- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate;
- (void)znm43_testCandidate:(UIButton *)sender;
- (void)znm44_testCandidate:(UIButton *)sender;
@end

static NSArray<NSDictionary *> *ZNM462VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static void ZNM462CollectTestButtonsInHierarchyOrder(UIView *root,
                                                      id target,
                                                      NSMutableArray<UIButton *> *buttons) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm43_testCandidate:))]) [buttons addObject:button];
        }
        ZNM462CollectTestButtonsInHierarchyOrder(child, target, buttons);
    }
}

static void *ZNM462Symbol(NSString *path, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !path.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static BOOL ZNM462CandidateIsStatic(NSDictionary *candidate, BOOL *known) {
    if (known) *known = NO;
    uintptr_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) return NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM462MethodGetFlagsFn getFlags = (ZNM462MethodGetFlagsFn)ZNM462Symbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    if (known) *known = YES;
    return (flags & kZNM462MethodAttributeStatic) != 0;
}

static UIViewController *ZNM462TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM462TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM462TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM462TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM462TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static ZNRuntimeMethodAction *ZNM462ExactAction(ZNRuntimeMenuControllerV040 *controller,
                                                NSDictionary *candidate,
                                                NSArray<NSString *> *types) {
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    action.namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    action.className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    action.methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    action.argumentCount = [candidate[@"argumentCount"] unsignedIntegerValue];
    action.argumentValues = [controller znm43_argumentValues:candidate] ?: @[];
    action.parameterTypeNames = types ?: @[];
    action.signatureAvailable = YES;
    action.title = action.methodName;
    return action;
}

static void ZNM462ExecuteExact(ZNRuntimeMenuControllerV040 *controller,
                               NSDictionary *candidate,
                               NSArray<NSString *> *types) {
    ZNRuntimeMethodAction *action = ZNM462ExactAction(controller, candidate, types);
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    if (result) {
        BOOL isStatic = [result[@"static"] boolValue];
        NSString *suffix = isStatic ? @"static" : [NSString stringWithFormat:@"instance=0x%llX", (unsigned long long)[result[@"instance"] unsignedLongLongValue]];
        [controller zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@ · %@", action.canonicalIdentity, suffix]];
    } else {
        [controller zn60v3_setStatus:error ?: @"Runtime Invoke FAILED"];
    }
    [controller renderPage];
}

typedef void (^ZNM462ReadyBlock)(void);
static void ZNM462EnsureInstance(ZNRuntimeMenuControllerV040 *controller,
                                 NSDictionary *candidate,
                                 UIView *sourceView,
                                 ZNM462ReadyBlock ready) {
    NSString *assembly = candidate[@"assembly"] ?: @"Assembly-CSharp.dll";
    NSString *namespaceName = candidate[@"namespace"] ?: @"";
    NSString *className = candidate[@"class"] ?: @"";
    ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];

    uintptr_t selected = [resolver znm44_selectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    if (selected) {
        NSString *validationError = nil;
        if ([resolver znm44_validateInstanceAddress:selected assembly:assembly namespace:namespaceName className:className error:&validationError]) {
            if (ready) ready();
            return;
        }
        [resolver znm44_clearSelectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    }

    NSString *diagnostics = nil;
    NSString *findError = nil;
    NSArray<NSNumber *> *instances = [resolver candidateAddressesForAssembly:assembly
                                                                    namespace:namespaceName
                                                                    className:className
                                                                        limit:32
                                                                  diagnostics:&diagnostics
                                                                        error:&findError];
    if (!instances.count) {
        [controller zn60v3_setStatus:findError ?: @"M4.6.2 Instance Resolver：没有找到活实例"];
        [controller renderPage];
        return;
    }
    if (instances.count == 1) {
        NSString *selectionError = nil;
        if ([resolver znm44_selectInstanceAddress:instances.firstObject.unsignedLongLongValue
                                         assembly:assembly
                                        namespace:namespaceName
                                        className:className
                                            error:&selectionError]) {
            if (ready) ready();
        } else {
            [controller zn60v3_setStatus:selectionError ?: @"M4.6.2 Instance Resolver：唯一实例验证失败"];
            [controller renderPage];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择实例 · %@", className.length ? className : @"Object"]
                                                                   message:[NSString stringWithFormat:@"发现 %lu 个活实例；M4.6.2 使用 GCHandle（可用时）保持当前会话 receiver", (unsigned long)instances.count]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak ZNRuntimeMenuControllerV040 *weakController = controller;
    for (NSUInteger i = 0; i < instances.count; i++) {
        uintptr_t address = instances[i].unsignedLongLongValue;
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"实例 %lu · 0x%llX", (unsigned long)(i + 1), (unsigned long long)address]
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *a) {
            ZNRuntimeMenuControllerV040 *strong = weakController;
            if (!strong) return;
            NSString *selectionError = nil;
            if ([[ZNIL2CPPInstanceResolver sharedResolver] znm44_selectInstanceAddress:address
                                                                              assembly:assembly
                                                                             namespace:namespaceName
                                                                             className:className
                                                                                 error:&selectionError]) {
                if (ready) ready();
            } else {
                [strong zn60v3_setStatus:selectionError ?: @"M4.6.2 receiver 选择失败"];
                [strong renderPage];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = controller.hostWindow ?: [controller currentWindow];
    UIViewController *presenter = ZNM462TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: controller.contentView;
        popover.sourceRect = sourceView ? sourceView.bounds : controller.contentView.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface ZNRuntimeMenuControllerV040 (ZNM462CandidateBindingUI)
- (void)znm462_renderResultsAtWidth:(CGFloat)width;
- (void)znm462_boundTestCandidate:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM462CandidateBindingUI)

- (void)znm462_renderResultsAtWidth:(CGFloat)width {
    [self znm462_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM462VisibleCandidates(self);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM462CollectTestButtonsInHierarchyOrder(self.contentView, self, buttons);
    if (!visible.count || buttons.count != visible.count) {
        if (visible.count || buttons.count) {
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6.2-candidate-binding] count mismatch candidates=%lu buttons=%lu; preserving previous route",
                                                 (unsigned long)visible.count, (unsigned long)buttons.count]];
        }
        return;
    }

    for (NSUInteger i = 0; i < visible.count; i++) {
        UIButton *button = buttons[i];
        NSDictionary *candidate = visible[i];
        objc_setAssociatedObject(button, kZNM462BoundCandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button removeTarget:self action:@selector(znm43_testCandidate:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(znm462_boundTestCandidate:) forControlEvents:UIControlEventTouchUpInside];
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6.2-candidate-binding] explicitly bound %lu result buttons without Y-coordinate mapping",
                                         (unsigned long)visible.count]];
}

- (void)znm462_boundTestCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM462BoundCandidateKey);
    if (!candidate) {
        // Fail-safe only: an unbound button keeps the previous M4.6 route.
        [self znm43_testCandidate:sender];
        return;
    }

    NSString *signatureError = nil;
    NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
    BOOL exact = types && types.count == [candidate[@"argumentCount"] unsignedIntegerValue];

    BOOL staticKnown = NO;
    BOOL isStatic = ZNM462CandidateIsStatic(candidate, &staticKnown);
    void (^execute)(void) = ^{
        if (exact) {
            ZNM462ExecuteExact(self, candidate, types);
        } else {
            // znm44_testCandidate: is the post-M4.4 selector alias containing
            // the original M4.3 candidate-associated handler. It consumes the
            // association placed on the button at creation, so no geometry is
            // used even in the legacy signature fallback.
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6.2-candidate-binding] exact signature unavailable; direct candidate legacy route reason=%@",
                                                 signatureError ?: @"signature unavailable"]];
            [self znm44_testCandidate:sender];
        }
    };

    if (!staticKnown || isStatic) {
        execute();
        return;
    }
    ZNM462EnsureInstance(self, candidate, sender, execute);
}

@end

static void ZNM462UISwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM462CandidateBindingUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM462UISwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm462_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.6.2-candidate-binding] structural explicit binding layer installed"];
    });
}
