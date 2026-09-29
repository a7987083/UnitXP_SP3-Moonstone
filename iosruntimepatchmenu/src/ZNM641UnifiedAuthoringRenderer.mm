#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M6.4.1 canonical authoring renderer.
// Exactly one Builder renderer owns `其他`.
// UI is split into two simple sections inside this single renderer:
//   1) 普通 Patch: 名称 + 说明 + Offset + Patch
//   2) Runtime / IL2CPP: 名称 + 说明 + Offset + 控件 + Value/Max
// No nested renderer, no post-render overlay, no second authoring surface.

static NSString * const kM641BackendPrefix = @"zonoe.m6.4.1.backend.v1";
static NSString * const kM641ControlPrefix = @"zonoe.m6.4.1.control.v1";
static NSString * const kM641SliderPrefix  = @"zonoe.m5.8.5.static-slider-max.v1";
static NSString * const kM641ValuePrefix   = @"zonoe.m6.4.offset-fixed-value.v1";

static const NSInteger kM641Target          = 440000;
static const NSInteger kM641OffsetField     = 441000;
static const NSInteger kM641StaticName      = 710000;
static const NSInteger kM641StaticDesc      = 711000;
static const NSInteger kM641StaticPatch     = 712000;
static const NSInteger kM641StaticDelete    = 713000;
static const NSInteger kM641RuntimeRowName  = 730000;
static const NSInteger kM641RuntimeRowDesc  = 731000;
static const NSInteger kM641RuntimeRowCtl   = 732000;
static const NSInteger kM641RuntimeRowAux   = 733000;
static const NSInteger kM641RuntimeRowDel   = 734000;
static const NSInteger kM641RuntimeName     = 720000;
static const NSInteger kM641RuntimeDesc     = 721000;
static const NSInteger kM641RuntimeCtl      = 722000;
static const NSInteger kM641RuntimeAux      = 723000;
static const NSInteger kM641RuntimeDel      = 724000;

typedef NS_ENUM(NSInteger,M641Backend){M641BackendRuntime=0,M641BackendStatic=1};

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

static NSString *M641Trim(NSString *s){return [(s?:@"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *M641NameForRow(ZNBinaryPatchRow *r){NSString *g=M641Trim(r.group);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return g;NSString *t=M641Trim(r.title);return t.length?t:@"未命名功能";}
static NSString *M641Key(NSString *prefix,NSString *name){return [NSString stringWithFormat:@"%@.%@",prefix,M641Trim(name).lowercaseString];}
static BOOL M641Placeholder(ZNBinaryPatchRow *r){NSString *g=M641Trim(r.group),*t=M641Trim(r.title);BOOL pg=!g.length||[g caseInsensitiveCompare:@"Imported"]==NSOrderedSame;return !r.offsetText.length&&!r.enabledText.length&&!t.length&&pg;}

static NSArray<ZNBinaryPatchRow *> *M641Rows(void){
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];[w ensureDefaultRows];
    NSMutableArray *out=[NSMutableArray array];
    for(ZNBinaryPatchRow *r in w.rows){if(!M641Placeholder(r))[out addObject:r];}
    return [out copy];
}
static M641Backend M641BackendForRow(ZNBinaryPatchRow *r){NSString *s=[NSUserDefaults.standardUserDefaults stringForKey:M641Key(kM641BackendPrefix,M641NameForRow(r))];if([s isEqualToString:@"static"])return M641BackendStatic;if([s isEqualToString:@"runtime"])return M641BackendRuntime;return r.enabledText.length?M641BackendStatic:M641BackendRuntime;}
static void M641SetBackend(ZNBinaryPatchRow *r,M641Backend b){[NSUserDefaults.standardUserDefaults setObject:(b==M641BackendStatic?@"static":@"runtime") forKey:M641Key(kM641BackendPrefix,M641NameForRow(r))];}
static NSArray<ZNBinaryPatchRow *> *M641RowsForBackend(M641Backend b){NSMutableArray *out=[NSMutableArray array];for(ZNBinaryPatchRow *r in M641Rows())if(M641BackendForRow(r)==b)[out addObject:r];return [out copy];}

static ZNRuntimeArgumentControlType M641RuntimeControl(ZNBinaryPatchRow *r){NSString *s=[NSUserDefaults.standardUserDefaults stringForKey:M641Key(kM641ControlPrefix,M641NameForRow(r))];if(s.length)return ZNRuntimeArgumentControlTypeFromKey(s);switch(r.featureControlType){case ZNFeatureControlTypeSlider:return ZNRuntimeArgumentControlTypeSlider;case ZNFeatureControlTypeSwitch:return ZNRuntimeArgumentControlTypeSwitch;case ZNFeatureControlTypeButton:return ZNRuntimeArgumentControlTypeButton;default:return ZNRuntimeArgumentControlTypeNumber;}}
static void M641SetRuntimeControl(ZNBinaryPatchRow *r,ZNRuntimeArgumentControlType c){[NSUserDefaults.standardUserDefaults setObject:ZNRuntimeArgumentControlTypeKey(c) forKey:M641Key(kM641ControlPrefix,M641NameForRow(r))];r.featureControlType=(c==ZNRuntimeArgumentControlTypeSlider)?ZNFeatureControlTypeSlider:(c==ZNRuntimeArgumentControlTypeSwitch?ZNFeatureControlTypeSwitch:(c==ZNRuntimeArgumentControlTypeButton?ZNFeatureControlTypeButton:ZNFeatureControlTypeNumber));}
static ZNRuntimeArgumentControlType M641NextRuntime(ZNRuntimeArgumentControlType c){switch(c){case ZNRuntimeArgumentControlTypeFixed:return ZNRuntimeArgumentControlTypeNumber;case ZNRuntimeArgumentControlTypeNumber:return ZNRuntimeArgumentControlTypeSlider;case ZNRuntimeArgumentControlTypeSlider:return ZNRuntimeArgumentControlTypeSwitch;case ZNRuntimeArgumentControlTypeSwitch:return ZNRuntimeArgumentControlTypeButton;default:return ZNRuntimeArgumentControlTypeFixed;}}
static NSString *M641RuntimeControlDisplay(ZNRuntimeArgumentControlType c){switch(c){case ZNRuntimeArgumentControlTypeFixed:return @"固定值";case ZNRuntimeArgumentControlTypeNumber:return @"数值";case ZNRuntimeArgumentControlTypeSlider:return @"滑块";case ZNRuntimeArgumentControlTypeSwitch:return @"开关";case ZNRuntimeArgumentControlTypeButton:return @"按钮";default:return ZNRuntimeArgumentControlTypeName(c);}}
static ZNRuntimeArgumentControlType M641ActionControl(ZNRuntimeMethodAction *a){if(a.argumentCount!=1||a.argumentControlConfigs.count!=1)return ZNRuntimeArgumentControlTypeFixed;NSDictionary *cfg=a.argumentControlConfigs.firstObject;return [cfg[@"enabled"]boolValue]?ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]):ZNRuntimeArgumentControlTypeFixed;}

static UITextField *M641Field(CGRect f,ZNTheme *t){UITextField *x=[[UITextField alloc]initWithFrame:f];x.textColor=t.primaryTextColor;x.backgroundColor=t.controlColor;x.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];x.autocorrectionType=UITextAutocorrectionTypeNo;x.autocapitalizationType=UITextAutocapitalizationTypeNone;x.returnKeyType=UIReturnKeyDone;x.clearButtonMode=UITextFieldViewModeWhileEditing;x.layer.cornerRadius=7;x.layer.borderWidth=1;x.layer.borderColor=t.borderColor.CGColor;UIView *p=[[UIView alloc]initWithFrame:CGRectMake(0,0,8,1)];x.leftView=p;x.leftViewMode=UITextFieldViewModeAlways;return x;}
static UIColor *M641StatusColor(NSString *status,ZNTheme *theme){NSString *s=M641Trim(status);if([s hasPrefix:@"❌"])return UIColor.systemRedColor;if([s hasPrefix:@"✅"])return UIColor.systemGreenColor;if([s hasPrefix:@"⚠"])return UIColor.systemOrangeColor;return theme.secondaryTextColor;}
static void M641Persist(void){ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];[w updateDefaultTarget:w.defaultTarget];}
static void M641MoveSidecars(NSString *oldName,NSString *newName){for(NSString *p in @[kM641BackendPrefix,kM641ControlPrefix,kM641SliderPrefix,kM641ValuePrefix]){NSString *ok=M641Key(p,oldName),*nk=M641Key(p,newName);id v=[NSUserDefaults.standardUserDefaults objectForKey:ok];if(v){[NSUserDefaults.standardUserDefaults setObject:v forKey:nk];[NSUserDefaults.standardUserDefaults removeObjectForKey:ok];}}}
static void M641ClearSidecars(NSString *name){for(NSString *p in @[kM641BackendPrefix,kM641ControlPrefix,kM641SliderPrefix,kM641ValuePrefix])[NSUserDefaults.standardUserDefaults removeObjectForKey:M641Key(p,name)];}
static BOOL M641ValidateStaticRows(ZNBinaryPatchWorkspace *w,NSString **error){NSArray<ZNBinaryPatchRow *> *original=[w.rows copy];NSMutableArray<ZNBinaryPatchRow *> *statics=[NSMutableArray array];for(ZNBinaryPatchRow *r in original){if(M641Placeholder(r))continue;if(M641BackendForRow(r)==M641BackendStatic)[statics addObject:r];}if(!statics.count)return YES;[w.rows removeAllObjects];[w.rows addObjectsFromArray:statics];NSString *e=nil;BOOL ok=[w validateAll:&e];[w.rows removeAllObjects];[w.rows addObjectsFromArray:original];if(!ok&&error)*error=e?:@"普通 Patch 验证失败";return ok;}

@interface ZNRuntimeMenuControllerV040 (M641Authoring)
- (void)m641_renderOther;
- (void)m641_target:(UITextField *)f;
- (void)m641_addStatic:(id)s;
- (void)m641_addRuntime:(id)s;
- (void)m641_staticName:(UITextField *)f;
- (void)m641_staticDesc:(UITextField *)f;
- (void)m641_staticPatch:(UITextField *)f;
- (void)m641_staticDelete:(UIButton *)b;
- (void)m641_runtimeRowName:(UITextField *)f;
- (void)m641_runtimeRowDesc:(UITextField *)f;
- (void)m641_runtimeRowCtl:(UIButton *)b;
- (void)m641_runtimeRowAux:(UITextField *)f;
- (void)m641_runtimeRowDel:(UIButton *)b;
- (void)m641_runtimeName:(UITextField *)f;
- (void)m641_runtimeDesc:(UITextField *)f;
- (void)m641_runtimeCtl:(UIButton *)b;
- (void)m641_runtimeAux:(UITextField *)f;
- (void)m641_runtimeDel:(UIButton *)b;
- (void)m641_build:(id)s;
@end

@implementation ZNRuntimeMenuControllerV040 (M641Authoring)

- (void)m641_renderOther{
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=9;
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];BOOL locked=w.isBuilding||w.hasAnyApplied;

    UIView *tc=[self cardAtY:y height:56 width:width compact:NO];
    UILabel *bl=[self label:@"二进制" size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];bl.frame=CGRectMake(13,11,48,32);[tc addSubview:bl];
    UITextField *tf=M641Field(CGRectMake(65,11,tc.bounds.size.width-78,32),self.theme);tf.tag=kM641Target;tf.text=w.defaultTarget;tf.placeholder=@"UnityFramework / 主程序 / 其他 dylib";tf.enabled=!locked;[tf addTarget:self action:@selector(m641_target:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[tc addSubview:tf];[self.contentView addSubview:tc];y+=64;

    NSArray<ZNBinaryPatchRow *> *staticRows=M641RowsForBackend(M641BackendStatic);
    UIView *sh=[self cardAtY:y height:42 width:width compact:NO];UILabel *sl=[self label:[NSString stringWithFormat:@"普通 Patch · %lu",(unsigned long)staticRows.count] size:10.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];sl.frame=CGRectMake(13,7,sh.bounds.size.width-26,28);[sh addSubview:sl];[self.contentView addSubview:sh];y+=50;

    for(NSUInteger i=0;i<staticRows.count;i++){
        ZNBinaryPatchRow *r=staticRows[i];BOOL hasStatus=M641Trim(r.statusText).length>0;CGFloat h=181+(hasStatus?29:0);UIView *c=[self cardAtY:y height:h width:width compact:NO];CGFloat x=13,fw=c.bounds.size.width-71;
        UILabel *l1=[self label:@"名称" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l1.frame=CGRectMake(x,7,42,29);[c addSubview:l1];UITextField *nf=M641Field(CGRectMake(58,7,fw,29),self.theme);nf.tag=kM641StaticName+(NSInteger)i;nf.text=M641NameForRow(r);nf.enabled=!locked;[nf addTarget:self action:@selector(m641_staticName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:nf];
        UILabel *l2=[self label:@"说明" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l2.frame=CGRectMake(x,42,42,29);[c addSubview:l2];UITextField *df=M641Field(CGRectMake(58,42,fw,29),self.theme);df.tag=kM641StaticDesc+(NSInteger)i;df.text=M641Trim(r.title);df.placeholder=@"显示给客户的说明";df.enabled=!locked;[df addTarget:self action:@selector(m641_staticDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:df];
        UILabel *l3=[self label:@"Offset" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l3.frame=CGRectMake(x,77,42,29);[c addSubview:l3];NSUInteger gi=[w.rows indexOfObjectIdenticalTo:r];UITextField *off=[self zn44_field:CGRectMake(58,77,fw,29) text:r.offsetText placeholder:@"0x123456" tag:kM641OffsetField+(NSInteger)gi enabled:!locked];[c addSubview:off];
        UILabel *l4=[self label:@"Patch" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l4.frame=CGRectMake(x,112,42,29);[c addSubview:l4];UITextField *pf=M641Field(CGRectMake(58,112,fw,29),self.theme);pf.tag=kM641StaticPatch+(NSInteger)i;pf.text=r.enabledText;pf.placeholder=@"例如 1F2003D5 / C0035FD6";pf.keyboardType=UIKeyboardTypeASCIICapable;pf.enabled=!locked;[pf addTarget:self action:@selector(m641_staticPatch:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:pf];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(m641_staticDelete:) frame:CGRectMake(c.bounds.size.width-62,147,49,29)];del.tag=kM641StaticDelete+(NSInteger)i;del.enabled=!locked;[c addSubview:del];UILabel *hint=[self label:@"普通 Offset + HEX Patch" size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];hint.frame=CGRectMake(x,147,c.bounds.size.width-82,29);[c addSubview:hint];
        if(hasStatus){UILabel *st=[self label:r.statusText size:8.4 weight:UIFontWeightSemibold color:M641StatusColor(r.statusText,self.theme)];st.frame=CGRectMake(x,181,c.bounds.size.width-26,24);st.numberOfLines=2;[c addSubview:st];}
        [self.contentView addSubview:c];y+=h+8;
    }
    UIView *sa=[self cardAtY:y height:46 width:width compact:NO];UIButton *sab=[self zn40_button:@"＋ 增加普通 Patch" selector:@selector(m641_addStatic:) frame:CGRectMake(13,7,sa.bounds.size.width-26,32)];sab.enabled=!locked;[sa addSubview:sab];[self.contentView addSubview:sa];y+=58;

    NSArray<ZNBinaryPatchRow *> *runtimeRows=M641RowsForBackend(M641BackendRuntime);
    UIView *rsh=[self cardAtY:y height:42 width:width compact:NO];UILabel *rsl=[self label:[NSString stringWithFormat:@"Runtime / IL2CPP · 待生成 %lu",(unsigned long)runtimeRows.count] size:10.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];rsl.frame=CGRectMake(13,7,rsh.bounds.size.width-26,28);[rsh addSubview:rsl];[self.contentView addSubview:rsh];y+=50;

    for(NSUInteger i=0;i<runtimeRows.count;i++){
        ZNBinaryPatchRow *r=runtimeRows[i];NSString *name=M641NameForRow(r);ZNRuntimeArgumentControlType ct=M641RuntimeControl(r);BOOL aux=(ct==ZNRuntimeArgumentControlTypeSlider||ct==ZNRuntimeArgumentControlTypeFixed||ct==ZNRuntimeArgumentControlTypeButton);BOOL hasStatus=M641Trim(r.statusText).length>0;CGFloat h=(aux?216:181)+(hasStatus?29:0);UIView *c=[self cardAtY:y height:h width:width compact:NO];CGFloat x=13,fw=c.bounds.size.width-71;
        UILabel *l1=[self label:@"名称" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l1.frame=CGRectMake(x,7,42,29);[c addSubview:l1];UITextField *nf=M641Field(CGRectMake(58,7,fw,29),self.theme);nf.tag=kM641RuntimeRowName+(NSInteger)i;nf.text=name;nf.enabled=!locked;[nf addTarget:self action:@selector(m641_runtimeRowName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:nf];
        UILabel *l2=[self label:@"说明" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l2.frame=CGRectMake(x,42,42,29);[c addSubview:l2];UITextField *df=M641Field(CGRectMake(58,42,fw,29),self.theme);df.tag=kM641RuntimeRowDesc+(NSInteger)i;df.text=M641Trim(r.title);df.placeholder=@"显示给客户的说明";df.enabled=!locked;[df addTarget:self action:@selector(m641_runtimeRowDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:df];
        UILabel *l3=[self label:@"Offset" size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l3.frame=CGRectMake(x,77,42,29);[c addSubview:l3];NSUInteger gi=[w.rows indexOfObjectIdenticalTo:r];UITextField *off=[self zn44_field:CGRectMake(58,77,fw,29) text:r.offsetText placeholder:@"exact IL2CPP method RVA" tag:kM641OffsetField+(NSInteger)gi enabled:!locked];[c addSubview:off];
        UIButton *ctl=[self zn40_button:[NSString stringWithFormat:@"控件 · %@",M641RuntimeControlDisplay(ct)] selector:@selector(m641_runtimeRowCtl:) frame:CGRectMake(x,112,c.bounds.size.width-80,29)];ctl.tag=kM641RuntimeRowCtl+(NSInteger)i;ctl.enabled=!locked;[c addSubview:ctl];UIButton *del=[self zn40_button:@"删除" selector:@selector(m641_runtimeRowDel:) frame:CGRectMake(c.bounds.size.width-62,147,49,29)];del.tag=kM641RuntimeRowDel+(NSInteger)i;del.enabled=!locked;[c addSubview:del];UILabel *hint=[self label:@"Offset → exact IL2CPP Method" size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];hint.frame=CGRectMake(x,147,c.bounds.size.width-82,29);[c addSubview:hint];
        if(aux){UILabel *al=[self label:(ct==ZNRuntimeArgumentControlTypeSlider?@"Max":@"Value") size:8.6 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];al.frame=CGRectMake(x,182,52,29);[c addSubview:al];UITextField *af=M641Field(CGRectMake(67,182,c.bounds.size.width-80,29),self.theme);af.tag=kM641RuntimeRowAux+(NSInteger)i;af.enabled=!locked;af.keyboardType=UIKeyboardTypeNumbersAndPunctuation;if(ct==ZNRuntimeArgumentControlTypeSlider){id m=[NSUserDefaults.standardUserDefaults objectForKey:M641Key(kM641SliderPrefix,name)];af.text=[m isKindOfClass:NSNumber.class]?[(NSNumber *)m stringValue]:@"";af.placeholder=@"例如 31";}else{af.text=[NSUserDefaults.standardUserDefaults stringForKey:M641Key(kM641ValuePrefix,name)]?:@"";af.placeholder=@"例如 10000";}[af addTarget:self action:@selector(m641_runtimeRowAux:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:af];}
        if(hasStatus){CGFloat sy=aux?216:181;UILabel *st=[self label:r.statusText size:8.4 weight:UIFontWeightSemibold color:M641StatusColor(r.statusText,self.theme)];st.frame=CGRectMake(x,sy,c.bounds.size.width-26,24);st.numberOfLines=2;[c addSubview:st];}
        [self.contentView addSubview:c];y+=h+8;
    }
    UIView *ra=[self cardAtY:y height:46 width:width compact:NO];UIButton *rab=[self zn40_button:@"＋ 增加 Runtime 功能" selector:@selector(m641_addRuntime:) frame:CGRectMake(13,7,ra.bounds.size.width-26,32)];rab.enabled=!locked;[ra addSubview:rab];[self.contentView addSubview:ra];y+=58;

    NSArray *actions=[[ZNRuntimeActionStore sharedStore]actionsSnapshot];
    UIView *rh=[self cardAtY:y height:40 width:width compact:NO];UILabel *rhl=[self label:[NSString stringWithFormat:@"已保存 Runtime Method · %lu",(unsigned long)actions.count] size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];rhl.frame=CGRectMake(13,6,rh.bounds.size.width-26,28);[rh addSubview:rhl];[self.contentView addSubview:rh];y+=48;
    for(NSUInteger i=0;i<actions.count;i++){
        ZNRuntimeMethodAction *act=actions[i];BOOL one=act.argumentCount==1;ZNRuntimeArgumentControlType ct=M641ActionControl(act);CGFloat h=one?151:112;UIView *c=[self cardAtY:y height:h width:width compact:NO];
        UITextField *nf=M641Field(CGRectMake(13,7,c.bounds.size.width-76,29),self.theme);nf.tag=kM641RuntimeName+(NSInteger)i;nf.text=act.title;nf.placeholder=act.methodName;[nf addTarget:self action:@selector(m641_runtimeName:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:nf];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(m641_runtimeDel:) frame:CGRectMake(c.bounds.size.width-58,7,45,29)];del.tag=kM641RuntimeDel+(NSInteger)i;[c addSubview:del];
        UITextField *df=M641Field(CGRectMake(13,42,c.bounds.size.width-26,29),self.theme);df.tag=kM641RuntimeDesc+(NSInteger)i;df.text=([act.group caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame)?@"":act.group;df.placeholder=@"说明（显示给客户）";[df addTarget:self action:@selector(m641_runtimeDesc:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[c addSubview:df];
        UILabel *idn=[self label:act.canonicalIdentity size:7.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];idn.frame=CGRectMake(13,77,c.bounds.size.width-26,25);idn.numberOfLines=2;[c addSubview:idn];
        if(one){UIButton *ctl=[self zn40_button:[NSString stringWithFormat:@"控件 · %@",M641RuntimeControlDisplay(ct)] selector:@selector(m641_runtimeCtl:) frame:CGRectMake(13,111,c.bounds.size.width*.5-17,31)];ctl.tag=kM641RuntimeCtl+(NSInteger)i;[c addSubview:ctl];if(ct==ZNRuntimeArgumentControlTypeSlider||ct==ZNRuntimeArgumentControlTypeFixed||ct==ZNRuntimeArgumentControlTypeButton){UITextField *af=M641Field(CGRectMake(c.bounds.size.width*.5+2,111,c.bounds.size.width*.5-15,31),self.theme);af.tag=kM641RuntimeAux+(NSInteger)i;af.keyboardType=UIKeyboardTypeNumbersAndPunctuation;if(ct==ZNRuntimeArgumentControlTypeSlider){NSDictionary *cfg=act.argumentControlConfigs.firstObject;af.text=[cfg[@"max"]description];af.placeholder=@"Max";}else{af.text=act.argumentValues.firstObject?:@"";af.placeholder=@"Value";}[af addTarget:self action:@selector(m641_runtimeAux:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];[c addSubview:af];}}
        [self.contentView addSubview:c];y+=h+8;
    }

    UIView *bc=[self cardAtY:y height:52 width:width compact:NO];UIButton *build=[self zn40_button:(w.isBuilding?@"正在生成…":@"解析并生成新二进制") selector:@selector(m641_build:) frame:CGRectMake(13,9,bc.bounds.size.width-26,34)];build.enabled=!w.isBuilding&&!w.hasAnyApplied&&(staticRows.count||runtimeRows.count||actions.count);[bc addSubview:build];[self.contentView addSubview:bc];y+=60;
    if(w.lastStatus.length){UIView *sc=[self cardAtY:y height:46 width:width compact:NO];UIColor *gc=[w.lastStatus containsString:@"失败"]?UIColor.systemRedColor:self.theme.secondaryTextColor;UILabel *gs=[self label:w.lastStatus size:8.2 weight:UIFontWeightRegular color:gc];gs.frame=CGRectMake(13,6,sc.bounds.size.width-26,34);gs.numberOfLines=2;[sc addSubview:gs];[self.contentView addSubview:sc];y+=54;}
    [self zn40_updateContentHeight:y];
}

- (void)m641_target:(UITextField *)f{ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *t=M641Trim(f.text);if(!t.length)t=@"UnityFramework";[w updateDefaultTarget:t];for(ZNBinaryPatchRow *r in w.rows){if(!M641Placeholder(r)){r.target=t;r.explicitTarget=YES;r.validated=NO;r.validator=nil;r.statusText=@"";}}f.text=w.defaultTarget;[f resignFirstResponder];}

- (void)m641_addStatic:(id)s{(void)s;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(w.isBuilding||w.hasAnyApplied)return;NSUInteger n=1;NSMutableSet *used=[NSMutableSet set];for(ZNBinaryPatchRow *r in M641Rows())[used addObject:M641NameForRow(r).lowercaseString];NSString *name=nil;do{name=[NSString stringWithFormat:@"普通 Patch %lu",(unsigned long)n++];}while([used containsObject:name.lowercaseString]);ZNBinaryPatchRow *r=[ZNBinaryPatchRow new];r.group=name;r.title=@"";r.target=w.defaultTarget;r.explicitTarget=YES;r.statusText=@"⚠ 待填写 Offset / Patch";r.featureControlType=ZNFeatureControlTypeSwitch;[w.rows addObject:r];M641SetBackend(r,M641BackendStatic);[NSUserDefaults.standardUserDefaults setObject:@"hex" forKey:M641Key(kM641ControlPrefix,name)];M641Persist();[self renderPage];}
- (void)m641_addRuntime:(id)s{(void)s;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(w.isBuilding||w.hasAnyApplied)return;NSUInteger n=1;NSMutableSet *used=[NSMutableSet set];for(ZNBinaryPatchRow *r in M641Rows())[used addObject:M641NameForRow(r).lowercaseString];NSString *name=nil;do{name=[NSString stringWithFormat:@"Runtime 功能 %lu",(unsigned long)n++];}while([used containsObject:name.lowercaseString]);ZNBinaryPatchRow *r=[ZNBinaryPatchRow new];r.group=name;r.title=@"";r.target=w.defaultTarget;r.explicitTarget=YES;r.statusText=@"⚠ 待填写 Offset";r.featureControlType=ZNFeatureControlTypeNumber;[w.rows addObject:r];M641SetBackend(r,M641BackendRuntime);M641SetRuntimeControl(r,ZNRuntimeArgumentControlTypeNumber);M641Persist();[self renderPage];}

- (void)m641_staticName:(UITextField *)f{NSInteger i=f.tag-kM641StaticName;NSArray *rows=M641RowsForBackend(M641BackendStatic);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];NSString *old=M641NameForRow(r),*name=M641Trim(f.text);if(!name.length){f.text=old;return;}M641MoveSidecars(old,name);r.group=name;M641Persist();[f resignFirstResponder];}
- (void)m641_staticDesc:(UITextField *)f{NSInteger i=f.tag-kM641StaticDesc;NSArray *rows=M641RowsForBackend(M641BackendStatic);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];r.title=M641Trim(f.text);M641Persist();[f resignFirstResponder];}
- (void)m641_staticPatch:(UITextField *)f{NSInteger i=f.tag-kM641StaticPatch;NSArray *rows=M641RowsForBackend(M641BackendStatic);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];r.enabledText=[M641Trim(f.text) uppercaseString];r.validated=NO;r.validator=nil;r.statusText=@"";}
- (void)m641_staticDelete:(UIButton *)b{NSInteger i=b.tag-kM641StaticDelete;NSArray *rows=M641RowsForBackend(M641BackendStatic);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];ZNBinaryPatchRow *r=rows[(NSUInteger)i];NSString *name=M641NameForRow(r);[w.rows removeObjectIdenticalTo:r];M641ClearSidecars(name);[w ensureDefaultRows];M641Persist();[self renderPage];}

- (void)m641_runtimeRowName:(UITextField *)f{NSInteger i=f.tag-kM641RuntimeRowName;NSArray *rows=M641RowsForBackend(M641BackendRuntime);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];NSString *old=M641NameForRow(r),*name=M641Trim(f.text);if(!name.length){f.text=old;return;}M641MoveSidecars(old,name);r.group=name;M641Persist();[f resignFirstResponder];}
- (void)m641_runtimeRowDesc:(UITextField *)f{NSInteger i=f.tag-kM641RuntimeRowDesc;NSArray *rows=M641RowsForBackend(M641BackendRuntime);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];r.title=M641Trim(f.text);M641Persist();[f resignFirstResponder];}
- (void)m641_runtimeRowCtl:(UIButton *)b{NSInteger i=b.tag-kM641RuntimeRowCtl;NSArray *rows=M641RowsForBackend(M641BackendRuntime);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];M641SetRuntimeControl(r,M641NextRuntime(M641RuntimeControl(r)));r.validated=NO;r.validator=nil;r.statusText=@"";M641Persist();[self renderPage];}
- (void)m641_runtimeRowAux:(UITextField *)f{NSInteger i=f.tag-kM641RuntimeRowAux;NSArray *rows=M641RowsForBackend(M641BackendRuntime);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchRow *r=rows[(NSUInteger)i];NSString *name=M641NameForRow(r);ZNRuntimeArgumentControlType c=M641RuntimeControl(r);if(c==ZNRuntimeArgumentControlTypeSlider){double m=f.text.doubleValue;NSString *k=M641Key(kM641SliderPrefix,name);if(isfinite(m)&&m>0)[NSUserDefaults.standardUserDefaults setDouble:m forKey:k];else[NSUserDefaults.standardUserDefaults removeObjectForKey:k];}else{NSString *k=M641Key(kM641ValuePrefix,name),*v=M641Trim(f.text);if(v.length)[NSUserDefaults.standardUserDefaults setObject:v forKey:k];else[NSUserDefaults.standardUserDefaults removeObjectForKey:k];}r.validated=NO;r.validator=nil;r.statusText=@"";}
- (void)m641_runtimeRowDel:(UIButton *)b{NSInteger i=b.tag-kM641RuntimeRowDel;NSArray *rows=M641RowsForBackend(M641BackendRuntime);if(i<0||(NSUInteger)i>=rows.count)return;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];ZNBinaryPatchRow *r=rows[(NSUInteger)i];NSString *name=M641NameForRow(r);[w.rows removeObjectIdenticalTo:r];M641ClearSidecars(name);[w ensureDefaultRows];M641Persist();[self renderPage];}

- (void)m641_runtimeName:(UITextField *)f{NSInteger i=f.tag-kM641RuntimeName;if(i>=0)[[ZNRuntimeActionStore sharedStore]updateTitle:f.text atIndex:(NSUInteger)i error:nil];[f resignFirstResponder];}
- (void)m641_runtimeDesc:(UITextField *)f{NSInteger i=f.tag-kM641RuntimeDesc;if(i>=0)[[ZNRuntimeActionStore sharedStore]updateGroup:f.text atIndex:(NSUInteger)i error:nil];[f resignFirstResponder];}
- (void)m641_runtimeCtl:(UIButton *)b{NSInteger i=b.tag-kM641RuntimeCtl;NSArray *a=[[ZNRuntimeActionStore sharedStore]actionsSnapshot];if(i<0||(NSUInteger)i>=a.count)return;ZNRuntimeMethodAction *x=a[(NSUInteger)i];if(x.argumentCount!=1)return;ZNRuntimeArgumentControlType n=M641NextRuntime(M641ActionControl(x));NSMutableDictionary *cfg=[x.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@(n!=ZNRuntimeArgumentControlTypeFixed);cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(n);if(n==ZNRuntimeArgumentControlTypeSlider){double m=[cfg[@"max"]doubleValue];if(!isfinite(m)||m<=0)m=10;cfg[@"min"]=@0;cfg[@"max"]=@(m);cfg[@"step"]=@1;cfg[@"default"]=@(m);}[[ZNRuntimeActionStore sharedStore]updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)i error:nil];[self renderPage];}
- (void)m641_runtimeAux:(UITextField *)f{NSInteger i=f.tag-kM641RuntimeAux;NSArray *a=[[ZNRuntimeActionStore sharedStore]actionsSnapshot];if(i<0||(NSUInteger)i>=a.count)return;ZNRuntimeMethodAction *x=a[(NSUInteger)i];if(x.argumentCount!=1)return;ZNRuntimeArgumentControlType c=M641ActionControl(x);if(c==ZNRuntimeArgumentControlTypeSlider){double m=f.text.doubleValue;if(!isfinite(m)||m<=0)return;NSMutableDictionary *cfg=[x.argumentControlConfigs.firstObject mutableCopy]?:[NSMutableDictionary dictionary];cfg[@"enabled"]=@YES;cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(c);cfg[@"min"]=@0;cfg[@"max"]=@(m);cfg[@"step"]=@1;cfg[@"default"]=@(m);[[ZNRuntimeActionStore sharedStore]updateArgumentControlConfigs:@[[cfg copy]] atIndex:(NSUInteger)i error:nil];[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[[NSString stringWithFormat:@"%.15g",m]] atIndex:(NSUInteger)i error:nil];}else if(c==ZNRuntimeArgumentControlTypeFixed||c==ZNRuntimeArgumentControlTypeButton){[[ZNRuntimeActionStore sharedStore]updateArgumentValues:@[M641Trim(f.text)] atIndex:(NSUInteger)i error:nil];}}
- (void)m641_runtimeDel:(UIButton *)b{NSInteger i=b.tag-kM641RuntimeDel;if(i>=0)[[ZNRuntimeActionStore sharedStore]removeActionAtIndex:(NSUInteger)i];[self renderPage];}

- (void)m641_build:(id)s{
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray *statics=M641RowsForBackend(M641BackendStatic),*runtimes=M641RowsForBackend(M641BackendRuntime);
    for(ZNBinaryPatchRow *r in statics){NSString *name=M641NameForRow(r);r.statusText=@"";if(!r.offsetText.length){r.statusText=@"❌ 必须填写 Offset";w.lastStatus=[NSString stringWithFormat:@"解析准备失败 · %@：必须填写 Offset",name];[self renderPage];return;}if(!M641Trim(r.enabledText).length){r.statusText=@"❌ Patch 不能为空";w.lastStatus=[NSString stringWithFormat:@"解析准备失败 · %@：Patch 不能为空",name];[self renderPage];return;}}
    for(ZNBinaryPatchRow *r in runtimes){NSString *name=M641NameForRow(r);r.statusText=@"";if(!r.offsetText.length){r.statusText=@"❌ 必须填写 Offset";w.lastStatus=[NSString stringWithFormat:@"解析准备失败 · %@：必须填写 Offset",name];[self renderPage];return;}ZNRuntimeArgumentControlType c=M641RuntimeControl(r);if(c==ZNRuntimeArgumentControlTypeSlider){id m=[NSUserDefaults.standardUserDefaults objectForKey:M641Key(kM641SliderPrefix,name)];if(![m isKindOfClass:NSNumber.class]||[(NSNumber *)m doubleValue]<=0){r.statusText=@"❌ Slider Max 必须大于 0";w.lastStatus=[NSString stringWithFormat:@"解析准备失败 · %@：Slider Max 必须大于 0",name];[self renderPage];return;}}if((c==ZNRuntimeArgumentControlTypeFixed||c==ZNRuntimeArgumentControlTypeButton)&&![[NSUserDefaults.standardUserDefaults stringForKey:M641Key(kM641ValuePrefix,name)]length]){r.statusText=[NSString stringWithFormat:@"❌ %@ Value 不能为空",M641RuntimeControlDisplay(c)];w.lastStatus=[NSString stringWithFormat:@"解析准备失败 · %@：%@ Value 不能为空",name,M641RuntimeControlDisplay(c)];[self renderPage];return;}r.statusText=@"⚠ 待解析 IL2CPP exact Method";}
    NSString *e=nil;if(!M641ValidateStaticRows(w,&e)){ZNBinaryPatchRow *bad=nil;for(ZNBinaryPatchRow *r in statics)if([M641Trim(r.statusText) hasPrefix:@"❌"]){bad=r;break;}w.lastStatus=bad?[NSString stringWithFormat:@"解析准备失败 · %@：%@",M641NameForRow(bad),M641Trim(bad.statusText)]:[NSString stringWithFormat:@"解析准备失败：%@",e?:@"普通 Patch 验证失败"];[self renderPage];return;}
    [self zn44_buildBinary:s];
}
@end

static void M641Swap(Class c,SEL a,SEL b){Method x=class_getInstanceMethod(c,a),y=class_getInstanceMethod(c,b);if(x&&y)method_exchangeImplementations(x,y);}
extern "C" void ZNInstallFeatureBuilderUIDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class c=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!c)return;M641Swap(c,@selector(zn44_renderOther),@selector(m641_renderOther));[[ZNRuntimeLogger sharedLogger]log:@"[m6.4.1-authoring] one Builder renderer; ordinary Patch and Runtime/IL2CPP authoring are visually separated"];} );}
