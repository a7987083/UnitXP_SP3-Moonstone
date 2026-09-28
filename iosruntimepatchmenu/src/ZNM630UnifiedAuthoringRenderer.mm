#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M6.3 canonical authoring renderer.
// Exactly one renderer owns the `其他` authoring page.
// It never appends another UI layer and never post-processes cards created by
// an older renderer.
//
// New authoring contract:
//   Offset: 功能名 + 说明 + exact IL2CPP Method Offset + Number/Slider (+ Max)
//   Runtime Method: 功能名 + 说明 + Runtime control
//
// Removed from new authoring:
//   - raw ARM64 HEX / Enabled input
//   - direct Offset numeric/raw-value authoring
//   - multi-Patch creation UI
// Legacy Static records remain runtime-readable for compatibility only.

static NSString * const ZNM630SliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";
static const NSInteger ZNM630OffsetFieldBase = 441000;
static const NSInteger ZNM630OffsetNameBase = 980000;
static const NSInteger ZNM630OffsetDescriptionBase = 981000;
static const NSInteger ZNM630OffsetControlBase = 982000;
static const NSInteger ZNM630OffsetMaxBase = 983000;
static const NSInteger ZNM630OffsetDeleteBase = 984000;
static const NSInteger ZNM630RuntimeNameBase = 985000;
static const NSInteger ZNM630RuntimeDescriptionBase = 986000;
static const NSInteger ZNM630RuntimeControlBase = 987000;
static const NSInteger ZNM630RuntimeMaxBase = 988000;
static const NSInteger ZNM630RuntimeDeleteBase = 989000;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UITextField *)zn44_field:(CGRect)frame text:(NSString *)text placeholder:(NSString *)placeholder tag:(NSInteger)tag enabled:(BOOL)enabled;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn44_renderOther;
- (void)zn44_buildBinary:(id)sender;
@end

static NSString *ZNM630Trim(NSString *s) {
    return [(s ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM630FeatureName(ZNBinaryPatchRow *row) {
    NSString *group = ZNM630Trim(row.group);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return group;
    NSString *title = ZNM630Trim(row.title);
    return title.length ? title : @"未命名功能";
}

static NSString *ZNM630SliderKey(NSString *name) {
    return [NSString stringWithFormat:@"%@.%@", ZNM630SliderMaxPrefix, ZNM630Trim(name).lowercaseString];
}

static UITextField *ZNM630Field(CGRect frame, ZNTheme *theme) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.layer.cornerRadius = 7.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0,0,8,1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

static NSArray<ZNBinaryPatchRow *> *ZNM630OffsetRows(void) {
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    [workspace ensureDefaultRows];
    NSMutableArray *rows = [NSMutableArray array];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        NSString *name = ZNM630FeatureName(row);
        BOOL meaningful = row.offsetText.length || row.enabledText.length || ZNM630Trim(row.group).length || ZNM630Trim(row.title).length;
        if (!meaningful) continue;
        // Keep one source row per visible feature. Legacy multi-Patch rows are
        // read-compatible but not exposed as editable new authoring rows.
        BOOL duplicate = NO;
        for (ZNBinaryPatchRow *existing in rows) {
            if ([ZNM630FeatureName(existing) caseInsensitiveCompare:name] == NSOrderedSame) { duplicate = YES; break; }
        }
        if (!duplicate) [rows addObject:row];
    }
    return rows;
}

static ZNRuntimeArgumentControlType ZNM630RuntimeControl(ZNRuntimeMethodAction *action) {
    if (action.argumentCount != 1 || action.argumentControlConfigs.count != 1) return ZNRuntimeArgumentControlTypeFixed;
    NSDictionary *cfg = action.argumentControlConfigs.firstObject;
    if (![cfg[@"enabled"] boolValue]) return ZNRuntimeArgumentControlTypeFixed;
    return ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
}

static void ZNM630PersistWorkspace(void) {
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    // M5.9.2 swizzles updateDefaultTarget and persists the complete authoring
    // workspace. Reuse that storage owner instead of creating another registry.
    [workspace updateDefaultTarget:workspace.defaultTarget];
}

@interface ZNRuntimeMenuControllerV040 (ZNM630UnifiedAuthoring)
- (void)znm630_renderOther;
- (void)znm630_addOffsetFeature:(id)sender;
- (void)znm630_offsetNameChanged:(UITextField *)field;
- (void)znm630_offsetDescriptionChanged:(UITextField *)field;
- (void)znm630_cycleOffsetControl:(UIButton *)sender;
- (void)znm630_offsetMaxChanged:(UITextField *)field;
- (void)znm630_deleteOffset:(UIButton *)sender;
- (void)znm630_runtimeNameChanged:(UITextField *)field;
- (void)znm630_runtimeDescriptionChanged:(UITextField *)field;
- (void)znm630_cycleRuntimeControl:(UIButton *)sender;
- (void)znm630_runtimeMaxChanged:(UITextField *)field;
- (void)znm630_deleteRuntime:(UIButton *)sender;
- (void)znm630_build:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM630UnifiedAuthoring)

- (void)znm630_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 9.0;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    BOOL locked = workspace.hasAnyApplied || workspace.isBuilding;

    UIView *intro = [self cardAtY:y height:54 width:width compact:NO];
    UILabel *introLabel = [self label:@"统一制作 · Offset 只用于解析 exact IL2CPP Method" size:9.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    introLabel.frame = CGRectMake(13,8,intro.bounds.size.width-26,18);
    [intro addSubview:introLabel];
    UILabel *sub = [self label:@"不提供 Raw Patch / Enabled / 普通 Offset 直接数字" size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    sub.frame = CGRectMake(13,28,intro.bounds.size.width-26,17);
    [intro addSubview:sub];
    [self.contentView addSubview:intro];
    y += 62.0;

    NSArray<ZNBinaryPatchRow *> *offsetRows = ZNM630OffsetRows();
    for (NSUInteger i=0; i<offsetRows.count; i++) {
        ZNBinaryPatchRow *row = offsetRows[i];
        NSString *name = ZNM630FeatureName(row);
        BOOL numeric = row.featureControlType == ZNFeatureControlTypeNumber || row.featureControlType == ZNFeatureControlTypeSlider;
        CGFloat cardH = row.featureControlType == ZNFeatureControlTypeSlider ? 170.0 : 132.0;
        UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

        UILabel *nameLabel = [self label:@"功能名" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
        nameLabel.frame = CGRectMake(13,7,42,28); [card addSubview:nameLabel];
        UITextField *nameField = ZNM630Field(CGRectMake(58,7,card.bounds.size.width-71,29),self.theme);
        nameField.tag = ZNM630OffsetNameBase + (NSInteger)i;
        nameField.text = name;
        nameField.enabled = !locked;
        [nameField addTarget:self action:@selector(znm630_offsetNameChanged:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
        [card addSubview:nameField];

        UILabel *descriptionLabel = [self label:@"说明" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
        descriptionLabel.frame = CGRectMake(13,42,42,28); [card addSubview:descriptionLabel];
        UITextField *description = ZNM630Field(CGRectMake(58,42,card.bounds.size.width-71,29),self.theme);
        description.tag = ZNM630OffsetDescriptionBase + (NSInteger)i;
        description.text = ([ZNM630Trim(row.group) caseInsensitiveCompare:@"Imported"] == NSOrderedSame) ? @"" : ZNM630Trim(row.title);
        description.placeholder = @"显示给客户的说明";
        description.enabled = !locked;
        [description addTarget:self action:@selector(znm630_offsetDescriptionChanged:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
        [card addSubview:description];

        UILabel *offsetLabel = [self label:@"Offset" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
        offsetLabel.frame = CGRectMake(13,77,42,28); [card addSubview:offsetLabel];
        NSUInteger globalIndex = [workspace.rows indexOfObjectIdenticalTo:row];
        UITextField *offset = [self zn44_field:CGRectMake(58,77,card.bounds.size.width-71,29)
                                          text:row.offsetText
                                   placeholder:@"0x4FAEA98 · exact IL2CPP Method Offset"
                                           tag:ZNM630OffsetFieldBase + (NSInteger)globalIndex
                                       enabled:!locked && numeric];
        [card addSubview:offset];

        UIButton *control = [self zn40_button:(numeric ? (row.featureControlType==ZNFeatureControlTypeSlider?@"控件 · 滑块":@"控件 · 数值") : @"旧 Static · 只读")
                                      selector:@selector(znm630_cycleOffsetControl:)
                                         frame:CGRectMake(13,112,card.bounds.size.width-82,29)];
        control.tag = ZNM630OffsetControlBase + (NSInteger)i;
        control.enabled = !locked && numeric;
        [card addSubview:control];
        UIButton *deleteButton = [self zn40_button:@"删除" selector:@selector(znm630_deleteOffset:) frame:CGRectMake(card.bounds.size.width-62,112,49,29)];
        deleteButton.tag = ZNM630OffsetDeleteBase + (NSInteger)i;
        deleteButton.enabled = !locked;
        [card addSubview:deleteButton];

        if (row.featureControlType == ZNFeatureControlTypeSlider) {
            UILabel *maxLabel = [self label:@"Max" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
            maxLabel.frame = CGRectMake(13,147,42,29); [card addSubview:maxLabel];
            UITextField *maxField = ZNM630Field(CGRectMake(58,147,card.bounds.size.width-71,29),self.theme);
            maxField.tag = ZNM630OffsetMaxBase + (NSInteger)i;
            id stored = [NSUserDefaults.standardUserDefaults objectForKey:ZNM630SliderKey(name)];
            maxField.text = [stored isKindOfClass:NSNumber.class] ? [(NSNumber *)stored stringValue] : @"";
            maxField.placeholder = @"例如 31";
            maxField.keyboardType = UIKeyboardTypeNumberPad;
            maxField.enabled = !locked;
            [maxField addTarget:self action:@selector(znm630_offsetMaxChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
            [card addSubview:maxField];
        }

        [self.contentView addSubview:card];
        y += cardH + 8.0;
    }

    UIView *add = [self cardAtY:y height:46 width:width compact:NO];
    UIButton *addButton = [self zn40_button:@"＋ 增加 Offset 功能" selector:@selector(znm630_addOffsetFeature:) frame:CGRectMake(13,7,add.bounds.size.width-26,32)];
    addButton.enabled = !locked;
    [add addSubview:addButton];
    [self.contentView addSubview:add];
    y += 54.0;

    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    UIView *runtimeHeader = [self cardAtY:y height:40 width:width compact:NO];
    UILabel *runtimeTitle = [self label:[NSString stringWithFormat:@"Runtime Method · %lu",(unsigned long)actions.count] size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    runtimeTitle.frame = CGRectMake(13,6,runtimeHeader.bounds.size.width-26,28);
    [runtimeHeader addSubview:runtimeTitle];
    [self.contentView addSubview:runtimeHeader];
    y += 48.0;

    for (NSUInteger i=0; i<actions.count; i++) {
        ZNRuntimeMethodAction *action = actions[i];
        BOOL oneArg = action.argumentCount == 1;
        CGFloat cardH = oneArg ? 151.0 : 112.0;
        UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

        UITextField *name = ZNM630Field(CGRectMake(13,7,card.bounds.size.width-76,29),self.theme);
        name.tag = ZNM630RuntimeNameBase + (NSInteger)i;
        name.text = action.title;
        name.placeholder = action.methodName;
        [name addTarget:self action:@selector(znm630_runtimeNameChanged:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
        [card addSubview:name];
        UIButton *deleteButton = [self zn40_button:@"删除" selector:@selector(znm630_deleteRuntime:) frame:CGRectMake(card.bounds.size.width-58,7,45,29)];
        deleteButton.tag = ZNM630RuntimeDeleteBase + (NSInteger)i;
        [card addSubview:deleteButton];

        UITextField *description = ZNM630Field(CGRectMake(13,42,card.bounds.size.width-26,29),self.theme);
        description.tag = ZNM630RuntimeDescriptionBase + (NSInteger)i;
        description.text = ([action.group caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame) ? @"" : action.group;
        description.placeholder = @"说明（显示给客户）";
        [description addTarget:self action:@selector(znm630_runtimeDescriptionChanged:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
        [card addSubview:description];

        UILabel *identity = [self label:action.canonicalIdentity size:7.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        identity.frame = CGRectMake(13,77,card.bounds.size.width-26,25);
        identity.numberOfLines = 2;
        identity.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:identity];

        if (oneArg) {
            ZNRuntimeArgumentControlType current = ZNM630RuntimeControl(action);
            UIButton *control = [self zn40_button:[NSString stringWithFormat:@"控件 · %@",ZNRuntimeArgumentControlTypeName(current)] selector:@selector(znm630_cycleRuntimeControl:) frame:CGRectMake(13,111,card.bounds.size.width*0.5-17,31)];
            control.tag = ZNM630RuntimeControlBase + (NSInteger)i;
            [card addSubview:control];
            if (current == ZNRuntimeArgumentControlTypeSlider) {
                NSDictionary *cfg = action.argumentControlConfigs.firstObject;
                UITextField *maxField = ZNM630Field(CGRectMake(card.bounds.size.width*0.5+2,111,card.bounds.size.width*0.5-15,31),self.theme);
                maxField.tag = ZNM630RuntimeMaxBase + (NSInteger)i;
                maxField.text = [cfg[@"max"] stringValue];
                maxField.placeholder = @"Max";
                maxField.keyboardType = UIKeyboardTypeNumberPad;
                [maxField addTarget:self action:@selector(znm630_runtimeMaxChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
                [card addSubview:maxField];
            }
        }

        [self.contentView addSubview:card];
        y += cardH + 8.0;
    }

    UIView *buildCard = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *build = [self zn40_button:(workspace.isBuilding?@"正在生成…":@"解析并生成新二进制") selector:@selector(znm630_build:) frame:CGRectMake(13,9,buildCard.bounds.size.width-26,34)];
    build.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && (offsetRows.count || actions.count);
    [buildCard addSubview:build];
    [self.contentView addSubview:buildCard];
    y += 60.0;

    if (workspace.lastStatus.length) {
        UIView *statusCard = [self cardAtY:y height:42 width:width compact:NO];
        UILabel *status = [self label:workspace.lastStatus size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13,6,statusCard.bounds.size.width-26,30);
        status.numberOfLines = 2;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 50.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znm630_addOffsetFeature:(id)sender {
    (void)sender;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (workspace.isBuilding || workspace.hasAnyApplied) return;
    NSUInteger serial=1;
    NSMutableSet *names=[NSMutableSet set];
    for (ZNBinaryPatchRow *row in workspace.rows) [names addObject:ZNM630FeatureName(row).lowercaseString];
    NSString *name=nil;
    do { name=[NSString stringWithFormat:@"新功能 %lu",(unsigned long)serial++]; } while ([names containsObject:name.lowercaseString]);
    ZNBinaryPatchRow *row=[ZNBinaryPatchRow new];
    row.group=name;
    row.title=@"";
    row.statusText=@"待填写 exact Offset";
    row.featureControlType=ZNFeatureControlTypeNumber;
    [workspace.rows addObject:row];
    ZNM630PersistWorkspace();
    workspace.lastStatus=[NSString stringWithFormat:@"已增加：%@",name];
    [self renderPage];
}

- (void)znm630_offsetNameChanged:(UITextField *)field {
    NSInteger idx=field.tag-ZNM630OffsetNameBase;
    NSArray *rows=ZNM630OffsetRows();
    if(idx<0||(NSUInteger)idx>=rows.count)return;
    ZNBinaryPatchRow *row=rows[(NSUInteger)idx];
    NSString *name=ZNM630Trim(field.text);
    if(!name.length){field.text=ZNM630FeatureName(row);return;}
    NSString *old=ZNM630FeatureName(row);
    id oldMax=[NSUserDefaults.standardUserDefaults objectForKey:ZNM630SliderKey(old)];
    row.group=name;
    if(oldMax){[NSUserDefaults.standardUserDefaults setObject:oldMax forKey:ZNM630SliderKey(name)];[NSUserDefaults.standardUserDefaults removeObjectForKey:ZNM630SliderKey(old)];}
    ZNM630PersistWorkspace();
    [field resignFirstResponder];
}

- (void)znm630_offsetDescriptionChanged:(UITextField *)field {
    NSInteger idx=field.tag-ZNM630OffsetDescriptionBase;
    NSArray *rows=ZNM630OffsetRows();
    if(idx<0||(NSUInteger)idx>=rows.count)return;
    rows[(NSUInteger)idx].title=ZNM630Trim(field.text);
    ZNM630PersistWorkspace();
    [field resignFirstResponder];
}

- (void)znm630_cycleOffsetControl:(UIButton *)sender {
    NSInteger idx=sender.tag-ZNM630OffsetControlBase;
    NSArray *rows=ZNM630OffsetRows();
    if(idx<0||(NSUInteger)idx>=rows.count)return;
    ZNBinaryPatchRow *row=rows[(NSUInteger)idx];
    if(row.featureControlType!=ZNFeatureControlTypeNumber&&row.featureControlType!=ZNFeatureControlTypeSlider)return;
    row.featureControlType=(row.featureControlType==ZNFeatureControlTypeNumber)?ZNFeatureControlTypeSlider:ZNFeatureControlTypeNumber;
    row.validated=NO;
    row.validator=nil;
    ZNM630PersistWorkspace();
    [self renderPage];
}

- (void)znm630_offsetMaxChanged:(UITextField *)field {
    NSInteger idx=field.tag-ZNM630OffsetMaxBase;
    NSArray *rows=ZNM630OffsetRows();
    if(idx<0||(NSUInteger)idx>=rows.count)return;
    ZNBinaryPatchRow *row=rows[(NSUInteger)idx];
    double max=field.text.doubleValue;
    NSString *key=ZNM630SliderKey(ZNM630FeatureName(row));
    if(isfinite(max)&&max>0.0)[NSUserDefaults.standardUserDefaults setDouble:max forKey:key];
    else[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    row.validated=NO;
    row.validator=nil;
}

- (void)znm630_deleteOffset:(UIButton *)sender {
    NSInteger idx=sender.tag-ZNM630OffsetDeleteBase;
    NSArray *rows=ZNM630OffsetRows();
    if(idx<0||(NSUInteger)idx>=rows.count)return;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    ZNBinaryPatchRow *row=rows[(NSUInteger)idx];
    NSString *feature=ZNM630FeatureName(row);
    NSIndexSet *indexes=[workspace.rows indexesOfObjectsPassingTest:^BOOL(ZNBinaryPatchRow *candidate, NSUInteger index, BOOL *stop){(void)index;(void)stop;return [ZNM630FeatureName(candidate) caseInsensitiveCompare:feature]==NSOrderedSame;}];
    [workspace.rows removeObjectsAtIndexes:indexes];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:ZNM630SliderKey(feature)];
    [workspace ensureDefaultRows];
    ZNM630PersistWorkspace();
    [self renderPage];
}

- (void)znm630_runtimeNameChanged:(UITextField *)field {
    NSInteger idx=field.tag-ZNM630RuntimeNameBase;
    if(idx<0)return;
    [[ZNRuntimeActionStore sharedStore] updateTitle:field.text atIndex:(NSUInteger)idx error:nil];
    [field resignFirstResponder];
}

- (void)znm630_runtimeDescriptionChanged:(UITextField *)field {
    NSInteger idx=field.tag-ZNM630RuntimeDescriptionBase;
    if(idx<0)return;
    [[ZNRuntimeActionStore sharedStore] updateGroup:field.text atIndex:(NSUInteger)idx error:nil];
    [field resignFirstResponder];
}

- (void)znm630_cycleRuntimeControl:(UIButton *)sender {
    NSInteger idx=sender.tag-ZNM630RuntimeControlBase;
    NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if(idx<0||(NSUInteger)idx>=actions.count)return;
    ZNRuntimeMethodAction *action=actions[(NSUInteger)idx];
    if(action.argumentCount!=1)return;
    ZNRuntimeArgumentControlType current=ZNM630RuntimeControl(action),next=ZNRuntimeArgumentControlTypeFixed;
    switch(current){
        case ZNRuntimeArgumentControlTypeFixed: next=ZNRuntimeArgumentControlTypeNumber; break;
        case ZNRuntimeArgumentControlTypeNumber: next=ZNRuntimeArgumentControlTypeSlider; break;
        case ZNRuntimeArgumentControlTypeSlider: next=ZNRuntimeArgumentControlTypeSwitch; break;
        case ZNRuntimeArgumentControlTypeSwitch: next=ZNRuntimeArgumentControlTypeButton; break;
        default: next=ZNRuntimeArgumentControlTypeFixed; break;
    }
    NSMutableDictionary *cfg=[action.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];
    cfg[@"enabled"]=@(next!=ZNRuntimeArgumentControlTypeFixed);
    cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(next);
    if(next==ZNRuntimeArgumentControlTypeSlider){
        double max=[cfg[@"max"] doubleValue];
        if(!isfinite(max)||max<=0.0||max>1000000.0)max=10.0;
        cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);
        [[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[[NSString stringWithFormat:@"%.0f",max]] atIndex:(NSUInteger)idx error:nil];
    }
    [[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)idx error:nil];
    [self renderPage];
}

- (void)znm630_runtimeMaxChanged:(UITextField *)field {
    NSInteger idx=field.tag-ZNM630RuntimeMaxBase;
    NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if(idx<0||(NSUInteger)idx>=actions.count)return;
    ZNRuntimeMethodAction *action=actions[(NSUInteger)idx];
    if(action.argumentCount!=1)return;
    double max=field.text.doubleValue;
    if(!isfinite(max)||max<=0.0)return;
    NSMutableDictionary *cfg=[action.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];
    cfg[@"enabled"]=@YES;
    cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(ZNRuntimeArgumentControlTypeSlider);
    cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);
    [[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)idx error:nil];
    [[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[[NSString stringWithFormat:@"%.15g",max]] atIndex:(NSUInteger)idx error:nil];
}

- (void)znm630_deleteRuntime:(UIButton *)sender {
    NSInteger idx=sender.tag-ZNM630RuntimeDeleteBase;
    if(idx>=0)[[ZNRuntimeActionStore sharedStore] removeActionAtIndex:(NSUInteger)idx];
    [self renderPage];
}

- (void)znm630_build:(id)sender {
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    for(ZNBinaryPatchRow *row in ZNM630OffsetRows()){
        if(!row.offsetText.length){workspace.lastStatus=[NSString stringWithFormat:@"%@：必须填写 exact IL2CPP Method Offset",ZNM630FeatureName(row)];[self renderPage];return;}
        if(row.featureControlType!=ZNFeatureControlTypeNumber&&row.featureControlType!=ZNFeatureControlTypeSlider){workspace.lastStatus=[NSString stringWithFormat:@"%@：旧 Static 记录仅兼容读取，不能作为新数值功能生成",ZNM630FeatureName(row)];[self renderPage];return;}
        if(row.featureControlType==ZNFeatureControlTypeSlider){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM630SliderKey(ZNM630FeatureName(row))];if(![stored isKindOfClass:NSNumber.class]||[(NSNumber *)stored doubleValue]<=0.0){workspace.lastStatus=[NSString stringWithFormat:@"%@：Slider Max 必须大于 0",ZNM630FeatureName(row)];[self renderPage];return;}}
    }
    NSString *error=nil;
    if(![workspace validateAll:&error]){workspace.lastStatus=[NSString stringWithFormat:@"解析准备失败：%@",error?:@"未知错误"];[self renderPage];return;}
    [self zn44_buildBinary:sender];
}

@end

static void ZNM630Swap(Class cls, SEL original, SEL replacement) {
    Method a=class_getInstanceMethod(cls,original), b=class_getInstanceMethod(cls,replacement);
    if(a&&b)method_exchangeImplementations(a,b);
}

extern "C" void ZNInstallFeatureBuilderUIDeferred(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls)return;
        ZNM630Swap(cls,@selector(zn44_renderOther),@selector(znm630_renderOther));
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.3-authoring] single Builder renderer installed; raw/direct-value UI removed"];
    });
}
