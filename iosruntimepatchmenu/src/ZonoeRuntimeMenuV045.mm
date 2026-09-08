#include "ZonoeRuntimeMenuV044.mm"
#import "ZNDeveloperGate.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNPatchCore.h"

// v0.4.5 UI cleanup layer.
// Public runtime Patch UI is intentionally reduced to one `功能` category.
// `其他` remains q-gated for the developer Binary Builder; g still controls
// Diagnostics + Debug. All generated Static Dispatch records are shown in 功能.

@interface ZNRuntimeMenuControllerV040 (V045Base)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial;
- (void)updateSidebar;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V045)
- (NSArray<NSString *> *)zn45_baseCategories;
- (NSArray<NSString *> *)zn45_baseSymbols;
- (void)zn45_renderFullPage;
- (void)zn45_renderCompactPage;
- (void)zn45_renderFeaturePage;
- (CGSize)zn45_fullSizeForWindow:(UIWindow *)window;
- (void)zn45_themeTapped:(id)sender;
- (void)zn45_makeUI:(UIWindow *)window;
- (void)zn45_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (V045)

- (NSArray<NSString *> *)zn45_baseCategories {
    NSMutableArray<NSString *> *items=[NSMutableArray arrayWithObject:@"功能"];
    if ([ZNDeveloperGate sharedGate].otherAuthorized) [items addObject:@"其他"];
    [items addObjectsFromArray:@[@"设置",@"主题"]];
    return items;
}

- (NSArray<NSString *> *)zn45_baseSymbols {
    NSMutableArray<NSString *> *items=[NSMutableArray arrayWithObject:@"switch.2"];
    if ([ZNDeveloperGate sharedGate].otherAuthorized) [items addObject:@"square.grid.2x2.fill"];
    [items addObjectsFromArray:@[@"gearshape.fill",@"paintpalette.fill"]];
    return items;
}

- (void)zn45_renderFeaturePage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=9.0;
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];

    [self addSection:@"功能" subtitle:@"所有 Runtime Patch 统一显示在这里" y:&y width:width];
    if (!runtime.records.count) {
        [self zn40_addInfoCard:@"暂无 Patch" lines:@[
            @"当前安装包没有检测到 Static Dispatch Patch。",
            @"开发者可在“其他”中导入 JSON、验证并生成新二进制后重新签名安装。"
        ] y:&y width:width];
        [self zn40_updateContentHeight:y];
        return;
    }

    for (NSUInteger i=0;i<runtime.records.count;i++) {
        ZNStaticPatchRecord *r=runtime.records[i];
        UIView *card=[self cardAtY:y height:52 width:width compact:NO];
        NSString *title=r.title.length?r.title:[NSString stringWithFormat:@"Patch #%u",r.patchID];
        UILabel *name=[self label:title size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame=CGRectMake(13,6,card.bounds.size.width-96,18);
        name.lineBreakMode=NSLineBreakByTruncatingMiddle;
        [card addSubview:name];
        UILabel *detail=[self label:[NSString stringWithFormat:@"%@ + 0x%llX · ID %u",r.target,r.siteRVA,r.patchID] size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        detail.frame=CGRectMake(13,27,card.bounds.size.width-96,16);
        detail.lineBreakMode=NSLineBreakByTruncatingMiddle;
        [card addSubview:detail];
        UIButton *toggle=[self zn40_button:r.enabled?@"ON":@"OFF" selector:@selector(zn44_toggleStatic:) frame:CGRectMake(card.bounds.size.width-72,9,60,34)];
        toggle.tag=447000+i;
        [card addSubview:toggle];
        [self.contentView addSubview:card];
        y+=58;
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn45_renderFullPage {
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    if ([cat isEqualToString:@"功能"]) { [self zn45_renderFeaturePage]; return; }
    [self zn45_renderFullPage];
}

- (void)zn45_renderCompactPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=7.0;
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    if (!runtime.records.count) {
        UIView *card=[self cardAtY:y height:44 width:width compact:YES];
        UILabel *label=[self label:@"暂无 Runtime Patch" size:11.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame=CGRectMake(9,11,card.bounds.size.width-18,20);
        [card addSubview:label];
        [self.contentView addSubview:card];
        y+=50;
    } else {
        for (NSUInteger i=0;i<runtime.records.count;i++) {
            ZNStaticPatchRecord *r=runtime.records[i];
            UIView *card=[self cardAtY:y height:42 width:width compact:YES];
            NSString *title=r.title.length?r.title:[NSString stringWithFormat:@"Patch #%u",r.patchID];
            UILabel *label=[self label:title size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            label.frame=CGRectMake(9,10,card.bounds.size.width-80,20);
            label.lineBreakMode=NSLineBreakByTruncatingMiddle;
            [card addSubview:label];
            UIButton *toggle=[self zn40_button:r.enabled?@"ON":@"OFF" selector:@selector(zn44_toggleStatic:) frame:CGRectMake(card.bounds.size.width-65,7,56,28)];
            toggle.tag=447000+i;
            [card addSubview:toggle];
            [self.contentView addSubview:card];
            y+=48;
        }
    }
    [self zn40_updateContentHeight:y];
}

- (CGSize)zn45_fullSizeForWindow:(UIWindow *)window {
    CGSize size=[self zn45_fullSizeForWindow:window];
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    UIEdgeInsets insets=window.safeAreaInsets;
    CGFloat available=CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0;
    if ([cat isEqualToString:@"功能"]) size.height=MIN(MAX(size.height,390.0),MAX(300.0,available));
    if ([cat isEqualToString:@"主题"]) size.height=MIN(MAX(size.height,430.0),MAX(300.0,available));
    return size;
}

- (void)zn45_themeTapped:(id)sender {
    (void)sender;
    if (self.compactMode) return;
    NSInteger idx=[self.categories indexOfObject:@"主题"];
    if (idx==NSNotFound) return;
    self.selectedCategory=idx;
    [NSUserDefaults.standardUserDefaults setInteger:idx forKey:@"ZonoePatch.SelectedCategory"];
    self.contentScroll.contentOffset=CGPointZero;
    [self layoutForWindow:self.hostWindow initial:NO];
    [self updateSidebar];
    [self renderPage];
}

- (void)zn45_makeUI:(UIWindow *)window {
    [self zn45_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.5    Function + Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn45_tick:(NSTimer *)timer {
    [self zn45_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.5    Function + Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV045(Class cls,SEL a,SEL b){
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if(x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(111))) static void ZNInstallV045FunctionUI(void){
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls) return;
        ZNSwapV045(cls,@selector(zn40_baseCategories),@selector(zn45_baseCategories));
        ZNSwapV045(cls,@selector(zn40_baseSymbols),@selector(zn45_baseSymbols));
        ZNSwapV045(cls,@selector(renderFullPage),@selector(zn45_renderFullPage));
        ZNSwapV045(cls,@selector(renderCompactPage),@selector(zn45_renderCompactPage));
        ZNSwapV045(cls,@selector(fullSizeForWindow:),@selector(zn45_fullSizeForWindow:));
        ZNSwapV045(cls,@selector(themeTapped:),@selector(zn45_themeTapped:));
        ZNSwapV045(cls,@selector(makeUI:),@selector(zn45_makeUI:));
        ZNSwapV045(cls,@selector(tick:),@selector(zn45_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.5 single Function category installed; q=Other, g=Diagnostics/Debug"];
    }
}
