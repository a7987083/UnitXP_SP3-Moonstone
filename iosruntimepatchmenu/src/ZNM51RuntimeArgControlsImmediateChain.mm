#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZN51BuilderTitleTagBase = 672000;
static const NSInteger kZN51BuilderArg1TagBase = 674000;
static const NSInteger kZN51BuilderMultiArgTagBase = 690000;
static const NSInteger kZN51BuilderCheckTagBase = 812000;
static const NSInteger kZN51BuilderTypeTagBase = 813000;
static const NSInteger kZN51FinderChainTagBase = 814000;
static const NSInteger kZN51RuntimeCardTagBase = 795000;
static const NSInteger kZN51RuntimeExecTagBase = 796000;
static const NSInteger kZN51RuntimeFieldTagBase = 797000;
static const NSInteger kZN51RuntimeSwitchTagBase = 798000;
static const NSInteger kZN51RuntimeSliderTagBase = 799000;
static const NSInteger kZN49RuntimeCardTagBase = 786000;

static const void *kZN51CandidateKey = &kZN51CandidateKey;
static const void *kZN51ActionIndexKey = &kZN51ActionIndexKey;
static const void *kZN51ArgIndexKey = &kZN51ArgIndexKey;
static const void *kZN51RuntimeValueStoreKey = &kZN51RuntimeValueStoreKey;
static const void *kZN51RecordIndexKey = &kZN51RecordIndexKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (void)zn50b_renderOther;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static CGFloat ZN51MaxY(UIView *root){CGFloat y=0;for(UIView *v in root.subviews)y=MAX(y,CGRectGetMaxY(v.frame));return y;}
static UIViewController *ZN51Top(UIWindow *window){UIViewController *vc=window.rootViewController;while(vc.presentedViewController)vc=vc.presentedViewController;return vc;}
static NSString *ZN51ShortType(NSString *type){NSArray *p=[(type?:@"") componentsSeparatedByString:@"."];return p.lastObject.length?p.lastObject:(type?:@"?");}
static NSArray<NSDictionary *> *ZN51Visible(ZNRuntimeMenuControllerV040 *c){NSArray *all=[c zn60v3_candidates]?:@[];NSInteger filter=[c znm42_filter];NSMutableArray *out=[NSMutableArray array];for(NSDictionary *x in all)if(filter<0||[x[@"argumentCount"] integerValue]==filter)[out addObject:x];return out;}
static void ZN51CollectButtons(UIView *root,NSString *title,NSMutableArray<UIButton *> *out){for(UIView *v in root.subviews){if([v isKindOfClass:UIButton.class]&&[[(UIButton *)v titleForState:UIControlStateNormal] isEqualToString:title])[out addObject:(UIButton *)v];ZN51CollectButtons(v,title,out);}}
static NSMutableDictionary<NSString *,NSString *> *ZN51RuntimeValues(ZNRuntimeMenuControllerV040 *c){NSMutableDictionary *d=objc_getAssociatedObject(c,kZN51RuntimeValueStoreKey);if(!d){d=[NSMutableDictionary dictionary];objc_setAssociatedObject(c,kZN51RuntimeValueStoreKey,d,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}return d;}
static NSString *ZN51ValueKey(uint32_t actionID,NSUInteger arg){return[NSString stringWithFormat:@"%u:%lu",actionID,(unsigned long)arg];}

@interface ZNRuntimeMenuControllerV040 (ZNM51)
- (void)zn51_builderRender;
- (void)zn51_toggleArg:(UIButton *)sender;
- (void)zn51_cycleArgType:(UIButton *)sender;
- (void)zn51_finderRender:(CGFloat)width;
- (void)zn51_chainTapped:(UIButton *)sender;
- (void)zn51_runtimeFull;
- (void)zn51_runtimeCompact;
- (void)zn51_runtimeExecute:(UIButton *)sender;
- (void)zn51_runtimeNumberChanged:(UITextField *)field;
- (void)zn51_runtimeSwitchChanged:(UISwitch *)control;
- (void)zn51_runtimeSliderChanged:(UISlider *)control;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM51)

- (void)zn51_builderRender {
    [self zn51_builderRender];
    NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for(NSUInteger i=0;i<actions.count;i++){
        ZNRuntimeMethodAction *a=actions[i];
        if(!a.argumentCount)continue;
        for(NSUInteger arg=0;arg<a.argumentCount;arg++){
            NSInteger tag=(a.argumentCount==1)?(kZN51BuilderArg1TagBase+(NSInteger)i):(kZN51BuilderMultiArgTagBase+(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg));
            UIView *v=[self.contentView viewWithTag:tag];if(![v isKindOfClass:UITextField.class])continue;UITextField *field=(UITextField *)v;UIView *card=field.superview;if(!card)continue;
            CGFloat right=CGRectGetWidth(card.bounds)-12.0;CGFloat typeW=56.0,checkW=34.0,gap=4.0;CGRect f=field.frame;CGFloat available=right-CGRectGetMinX(f)-typeW-checkW-gap*2.0;if(available>70.0)f.size.width=available;field.frame=f;
            NSDictionary *cfg=(a.argumentControlConfigs.count==a.argumentCount)?a.argumentControlConfigs[arg]:@{@"enabled":@NO,@"type":@"fixed"};BOOL enabled=[cfg[@"enabled"] boolValue];ZNRuntimeArgumentControlType type=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
            UIButton *check=[self zn40_button:(enabled?@"☑":@"☐") selector:@selector(zn51_toggleArg:) frame:CGRectMake(CGRectGetMaxX(f)+gap,CGRectGetMinY(f),checkW,CGRectGetHeight(f))];check.tag=kZN51BuilderCheckTagBase+(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);objc_setAssociatedObject(check,kZN51ActionIndexKey,@(i),OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(check,kZN51ArgIndexKey,@(arg),OBJC_ASSOCIATION_RETAIN_NONATOMIC);[card addSubview:check];
            UIButton *typeButton=[self zn40_button:(enabled?ZNRuntimeArgumentControlTypeName(type):@"固定") selector:@selector(zn51_cycleArgType:) frame:CGRectMake(CGRectGetMaxX(check.frame)+gap,CGRectGetMinY(f),typeW,CGRectGetHeight(f))];typeButton.tag=kZN51BuilderTypeTagBase+(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);typeButton.enabled=enabled;typeButton.alpha=enabled?1.0:0.5;typeButton.titleLabel.font=[UIFont systemFontOfSize:7.8 weight:UIFontWeightSemibold];objc_setAssociatedObject(typeButton,kZN51ActionIndexKey,@(i),OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(typeButton,kZN51ArgIndexKey,@(arg),OBJC_ASSOCIATION_RETAIN_NONATOMIC);[card addSubview:typeButton];
        }
    }
    [self zn40_updateContentHeight:ZN51MaxY(self.contentView)+8.0];
}

- (void)zn51_toggleArg:(UIButton *)sender {
    NSUInteger ai=[objc_getAssociatedObject(sender,kZN51ActionIndexKey) unsignedIntegerValue],arg=[objc_getAssociatedObject(sender,kZN51ArgIndexKey) unsignedIntegerValue];NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if(ai>=actions.count)return;ZNRuntimeMethodAction *a=actions[ai];if(arg>=a.argumentCount)return;NSMutableArray *configs=[NSMutableArray arrayWithArray:(a.argumentControlConfigs.count==a.argumentCount?a.argumentControlConfigs:@[])];while(configs.count<a.argumentCount)[configs addObject:@{@"enabled":@NO,@"type":@"fixed",@"min":@0,@"max":@100,@"step":@1}];NSMutableDictionary *cfg=[configs[arg] mutableCopy];BOOL next=![cfg[@"enabled"] boolValue];cfg[@"enabled"]=@(next);cfg[@"type"]=next?@"number":@"fixed";configs[arg]=cfg;[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:configs atIndex:ai error:nil];[self renderPage];
}

- (void)zn51_cycleArgType:(UIButton *)sender {
    NSUInteger ai=[objc_getAssociatedObject(sender,kZN51ActionIndexKey) unsignedIntegerValue],arg=[objc_getAssociatedObject(sender,kZN51ArgIndexKey) unsignedIntegerValue];NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];if(ai>=actions.count)return;ZNRuntimeMethodAction *a=actions[ai];if(arg>=a.argumentCount||a.argumentControlConfigs.count!=a.argumentCount)return;NSMutableArray *configs=[a.argumentControlConfigs mutableCopy];NSMutableDictionary *cfg=[configs[arg] mutableCopy];if(![cfg[@"enabled"] boolValue])return;ZNRuntimeArgumentControlType current=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);ZNRuntimeArgumentControlType next=current<ZNRuntimeArgumentControlTypeSwitch||current>=ZNRuntimeArgumentControlTypeSlider?ZNRuntimeArgumentControlTypeSwitch:(ZNRuntimeArgumentControlType)(current+1);cfg[@"type"]=ZNRuntimeArgumentControlTypeKey(next);configs[arg]=cfg;[[ZNRuntimeActionStore sharedStore] updateArgumentControlConfigs:configs atIndex:ai error:nil];[self renderPage];
}

- (void)zn51_finderRender:(CGFloat)width {
    [self zn51_finderRender:width];
    NSArray *visible=ZN51Visible(self);NSMutableArray<UIButton *> *creates=[NSMutableArray array];ZN51CollectButtons(self.contentView,@"创建方法",creates);if(!visible.count||creates.count!=visible.count)return;
    for(NSUInteger i=0;i<visible.count;i++){
        UIButton *create=creates[i];UIView *card=create.superview;if(!card)continue;NSDictionary *candidate=visible[i];CGFloat y=CGRectGetMaxY(create.frame)+5.0;CGFloat needed=y+CGRectGetHeight(create.frame)+7.0;CGFloat oldBottom=CGRectGetMaxY(card.frame);if(needed>CGRectGetHeight(card.frame)){CGFloat delta=needed-CGRectGetHeight(card.frame);CGRect cf=card.frame;cf.size.height=needed;card.frame=cf;for(UIView *sib in self.contentView.subviews){if(sib==card||CGRectGetMinY(sib.frame)+0.5<oldBottom)continue;CGRect sf=sib.frame;sf.origin.y+=delta;sib.frame=sf;}}
        UIButton *chain=[self zn40_button:@"链式调用" selector:@selector(zn51_chainTapped:) frame:CGRectMake(CGRectGetMinX(create.frame),y,CGRectGetWidth(create.frame),CGRectGetHeight(create.frame))];chain.tag=kZN51FinderChainTagBase+(NSInteger)i;chain.titleLabel.font=[UIFont systemFontOfSize:8.2 weight:UIFontWeightSemibold];objc_setAssociatedObject(chain,kZN51CandidateKey,candidate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[card addSubview:chain];
    }
    [self zn40_updateContentHeight:ZN51MaxY(self.contentView)+8.0];
}

- (void)zn51_chainTapped:(UIButton *)sender {
    NSDictionary *candidate=objc_getAssociatedObject(sender,kZN51CandidateKey);if(!candidate)return;NSDictionary *abi=ZNIL2CPPDescribeMethodABI(candidate);NSDictionary *ret=[abi[@"return"] isKindOfClass:NSDictionary.class]?abi[@"return"]:@{};NSString *returnType=[ret[@"name"] isKindOfClass:NSString.class]?ret[@"name"]:@"";ZNIL2CPPABIValueKind kind=(ZNIL2CPPABIValueKind)[ret[@"kind"] integerValue];if(kind!=ZNIL2CPPABIValueKindObjectReference){[self zn60v3_setStatus:[NSString stringWithFormat:@"链式调用需要 managed-reference 返回值；当前=%@",returnType.length?returnType:@"?"]];[self renderPage];return;}
    NSString *ns=@"",*cls=returnType;NSRange dot=[returnType rangeOfString:@"." options:NSBackwardsSearch];if(dot.location!=NSNotFound){ns=[returnType substringToIndex:dot.location];cls=[returnType substringFromIndex:dot.location+1];}
    UIViewController *top=ZN51Top(self.hostWindow);if(!top)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"返回对象 → 立即调用方法" message:[NSString stringWithFormat:@"%@::%@/%@\n返回类型：%@\nM5.1 V1 链式目标先支持 /0。",candidate[@"class"]?:@"?",candidate[@"method"]?:@"?",candidate[@"argumentCount"]?:@0,returnType?:@"?"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Namespace（可空）";f.text=ns;}];[alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Class";f.text=cls;}];[alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Method";f.text=@"ToString";}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];__weak typeof(self) weakSelf=self;[alert addAction:[UIAlertAction actionWithTitle:@"创建链式方法" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){__strong typeof(weakSelf) selfRef=weakSelf;if(!selfRef)return;NSString *targetNS=alert.textFields.count>0?alert.textFields[0].text:@"";NSString *targetClass=alert.textFields.count>1?alert.textFields[1].text:@"";NSString *targetMethod=alert.textFields.count>2?alert.textFields[2].text:@"";if(!targetClass.length||!targetMethod.length){[selfRef zn60v3_setStatus:@"链式 Class/Method 不能为空"];[selfRef renderPage];return;}NSArray *values=[selfRef znm43_argumentValues:candidate]?:@[];NSString *err=nil;ZNRuntimeMethodAction *created=[[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate title:candidate[@"method"] argumentValues:values error:&err];if(!created){[selfRef zn60v3_setStatus:err?:@"创建主 Runtime Method 失败"];[selfRef renderPage];return;}NSArray *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];NSUInteger idx=NSNotFound;for(NSUInteger j=0;j<actions.count;j++)if(actions[j].actionID==created.actionID){idx=j;break;}NSDictionary *chain=@{@"assembly":candidate[@"assembly"]?:@"Assembly-CSharp.dll",@"namespace":targetNS?:@"",@"class":targetClass,@"method":targetMethod,@"argumentCount":@0,@"argumentValues":@[]};if(idx==NSNotFound||![[ZNRuntimeActionStore sharedStore] updateImmediateChain:chain atIndex:idx error:&err]){[selfRef zn60v3_setStatus:err?:@"保存 Immediate Chain 失败"];[selfRef renderPage];return;}[selfRef zn60v3_setStatus:[NSString stringWithFormat:@"已创建链式方法：%@ → %@::%@/0",created.canonicalIdentity,targetClass,targetMethod]];[selfRef renderPage];}]];[top presentViewController:alert animated:YES completion:nil];
}

- (void)zn51_removeRuntimeCards { for(UIView *v in [self.contentView.subviews copy])if((v.tag>=kZN49RuntimeCardTagBase&&v.tag<kZN49RuntimeCardTagBase+512)||(v.tag>=kZN51RuntimeCardTagBase&&v.tag<kZN51RuntimeCardTagBase+512))[v removeFromSuperview]; }
- (void)zn51_renderRuntime:(BOOL)compact {
    ZNRuntimeActionRuntime *runtime=[ZNRuntimeActionRuntime sharedRuntime];[runtime refresh];[self zn51_removeRuntimeCards];CGFloat width=CGRectGetWidth(self.contentView.bounds),y=ZN51MaxY(self.contentView)+(compact?6:8);NSArray *records=runtime.records?:@[];
    for(NSUInteger i=0;i<records.count;i++){ZNRuntimeMethodActionRecord *r=records[i];NSArray *configs=r.argumentControlConfigs.count==r.argumentCount?r.argumentControlConfigs:@[];NSUInteger exposed=0;for(NSDictionary *c in configs)if([c[@"enabled"] boolValue])exposed++;CGFloat rowH=34.0,baseH=compact?42.0:48.0,height=baseH+exposed*rowH;UIView *card=[self cardAtY:y height:height width:width compact:compact];card.tag=kZN51RuntimeCardTagBase+(NSInteger)i;UILabel *name=[self label:(r.title.length?r.title:r.methodName) size:(compact?10.5:11.2) weight:UIFontWeightSemibold color:self.theme.primaryTextColor];name.frame=CGRectMake(compact?9:13,8,card.bounds.size.width-92,24);[card addSubview:name];UIButton *exec=[self zn40_button:@"执行" selector:@selector(zn51_runtimeExecute:) frame:CGRectMake(card.bounds.size.width-76,7,64,29)];exec.tag=kZN51RuntimeExecTagBase+(NSInteger)i;[card addSubview:exec];CGFloat ry=baseH;
        for(NSUInteger arg=0;arg<r.argumentCount;arg++){NSDictionary *cfg=configs.count?configs[arg]:nil;if(![cfg[@"enabled"] boolValue])continue;NSString *type=(arg<r.parameterTypeNames.count)?r.parameterTypeNames[arg]:@"?";UILabel *lab=[self label:[NSString stringWithFormat:@"参数%lu · %@",(unsigned long)arg+1,ZN51ShortType(type)] size:8.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];lab.frame=CGRectMake(13,ry,82,28);[card addSubview:lab];NSString *key=ZN51ValueKey(r.actionID,arg);NSString *def=(arg<r.argumentValues.count)?r.argumentValues[arg]:@"";NSString *stored=ZN51RuntimeValues(self)[key]?:def;ZNRuntimeArgumentControlType ct=ZNRuntimeArgumentControlTypeFromKey(cfg[@"type"]);
            if(ct==ZNRuntimeArgumentControlTypeSwitch){UISwitch *sw=[[UISwitch alloc]initWithFrame:CGRectZero];sw.on=[stored boolValue]||[stored.lowercaseString isEqualToString:@"true"];sw.tag=kZN51RuntimeSwitchTagBase+(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);objc_setAssociatedObject(sw,kZN51RecordIndexKey,@(i),OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(sw,kZN51ArgIndexKey,@(arg),OBJC_ASSOCIATION_RETAIN_NONATOMIC);[sw addTarget:self action:@selector(zn51_runtimeSwitchChanged:) forControlEvents:UIControlEventValueChanged];sw.center=CGPointMake(card.bounds.size.width-38,ry+14);[card addSubview:sw];}
            else if(ct==ZNRuntimeArgumentControlTypeSlider){UISlider *sl=[[UISlider alloc]initWithFrame:CGRectMake(96,ry,card.bounds.size.width-109,28)];sl.minimumValue=[cfg[@"min"] floatValue];sl.maximumValue=[cfg[@"max"] floatValue];if(sl.maximumValue<=sl.minimumValue)sl.maximumValue=sl.minimumValue+100;sl.value=stored.floatValue;sl.tag=kZN51RuntimeSliderTagBase+(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);objc_setAssociatedObject(sl,kZN51RecordIndexKey,@(i),OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(sl,kZN51ArgIndexKey,@(arg),OBJC_ASSOCIATION_RETAIN_NONATOMIC);[sl addTarget:self action:@selector(zn51_runtimeSliderChanged:) forControlEvents:UIControlEventValueChanged];[card addSubview:sl];}
            else if(ct==ZNRuntimeArgumentControlTypeButton){UIButton *b=[self zn40_button:@"触发" selector:@selector(zn51_runtimeExecute:) frame:CGRectMake(card.bounds.size.width-70,ry,58,28)];b.tag=kZN51RuntimeExecTagBase+(NSInteger)i;[card addSubview:b];}
            else {UITextField *field=[[UITextField alloc]initWithFrame:CGRectMake(96,ry,card.bounds.size.width-109,28)];field.text=stored;field.placeholder=def;field.textColor=self.theme.primaryTextColor;field.backgroundColor=self.theme.controlColor;field.layer.cornerRadius=6;field.layer.borderWidth=1;field.layer.borderColor=self.theme.borderColor.CGColor;field.font=[UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium];field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;field.tag=kZN51RuntimeFieldTagBase+(NSInteger)(i*ZN_RUNTIME_ACTION_MAX_ARGUMENTS+arg);objc_setAssociatedObject(field,kZN51RecordIndexKey,@(i),OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(field,kZN51ArgIndexKey,@(arg),OBJC_ASSOCIATION_RETAIN_NONATOMIC);[field addTarget:self action:@selector(zn51_runtimeNumberChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];[card addSubview:field];}
            ry+=rowH;
        }
        [self.contentView addSubview:card];y+=height+(compact?6:8);
    }[self zn40_updateContentHeight:y];
}
- (void)zn51_runtimeFull{[self zn51_runtimeFull];[self zn51_renderRuntime:NO];}
- (void)zn51_runtimeCompact{[self zn51_runtimeCompact];[self zn51_renderRuntime:YES];}
- (void)zn51_runtimeNumberChanged:(UITextField *)field{NSUInteger ri=[objc_getAssociatedObject(field,kZN51RecordIndexKey) unsignedIntegerValue],arg=[objc_getAssociatedObject(field,kZN51ArgIndexKey) unsignedIntegerValue];ZNRuntimeActionRuntime *rt=[ZNRuntimeActionRuntime sharedRuntime];if(ri>=rt.records.count)return;ZN51RuntimeValues(self)[ZN51ValueKey(rt.records[ri].actionID,arg)]=field.text?:@"";}
- (void)zn51_runtimeSwitchChanged:(UISwitch *)control{NSUInteger ri=[objc_getAssociatedObject(control,kZN51RecordIndexKey) unsignedIntegerValue],arg=[objc_getAssociatedObject(control,kZN51ArgIndexKey) unsignedIntegerValue];ZNRuntimeActionRuntime *rt=[ZNRuntimeActionRuntime sharedRuntime];if(ri>=rt.records.count)return;ZN51RuntimeValues(self)[ZN51ValueKey(rt.records[ri].actionID,arg)]=control.on?@"true":@"false";}
- (void)zn51_runtimeSliderChanged:(UISlider *)control{NSUInteger ri=[objc_getAssociatedObject(control,kZN51RecordIndexKey) unsignedIntegerValue],arg=[objc_getAssociatedObject(control,kZN51ArgIndexKey) unsignedIntegerValue];ZNRuntimeActionRuntime *rt=[ZNRuntimeActionRuntime sharedRuntime];if(ri>=rt.records.count)return;ZNRuntimeMethodActionRecord *r=rt.records[ri];NSDictionary *cfg=(r.argumentControlConfigs.count==r.argumentCount)?r.argumentControlConfigs[arg]:@{};float step=[cfg[@"step"] floatValue];float value=control.value;if(step>0)value=roundf(value/step)*step;ZN51RuntimeValues(self)[ZN51ValueKey(r.actionID,arg)]=[NSString stringWithFormat:@"%.7g",value];}
- (void)zn51_runtimeExecute:(UIButton *)sender{NSInteger index=sender.tag-kZN51RuntimeExecTagBase;if(index<0)return;ZNRuntimeActionRuntime *rt=[ZNRuntimeActionRuntime sharedRuntime];[rt refresh];if((NSUInteger)index>=rt.records.count)return;ZNRuntimeMethodActionRecord *r=rt.records[(NSUInteger)index];NSMutableArray *values=[NSMutableArray arrayWithArray:r.argumentValues?:@[]];while(values.count<r.argumentCount)[values addObject:@""];if(r.argumentControlConfigs.count==r.argumentCount)for(NSUInteger arg=0;arg<r.argumentCount;arg++)if([r.argumentControlConfigs[arg][@"enabled"] boolValue]){NSString *v=ZN51RuntimeValues(self)[ZN51ValueKey(r.actionID,arg)];if(v)values[arg]=v;}ZNRuntimeMethodAction *a=[ZNRuntimeMethodAction new];a.actionID=r.actionID;a.title=r.title;a.group=r.group;a.assembly=r.assembly;a.namespaceName=r.namespaceName;a.className=r.className;a.methodName=r.methodName;a.argumentCount=r.argumentCount;a.argumentValues=values;a.parameterTypeNames=r.parameterTypeNames;a.signatureAvailable=r.signatureAvailable;a.argumentControlConfigs=r.argumentControlConfigs;a.immediateChain=r.immediateChain;NSString *err=nil;NSDictionary *result=[[ZNIL2CPPInvokeEngine sharedEngine] executeAction:a error:&err];UIViewController *top=ZN51Top(self.hostWindow);if(top){NSString *msg=result?[NSString stringWithFormat:@"返回 %@ = %@",result[@"returnType"]?:@"?",result[@"returnValue"]?:@"?"]:(err?:@"执行失败");UIAlertController *done=[UIAlertController alertControllerWithTitle:(result?@"执行完成":@"执行失败") message:msg preferredStyle:UIAlertControllerStyleAlert];[done addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];[top presentViewController:done animated:YES completion:nil];}}
@end

@interface ZNIL2CPPInvokeEngine (ZNM51ImmediateChain)
- (NSDictionary<NSString *,id> *)znm51_executeAction:(ZNRuntimeMethodAction *)action error:(NSString **)error;
@end
@implementation ZNIL2CPPInvokeEngine (ZNM51ImmediateChain)
- (NSDictionary<NSString *,id> *)znm51_executeAction:(ZNRuntimeMethodAction *)action error:(NSString **)error {
    NSDictionary *primary=[self znm51_executeAction:action error:error];if(!primary||!action.immediateChain.count)return primary;NSString *kind=[primary[@"returnKind"] isKindOfClass:NSString.class]?primary[@"returnKind"]:@"";uintptr_t raw=[primary[@"returnRawObject"] unsignedLongLongValue];if(!raw||![kind containsString:@"managed reference"]){if(error)*error=@"Immediate Chain：主方法没有返回 managed-reference";return nil;}
    NSDictionary *c=action.immediateChain;ZNRuntimeMethodAction *next=[ZNRuntimeMethodAction new];next.title=@"Immediate Chain";next.assembly=[c[@"assembly"] isKindOfClass:NSString.class]?c[@"assembly"]:action.assembly;next.namespaceName=[c[@"namespace"] isKindOfClass:NSString.class]?c[@"namespace"]:@"";next.className=[c[@"class"] isKindOfClass:NSString.class]?c[@"class"]:@"";next.methodName=[c[@"method"] isKindOfClass:NSString.class]?c[@"method"]:@"";next.argumentCount=[c[@"argumentCount"] unsignedIntegerValue];next.argumentValues=[c[@"argumentValues"] isKindOfClass:NSArray.class]?c[@"argumentValues"]:@[];next.signatureAvailable=NO;NSString *chainError=nil;NSDictionary *second=[self znm51_executeAction:next error:&chainError];if(!second){if(error)*error=chainError?:@"Immediate Chain 第二跳失败";return nil;}NSMutableDictionary *merged=[second mutableCopy];merged[@"immediateChain"]=@YES;merged[@"chainPrimaryReturnType"]=primary[@"returnType"]?:@"?";merged[@"chainPrimaryRawObject"]=primary[@"returnRawObject"]?:@0;[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.1-chain] %@ -> %@::%@/%lu SUCCESS",action.canonicalIdentity,next.className,next.methodName,(unsigned long)next.argumentCount]];return[merged copy];}
@end

static void ZN51Swap(Class cls,SEL a,SEL b){Method ma=class_getInstanceMethod(cls,a),mb=class_getInstanceMethod(cls,b);if(ma&&mb)method_exchangeImplementations(ma,mb);}
extern "C" void ZNInstallM51RuntimeArgControlsImmediateChainDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class menu=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(menu){ZN51Swap(menu,@selector(zn50b_renderOther),@selector(zn51_builderRender));ZN51Swap(menu,@selector(zn60v3_renderResultsAtWidth:),@selector(zn51_finderRender:));ZN51Swap(menu,@selector(zn50_renderFeatureGroupsFull),@selector(zn51_runtimeFull));ZN51Swap(menu,@selector(zn50_renderFeatureGroupsCompact),@selector(zn51_runtimeCompact));}ZN51Swap(ZNIL2CPPInvokeEngine.class,@selector(executeAction:error:),@selector(znm51_executeAction:error:));[[ZNRuntimeLogger sharedLogger]log:@"[m5.1] per-argument runtime controls + Immediate Chain installed"];});}
