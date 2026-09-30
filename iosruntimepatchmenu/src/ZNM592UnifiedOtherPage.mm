#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M5.9.2 unified "Other" authoring surface.
// ZN_UI_CANONICAL_FEATURE_RENDERER
//
// One file, one renderer, one pass:
//   Runtime Method authoring + Offset/Static authoring + build actions.
// No previous renderer is called and no post-render decorator is required.

static const NSInteger kZN592NameBase       = 776000;
static const NSInteger kZN592DescBase       = 777000;
static const NSInteger kZN592OffsetBase     = 778000;
static const NSInteger kZN592AuxBase        = 779000;
static const NSInteger kZN592TypeBase       = 780000;
static const NSInteger kZN592ValueTypeBase  = 781000;
static const NSInteger kZN592DeleteBase     = 782000;

static const NSInteger kZN592RTTitleBase    = 820000;
static const NSInteger kZN592RTDeleteBase   = 821000;
static const NSInteger kZN592RTArgBase      = 830000;
static const NSInteger kZN592RTToggleBase   = 840000;
static const NSInteger kZN592RTTypeBase     = 850000;
static const NSInteger kZN592RTValueBase    = 860000;

static NSString * const kZN592SliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UITextField *)zn44_field:(CGRect)frame text:(NSString *)text placeholder:(NSString *)placeholder tag:(NSInteger)tag enabled:(BOOL)enabled;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn44_renderOther;
- (void)zn50b_renderOther;
- (void)zn64fb_renderOther;
- (void)zn44_importJSON:(id)sender;
- (void)zn44_jsonTapped:(UIButton *)sender;
- (void)zn44_applyAll:(id)sender;
- (void)zn44_restoreAll:(id)sender;
- (void)zn44_buildBinary:(id)sender;
@end

static NSString *ZN592Trim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void ZN592ConfigureField(UITextField *field) {
    // Unified input behavior requested for the whole page: full system keyboard
    // (Chinese/English/numbers/symbols) and an explicit Done key.
    field.keyboardType = UIKeyboardTypeDefault;
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.enablesReturnKeyAutomatically = NO;
}

static BOOL ZN592Meaningful(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *g=ZN592Trim(row.group), *t=ZN592Trim(row.title);
    if (g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return YES;
    return t.length>0;
}

static NSString *ZN592Name(ZNBinaryPatchRow *row, NSUInteger index) {
    NSString *g=ZN592Trim(row.group);
    if (g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return g;
    return [NSString stringWithFormat:@"新功能 %lu",(unsigned long)index+1];
}

static NSString *ZN592Description(ZNBinaryPatchRow *row) {
    NSString *t=ZN592Trim(row.title);
    return [t hasPrefix:@"Patch #"] ? @"" : t;
}

static NSString *ZN592SliderKey(NSString *name) {
    return [NSString stringWithFormat:@"%@.%@",kZN592SliderMaxPrefix,ZN592Trim(name).lowercaseString];
}
static double ZN592SliderMax(NSString *name) {
    id v=[NSUserDefaults.standardUserDefaults objectForKey:ZN592SliderKey(name)];
    return [v isKindOfClass:NSNumber.class]?[v doubleValue]:0.0;
}
static void ZN592StoreSliderMax(NSString *name,double value) {
    NSString *key=ZN592SliderKey(name);
    if(isfinite(value)&&value>0.0)[NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}
static BOOL ZN592ParseRVA(NSString *text,uint64_t *out) {
    NSString *s=ZN592Trim(text).lowercaseString;
    if(!s.length)return NO;
    const char *c=s.UTF8String; char *end=NULL; errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}
    if(errno||end==c||(end&&*end))return NO;
    if(out)*out=(uint64_t)v; return YES;
}
static ZNFeatureControlType ZN592NextStaticType(ZNFeatureControlType t) {
    switch(t){case ZNFeatureControlTypeNumber:return ZNFeatureControlTypeSlider;case ZNFeatureControlTypeSlider:return ZNFeatureControlTypeSwitch;case ZNFeatureControlTypeSwitch:return ZNFeatureControlTypeButton;default:return ZNFeatureControlTypeNumber;}
}
static ZNValueType ZN592NextValueType(ZNValueType t) {
    NSInteger n=(NSInteger)t+1; if(n>(NSInteger)ZNValueTypeF64)n=(NSInteger)ZNValueTypeAuto; return (ZNValueType)n;
}
static ZNRuntimeArgumentControlType ZN592NextRuntimeType(ZNRuntimeArgumentControlType t) {
    switch(t){case ZNRuntimeArgumentControlTypeSwitch:return ZNRuntimeArgumentControlTypeButton;case ZNRuntimeArgumentControlTypeButton:return ZNRuntimeArgumentControlTypeNumber;case ZNRuntimeArgumentControlTypeNumber:return ZNRuntimeArgumentControlTypeSlider;default:return ZNRuntimeArgumentControlTypeSwitch;}
}
static UIColor *ZN592StatusColor(NSString *text, UIColor *fallback) {
    if([text hasPrefix:@"❌"])return UIColor.systemRedColor;
    if([text hasPrefix:@"✅"])return UIColor.systemGreenColor;
    if([text hasPrefix:@"⚠"])return UIColor.systemOrangeColor;
    return fallback;
}
static void ZN592PersistStatic(ZNBinaryPatchWorkspace *w) {
    [w updateDefaultTarget:w.defaultTarget ?: @"main"];
}
static NSArray<NSDictionary *> *ZN592RuntimeConfigs(ZNRuntimeMethodAction *action) {
    if(action.argumentControlConfigs.count==action.argumentCount)return action.argumentControlConfigs;
    NSMutableArray *items=[NSMutableArray arrayWithCapacity:action.argumentCount];
    for(NSUInteger i=0;i<action.argumentCount;i++) [items addObject:@{@"enabled":@NO,@"type":@"fixed",@"valueType":@"auto",@"default":@1,@"min":@0,@"max":@100,@"step":@1}];
    return items;
}

@interface ZNRuntimeMenuControllerV040 (ZNM592UnifiedOtherPage)
- (void)znm592u_renderOther;
- (void)znm592u_targetEnd:(UITextField *)field;
- (void)znm592u_nameEnd:(UITextField *)field;
- (void)znm592u_descEnd:(UITextField *)field;
- (void)znm592u_offsetEnd:(UITextField *)field;
- (void)znm592u_auxEnd:(UITextField *)field;
- (void)znm592u_cycleType:(UIButton *)sender;
- (void)znm592u_cycleValueType:(UIButton *)sender;
- (void)znm592u_deleteStatic:(UIButton *)sender;
- (void)znm592u_addStatic:(id)sender;
- (void)znm592u_clearRuntime:(id)sender;
- (void)znm592u_deleteRuntime:(UIButton *)sender;
- (void)znm592u_runtimeTitleEnd:(UITextField *)field;
- (void)znm592u_runtimeArgEnd:(UITextField *)field;
- (void)znm592u_runtimeToggle:(UIButton *)sender;
- (void)znm592u_runtimeCycleType:(UIButton *)sender;
- (void)znm592u_runtimeCycleValue:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM592UnifiedOtherPage)

- (void)znm592u_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    [w ensureDefaultRows];
    NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    BOOL locked=w.hasAnyApplied||w.isBuilding;
    CGFloat width=CGRectGetWidth(self.contentView.bounds), y=9.0;

    // Runtime authoring lives in the canonical renderer, not a second swizzle.
    UIView *rtHeader=[self cardAtY:y height:48 width:width compact:NO];
    UILabel *rtTitle=[self label:[NSString stringWithFormat:@"Runtime Method Call · %lu",(unsigned long)actions.count] size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    rtTitle.frame=CGRectMake(13,8,rtHeader.bounds.size.width-96,31);[rtHeader addSubview:rtTitle];
    UIButton *clear=[self zn40_button:@"清空" selector:@selector(znm592u_clearRuntime:) frame:CGRectMake(rtHeader.bounds.size.width-75,8,62,31)];
    clear.enabled=actions.count>0&&!locked;clear.alpha=clear.enabled?1.0:0.5;[rtHeader addSubview:clear];[self.contentView addSubview:rtHeader];y+=56.0;

    if(!actions.count){
        UIView *empty=[self cardAtY:y height:54 width:width compact:NO];
        UILabel *l=[self label:@"在“方法查找”创建 Runtime 方法后，会在这里显示。" size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        l.frame=CGRectMake(13,8,empty.bounds.size.width-26,38);l.numberOfLines=2;[empty addSubview:l];[self.contentView addSubview:empty];y+=62.0;
    } else {
        for(NSUInteger i=0;i<actions.count;i++){
            ZNRuntimeMethodAction *action=actions[i];
            CGFloat rowH=34.0;
            CGFloat cardH=72.0 + action.argumentCount*rowH + 8.0;
            UIView *card=[self cardAtY:y height:cardH width:width compact:NO];
            UITextField *title=[self zn44_field:CGRectMake(13,7,card.bounds.size.width-82,28) text:(action.title.length?action.title:action.methodName) placeholder:action.methodName tag:kZN592RTTitleBase+(NSInteger)i enabled:!locked];
            ZN592ConfigureField(title);[title removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];[title addTarget:self action:@selector(znm592u_runtimeTitleEnd:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[card addSubview:title];
            UIButton *del=[self zn40_button:@"删除" selector:@selector(znm592u_deleteRuntime:) frame:CGRectMake(card.bounds.size.width-65,7,52,28)];del.tag=kZN592RTDeleteBase+(NSInteger)i;del.enabled=!locked;[card addSubview:del];
            UILabel *identity=[self label:action.canonicalIdentity size:7.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];identity.frame=CGRectMake(13,39,card.bounds.size.width-26,24);identity.numberOfLines=2;identity.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:identity];
            NSArray<NSDictionary *> *configs=ZN592RuntimeConfigs(action);
            for(NSUInteger a=0;a<action.argumentCount;a++){
                NSInteger slot=(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+a);
                CGFloat ay=68.0+a*rowH;
                UILabel *lab=[self label:[NSString stringWithFormat:@"参数%lu",(unsigned long)a+1] size:8.1 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];lab.frame=CGRectMake(13,ay,40,28);[card addSubview:lab];
                CGFloat controlsW=122.0;
                UITextField *arg=[self zn44_field:CGRectMake(54,ay,MAX(70.0,card.bounds.size.width-67-controlsW),28) text:(a<action.argumentValues.count?action.argumentValues[a]:@"") placeholder:@"参数值" tag:kZN592RTArgBase+slot enabled:!locked];
                ZN592ConfigureField(arg);[arg removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];[arg addTarget:self action:@selector(znm592u_runtimeArgEnd:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[card addSubview:arg];
                NSDictionary *cfg=configs[a];BOOL enabled=[cfg[@"enabled"] boolValue];ZNRuntimeArgumentControlType ct=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);ZNValueType vt=ZNValueTypeFromKey([cfg[@"valueType"] isKindOfClass:NSString.class]?cfg[@"valueType"]:@"auto");
                CGFloat x=CGRectGetMaxX(arg.frame)+4.0;
                UIButton *toggle=[self zn40_button:(enabled?@"☑":@"☐") selector:@selector(znm592u_runtimeToggle:) frame:CGRectMake(x,ay,30,28)];toggle.tag=kZN592RTToggleBase+slot;toggle.enabled=!locked;[card addSubview:toggle];x+=34.0;
                UIButton *type=[self zn40_button:(enabled?ZNRuntimeArgumentControlTypeName(ct):@"固定") selector:@selector(znm592u_runtimeCycleType:) frame:CGRectMake(x,ay,43,28)];type.tag=kZN592RTTypeBase+slot;type.enabled=enabled&&!locked;type.titleLabel.font=[UIFont systemFontOfSize:7.2 weight:UIFontWeightSemibold];[card addSubview:type];x+=47.0;
                UIButton *value=[self zn40_button:ZNValueTypeName(vt) selector:@selector(znm592u_runtimeCycleValue:) frame:CGRectMake(x,ay,41,28)];value.tag=kZN592RTValueBase+slot;value.enabled=enabled&&!locked;value.titleLabel.font=[UIFont systemFontOfSize:7.0 weight:UIFontWeightSemibold];[card addSubview:value];
            }
            [self.contentView addSubview:card];y+=cardH+8.0;
        }
    }

    // Static / Offset authoring.
    UIView *targetCard=[self cardAtY:y height:54 width:width compact:NO];
    UILabel *binary=[self label:@"二进制" size:10.5 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];binary.frame=CGRectMake(13,11,48,32);[targetCard addSubview:binary];
    CGFloat importW=76.0;UITextField *target=[self zn44_field:CGRectMake(62,11,targetCard.bounds.size.width-62-importW-18,32) text:w.defaultTarget placeholder:@"UnityFramework" tag:440000 enabled:!locked];ZN592ConfigureField(target);[target removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];[target addTarget:self action:@selector(znm592u_targetEnd:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[targetCard addSubview:target];
    UIButton *import=[self zn40_button:(w.showJSONFiles?@"收起 JSON":@"导入 JSON") selector:@selector(zn44_importJSON:) frame:CGRectMake(targetCard.bounds.size.width-importW-9,11,importW,32)];import.enabled=!locked;[targetCard addSubview:import];[self.contentView addSubview:targetCard];y+=62.0;

    if(w.showJSONFiles){NSUInteger count=w.jsonFiles.count;CGFloat h=32.0+count*34.0;UIView *json=[self cardAtY:y height:h width:width compact:NO];UILabel *jt=[self label:[NSString stringWithFormat:@"同目录 JSON · %lu",(unsigned long)count] size:10 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];jt.frame=CGRectMake(13,7,json.bounds.size.width-26,18);[json addSubview:jt];for(NSUInteger i=0;i<count;i++){NSString *path=w.jsonFiles[i];UIButton *b=[self zn40_button:path.lastPathComponent selector:@selector(zn44_jsonTapped:) frame:CGRectMake(13,27+i*34,json.bounds.size.width-26,28)];b.tag=446000+(NSInteger)i;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;b.titleLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[json addSubview:b];}[self.contentView addSubview:json];y+=h+8.0;}

    NSUInteger shown=0;
    for(NSUInteger i=0;i<w.rows.count;i++){
        ZNBinaryPatchRow *row=w.rows[i];if(!ZN592Meaningful(row))continue;shown++;
        NSString *name=ZN592Name(row,i);ZNFeatureControlType type=row.featureControlType;BOOL numeric=(type==ZNFeatureControlTypeNumber||type==ZNFeatureControlTypeSlider);BOOL hasAux=(type==ZNFeatureControlTypeSlider||type==ZNFeatureControlTypeSwitch||type==ZNFeatureControlTypeButton);CGFloat cardH=hasAux?286.0:244.0;UIView *card=[self cardAtY:y height:cardH width:width compact:NO];
        UILabel *idx=[self label:[NSString stringWithFormat:@"Offset 功能 %lu",(unsigned long)shown] size:10.5 weight:UIFontWeightBold color:self.theme.primaryTextColor];idx.frame=CGRectMake(13,7,120,28);[card addSubview:idx];UIButton *del=[self zn40_button:@"删除" selector:@selector(znm592u_deleteStatic:) frame:CGRectMake(card.bounds.size.width-60,6,48,28)];del.tag=kZN592DeleteBase+(NSInteger)i;del.enabled=!locked;[card addSubview:del];
        NSArray *labels=@[@"名称",@"说明",@"Offset"];NSArray *texts=@[name,ZN592Description(row),row.offsetText?:@""];NSArray *holders=@[@"例如：无限金币",@"例如：修改金币数量",@"0x123456"];NSInteger tags[]={kZN592NameBase+(NSInteger)i,kZN592DescBase+(NSInteger)i,kZN592OffsetBase+(NSInteger)i};SEL sels[]={@selector(znm592u_nameEnd:),@selector(znm592u_descEnd:),@selector(znm592u_offsetEnd:)};
        for(NSUInteger f=0;f<3;f++){CGFloat fy=39.0+f*42.0;UILabel *l=[self label:labels[f] size:9.4 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,fy,44,32);[card addSubview:l];UITextField *field=[self zn44_field:CGRectMake(58,fy,card.bounds.size.width-71,32) text:texts[f] placeholder:holders[f] tag:tags[f] enabled:!locked];ZN592ConfigureField(field);[field removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];[field addTarget:self action:sels[f] forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[card addSubview:field];}
        CGFloat controlsY=165.0,inner=card.bounds.size.width-26.0,gap=8.0;
        if(numeric){CGFloat bw=(inner-gap)/2.0;UIButton *tb=[self zn40_button:[NSString stringWithFormat:@"类型 · %@",ZNFeatureControlTypeName(type)] selector:@selector(znm592u_cycleType:) frame:CGRectMake(13,controlsY,bw,32)];tb.tag=kZN592TypeBase+(NSInteger)i;tb.enabled=!locked;[card addSubview:tb];UIButton *vb=[self zn40_button:[NSString stringWithFormat:@"数值 · %@",ZNValueTypeName(row.featureValueType)] selector:@selector(znm592u_cycleValueType:) frame:CGRectMake(13+bw+gap,controlsY,bw,32)];vb.tag=kZN592ValueTypeBase+(NSInteger)i;vb.enabled=!locked;[card addSubview:vb];}else{UIButton *tb=[self zn40_button:[NSString stringWithFormat:@"类型 · %@",ZNFeatureControlTypeName(type)] selector:@selector(znm592u_cycleType:) frame:CGRectMake(13,controlsY,inner,32)];tb.tag=kZN592TypeBase+(NSInteger)i;tb.enabled=!locked;[card addSubview:tb];}
        CGFloat statusY=205.0;
        if(hasAux){NSString *auxLabel=(type==ZNFeatureControlTypeSlider)?@"Max":@"Patch";NSString *auxText=@"",*placeholder=@"";if(type==ZNFeatureControlTypeSlider){double max=ZN592SliderMax(name);auxText=max>0?[NSString stringWithFormat:@"%.0f",max]:@"";placeholder=@"例如 99";}else{auxText=row.enabledText?:@"";placeholder=@"ARM64 HEX";}UILabel *al=[self label:auxLabel size:9.4 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];al.frame=CGRectMake(13,207,44,32);[card addSubview:al];UITextField *af=[self zn44_field:CGRectMake(58,207,card.bounds.size.width-71,32) text:auxText placeholder:placeholder tag:kZN592AuxBase+(NSInteger)i enabled:!locked];ZN592ConfigureField(af);[af removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];[af addTarget:self action:@selector(znm592u_auxEnd:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[card addSubview:af];statusY=247.0;}
        NSString *statusText=row.statusText.length?row.statusText:@"待填写";UILabel *status=[self label:statusText size:8.7 weight:UIFontWeightRegular color:ZN592StatusColor(statusText,self.theme.secondaryTextColor)];status.frame=CGRectMake(13,statusY,card.bounds.size.width-26,30);status.numberOfLines=2;[card addSubview:status];[self.contentView addSubview:card];y+=cardH+8.0;
    }

    UIView *addCard=[self cardAtY:y height:52 width:width compact:NO];UIButton *add=[self zn40_button:@"＋ 增加 Offset 功能" selector:@selector(znm592u_addStatic:) frame:CGRectMake(13,9,addCard.bounds.size.width-26,34)];add.enabled=!locked;[addCard addSubview:add];[self.contentView addSubview:addCard];y+=60.0;
    UIView *actionsCard=[self cardAtY:y height:92 width:width compact:NO];CGFloat gap=8.0,inner=actionsCard.bounds.size.width-26.0,bw=(inner-gap)/2.0;UIButton *apply=[self zn40_button:@"临时应用" selector:@selector(zn44_applyAll:) frame:CGRectMake(13,9,bw,34)];UIButton *restore=[self zn40_button:@"恢复全部" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13+bw+gap,9,bw,34)];UIButton *build=[self zn40_button:(w.isBuilding?@"正在生成…":@"生成新二进制") selector:@selector(zn44_buildBinary:) frame:CGRectMake(13,49,inner,34)];BOOL runtimeOnlyReady=actions.count>0&&w.filledCount==0;apply.enabled=!locked&&w.filledCount>0;restore.enabled=w.hasAnyApplied;build.enabled=!w.isBuilding&&!w.hasAnyApplied&&(w.filledCount>0||runtimeOnlyReady);[actionsCard addSubview:apply];[actionsCard addSubview:restore];[actionsCard addSubview:build];[self.contentView addSubview:actionsCard];y+=100.0;
    if(w.lastStatus.length){UIView *s=[self cardAtY:y height:58 width:width compact:NO];UILabel *l=[self label:w.lastStatus size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,8,s.bounds.size.width-26,42);l.numberOfLines=3;[s addSubview:l];[self.contentView addSubview:s];y+=66.0;}
    [self zn40_updateContentHeight:y+8.0];
}

- (void)znm592u_targetEnd:(UITextField *)field {[[ZNBinaryPatchWorkspace sharedWorkspace] updateDefaultTarget:field.text?:@""];[field resignFirstResponder];}
- (void)znm592u_nameEnd:(UITextField *)field {NSInteger idx=field.tag-kZN592NameBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];NSString *old=ZN592Name(row,(NSUInteger)idx),*next=ZN592Trim(field.text);if(!next.length){field.text=old;return;}if(row.featureControlType==ZNFeatureControlTypeSlider&&[old caseInsensitiveCompare:next]!=NSOrderedSame){double max=ZN592SliderMax(old);if(max>0){ZN592StoreSliderMax(next,max);ZN592StoreSliderMax(old,0);}}row.group=next;row.validated=NO;row.validator=nil;row.statusText=@"待自动准备";ZN592PersistStatic(w);[field resignFirstResponder];}
- (void)znm592u_descEnd:(UITextField *)field {NSInteger idx=field.tag-kZN592DescBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;w.rows[(NSUInteger)idx].title=field.text?:@"";ZN592PersistStatic(w);[field resignFirstResponder];}
- (void)znm592u_offsetEnd:(UITextField *)field {NSInteger idx=field.tag-kZN592OffsetBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;NSString *text=ZN592Trim(field.text);uint64_t rva=0;if(text.length&&ZN592ParseRVA(text,&rva)){text=[NSString stringWithFormat:@"0x%llX",rva];field.text=text;}[w updateOffset:text row:(NSUInteger)idx];[field resignFirstResponder];}
- (void)znm592u_auxEnd:(UITextField *)field {NSInteger idx=field.tag-kZN592AuxBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];if(row.featureControlType==ZNFeatureControlTypeSlider){NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:ZN592Trim(field.text) locale:@{NSLocaleDecimalSeparator:@"."}];double v=[n isEqualToNumber:NSDecimalNumber.notANumber]?0:n.doubleValue;ZN592StoreSliderMax(ZN592Name(row,(NSUInteger)idx),v);row.validated=NO;row.validator=nil;row.statusText=v>0?@"待自动准备":@"❌ Slider Max 必须大于 0";ZN592PersistStatic(w);}else if(row.featureControlType==ZNFeatureControlTypeSwitch||row.featureControlType==ZNFeatureControlTypeButton){[w updateEnabled:field.text?:@"" row:(NSUInteger)idx];}[field resignFirstResponder];}
- (void)znm592u_cycleType:(UIButton *)sender {NSInteger idx=sender.tag-kZN592TypeBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];ZNFeatureControlType next=ZN592NextStaticType(row.featureControlType);row.featureControlType=next;if(next==ZNFeatureControlTypeNumber||next==ZNFeatureControlTypeSlider)row.enabledText=@"";row.validated=NO;row.validator=nil;row.originalHex=@"";row.statusText=@"待自动准备";ZN592PersistStatic(w);[self renderPage];}
- (void)znm592u_cycleValueType:(UIButton *)sender {NSInteger idx=sender.tag-kZN592ValueTypeBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];row.featureValueType=ZN592NextValueType(row.featureValueType);row.validated=NO;row.validator=nil;row.statusText=@"待自动准备";ZN592PersistStatic(w);[self renderPage];}
- (void)znm592u_deleteStatic:(UIButton *)sender {NSInteger idx=sender.tag-kZN592DeleteBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(idx<0||(NSUInteger)idx>=w.rows.count)return;NSString *error=nil;if(![w removePatchAtGlobalIndex:(NSUInteger)idx error:&error])w.lastStatus=[NSString stringWithFormat:@"删除失败：%@",error?:@"未知错误"];[self renderPage];}
- (void)znm592u_addStatic:(id)sender {(void)sender;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(w.hasAnyApplied||w.isBuilding)return;NSString *name=[w addFeature];if(name.length){for(ZNBinaryPatchRow *row in w.rows.reverseObjectEnumerator){if([ZN592Trim(row.group) caseInsensitiveCompare:name]==NSOrderedSame){row.title=@"";row.featureControlType=ZNFeatureControlTypeNumber;row.featureValueType=ZNValueTypeAuto;row.enabledText=@"";row.statusText=@"待填写 Offset";break;}}ZN592PersistStatic(w);}[self renderPage];}

- (void)znm592u_clearRuntime:(id)sender {(void)sender;[[ZNRuntimeActionStore sharedStore] clear];[self renderPage];}
- (void)znm592u_deleteRuntime:(UIButton *)sender {NSInteger idx=sender.tag-kZN592RTDeleteBase;if(idx>=0)[[ZNRuntimeActionStore sharedStore] removeActionAtIndex:(NSUInteger)idx];[self renderPage];}
- (void)znm592u_runtimeTitleEnd:(UITextField *)field {NSInteger idx=field.tag-kZN592RTTitleBase;if(idx<0)return;NSString *error=nil;[[ZNRuntimeActionStore sharedStore] updateTitle:field.text atIndex:(NSUInteger)idx error:&error];[field resignFirstResponder];}
- (void)znm592u_runtimeArgEnd:(UITextField *)field {NSInteger slot=field.tag-kZN592RTArgBase;if(slot<0)return;NSUInteger actionIndex=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS,argIndex=(NSUInteger)slot%ZN_RUNTIME_ACTION_MAX_ARGUMENTS;NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if(actionIndex>=actions.count)return;ZNRuntimeMethodAction *action=actions[actionIndex];if(argIndex>=action.argumentCount)return;NSMutableArray *values=[NSMutableArray arrayWithCapacity:action.argumentCount];for(NSUInteger i=0;i<action.argumentCount;i++)[values addObject:(i<action.argumentValues.count?action.argumentValues[i]:@"")];values[argIndex]=field.text?:@"";[[ZNRuntimeActionStore sharedStore] updateArgumentValues:values atIndex:actionIndex error:nil];[field resignFirstResponder];}
- (void)znm592u_runtimeToggle:(UIButton *)sender {NSInteger slot=sender.tag-kZN592RTToggleBase;if(slot<0)return;NSUInteger ai=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS,ar=(NSUInteger)slot%ZN_RUNTIME_ACTION_MAX_ARGUMENTS;NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if(ai>=actions.count)return;ZNRuntimeMethodAction *action=actions[ai];if(ar>=action.argumentCount)return;NSMutableArray *cfgs=[ZN592RuntimeConfigs(action) mutableCopy];NSMutableDictionary *cfg=[cfgs[ar] mutableCopy];BOOL enabled=![cfg[@"enabled"] boolValue];cfg[@"enabled"]=@(enabled);cfg[@"type"]=enabled?@"number":@"fixed";cfgs[ar]=cfg;[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:cfgs atIndex:ai error:nil];[self renderPage];}
- (void)znm592u_runtimeCycleType:(UIButton *)sender {NSInteger slot=sender.tag-kZN592RTTypeBase;if(slot<0)return;NSUInteger ai=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS,ar=(NSUInteger)slot%ZN_RUNTIME_ACTION_MAX_ARGUMENTS;NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if(ai>=actions.count)return;ZNRuntimeMethodAction *action=actions[ai];if(ar>=action.argumentCount)return;NSMutableArray *cfgs=[ZN592RuntimeConfigs(action) mutableCopy];NSMutableDictionary *cfg=[cfgs[ar] mutableCopy];if(![cfg[@"enabled"] boolValue])return;ZNRuntimeArgumentControlType next=ZN592NextRuntimeType(ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]));cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(next);cfgs[ar]=cfg;[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:cfgs atIndex:ai error:nil];[self renderPage];}
- (void)znm592u_runtimeCycleValue:(UIButton *)sender {NSInteger slot=sender.tag-kZN592RTValueBase;if(slot<0)return;NSUInteger ai=(NSUInteger)slot/ZN_RUNTIME_ACTION_MAX_ARGUMENTS,ar=(NSUInteger)slot%ZN_RUNTIME_ACTION_MAX_ARGUMENTS;NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if(ai>=actions.count)return;ZNRuntimeMethodAction *action=actions[ai];if(ar>=action.argumentCount)return;NSMutableArray *cfgs=[ZN592RuntimeConfigs(action) mutableCopy];NSMutableDictionary *cfg=[cfgs[ar] mutableCopy];if(![cfg[@"enabled"] boolValue])return;ZNValueType cur=ZNValueTypeFromKey([cfg[@"valueType"] isKindOfClass:NSString.class]?cfg[@"valueType"]:@"auto");cfg[@"valueType"]=ZNValueTypeKey(ZN592NextValueType(cur));cfgs[ar]=cfg;[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:cfgs atIndex:ai error:nil];[self renderPage];}

@end

extern "C" void ZNInstallM592UnifiedOtherPageDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;
        Method unified=class_getInstanceMethod(cls,@selector(znm592u_renderOther));if(!unified)return;
        IMP canonical=method_getImplementation(unified);
        SEL selectors[]={@selector(zn44_renderOther),@selector(zn50b_renderOther),@selector(zn64fb_renderOther)};
        for(NSUInteger i=0;i<sizeof(selectors)/sizeof(selectors[0]);i++){Method m=class_getInstanceMethod(cls,selectors[i]);if(m)method_setImplementation(m,canonical);}
        [[ZNRuntimeLogger sharedLogger]log:@"[m5.9.2-unified-other] one canonical renderer owns Runtime + Offset authoring; unified keyboard Done behavior enabled"];
    });
}
