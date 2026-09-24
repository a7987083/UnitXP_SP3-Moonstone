#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"

static const void *kZNM52XActionKey = &kZNM52XActionKey;
static const void *kZNM52XIndexKey = &kZNM52XIndexKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (void)zn52x_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)renderPage;
- (void)zn52_chainTapped:(UIButton *)sender;
- (void)zn52x_executeChainTapped:(UIButton *)sender;
- (void)zn52x_restartChainLongPress:(UILongPressGestureRecognizer *)gesture;
@end

static NSString *ZNM52XString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray<NSDictionary *> *ZNM52XVisible(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [out addObject:candidate];
    }
    return out;
}

static void ZNM52XCollectChainButtons(UIView *root, NSMutableArray<UIButton *> *out) {
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UIButton.class]) {
            NSString *title = [(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"链式调用"] || [title isEqualToString:@"执行链"]) [out addObject:(UIButton *)view];
        }
        ZNM52XCollectChainButtons(view, out);
    }
}

static BOOL ZNM52XCandidateMatches(NSDictionary *candidate, ZNRuntimeMethodAction *action) {
    NSDictionary *chain = [action.immediateChain isKindOfClass:NSDictionary.class] ? action.immediateChain : @{};
    NSArray *nodes = [chain[@"nodes"] isKindOfClass:NSArray.class] ? chain[@"nodes"] : nil;
    if ([chain[@"version"] integerValue] != 2 || !nodes.count) return NO;
    NSString *assembly = ZNM52XString(candidate[@"assembly"]); if (!assembly.length) assembly = @"Assembly-CSharp.dll";
    return [action.assembly isEqualToString:assembly] &&
           [(action.namespaceName ?: @"") isEqualToString:ZNM52XString(candidate[@"namespace"])] &&
           [action.className isEqualToString:ZNM52XString(candidate[@"class"])] &&
           [action.methodName isEqualToString:ZNM52XString(candidate[@"method"])] &&
           action.argumentCount == [candidate[@"argumentCount"] unsignedIntegerValue];
}

static NSInteger ZNM52XFindChain(NSDictionary *candidate, ZNRuntimeMethodAction **outAction) {
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for (NSInteger i = (NSInteger)actions.count - 1; i >= 0; i--) {
        ZNRuntimeMethodAction *action = actions[(NSUInteger)i];
        if (ZNM52XCandidateMatches(candidate, action)) {
            if (outAction) *outAction = action;
            return i;
        }
    }
    return NSNotFound;
}

static UIViewController *ZNM52XTop(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static NSString *ZNM52XTrace(NSDictionary *result) {
    NSArray *trace = [result[@"chainTrace"] isKindOfClass:NSArray.class] ? result[@"chainTrace"] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSDictionary *level in trace) {
        NSString *identity = ZNM52XString(level[@"identity"]);
        [lines addObject:[NSString stringWithFormat:@"L%@ %@ → %@", level[@"level"] ?: @"?", identity.length ? identity : @"?", level[@"returnValue"] ?: @"?"]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

@implementation ZNRuntimeMenuControllerV040 (ZNM52ChainExecuteButton)

- (void)zn52x_renderResultsAtWidth:(CGFloat)width {
    [self zn52x_renderResultsAtWidth:width];
    NSArray<NSDictionary *> *visible = ZNM52XVisible(self);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM52XCollectChainButtons(self.contentView, buttons);
    if (!visible.count || buttons.count != visible.count) return;

    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIButton *button = buttons[i];
        ZNRuntimeMethodAction *action = nil;
        NSInteger actionIndex = ZNM52XFindChain(visible[i], &action);
        if (actionIndex == NSNotFound || !action) continue;

        [button setTitle:@"执行链" forState:UIControlStateNormal];
        objc_setAssociatedObject(button, kZNM52XActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, kZNM52XIndexKey, @(actionIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button removeTarget:self action:@selector(zn52_chainTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button removeTarget:self action:@selector(zn52x_executeChainTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(zn52x_executeChainTapped:) forControlEvents:UIControlEventTouchUpInside];

        BOOL hasLongPress = NO;
        for (UIGestureRecognizer *g in button.gestureRecognizers) if ([g isKindOfClass:UILongPressGestureRecognizer.class]) { hasLongPress = YES; break; }
        if (!hasLongPress) {
            UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(zn52x_restartChainLongPress:)];
            longPress.minimumPressDuration = 0.65;
            [button addGestureRecognizer:longPress];
        }
    }
}

- (void)zn52x_executeChainTapped:(UIButton *)sender {
    ZNRuntimeMethodAction *action = objc_getAssociatedObject(sender, kZNM52XActionKey);
    if (!action) return;
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    if (!result) {
        NSString *message = error.length ? error : @"未知错误";
        [self zn60v3_setStatus:[NSString stringWithFormat:@"执行链失败：%@", message]];
        UIViewController *top = ZNM52XTop(self.hostWindow);
        if (top) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"执行链失败" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [top presentViewController:alert animated:YES completion:nil];
        }
        return;
    }
    NSString *type = ZNM52XString(result[@"returnType"]);
    NSString *value = [result[@"returnValue"] description] ?: @"?";
    NSString *trace = ZNM52XTrace(result);
    [self zn60v3_setStatus:[NSString stringWithFormat:@"执行链成功 · %@ = %@", type.length ? type : @"return", value]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.2-chain-ui] %@ = %@\n%@", type.length ? type : @"return", value, trace ?: @""]];
    UIViewController *top = ZNM52XTop(self.hostWindow);
    if (top) {
        NSString *message = trace.length ? [NSString stringWithFormat:@"最终返回：%@ = %@\n\n%@", type.length ? type : @"return", value, trace] : [NSString stringWithFormat:@"最终返回：%@ = %@", type.length ? type : @"return", value];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"执行链结果" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    }
}

- (void)zn52x_restartChainLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIButton *button = [gesture.view isKindOfClass:UIButton.class] ? (UIButton *)gesture.view : nil;
    if (!button) return;
    NSInteger index = [objc_getAssociatedObject(button, kZNM52XIndexKey) integerValue];
    NSString *error = nil;
    if (index < 0 || ![[ZNRuntimeActionStore sharedStore] updateImmediateChain:@{} atIndex:(NSUInteger)index error:&error]) {
        [self zn60v3_setStatus:error.length ? error : @"重新链式调用失败：无法清空旧链"];
        return;
    }
    [button setTitle:@"链式调用" forState:UIControlStateNormal];
    [button removeTarget:self action:@selector(zn52x_executeChainTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(zn52_chainTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, kZNM52XActionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self zn60v3_setStatus:@"旧链已清空，重新进入链式调用"];
    [self zn52_chainTapped:button];
}

@end

static void ZNM52XSwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM52ChainExecuteButtonDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (menu) ZNM52XSwap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(zn52x_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.2-chain-ui] completed chain button: tap=execute, long-press=restart"];
    });
}
