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
// Exactly one renderer owns `其他`. No post-render overlays, no nested Builder.
// New Offset authoring = 功能名 + 说明 + exact IL2CPP Method Offset + Number/Slider.
// Raw ARM64/Enabled, multi-Patch authoring and ordinary Offset direct-number input
// are intentionally absent. Legacy Static records remain read-compatible only.

static NSString * const kM630SliderPrefix = @"zonoe.m5.8.5.static-slider-max.v1";
static const NSInteger kM630OffsetField = 441000;
static const NSInteger kM630OffsetName = 980000;
static const NSInteger kM630OffsetDesc = 981000;
static const NSInteger kM630OffsetControl = 982000;
static const NSInteger kM630OffsetMax = 983000;
static const NSInteger kM630OffsetDelete = 984000;
static const NSInteger kM630RuntimeName = 985000;
static const NSInteger kM630RuntimeDesc = 986000;
static const NSInteger kM630RuntimeControl = 987000;
static const NSInteger kM630RuntimeMax = 988000;
static const NSInteger kM630RuntimeDelete = 989000;

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

static NSString *M630Trim(NSString *s) {
    return [(s ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *M630Name(ZNBinaryPatchRow *row) {
    NSString *g=M630Trim(row.group);
    if(g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return g;
    NSString *t=M630Trim(row.title);
    return t.length?t:@"未命名功能";
}

static NSString *M630SliderKey(NSString *name) {
    return [NSString stringWithFormat:@"%@.%@",kM630SliderPrefix,M630Trim(name).lowercaseString];
}

static UITextField *M630Field(CGRect frame, ZNTheme *theme) {
    UITextField *f=[[UITextField alloc]initWithFrame:frame];
    f.textColor=theme.primaryTextColor; f.backgroundColor=theme.controlColor;
    f.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    f.returnKeyType=UIReturnKeyDone; f.clearButtonMode=UITextFieldViewModeWhileEditing;
    f.layer.cornerRadius=7; f.layer.borderWidth=1; f.layer.borderColor=theme.borderColor.CGColor;
    UIView *pad=[[UIView alloc]initWithFrame:CGRectMake(0,0,8,1)]; f.leftView=pad; f.leftViewMode=UITextFieldViewModeAlways;
    return f;
}

static NSArray<ZNBinaryPatchRow *> *M630Rows(void) {
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; [w ensureDefaultRows];
    NSMutableArray<ZNBinaryPatchRow *> *out=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in w.rows){
        BOOL meaningful=row.offsetText.length||row.enabledText.length||M630Trim(row.group).length||M630Trim(row.title).length;
        if(!meaningful)continue;
        NSString *name=M630Name(row); BOOL duplicate=NO;
        for(ZNBinaryPatchRow *old in out) if([M630Name(old) caseInsensitiveCompare:name]==NSOrderedSame){duplicate=YES;break;}
        if(!duplicate)[out addObject:row];
    }
    return [out copy];
}

static ZNRuntimeArgumentControlType M630RuntimeControl(ZNRuntimeMethodAction *a) {
    if(a.argumentCount!=1||a.argumentControlConfigs.count!=1)return ZNRuntimeArgumentControlTypeFixed;
    NSDictionary *cfg=a.argumentControlConfigs.firstObject;
    return [cfg[@"enabled"] boolValue]?ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]):ZNRuntimeArgumentControlTypeFixed;
}

static void M630Persist(void) {
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    [w updateDefaultTarget:w.defaultTarget];
}

@interface ZNRuntimeMenuControllerV040 (M630Authoring)
- (void)m630_renderOther;
- (void)m630_add:(id)sender;
- (void)m630_offsetName:(UITextField *)field;
- (void)m630_offsetDesc:(UITextField *)field;
- (void)m630_offsetControl:(UIButton *)sender;
- (void)m630_offsetMax:(UITextField *)field;
- (void)m630_offsetDelete:(UIButton *)sender;
- (void)m630_runtimeName:(UITextField *)field;
- (void)m630_runtimeDesc:(UITextField *)field;
- (void)m630_runtimeControl:(UIButton *)sender;
- (void)m630_runtimeMax:(UITextField *)field;
- (void)m630_runtimeDelete:(UIButton *)sender;
- (void)m630_build:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (M630Authoring)

- (void)m630_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds), y=9;
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; BOOL locked=w.isBuilding||w.hasAnyApplied;

    UIView *intro=[self cardAtY:y height:54 width:width compact:NO];
    UILabel *a=[self label:@"统一制作 · Offset 只解析 exact IL2CPP Method" size:9.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    a.frame=CGRectMake(13,7,intro.bounds.size.width-26,19); [intro addSubview:a];
    UILabel *b=[self label:@"不提供 Raw Patch / Enabled / 普通 Offset 直接数字" size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    b.frame=CGRectMake(13,29,intro.bounds.size.width-26,17); [intro addSubview:b]; [self.contentView addSubview:intro]; y+=62;

    NSArray<ZNBinaryPatchRow *> *rows=M630Rows();
    for(NSUInteger i=0;i<rows.count;i++){
        ZNBinaryPatchRow *row=rows[i]; NSString *name=M630Name(row);
        BOOL numeric=row.featureControlType==ZNFeatureControlTypeNumber||row.featureControlType==ZNFeatureControlTypeSlider;
        CGFloat h=row.featureControlType==ZNFeatureControlTypeSlider?170:132; UIView *card=[self cardAtY:y height:h width:width compact:NO];
        UILabel *l1=[self label:@"功能名" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; l1.frame=CGRectMake(13,7,42,29); [card addSubview:l1];
        UITextField *nameF=M630Field(CGRectMake(58,7,card.bounds.size.width-71,29),self.theme); nameF.tag=kM630OffsetName+(NSInteger)i; nameF.text=name; nameF.enabled=!locked; [nameF addTarget:self action:@selector(m630_offsetName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:nameF];
        UILabel *l2=[self label:@"说明" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; l2.frame=CGRectMake(13,42,42,29); [card addSubview:l2];
        UITextField *desc=M630Field(CGRectMake(58,42,card.bounds.size.width-71,29),self.theme); desc.tag=kM630OffsetDesc+(NSInteger)i; desc.text=([M630Trim(row.group) caseInsensitiveCompare:@"Imported"]==NSOrderedSame)?@"":M630Trim(row.title); desc.placeholder=@"显示给客户的说明"; desc.enabled=!locked; [desc addTarget:self action:@selector(m630_offsetDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:desc];
        UILabel *l3=[self label:@"Offset" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; l3.frame=CGRectMake(13,77,42,29); [card addSubview:l3];
        NSUInteger global=[w.rows indexOfObjectIdenticalTo:row]; UITextField *off=[self zn44_field:CGRectMake(58,77,card.bounds.size.width-71,29) text:row.offsetText placeholder:@"0x4FAEA98 · exact IL2CPP Method Offset" tag:kM630OffsetField+(NSInteger)global enabled:!locked&&numeric]; [card addSubview:off];
        UIButton *control=[self zn40_button:(numeric?(row.featureControlType==ZNFeatureControlTypeSlider?@"控件 · 滑块":@"控件 · 数值"):@"旧 Static · 只读") selector:@selector(m630_offsetControl:) frame:CGRectMake(13,112,card.bounds.size.width-82,29)]; control.tag=kM630OffsetControl+(NSInteger)i; control.enabled=!locked&&numeric; [card addSubview:control];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(m630_offsetDelete:) frame:CGRectMake(card.bounds.size.width-62,112,49,29)]; del.tag=kM630OffsetDelete+(NSInteger)i; del.enabled=!locked; [card addSubview:del];
        if(row.featureControlType==ZNFeatureControlTypeSlider){ UILabel *lm=[self label:@"Max" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor]; lm.frame=CGRectMake(13,147,42,29); [card addSubview:lm]; UITextField *mf=M630Field(CGRectMake(58,147,card.bounds.size.width-71,29),self.theme); mf.tag=kM630OffsetMax+(NSInteger)i; id stored=[NSUserDefaults.standardUserDefaults objectForKey:M630SliderKey(name)]; mf.text=[stored isKindOfClass:NSNumber.class]?[(NSNumber *)stored stringValue]:@""; mf.placeholder=@"例如 31"; mf.keyboardType=UIKeyboardTypeNumberPad; mf.enabled=!locked; [mf addTarget:self action:@selector(m630_offsetMax:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd]; [card addSubview:mf]; }
        [self.contentView addSubview:card]; y+=h+8;
    }

    UIView *add=[self cardAtY:y height:46 width:width compact:NO]; UIButton *addB=[self zn40_button:@"＋ 增加 Offset 功能" selector:@selector(m630_add:) frame:CGRectMake(13,7,add.bounds.size.width-26,32)]; addB.enabled=!locked; [add addSubview:addB]; [self.contentView addSubview:add]; y+=54;

    NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    UIView *rh=[self cardAtY:y height:40 width:width compact:NO]; UILabel *rhl=[self label:[NSString stringWithFormat:@"Runtime Method · %lu",(unsigned long)actions.count] size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; rhl.frame=CGRectMake(13,6,rh.bounds.size.width-26,28); [rh addSubview:rhl]; [self.contentView addSubview:rh]; y+=48;
    for(NSUInteger i=0;i<actions.count;i++){
        ZNRuntimeMethodAction *act=actions[i]; BOOL one=act.argumentCount==1; CGFloat h=one?151:112; UIView *card=[self cardAtY:y height:h width:width compact:NO];
        UITextField *nf=M630Field(CGRectMake(13,7,card.bounds.size.width-76,29),self.theme); nf.tag=kM630RuntimeName+(NSInteger)i; nf.text=act.title; nf.placeholder=act.methodName; [nf addTarget:self action:@selector(m630_runtimeName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:nf];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(m630_runtimeDelete:) frame:CGRectMake(card.bounds.size.width-58,7,45,29)]; del.tag=kM630RuntimeDelete+(NSInteger)i; [card addSubview:del];
        UITextField *df=M630Field(CGRectMake(13,42,card.bounds.size.width-26,29),self.theme); df.tag=kM630RuntimeDesc+(NSInteger)i; df.text=([act.group caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame)?@"":act.group; df.placeholder=@"说明（显示给客户）"; [df addTarget:self action:@selector(m630_runtimeDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit]; [card addSubview:df];
        UILabel *identity=[self label:act.canonicalIdentity size:7.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; identity.frame=CGRectMake(13,77,card.bounds.size.width-26,25); identity.numberOfLines=2; identity.lineBreakMode=NSLineBreakByTruncatingMiddle; [card addSubview:identity];
        if(one){ ZNRuntimeArgumentControlType ct=M630RuntimeControl(act); UIButton *cb=[self zn40_button:[NSString stringWithFormat:@"控件 · %@",ZNRuntimeArgumentControlTypeName(ct)] selector:@selector(m630_runtimeControl:) frame:CGRectMake(13,111,card.bounds.size.width*0.5-17,31)]; cb.tag=kM630RuntimeControl+(NSInteger)i; [card addSubview:cb]; if(ct==ZNRuntimeArgumentControlTypeSlider){ NSDictionary *cfg=act.argumentControlConfigs.firstObject; UITextField *mf=M630Field(CGRectMake(card.bounds.size.width*0.5+2,111,card.bounds.size.width*0.5-15,31),self.theme); mf.tag=kM630RuntimeMax+(NSInteger)i; mf.text=[cfg[@"max"] stringValue]; mf.placeholder=@"Max"; mf.keyboardType=UIKeyboardTypeNumberPad; [mf addTarget:self action:@selector(m630_runtimeMax:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd]; [card addSubview:mf]; } }
        [self.contentView addSubview:card]; y+=h+8;
    }

    UIView *buildCard=[self cardAtY:y height:52 width:width compact:NO]; UIButton *build=[self zn40_button:(w.isBuilding?@"正在生成…":@"解析并生成新二进制") selector:@selector(m630_build:) frame:CGRectMake(13,9,buildCard.bounds.size.width-26,34)]; build.enabled=!w.isBuilding&&!w.hasAnyApplied&&(rows.count||actions.count); [buildCard addSubview:build]; [self.contentView addSubview:buildCard]; y+=60;
    if(w.lastStatus.length){ UIView *status=[self cardAtY:y height:42 width:width compact:NO]; UILabel *sl=[self label:w.lastStatus size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; sl.frame=CGRectMake(13,6,status.bounds.size.width-26,30); sl.numberOfLines=2; [status addSubview:sl]; [self.contentView addSubview:status]; y+=50; }
    [self zn40_updateContentHeight:y];
}

- (void)m630_add:(id)sender { (void)sender; ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; if(w.isBuilding||w.hasAnyApplied)return; NSUInteger n=1; NSMutableSet *used=[NSMutableSet set]; for(ZNBinaryPatchRow *r in w.rows)[used addObject:M630Name(r).lowercaseString]; NSString *name=nil; do{name=[NSString stringWithFormat:@"新功能 %lu",(unsigned long)n++];}while([used containsObject:name.lowercaseString]); ZNBinaryPatchRow *r=[ZNBinaryPatchRow new]; r.group=name; r.title=@""; r.statusText=@"待填写 exact Offset"; r.featureControlType=ZNFeatureControlTypeNumber; [w.rows addObject:r]; M630Persist(); w.lastStatus=[NSString stringWithFormat:@"已增加：%@",name]; [self renderPage]; }
- (void)m630_offsetName:(UITextField *)field { NSInteger i=field.tag-kM630OffsetName; NSArray<ZNBinaryPatchRow *> *rows=M630Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; NSString *name=M630Trim(field.text); if(!name.length){field.text=M630Name(r);return;} NSString *old=M630Name(r); id m=[NSUserDefaults.standardUserDefaults objectForKey:M630SliderKey(old)]; r.group=name; if(m){[NSUserDefaults.standardUserDefaults setObject:m forKey:M630SliderKey(name)];[NSUserDefaults.standardUserDefaults removeObjectForKey:M630SliderKey(old)];} M630Persist(); [field resignFirstResponder]; }
- (void)m630_offsetDesc:(UITextField *)field { NSInteger i=field.tag-kM630OffsetDesc; NSArray<ZNBinaryPatchRow *> *rows=M630Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; r.title=M630Trim(field.text); M630Persist(); [field resignFirstResponder]; }
- (void)m630_offsetControl:(UIButton *)sender { NSInteger i=sender.tag-kM630OffsetControl; NSArray<ZNBinaryPatchRow *> *rows=M630Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; if(r.featureControlType!=ZNFeatureControlTypeNumber&&r.featureControlType!=ZNFeatureControlTypeSlider)return; r.featureControlType=r.featureControlType==ZNFeatureControlTypeNumber?ZNFeatureControlTypeSlider:ZNFeatureControlTypeNumber; r.validated=NO; r.validator=nil; M630Persist(); [self renderPage]; }
- (void)m630_offsetMax:(UITextField *)field { NSInteger i=field.tag-kM630OffsetMax; NSArray<ZNBinaryPatchRow *> *rows=M630Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchRow *r=rows[(NSUInteger)i]; double max=field.text.doubleValue; NSString *key=M630SliderKey(M630Name(r)); if(isfinite(max)&&max>0)[NSUserDefaults.standardUserDefaults setDouble:max forKey:key]; else[NSUserDefaults.standardUserDefaults removeObjectForKey:key]; r.validated=NO; r.validator=nil; }
- (void)m630_offsetDelete:(UIButton *)sender { NSInteger i=sender.tag-kM630OffsetDelete; NSArray<ZNBinaryPatchRow *> *rows=M630Rows(); if(i<0||(NSUInteger)i>=rows.count)return; ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; NSString *name=M630Name(rows[(NSUInteger)i]); NSIndexSet *set=[w.rows indexesOfObjectsPassingTest:^BOOL(ZNBinaryPatchRow *r,NSUInteger idx,BOOL *stop){(void)idx;(void)stop;return [M630Name(r) caseInsensitiveCompare:name]==NSOrderedSame;}]; [w.rows removeObjectsAtIndexes:set]; [NSUserDefaults.standardUserDefaults removeObjectForKey:M630SliderKey(name)]; [w ensureDefaultRows]; M630Persist(); [self renderPage]; }
- (void)m630_runtimeName:(UITextField *)field { NSInteger i=field.tag-kM630RuntimeName; if(i>=0)[[ZNRuntimeActionStore sharedStore]updateTitle:field.text atIndex:(NSUInteger)i error:nil]; [field resignFirstResponder]; }
- (void)m630_runtimeDesc:(UITextField *)field { NSInteger i=field.tag-kM630RuntimeDesc; if(i>=0)[[ZNRuntimeActionStore sharedStore]updateGroup:field.text atIndex:(NSUInteger)i error:nil]; [field resignFirstResponder]; }
- (void)m630_runtimeControl:(UIButton *)sender { NSInteger i=sender.tag-kM630RuntimeControl; NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore]actionsSnapshot]; if(i<0||(NSUInteger)i>=actions.count)return; ZNRuntimeMethodAction *a=actions[(NSUInteger)i]; if(a.argumentCount!=1)return; ZNRuntimeArgumentControlType c=M630RuntimeControl(a),n=ZNRuntimeArgumentControlTypeFixed; switch(c){case ZNRuntimeArgumentControlTypeFixed:n=ZNRuntimeArgumentControlTypeNumber;break;case ZNRuntimeArgumentControlTypeNumber:n=ZNRuntimeArgumentControlTypeSlider;break;case ZNRuntimeArgumentControlTypeSlider:n=ZNRuntimeArgumentControlTypeSwitch;break;case ZNRuntimeArgumentControlTypeSwitch:n=ZNRuntimeArgumentControlTypeButton;break;default:n=ZNRuntimeArgumentControlTypeFixed;break;} NSMutableDictionary *cfg=[a.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary]; cfg[@"enabled"]=@(n!=ZNRuntimeArgumentControlTypeFixed); cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(n); if(n==ZNRuntimeArgumentControlTypeSlider){double max=[cfg[@"max"]doubleValue];if(!isfinite(max)||max<=0||max>1000000)max=10;cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[[NSString stringWithFormat:@"%.0f",max]] atIndex:(NSUInteger)i error:nil];} [[ZNRuntimeActionStore sharedStore]updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)i error:nil]; [self renderPage]; }
- (void)m630_runtimeMax:(UITextField *)field { NSInteger i=field.tag-kM630RuntimeMax; NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore]actionsSnapshot]; if(i<0||(NSUInteger)i>=actions.count)return; ZNRuntimeMethodAction *a=actions[(NSUInteger)i]; if(a.argumentCount!=1)return; double max=field.text.doubleValue;if(!isfinite(max)||max<=0)return; NSMutableDictionary *cfg=[a.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@YES;cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(ZNRuntimeArgumentControlTypeSlider);cfg[@"min"]=@0;cfg[@"max"]=@(max);cfg[@"step"]=@1;cfg[@"default"]=@(max);[[ZNRuntimeActionStore sharedStore]updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)i error:nil];[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[[NSString stringWithFormat:@"%.15g",max]] atIndex:(NSUInteger)i error:nil]; }
- (void)m630_runtimeDelete:(UIButton *)sender { NSInteger i=sender.tag-kM630RuntimeDelete;if(i>=0)[[ZNRuntimeActionStore sharedStore]removeActionAtIndex:(NSUInteger)i];[self renderPage]; }
- (void)m630_build:(id)sender { ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace]; for(ZNBinaryPatchRow *r in M630Rows()){ if(!r.offsetText.length){w.lastStatus=[NSString stringWithFormat:@"%@：必须填写 exact IL2CPP Method Offset",M630Name(r)];[self renderPage];return;} if(r.featureControlType!=ZNFeatureControlTypeNumber&&r.featureControlType!=ZNFeatureControlTypeSlider){w.lastStatus=[NSString stringWithFormat:@"%@：旧 Static 仅兼容读取，不能新生成",M630Name(r)];[self renderPage];return;} if(r.featureControlType==ZNFeatureControlTypeSlider){id m=[NSUserDefaults.standardUserDefaults objectForKey:M630SliderKey(M630Name(r))];if(![m isKindOfClass:NSNumber.class]||[(NSNumber *)m doubleValue]<=0){w.lastStatus=[NSString stringWithFormat:@"%@：Slider Max 必须大于 0",M630Name(r)];[self renderPage];return;}} } NSString *error=nil;if(![w validateAll:&error]){w.lastStatus=[NSString stringWithFormat:@"解析准备失败：%@",error?:@"未知错误"];[self renderPage];return;} [self zn44_buildBinary:sender]; }
@end

static void M630Swap(Class cls,SEL oldSel,SEL newSel){Method a=class_getInstanceMethod(cls,oldSel),b=class_getInstanceMethod(cls,newSel);if(a&&b)method_exchangeImplementations(a,b);}
extern "C" void ZNInstallFeatureBuilderUIDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;M630Swap(cls,@selector(zn44_renderOther),@selector(m630_renderOther));[[ZNRuntimeLogger sharedLogger]log:@"[m6.3-authoring] single Builder renderer installed; raw/direct-value UI removed"];});}
