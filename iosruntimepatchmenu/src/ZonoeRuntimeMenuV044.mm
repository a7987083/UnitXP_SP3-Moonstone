#include "ZonoeRuntimeMenuV043.mm"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticDispatchRuntime.h"

// v0.4.4 developer binary-builder layer.
// `其他` is q-gated by ZNDeveloperGate. No system configuration alerts are
// used here: target/offset/enabled are edited inline, Original is live-captured.

@interface ZNRuntimeMenuControllerV040 (V044Base)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V044)
- (void)zn44_renderFullPage;
- (CGSize)zn44_fullSizeForWindow:(UIWindow *)window;
- (void)zn44_makeUI:(UIWindow *)window;
- (void)zn44_tick:(NSTimer *)timer;
- (void)zn44_renderOther;
- (void)zn44_fieldChanged:(UITextField *)field;
- (void)zn44_endEditing:(UITextField *)field;
- (void)zn44_importJSON:(id)sender;
- (void)zn44_jsonTapped:(UIButton *)sender;
- (void)zn44_addOffset:(id)sender;
- (void)zn44_validateAll:(id)sender;
- (void)zn44_applyAll:(id)sender;
- (void)zn44_restoreAll:(id)sender;
- (void)zn44_buildBinary:(id)sender;
- (void)zn44_toggleStatic:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V044)

- (UITextField *)zn44_field:(CGRect)frame text:(NSString *)text placeholder:(NSString *)placeholder tag:(NSInteger)tag enabled:(BOOL)enabled {
    UITextField *f=[[UITextField alloc] initWithFrame:frame];
    f.tag=tag; f.text=text?:@""; f.placeholder=placeholder; f.enabled=enabled;
    f.textColor=self.theme.primaryTextColor; f.backgroundColor=self.theme.controlColor;
    f.font=[self menuFont:10.5 weight:UIFontWeightMedium]; f.keyboardType=UIKeyboardTypeASCIICapable;
    f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    f.returnKeyType=UIReturnKeyDone; f.clearButtonMode=UITextFieldViewModeWhileEditing;
    f.layer.cornerRadius=7; f.layer.borderWidth=1; f.layer.borderColor=self.theme.borderColor.CGColor;
    UIView *pad=[[UIView alloc] initWithFrame:CGRectMake(0,0,8,1)]; f.leftView=pad; f.leftViewMode=UITextFieldViewModeAlways;
    [f addTarget:self action:@selector(zn44_fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [f addTarget:self action:@selector(zn44_endEditing:) forControlEvents:UIControlEventEditingDidEndOnExit];
    return f;
}

- (void)zn44_renderFullPage {
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    if([cat isEqualToString:@"其他"]){[self zn44_renderOther];return;}
    [self zn44_renderFullPage];
}

- (CGSize)zn44_fullSizeForWindow:(UIWindow *)window {
    CGSize size=[self zn44_fullSizeForWindow:window];
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    if([cat isEqualToString:@"其他"]){UIEdgeInsets insets=window.safeAreaInsets;CGFloat avail=CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20;size.height=MIN(MAX(size.height,500.0),MAX(320.0,avail));}
    return size;
}

- (void)zn44_makeUI:(UIWindow *)window {
    [self zn44_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.4    Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}
- (void)zn44_tick:(NSTimer *)timer {
    [self zn44_tick:timer]; if(self.uiReady)self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.4    Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn44_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=9.0; ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace]; [ws ensureDefaultRows];
    BOOL locked=ws.hasAnyApplied||ws.isBuilding;
    [self addSection:@"二进制生成" subtitle:@"q 开发者工具 · Inline Patch Editor · Universal JSON · Static Dispatch / No-JIT" y:&y width:width];

    UIView *targetCard=[self cardAtY:y height:58 width:width compact:NO];
    UILabel *tl=[self label:@"二进制" size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];tl.frame=CGRectMake(13,7,56,18);[targetCard addSubview:tl];
    CGFloat buttonW=76; UITextField *target=[self zn44_field:CGRectMake(68,7,targetCard.bounds.size.width-68-buttonW-20,34) text:ws.defaultTarget placeholder:@"默认主程序，可输入" tag:440000 enabled:!locked];[targetCard addSubview:target];
    UIButton *import=[self zn40_button:ws.showJSONFiles?@"收起 JSON":@"导入 JSON" selector:@selector(zn44_importJSON:) frame:CGRectMake(targetCard.bounds.size.width-buttonW-9,7,buttonW,34)];import.enabled=!locked;[targetCard addSubview:import];
    UILabel *hint=[self label:@"target 可为主程序 / UnityFramework / framework / dylib 名称" size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];hint.frame=CGRectMake(13,42,targetCard.bounds.size.width-26,13);[targetCard addSubview:hint];
    [self.contentView addSubview:targetCard];y+=66;

    if(ws.showJSONFiles){
        NSUInteger shown=MIN((NSUInteger)20,ws.jsonFiles.count);CGFloat h=34+shown*34+(ws.jsonFiles.count>shown?18:0);UIView *list=[self cardAtY:y height:h width:width compact:NO];
        UILabel *t=[self label:[NSString stringWithFormat:@"游戏数据目录 JSON · %lu",(unsigned long)ws.jsonFiles.count] size:11.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];t.frame=CGRectMake(13,7,list.bounds.size.width-26,18);[list addSubview:t];
        for(NSUInteger i=0;i<shown;i++){NSString *p=ws.jsonFiles[i];NSString *home=NSHomeDirectory();NSString *display=[p hasPrefix:home]?[p substringFromIndex:home.length]:p.lastPathComponent;UIButton *b=[self zn40_button:display selector:@selector(zn44_jsonTapped:) frame:CGRectMake(13,29+i*34,list.bounds.size.width-26,28)];b.tag=446000+i;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;b.titleLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[list addSubview:b];}
        if(ws.jsonFiles.count>shown){UILabel *more=[self label:[NSString stringWithFormat:@"仅显示前 %lu 个",(unsigned long)shown] size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];more.frame=CGRectMake(13,29+shown*34,list.bounds.size.width-26,15);[list addSubview:more];}
        [self.contentView addSubview:list];y+=h+8;
    }

    for(NSUInteger i=0;i<ws.rows.count;i++){
        ZNBinaryPatchRow *r=ws.rows[i];CGFloat h=92;UIView *card=[self cardAtY:y height:h width:width compact:NO];
        NSString *rowTitle=[NSString stringWithFormat:@"#%lu",(unsigned long)i+1];if(r.explicitTarget&&r.target.length)rowTitle=[rowTitle stringByAppendingFormat:@" · %@",r.target];if(r.title.length)rowTitle=[rowTitle stringByAppendingFormat:@" · %@",r.title];
        UILabel *head=[self label:rowTitle size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];head.frame=CGRectMake(13,5,card.bounds.size.width-26,15);head.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:head];
        UILabel *ol=[self label:@"Offset" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];ol.frame=CGRectMake(13,23,48,28);[card addSubview:ol];UITextField *of=[self zn44_field:CGRectMake(58,22,card.bounds.size.width-71,29) text:r.offsetText placeholder:@"0x..." tag:441000+i enabled:!locked];[card addSubview:of];
        UILabel *el=[self label:@"Enabled" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];el.frame=CGRectMake(13,53,48,28);[card addSubview:el];UITextField *ef=[self zn44_field:CGRectMake(58,52,card.bounds.size.width-71,29) text:r.enabledText placeholder:@"ARM64 HEX" tag:442000+i enabled:!locked];ef.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;[card addSubview:ef];
        NSString *orig=r.originalHex.length?r.originalHex:@"-";NSString *line=[NSString stringWithFormat:@"Original  %@",orig];if(r.statusText.length)line=[line stringByAppendingFormat:@"   %@",r.statusText];UILabel *st=[self label:line size:8.3 weight:UIFontWeightRegular color:r.conflict?UIColor.systemOrangeColor:self.theme.secondaryTextColor];st.frame=CGRectMake(13,80,card.bounds.size.width-26,11);st.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:st];
        [self.contentView addSubview:card];y+=h+6;
    }

    UIView *addCard=[self cardAtY:y height:48 width:width compact:NO];UIButton *add=[self zn40_button:@"＋ 增加 Offset" selector:@selector(zn44_addOffset:) frame:CGRectMake(13,7,addCard.bounds.size.width-26,34)];add.enabled=!locked;[addCard addSubview:add];[self.contentView addSubview:addCard];y+=56;

    UIView *summary=[self cardAtY:y height:44 width:width compact:NO];UILabel *sl=[self label:[NSString stringWithFormat:@"已填写 %lu / %lu · 已验证 %lu%@",(unsigned long)ws.filledCount,(unsigned long)ws.rows.count,(unsigned long)ws.validatedCount,ws.hasAnyApplied?@" · Runtime 已应用":(ws.isBuilding?@" · 正在生成…":@"")] size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];sl.frame=CGRectMake(13,6,summary.bounds.size.width-26,16);[summary addSubview:sl];UILabel *ss=[self label:ws.lastStatus?:@"" size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];ss.frame=CGRectMake(13,23,summary.bounds.size.width-26,15);ss.lineBreakMode=NSLineBreakByTruncatingMiddle;[summary addSubview:ss];[self.contentView addSubview:summary];y+=52;

    UIView *a1=[self cardAtY:y height:52 width:width compact:NO];CGFloat gap=8,inner=a1.bounds.size.width-26,bw=(inner-gap)/2;UIButton *v=[self zn40_button:@"读取验证" selector:@selector(zn44_validateAll:) frame:CGRectMake(13,9,bw,34)];UIButton *ap=[self zn40_button:@"临时应用" selector:@selector(zn44_applyAll:) frame:CGRectMake(13+bw+gap,9,bw,34)];v.enabled=!ws.isBuilding&&!ws.hasAnyApplied;ap.enabled=!ws.isBuilding&&!ws.hasAnyApplied;[a1 addSubview:v];[a1 addSubview:ap];[self.contentView addSubview:a1];y+=60;
    UIView *a2=[self cardAtY:y height:52 width:width compact:NO];UIButton *rs=[self zn40_button:@"恢复全部" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13,9,bw,34)];UIButton *build=[self zn40_button:ws.isBuilding?@"正在生成…":@"生成新二进制" selector:@selector(zn44_buildBinary:) frame:CGRectMake(13+bw+gap,9,bw,34)];rs.enabled=!ws.isBuilding&&ws.hasAnyApplied;build.enabled=!ws.isBuilding&&!ws.hasAnyApplied&&ws.validatedCount==ws.filledCount&&ws.filledCount>0;[a2 addSubview:rs];[a2 addSubview:build];[self.contentView addSubview:a2];y+=60;

    if(ws.lastOutputPaths.count){NSMutableArray *lines=[NSMutableArray array];for(NSUInteger i=0;i<MIN((NSUInteger)4,ws.lastOutputPaths.count);i++){NSString *p=ws.lastOutputPaths[i];[lines addObject:[p hasPrefix:NSHomeDirectory()]?[p substringFromIndex:NSHomeDirectory().length]:p];}[self zn40_addInfoCard:@"最近输出" lines:lines y:&y width:width];}

    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];[runtime refresh];
    if(runtime.records.count){[self addSection:@"已生成 Static Dispatch" subtitle:@"当前安装包已预处理 · 这里只切换 RW selectedTarget，不修改 RX" y:&y width:width];
        NSUInteger shown=MIN((NSUInteger)40,runtime.records.count);for(NSUInteger i=0;i<shown;i++){ZNStaticPatchRecord *r=runtime.records[i];UIView *c=[self cardAtY:y height:48 width:width compact:NO];UILabel *l=[self label:[NSString stringWithFormat:@"%@ · %@+0x%llX",r.title,r.target,r.siteRVA] size:9.4 weight:UIFontWeightMedium color:self.theme.primaryTextColor];l.frame=CGRectMake(13,6,c.bounds.size.width-94,17);l.lineBreakMode=NSLineBreakByTruncatingMiddle;[c addSubview:l];UILabel *g=[self label:[NSString stringWithFormat:@"%@ · PatchID %u",r.group,r.patchID] size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];g.frame=CGRectMake(13,24,c.bounds.size.width-94,15);[c addSubview:g];UIButton *b=[self zn40_button:r.enabled?@"ON":@"OFF" selector:@selector(zn44_toggleStatic:) frame:CGRectMake(c.bounds.size.width-72,7,60,34)];b.tag=447000+i;[c addSubview:b];[self.contentView addSubview:c];y+=54;}}

    [self zn40_updateContentHeight:y];
}

- (void)zn44_fieldChanged:(UITextField *)f {
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(f.tag==440000){[ws updateDefaultTarget:f.text?:@""];return;}if(f.tag>=441000&&f.tag<442000){[ws updateOffset:f.text?:@"" row:(NSUInteger)(f.tag-441000)];return;}if(f.tag>=442000&&f.tag<443000){[ws updateEnabled:f.text?:@"" row:(NSUInteger)(f.tag-442000)];return;}
}
- (void)zn44_endEditing:(UITextField *)field {(void)field;[self.hostWindow endEditing:YES];}
- (void)zn44_importJSON:(id)sender {(void)sender;ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(ws.showJSONFiles)ws.showJSONFiles=NO;else{[ws refreshJSONFiles];ws.showJSONFiles=YES;}[self renderPage];}
- (void)zn44_jsonTapped:(UIButton *)sender {ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSUInteger i=(NSUInteger)(sender.tag-446000);if(i>=ws.jsonFiles.count)return;NSString *e=nil;if(![ws importJSONAtPath:ws.jsonFiles[i] error:&e])ws.lastStatus=[NSString stringWithFormat:@"导入失败：%@",e?:@"未知错误"];[self renderPage];}
- (void)zn44_addOffset:(id)sender {(void)sender;[[ZNBinaryPatchWorkspace sharedWorkspace] addEmptyRow];[self renderPage];}
- (void)zn44_validateAll:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *e=nil;[ws validateAll:&e];if(e.length&&![ws.lastStatus containsString:e])[[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] validate: %@",e]];[self renderPage];}
- (void)zn44_applyAll:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *e=nil;if(![ws applyAll:&e]&&e.length)[[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] apply: %@",e]];[self renderPage];}
- (void)zn44_restoreAll:(id)sender {(void)sender;ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *e=nil;if(![ws restoreAll:&e]&&e.length)[[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] restore: %@",e]];[self renderPage];}
- (void)zn44_buildBinary:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(ws.isBuilding)return;if(ws.hasAnyApplied){ws.lastStatus=@"生成前必须先恢复 Runtime Patch";[self renderPage];return;}ws.building=YES;ws.lastStatus=@"正在生成：验证 Mach-O / 安全 gap / relocation…";[self renderPage];__weak typeof(self) weakSelf=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSArray *paths=nil;NSString *report=nil,*error=nil;BOOL ok=[ZNStaticBinaryBuilder buildWorkspace:ws outputs:&paths report:&report error:&error];dispatch_async(dispatch_get_main_queue(),^{ws.building=NO;if(ok)[ws setBuildOutputs:paths status:report?:@"生成成功"];else[ws setBuildOutputs:@[] status:[NSString stringWithFormat:@"生成失败：%@",error?:@"未知错误"]];[weakSelf renderPage];});});}
- (void)zn44_toggleStatic:(UIButton *)sender {ZNStaticDispatchRuntime *rt=[ZNStaticDispatchRuntime sharedRuntime];NSUInteger i=(NSUInteger)(sender.tag-447000);if(i>=rt.records.count)return;ZNStaticPatchRecord *r=rt.records[i];NSString *e=nil;if(![rt setEnabled:!r.enabled forRecord:r error:&e])[[ZNBinaryPatchWorkspace sharedWorkspace] setBuildOutputs:[ZNBinaryPatchWorkspace sharedWorkspace].lastOutputPaths status:[NSString stringWithFormat:@"Static Dispatch 切换失败：%@",e?:@"未知错误"]];[self renderPage];}
@end

static void ZNSwapV044(Class cls,SEL a,SEL b){Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);if(x&&y)method_exchangeImplementations(x,y);}
__attribute__((constructor(110))) static void ZNInstallV044BinaryBuilder(void){@autoreleasepool{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;ZNSwapV044(cls,@selector(renderFullPage),@selector(zn44_renderFullPage));ZNSwapV044(cls,@selector(fullSizeForWindow:),@selector(zn44_fullSizeForWindow:));ZNSwapV044(cls,@selector(makeUI:),@selector(zn44_makeUI:));ZNSwapV044(cls,@selector(tick:),@selector(zn44_tick:));[[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.4 embedded patch editor / universal JSON / static binary builder installed"];}}
