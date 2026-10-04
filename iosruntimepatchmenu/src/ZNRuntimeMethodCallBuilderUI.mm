#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionModel.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNNativeHookAction.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNRMCBuilderDeleteTagBase = 671000;
static const NSInteger kZNRMCBuilderTitleTagBase = 672000;
static const NSInteger kZNRMCBuilderArgumentTagBase = 674000;
static const NSInteger kZNRMCBuilderDescriptionTagBase = 675000;
static const NSInteger kZNNativeHookDeleteTagBase = 676000;

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

static UIButton *ZNRMCBuilderFindBuildButton(UIView *root) {
    for (UIView *view in root.subviews ?: @[]) {
        if ([view isKindOfClass:UIButton.class]) {
            NSString *title=[(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"生成新二进制"] || [title isEqualToString:@"正在生成…"]) return (UIButton *)view;
        }
        UIButton *nested=ZNRMCBuilderFindBuildButton(view);
        if (nested) return nested;
    }
    return nil;
}

static NSUInteger ZNRMCBuilderCompleteStaticRows(ZNBinaryPatchWorkspace *workspace) {
    NSUInteger count=0;
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        if (row.offsetText.length>0 && row.enabledText.length>0) count++;
    }
    return count;
}

static void ZNRMCBuilderFinalizeBuildGate(UIView *root,
                                         NSUInteger runtimeCount,
                                         NSUInteger nativeHookCount) {
    if (!runtimeCount && !nativeHookCount) return;
    UIButton *build=ZNRMCBuilderFindBuildButton(root);
    if (!build) return;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    NSUInteger completeStatic=ZNRMCBuilderCompleteStaticRows(workspace);
    if (completeStatic!=0) return; // Static/mixed mode keeps its own validation gate.
    BOOL ready=!workspace.isBuilding && !workspace.hasAnyApplied;
    build.enabled=ready;
    build.alpha=ready?1.0:0.5;
    if (ready) {
        build.accessibilityHint=nativeHookCount>0 && runtimeCount==0
            ? @"Native Hook-only：可以直接生成二进制"
            : @"Runtime/Native Hook-only：可以直接生成二进制";
    }
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
- (void)znrmc_descriptionEditingEnded:(UITextField *)field;
- (void)znrmc_argumentEditingChanged:(UITextField *)field;
- (void)znrmc_argumentEditingEnded:(UITextField *)field;
- (void)zn64_deleteNativeHook:(UIButton *)sender;
- (void)zn64_clearNativeHooks:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallBuilderUI)

- (void)znrmc_renderOther {
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
        UILabel *label = [self label:@"在“方法查找”选择 /0 或受支持的方法 → 创建方法。制作数据会自动保存。"
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
            CGFloat cardH = hasArgument ? 149.0 : 109.0;
            UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

            UITextField *name = ZNRMCBuilderTextField(CGRectMake(13, 7, card.bounds.size.width - 82, 27), self.theme);
            name.tag = kZNRMCBuilderTitleTagBase + (NSInteger)i;
            name.text = action.title.length ? action.title : action.methodName;
            name.placeholder = action.methodName;
            [name addTarget:self action:@selector(znrmc_titleEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:name];

            UIButton *deleteButton = [self zn40_button:@"删除"
                                               selector:@selector(znrmc_deleteAuthoringAction:)
                                                  frame:CGRectMake(card.bounds.size.width - 65, 7, 52, 27)];
            deleteButton.tag = kZNRMCBuilderDeleteTagBase + (NSInteger)i;
            [card addSubview:deleteButton];

            UILabel *identity = [self label:action.canonicalIdentity
                                        size:7.8
                                      weight:UIFontWeightRegular
                                       color:self.theme.secondaryTextColor];
            identity.frame = CGRectMake(13, 40, card.bounds.size.width - 26, 20);
            identity.numberOfLines = 2;
            identity.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [card addSubview:identity];

            UITextField *description = ZNRMCBuilderTextField(CGRectMake(13, 65, card.bounds.size.width - 26, 29), self.theme);
            description.tag = kZNRMCBuilderDescriptionTagBase + (NSInteger)i;
            description.text = action.featureDescription ?: @"";
            description.placeholder = @"功能说明";
            description.font = [UIFont systemFontOfSize:9.2 weight:UIFontWeightRegular];
            [description addTarget:self action:@selector(znrmc_descriptionEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:description];

            if (hasArgument) {
                UITextField *argument = ZNRMCBuilderTextField(CGRectMake(13, 104, card.bounds.size.width - 26, 31), self.theme);
                argument.tag = kZNRMCBuilderArgumentTagBase + (NSInteger)i;
                argument.text = action.argumentValues.count ? action.argumentValues.firstObject : @"";
                argument.placeholder = @"参数值";
                argument.font = [UIFont monospacedDigitSystemFontOfSize:9.6 weight:UIFontWeightMedium];
                // M5.8.3: keep the model current while typing. This is required
                // for Slider authoring because the value at build time is its max.
                [argument addTarget:self action:@selector(znrmc_argumentEditingChanged:) forControlEvents:UIControlEventEditingChanged];
                [argument addTarget:self action:@selector(znrmc_argumentEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
                [card addSubview:argument];
            }

            [self.contentView addSubview:card];
            y += cardH + 10.0;
        }
    }
    NSArray<ZNNativeHookAction *> *hooks=[[ZNNativeHookStore sharedStore] actionsSnapshot];
    y += 4.0;
    UIView *hookHeader=[self cardAtY:y height:48 width:width compact:NO];
    UILabel *hookTitle=[self label:[NSString stringWithFormat:@"IL2CPP Native Hook · %lu",(unsigned long)hooks.count]
                              size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    hookTitle.frame=CGRectMake(13,8,hookHeader.bounds.size.width-96,31);
    [hookHeader addSubview:hookTitle];
    UIButton *hookClear=[self zn40_button:@"清空" selector:@selector(zn64_clearNativeHooks:) frame:CGRectMake(hookHeader.bounds.size.width-75,8,62,31)];
    hookClear.enabled=hooks.count>0;hookClear.alpha=hookClear.enabled?1.0:.5;
    [hookHeader addSubview:hookClear];
    [self.contentView addSubview:hookHeader];
    y += 56.0;

    if(!hooks.count){
        UIView *empty=[self cardAtY:y height:54 width:width compact:NO];
        UILabel *label=[self label:@"方法查找 → Hook 测试 → 安装真机测试 Hook → 创建 Hook 方法。"
                              size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame=CGRectMake(13,8,empty.bounds.size.width-26,38);label.numberOfLines=2;
        [empty addSubview:label];[self.contentView addSubview:empty];y+=62.0;
    }else{
        for(NSUInteger i=0;i<hooks.count;i++){
            ZNNativeHookAction *hook=hooks[i];
            UIView *card=[self cardAtY:y height:104 width:width compact:NO];
            UILabel *name=[self label:hook.title.length?hook.title:hook.methodName
                                size:10.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            name.frame=CGRectMake(13,7,card.bounds.size.width-82,22);[card addSubview:name];
            UIButton *del=[self zn40_button:@"删除" selector:@selector(zn64_deleteNativeHook:) frame:CGRectMake(card.bounds.size.width-65,7,52,27)];
            del.tag=kZNNativeHookDeleteTagBase+(NSInteger)i;[card addSubview:del];
            UILabel *identity=[self label:hook.canonicalIdentity size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            identity.frame=CGRectMake(13,35,card.bounds.size.width-26,20);identity.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:identity];
            NSString *info=nil;
            if(hook.templateKind==ZNNativeHookTemplateManagedCallbackShortCircuit){
                info=[NSString stringWithFormat:@"%@ · callback arg%lu · value=%@ · SkipOriginal · RVA=%@",
                      ZNNativeHookTemplateKey(hook.templateKind),(unsigned long)hook.callbackArgumentIndex,
                      hook.callbackValue?@"true":@"false",
                      hook.fallbackRVA?[NSString stringWithFormat:@"0x%llX",(unsigned long long)hook.fallbackRVA]:@"—"];
            }else{
                info=[NSString stringWithFormat:@"%@ · arg%lu · Slider %ld~%ld · default=%ld · RVA=%@",
                      ZNNativeHookTemplateKey(hook.templateKind),(unsigned long)hook.argumentIndex,
                      (long)hook.minValue,(long)hook.maxValue,(long)hook.defaultValue,
                      hook.fallbackRVA?[NSString stringWithFormat:@"0x%llX",(unsigned long long)hook.fallbackRVA]:@"—"];
            }
            UILabel *meta=[self label:info size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            meta.frame=CGRectMake(13,60,card.bounds.size.width-26,18);meta.adjustsFontSizeToFitWidth=YES;meta.minimumScaleFactor=.65;[card addSubview:meta];
            UILabel *desc=[self label:(hook.featureDescription.length?hook.featureDescription:@"Native Hook V1 · Dobby")
                                size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            desc.frame=CGRectMake(13,81,card.bounds.size.width-26,16);[card addSubview:desc];
            [self.contentView addSubview:card];y+=114.0;
        }
    }

    // M6.8 final gate runs after Native Hook authoring cards are rendered.
    // This intentionally uses the same snapshots that produced the visible
    // "Runtime Method Call · N" / "IL2CPP Native Hook · N" counts, avoiding
    // earlier swizzle/render ordering from leaving the build button stale.
    ZNRMCBuilderFinalizeBuildGate(self.contentView,actions.count,hooks.count);

    [self zn40_updateContentHeight:y];
}

- (void)znrmc_clearAuthoringActions:(id)sender {
    (void)sender;
    [[ZNRuntimeActionStore sharedStore] clear];
    [self renderPage];
}

- (void)zn64_clearNativeHooks:(id)sender {
    (void)sender;
    [[ZNNativeHookStore sharedStore] clear];
    [self renderPage];
}

- (void)zn64_deleteNativeHook:(UIButton *)sender {
    NSInteger index=sender.tag-kZNNativeHookDeleteTagBase;
    if(index>=0)[[ZNNativeHookStore sharedStore] removeActionAtIndex:(NSUInteger)index];
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

- (void)znrmc_descriptionEditingEnded:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderDescriptionTagBase;
    if (index < 0) return;
    NSString *error = nil;
    [[ZNRuntimeActionStore sharedStore] updateFeatureDescription:field.text atIndex:(NSUInteger)index error:&error];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if ((NSUInteger)index < actions.count) field.text = actions[(NSUInteger)index].featureDescription ?: @"";
    [field resignFirstResponder];
}

- (void)znrmc_argumentEditingChanged:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderArgumentTagBase;
    if (index < 0) return;
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[field.text ?: @""] atIndex:(NSUInteger)index error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.8.3-authoring] live argument update failed: %@", error ?: @"unknown"]];
    }
}

- (void)znrmc_argumentEditingEnded:(UITextField *)field {
    [self znrmc_argumentEditingChanged:field];
    NSInteger index = field.tag - kZNRMCBuilderArgumentTagBase;
    if (index < 0) return;
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
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Builder action list UI installed (M5.8.3 live argument sync)"];
        }
    });
}
