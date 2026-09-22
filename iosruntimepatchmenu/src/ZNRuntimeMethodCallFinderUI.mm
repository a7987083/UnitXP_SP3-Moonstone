#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSDictionary *)zn60v3_selected;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn60v3_renderDetailAtWidth:(CGFloat)width;
@end

static CGFloat ZNRMCFinderMaxY(UIView *view) {
    CGFloat y = 0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFinderUI)
- (void)znrmc_renderDetailAtWidth:(CGFloat)width;
- (void)znrmc_createMethodAction:(id)sender;
- (void)znrmc_testInvoke:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFinderUI)

- (void)znrmc_renderDetailAtWidth:(CGFloat)width {
    // Swizzled: this selector points to the original Method Finder V3 detail renderer.
    [self znrmc_renderDetailAtWidth:width];

    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)]
        ? [candidate[@"argumentCount"] integerValue] : -1;
    NSString *candidateClass = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *candidateMethod = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    BOOL supported = (argc == 0 && candidateClass.length && candidateMethod.length);

    CGFloat y = ZNRMCFinderMaxY(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:92 width:width compact:NO];
    UILabel *title = [self label:@"Runtime Method Call · M4.1" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 26, 18);
    [card addSubview:title];

    NSString *hint = supported
        ? @"0 参数方法：可加入 Builder，也可直接做一次 Runtime Invoke 测试。实例方法会 fail closed。"
        : [NSString stringWithFormat:@"当前 argumentCount=%ld；M4.1 首版仅支持 0 参数方法。", (long)argc];
    UILabel *note = [self label:hint size:7.9 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    note.frame = CGRectMake(13, 27, card.bounds.size.width - 26, 24);
    note.numberOfLines = 2;
    [card addSubview:note];

    CGFloat gap = 8.0;
    CGFloat buttonW = (card.bounds.size.width - 26 - gap) / 2.0;
    UIButton *create = [self zn40_button:(supported ? @"创建方法按钮" : @"创建方法按钮（不可用）")
                                   selector:@selector(znrmc_createMethodAction:)
                                      frame:CGRectMake(13, 55, buttonW, 29)];
    create.enabled = supported;
    create.alpha = supported ? 1.0 : 0.55;
    [card addSubview:create];

    UIButton *test = [self zn40_button:(supported ? @"测试执行" : @"测试执行（不可用）")
                                 selector:@selector(znrmc_testInvoke:)
                                    frame:CGRectMake(13 + buttonW + gap, 55, buttonW, 29)];
    test.enabled = supported;
    test.alpha = supported ? 1.0 : 0.55;
    test.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
    test.layer.borderColor = self.theme.accentColor.CGColor;
    [card addSubview:test];

    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:CGRectGetMaxY(card.frame) + 8.0];
}

- (void)znrmc_createMethodAction:(id)sender {
    (void)sender;
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;
    NSString *error = nil;
    ZNRuntimeMethodAction *action = [[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate
                                                                                     title:candidate[@"method"]
                                                                                     error:&error];
    if (!action) {
        [self zn60v3_setStatus:error ?: @"创建 Runtime Method Call 失败"];
    } else {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"已加入 Builder：%@", action.canonicalIdentity]];
    }
    [self renderPage];
}

- (void)znrmc_testInvoke:(id)sender {
    (void)sender;
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;
    NSString *assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    NSString *namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    NSString *className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAssembly:assembly
                                                                      namespace:namespaceName
                                                                      className:className
                                                                         method:methodName
                                                                  argumentCount:argc
                                                                          error:&error];
    if (result) {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@::%@/%lu",
                                  className, methodName, (unsigned long)argc]];
    } else {
        [self zn60v3_setStatus:error ?: @"Runtime Invoke FAILED"];
    }
    [self renderPage];
}

@end

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn60v3_renderDetailAtWidth:));
        Method replacement = class_getInstanceMethod(cls, @selector(znrmc_renderDetailAtWidth:));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Method Finder action UI installed"];
        }
    });
}
