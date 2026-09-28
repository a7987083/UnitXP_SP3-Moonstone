#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M6.3 canonical authoring surface.
// One renderer owns the entire `其他` Builder page. There is no post-render
// overlay and no second Runtime Builder renderer.
//
// New Offset authoring is intentionally narrow:
//   功能名 + 说明 + Offset + Number/Slider (+ Slider Max)
// There is NO Enabled/ARM64 HEX field, NO direct numeric Offset patch value,
// and NO "增加 Patch" path. M6.1/M6.3 resolves Offset -> exact IL2CPP method
// and promotes it to Runtime backend at build time.
// Legacy imported Static rows may remain readable for compatibility, but the
// M6.3 UI does not expose raw patch authoring controls for them.

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UITextField *)zn44_field:(CGRect)frame text:(NSString *)text placeholder:(NSString *)placeholder tag:(NSInteger)tag enabled:(BOOL)enabled;
- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn44_renderOther;
- (void)zn44_importJSON:(id)sender;
- (void)zn44_jsonTapped:(UIButton *)sender;
- (void)zn44_buildBinary:(id)sender;
@end

static const void *kZN50BExpandedFeatureKeys = &kZN50BExpandedFeatureKeys;
static const NSInteger kZN50BExpandTagBase = 460000;
static const NSInteger kZN50BRenameTagBase = 462000;
static const NSInteger kZN50BDescriptionTagBase = 463000;
static const NSInteger kZN50BOffsetTagBase = 441000;
static const NSInteger kZN50BControlTagBase = 466000;
static const NSInteger kZN50BDeleteTagBase = 467000;
static const NSInteger kZN50BSliderMaxTagBase = 931000;
static const NSInteger kZN50BRuntimeTitleTagBase = 972000;
static const NSInteger kZN50BRuntimeDescriptionTagBase = 973000;
static const NSInteger kZN50BRuntimeDeleteTagBase = 974000;
static const NSInteger kZN50BRuntimeControlTagBase = 975000;
static const NSInteger kZN50BRuntimeMaxTagBase = 976000;
static NSString * const kZN50BSliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *ZN50BTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN50BFeatureKey(NSString *name) { return ZN50BTrim(name).lowercaseString; }
static NSString *ZN50BSliderKey(NSString *name) { return [NSString stringWithFormat:@"%@.%@", kZN50BSliderMaxPrefix, ZN50BFeatureKey(name)]; }

static UITextField *ZN50BStyledField(CGRect frame, ZNTheme *theme) {
    UITextField *field=[[UITextField alloc]initWithFrame:frame];
    field.textColor=theme.primaryTextColor;
    field.backgroundColor=theme.controlColor;
    field.font=[UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
    field.autocorrectionType=UITextAutocorrectionTypeNo;
    field.autocapitalizationType=UITextAutocapitalizationTypeNone;
    field.returnKeyType=UIReturnKeyDone;
    field.clearButtonMode=UITextFieldViewModeWhileEditing;
    field.layer.cornerRadius=7.0;
    field.layer.borderWidth=1.0;
    field.layer.borderColor=theme.borderColor.CGColor;
    UIView *pad=[[UIView alloc]initWithFrame:CGRectMake(0,0,8,1)];
    field.leftView=pad; field.leftViewMode=UITextFieldViewModeAlways;
    return field;
}

static void ZN50BNormalizeImportedGroups(ZNBinaryPatchWorkspace *workspace) {
    for (ZNBinaryPatchRow *row in workspace.rows) {
        NSString *group=ZN50BTrim(row.group), *title=ZN50BTrim(row.title);
        if ((!group.length || [group caseInsensitiveCompare:@"Imported"]==NSOrderedSame) && title.length) row.group=title;
    }
}

static BOOL ZN50BRowVisible(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *group=ZN50BTrim(row.group), *title=ZN50BTrim(row.title);
    return group.length || title.length;
}

static NSArray<NSDictionary *> *ZN50BFeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    ZN50BNormalizeImportedGroups(workspace);
    NSMutableArray *order=[NSMutableArray array];
    NSMutableDictionary *rows=[NSMutableDictionary dictionary], *names=[NSMutableDictionary dictionary];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZN50BRowVisible(row)) continue;
        NSString *name=ZN50BTrim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"]==NSOrderedSame) name=ZN50BTrim(row.title);
        if (!name.length) name=@"未命名功能";
        NSString *key=ZN50BFeatureKey(name);
        if (!rows[key]) { rows[key]=[NSMutableArray array]; names[key]=name; [order addObject:key]; }
        [rows[key] addObject:row];
    }
    NSMutableArray *out=[NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) [out addObject:@{@"key":key,@"name":names[key]?:@"功能",@"rows":[rows[key] copy]?:@[]}];
    return out;
}

static NSMutableSet<NSString *> *ZN50BExpandedKeys(ZNRuntimeMenuControllerV040 *controller) {
    NSMutableSet *set=objc_getAssociatedObject(controller,kZN50BExpandedFeatureKeys);
    if (!set) { set=[NSMutableSet set]; objc_setAssociatedObject(controller,kZN50BExpandedFeatureKeys,set,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return set;
}

static NSString *ZN50BOffsetControlTitle(ZNFeatureControlType type) {
    return type==ZNFeatureControlTypeSlider ? @"控件 · 滑块" : @"控件 · 数值";
}

static ZNRuntimeArgumentControlType ZN50BRuntimeControlType(ZNRuntimeMethodAction *action) {
    if (action.argumentCount!=1 || action.argumentControlConfigs.count!=1) return ZNRuntimeArgumentControlTypeFixed;
    NSDictionary *cfg=action.argumentControlConfigs.firstObject;
    if (![cfg[@"enabled"] boolValue]) return ZNRuntimeArgumentControlTypeFixed;
    return ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
}

@implementation ZNBinaryPatchWorkspace (ZNFeatureEditing)
- (NSString *)addFeature {
    if (self.hasAnyApplied || self.isBuilding) { self.lastStatus=@"当前状态不可增加功能"; return @""; }
    NSMutableSet *used=[NSMutableSet set];
    for (ZNBinaryPatchRow *row in self.rows) if (ZN50BTrim(row.group).length) [used addObject:ZN50BFeatureKey(row.group)];
    NSUInteger serial=1; NSString *name=nil;
    do { name=[NSString stringWithFormat:@"新功能 %lu",(unsigned long)serial++]; } while ([used containsObject:ZN50BFeatureKey(name)]);
    ZNBinaryPatchRow *row=[ZNBinaryPatchRow new];
    row.group=name; row.title=@""; row.statusText=@"待填写 Offset"; row.featureControlType=ZNFeatureControlTypeNumber;
    [self.rows addObject:row];
    [self updateDefaultTarget:self.defaultTarget]; // trigger M5.9.2 persistence
    self.lastStatus=[NSString stringWithFormat:@"已增加功能：%@",name];
    return name;
}
- (void)addPatchToFeature:(NSString *)featureName {
    (void)featureName;
    self.lastStatus=@"M6.3 已取消多 Patch/Raw Patch 制作；一个 Offset 功能只保留一个 Source";
}
- (BOOL)renameFeature:(NSString *)oldName to:(NSString *)newName error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) { if(error)*error=@"当前状态不可重命名功能"; return NO; }
    NSString *oldValue=ZN50BTrim(oldName), *newValue=ZN50BTrim(newName);
    if (!newValue.length) { if(error)*error=@"功能名称不能为空"; return NO; }
    for (ZNBinaryPatchRow *row in self.rows) {
        NSString *g=ZN50BTrim(row.group);
        if ([g caseInsensitiveCompare:newValue]==NSOrderedSame && [g caseInsensitiveCompare:oldValue]!=NSOrderedSame) { if(error)*error=@"已存在同名功能"; return NO; }
    }
    BOOL changed=NO;
    for (ZNBinaryPatchRow *row in self.rows) if ([ZN50BTrim(row.group) caseInsensitiveCompare:oldValue]==NSOrderedSame) { row.group=newValue; changed=YES; }
    if (!changed) { if(error)*error=@"找不到功能"; return NO; }
    id oldMax=[NSUserDefaults.standardUserDefaults objectForKey:ZN50BSliderKey(oldValue)];
    if (oldMax) { [NSUserDefaults.standardUserDefaults setObject:oldMax forKey:ZN50BSliderKey(newValue)]; [NSUserDefaults.standardUserDefaults removeObjectForKey:ZN50BSliderKey(oldValue)]; }
    [self updateDefaultTarget:self.defaultTarget];
    self.lastStatus=[NSString stringWithFormat:@"功能已重命名：%@ → %@",oldValue,newValue];
    return YES;
}
@end

@interface ZNRuntimeMenuControllerV040 (ZNFeatureBuilderUI)
- (void)zn50b_renderOther;
- (void)zn50b_expandFeature:(UIButton *)sender;
- (void)zn50b_addFeature:(id)sender;
- (void)zn50b_featureNameEnd:(UITextField *)field;
- (void)zn50b_descriptionEnd:(UITextField *)field;
- (void)zn50b_cycleOffsetControl:(UIButton *)sender;
- (void)zn50b_sliderMaxChanged:(UITextField *)field;
- (void)zn50b_deleteOffsetFeature:(UIButton *)sender;
- (void)zn50b_runtimeTitleEnd:(UITextField *)field;
- (void)zn50b_runtimeDescriptionEnd:(UITextField *)field;
- (void)zn50b_runtimeDelete:(UIButton *)sender;
- (void)zn50b_runtimeCycleControl:(UIButton *)sender;
- (void)zn50b_runtimeMaxChanged:(UITextField *)field;
- (void)zn50b_buildUnified:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureBuilderUI)

- (void)zn50b_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds), y=9.0;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    [workspace ensureDefaultRows]; ZN50BNormalizeImportedGroups(workspace);
    BOOL locked=workspace.hasAnyApplied||workspace.isBuilding;

    UIView *targetCard=[self cardAtY:y height:56 width:width compact:NO];
    UILabel *binaryLabel=[self label:@"二进制" size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    binaryLabel.frame=CGRectMake(13,11,50,32); [targetCard addSubview:binaryLabel];
    CGFloat importW=78.0;
    UITextField *target=[self zn44_field:CGRectMake(65,11,targetCard.bounds.size.width-65-importW-18,32) text:workspace.defaultTarget placeholder:@"UnityFramework" tag:440000 enabled:!locked];
    [targetCard addSubview:target];
    UIButton *import=[self zn40_button:(workspace.showJSONFiles?@"收起 JSON":@"导入 JSON") selector:@selector(zn44_importJSON:) frame:CGRectMake(targetCard.bounds.size.width-importW-9,11,importW,32)];
    import.enabled=!locked; [targetCard addSubview:import]; [self.contentView addSubview:targetCard]; y+=64;

    if (workspace.showJSONFiles) {
        NSUInteger shown=workspace.jsonFiles.count; CGFloat h=32.0+shown*34.0;
        UIView *jsonCard=[self cardAtY:y height:h width:width compact:NO];
        UILabel *title=[self label:[NSString stringWithFormat:@"同目录 JSON · %lu",(unsigned long)shown] size:10.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        title.frame=CGRectMake(13,7,jsonCard.bounds.size.width-26,17); [jsonCard addSubview:title];
        for(NSUInteger i=0;i<shown;i++){NSString *path=workspace.jsonFiles[i];UIButton *b=[self zn40_button:path.lastPathComponent selector:@selector(zn44_jsonTapped:) frame:CGRectMake(13,27+i*34,jsonCard.bounds.size.width-26,28)];b.tag=446000+(NSInteger)i;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[jsonCard addSubview:b];}
        [self.contentView addSubview:jsonCard]; y+=h+8;
    }

    NSArray *features=ZN50BFeatureGroups(workspace); NSMutableSet *expanded=ZN50BExpandedKeys(self);
    for(NSUInteger featureIndex=0;featureIndex<features.count;featureIndex++){
        NSDictionary *feature=features[featureIndex]; NSString *key=feature[@"key"], *name=feature[@"name"]; NSArray *rows=feature[@"rows"]; ZNBinaryPatchRow *row=rows.firstObject;
        BOOL isExpanded=[expanded containsObject:key];
        UIView *head=[self cardAtY:y height:48 width:width compact:NO];
        UILabel *nameLabel=[self label:name size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];nameLabel.frame=CGRectMake(13,8,head.bounds.size.width-130,30);[head addSubview:nameLabel];
        UIButton *expand=[self zn40_button:(isExpanded?@"收起 ▲":@"编辑 ▼") selector:@selector(zn50b_expandFeature:) frame:CGRectMake(head.bounds.size.width-112,8,100,32)];expand.tag=kZN50BExpandTagBase+(NSInteger)featureIndex;[head addSubview:expand];[self.contentView addSubview:head];y+=54;
        if(!isExpanded||!row)continue;

        UIView *nameCard=[self cardAtY:y height:86 width:width compact:NO];
        UILabel *n1=[self label:@"功能名" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];n1.frame=CGRectMake(18,8,45,30);[nameCard addSubview:n1];
        UITextField *nameField=ZN50BStyledField(CGRectMake(63,8,nameCard.bounds.size.width-78,31),self.theme);nameField.tag=kZN50BRenameTagBase+(NSInteger)featureIndex;nameField.text=name;nameField.enabled=!locked;[nameField addTarget:self action:@selector(zn50b_featureNameEnd:) forControlEvents:UIControlEventEditingDidEndOnExit|UIControlEventEditingDidEnd];[nameCard addSubview:nameField];
        UILabel *n2=[self label:@"说明" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];n2.frame=CGRectMake(18,46,45,30);[nameCard addSubview:n2];
        UITextField *desc=ZN50BStyledField(CGRectMake(63,46,nameCard.bounds.size.width-78,31),self.theme);desc.tag=kZN50BDescriptionTagBase+(NSInteger)featureIndex;desc.text=ZN50BTrim(row.title);desc.placeholder=@"显示给客户的说明";desc.enabled=!locked;[desc addTarget:self action:@selector(zn50b_descriptionEnd:) forControlEvents:UIControlEventEditingDidEndOnExit|UIControlEventEditingDidEnd];[nameCard addSubview:desc];
        [self.contentView addSubview:nameCard];y+=94;

        BOOL numeric=(row.featureControlType==ZNFeatureControlTypeNumber||row.featureControlType==ZNFeatureControlTypeSlider);
        UIView *source=[self cardAtY:y height:(row.featureControlType==ZNFeatureControlTypeSlider?126:88) width:width compact:NO];
        UILabel *ol=[self label:@"Offset" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];ol.frame=CGRectMake(18,8,45,30);[source addSubview:ol];
        UITextField *offset=[self zn44_field:CGRectMake(63,8,source.bounds.size.width-78,31) text:row.offsetText placeholder:@"0x4FAEA98 · exact IL2CPP method" tag:kZN50BOffsetTagBase+(NSInteger)[workspace.rows indexOfObjectIdenticalTo:row] enabled:!locked&&numeric];[source addSubview:offset];
        UIButton *type=[self zn40_button:(numeric?ZN50BOffsetControlTitle(row.featureControlType):@"旧 Static · 只读兼容") selector:@selector(zn50b_cycleOffsetControl:) frame:CGRectMake(18,47,source.bounds.size.width-94,32)];type.tag=kZN50BControlTagBase+(NSInteger)featureIndex;type.enabled=!locked&&numeric;[source addSubview:type];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(zn50b_deleteOffsetFeature:) frame:CGRectMake(source.bounds.size.width-68,47,56,32)];del.tag=kZN50BDeleteTagBase+(NSInteger)featureIndex;del.enabled=!locked;[source addSubview:del];
        if(row.featureControlType==ZNFeatureControlTypeSlider){UILabel *ml=[self label:@"Max" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];ml.frame=CGRectMake(18,86,45,30);[source addSubview:ml];UITextField *max=ZN50BStyledField(CGRectMake(63,86,source.bounds.size.width-78,31),self.theme);max.tag=kZN50BSliderMaxTagBase+(NSInteger)featureIndex;id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZN50BSliderKey(name)];max.text=[stored isKindOfClass:NSNumber.class]?[stored stringValue]:@"";max.placeholder=@"例如 31";max.keyboardType=UIKeyboardTypeNumberPad;max.enabled=!locked;[max addTarget:self action:@selector(zn50b_sliderMaxChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];[source addSubview:max];}
        [self.contentView addSubview:source];y+=CGRectGetHeight(source.bounds)+8;
        if(rows.count>1){UIView *legacy=[self cardAtY:y height:40 width:width compact:NO];UILabel *l=[self label:[NSString stringWithFormat:@"旧版多 Patch 数据 %lu 条：仅兼容读取，不再提供新增/Raw Patch 编辑",(unsigned long)rows.count] size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,8,legacy.bounds.size.width-26,24);[legacy addSubview:l];[self.contentView addSubview:legacy];y+=48;}
    }

    UIView *add=[self cardAtY:y height:48 width:width compact:NO];UIButton *addFeature=[self zn40_button:@"＋ 增加 Offset 功能" selector:@selector(zn50b_addFeature:) frame:CGRectMake(13,7,add.bounds.size.width-26,34)];addFeature.enabled=!locked;[add addSubview:addFeature];[self.contentView addSubview:add];y+=58;

    NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    UIView *rh=[self cardAtY:y height:42 width:width compact:NO];UILabel *rt=[self label:[NSString stringWithFormat:@"Runtime Method · %lu",(unsigned long)actions.count] size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];rt.frame=CGRectMake(13,7,rh.bounds.size.width-26,28);[rh addSubview:rt];[self.contentView addSubview:rh];y+=50;
    for(NSUInteger i=0;i<actions.count;i++){
        ZNRuntimeMethodAction *a=actions[i]; BOOL one=a.argumentCount==1; CGFloat h=one?154:116;
        UIView *card=[self cardAtY:y height:h width:width compact:NO];
        UITextField *title=ZN50BStyledField(CGRectMake(13,7,card.bounds.size.width-82,29),self.theme);title.tag=kZN50BRuntimeTitleTagBase+(NSInteger)i;title.text=a.title;title.placeholder=a.methodName;[title addTarget:self action:@selector(zn50b_runtimeTitleEnd:) forControlEvents:UIControlEventEditingDidEndOnExit|UIControlEventEditingDidEnd];[card addSubview:title];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(zn50b_runtimeDelete:) frame:CGRectMake(card.bounds.size.width-65,7,52,29)];del.tag=kZN50BRuntimeDeleteTagBase+(NSInteger)i;[card addSubview:del];
        UITextField *desc=ZN50BStyledField(CGRectMake(13,43,card.bounds.size.width-26,29),self.theme);desc.tag=kZN50BRuntimeDescriptionTagBase+(NSInteger)i;desc.text=([a.group caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame?@"":a.group);desc.placeholder=@"说明（显示给客户）";[desc addTarget:self action:@selector(zn50b_runtimeDescriptionEnd:) forControlEvents:UIControlEventEditingDidEndOnExit|UIControlEventEditingDidEnd];[card addSubview:desc];
        UILabel *idn=[self label:a.canonicalIdentity size:7.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];idn.frame=CGRectMake(13,77,card.bounds.size.width-26,28);idn.numberOfLines=2;idn.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:idn];
        if(one){ZNRuntimeArgumentControlType ct=ZN50BRuntimeControlType(a);NSString *ctName=ZNRuntimeArgumentControlTypeName(ct);UIButton *ctrl=[self zn40_button:[NSString stringWithFormat:@"控件 · %@",ctName] selector:@selector(zn50b_runtimeCycleControl:) frame:CGRectMake(13,112,card.bounds.size.width*0.5-18,32)];ctrl.tag=kZN50BRuntimeControlTagBase+(NSInteger)i;[card addSubview:ctrl];if(ct==ZNRuntimeArgumentControlTypeSlider){NSDictionary *cfg=a.argumentControlConfigs.firstObject;UITextField *max=ZN50BStyledField(CGRectMake(card.bounds.size.width*0.5+2,112,card.bounds.size.width*0.5-15,32),self.theme);max.tag=kZN50BRuntimeMaxTagBase+(NSInteger)i;max.text=[cfg[@"max"] stringValue];max.placeholder=@"Max";max.keyboardType=UIKeyboardTypeNumberPad;[max addTarget:self action:@selector(zn50b_runtimeMaxChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];[card addSubview:max];}}
        [self.contentView addSubview:card];y+=h+8;
    }

    UIView *buildCard=[self cardAtY:y height:54 width:width compact:NO];UIButton *build=[self zn40_button:(workspace.isBuilding?@"正在生成…":@"解析并生成新二进制") selector:@selector(zn50b_buildUnified:) frame:CGRectMake(13,10,buildCard.bounds.size.width-26,34)];build.enabled=!workspace.isBuilding&&!workspace.hasAnyApplied&&(actions.count>0||features.count>0);[buildCard addSubview:build];[self.contentView addSubview:buildCard];y+=62;

    if(workspace.lastStatus.length){UIView *statusCard=[self cardAtY:y height:42 width:width compact:NO];UILabel *status=[self label:workspace.lastStatus size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];status.frame=CGRectMake(13,7,statusCard.bounds.size.width-26,28);status.numberOfLines=2;[statusCard addSubview:status];[self.contentView addSubview:statusCard];y+=50;}
    if(workspace.lastOutputPaths.count){NSMutableArray *lines=[NSMutableArray array];for(NSUInteger i=0;i<MIN((NSUInteger)4,workspace.lastOutputPaths.count);i++) [lines addObject:workspace.lastOutputPaths[i]];[self zn40_addInfoCard:@"最近输出" lines:lines y:&y width:width];}
    [self zn40_updateContentHeight:y];
}

- (void)zn50b_expandFeature:(UIButton *)sender { NSInteger index=sender.tag-kZN50BExpandTagBase;if(index<0)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSArray *f=ZN50BFeatureGroups(w);if((NSUInteger)index>=f.count)return;NSString *key=f[(NSUInteger)index][@"key"];NSMutableSet *e=ZN50BExpandedKeys(self);if([e containsObject:key])[e removeObject:key];else[e addObject:key];[self renderPage]; }
- (void)zn50b_addFeature:(id)sender { (void)sender;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *name=[w addFeature];if(name.length)[ZN50BExpandedKeys(self)addObject:ZN50BFeatureKey(name)];[self renderPage]; }
- (void)zn50b_featureNameEnd:(UITextField *)field { NSInteger index=field.tag-kZN50BRenameTagBase;if(index<0)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSArray *f=ZN50BFeatureGroups(w);if((NSUInteger)index>=f.count)return;NSString *old=f[(NSUInteger)index][@"name"],*new=ZN50BTrim(field.text),*error=nil;if([w renameFeature:old to:new error:&error]){NSMutableSet *e=ZN50BExpandedKeys(self);[e removeObject:ZN50BFeatureKey(old)];[e addObject:ZN50BFeatureKey(new)];}else{w.lastStatus=[NSString stringWithFormat:@"重命名失败：%@",error?:@"未知错误"];}[self.hostWindow endEditing:YES];[self renderPage]; }
- (void)zn50b_descriptionEnd:(UITextField *)field { NSInteger index=field.tag-kZN50BDescriptionTagBase;if(index<0)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSArray *f=ZN50BFeatureGroups(w);if((NSUInteger)index>=f.count)return;for(ZNBinaryPatchRow *r in f[(NSUInteger)index][@"rows"])r.title=ZN50BTrim(field.text);[w updateDefaultTarget:w.defaultTarget];[field resignFirstResponder]; }
- (void)zn50b_cycleOffsetControl:(UIButton *)sender { NSInteger index=sender.tag-kZN50BControlTagBase;if(index<0)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSArray *f=ZN50BFeatureGroups(w);if((NSUInteger)index>=f.count)return;NSString *name=f[(NSUInteger)index][@"name"];ZNBinaryPatchRow *row=[f[(NSUInteger)index][@"rows"] firstObject];if(row.featureControlType!=ZNFeatureControlTypeNumber&&row.featureControlType!=ZNFeatureControlTypeSlider)return;ZNFeatureControlType next=row.featureControlType==ZNFeatureControlTypeSlider?ZNFeatureControlTypeNumber:ZNFeatureControlTypeSlider;NSString *error=nil;if(![w setControlType:next forFeature:name error:&error])w.lastStatus=error?:@"修改控件失败";[self renderPage]; }
- (void)zn50b_sliderMaxChanged:(UITextField *)field { NSInteger index=field.tag-kZN50BSliderMaxTagBase;if(index<0)return;NSArray *f=ZN50BFeatureGroups([ZNBinaryPatchWorkspace sharedWorkspace]);if((NSUInteger)index>=f.count)return;NSString *name=f[(NSUInteger)index][@"name"];double v=field.text.doubleValue;if(isfinite(v)&&v>0)[NSUserDefaults.standardUserDefaults setDouble:v forKey:ZN50BSliderKey(name)];else[NSUserDefaults.standardUserDefaults removeObjectForKey:ZN50BSliderKey(name)]; }
- (void)zn50b_deleteOffsetFeature:(UIButton *)sender { NSInteger index=sender.tag-kZN50BDeleteTagBase;if(index<0)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSArray *f=ZN50BFeatureGroups(w);if((NSUInteger)index>=f.count)return;NSString *error=nil;if(![w removeFeatureNamed:f[(NSUInteger)index][@"name"] error:&error])w.lastStatus=error?:@"删除失败";[self renderPage]; }
- (void)zn50b_runtimeTitleEnd:(UITextField *)field { NSInteger index=field.tag-kZN50BRuntimeTitleTagBase;if(index<0)return;[[ZNRuntimeActionStore sharedStore] updateTitle:field.text atIndex:(NSUInteger)index error:nil];[field resignFirstResponder]; }
- (void)zn50b_runtimeDescriptionEnd:(UITextField *)field { NSInteger index=field.tag-kZN50BRuntimeDescriptionTagBase;if(index<0)return;[[ZNRuntimeActionStore sharedStore] updateGroup:field.text atIndex:(NSUInteger)index error:nil];[field resignFirstResponder]; }
- (void)zn50b_runtimeDelete:(UIButton *)sender { NSInteger index=sender.tag-kZN50BRuntimeDeleteTagBase;if(index>=0)[[ZNRuntimeActionStore sharedStore] removeActionAtIndex:(NSUInteger)index];[self renderPage]; }
- (void)zn50b_runtimeCycleControl:(UIButton *)sender { NSInteger index=sender.tag-kZN50BRuntimeControlTagBase;if(index<0)return;NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if((NSUInteger)index>=actions.count)return;ZNRuntimeMethodAction *a=actions[(NSUInteger)index];if(a.argumentCount!=1)return;ZNRuntimeArgumentControlType current=ZN50BRuntimeControlType(a),next;switch(current){case ZNRuntimeArgumentControlTypeFixed:next=ZNRuntimeArgumentControlTypeNumber;break;case ZNRuntimeArgumentControlTypeNumber:next=ZNRuntimeArgumentControlTypeSlider;break;case ZNRuntimeArgumentControlTypeSlider:next=ZNRuntimeArgumentControlTypeSwitch;break;case ZNRuntimeArgumentControlTypeSwitch:next=ZNRuntimeArgumentControlTypeButton;break;default:next=ZNRuntimeArgumentControlTypeFixed;break;}NSMutableDictionary *cfg=[a.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@(next!=ZNRuntimeArgumentControlTypeFixed);cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(next);if(next==ZNRuntimeArgumentControlTypeSlider){double max=[cfg[@"max"] doubleValue];if(!isfinite(max)||max<=0||max>1000000)max=10;cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);[[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[[NSString stringWithFormat:@"%.0f",max]] atIndex:(NSUInteger)index error:nil];}[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)index error:nil];[self renderPage]; }
- (void)zn50b_runtimeMaxChanged:(UITextField *)field { NSInteger index=field.tag-kZN50BRuntimeMaxTagBase;if(index<0)return;NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if((NSUInteger)index>=actions.count)return;ZNRuntimeMethodAction *a=actions[(NSUInteger)index];if(a.argumentCount!=1)return;double max=field.text.doubleValue;if(!isfinite(max)||max<=0)return;NSMutableDictionary *cfg=[a.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@YES;cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(ZNRuntimeArgumentControlTypeSlider);cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)index error:nil];[[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[[NSString stringWithFormat:@"%.15g",max]] atIndex:(NSUInteger)index error:nil]; }
- (void)zn50b_buildUnified:(id)sender { ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];for(NSDictionary *f in ZN50BFeatureGroups(w)){ZNBinaryPatchRow *r=[f[@"rows"] firstObject];if(!r.offsetText.length){w.lastStatus=[NSString stringWithFormat:@"%@：必须填写 exact IL2CPP Method Offset",f[@"name"]?:@"功能"];[self renderPage];return;}if(r.featureControlType!=ZNFeatureControlTypeNumber&&r.featureControlType!=ZNFeatureControlTypeSlider){w.lastStatus=[NSString stringWithFormat:@"%@：旧 Static 记录只做兼容读取，不能作为新数值功能生成",f[@"name"]?:@"功能"];[self renderPage];return;}}NSString *error=nil;if(![w validateAll:&error]){w.lastStatus=[NSString stringWithFormat:@"解析准备失败：%@",error?:@"未知错误"];[self renderPage];return;}[self zn44_buildBinary:sender]; }

@end

static void ZN50BSwapInstanceMethod(Class cls, SEL original, SEL replacement) { Method a=class_getInstanceMethod(cls,original),b=class_getInstanceMethod(cls,replacement);if(a&&b)method_exchangeImplementations(a,b); }
extern "C" void ZNInstallFeatureBuilderUIDeferred(void) {
    @autoreleasepool { Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;ZN50BSwapInstanceMethod(cls,@selector(zn44_renderOther),@selector(zn50b_renderOther));[[ZNRuntimeLogger sharedLogger]log:@"[m6.3-authoring] single Builder renderer installed: name + description + exact Offset/Method; raw Patch/direct numeric UI removed"]; }
}
