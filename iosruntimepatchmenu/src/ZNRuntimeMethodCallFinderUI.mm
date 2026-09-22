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
    // Detail-page action buttons intentionally remain /0-only. M4.2 /1 takes its
    // typed argument from the inline input on the result card, so duplicating a
    // second unsynchronised input in Details would be ambiguous.
    BOOL detailActionSupported = (argc == 0 && candidateClass.length && candidateMethod.length);

    CGFloat y = ZNRMCFinderMaxY(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:92 width:width compact:NO];
    UILabel *title = [self label:@"Runtime Method Call · M4.2" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 26, 18);
    [card addSubview:title];

    NSString *hint = nil;
    if (argc == 0) {
        hint = @"/0：可在详情直接测试或创建。实例方法继续 fail closed。";
    } else if (argc == 1) {
        hint = @"/1 已支持 typed argument；请返回搜索结果，在卡片输入参数后使用“测试执行 / 创建方法”。";
    } else {
        hint = [NSString stringWithFormat:@"当前 /%ld 可搜索和筛选；M4.2 首版暂不执行 /2+。", (long)argc];
    }
    UILabel *note = [self label:hint size:7.9 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    note.frame = CGRectMake(13, 27, card.bounds.size.width - 26, 24);
    note.numberOfLines = 2;
    [card addSubview:note];

    CGFloat gap = 8.0;
    CGFloat buttonW = (card.bounds.size.width - 26 - gap) / 2.0;
    UIButton *create = [self zn40_button:(detailActionSupported ? @"创建方法" : @"返回结果输入参数")
                                   selector:@selector(znrmc_createMethodAction:)
                                      frame:CGRectMake(13, 55, buttonW, 29)];
    create.enabled = detailActionSupported;
    create.alpha = detailActionSupported ? 1.0 : 0.55;
    [card addSubview:create];

    UIButton *test = [self zn40_button:(detailActionSupported ? @"测试执行" : @"详情仅查看")
                                 selector:@selector(znrmc_testInvoke:)
                                    frame:CGRectMake(13 + buttonW + gap, 55, buttonW, 29)];
    test.enabled = detailActionSupported;
    test.alpha = detailActionSupported ? 1.0 : 0.55;
    test.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
    test.layer.borderColor = self.theme.accentColor.CGColor;
    [card addSubview:test];

    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:CGRectGetMaxY(card.frame) + 8.0];
}

- (void)znrmc_createMethodAction:(id)sender {
    (void)sender;
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate || [candidate[@"argumentCount"] integerValue] != 0) return;
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
    if (!candidate || [candidate[@"argumentCount"] integerValue] != 0) return;
    NSString *assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    NSString *namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    NSString *className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAssembly:assembly
                                                                      namespace:namespaceName
                                                                      className:className
                                                                         method:methodName
                                                                  argumentCount:0
                                                                          error:&error];
    if (result) {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@::%@/0", className, methodName]];
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
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Method Finder detail UI installed (M4.2 /0 direct; /1 inline result input)"];
        }
    });
}
