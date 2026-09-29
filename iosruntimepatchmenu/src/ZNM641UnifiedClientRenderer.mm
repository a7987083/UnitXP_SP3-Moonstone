#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNRangeControl.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// ZN_UI_CANONICAL_FEATURE_RENDERER
// M6.4.1: one customer Feature renderer owns BOTH Static and Runtime records.
// No second Feature renderer, no post-render decoration, no runtime append pass.

static const NSInteger kM641StaticToggle = 610000;
static const NSInteger kM641StaticNumber = 611000;
static const NSInteger kM641StaticExec   = 612000;
static const NSInteger kM641StaticSlider = 613000;
static const NSInteger kM641StaticValue  = 614000;
static const NSInteger kM641RuntimeExec  = 620000;
static const NSInteger kM641RuntimeField = 621000;
static const NSInteger kM641RuntimeSwitch= 622000;
static const NSInteger kM641RuntimeSlider= 623000;
static const NSInteger kM641RuntimeValue = 624000;
static NSString * const kM641RuntimeValuesKey = @"zonoe.m5.8.2.runtime-values.v1";

@interface ZNStaticPatchRecord (M641Entry)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderFullPage;
- (void)renderCompactPage;
- (void)renderPage;
- (void)znm58_numberChanged:(UITextField *)field;
- (void)znm58_numberReturn:(UITextField *)field;
- (void)znm58_switchChanged:(UISwitch *)control;
- (void)znm58_sliderChanged:(ZNRangeControl *)control;
- (void)znm58_sliderCommitted:(ZNRangeControl *)control;
- (void)znm58_execute:(UIButton *)sender;
@end

static NSString *M641Trim(NSString *s){return [(s?:@"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *M641StaticPref(NSDictionary *feature,NSString *suffix){uint64_t fid=[feature[@"featureID"] unsignedLongLongValue];NSString *idn=fid?[NSString stringWithFormat:@"%016llx",fid]:[feature[@"key"] description];return [NSString stringWithFormat:@"zn.fc.%@.%@",idn?:@"feature",suffix?:@"value"];}

static NSDictionary *M641StaticMeta(ZNStaticPatchRecord *record){
    NSDictionary *m=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;
    if(m)return m;
    NSString *title=M641Trim(record.title),*group=M641Trim(record.group);
    if(!title.length||[title hasPrefix:@"Patch #"])title=[NSString stringWithFormat:@"功能 #%u",record.patchID];
    if(!group.length)group=@"Imported";
    return @{@"featureID":@0,@"title":title,@"group":group,@"explicitGroup":@([group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)};
}

static NSArray<NSDictionary *> *M641StaticFeatures(void){
    ZNStaticDispatchRuntime *rt=[ZNStaticDispatchRuntime sharedRuntime];[rt refresh];
    NSMutableArray *order=[NSMutableArray array];NSMutableDictionary *members=[NSMutableDictionary dictionary],*meta=[NSMutableDictionary dictionary];
    for(ZNStaticPatchRecord *r in rt.records){
        NSDictionary *m=M641StaticMeta(r);NSString *group=M641Trim(m[@"group"]),*title=M641Trim(m[@"title"]);uint64_t fid=[m[@"featureID"] unsignedLongLongValue];BOOL explicit=[m[@"explicitGroup"] boolValue]||(group.length&&[group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame);NSString *key=fid?[NSString stringWithFormat:@"id:%016llx",fid]:(explicit?[@"group:" stringByAppendingString:group.lowercaseString]:[NSString stringWithFormat:@"patch:%@:%u",r.target.lowercaseString?:@"",r.patchID]);
        if(!members[key]){members[key]=[NSMutableArray array];ZNFeatureControlType ct=r.entry?ZNFeatureControlTypeFromFlags(r.entry->flags):ZNFeatureControlTypeSwitch;ZNValueType vt=r.entry?ZNFeatureValueTypeFromFlags(r.entry->flags):ZNValueTypeAuto;NSString *display=explicit&&group.length?group:(title.length?title:@"功能");NSString *desc=(explicit&&title.length&&[title caseInsensitiveCompare:display]!=NSOrderedSame)?title:@"";meta[key]=[@{@"key":key,@"featureID":@(fid),@"title":display,@"description":desc,@"controlType":@(ct),@"valueType":@(vt)} mutableCopy];[order addObject:key];}
        [members[key] addObject:r];
    }
    NSMutableArray *out=[NSMutableArray array];for(NSString *key in order){NSMutableDictionary *d=[meta[key] mutableCopy];d[@"records"]=[members[key] copy];[out addObject:[d copy]];}return out;
}

static BOOL M641AllStaticEnabled(NSArray<ZNStaticPatchRecord *> *records){if(!records.count)return NO;for(ZNStaticPatchRecord *r in records)if(!r.enabled)return NO;return YES;}
static BOOL M641SetStatic(NSArray<ZNStaticPatchRecord *> *records,BOOL enabled,NSString **error){ZNStaticDispatchRuntime *rt=[ZNStaticDispatchRuntime sharedRuntime];for(ZNStaticPatchRecord *r in records){if(r.enabled==enabled)continue;NSString *e=nil;if(![rt setEnabled:enabled forRecord:r error:&e]){if(error)*error=e?:@"Static toggle failed";return NO;}}return YES;}
static NSDictionary *M641StaticEvent(NSDictionary *f,NSString *text){NSMutableDictionary *d=[@{@"featureID":f[@"featureID"]?:@0,@"title":f[@"title"]?:@"功能",@"controlType":f[@"controlType"]?:@(ZNFeatureControlTypeSwitch),@"valueType":f[@"valueType"]?:@(ZNValueTypeAuto),@"key":f[@"key"]?:@""} mutableCopy];if(text.length){d[@"valueText"]=text;d[@"value"]=@(text.doubleValue);}return d;}

static NSString *M641RuntimeKey(ZNRuntimeMethodActionRecord *r){NSString *identity=r.canonicalIdentity.length?r.canonicalIdentity:[NSString stringWithFormat:@"%@::%@/%lu",r.className?:@"",r.methodName?:@"",(unsigned long)r.argumentCount];NSString *cfg=r.argumentControlConfigs.description?:@"";return [NSString stringWithFormat:@"%@|%@",identity,cfg];}
static NSArray<ZNRuntimeMethodActionRecord *> *M641RuntimeRecords(void){ZNRuntimeActionRuntime *rt=[ZNRuntimeActionRuntime sharedRuntime];[rt refresh];NSMutableArray *out=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];for(ZNRuntimeMethodActionRecord *r in rt.records?:@[]){NSString *key=M641RuntimeKey(r);if([seen containsObject:key])continue;[seen addObject:key];[out addObject:r];}return out;}
static NSString *M641RecordKey(ZNRuntimeMethodActionRecord *r){NSString *idn=r.canonicalIdentity.length?r.canonicalIdentity:[NSString stringWithFormat:@"%@::%@/%lu",r.className?:@"",r.methodName?:@"",(unsigned long)r.argumentCount];return [NSString stringWithFormat:@"%u|%@",r.actionID,idn];}
static NSArray<NSString *> *M641StoredValues(ZNRuntimeMethodActionRecord *r){NSDictionary *root=[NSUserDefaults.standardUserDefaults objectForKey:kM641RuntimeValuesKey];if(![root isKindOfClass:NSDictionary.class])return nil;NSArray *v=root[M641RecordKey(r)];return [v isKindOfClass:NSArray.class]&&v.count==r.argumentCount?v:nil;}
static double M641Quantize(double value,NSDictionary *cfg,double fmin,double fmax){double mn=[cfg[@"min"]doubleValue],mx=[cfg[@"max"]doubleValue],st=[cfg[@"step"]doubleValue];if(!isfinite(mn))mn=fmin;if(!isfinite(mx)||mx<=mn)mx=fmax>mn?fmax:mn+1;if(!isfinite(st)||st<=0)st=1;value=MAX(mn,MIN(mx,value));double q=mn+round((value-mn)/st)*st;return MAX(mn,MIN(mx,q));}
static NSString *M641ValueText(double value,NSDictionary *cfg){double st=[cfg[@"step"]doubleValue];if(!isfinite(st)||st<=0)st=1;if(fabs(st-round(st))<1e-9&&fabs(value-round(value))<1e-9)return [NSString stringWithFormat:@"%.0f",value];return [NSString stringWithFormat:@"%.6g",value];}

@interface ZNRuntimeMenuControllerV040 (M641UnifiedClient)
- (void)m641_renderFull;
- (void)m641_renderCompact;
- (void)m641_renderFeaturesCompact:(BOOL)compact;
- (void)m641_staticToggle:(UISwitch *)sender;
- (void)m641_staticNumberChanged:(UITextField *)field;
- (void)m641_staticNumberExec:(UIButton *)button;
- (void)m641_staticSlider:(ZNRangeControl *)slider;
- (void)m641_staticButton:(UIButton *)button;
@end

@implementation ZNRuntimeMenuControllerV040 (M641UnifiedClient)
- (void)m641_renderFull{NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<(NSInteger)self.categories.count)?self.categories[(NSUInteger)self.selectedCategory]:@"";if([cat isEqualToString:@"功能"]){[self m641_renderFeaturesCompact:NO];return;}[self m641_renderFull];}
- (void)m641_renderCompact{[self m641_renderFeaturesCompact:YES];}

- (void)m641_renderFeaturesCompact:(BOOL)compact{
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];CGFloat width=CGRectGetWidth(self.contentView.bounds),y=compact?7:9;NSArray *statics=M641StaticFeatures();NSArray *runtime=M641RuntimeRecords();
    if(!statics.count&&!runtime.count){UIView *c=[self cardAtY:y height:compact?40:46 width:width compact:compact];UILabel *l=[self label:@"暂无功能" size:compact?10.7:11 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];l.frame=CGRectMake(compact?9:13,compact?10:13,c.bounds.size.width-(compact?18:26),20);[c addSubview:l];[self.contentView addSubview:c];[self zn40_updateContentHeight:y+(compact?46:54)];return;}
    for(NSUInteger i=0;i<statics.count;i++){
        NSDictionary *f=statics[i];ZNFeatureControlType ct=(ZNFeatureControlType)[f[@"controlType"]unsignedIntValue];NSString *title=f[@"title"]?:@"功能",*desc=f[@"description"]?:@"";CGFloat h=compact?44:54;UIView *c=[self cardAtY:y height:h width:width compact:compact];CGFloat left=compact?9:13;CGFloat reserve=compact?126:150;UILabel *n=[self label:title size:compact?10.5:11.3 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];n.frame=CGRectMake(left,desc.length?(compact?4:6):(compact?11:16),MAX(70,c.bounds.size.width-reserve),20);[c addSubview:n];if(desc.length){UILabel *d=[self label:desc size:compact?7.5:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];d.frame=CGRectMake(left,compact?23:28,MAX(70,c.bounds.size.width-reserve),15);[c addSubview:d];}
        if(ct==ZNFeatureControlTypeSwitch){UISwitch *sw=[[UISwitch alloc]initWithFrame:CGRectZero];sw.on=M641AllStaticEnabled(f[@"records"]);sw.tag=kM641StaticToggle+(NSInteger)i;sw.center=CGPointMake(c.bounds.size.width-(compact?34:38),h*.5);[sw addTarget:self action:@selector(m641_staticToggle:) forControlEvents:UIControlEventValueChanged];[c addSubview:sw];}
        else if(ct==ZNFeatureControlTypeNumber){CGFloat ew=compact?46:52;UITextField *tf=[[UITextField alloc]initWithFrame:CGRectMake(c.bounds.size.width-(compact?126:148),compact?7:10,compact?72:88,compact?30:34)];tf.tag=kM641StaticNumber+(NSInteger)i;tf.text=[NSUserDefaults.standardUserDefaults stringForKey:M641StaticPref(f,@"valueText")]?:@"1";tf.keyboardType=UIKeyboardTypeNumbersAndPunctuation;tf.textAlignment=NSTextAlignmentCenter;tf.backgroundColor=self.theme.controlColor;tf.textColor=self.theme.primaryTextColor;tf.layer.cornerRadius=7;[tf addTarget:self action:@selector(m641_staticNumberChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEndOnExit];[c addSubview:tf];UIButton *b=[self zn40_button:@"执行" selector:@selector(m641_staticNumberExec:) frame:CGRectMake(CGRectGetMaxX(tf.frame)+4,tf.frame.origin.y,ew,tf.frame.size.height)];b.tag=kM641StaticExec+(NSInteger)i;[c addSubview:b];}
        else if(ct==ZNFeatureControlTypeSlider){CGFloat vw=compact?38:46;CGFloat sx=c.bounds.size.width-(compact?132:162);ZNRangeControl *sl=[[ZNRangeControl alloc]initWithFrame:CGRectMake(sx,compact?8:11,compact?86:108,compact?28:32)];sl.minimumValue=0;sl.maximumValue=10;double v=[NSUserDefaults.standardUserDefaults doubleForKey:M641StaticPref(f,@"value")];if(v<=0)v=1;sl.value=MAX(0,MIN(10,v));sl.tag=kM641StaticSlider+(NSInteger)i;[sl addTarget:self action:@selector(m641_staticSlider:) forControlEvents:UIControlEventValueChanged|UIControlEventPrimaryActionTriggered];[c addSubview:sl];UILabel *vl=[self label:[NSString stringWithFormat:@"%.0f",sl.value] size:compact?8:8.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];vl.tag=kM641StaticValue+(NSInteger)i;vl.textAlignment=NSTextAlignmentCenter;vl.frame=CGRectMake(CGRectGetMaxX(sl.frame)+4,sl.frame.origin.y,vw,sl.frame.size.height);[c addSubview:vl];}
        else {UIButton *b=[self zn40_button:@"执行" selector:@selector(m641_staticButton:) frame:CGRectMake(c.bounds.size.width-(compact?66:76),compact?7:10,compact?58:64,compact?30:34)];b.tag=kM641StaticExec+(NSInteger)i;[c addSubview:b];}
        [self.contentView addSubview:c];y+=h+(compact?6:8);
    }
    for(NSUInteger i=0;i<runtime.count;i++){
        ZNRuntimeMethodActionRecord *r=runtime[i];NSArray *cfgs=r.argumentControlConfigs.count==r.argumentCount?r.argumentControlConfigs:@[];NSArray *stored=M641StoredValues(r);NSUInteger exposed=0,numbers=0;for(NSDictionary *cfg in cfgs){if(![cfg[@"enabled"]boolValue])continue;exposed++;if(ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"])==ZNRuntimeArgumentControlTypeNumber)numbers++;}BOOL zero=r.argumentCount==0,fixed=r.argumentCount>0&&exposed==0,singleNumber=exposed==1&&numbers==1,headerExec=zero||fixed||(numbers>0&&!singleNumber);CGFloat hh=compact?45:56,rowH=compact?31:38,h=hh+exposed*rowH;if(zero||fixed)h=compact?49:61;UIView *c=[self cardAtY:y height:h width:width compact:compact];CGFloat left=compact?10:14,execW=compact?56:66,reserve=headerExec?execW+20:14;UILabel *name=[self label:(r.title.length?r.title:r.methodName) size:compact?10.5:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];name.frame=CGRectMake(left,compact?5:7,MAX(80,c.bounds.size.width-left-reserve),20);[c addSubview:name];NSString *desc=M641Trim(r.group);if([desc caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame)desc=@"";if(desc.length){UILabel *d=[self label:desc size:compact?7.8:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];d.frame=CGRectMake(left,compact?24:28,MAX(80,c.bounds.size.width-left-reserve),17);[c addSubview:d];}if(headerExec){UIButton *e=[self zn40_button:@"执行" selector:@selector(znm58_execute:) frame:CGRectMake(c.bounds.size.width-execW-12,compact?8:13,execW,compact?29:34)];e.tag=kM641RuntimeExec+(NSInteger)i;[c addSubview:e];}
        CGFloat ry=hh;for(NSUInteger arg=0;arg<r.argumentCount;arg++){NSDictionary *cfg=cfgs.count?cfgs[arg]:nil;if(![cfg[@"enabled"]boolValue])continue;NSInteger slot=(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);NSString *def=stored.count==r.argumentCount?stored[arg]:(arg<r.argumentValues.count?r.argumentValues[arg]:@"");ZNRuntimeArgumentControlType type=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);CGFloat available=MAX(80,c.bounds.size.width-left-12);if(type==ZNRuntimeArgumentControlTypeSlider){double mn=[cfg[@"min"]doubleValue],mx=[cfg[@"max"]doubleValue];if(!isfinite(mn))mn=0;if(!isfinite(mx)||mx<=mn)mx=mn+1;CGFloat vw=compact?42:50,gap=7,sw=MAX(80,available-vw-gap);ZNRangeControl *sl=[[ZNRangeControl alloc]initWithFrame:CGRectMake(left,ry+2,sw,rowH-5)];sl.minimumValue=mn;sl.maximumValue=mx;sl.value=M641Quantize(def.doubleValue,cfg,mn,mx);sl.tag=kM641RuntimeSlider+slot;[sl addTarget:self action:@selector(znm58_sliderChanged:) forControlEvents:UIControlEventValueChanged];[sl addTarget:self action:@selector(znm58_sliderCommitted:) forControlEvents:UIControlEventPrimaryActionTriggered];[c addSubview:sl];UILabel *vl=[self label:M641ValueText(sl.value,cfg) size:compact?8:8.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];vl.tag=kM641RuntimeValue+slot;vl.textAlignment=NSTextAlignmentCenter;vl.frame=CGRectMake(CGRectGetMaxX(sl.frame)+gap,ry+5,vw,rowH-11);[c addSubview:vl];}else if(type==ZNRuntimeArgumentControlTypeSwitch){UISwitch *sw=[[UISwitch alloc]initWithFrame:CGRectZero];sw.on=def.boolValue||[def.lowercaseString isEqualToString:@"true"];sw.tag=kM641RuntimeSwitch+slot;[sw addTarget:self action:@selector(znm58_switchChanged:) forControlEvents:UIControlEventValueChanged];sw.center=CGPointMake(c.bounds.size.width-12-sw.bounds.size.width*.5,ry+rowH*.5);[c addSubview:sw];}else if(type==ZNRuntimeArgumentControlTypeButton){UIButton *b=[self zn40_button:@"触发" selector:@selector(znm58_execute:) frame:CGRectMake(c.bounds.size.width-70,ry+4,58,rowH-8)];b.tag=kM641RuntimeExec+(NSInteger)i;[c addSubview:b];}else{CGFloat ew=singleNumber?(compact?56:66):0,gap=singleNumber?7:0,fw=MAX(80,available-ew-gap);UITextField *tf=[[UITextField alloc]initWithFrame:CGRectMake(left,ry+4,fw,rowH-8)];tf.text=def;tf.placeholder=@"数值";tf.textColor=self.theme.primaryTextColor;tf.backgroundColor=self.theme.controlColor;tf.layer.cornerRadius=8;tf.keyboardType=UIKeyboardTypeNumbersAndPunctuation;tf.tag=kM641RuntimeField+slot;[tf addTarget:self action:@selector(znm58_numberChanged:) forControlEvents:UIControlEventEditingChanged];[tf addTarget:self action:@selector(znm58_numberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];[c addSubview:tf];if(singleNumber){UIButton *e=[self zn40_button:@"执行" selector:@selector(znm58_execute:) frame:CGRectMake(CGRectGetMaxX(tf.frame)+gap,ry+4,ew,rowH-8)];e.tag=kM641RuntimeExec+(NSInteger)i;[c addSubview:e];}}ry+=rowH;}
        [self.contentView addSubview:c];y+=h+(compact?7:10);
    }
    [self zn40_updateContentHeight:y+(compact?3:6)];
}

- (void)m641_staticToggle:(UISwitch *)sender{NSInteger i=sender.tag-kM641StaticToggle;NSArray *f=M641StaticFeatures();if(i<0||(NSUInteger)i>=f.count)return;NSString *e=nil;if(!M641SetStatic(f[(NSUInteger)i][@"records"],sender.on,&e)){sender.on=!sender.on;[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.4.1-static] toggle failed: %@",e?:@"unknown"]];}}
- (void)m641_staticNumberChanged:(UITextField *)field{NSInteger i=field.tag-kM641StaticNumber;NSArray *f=M641StaticFeatures();if(i<0||(NSUInteger)i>=f.count)return;NSString *t=M641Trim(field.text);[NSUserDefaults.standardUserDefaults setObject:(t.length?t:@"0") forKey:M641StaticPref(f[(NSUInteger)i],@"valueText")];}
- (void)m641_staticNumberExec:(UIButton *)button{NSInteger i=button.tag-kM641StaticExec;NSArray *f=M641StaticFeatures();if(i<0||(NSUInteger)i>=f.count)return;NSDictionary *x=f[(NSUInteger)i];NSString *t=[NSUserDefaults.standardUserDefaults stringForKey:M641StaticPref(x,@"valueText")]?:@"0";[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureNumberValueDidChangeNotification object:self userInfo:M641StaticEvent(x,t)];}
- (void)m641_staticSlider:(ZNRangeControl *)slider{NSInteger i=slider.tag-kM641StaticSlider;NSArray *f=M641StaticFeatures();if(i<0||(NSUInteger)i>=f.count)return;NSDictionary *x=f[(NSUInteger)i];double v=round(slider.value);slider.value=v;[NSUserDefaults.standardUserDefaults setDouble:v forKey:M641StaticPref(x,@"value")];NSString *t=[NSString stringWithFormat:@"%.0f",v];UILabel *vl=[self.contentView viewWithTag:kM641StaticValue+i];vl.text=t;[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification object:self userInfo:M641StaticEvent(x,t)];}
- (void)m641_staticButton:(UIButton *)button{NSInteger i=button.tag-kM641StaticExec;NSArray *f=M641StaticFeatures();if(i<0||(NSUInteger)i>=f.count)return;NSDictionary *x=f[(NSUInteger)i];[NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureActionRequestedNotification object:self userInfo:M641StaticEvent(x,nil)];}
@end

extern "C" void ZNInstallM641UnifiedClientRendererDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;Method a=class_getInstanceMethod(cls,@selector(renderFullPage)),b=class_getInstanceMethod(cls,@selector(m641_renderFull));if(a&&b)method_exchangeImplementations(a,b);Method c=class_getInstanceMethod(cls,@selector(renderCompactPage)),d=class_getInstanceMethod(cls,@selector(m641_renderCompact));if(c&&d)method_exchangeImplementations(c,d);[[ZNRuntimeLogger sharedLogger]log:@"[m6.4.1-client] one renderer owns Static + Runtime Feature surface; no append/decorate layer"];});}
