#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

static const uint32_t kZNM44MethodAttributeStatic = 0x0010u;
static const NSInteger kZNM44FeatureExecuteTagBase = 672000;
static const NSInteger kZNM44FeatureCompactExecuteTagBase = 673000;

typedef uint32_t (*ZNM44MethodGetFlagsFn)(const void *, uint32_t *);

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (UIWindow *)currentWindow;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)renderPage;
- (void)znm43_testCandidate:(UIButton *)sender;
- (void)znrmc_executeAction:(UIButton *)sender;
@end

static UIViewController *ZNM44TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM44TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM44TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM44TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM44TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static void ZNM44CollectTestButtons(UIView *view, id target, NSMutableArray<UIButton *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm43_testCandidate:))]) [out addObject:button];
        }
        ZNM44CollectTestButtons(child, target, out);
    }
}

static CGFloat ZNM44ButtonY(UIButton *button, UIView *contentView) {
    CGRect rect = [button convertRect:button.bounds toView:contentView];
    return CGRectGetMinY(rect);
}

static NSDictionary *ZNM44CandidateForButton(ZNRuntimeMenuControllerV040 *controller, UIButton *sender) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM44CollectTestButtons(controller.contentView, controller, buttons);
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat ay = ZNM44ButtonY(a, controller.contentView);
        CGFloat by = ZNM44ButtonY(b, controller.contentView);
        if (ay < by) return NSOrderedAscending;
        if (ay > by) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSUInteger index = [buttons indexOfObjectIdenticalTo:sender];
    return index != NSNotFound && index < visible.count ? visible[index] : nil;
}

static void *ZNM44ResolveSymbol(NSString *path, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !path.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static BOOL ZNM44MethodIsStatic(NSString *assembly,
                                NSString *namespaceName,
                                NSString *className,
                                NSString *methodName,
                                NSUInteger argumentCount,
                                NSNumber *methodInfoHint,
                                BOOL *known) {
    if (known) *known = NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if (!resolver.isAvailable) return NO;
    uintptr_t methodInfo = [methodInfoHint unsignedLongLongValue];
    if (!methodInfo) {
        NSDictionary *resolved = [resolver resolveMethodAssembly:assembly
                                                       namespace:namespaceName ?: @""
                                                       className:className
                                                          method:methodName
                                                   argumentCount:(NSInteger)argumentCount];
        methodInfo = [resolved[@"methodInfo"] unsignedLongLongValue];
    }
    if (!methodInfo) return NO;
    ZNM44MethodGetFlagsFn getFlags = (ZNM44MethodGetFlagsFn)ZNM44ResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    if (known) *known = YES;
    return (flags & kZNM44MethodAttributeStatic) != 0;
}

typedef void (^ZNM44ReadyBlock)(void);

static void ZNM44EnsureInstance(ZNRuntimeMenuControllerV040 *controller,
                                NSString *assembly,
                                NSString *namespaceName,
                                NSString *className,
                                UIView *sourceView,
                                ZNM44ReadyBlock ready) {
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
                                                                    namespace:namespaceName ?: @""
                                                                    className:className
                                                                        limit:32
                                                                  diagnostics:&diagnostics
                                                                        error:&findError];
    if (!instances.count) {
        [controller zn60v3_setStatus:findError ?: @"Instance Resolver：没有找到活实例"];
        [controller renderPage];
        return;
    }
    if (instances.count == 1) {
        NSString *selectionError = nil;
        if ([resolver znm44_selectInstanceAddress:instances.firstObject.unsignedLongLongValue
                                         assembly:assembly
                                        namespace:namespaceName ?: @""
                                        className:className
                                            error:&selectionError]) {
            if (ready) ready();
        } else {
            [controller zn60v3_setStatus:selectionError ?: @"Instance Resolver：唯一实例验证失败"];
            [controller renderPage];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择实例 · %@", className ?: @"Object"]
                                                                   message:[NSString stringWithFormat:@"发现 %lu 个活实例；本次选择仅在当前进程有效", (unsigned long)instances.count]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak ZNRuntimeMenuControllerV040 *weakController = controller;
    for (NSUInteger i = 0; i < instances.count; i++) {
        uintptr_t address = instances[i].unsignedLongLongValue;
        NSString *title = [NSString stringWithFormat:@"实例 %lu · 0x%llX", (unsigned long)(i + 1), (unsigned long long)address];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            ZNRuntimeMenuControllerV040 *strongController = weakController;
            if (!strongController) return;
            NSString *selectionError = nil;
            BOOL ok = [[ZNIL2CPPInstanceResolver sharedResolver] znm44_selectInstanceAddress:address
                                                                                     assembly:assembly
                                                                                    namespace:namespaceName ?: @""
                                                                                    className:className
                                                                                        error:&selectionError];
            if (ok) {
                [strongController zn60v3_setStatus:[NSString stringWithFormat:@"已选择 %@ 实例：0x%llX", className ?: @"Object", (unsigned long long)address]];
                if (ready) ready();
            } else {
                [strongController zn60v3_setStatus:selectionError ?: @"实例验证失败"];
                [strongController renderPage];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = controller.hostWindow ?: [controller currentWindow];
    UIViewController *presenter = ZNM44TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: controller.contentView;
        popover.sourceRect = sourceView ? sourceView.bounds : controller.contentView.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface ZNRuntimeMenuControllerV040 (ZNInstanceSelectionV2UI)
- (void)znm44_testCandidate:(UIButton *)sender;
- (void)znm44_executeAction:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNInstanceSelectionV2UI)

- (void)znm44_testCandidate:(UIButton *)sender {
    NSDictionary *candidate = ZNM44CandidateForButton(self, sender);
    if (!candidate) {
        [self znm44_testCandidate:sender];
        return;
    }
    NSString *assembly = candidate[@"assembly"] ?: @"Assembly-CSharp.dll";
    NSString *namespaceName = candidate[@"namespace"] ?: @"";
    NSString *className = candidate[@"class"] ?: @"";
    NSString *methodName = candidate[@"method"] ?: @"";
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    BOOL known = NO;
    BOOL isStatic = ZNM44MethodIsStatic(assembly, namespaceName, className, methodName, argc, candidate[@"methodInfo"], &known);
    if (!known || isStatic) {
        [self znm44_testCandidate:sender];
        return;
    }
    __weak typeof(self) weakSelf = self;
    ZNM44EnsureInstance(self, assembly, namespaceName, className, sender, ^{
        [weakSelf znm44_testCandidate:sender];
    });
}

- (void)znm44_executeAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZNM44FeatureExecuteTagBase;
    if (sender.tag >= kZNM44FeatureCompactExecuteTagBase) index = sender.tag - kZNM44FeatureCompactExecuteTagBase;
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if (index < 0 || (NSUInteger)index >= runtime.records.count) {
        [self znm44_executeAction:sender];
        return;
    }
    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    BOOL known = NO;
    BOOL isStatic = ZNM44MethodIsStatic(record.assembly,
                                        record.namespaceName,
                                        record.className,
                                        record.methodName,
                                        record.argumentCount,
                                        nil,
                                        &known);
    if (!known || isStatic) {
        [self znm44_executeAction:sender];
        return;
    }
    __weak typeof(self) weakSelf = self;
    ZNM44EnsureInstance(self, record.assembly, record.namespaceName, record.className, sender, ^{
        [weakSelf znm44_executeAction:sender];
    });
}

@end

static void ZNM44Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallInstanceSelectionV2UIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZNInstallIL2CPPInstanceSelectionV2Deferred();
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM44Swap(cls, @selector(znm43_testCandidate:), @selector(znm44_testCandidate:));
        ZNM44Swap(cls, @selector(znrmc_executeAction:), @selector(znm44_executeAction:));
        [[ZNRuntimeLogger sharedLogger] log:@"[instance-selection-v2] multi-instance picker UI installed"];
    });
}
