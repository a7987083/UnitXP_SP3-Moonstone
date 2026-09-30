#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M6.2.1 — Flat Offset Authoring.
// One canonical authoring renderer only. No Feature -> Patch nesting, no
// post-render decoration, no secondary authoring surface.
//
// One row == one feature card:
//   名称 / 说明 / Offset / 类型 / (Max or Patch) / 状态 / 删除
// Number: Offset only, no authored Patch.
// Slider: Offset + Max, no authored Patch.
// Switch/Button: Offset + authored Patch HEX.

static const NSInteger kZNM621NameBase   = 760000;
static const NSInteger kZNM621DescBase   = 761000;
static const NSInteger kZNM621OffsetBase = 762000;
static const NSInteger kZNM621AuxBase    = 763000;
static const NSInteger kZNM621TypeBase   = 764000;
static const NSInteger kZNM621DeleteBase = 765000;
static NSString * const kZNM621SliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

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
- (void)zn44_validateAll:(id)sender;
- (void)zn44_applyAll:(id)sender;
- (void)zn44_restoreAll:(id)sender;
- (void)zn44_buildBinary:(id)sender;
@end

static NSString *ZNM621Trim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM621Meaningful(ZNBinaryPatchRow *row) {
    NSString *g=ZNM621Trim(row.group),*t=ZNM621Trim(row.title);
    return row.offsetText.length || row.enabledText.length ||
           (g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) || t.length;
}

static NSString *ZNM621FeatureName(ZNBinaryPatchRow *row, NSUInteger index) {
    NSString *g=ZNM621Trim(row.group);
    if(g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return g;
    return [NSString stringWithFormat:@"新功能 %lu",(unsigned long)index+1];
}

static NSString *ZNM621SliderKey(NSString *name) {
    return [NSString stringWithFormat:@"%@.%@",kZNM621SliderMaxPrefix,ZNM621Trim(name).lowercaseString];
}

static double ZNM621SliderMax(NSString *name) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:ZNM621SliderKey(name)];
    return [value isKindOfClass:NSNumber.class]?[value doubleValue]:0.0;
}

static void ZNM621StoreSliderMax(NSString *name,double value) {
    NSString *key=ZNM621SliderKey(name);
    if(isfinite(value)&&value>0.0)[NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

static ZNFeatureControlType ZNM621NextType(ZNFeatureControlType current) {
    switch(current) {
        case ZNFeatureControlTypeNumber: return ZNFeatureControlTypeSlider;
        case ZNFeatureControlTypeSlider: return ZNFeatureControlTypeSwitch;
        case ZNFeatureControlTypeSwitch: return ZNFeatureControlTypeButton;
        case ZNFeatureControlTypeButton:
        default: return ZNFeatureControlTypeNumber;
    }
}

static UIColor *ZNM621StatusColor(NSString *text, UIColor *fallback) {
    if([text hasPrefix:@"❌"])return UIColor.systemRedColor;
    if([text hasPrefix:@"✅"])return UIColor.systemGreenColor;
    if([text hasPrefix:@"⚠"])return UIColor.systemOrangeColor;
    return fallback;
}

@interface ZNRuntimeMenuControllerV040 (ZNM621FlatOffsetAuthoring)
- (void)znm621_renderOther;
- (void)znm621_addFeature:(id)sender;
- (void)znm621_nameChanged:(UITextField *)field;
- (void)znm621_descChanged:(UITextField *)field;
- (void)znm621_offsetChanged:(UITextField *)field;
- (void)znm621_auxChanged:(UITextField *)field;
- (void)znm621_cycleType:(UIButton *)sender;
- (void)znm621_delete:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM621FlatOffsetAuthoring)

- (void)znm621_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    [w ensureDefaultRows];
    BOOL locked=w.hasAnyApplied||w.isBuilding;
    CGFloat width=CGRectGetWidth(self.contentView.bounds), y=9.0;

    UIView *targetCard=[self cardAtY:y height:54 width:width compact:NO];
    UILabel *tl=[self label:@"二进制" size:10.5 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    tl.frame=CGRectMake(13,11,48,30);[targetCard addSubview:tl];
    UITextField *target=[self zn44_field:CGRectMake(62,11,targetCard.bounds.size.width-75,32)
                                    text:w.defaultTarget placeholder:@"UnityFramework" tag:440000 enabled:!locked];
    [target addTarget:self action:@selector(znm621_offsetChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [targetCard addSubview:target];[self.contentView addSubview:targetCard];y+=62;

    NSUInteger shown=0;
    for(NSUInteger i=0;i<w.rows.count;i++) {
        ZNBinaryPatchRow *row=w.rows[i];
        if(!ZNM621Meaningful(row))continue;
        shown++;
        ZNFeatureControlType type=row.featureControlType;
        NSString *name=ZNM621FeatureName(row,i);
        CGFloat cardH=(type==ZNFeatureControlTypeNumber)?214.0:258.0;
        UIView *card=[self cardAtY:y height:cardH width:width compact:NO];

        UILabel *idx=[self label:[NSString stringWithFormat:@"功能 %lu",(unsigned long)shown] size:10.5 weight:UIFontWeightBold color:self.theme.primaryTextColor];
        idx.frame=CGRectMake(13,8,70,24);[card addSubview:idx];
        UIButton *typeButton=[self zn40_button:[NSString stringWithFormat:@"类型 · %@",ZNFeatureControlTypeName(type)] selector:@selector(znm621_cycleType:) frame:CGRectMake(card.bounds.size.width-164,6,104,28)];
        typeButton.tag=kZNM621TypeBase+(NSInteger)i;typeButton.enabled=!locked;typeButton.titleLabel.adjustsFontSizeToFitWidth=YES;typeButton.titleLabel.minimumScaleFactor=.65;[card addSubview:typeButton];
        UIButton *del=[self zn40_button:@"删除" selector:@selector(znm621_delete:) frame:CGRectMake(card.bounds.size.width-54,6,44,28)];
        del.tag=kZNM621DeleteBase+(NSInteger)i;del.enabled=!locked;del.backgroundColor=[UIColor.systemRedColor colorWithAlphaComponent:.10];del.layer.borderColor=[UIColor.systemRedColor colorWithAlphaComponent:.65].CGColor;[card addSubview:del];

        NSArray *labels=@[@"名称",@"说明",@"Offset"];
        NSArray *texts=@[name,ZNM621Trim(row.title),row.offsetText?:@""];
        NSArray *holders=@[@"例如：无限金币",@"例如：修改金币数量",@"0x123456"];
        NSInteger bases[]={kZNM621NameBase,kZNM621DescBase,kZNM621OffsetBase};
        SEL actions[]={@selector(znm621_nameChanged:),@selector(znm621_descChanged:),@selector(znm621_offsetChanged:)};
        for(NSUInteger f=0;f<3;f++){
            CGFloat fy=39.0+f*42.0;
            UILabel *l=[self label:labels[f] size:9.4 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,fy,44,32);[card addSubview:l];
            UITextField *field=[self zn44_field:CGRectMake(58,fy,card.bounds.size.width-71,32) text:texts[f] placeholder:holders[f] tag:bases[f]+(NSInteger)i enabled:!locked];
            [field addTarget:self action:actions[f] forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];[card addSubview:field];
        }

        CGFloat statusY=168.0;
        if(type!=ZNFeatureControlTypeNumber){
            NSString *auxLabel=(type==ZNFeatureControlTypeSlider)?@"Max":@"Patch";
            NSString *auxText=@"";NSString *auxPlaceholder=@"";
            if(type==ZNFeatureControlTypeSlider){double max=ZNM621SliderMax(name);auxText=max>0?[NSString stringWithFormat:@"%.0f",max]:@"";auxPlaceholder=@"例如 99";}
            else {auxText=row.enabledText?:@"";auxPlaceholder=@"ARM64 HEX";}
            UILabel *al=[self label:auxLabel size:9.4 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];al.frame=CGRectMake(13,165,44,32);[card addSubview:al];
            UITextField *af=[self zn44_field:CGRectMake(58,165,card.bounds.size.width-71,32) text:auxText placeholder:auxPlaceholder tag:kZNM621AuxBase+(NSInteger)i enabled:!locked];
            af.keyboardType=(type==ZNFeatureControlTypeSlider)?UIKeyboardTypeNumberPad:UIKeyboardTypeASCIICapable;
            [af addTarget:self action:@selector(znm621_auxChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];[card addSubview:af];
            statusY=210.0;
        }
        UILabel *status=[self label:(row.statusText.length?row.statusText:@"待填写") size:8.8 weight:UIFontWeightRegular color:ZNM621StatusColor(row.statusText,self.theme.secondaryTextColor)];
        status.frame=CGRectMake(13,statusY,card.bounds.size.width-26,34);status.numberOfLines=2;[card addSubview:status];
        [self.contentView addSubview:card];y+=cardH+8.0;
    }

    UIView *addCard=[self cardAtY:y height:52 width:width compact:NO];
    UIButton *add=[self zn40_button:@"＋ 增加功能" selector:@selector(znm621_addFeature:) frame:CGRectMake(13,9,addCard.bounds.size.width-26,34)];add.enabled=!locked;[addCard addSubview:add];[self.contentView addSubview:addCard];y+=60;

    UIView *actions=[self cardAtY:y height:92 width:width compact:NO];
    CGFloat gap=8.0, inner=actions.bounds.size.width-26, bw=(inner-gap)/2.0;
    UIButton *validate=[self zn40_button:@"读取验证" selector:@selector(zn44_validateAll:) frame:CGRectMake(13,9,bw,34)];
    UIButton *apply=[self zn40_button:@"临时应用" selector:@selector(zn44_applyAll:) frame:CGRectMake(13+bw+gap,9,bw,34)];
    UIButton *restore=[self zn40_button:@"恢复全部" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13,49,bw,34)];
    UIButton *build=[self zn40_button:(w.isBuilding?@"正在生成…":@"生成新二进制") selector:@selector(zn44_buildBinary:) frame:CGRectMake(13+bw+gap,49,bw,34)];
    validate.enabled=!locked;apply.enabled=!locked&&w.filledCount>0;restore.enabled=w.hasAnyApplied;build.enabled=!w.isBuilding&&!w.hasAnyApplied&&w.filledCount>0;
    [actions addSubview:validate];[actions addSubview:apply];[actions addSubview:restore];[actions addSubview:build];[self.contentView addSubview:actions];y+=100;

    if(w.lastStatus.length){UIView *s=[self cardAtY:y height:58 width:width compact:NO];UILabel *l=[self label:w.lastStatus size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];l.frame=CGRectMake(13,8,s.bounds.size.width-26,42);l.numberOfLines=3;[s addSubview:l];[self.contentView addSubview:s];y+=66;}
    [self zn40_updateContentHeight:y+8];
}

- (void)znm621_addFeature:(id)sender {
    (void)sender;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(w.hasAnyApplied||w.isBuilding)return;
    NSUInteger slot=NSNotFound;for(NSUInteger i=0;i<w.rows.count;i++){if(!ZNM621Meaningful(w.rows[i])){slot=i;break;}}
    ZNBinaryPatchRow *row=nil;if(slot==NSNotFound){row=[ZNBinaryPatchRow new];[w.rows addObject:row];slot=w.rows.count-1;}else row=w.rows[slot];
    row.group=[NSString stringWithFormat:@"新功能 %lu",(unsigned long)(w.filledCount+1)];row.title=@"";row.featureControlType=ZNFeatureControlTypeNumber;row.featureValueType=ZNValueTypeAuto;row.enabledText=@"";row.statusText=@"待填写 Offset";w.lastStatus=@"已增加功能";[self renderPage];
}

- (void)znm621_nameChanged:(UITextField *)field {
    NSInteger i=field.tag-kZNM621NameBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(i<0||(NSUInteger)i>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)i];NSString *old=ZNM621FeatureName(row,(NSUInteger)i),*next=ZNM621Trim(field.text);if(!next.length)return;
    if([old caseInsensitiveCompare:next]!=NSOrderedSame&&row.featureControlType==ZNFeatureControlTypeSlider){double max=ZNM621SliderMax(old);if(max>0){ZNM621StoreSliderMax(next,max);ZNM621StoreSliderMax(old,0);}}
    row.group=next;row.validated=NO;row.validator=nil;row.statusText=@"待验证";
}

- (void)znm621_descChanged:(UITextField *)field {
    NSInteger i=field.tag-kZNM621DescBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(i<0||(NSUInteger)i>=w.rows.count)return;w.rows[(NSUInteger)i].title=field.text?:@"";
}

- (void)znm621_offsetChanged:(UITextField *)field {
    ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(field.tag==440000){[w updateDefaultTarget:field.text?:@""];return;}
    NSInteger i=field.tag-kZNM621OffsetBase;if(i<0||(NSUInteger)i>=w.rows.count)return;[w updateOffset:field.text?:@"" row:(NSUInteger)i];
}

- (void)znm621_auxChanged:(UITextField *)field {
    NSInteger i=field.tag-kZNM621AuxBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(i<0||(NSUInteger)i>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)i];
    if(row.featureControlType==ZNFeatureControlTypeSlider){NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:ZNM621Trim(field.text) locale:@{NSLocaleDecimalSeparator:@"."}];double v=[n isEqualToNumber:NSDecimalNumber.notANumber]?0:n.doubleValue;ZNM621StoreSliderMax(ZNM621FeatureName(row,(NSUInteger)i),v);row.validated=NO;row.validator=nil;row.statusText=v>0?@"待验证":@"❌ Slider Max 必须大于 0";}
    else if(row.featureControlType==ZNFeatureControlTypeSwitch||row.featureControlType==ZNFeatureControlTypeButton){[w updateEnabled:field.text?:@"" row:(NSUInteger)i];}
}

- (void)znm621_cycleType:(UIButton *)sender {
    NSInteger i=sender.tag-kZNM621TypeBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(i<0||(NSUInteger)i>=w.rows.count)return;ZNBinaryPatchRow *row=w.rows[(NSUInteger)i];row.featureControlType=ZNM621NextType(row.featureControlType);row.validated=NO;row.validator=nil;row.originalHex=@"";if(row.featureControlType==ZNFeatureControlTypeNumber||row.featureControlType==ZNFeatureControlTypeSlider)row.enabledText=@"";row.statusText=@"待验证";[self renderPage];
}

- (void)znm621_delete:(UIButton *)sender {
    NSInteger i=sender.tag-kZNM621DeleteBase;ZNBinaryPatchWorkspace *w=[ZNBinaryPatchWorkspace sharedWorkspace];if(i<0||(NSUInteger)i>=w.rows.count||w.hasAnyApplied||w.isBuilding)return;[w.rows removeObjectAtIndex:(NSUInteger)i];[w ensureDefaultRows];w.lastStatus=@"已删除功能";[self renderPage];
}
@end

extern "C" void ZNInstallM621FlatOffsetAuthoringDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;
        Method a=class_getInstanceMethod(cls,@selector(zn44_renderOther));
        Method b=class_getInstanceMethod(cls,@selector(znm621_renderOther));
        if(a&&b)method_exchangeImplementations(a,b);
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.2.1-ui] canonical flat Offset authoring installed: one row = one feature; description field restored; no Feature/Patch nesting"];
    });
}
