#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNRMCBuilderDeleteTagBase = 671000;
static const NSInteger kZNRMCBuilderTitleTagBase = 672000;
static const NSInteger kZNRMCBuilderArgumentTagBase = 674000;

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

static UITextField *ZNRMCBuilderTextField(CGRect frame, ZNTheme *theme) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.layer.cornerRadius = 7.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallBuilderUI)
- (void)znrmc_renderOther;
- (void)znrmc_clearAuthoringActions:(id)sender;
- (void)znrmc_deleteAuthoringAction:(UIButton *)sender;
- (void)znrmc_titleEditingEnded:(UITextField *)field;
- (void)znrmc_argumentEditingEnded:(UITextField *)field;
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
        UILabel *label = [self label:@"在“方法查找”选择 /0 或受支持的 /1 方法 → 创建方法。Static Patch ABI 保持不变。"
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
            BOOL hasArgument = action.argumentCount == 1;
            CGFloat cardH = hasArgument ? 108.0 : 72.0;
            UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

            UITextField *name = ZNRMCBuilderTextField(CGRectMake(13, 7, card.bounds.size.width - 78, 27), self.theme);
            name.tag = kZNRMCBuilderTitleTagBase + (NSInteger)i;
            name.text = action.title.length ? action.title : action.methodName;
            name.placeholder = action.methodName;
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
                                                  frame:CGRectMake(card.bounds.size.width - 65, hasArgument ? 37 : 19, 52, 31)];
            deleteButton.tag = kZNRMCBuilderDeleteTagBase + (NSInteger)i;
            [card addSubview:deleteButton];

            if (hasArgument) {
                UILabel *argLabel = [self label:@"参数 1" size:8.2 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
                argLabel.frame = CGRectMake(13, 72, 44, 25);
                [card addSubview:argLabel];

                UITextField *argument = ZNRMCBuilderTextField(CGRectMake(59, 69, card.bounds.size.width - 72, 29), self.theme);
                argument.tag = kZNRMCBuilderArgumentTagBase + (NSInteger)i;
                argument.text = action.argumentValues.count ? action.argumentValues.firstObject : @"";
                argument.placeholder = @"/1 参数值";
                argument.font = [UIFont monospacedDigitSystemFontOfSize:9.6 weight:UIFontWeightMedium];
                [argument addTarget:self action:@selector(znrmc_argumentEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
                [card addSubview:argument];
            }

            [self.contentView addSubview:card];
            y += cardH + 8.0;
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

- (void)znrmc_argumentEditingEnded:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderArgumentTagBase;
    if (index < 0) return;
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[field.text ?: @""] atIndex:(NSUInteger)index error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] argument update failed: %@", error ?: @"unknown"]];
    }
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if ((NSUInteger)index < actions.count) {
        ZNRuntimeMethodAction *action = actions[(NSUInteger)index];
        field.text = action.argumentValues.count ? action.argumentValues.firstObject : @"";
    }
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
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Builder action list UI installed (/0 + /1)"];
        }
    });
}
