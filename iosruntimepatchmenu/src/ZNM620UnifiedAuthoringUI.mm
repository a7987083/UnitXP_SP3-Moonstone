#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNPatchCore.h"

// M6.2 — Unified Authoring UX + client-facing Feature descriptions.
// No second menu/controller hierarchy is created. Existing authoring/runtime
// renderers are post-processed in place.

static const NSInteger kZNM620RuntimeTitleTagBase = 672000;
static const NSInteger kZNM620RuntimeDescriptionTagBase = 964000;
static const NSInteger kZNM620StaticNameTagBase = 462000;
static const NSInteger kZNM620StaticDescriptionTagBase = 965000;
static const NSInteger kZNM620RuntimeCardBase = 895000;
static const NSInteger kZNM620RuntimeCardLimit = 895512;
static NSString * const kZNM620RuntimeDescriptionsKey = @"zonoe.m6.2.runtime-descriptions.v1";
static NSString * const kZNM620StaticDescriptionsKey = @"zonoe.m6.2.static-descriptions.v1";
static NSMutableDictionary<NSNumber *, NSString *> *gZNM620PromotionDescriptions;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn50b_renderOther;
- (void)zn51_renderRuntime:(BOOL)compact;
- (void)zn40_updateContentHeight:(CGFloat)y;
@end

static NSString *ZNM620Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM620FeatureName(ZNBinaryPatchRow *row) {
    NSString *group=ZNM620Trim(row.group);
    if(group.length && [group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return group;
    return ZNM620Trim(row.title);
}

static NSString *ZNM620RuntimeKey(ZNRuntimeMethodAction *action) {
    return action.canonicalIdentity.length?action.canonicalIdentity:(action.legacyCanonicalIdentity?:@"");
}

static NSMutableDictionary *ZNM620MutableDefaults(NSString *key) {
    NSDictionary *stored=[NSUserDefaults.standardUserDefaults objectForKey:key];
    return [stored isKindOfClass:NSDictionary.class]?[stored mutableCopy]:[NSMutableDictionary dictionary];
}

static NSString *ZNM620StaticDescription(NSString *featureName) {
    NSDictionary *root=[NSUserDefaults.standardUserDefaults objectForKey:kZNM620StaticDescriptionsKey];
    if(![root isKindOfClass:NSDictionary.class])return @"";
    id v=root[ZNM620Trim(featureName).lowercaseString];
    return [v isKindOfClass:NSString.class]?v:@"";
}

static void ZNM620SetStaticDescription(NSString *featureName,NSString *description) {
    NSString *key=ZNM620Trim(featureName).lowercaseString;if(!key.length)return;
    NSMutableDictionary *root=ZNM620MutableDefaults(kZNM620StaticDescriptionsKey);
    NSString *value=ZNM620Trim(description);
    if(value.length)root[key]=value;else[root removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNM620StaticDescriptionsKey];
}

static NSString *ZNM620RuntimeDescription(ZNRuntimeMethodAction *action) {
    NSString *group=ZNM620Trim(action.group);
    if(group.length && [group caseInsensitiveCompare:@"Runtime Methods"]!=NSOrderedSame)return group;
    NSDictionary *root=[NSUserDefaults.standardUserDefaults objectForKey:kZNM620RuntimeDescriptionsKey];
    id value=[root isKindOfClass:NSDictionary.class]?root[ZNM620RuntimeKey(action)]:nil;
    return [value isKindOfClass:NSString.class]?value:@"";
}

static void ZNM620SetRuntimeDescriptionAtIndex(NSUInteger index,NSString *description) {
    ZNRuntimeActionStore *store=[ZNRuntimeActionStore sharedStore];
    NSMutableArray *actions=nil;
    @try { actions=[store valueForKey:@"mutableActions"]; } @catch(__unused NSException *e) { actions=nil; }
    if(![actions isKindOfClass:NSMutableArray.class]||index>=actions.count)return;
    ZNRuntimeMethodAction *action=actions[index];
    NSString *value=ZNM620Trim(description);
    action.group=value.length?value:@"Runtime Methods";
    NSMutableDictionary *root=ZNM620MutableDefaults(kZNM620RuntimeDescriptionsKey);
    NSString *key=ZNM620RuntimeKey(action);
    if(key.length){if(value.length)root[key]=value;else[root removeObjectForKey:key];}
    [NSUserDefaults.standardUserDefaults setObject:root forKey:kZNM620RuntimeDescriptionsKey];
    // Existing M5.5.1 swizzle persists the action immediately.
    [store updateTitle:action.title atIndex:index error:nil];
}

static void ZNM620ShiftFollowingSubviews(UIView *content,CGFloat threshold,CGFloat delta,UIView *except) {
    for(UIView *view in content.subviews){if(view==except)continue;if(CGRectGetMinY(view.frame)>=threshold){CGRect f=view.frame;f.origin.y+=delta;view.frame=f;}}
}

static UITextField *ZNM620DescriptionField(CGRect frame,NSInteger tag,NSString *text,SEL selector,id target) {
    UITextField *field=[[UITextField alloc]initWithFrame:frame];
    field.tag=tag;field.text=text?:@"";field.placeholder=@"说明（显示给用户）";
    field.font=[UIFont systemFontOfSize:9.8 weight:UIFontWeightRegular];
    field.textColor=UIColor.labelColor;field.backgroundColor=[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.55];
    field.autocorrectionType=UITextAutocorrectionTypeNo;field.returnKeyType=UIReturnKeyDone;
    field.clearButtonMode=UITextFieldViewModeWhileEditing;field.layer.cornerRadius=7;field.layer.borderWidth=.8;
    field.layer.borderColor=[UIColor.separatorColor colorWithAlphaComponent:.65].CGColor;
    UIView *pad=[[UIView alloc]initWithFrame:CGRectMake(0,0,7,1)];field.leftView=pad;field.leftViewMode=UITextFieldViewModeAlways;
    [field addTarget:target action:selector forControlEvents:UIControlEventEditingDidEnd|UIControlEventEditingDidEndOnExit];
    return field;
}

@interface ZNRuntimeMenuControllerV040 (ZNM620Authoring)
- (void)znm620_renderOther;
- (void)znm620_renderRuntime:(BOOL)compact;
- (void)znm620_runtimeDescriptionEnded:(UITextField *)field;
- (void)znm620_staticDescriptionEnded:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM620Authoring)

- (void)znm620_renderOther {
    [self znm620_renderOther];

    // Runtime Method authoring cards: add a first-class Description field.
    NSMutableArray<UITextField *> *runtimeNames=[NSMutableArray array];
    NSMutableArray<UITextField *> *staticNames=[NSMutableArray array];
    for(UIView *top in self.contentView.subviews){
        NSMutableArray *stack=[NSMutableArray arrayWithObject:top];
        while(stack.count){UIView *v=stack.lastObject;[stack removeLastObject];if([v isKindOfClass:UITextField.class]){UITextField *f=(UITextField *)v;if(f.tag>=kZNM620RuntimeTitleTagBase&&f.tag<kZNM620RuntimeTitleTagBase+512)[runtimeNames addObject:f];else if(f.tag>=kZNM620StaticNameTagBase&&f.tag<kZNM620StaticNameTagBase+512)[staticNames addObject:f];}[stack addObjectsFromArray:v.subviews?:@[]];}
    }
    [runtimeNames sortUsingComparator:^NSComparisonResult(UITextField *a,UITextField *b){return CGRectGetMinY(a.superview.frame)<CGRectGetMinY(b.superview.frame)?NSOrderedAscending:NSOrderedDescending;}];
    [staticNames sortUsingComparator:^NSComparisonResult(UITextField *a,UITextField *b){return CGRectGetMinY(a.superview.frame)<CGRectGetMinY(b.superview.frame)?NSOrderedAscending:NSOrderedDescending;}];

    NSArray<ZNRuntimeMethodAction *> *actions=[[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for(UITextField *name in runtimeNames){
        NSInteger index=name.tag-kZNM620RuntimeTitleTagBase;if(index<0||(NSUInteger)index>=actions.count)continue;
        UIView *card=name.superview;if(!card||[card viewWithTag:kZNM620RuntimeDescriptionTagBase+index])continue;
        CGFloat oldMax=CGRectGetMaxY(card.frame);CGFloat delta=38.0;
        ZNM620ShiftFollowingSubviews(self.contentView,oldMax+0.5,delta,card);
        CGRect cf=card.frame;cf.size.height+=delta;card.frame=cf;
        UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(13,39,38,29)];label.text=@"说明";label.font=[UIFont systemFontOfSize:8.4 weight:UIFontWeightMedium];label.textColor=UIColor.secondaryLabelColor;[card addSubview:label];
        ZNRuntimeMethodAction *action=actions[(NSUInteger)index];
        UITextField *desc=ZNM620DescriptionField(CGRectMake(52,39,MAX(80.0,card.bounds.size.width-65),29),kZNM620RuntimeDescriptionTagBase+index,ZNM620RuntimeDescription(action),@selector(znm620_runtimeDescriptionEnded:),self);
        [card addSubview:desc];
        for(UIView *sub in card.subviews){if(sub==label||sub==desc||sub==name)continue;if(CGRectGetMinY(sub.frame)>=39){CGRect f=sub.frame;f.origin.y+=delta;sub.frame=f;}}
    }

    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    for(UITextField *name in staticNames){
        NSInteger featureIndex=name.tag-kZNM620StaticNameTagBase;if(featureIndex<0)continue;
        UIView *card=name.superview;if(!card||[card viewWithTag:kZNM620StaticDescriptionTagBase+featureIndex])continue;
        NSString *featureName=ZNM620Trim(name.text);if(!featureName.length)continue;
        CGFloat oldMax=CGRectGetMaxY(card.frame);CGFloat delta=38.0;
        ZNM620ShiftFollowingSubviews(self.contentView,oldMax+0.5,delta,card);
        CGRect cf=card.frame;cf.size.height+=delta;card.frame=cf;
        UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(18,43,38,29)];label.text=@"说明";label.font=[UIFont systemFontOfSize:8.4 weight:UIFontWeightMedium];label.textColor=UIColor.secondaryLabelColor;[card addSubview:label];
        UITextField *desc=ZNM620DescriptionField(CGRectMake(63,43,MAX(80.0,card.bounds.size.width-78),29),kZNM620StaticDescriptionTagBase+featureIndex,ZNM620StaticDescription(featureName),@selector(znm620_staticDescriptionEnded:),self);
        objc_setAssociatedObject(desc,@selector(znm620_staticDescriptionEnded:),featureName,OBJC_ASSOCIATION_COPY_NONATOMIC);
        [card addSubview:desc];
    }

    CGFloat maxY=0;for(UIView *v in self.contentView.subviews)maxY=MAX(maxY,CGRectGetMaxY(v.frame));[self zn40_updateContentHeight:maxY+8.0];
    (void)workspace;
}

- (void)znm620_runtimeDescriptionEnded:(UITextField *)field {
    NSInteger index=field.tag-kZNM620RuntimeDescriptionTagBase;if(index>=0)ZNM620SetRuntimeDescriptionAtIndex((NSUInteger)index,field.text);
    [field resignFirstResponder];
}

- (void)znm620_staticDescriptionEnded:(UITextField *)field {
    NSString *feature=objc_getAssociatedObject(field,@selector(znm620_staticDescriptionEnded:));if(!feature.length)return;
    NSString *value=ZNM620Trim(field.text);ZNM620SetStaticDescription(feature,value);
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    for(ZNBinaryPatchRow *row in workspace.rows){if([ZNM620Trim(row.group) caseInsensitiveCompare:feature]==NSOrderedSame)row.title=value.length?value:@"Patch #1";}
    // Trigger existing M5.9.2 workspace persistence.
    [workspace updateDefaultTarget:workspace.defaultTarget];
    [field resignFirstResponder];
}

- (void)znm620_renderRuntime:(BOOL)compact {
    [self znm620_renderRuntime:compact];
    ZNRuntimeActionRuntime *runtime=[ZNRuntimeActionRuntime sharedRuntime];[runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *records=runtime.records?:@[];
    for(NSUInteger i=0;i<records.count;i++){
        UIView *card=[self.contentView viewWithTag:kZNM620RuntimeCardBase+(NSInteger)i];if(!card)continue;
        ZNRuntimeMethodActionRecord *record=records[i];
        NSString *description=ZNM620Trim(record.group);
        if([description caseInsensitiveCompare:@"Runtime Methods"]==NSOrderedSame)description=@"";
        NSMutableArray<UILabel *> *labels=[NSMutableArray array];
        NSMutableArray *stack=[NSMutableArray arrayWithArray:card.subviews?:@[]];
        while(stack.count){UIView *v=stack.lastObject;[stack removeLastObject];if([v isKindOfClass:UILabel.class])[labels addObject:(UILabel *)v];[stack addObjectsFromArray:v.subviews?:@[]];}
        UILabel *subtitle=nil;
        for(UILabel *label in labels){NSString *t=label.text?:@"";if([t hasPrefix:@"参数 "]||[t hasSuffix:@" 个参数"]){if(!subtitle||CGRectGetMinY(label.frame)<CGRectGetMinY(subtitle.frame))subtitle=label;}}
        if(subtitle)subtitle.text=description;
        for(UILabel *label in labels){NSString *t=label.text?:@"";if([t hasPrefix:@"参数"]&&label!=subtitle)label.hidden=YES;}
    }
}
@end

// During M6.1 Offset->Runtime promotion, carry the authoring description into
// the Runtime action's existing group field. The on-disk Runtime ABI is unchanged.
@interface ZNRuntimeActionStore (ZNM620Promotion)
- (ZNRuntimeMethodAction *)znm620_addMethodCandidate:(NSDictionary<NSString *,id> *)candidate title:(NSString *)title argumentValues:(NSArray<NSString *> *)argumentValues error:(NSString **)error;
@end
@implementation ZNRuntimeActionStore (ZNM620Promotion)
- (ZNRuntimeMethodAction *)znm620_addMethodCandidate:(NSDictionary<NSString *,id> *)candidate title:(NSString *)title argumentValues:(NSArray<NSString *> *)argumentValues error:(NSString **)error {
    ZNRuntimeMethodAction *result=[self znm620_addMethodCandidate:candidate title:title argumentValues:argumentValues error:error];
    if(!result)return nil;
    uint64_t rva=[candidate[@"methodRVA"] unsignedLongLongValue];NSString *description=gZNM620PromotionDescriptions[@(rva)];
    if(!description.length){NSDictionary *root=[NSUserDefaults.standardUserDefaults objectForKey:kZNM620RuntimeDescriptionsKey];id saved=[root isKindOfClass:NSDictionary.class]?root[ZNM620RuntimeKey(result)]:nil;if([saved isKindOfClass:NSString.class])description=saved;}
    if(description.length){NSArray *snapshot=[self actionsSnapshot];if(snapshot.count)ZNM620SetRuntimeDescriptionAtIndex(snapshot.count-1,description);result.group=description;}
    return result;
}
@end

@interface ZNStaticBinaryBuilder (ZNM620DescriptionBridge)
+ (BOOL)znm620_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end
@implementation ZNStaticBinaryBuilder (ZNM620DescriptionBridge)
+ (BOOL)znm620_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    gZNM620PromotionDescriptions=[NSMutableDictionary dictionary];
    for(ZNBinaryPatchRow *row in workspace.rows){
        NSString *feature=ZNM620FeatureName(row);NSString *description=ZNM620StaticDescription(feature);
        if(description.length){row.title=description;NSString *s=ZNM620Trim(row.offsetText).lowercaseString;char *end=NULL;unsigned long long rva=strtoull(s.UTF8String,&end,0);if(end==s.UTF8String||*end){end=NULL;rva=strtoull(s.UTF8String,&end,16);}if(end&&end!=s.UTF8String&&!*end)gZNM620PromotionDescriptions[@((uint64_t)rva)]=description;}
    }
    BOOL ok=[self znm620_buildWorkspace:workspace outputs:outputs report:report error:error];
    gZNM620PromotionDescriptions=nil;
    return ok;
}
@end

static void ZNM620SwapInstance(Class cls,SEL a,SEL b){Method ma=class_getInstanceMethod(cls,a),mb=class_getInstanceMethod(cls,b);if(ma&&mb)method_exchangeImplementations(ma,mb);}
static void ZNM620SwapClass(Class cls,SEL a,SEL b){Method ma=class_getClassMethod(cls,a),mb=class_getClassMethod(cls,b);if(ma&&mb)method_exchangeImplementations(ma,mb);}

extern "C" void ZNInstallM620UnifiedAuthoringUIDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class menu=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        ZNM620SwapInstance(menu,@selector(zn50b_renderOther),@selector(znm620_renderOther));
        ZNM620SwapInstance(menu,@selector(zn51_renderRuntime:),@selector(znm620_renderRuntime:));
        Class store=ZNRuntimeActionStore.class;
        ZNM620SwapInstance(store,@selector(addMethodCandidate:title:argumentValues:error:),@selector(znm620_addMethodCandidate:title:argumentValues:error:));
        Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");
        ZNM620SwapClass(builder,@selector(buildWorkspace:outputs:report:error:),@selector(znm620_buildWorkspace:outputs:report:error:));
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.2] unified authoring descriptions installed in-place; runtime duplicate parameter labels hidden; no second UI hierarchy"];
    });
}

__attribute__((constructor)) static void ZNM620Bootstrap(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ZNInstallM620UnifiedAuthoringUIDeferred();});
}
