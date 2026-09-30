#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M5.9.2 UI cleanup.
// ZN_UI_CANONICAL_FEATURE_RENDERER
//
// Exactly one authoring implementation owns the Offset builder surface.
// Legacy Feature -> Patch renderers and M5.8.5/M5.9.0/M5.9.1 post-process
// render wrappers remain compiled for backend compatibility, but their legacy
// entry selectors are rebound to this one implementation at install time.
// This method never calls a previous renderer and never decorates an already
// rendered page.
//
// One workspace row == one visual feature card:
//   名称 / 说明 / Offset / 类型 / 数值类型 / (Max or Patch) / 状态 / 删除

static const NSInteger kZNM592FNameBase      = 776000;
static const NSInteger kZNM592FDescBase      = 777000;
static const NSInteger kZNM592FOffsetBase    = 778000;
static const NSInteger kZNM592FAuxBase       = 779000;
static const NSInteger kZNM592FTypeBase      = 780000;
static const NSInteger kZNM592FValueTypeBase = 781000;
static const NSInteger kZNM592FDeleteBase    = 782000;
static NSString * const kZNM592FSliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

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

static NSString *ZNM592FTrim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM592FMeaningful(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *g=ZNM592FTrim(row.group), *t=ZNM592FTrim(row.title);
    if (g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return YES;
    return t.length>0;
}

static NSString *ZNM592FName(ZNBinaryPatchRow *row, NSUInteger index) {
    NSString *g=ZNM592FTrim(row.group);
    if (g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return g;
    return [NSString stringWithFormat:@"新功能 %lu",(unsigned long)index+1];
}

static NSString *ZNM592FDescription(ZNBinaryPatchRow *row) {
    NSString *t=ZNM592FTrim(row.title);
    if ([t hasPrefix:@"Patch #"]) return @"";
    return t;
}

static NSString *ZNM592FSliderKey(NSString *name) {
    return [NSString stringWithFormat:@"%@.%@",kZNM592FSliderMaxPrefix,ZNM592FTrim(name).lowercaseString];
}

static double ZNM592FSliderMax(NSString *name) {
    id v=[NSUserDefaults.standardUserDefaults objectForKey:ZNM592FSliderKey(name)];
    return [v isKindOfClass:NSNumber.class]?[v doubleValue]:0.0;
}

static void ZNM592FStoreSliderMax(NSString *name,double value) {
    NSString *key=ZNM592FSliderKey(name);
    if(isfinite(value)&&value>0.0)[NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

static BOOL ZNM592FParseRVA(NSString *text,uint64_t *out) {
    NSString *s=ZNM592FTrim(text).lowercaseString;
    if(!s.length)return NO;
    const char *c=s.UTF8String;char *end=NULL;errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}
    if(errno||end==c||(end&&*end))return NO;
    if(out)*out=(uint64_t)v;
    return YES;
}

static ZNFeatureControlType ZNM592FNextControl(ZNFeatureControlType current) {
    switch(current){
        case ZNFeatureControlTypeNumber:return ZNFeatureControlTypeSlider;
        case ZNFeatureControlTypeSlider:return ZNFeatureControlTypeSwitch;
        case ZNFeatureControlTypeSwitch:return ZNFeatureControlTypeButton;
        case ZNFeatureControlTypeButton:
        default:return ZNFeatureControlTypeNumber;
    }
}

static ZNValueType ZNM592FNextValueType(ZNValueType current) {
    NSInteger n=(NSInteger)current+1;
    if(n>(NSInteger)ZNValueTypeF64)n=(NSInteger)ZNValueTypeAuto;
    return (ZNValueType)n;
}

static UIColor *ZNM592FStatusColor(NSString *text, UIColor *fallback) {
    if([text hasPrefix:@"❌"])return UIColor.systemRedColor;
    if([text hasPrefix:@"✅"])return UIColor.systemGreenColor;
    if([text hasPrefix:@"⚠"])return UIColor.systemOrangeColor;
    return fallback;
}

// Reuse M5.9.2's own persistence swizzles without introducing a second store.
// Updating the unchanged default target is intentionally side-effect free in
// the workspace but triggers M5.9.2's canonical save routine after direct row
// metadata edits (name/description/value type).
static void ZNM592FPersist(ZNBinaryPatchWorkspace *w) {
    [w updateDefaultTarget:w.defaultTarget ?: @"main"];
}

@interface ZNRuntimeMenuControllerV040 (ZNM592FlatAuthoring)
- (void)znm592f_renderOther;
- (void)znm592f_targetEnd:(UITextField *)field;
- (void)znm592f_nameEnd:(UITextField *)field;
- (void)znm592f_descEnd:(UITextField *)field;
- (void)znm592f_offsetEnd:(UITextField *)field;
- (void)znm592f_auxEnd:(UITextField *)field;
- (void)znm592f_cycleType:(UIButton *)sender;
- (void)znm592f_cycleValueType:(UIButton *)sender;
- (void)znm592f_delete:(UIButton *)sender;
- (void)znm592f_add:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM592FlatAuthoring)

- (void)znm592f_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    [w ensureDefaultRows];
    BOOL locked=w.hasAnyApplied||w.isBuilding;
    CGFloat width=CGRectGetWidth(self.contentView.bounds), y=9.0;

    UIView *targetCard=[self cardAtY:y height:54 width:width compact:NO];
    UILabel *binary=[self label:@"二进制" size:10.5 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    binary.frame=CGRectMake(13,11,48,32);[targetCard addSubview:binary];
    CGFloat importW=76.0;
    UITextField *target=[self zn44_field:CGRectMake(62,11,targetCard.bounds.size.width-62-importW-18,32)
                                    text:w.defaultTarget placeholder:@"UnityFramework" tag:440000 enabled:!locked];
    [target removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [target addTarget:self action:@selector(znm592f_targetEnd:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
    [targetCard addSubview:target];
    UIButton *import=[self zn40_button:(w.showJSONFiles?@"收起 JSON":@"导入 JSON") selector:@selector(zn44_importJSON:) frame:CGRectMake(targetCard.bounds.size.width-importW-9,11,importW,32)];
    import.enabled=!locked;[targetCard addSubview:import];
    [self.contentView addSubview:targetCard];y+=62;

    if(w.showJSONFiles){
        NSUInteger count=w.jsonFiles.count;CGFloat h=32.0+count*34.0;
        UIView *json=[self cardAtY:y height:h width:width compact:NO];
        UILabel *jt=[self label:[NSString stringWithFormat:@"同目录 JSON · %lu",(unsigned long)count] size:10 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        jt.frame=CGRectMake(13,7,json.bounds.size.width-26,18);[json addSubview:jt];
        for(NSUInteger i=0;i<count;i++){
            NSString *path=w.jsonFiles[i];UIButton *b=[self zn40_button:path.lastPathComponent selector:@selector(zn44_jsonTapped:) frame:CGRectMake(13,27+i*34,json.bounds.size.width-26,28)];
            b.tag=446000+(NSInteger)i;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;b.titleLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[json addSubview:b];
        }
        [self.contentView addSubview:json];y+=h+8;
    }

    NSUInteger shown=0;
    for(NSUInteger i=0;i<w.rows.count;i++){
        ZNBinaryPatchRow *row=w.rows[i];
        if(!ZNM592FMeaningful(row))continue;
        shown++;
        NSString *name=ZNM592FName(row,i);
        ZNFeatureControlType type=row.featureControlType;
        BOOL numeric=(type==ZNFeatureControlTypeNumber||type==ZNFeatureControlTypeSlider);
        BOOL hasAux=(type==ZNFeatureControlTypeSlider||type==ZNFeatureControlTypeSwitch||type==ZNFeatureControlTypeButton);
        CGFloat cardH=hasAux?286.0:244.0;
        UIView *card=[self cardAtY:y height:cardH width:width compact:NO];

        UILabel *idx=[self label:[NSString stringWithFormat:@"功能 %lu",(unsigned long)shown] size:10.5 weight:UIFontWeightBold color:self.theme.primaryTextColor];
        idx.frame=CGRectMake(13,7,80,28);[card addSubview:idx];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(znm592f_delete:) frame:CGRectMake(card.bounds.size.width-60,6,48,28)];
        del.tag=kZNM592FDeleteBase+(NSInteger)i;del.enabled=!locked;del.backgroundColor=[UIColor.systemRedColor colorWithAlphaComponent:.10];del.layer.borderColor=[UIColor.systemRedColor colorWithAlphaComponent:.65].CGColor;[card addSubview:del];

        NSArray *labels=@[@"名称",@"说明",@"Offset"];
        NSArray *texts=@[name,ZNM592FDescription(row),row.offsetText?:@""];
        NSArray *holders=@[@"例如：无限金币",@"例如：修改金币数量",@"0x123456"];
        NSInteger tags[]={kZNM592FNameBase+(NSInteger)i,kZNM592FDescBase+(NSInteger)i,kZNM592FOffsetBase+(NSInteger)i};
        SEL sels[]={@selector(znm592f_nameEnd:),@selector(znm592f_descEnd:),@selector(znm592f_offsetEnd:)};
        for(NSUInteger f=0;f<3;f++){
            CGFloat fy=39.0+f*42.0;
            UILabel *l=[self label:labels[f] size:9.4 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,fy,44,32);[card addSubview:l];
            UITextField *field=[self zn44_field:CGRectMake(58,fy,card.bounds.size.width-71,32) text:texts[f] placeholder:holders[f] tag:tags[f] enabled:!locked];
            [field removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
            field.autocorrectionType=UITextAutocorrectionTypeNo;field.autocapitalizationType=UITextAutocapitalizationTypeNone;
            if(f==2)field.keyboardType=UIKeyboardTypeASCIICapable;
            [field addTarget:self action:sels[f] forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
            [card addSubview:field];
        }

        CGFloat controlsY=165.0;
        CGFloat inner=card.bounds.size.width-26.0,gap=8.0;
        if(numeric){
            CGFloat bw=(inner-gap)/2.0;
            UIButton *typeBtn=[self zn40_button:[NSString stringWithFormat:@"类型 · %@",ZNFeatureControlTypeName(type)] selector:@selector(znm592f_cycleType:) frame:CGRectMake(13,controlsY,bw,32)];
            typeBtn.tag=kZNM592FTypeBase+(NSInteger)i;typeBtn.enabled=!locked;typeBtn.titleLabel.adjustsFontSizeToFitWidth=YES;typeBtn.titleLabel.minimumScaleFactor=.65;[card addSubview:typeBtn];
            UIButton *valueBtn=[self zn40_button:[NSString stringWithFormat:@"数值 · %@",ZNValueTypeName(row.featureValueType)] selector:@selector(znm592f_cycleValueType:) frame:CGRectMake(13+bw+gap,controlsY,bw,32)];
            valueBtn.tag=kZNM592FValueTypeBase+(NSInteger)i;valueBtn.enabled=!locked;valueBtn.titleLabel.adjustsFontSizeToFitWidth=YES;valueBtn.titleLabel.minimumScaleFactor=.62;[card addSubview:valueBtn];
        }else{
            UIButton *typeBtn=[self zn40_button:[NSString stringWithFormat:@"类型 · %@",ZNFeatureControlTypeName(type)] selector:@selector(znm592f_cycleType:) frame:CGRectMake(13,controlsY,inner,32)];
            typeBtn.tag=kZNM592FTypeBase+(NSInteger)i;typeBtn.enabled=!locked;[card addSubview:typeBtn];
        }

        CGFloat statusY=205.0;
        if(hasAux){
            NSString *auxLabel=(type==ZNFeatureControlTypeSlider)?@"Max":@"Patch";
            NSString *auxText=@"",*placeholder=@"";
            if(type==ZNFeatureControlTypeSlider){double max=ZNM592FSliderMax(name);auxText=max>0?[NSString stringWithFormat:@"%.0f",max]:@"";placeholder=@"例如 99";}
            else {auxText=row.enabledText?:@"";placeholder=@"ARM64 HEX";}
            UILabel *al=[self label:auxLabel size:9.4 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];al.frame=CGRectMake(13,207,44,32);[card addSubview:al];
            UITextField *af=[self zn44_field:CGRectMake(58,207,card.bounds.size.width-71,32) text:auxText placeholder:placeholder tag:kZNM592FAuxBase+(NSInteger)i enabled:!locked];
            [af removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
            af.keyboardType=(type==ZNFeatureControlTypeSlider)?UIKeyboardTypeNumberPad:UIKeyboardTypeASCIICapable;
            af.autocorrectionType=UITextAutocorrectionTypeNo;af.autocapitalizationType=UITextAutocapitalizationTypeNone;
            [af addTarget:self action:@selector(znm592f_auxEnd:) forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];[card addSubview:af];
            statusY=247.0;
        }

        NSString *statusText=row.statusText.length?row.statusText:@"待填写";
        UILabel *status=[self label:statusText size:8.7 weight:UIFontWeightRegular color:ZNM592FStatusColor(statusText,self.theme.secondaryTextColor)];
        status.frame=CGRectMake(13,statusY,card.bounds.size.width-26,30);status.numberOfLines=2;[card addSubview:status];
        [self.contentView addSubview:card];y+=cardH+8.0;
    }

    UIView *addCard=[self cardAtY:y height:52 width:width compact:NO];
    UIButton *add=[self zn40_button:@"＋ 增加功能" selector:@selector(znm592f_add:) frame:CGRectMake(13,9,addCard.bounds.size.width-26,34)];
    add.enabled=!locked;[addCard addSubview:add];[self.contentView addSubview:addCard];y+=60;

    UIView *actions=[self cardAtY:y height:92 width:width compact:NO];
    CGFloat gap=8.0,inner=actions.bounds.size.width-26.0,bw=(inner-gap)/2.0;
    UIButton *apply=[self zn40_button:@"临时应用" selector:@selector(zn44_applyAll:) frame:CGRectMake(13,9,bw,34)];
    UIButton *restore=[self zn40_button:@"恢复全部" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13+bw+gap,9,bw,34)];
    UIButton *build=[self zn40_button:(w.isBuilding?@"正在生成…":@"生成新二进制") selector:@selector(zn44_buildBinary:) frame:CGRectMake(13,49,inner,34)];
    apply.enabled=!locked&&w.filledCount>0;restore.enabled=w.hasAnyApplied;build.enabled=!w.isBuilding&&!w.hasAnyApplied&&w.filledCount>0;
    [actions addSubview:apply];[actions addSubview:restore];[actions addSubview:build];[self.contentView addSubview:actions];y+=100;

    if(w.lastStatus.length){UIView *s=[self cardAtY:y height:58 width:width compact:NO];UILabel *l=[self label:w.lastStatus size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,8,s.bounds.size.width-26,42);l.numberOfLines=3;[s addSubview:l];[self.contentView addSubview:s];y+=66;}
    [self zn40_updateContentHeight:y+8.0];
}

- (void)znm592f_targetEnd:(UITextField *)field {
    [[ZNBinaryPatchWorkspace sharedWorkspace] updateDefaultTarget:field.text?:@""];
}

- (void)znm592f_nameEnd:(UITextField *)field {
    NSInteger idx=field.tag-kZNM592FNameBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];
    NSString *old=ZNM592FName(row,(NSUInteger)idx),*next=ZNM592FTrim(field.text);
    if(!next.length){field.text=old;return;}
    if(row.featureControlType==ZNFeatureControlTypeSlider&&[old caseInsensitiveCompare:next]!=NSOrderedSame){double max=ZNM592FSliderMax(old);if(max>0){ZNM592FStoreSliderMax(next,max);ZNM592FStoreSliderMax(old,0);}}
    row.group=next;row.validated=NO;row.validator=nil;row.statusText=@"待自动准备";ZNM592FPersist(w);
}

- (void)znm592f_descEnd:(UITextField *)field {
    NSInteger idx=field.tag-kZNM592FDescBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;w.rows[(NSUInteger)idx].title=field.text?:@"";ZNM592FPersist(w);
}

- (void)znm592f_offsetEnd:(UITextField *)field {
    NSInteger idx=field.tag-kZNM592FOffsetBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;
    NSString *text=ZNM592FTrim(field.text);uint64_t rva=0;
    if(text.length&&ZNM592FParseRVA(text,&rva)){text=[NSString stringWithFormat:@"0x%llX",rva];field.text=text;}
    [w updateOffset:text row:(NSUInteger)idx];
}

- (void)znm592f_auxEnd:(UITextField *)field {
    NSInteger idx=field.tag-kZNM592FAuxBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];
    if(row.featureControlType==ZNFeatureControlTypeSlider){
        NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:ZNM592FTrim(field.text) locale:@{NSLocaleDecimalSeparator:@"."}];
        double value=[n isEqualToNumber:NSDecimalNumber.notANumber]?0.0:n.doubleValue;ZNM592FStoreSliderMax(ZNM592FName(row,(NSUInteger)idx),value);row.validated=NO;row.validator=nil;row.statusText=value>0?@"待自动准备":@"❌ Slider Max 必须大于 0";ZNM592FPersist(w);
    }else if(row.featureControlType==ZNFeatureControlTypeSwitch||row.featureControlType==ZNFeatureControlTypeButton){
        [w updateEnabled:field.text?:@"" row:(NSUInteger)idx];
    }
}

- (void)znm592f_cycleType:(UIButton *)sender {
    NSInteger idx=sender.tag-kZNM592FTypeBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];
    ZNFeatureControlType next=ZNM592FNextControl(row.featureControlType);row.featureControlType=next;
    if(next==ZNFeatureControlTypeNumber||next==ZNFeatureControlTypeSlider)row.enabledText=@"";
    row.validated=NO;row.validator=nil;row.originalHex=@"";row.statusText=@"待自动准备";ZNM592FPersist(w);[self renderPage];
}

- (void)znm592f_cycleValueType:(UIButton *)sender {
    NSInteger idx=sender.tag-kZNM592FValueTypeBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)idx];
    row.featureValueType=ZNM592FNextValueType(row.featureValueType);row.validated=NO;row.validator=nil;row.statusText=@"待自动准备";ZNM592FPersist(w);[self renderPage];
}

- (void)znm592f_delete:(UIButton *)sender {
    NSInteger idx=sender.tag-kZNM592FDeleteBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(idx<0||(NSUInteger)idx>=w.rows.count)return;NSString *error=nil;
    if(![w removePatchAtGlobalIndex:(NSUInteger)idx error:&error])w.lastStatus=[NSString stringWithFormat:@"删除失败：%@",error?:@"未知错误"];
    [self renderPage];
}

- (void)znm592f_add:(id)sender {
    (void)sender;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(w.hasAnyApplied||w.isBuilding)return;
    NSString *name=[w addFeature];
    if(name.length){
        for(ZNBinaryPatchRow *row in w.rows.reverseObjectEnumerator){if([ZNM592FTrim(row.group) caseInsensitiveCompare:name]==NSOrderedSame){row.title=@"";row.featureControlType=ZNFeatureControlTypeNumber;row.featureValueType=ZNValueTypeAuto;row.enabledText=@"";row.statusText=@"待填写 Offset";break;}}
        ZNM592FPersist(w);
    }
    [self renderPage];
}

@end

extern "C" void ZNInstallM592FlatAuthoringDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;
        Method flat=class_getInstanceMethod(cls,@selector(znm592f_renderOther));if(!flat)return;
        IMP canonical=method_getImplementation(flat);
        // Bind every historical authoring entry selector to the same canonical
        // implementation. No legacy wrapper remains reachable from rendering.
        SEL selectors[]={@selector(zn44_renderOther),@selector(zn50b_renderOther),@selector(zn64fb_renderOther)};
        for(NSUInteger i=0;i<sizeof(selectors)/sizeof(selectors[0]);i++){
            Method m=class_getInstanceMethod(cls,selectors[i]);if(m)method_setImplementation(m,canonical);
        }
        [[ZNRuntimeLogger sharedLogger]log:@"[m5.9.2-flat-ui] canonical single authoring renderer installed; Feature/Patch nesting and post-render wrappers bypassed"];
    });
}
