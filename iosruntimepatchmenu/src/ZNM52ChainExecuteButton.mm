#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPResolver.h"
#import "ZNIL2CPPRuntimeCommon.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"

static const void *kZNM52XActionKey = &kZNM52XActionKey;
static const void *kZNM52XIndexKey = &kZNM52XIndexKey;
static const void *kZNM52XCandidateKey = &kZNM52XCandidateKey;
static const uint32_t kZNM52XMethodAttributeStatic = 0x0010u;

typedef uint32_t (*ZNM52XMethodGetFlagsFn)(const void *, uint32_t *);

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)renderPage;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn52_chainTapped:(UIButton *)sender;
@end

@interface ZNRuntimeMenuControllerV040 (ZNM52ChainExecuteButton)
- (void)zn52x_renderResultsAtWidth:(CGFloat)width;
- (void)zn52x_executeChainTapped:(UIButton *)sender;
- (void)zn52x_restartChainLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)zn52x_reselectInstance:(UIButton *)sender;
- (void)zn52x_batchTestInstances:(UIButton *)sender;
- (void)zn52x_directUnavailable:(UIButton *)sender;
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

static UIButton *ZNM52XButtonWithTitles(UIView *card, NSArray<NSString *> *titles) {
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button=(UIButton *)view;
        NSString *title=[button titleForState:UIControlStateNormal] ?: @"";
        if ([titles containsObject:title]) return button;
    }
    return nil;
}

static BOOL ZNM52XMethodIsInstance(NSDictionary *candidate, BOOL *known) {
    if(known)*known=NO;
    uintptr_t methodInfo=[candidate[@"methodInfo"] unsignedLongLongValue];
    if(!methodInfo)return NO;
    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM52XMethodGetFlagsFn getFlags=(ZNM52XMethodGetFlagsFn)ZNIL2CPPResolveSymbol(resolver.unityPath,"il2cpp_method_get_flags");
    if(!getFlags)return NO;
    uint32_t implFlags=0;
    uint32_t flags=getFlags((const void *)methodInfo,&implFlags);
    if(known)*known=YES;
    return (flags&kZNM52XMethodAttributeStatic)==0;
}

static BOOL ZNM52XBatchSafe(NSDictionary *candidate) {
    if([candidate[@"argumentCount"] unsignedIntegerValue]!=0)return NO;
    NSString *method=ZNM52XString(candidate[@"method"]).lowercaseString;
    return [method hasPrefix:@"get_"] || [method hasPrefix:@"is"] ||
           [method hasPrefix:@"has"] || [method hasPrefix:@"can"];
}

static void ZNM52XStyleGridButton(UIButton *button,CGFloat x,CGFloat y,CGFloat w,CGFloat h) {
    if(!button)return;
    button.frame=CGRectMake(x,y,w,h);
    button.titleLabel.font=[UIFont systemFontOfSize:8.1 weight:UIFontWeightSemibold];
    button.titleLabel.adjustsFontSizeToFitWidth=YES;
    button.titleLabel.minimumScaleFactor=.65;
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
    NSArray<NSDictionary *> *visible=ZNM52XVisible(self);
    NSMutableArray<UIButton *> *chainButtons=[NSMutableArray array];
    ZNM52XCollectChainButtons(self.contentView,chainButtons);
    if(!visible.count||chainButtons.count!=visible.count)return;

    for(NSUInteger i=0;i<chainButtons.count;i++){
        NSDictionary *candidate=visible[i];
        UIButton *chain=chainButtons[i];
        UIView *card=chain.superview;
        if(!card)continue;

        ZNRuntimeMethodAction *action=nil;
        NSInteger actionIndex=ZNM52XFindChain(candidate,&action);
        if(actionIndex!=NSNotFound&&action){
            [chain setTitle:@"执行链" forState:UIControlStateNormal];
            objc_setAssociatedObject(chain,kZNM52XActionKey,action,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(chain,kZNM52XIndexKey,@(actionIndex),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [chain removeTarget:self action:@selector(zn52_chainTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chain removeTarget:self action:@selector(zn52x_executeChainTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chain addTarget:self action:@selector(zn52x_executeChainTapped:) forControlEvents:UIControlEventTouchUpInside];
            BOOL hasLongPress=NO;
            for(UIGestureRecognizer *g in chain.gestureRecognizers)
                if([g isKindOfClass:UILongPressGestureRecognizer.class]){hasLongPress=YES;break;}
            if(!hasLongPress){
                UILongPressGestureRecognizer *longPress=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(zn52x_restartChainLongPress:)];
                longPress.minimumPressDuration=.65;
                [chain addGestureRecognizer:longPress];
            }
        }

        UIButton *test=ZNM52XButtonWithTitles(card,@[@"测试/捕获",@"测试执行"]);
        UIButton *create=ZNM52XButtonWithTitles(card,@[@"创建方法"]);
        UIButton *direct=ZNM52XButtonWithTitles(card,@[@"Direct 测试"]);
        if(!direct){
            direct=[self zn40_button:@"Direct 测试" selector:@selector(zn52x_directUnavailable:) frame:CGRectZero];
            direct.enabled=NO;
            direct.alpha=.48;
            [card addSubview:direct];
        }

        BOOL known=NO;
        BOOL instance=ZNM52XMethodIsInstance(candidate,&known);
        UIButton *reselect=[self zn40_button:@"重新选择实例" selector:@selector(zn52x_reselectInstance:) frame:CGRectZero];
        UIButton *batch=[self zn40_button:@"批量测试实例" selector:@selector(zn52x_batchTestInstances:) frame:CGRectZero];
        objc_setAssociatedObject(reselect,kZNM52XCandidateKey,candidate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(batch,kZNM52XCandidateKey,candidate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        reselect.enabled=known&&instance;
        batch.enabled=known&&instance&&ZNM52XBatchSafe(candidate);
        reselect.alpha=reselect.enabled?1.0:.48;
        batch.alpha=batch.enabled?1.0:.48;
        [card addSubview:reselect];
        [card addSubview:batch];

        CGFloat gap=6.0,rightInset=10.0,gridW=164.0;
        CGFloat colW=(gridW-gap)/2.0;
        CGFloat x0=CGRectGetWidth(card.bounds)-rightInset-gridW;
        CGFloat x1=x0+colW+gap;
        ZNM52XStyleGridButton(test,x0,7,colW,28);
        ZNM52XStyleGridButton(direct,x1,7,colW,28);
        ZNM52XStyleGridButton(create,x0,41,colW,28);
        ZNM52XStyleGridButton(chain,x1,41,colW,28);
        ZNM52XStyleGridButton(reselect,x0,75,colW,28);
        ZNM52XStyleGridButton(batch,x1,75,colW,28);
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

- (void)zn52x_directUnavailable:(UIButton *)sender {
    (void)sender;
    [self zn60v3_setStatus:@"Direct 测试：当前分支尚未接入 Direct Native Call backend"];
}

- (void)zn52x_reselectInstance:(UIButton *)sender {
    NSDictionary *candidate=objc_getAssociatedObject(sender,kZNM52XCandidateKey);
    if(!candidate)return;
    NSString *assembly=ZNM52XString(candidate[@"assembly"]); if(!assembly.length)assembly=@"Assembly-CSharp.dll";
    NSString *ns=ZNM52XString(candidate[@"namespace"]);
    NSString *cls=ZNM52XString(candidate[@"class"]);
    ZNIL2CPPInstanceResolver *resolver=[ZNIL2CPPInstanceResolver sharedResolver];

    uintptr_t previous=[resolver znm44_selectedInstanceForAssembly:assembly namespace:ns className:cls];
    [resolver znm44_clearSelectedInstanceForAssembly:assembly namespace:ns className:cls];

    NSString *diag=nil,*findError=nil;
    NSArray<NSNumber *> *instances=[resolver candidateAddressesForAssembly:assembly namespace:ns className:cls limit:32 diagnostics:&diag error:&findError];
    if(!instances.count){
        [self zn60v3_setStatus:findError ?: @"重新选择实例：没有找到活实例"];
        [self renderPage];
        return;
    }

    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"重新选择实例 · %@",cls.length?cls:@"Object"]
                                                                 message:[NSString stringWithFormat:@"发现 %lu 个活实例；旧 GCHandle 已释放",(unsigned long)instances.count]
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf=self;
    for(NSUInteger i=0;i<instances.count;i++){
        uintptr_t address=instances[i].unsignedLongLongValue;
        NSString *mark=(previous&&address==previous)?@" · 原当前":@"";
        NSString *title=[NSString stringWithFormat:@"实例 %lu · 0x%llX%@",(unsigned long)(i+1),(unsigned long long)address,mark];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            NSString *selectionError=nil;
            BOOL ok=[[ZNIL2CPPInstanceResolver sharedResolver] znm44_selectInstanceAddress:address assembly:assembly namespace:ns className:cls error:&selectionError];
            [weakSelf zn60v3_setStatus:ok
                ? [NSString stringWithFormat:@"已重新选择 %@：0x%llX",cls.length?cls:@"Object",(unsigned long long)address]
                : (selectionError ?: @"重新选择实例失败")];
            [weakSelf renderPage];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a){
        [weakSelf zn60v3_setStatus:@"已取消重新选择；旧 receiver 已释放"];
        [weakSelf renderPage];
    }]];

    UIViewController *top=ZNM52XTop(self.hostWindow);
    if(!top)return;
    UIPopoverPresentationController *popover=alert.popoverPresentationController;
    if(popover){popover.sourceView=sender;popover.sourceRect=sender.bounds;popover.permittedArrowDirections=UIPopoverArrowDirectionAny;}
    [top presentViewController:alert animated:YES completion:nil];
}

- (void)zn52x_batchTestInstances:(UIButton *)sender {
    NSDictionary *candidate=objc_getAssociatedObject(sender,kZNM52XCandidateKey);
    if(!candidate||!ZNM52XBatchSafe(candidate))return;
    NSString *assembly=ZNM52XString(candidate[@"assembly"]); if(!assembly.length)assembly=@"Assembly-CSharp.dll";
    NSString *ns=ZNM52XString(candidate[@"namespace"]);
    NSString *cls=ZNM52XString(candidate[@"class"]);
    NSString *method=ZNM52XString(candidate[@"method"]);

    NSString *diag=nil,*findError=nil;
    NSArray<NSNumber *> *instances=[[ZNIL2CPPInstanceResolver sharedResolver] candidateAddressesForAssembly:assembly namespace:ns className:cls limit:32 diagnostics:&diag error:&findError];
    if(!instances.count){
        [self zn60v3_setStatus:findError ?: @"批量测试实例：没有找到活实例"];
        [self renderPage];
        return;
    }

    ZNRuntimeMethodAction *action=[ZNRuntimeMethodAction new];
    action.title=method.length?method:@"Batch Instance Test";
    action.assembly=assembly;
    action.namespaceName=ns;
    action.className=cls;
    action.methodName=method;
    action.argumentCount=0;
    action.argumentValues=@[];
    action.immediateChain=@{};

    NSMutableArray<NSString *> *lines=[NSMutableArray array];
    NSUInteger success=0;
    for(NSUInteger i=0;i<instances.count;i++){
        uintptr_t address=instances[i].unsignedLongLongValue;
        NSString *invokeError=nil;
        NSDictionary *result=[[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action receiver:address error:&invokeError];
        if(result){
            success++;
            NSString *value=[result[@"returnValue"] description];
            if(!value.length)value=[NSString stringWithFormat:@"0x%llX",(unsigned long long)[result[@"result"] unsignedLongLongValue]];
            [lines addObject:[NSString stringWithFormat:@"#%lu 0x%llX  ✅  %@",(unsigned long)(i+1),(unsigned long long)address,value]];
        }else{
            [lines addObject:[NSString stringWithFormat:@"#%lu 0x%llX  ❌  %@",(unsigned long)(i+1),(unsigned long long)address,invokeError ?: @"FAILED"]];
        }
    }

    [self zn60v3_setStatus:[NSString stringWithFormat:@"批量测试完成：%lu/%lu 成功；当前 receiver 未改变",(unsigned long)success,(unsigned long)instances.count]];
    UIViewController *top=ZNM52XTop(self.hostWindow);
    if(top){
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"批量测试实例 · %@::%@",cls,method]
                                                                     message:[lines componentsJoinedByString:@"\n"]
                                                              preferredStyle:UIAlertControllerStyleAlert];
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
        [[ZNRuntimeLogger sharedLogger] log:@"[m6.4-finder-grid] right-side 2-column actions + reselect/batch instance test installed"];
    });
}
