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
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const uint32_t kZNM46MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM46MethodGetFlagsFn)(const void *, uint32_t *);

typedef void (^ZNM46ReadyBlock)(void);

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIWindow *)currentWindow;
- (void)renderPage;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSDictionary * _Nullable)zn60v3_selected;
- (NSInteger)znm42_filter;
- (void)zn60v3_setStatus:(NSString *)status;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate;
- (void)znm43_testCandidate:(UIButton *)sender;
- (void)zn60v3_createPatch:(id)sender;
- (void)zn61v3_createPatch:(id)sender;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
@end

static NSString *ZNM46LegacyShortName(NSDictionary *candidate) {
    NSString *method = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZNM46CandidateCollisionKey(NSDictionary *candidate) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"",
            candidate[@"namespace"] ?: @"",
            candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"",
            candidate[@"argumentCount"] ?: @(-1)];
}

static NSArray<NSDictionary *> *ZNM46VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static void ZNM46CollectTestButtons(UIView *view, id target, NSMutableArray<UIButton *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm43_testCandidate:))]) [out addObject:button];
        }
        ZNM46CollectTestButtons(child, target, out);
    }
}

static CGFloat ZNM46ViewY(UIView *view, UIView *content) {
    return CGRectGetMinY([view convertRect:view.bounds toView:content]);
}

static NSDictionary *ZNM46CandidateForButton(ZNRuntimeMenuControllerV040 *controller, UIButton *sender) {
    NSArray<NSDictionary *> *visible = ZNM46VisibleCandidates(controller);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM46CollectTestButtons(controller.contentView, controller, buttons);
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat ay = ZNM46ViewY(a, controller.contentView), by = ZNM46ViewY(b, controller.contentView);
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger index = [buttons indexOfObjectIdenticalTo:sender];
    return index != NSNotFound && index < visible.count ? visible[index] : nil;
}

static void ZNM46CollectMethodLabels(UIView *view,
                                     UIView *content,
                                     NSSet<NSString *> *legacyNames,
                                     NSMutableArray<UILabel *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)child;
            if ([legacyNames containsObject:label.text ?: @""]) [out addObject:label];
        }
        ZNM46CollectMethodLabels(child, content, legacyNames, out);
    }
}

static void *ZNM46ResolveSymbol(NSString *path, const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p || !path.length) return p;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static UIViewController *ZNM46TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM46TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM46TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM46TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM46TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static BOOL ZNM46CandidateIsStatic(NSDictionary *candidate, BOOL *known) {
    if (known) *known = NO;
    uintptr_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) return NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM46MethodGetFlagsFn getFlags = (ZNM46MethodGetFlagsFn)ZNM46ResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    if (known) *known = YES;
    return (flags & kZNM46MethodAttributeStatic) != 0;
}

static ZNRuntimeMethodAction *ZNM46EphemeralAction(NSDictionary *candidate,
                                                   NSArray<NSString *> *values,
                                                   NSString **error) {
    NSString *signatureError = nil;
    NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    if (!types || types.count != argc) {
        if (error) *error = signatureError ?: @"M4.6：无法读取完整参数签名";
        return nil;
    }
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    action.namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    action.className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    action.methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    action.argumentCount = argc;
    action.argumentValues = values ?: @[];
    action.parameterTypeNames = types;
    action.signatureAvailable = YES;
    action.title = action.methodName;
    return action;
}

static void ZNM46ExecuteExactCandidate(ZNRuntimeMenuControllerV040 *controller,
                                       NSDictionary *candidate) {
    NSArray<NSString *> *values = [controller znm43_argumentValues:candidate] ?: @[];
    NSString *actionError = nil;
    ZNRuntimeMethodAction *action = ZNM46EphemeralAction(candidate, values, &actionError);
    if (!action) {
        [controller zn60v3_setStatus:actionError ?: @"M4.6：完整签名不可用"];
        [controller renderPage];
        return;
    }
    NSString *invokeError = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&invokeError];
    if (result) {
        BOOL isStatic = [result[@"static"] boolValue];
        NSString *suffix = isStatic ? @"static" : [NSString stringWithFormat:@"instance=0x%llX", (unsigned long long)[result[@"instance"] unsignedLongLongValue]];
        [controller zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@ · %@", action.canonicalIdentity, suffix]];
    } else {
        [controller zn60v3_setStatus:invokeError ?: @"Runtime Invoke FAILED"];
    }
    [controller renderPage];
}

static void ZNM46EnsureInstanceThenExecute(ZNRuntimeMenuControllerV040 *controller,
                                           NSDictionary *candidate,
                                           UIView *sourceView) {
    NSString *assembly = candidate[@"assembly"] ?: @"Assembly-CSharp.dll";
    NSString *namespaceName = candidate[@"namespace"] ?: @"";
    NSString *className = candidate[@"class"] ?: @"";
    ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];

    uintptr_t selected = [resolver znm44_selectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    if (selected) {
        NSString *validationError = nil;
        if ([resolver znm44_validateInstanceAddress:selected assembly:assembly namespace:namespaceName className:className error:&validationError]) {
            ZNM46ExecuteExactCandidate(controller, candidate);
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
        [controller zn60v3_setStatus:findError ?: @"M4.6 Instance Resolver：没有找到活实例"];
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
            ZNM46ExecuteExactCandidate(controller, candidate);
        } else {
            [controller zn60v3_setStatus:selectionError ?: @"M4.6 Instance Resolver：唯一实例验证失败"];
            [controller renderPage];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择实例 · %@", className.length ? className : @"Object"]
                                                                   message:[NSString stringWithFormat:@"发现 %lu 个活实例；完整方法签名已锁定，实例选择仅当前进程有效", (unsigned long)instances.count]
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
                ZNM46ExecuteExactCandidate(strong, candidate);
            } else {
                [strong zn60v3_setStatus:selectionError ?: @"M4.6 实例验证失败"];
                [strong renderPage];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = controller.hostWindow ?: [controller currentWindow];
    UIViewController *presenter = ZNM46TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: controller.contentView;
        popover.sourceRect = sourceView ? sourceView.bounds : controller.contentView.bounds;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface ZNRuntimeMenuControllerV040 (ZNM46FullSignatureUI)
- (void)znm46_testCandidate:(UIButton *)sender;
- (void)znm46_createPatch:(id)sender;
- (void)znm46_renderResultsAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM46FullSignatureUI)

- (void)znm46_testCandidate:(UIButton *)sender {
    NSDictionary *candidate = ZNM46CandidateForButton(self, sender);
    if (!candidate) {
        [self znm46_testCandidate:sender];
        return;
    }
    NSString *signatureError = nil;
    NSArray *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
    if (!types || types.count != [candidate[@"argumentCount"] unsignedIntegerValue]) {
        // Preserve the M4.5 path when the runtime hides signature APIs. Do not
        // claim exact-overload resolution in this compatibility fallback.
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6-signature-ui] legacy test fallback %@ reason=%@",
                                             ZNM46LegacyShortName(candidate), signatureError ?: @"signature unavailable"]];
        [self znm46_testCandidate:sender];
        return;
    }

    BOOL staticKnown = NO;
    BOOL isStatic = ZNM46CandidateIsStatic(candidate, &staticKnown);
    if (!staticKnown || isStatic) {
        ZNM46ExecuteExactCandidate(self, candidate);
        return;
    }
    ZNM46EnsureInstanceThenExecute(self, candidate, sender);
}

- (void)znm46_createPatch:(id)sender {
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate || ![candidate[@"addressResolved"] boolValue]) {
        [self znm46_createPatch:sender];
        return;
    }
    uint64_t exactRVA = [candidate[@"queryRVA"] respondsToSelector:@selector(unsignedLongLongValue)]
        ? [candidate[@"queryRVA"] unsignedLongLongValue]
        : [candidate[@"rva"] unsignedLongLongValue];
    if (!exactRVA) {
        [self znm46_createPatch:sender];
        return;
    }

    NSString *previous = [self zn57mf_query] ?: @"";
    NSString *exactQuery = [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)exactRVA];
    [self zn57mf_setQuery:exactQuery];
    // zn61v3_createPatch: is the post-swap alias containing the original V3
    // implementation. Calling it directly intentionally bypasses the older
    // Method/N PatchBridge wrapper so overload identity cannot be re-guessed.
    [self zn61v3_createPatch:sender];
    [self zn57mf_setQuery:previous];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6-signature-ui] Static Patch locked to exact candidate RVA %@", exactQuery]];
}

- (void)znm46_renderResultsAtWidth:(CGFloat)width {
    [self znm46_renderResultsAtWidth:width];
    NSArray<NSDictionary *> *visible = ZNM46VisibleCandidates(self);
    if (visible.count < 2) return;

    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *legacyNames = [NSMutableSet set];
    for (NSDictionary *candidate in visible) {
        NSString *key = ZNM46CandidateCollisionKey(candidate);
        counts[key] = @([counts[key] unsignedIntegerValue] + 1);
        [legacyNames addObject:ZNM46LegacyShortName(candidate)];
    }

    BOOL hasCollision = NO;
    for (NSNumber *count in counts.allValues) if (count.unsignedIntegerValue > 1) { hasCollision = YES; break; }
    if (!hasCollision) return;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    ZNM46CollectMethodLabels(self.contentView, self.contentView, legacyNames, labels);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ay = ZNM46ViewY(a, self.contentView), by = ZNM46ViewY(b, self.contentView);
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    if (labels.count < visible.count) return;

    for (NSUInteger i = 0; i < visible.count && i < labels.count; i++) {
        NSDictionary *candidate = visible[i];
        if ([counts[ZNM46CandidateCollisionKey(candidate)] unsignedIntegerValue] <= 1) continue;
        NSString *signatureError = nil;
        NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
        if (!types || types.count != [candidate[@"argumentCount"] unsignedIntegerValue]) continue;
        labels[i].text = ZNIL2CPPShortSignature(candidate[@"method"] ?: @"Method", types);
        labels[i].adjustsFontSizeToFitWidth = YES;
        labels[i].minimumScaleFactor = 0.55;
    }
}

@end

static void ZNM46UISwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM46FullSignatureUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!menu) return;
        ZNM46UISwap(menu, @selector(znm43_testCandidate:), @selector(znm46_testCandidate:));
        ZNM46UISwap(menu, @selector(zn60v3_createPatch:), @selector(znm46_createPatch:));
        ZNM46UISwap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(znm46_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.6-signature-ui] exact candidate test + exact-RVA Static Patch + overload labels installed"];
    });
}
