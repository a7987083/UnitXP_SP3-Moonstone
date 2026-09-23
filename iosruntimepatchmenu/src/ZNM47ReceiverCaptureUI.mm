#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPResolver.h"
#import "ZNM47ReceiverCapture.h"
#import "ZNPatchCore.h"

static const void *kZNM47CaptureCandidateKey = &kZNM47CaptureCandidateKey;
static const uint32_t kZNM47MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM47MethodGetFlagsFn)(const void *, uint32_t *);

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)renderPage;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)znm462_boundTestCandidate:(UIButton *)sender;
@end

static NSArray<NSDictionary *> *ZNM47VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static void ZNM47CollectBoundTestButtons(UIView *root,
                                         id target,
                                         NSMutableArray<UIButton *> *buttons) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm462_boundTestCandidate:))]) [buttons addObject:button];
        }
        ZNM47CollectBoundTestButtons(child, target, buttons);
    }
}

static void *ZNM47Symbol(NSString *path, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !path.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static BOOL ZNM47CandidateIsInstance(NSDictionary *candidate) {
    uintptr_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) return NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM47MethodGetFlagsFn getFlags = (ZNM47MethodGetFlagsFn)ZNM47Symbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    return (flags & kZNM47MethodAttributeStatic) == 0;
}

@interface ZNRuntimeMenuControllerV040 (ZNM47ReceiverCaptureUI)
- (void)znm47_renderResultsAtWidth:(CGFloat)width;
- (void)znm47_captureLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM47ReceiverCaptureUI)

- (void)znm47_renderResultsAtWidth:(CGFloat)width {
    [self znm47_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM47VisibleCandidates(self);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM47CollectBoundTestButtons(self.contentView, self, buttons);
    if (!visible.count || visible.count != buttons.count) return;

    NSUInteger armed = 0;
    for (NSUInteger i = 0; i < visible.count; i++) {
        NSDictionary *candidate = visible[i];
        UIButton *button = buttons[i];
        if (!ZNM47CandidateIsInstance(candidate)) continue;
        uintptr_t methodPointer = [candidate[@"methodPointer"] unsignedLongLongValue];
        if (!methodPointer || (methodPointer & 3ULL)) continue;

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(znm47_captureLongPress:)];
        longPress.minimumPressDuration = 0.65;
        longPress.cancelsTouchesInView = YES;
        objc_setAssociatedObject(longPress, kZNM47CaptureCandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addGestureRecognizer:longPress];
        [button setTitle:@"测试/捕获" forState:UIControlStateNormal];
        armed++;
    }
    if (armed) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.7-receiver-ui] capture gesture armed on %lu instance method buttons", (unsigned long)armed]];
    }
}

- (void)znm47_captureLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSDictionary *candidate = objc_getAssociatedObject(gesture, kZNM47CaptureCandidateKey);
    if (!candidate) return;

    if (ZNM47ReceiverCaptureBusy()) {
        [self zn60v3_setStatus:@"M4.7 Receiver Capture：已有捕获任务运行中"];
        [self renderPage];
        return;
    }

    NSString *assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    NSString *namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    NSString *className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";

    __weak typeof(self) weakSelf = self;
    NSString *startError = nil;
    BOOL started = ZNM47StartReceiverCapture(candidate, 5.0, ^(uintptr_t receiver, NSString *captureError) {
        ZNRuntimeMenuControllerV040 *strong = weakSelf;
        if (!strong) return;
        if (!receiver) {
            [strong zn60v3_setStatus:captureError ?: @"M4.7 Receiver Capture：未捕获到实例"];
            [strong renderPage];
            return;
        }

        ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];
        NSString *validationError = nil;
        if (![resolver znm44_validateInstanceAddress:receiver
                                           assembly:assembly
                                          namespace:namespaceName
                                          className:className
                                              error:&validationError]) {
            [strong zn60v3_setStatus:[NSString stringWithFormat:@"M4.7 捕获到 x0=0x%llX，但类型验证失败：%@",
                                      (unsigned long long)receiver,
                                      validationError ?: @"unknown"]];
            [strong renderPage];
            return;
        }

        NSString *selectionError = nil;
        if (![resolver znm44_selectInstanceAddress:receiver
                                          assembly:assembly
                                         namespace:namespaceName
                                         className:className
                                             error:&selectionError]) {
            [strong zn60v3_setStatus:selectionError ?: @"M4.7：捕获 receiver 保存失败"];
            [strong renderPage];
            return;
        }

        [strong zn60v3_setStatus:[NSString stringWithFormat:@"M4.7 捕获成功：%@.%@ receiver=0x%llX；现在可直接点测试执行",
                                  className.length ? className : @"?",
                                  methodName,
                                  (unsigned long long)receiver]];
        [strong renderPage];
    }, &startError);

    if (!started) {
        [self zn60v3_setStatus:startError ?: @"M4.7 Receiver Capture 启动失败"];
        [self renderPage];
        return;
    }

    [self zn60v3_setStatus:[NSString stringWithFormat:@"M4.7 捕获中（5 秒）：请在游戏里触发 %@.%@；捕获的是 ARM64 x0/this",
                            className.length ? className : @"?",
                            methodName]];
    [self renderPage];
}

@end

static void ZNM47ReceiverUISwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM47ReceiverCaptureUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47ReceiverUISwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm47_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.7-receiver-ui] long-press receiver capture layer installed"];
    });
}
