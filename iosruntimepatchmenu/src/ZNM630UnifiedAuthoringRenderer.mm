#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M6.4 canonical authoring renderer.
// Exactly one renderer owns `其他`. No post-render overlays, no nested Builder.
// Offset is an exact IL2CPP method address source; Raw ARM64/Enabled/direct-value
// Static authoring stays disabled. Legacy Static rows remain removable/read-only.

static NSString * const kM640SliderPrefix  = @"zonoe.m5.8.5.static-slider-max.v1";
static NSString * const kM640ControlPrefix = @"zonoe.m6.4.offset-control.v1";
static NSString * const kM640ValuePrefix   = @"zonoe.m6.4.offset-fixed-value.v1";
static const NSInteger kM640Target          = 440000;
static const NSInteger kM640OffsetField     = 441000;
static const NSInteger kM640OffsetName      = 980000;
static const NSInteger kM640OffsetDesc      = 981000;
static const NSInteger kM640OffsetControl   = 982000;
static const NSInteger kM640OffsetAux       = 983000;
static const NSInteger kM640OffsetDelete    = 984000;
static const NSInteger kM640RuntimeName     = 985000;
static const NSInteger kM640RuntimeDesc     = 986000;
static const NSInteger kM640RuntimeControl  = 987000;
static const NSInteger kM640RuntimeAux      = 988000;
static const NSInteger kM640RuntimeDelete   = 989000;

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

static NSString *M640Trim(NSString *s) {
    return [(s ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *M640Name(ZNBinaryPatchRow *row) {
    NSString *g=M640Trim(row.group);
    if(g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return g;
    NSString *t=M640Trim(row.title);
    return t.length?t:@"未命名功能";
}

static NSString *M640Key(NSString *prefix, NSString *name) {
    return [NSString stringWithFormat:@"%@.%@",prefix,M640Trim(name).lowercaseString];
}

static BOOL M640PlaceholderRow(ZNBinaryPatchRow *row) {
    NSString *g=M640Trim(row.group), *t=M640Trim(row.title);
    BOOL placeholderGroup=!g.length || [g caseInsensitiveCompare:@"Imported"]==NSOrderedSame;
    return !row.offsetText.length && !row.enabledText.length && !t.length && placeholderGroup;
}

static BOOL M640LegacyStatic(ZNBinaryPatchRow *row) {
    return row.enabledText.length > 0;
}

static NSArray<ZNBinaryPatchRow *> *M640Rows(void) {
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    [w ensureDefaultRows];
    NSMutableArray<ZNBinaryPatchRow *> *out=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in w.rows){
        if(M640PlaceholderRow(row)) continue;
        NSString *name=M640Name(row); BOOL duplicate=NO;
        for(ZNBinaryPatchRow *old in out){
            if([M640Name(old) caseInsensitiveCompare:name]==NSOrderedSame){duplicate=YES;break;}
        }
        if(!duplicate)[out addObject:row];
    }
    return [out copy];
}

static ZNRuntimeArgumentControlType M640OffsetControl(ZNBinaryPatchRow *row) {
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:M640Key(kM640ControlPrefix,M640Name(row))];
    if(saved.length) return ZNRuntimeArgumentControlTypeFromKey(saved);
    switch(row.featureControlType){
        case ZNFeatureControlTypeSlider:return ZNRuntimeArgumentControlTypeSlider;
        case ZNFeatureControlTypeSwitch:return ZNRuntimeArgumentControlTypeSwitch;
        case ZNFeatureControlTypeButton:return ZNRuntimeArgumentControlTypeButton;
        case ZNFeatureControlTypeNumber:return ZNRuntimeArgumentControlTypeNumber;
    }
    return ZNRuntimeArgumentControlTypeNumber;
}

static void M640StoreOffsetControl(ZNBinaryPatchRow *row, ZNRuntimeArgumentControlType type) {
    [NSUserDefaults.standardUserDefaults setObject:ZNRuntimeArgumentControlTypeKey(type)
                                            forKey:M640Key(kM640ControlPrefix,M640Name(row))];
    switch(type){
        case ZNRuntimeArgumentControlTypeSlider: row.featureControlType=ZNFeatureControlTypeSlider; break;
        case ZNRuntimeArgumentControlTypeSwitch: row.featureControlType=ZNFeatureControlTypeSwitch; break;
        case ZNRuntimeArgumentControlTypeButton: row.featureControlType=ZNFeatureControlTypeButton; break;
        default: row.featureControlType=ZNFeatureControlTypeNumber; break;
    }
}

static ZNRuntimeArgumentControlType M640NextControl(ZNRuntimeArgumentControlType c) {
    switch(c){
        case ZNRuntimeArgumentControlTypeFixed:return ZNRuntimeArgumentControlTypeNumber;
        case ZNRuntimeArgumentControlTypeNumber:return ZNRuntimeArgumentControlTypeSlider;
        case ZNRuntimeArgumentControlTypeSlider:return ZNRuntimeArgumentControlTypeSwitch;
        case ZNRuntimeArgumentControlTypeSwitch:return ZNRuntimeArgumentControlTypeButton;
        default:return ZNRuntimeArgumentControlTypeFixed;
    }
}

static ZNRuntimeArgumentControlType M640RuntimeControl(ZNRuntimeMethodAction *a) {
    if(a.argumentCount!=1 || a.argumentControlConfigs.count!=1) return ZNRuntimeArgumentControlTypeFixed;
    NSDictionary *cfg=a.argumentControlConfigs.firstObject;
    return [cfg[@"enabled"] boolValue]?ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]):ZNRuntimeArgumentControlTypeFixed;
}

static UITextField *M640Field(CGRect frame, ZNTheme *theme) {
    UITextField *f=[[UITextField alloc]initWithFrame:frame];
    f.textColor=theme.primaryTextColor; f.backgroundColor=theme.controlColor;
    f.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    f.returnKeyType=UIReturnKeyDone; f.clearButtonMode=UITextFieldViewModeWhileEditing;
    f.layer.cornerRadius=7; f.layer.borderWidth=1; f.layer.borderColor=theme.borderColor.CGColor;
    UIView *pad=[[UIView alloc]initWithFrame:CGRectMake(0,0,8,1)]; f.leftView=pad; f.leftViewMode=UITextFieldViewModeAlways;
    return f;
}

static void M640Persist(void) {
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    [w updateDefaultTarget:w.defaultTarget];
}

@interface ZNRuntimeMenuControllerV040 (M640Authoring)
- (void)m640_renderOther;
- (void)m640_target:(UITextField *)field;
- (void)m640_add:(id)sender;
- (void)m640_offsetName:(UITextField *)field;
- (void)m640_offsetDesc:(UITextField *)field;
- (void)m640_offsetControl:(UIButton *)sender;
- (void)m640_offsetAux:(UITextField *)field;
- (void)m640_offsetDelete:(UIButton *)sender;
- (void)m640_runtimeName:(UITextField *)field;
- (void)m640_runtimeDesc:(UITextField *)field;
- (void)m640_runtimeControl:(UIButton *)sender;
- (void)m640_runtimeAux:(UITextField *)field;
- (void)m640_runtimeDelete:(UIButton *)sender;
- (void)m640_build:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (M640Authoring)

- (void)m640_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds), y=9;
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    BOOL locked=w.isBuilding||w.hasAnyApplied;

    UIView *targetCard=[self cardAtY:y height:56 width:width compact:NO];
    UILabel *binary=[self label:@"二进制" size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    binary.frame=CGRectMake(13,11,48,32); [targetCard addSubview:binary];
    UITextField *target=M640Field(CGRectMake(65,11,targetCard.bounds.size.width-78,32),self.theme);
    target.tag=kM640Target; target.text=w.defaultTarget; target.placeholder=@"UnityFramework"; target.enabled=!locked;
    [target addTarget:self action:@selector(m640_target:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
    [targetCard addSubview:target]; [self.contentView addSubview:targetCard]; y+=64;

    UIView *intro=[self cardAtY:y height:54 width:width compact:NO];
    UILabel *a=[self label:@"统一制作 · Offset 只解析 exact IL2CPP Method" size:9.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    a.frame=CGRectMake(13,7,intro.bounds.size.width-26,19); [intro addSubview:a];
    UILabel *b=[self label:@"单 Renderer · 无 Raw Patch / Enabled / 普通 Offset 直接数值" size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    b.frame=CGRectMake(13,29,intro.bounds.size.width-26,17); [intro addSubview:b]; [self.contentView addSubview:intro]; y+=62;

    NSArray<ZNBinaryPatchRow *> *rows=M640Rows();
    for(NSUInteger i=0;i<rows.count;i++){
        ZNBinaryPatchRow *row=rows[i]; NSString *name=M640Name(row); BOOL legacy=M640LegacyStatic(row);
        ZNRuntimeArgumentControlType ct=M640OffsetControl(row);
        BOOL needsAux=!legacy && (ct==ZNRuntimeArgumentControlTypeSlider||ct==ZNRuntimeArgumentControlTypeFixed||ct==ZNRuntimeArgumentControlTypeButton);
        CGFloat h=needsAux?170:132;
        UIView *card=[self cardAtY:y height:h width:width compact:NO];

        UILabel *l1=[self label:@"功能名" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; l1.frame=CGRectMake(13,7,42,29); [card addSubview:l1];
        UITextField *nameF=M640Field(CGRectMake(58,7,card.bounds.size.width-71,29),self.theme); nameF.tag=kM640OffsetName+(NSInteger)i; nameF.text=name; nameF.enabled=!locked&&!legacy; [nameF addTarget:self action:@selector(m640_offsetName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:nameF];

        UILabel *l2=[self label:@"说明" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; l2.frame=CGRectMake(13,42,42,29); [card addSubview:l2];
        UITextField *desc=M640Field(CGRectMake(58,42,card.bounds.size.width-71,29),self.theme); desc.tag=kM640OffsetDesc+(NSInteger)i; desc.text=([M640Trim(row.group) caseInsensitiveCompare:@"Imported"]==NSOrderedSame)?@"":M640Trim(row.title); desc.placeholder=@"显示给客户的说明"; desc.enabled=!locked&&!legacy; [desc addTarget:self action:@selector(m640_offsetDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:desc];

        UILabel *l3=[self label:@"Offset" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; l3.frame=CGRectMake(13,77,42,29); [card addSubview:l3];
        NSUInteger global=[w.rows indexOfObjectIdenticalTo:row];
        UITextField *off=[self zn44_field:CGRectMake(58,77,card.bounds.size.width-71,29) text:row.offsetText placeholder:@"0x4FAEA98 · exact IL2CPP Method Offset" tag:kM640OffsetField+(NSInteger)global enabled:!locked&&!legacy]; [card addSubview:off];

        NSString *controlTitle=legacy?@"旧 Static · 只读":[NSString stringWithFormat:@"控件 · %@",ZNRuntimeArgumentControlTypeName(ct)];
        UIButton *control=[self zn40_button:controlTitle selector:@selector(m640_offsetControl:) frame:CGRectMake(13,112,card.bounds.size.width-82,29)]; control.tag=kM640OffsetControl+(NSInteger)i; control.enabled=!locked&&!legacy; [card addSubview:control];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(m640_offsetDelete:) frame:CGRectMake(card.bounds.size.width-62,112,49,29)]; del.tag=kM640OffsetDelete+(NSInteger)i; del.enabled=!locked; [card addSubview:del];

        if(needsAux){
            UILabel *la=[self label:(ct==ZNRuntimeArgumentControlTypeSlider?@"Max":@"Value") size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; la.frame=CGRectMake(13,147,42,29); [card addSubview:la];
            UITextField *aux=M640Field(CGRectMake(58,147,card.bounds.size.width-71,29),self.theme); aux.tag=kM640OffsetAux+(NSInteger)i; aux.keyboardType=UIKeyboardTypeNumbersAndPunctuation; aux.enabled=!locked;
            if(ct==ZNRuntimeArgumentControlTypeSlider){ id v=[NSUserDefaults.standardUserDefaults objectForKey:M640Key(kM640SliderPrefix,name)]; aux.text=[v isKindOfClass:NSNumber.class]?[(NSNumber *)v stringValue]:@""; aux.placeholder=@"例如 31"; }
            else { aux.text=[NSUserDefaults.standardUserDefaults stringForKey:M640Key(kM640ValuePrefix,name)]?:@""; aux.placeholder=@"例如 10000"; }
            [aux addTarget:self action:@selector(m640_offsetAux:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:aux];
        }
        [self.contentView addSubview:card]; y+=h+8;
    }

    UIView *add=[self cardAtY:y height:46 width:width compact:NO];
    UIButton *addB=[self zn40_button:@"＋ 增加 Offset 功能" selector:@selector(m640_add:) frame:CGRectMake(13,7,add.bounds.size.width-26,32)]; addB.enabled=!locked; [add addSubview:addB]; [self.contentView addSubview:add]; y+=54;

    NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    UIView *rh=[self cardAtY:y height:40 width:width compact:NO];
    UILabel *rhl=[self label:[NSString stringWithFormat:@"Runtime Method · %lu",(unsigned long)actions.count] size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; rhl.frame=CGRectMake(13,6,rh.bounds.size.width-26,28); [rh addSubview:rhl]; [self.contentView addSubview:rh]; y+=48;

    for(NSUInteger i=0;i<actions.count;i++){
        ZNRuntimeMethodAction *act=actions[i]; BOOL one=act.argumentCount==1; ZNRuntimeArgumentControlType ct=M640RuntimeControl(act);
        CGFloat h=one?151:112; UIView *card=[self cardAtY:y height:h width:width compact:NO];
        UITextField *nf=M640Field(CGRectMake(13,7,card.bounds.size.width-76,29),self.theme); nf.tag=kM640RuntimeName+(NSInteger)i; nf.text=act.title; nf.placeholder=act.methodName; [nf addTarget:self action:@selector(m640_runtimeName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:nf];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(m640_runtimeDelete:) frame:CGRectMake(card.bounds.size.width-58,7,45,29)]; del.tag=kM640RuntimeDelete+(NSInteger)i; [card addSubview:del];
        UITextField *df=M640Field(CGRectMake(13,42,card.bounds.size.width-26,29),self.theme); df.tag=kM640RuntimeDesc+(NSInteger)i; df.text=([act.group caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame)?@"":act.group; df.placeholder=@"说明（显示给客户）"; [df addTarget:self action:@selector(m640_runtimeDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:df];
        UILabel *identity=[self label:act.canonicalIdentity size:7.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; identity.frame=CGRectMake(13,77,card.bounds.size.width-26,25); identity.numberOfLines=2; identity.lineBreakMode=NSLineBreakByTruncatingMiddle; [card addSubview:identity];
        if(one){
            UIButton *cb=[self zn40_button:[NSString stringWithFormat:@"控件 · %@",ZNRuntimeArgumentControlTypeName(ct)] selector:@selector(m640_runtimeControl:) frame:CGRectMake(13,111,card.bounds.size.width*0.5-17,31)]; cb.tag=kM640RuntimeControl+(NSInteger)i; [card addSubview:cb];
            if(ct==ZNRuntimeArgumentControlTypeSlider||ct==ZNRuntimeArgumentControlTypeFixed||ct==ZNRuntimeArgumentControlTypeButton){
                UITextField *aux=M640Field(CGRectMake(card.bounds.size.width*0.5+2,111,card.bounds.size.width*0.5-15,31),self.theme); aux.tag=kM640RuntimeAux+(NSInteger)i; aux.keyboardType=UIKeyboardTypeNumbersAndPunctuation;
                if(ct==ZNRuntimeArgumentControlTypeSlider){ NSDictionary *cfg=act.argumentControlConfigs.firstObject; aux.text=[cfg[@"max"] stringValue]; aux.placeholder=@"Max"; }
                else { aux.text=act.argumentValues.count?act.argumentValues.firstObject:@""; aux.placeholder=@"Value"; }
                [aux addTarget:self action:@selector(m640_runtimeAux:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:aux];
            }
        }
        [self.contentView addSubview:card]; y+=h+8;
    }

    UIView *buildCard=[self cardAtY:y height:52 width:width compact:NO];
    UIButton *build=[self zn40_button:(w.isBuilding?@"正在生成…":@"解析并生成新二进制") selector:@selector(m640_build:) frame:CGRectMake(13,9,buildCard.bounds.size.width-26,34)]; build.enabled=!w.isBuilding&&!w.hasAnyApplied&&(rows.count||actions.count); [buildCard addSubview:build]; [self.contentView addSubview:buildCard]; y+=60;
    if(w.lastStatus.length){ UIView *status=[self cardAtY:y height:42 width:width compact:NO]; UILabel *sl=[self label:w.lastStatus size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; sl.frame=CGRectMake(13,6,status.bounds.size.width-26,30); sl.numberOfLines=2; [status addSubview:sl]; [self.contentView addSubview:status]; y+=50; }
    [self zn40_updateContentHeight:y];
}

- (void)m640_target:(UITextField *)field {
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; NSString *target=M640Trim(field.text); if(!target.length)target=@"UnityFramework"; [w updateDefaultTarget:target];
    for(ZNBinaryPatchRow *r in w.rows){ if(!M640LegacyStatic(r)&&!M640PlaceholderRow(r)){ r.target=target; r.explicitTarget=YES; r.validated=NO; r.validator=nil; } }
    field.text=w.defaultTarget; [field resignFirstResponder];
}

- (void)m640_add:(id)sender { (void)sender; ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; if(w.isBuilding||w.hasAnyApplied)return; NSUInteger n=1; NSMutableSet *used=[NSMutableSet set]; for(ZNBinaryPatchRow *r in M640Rows())[used addObject:M640Name(r).lowercaseString]; NSString *name=nil; do{name=[NSString stringWithFormat:@"新功能 %lu",(unsigned long)n++];}while([used containsObject:name.lowercaseString]); ZNBinaryPatchRow *r=[ZNBinaryPatchRow new]; r.group=name; r.title=@""; r.target=w.defaultTarget; r.explicitTarget=YES; r.statusText=@"待填写 exact Offset"; r.featureControlType=ZNFeatureControlTypeNumber; [w.rows addObject:r]; M640StoreOffsetControl(r,ZNRuntimeArgumentControlTypeNumber); M640Persist(); w.lastStatus=[NSString stringWithFormat:@"已增加：%@",name]; [self renderPage]; }

- (void)m640_offsetName:(UITextField *)field { NSInteger i=field.tag-kM640OffsetName; NSArray *rows=M640Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; NSString *old=M640Name(r),*name=M640Trim(field.text); if(!name.length){field.text=old;return;} NSArray *prefixes=@[kM640SliderPrefix,kM640ControlPrefix,kM640ValuePrefix]; for(NSString *p in prefixes){NSString *ok=M640Key(p,old),*nk=M640Key(p,name);id value=[NSUserDefaults.standardUserDefaults objectForKey:ok];if(value){[NSUserDefaults.standardUserDefaults setObject:value forKey:nk];[NSUserDefaults.standardUserDefaults removeObjectForKey:ok];}} r.group=name; M640Persist(); [field resignFirstResponder]; }
- (void)m640_offsetDesc:(UITextField *)field { NSInteger i=field.tag-kM640OffsetDesc; NSArray *rows=M640Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; r.title=M640Trim(field.text); M640Persist(); [field resignFirstResponder]; }
- (void)m640_offsetControl:(UIButton *)sender { NSInteger i=sender.tag-kM640OffsetControl; NSArray *rows=M640Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; if(M640LegacyStatic(r))return; M640StoreOffsetControl(r,M640NextControl(M640OffsetControl(r))); r.validated=NO;r.validator=nil;M640Persist();[self renderPage]; }
- (void)m640_offsetAux:(UITextField *)field { NSInteger i=field.tag-kM640OffsetAux; NSArray *rows=M640Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; ZNRuntimeArgumentControlType ct=M640OffsetControl(r); NSString *name=M640Name(r); if(ct==ZNRuntimeArgumentControlTypeSlider){double max=field.text.doubleValue;NSString *key=M640Key(kM640SliderPrefix,name);if(isfinite(max)&&max>0)[NSUserDefaults.standardUserDefaults setDouble:max forKey:key];else[NSUserDefaults.standardUserDefaults removeObjectForKey:key];}else{NSString *key=M640Key(kM640ValuePrefix,name);NSString *v=M640Trim(field.text);if(v.length)[NSUserDefaults.standardUserDefaults setObject:v forKey:key];else[NSUserDefaults.standardUserDefaults removeObjectForKey:key];} r.validated=NO;r.validator=nil; }
- (void)m640_offsetDelete:(UIButton *)sender { NSInteger i=sender.tag-kM640OffsetDelete; NSArray *rows=M640Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; ZNBinaryPatchRow *victim=rows[(NSUInteger)i]; NSString *name=M640Name(victim); NSIndexSet *set=[w.rows indexesOfObjectsPassingTest:^BOOL(ZNBinaryPatchRow *r,NSUInteger idx,BOOL *stop){(void)idx;(void)stop;return r==victim || [M640Name(r) caseInsensitiveCompare:name]==NSOrderedSame;}]; [w.rows removeObjectsAtIndexes:set]; for(NSString *p in @[kM640SliderPrefix,kM640ControlPrefix,kM640ValuePrefix])[NSUserDefaults.standardUserDefaults removeObjectForKey:M640Key(p,name)]; [w ensureDefaultRows]; M640Persist(); [self renderPage]; }

- (void)m640_runtimeName:(UITextField *)field { NSInteger i=field.tag-kM640RuntimeName; if(i>=0)[[ZNRuntimeActionStore sharedStore]updateTitle:field.text atIndex:(NSUInteger)i error:nil]; [field resignFirstResponder]; }
- (void)m640_runtimeDesc:(UITextField *)field { NSInteger i=field.tag-kM640RuntimeDesc; if(i>=0)[[ZNRuntimeActionStore sharedStore]updateGroup:field.text atIndex:(NSUInteger)i error:nil]; [field resignFirstResponder]; }
- (void)m640_runtimeControl:(UIButton *)sender { NSInteger i=sender.tag-kM640RuntimeControl; NSArray *actions=[[ZNRuntimeActionStore sharedStore]actionsSnapshot]; if(i<0||(NSUInteger)i>=actions.count)return; ZNRuntimeMethodAction *a=actions[(NSUInteger)i]; if(a.argumentCount!=1)return; ZNRuntimeArgumentControlType n=M640NextControl(M640RuntimeControl(a)); NSMutableDictionary *cfg=[a.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary]; cfg[@"enabled"]=@(n!=ZNRuntimeArgumentControlTypeFixed);cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(n);if(n==ZNRuntimeArgumentControlTypeSlider){double max=[cfg[@"max"]doubleValue];if(!isfinite(max)||max<=0)max=10;cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[[NSString stringWithFormat:@"%.15g",max]] atIndex:(NSUInteger)i error:nil];}[[ZNRuntimeActionStore sharedStore]updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)i error:nil];[self renderPage]; }
- (void)m640_runtimeAux:(UITextField *)field { NSInteger i=field.tag-kM640RuntimeAux; NSArray *actions=[[ZNRuntimeActionStore sharedStore]actionsSnapshot]; if(i<0||(NSUInteger)i>=actions.count)return; ZNRuntimeMethodAction *a=actions[(NSUInteger)i]; if(a.argumentCount!=1)return; ZNRuntimeArgumentControlType ct=M640RuntimeControl(a); if(ct==ZNRuntimeArgumentControlTypeSlider){double max=field.text.doubleValue;if(!isfinite(max)||max<=0)return;NSMutableDictionary *cfg=[a.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@YES;cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(ZNRuntimeArgumentControlTypeSlider);cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);[[ZNRuntimeActionStore sharedStore]updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)i error:nil];[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[[NSString stringWithFormat:@"%.15g",max]] atIndex:(NSUInteger)i error:nil];}else if(ct==ZNRuntimeArgumentControlTypeFixed||ct==ZNRuntimeArgumentControlTypeButton){[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[M640Trim(field.text)] atIndex:(NSUInteger)i error:nil];} }
- (void)m640_runtimeDelete:(UIButton *)sender { NSInteger i=sender.tag-kM640RuntimeDelete;if(i>=0)[[ZNRuntimeActionStore sharedStore]removeActionAtIndex:(NSUInteger)i];[self renderPage]; }

- (void)m640_build:(id)sender { ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; for(ZNBinaryPatchRow *r in M640Rows()){ if(M640LegacyStatic(r))continue; if(!r.offsetText.length){w.lastStatus=[NSString stringWithFormat:@"%@：必须填写 exact IL2CPP Method Offset",M640Name(r)];[self renderPage];return;} ZNRuntimeArgumentControlType ct=M640OffsetControl(r); if(ct==ZNRuntimeArgumentControlTypeSlider){id m=[NSUserDefaults.standardUserDefaults objectForKey:M640Key(kM640SliderPrefix,M640Name(r))];if(![m isKindOfClass:NSNumber.class]||[(NSNumber *)m doubleValue]<=0){w.lastStatus=[NSString stringWithFormat:@"%@：Slider Max 必须大于 0",M640Name(r)];[self renderPage];return;}} if((ct==ZNRuntimeArgumentControlTypeFixed||ct==ZNRuntimeArgumentControlTypeButton)&&![[NSUserDefaults.standardUserDefaults stringForKey:M640Key(kM640ValuePrefix,M640Name(r))] length]){w.lastStatus=[NSString stringWithFormat:@"%@：%@ Value 不能为空",M640Name(r),ZNRuntimeArgumentControlTypeName(ct)];[self renderPage];return;} } NSString *error=nil;if(![w validateAll:&error]){w.lastStatus=[NSString stringWithFormat:@"解析准备失败：%@",error?:@"未知错误"];[self renderPage];return;}[self zn44_buildBinary:sender]; }
@end

static void M640Swap(Class cls,SEL oldSel,SEL newSel){Method a=class_getInstanceMethod(cls,oldSel),b=class_getInstanceMethod(cls,newSel);if(a&&b)method_exchangeImplementations(a,b);}
extern "C" void ZNInstallFeatureBuilderUIDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;M640Swap(cls,@selector(zn44_renderOther),@selector(m640_renderOther));[[ZNRuntimeLogger sharedLogger]log:@"[m6.4-authoring] single Builder renderer installed; binary target restored; phantom rows filtered; Fixed Value restored"];});}
