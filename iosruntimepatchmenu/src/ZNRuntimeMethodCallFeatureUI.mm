#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionRuntime.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNRMCFeatureExecuteTagBase = 672000;
static const NSInteger kZNRMCFeatureCompactExecuteTagBase = 673000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static CGFloat ZNRMCFeatureMaxY(UIView *view) {
    CGFloat y = 0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

static void ZNRMCRemoveEmptyStaticCardIfNeeded(UIView *contentView) {
    ZNStaticDispatchRuntime *staticRuntime = [ZNStaticDispatchRuntime sharedRuntime];
    [staticRuntime refresh];
    if (staticRuntime.records.count) return;
    for (UIView *subview in [contentView.subviews copy]) {
        BOOL isEmpty = NO;
        for (UIView *child in subview.subviews) {
            if ([child isKindOfClass:UILabel.class] && [((UILabel *)child).text isEqualToString:@"暂无功能"]) {
                isEmpty = YES;
                break;
            }
        }
        if (isEmpty) [subview removeFromSuperview];
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFeatureUI)
- (void)znrmc_renderFeatureGroupsFull;
- (void)znrmc_renderFeatureGroupsCompact;
- (void)znrmc_executeAction:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFeatureUI)

- (void)znrmc_renderFeatureGroupsFull {
    [self znrmc_renderFeatureGroupsFull];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *actions = runtime.records;
    if (!actions.count) return;

    ZNRMCRemoveEmptyStaticCardIfNeeded(self.contentView);
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNRMCFeatureMaxY(self.contentView) + 8.0;
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodActionRecord *record = actions[i];
        UIView *card = [self cardAtY:y height:46 width:width compact:NO];
        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:11.4
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 13, card.bounds.size.width - 100, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];
        UIButton *execute = [self zn40_button:@"执行"
                                      selector:@selector(znrmc_executeAction:)
                                         frame:CGRectMake(card.bounds.size.width - 78, 8, 66, 30)];
        execute.tag = kZNRMCFeatureExecuteTagBase + (NSInteger)i;
        execute.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
        execute.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:execute];
        [self.contentView addSubview:card];
        y += 52.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znrmc_renderFeatureGroupsCompact {
    [self znrmc_renderFeatureGroupsCompact];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *actions = runtime.records;
    if (!actions.count) return;

    ZNRMCRemoveEmptyStaticCardIfNeeded(self.contentView);
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNRMCFeatureMaxY(self.contentView) + 6.0;
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodActionRecord *record = actions[i];
        UIView *card = [self cardAtY:y height:40 width:width compact:YES];
        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:10.7
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(9, 10, card.bounds.size.width - 82, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];
        UIButton *execute = [self zn40_button:@"执行"
                                      selector:@selector(znrmc_executeAction:)
                                         frame:CGRectMake(card.bounds.size.width - 69, 6, 60, 28)];
        execute.tag = kZNRMCFeatureCompactExecuteTagBase + (NSInteger)i;
        execute.titleLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightSemibold];
        execute.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
        execute.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:execute];
        [self.contentView addSubview:card];
        y += 46.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znrmc_executeAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZNRMCFeatureExecuteTagBase;
    if (sender.tag >= kZNRMCFeatureCompactExecuteTagBase) index = sender.tag - kZNRMCFeatureCompactExecuteTagBase;
    if (index < 0) return;

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) return;
    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    NSString *error = nil;
    BOOL ok = [runtime executeRecord:record error:&error];
    NSString *oldTitle = [sender titleForState:UIControlStateNormal] ?: @"执行";
    [sender setTitle:(ok ? @"完成" : @"失败") forState:UIControlStateNormal];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] UI %@ %@%@",
                                         ok ? @"SUCCESS" : @"FAILED",
                                         record.canonicalIdentity,
                                         error.length ? [@" · " stringByAppendingString:error] : @""]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender setTitle:oldTitle forState:UIControlStateNormal];
    });
}

@end

extern "C" void ZNInstallRuntimeMethodCallFeatureUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method fullOriginal = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsFull));
        Method fullReplacement = class_getInstanceMethod(cls, @selector(znrmc_renderFeatureGroupsFull));
        if (fullOriginal && fullReplacement) method_exchangeImplementations(fullOriginal, fullReplacement);
        Method compactOriginal = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsCompact));
        Method compactReplacement = class_getInstanceMethod(cls, @selector(znrmc_renderFeatureGroupsCompact));
        if (compactOriginal && compactReplacement) method_exchangeImplementations(compactOriginal, compactReplacement);
        [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] public Feature action UI installed"];
    });
}
