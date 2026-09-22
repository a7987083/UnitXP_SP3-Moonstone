#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNRMCBuilderDeleteTagBase = 671000;
static const NSInteger kZNRMCBuilderTitleTagBase = 672000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn44_renderOther;
- (void)zn50b_renderOther;
@end

static CGFloat ZNRMCBuilderMaxY(UIView *view) {
    CGFloat y = 0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallBuilderUI)
- (void)znrmc_renderOther;
- (void)znrmc_clearAuthoringActions:(id)sender;
- (void)znrmc_deleteAuthoringAction:(UIButton *)sender;
- (void)znrmc_titleEditingEnded:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallBuilderUI)

- (void)znrmc_renderOther {
    // Installed before FeatureBuilderUI: after the later swap this selector
    // invokes the complete existing Builder page, then appends Runtime Actions.
    [self znrmc_renderOther];

    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNRMCBuilderMaxY(self.contentView) + 8.0;

    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UILabel *title = [self label:[NSString stringWithFormat:@"Runtime Method Call · %lu", (unsigned long)actions.count]
                               size:10.8
                             weight:UIFontWeightSemibold
                              color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, header.bounds.size.width - 96, 31);
    [header addSubview:title];
    UIButton *clear = [self zn40_button:@"清空" selector:@selector(znrmc_clearAuthoringActions:) frame:CGRectMake(header.bounds.size.width - 75, 8, 62, 31)];
    clear.enabled = actions.count > 0;
    clear.alpha = clear.enabled ? 1.0 : 0.5;
    [header addSubview:clear];
    [self.contentView addSubview:header];
    y += 56.0;

    if (!actions.count) {
        UIView *empty = [self cardAtY:y height:54 width:width compact:NO];
        UILabel *label = [self label:@"在“方法查找”选择 0 参数方法 → 创建方法按钮。它不会修改 Static Patch ABI。"
                                    size:8.4
                                  weight:UIFontWeightRegular
                                   color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, 8, empty.bounds.size.width - 26, 38);
        label.numberOfLines = 2;
        [empty addSubview:label];
        [self.contentView addSubview:empty];
        y += 62.0;
    } else {
        for (NSUInteger i = 0; i < actions.count; i++) {
            ZNRuntimeMethodAction *action = actions[i];
            UIView *card = [self cardAtY:y height:72 width:width compact:NO];

            UITextField *name = [[UITextField alloc] initWithFrame:CGRectMake(13, 7, card.bounds.size.width - 78, 27)];
            name.tag = kZNRMCBuilderTitleTagBase + (NSInteger)i;
            name.text = action.title.length ? action.title : action.methodName;
            name.placeholder = action.methodName;
            name.textColor = self.theme.primaryTextColor;
            name.backgroundColor = self.theme.controlColor;
            name.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
            name.autocorrectionType = UITextAutocorrectionTypeNo;
            name.autocapitalizationType = UITextAutocapitalizationTypeNone;
            name.returnKeyType = UIReturnKeyDone;
            name.clearButtonMode = UITextFieldViewModeWhileEditing;
            name.layer.cornerRadius = 7.0;
            name.layer.borderWidth = 1.0;
            name.layer.borderColor = self.theme.borderColor.CGColor;
            UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
            name.leftView = pad;
            name.leftViewMode = UITextFieldViewModeAlways;
            [name addTarget:self action:@selector(znrmc_titleEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:name];

            UILabel *identity = [self label:action.canonicalIdentity
                                        size:7.8
                                      weight:UIFontWeightRegular
                                       color:self.theme.secondaryTextColor];
            identity.frame = CGRectMake(13, 39, card.bounds.size.width - 78, 24);
            identity.numberOfLines = 2;
            identity.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [card addSubview:identity];

            UIButton *deleteButton = [self zn40_button:@"删除"
                                               selector:@selector(znrmc_deleteAuthoringAction:)
                                                  frame:CGRectMake(card.bounds.size.width - 65, 19, 52, 31)];
            deleteButton.tag = kZNRMCBuilderDeleteTagBase + (NSInteger)i;
            [card addSubview:deleteButton];
            [self.contentView addSubview:card];
            y += 80.0;
        }
    }
    [self zn40_updateContentHeight:y];
}

- (void)znrmc_clearAuthoringActions:(id)sender {
    (void)sender;
    [[ZNRuntimeActionStore sharedStore] clear];
    [self renderPage];
}

- (void)znrmc_deleteAuthoringAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZNRMCBuilderDeleteTagBase;
    if (index >= 0) [[ZNRuntimeActionStore sharedStore] removeActionAtIndex:(NSUInteger)index];
    [self renderPage];
}

- (void)znrmc_titleEditingEnded:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderTitleTagBase;
    if (index < 0) return;
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateTitle:field.text atIndex:(NSUInteger)index error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] rename failed: %@", error ?: @"unknown"]];
    }
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if ((NSUInteger)index < actions.count) field.text = actions[(NSUInteger)index].title;
    [field resignFirstResponder];
}

@end

extern "C" void ZNInstallRuntimeMethodCallBuilderUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method replacement = class_getInstanceMethod(cls, @selector(znrmc_renderOther));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Builder action list UI installed"];
        }
    });
}
