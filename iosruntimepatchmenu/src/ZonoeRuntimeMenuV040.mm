#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ZNPatchCore.h"
#import "ZNDeveloperGate.h"
#import "ZNIL2CPPResolver.h"

static void ZNInstallV040Swizzles(void);

__attribute__((constructor(101))) static void ZNRuntimeCoreBootstrapV040(void) {
    @autoreleasepool {
        [ZNPatchManager sharedManager];
        [[ZNDeveloperGate sharedGate] refresh];
        [[ZNIL2CPPResolver sharedResolver] refresh];
        ZNInstallV040Swizzles();
        [[ZNRuntimeLogger sharedLogger] log:@"Runtime Patch Foundation 0.4.0 bootstrap（Stock iOS / No JIT）"];
    }
}

// v0.2.4 remains the immutable visual baseline. v0.4 only layers runtime core,
// developer diagnostics and resolver state over it.
#define ZNRuntimeMenuControllerV024 ZNRuntimeMenuControllerV040
#define ZonoePatchGetAPIVersion ZonoePatchGetAPIVersionBaselineV024
#define ZonoePatchGetVersion ZonoePatchGetVersionBaselineV024
#define ZonoePatchStart ZonoePatchStartBaselineV024
#define ZonoePatchShow ZonoePatchShowBaselineV024
#define ZonoePatchHide ZonoePatchHideBaselineV024
#define ZonoePatchIsVisible ZonoePatchIsVisibleBaselineV024
#define ZNRuntimeMenuBootstrapV024 ZNRuntimeMenuBootstrapBaselineV024
#include "ZonoeRuntimeMenuV024.mm"
#undef ZNRuntimeMenuControllerV024
#undef ZonoePatchGetAPIVersion
#undef ZonoePatchGetVersion
#undef ZonoePatchStart
#undef ZonoePatchShow
#undef ZonoePatchHide
#undef ZonoePatchIsVisible
#undef ZNRuntimeMenuBootstrapV024

@interface ZNRuntimeMenuControllerV040 (V040Private)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)layoutSidebar;
- (void)updateSidebar;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V040)
- (instancetype)zn40_init;
- (BOOL)zn40_enabledForFeature:(NSString *)featureID;
- (void)zn40_setFeature:(NSString *)featureID enabled:(BOOL)enabled;
- (CGFloat)zn40_valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback;
- (void)zn40_setFeature:(NSString *)featureID value:(CGFloat)value;
- (void)zn40_renderFullPage;
- (CGSize)zn40_fullSizeForWindow:(UIWindow *)window;
- (void)zn40_tick:(NSTimer *)timer;
- (void)zn40_makeUI:(UIWindow *)window;
- (void)zn40_togglePanel:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V040)

- (instancetype)zn40_init {
    id obj = [self zn40_init];
    if (!obj) return nil;
    [ZNPatchManager sharedManager];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    return obj;
}

- (BOOL)zn40_enabledForFeature:(NSString *)featureID {
    return [[ZNPatchManager sharedManager] enabledForFeature:featureID];
}

- (void)zn40_setFeature:(NSString *)featureID enabled:(BOOL)enabled {
    [[ZNPatchManager sharedManager] setFeature:featureID enabled:enabled];
}

- (CGFloat)zn40_valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback {
    return (CGFloat)[[ZNPatchManager sharedManager] valueForFeature:featureID fallback:fallback];
}

- (void)zn40_setFeature:(NSString *)featureID value:(CGFloat)value {
    [[ZNPatchManager sharedManager] setFeature:featureID value:value];
}

- (NSArray<NSString *> *)zn40_baseCategories {
    return @[@"首页", @"玩家", @"战斗", @"移动", @"其他", @"设置", @"主题"];
}

- (NSArray<NSString *> *)zn40_baseSymbols {
    return @[@"house.fill", @"person.fill", @"bolt.fill", @"location.north.fill", @"square.grid.2x2.fill", @"gearshape.fill", @"paintpalette.fill"];
}

- (void)zn40_refreshDeveloperCategories:(BOOL)force {
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    NSMutableArray<NSString *> *cats = [[self zn40_baseCategories] mutableCopy];
    NSMutableArray<NSString *> *symbols = [[self zn40_baseSymbols] mutableCopy];
    if (gate.authorized) {
        [cats addObject:@"诊断"];
        [symbols addObject:@"stethoscope"];
        [cats addObject:@"Debug"];
        [symbols addObject:@"ladybug.fill"];
    }
    if (!force && [self.categories isEqualToArray:cats]) return;

    NSString *oldCategory = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"首页";
    self.categories = cats;
    self.categorySymbols = symbols;
    NSInteger newIndex = [cats indexOfObject:oldCategory];
    if (newIndex == NSNotFound) newIndex = 0;
    self.selectedCategory = newIndex;
    [NSUserDefaults.standardUserDefaults setInteger:self.selectedCategory forKey:@"ZonoePatch.SelectedCategory"];

    if (!self.uiReady || !self.sidebarView) return;
    for (UIButton *button in [self.sidebarButtons copy]) [button removeFromSuperview];
    [self.sidebarButtons removeAllObjects];
    for (NSInteger i=0; i<self.categories.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 3000+i;
        b.layer.cornerRadius = 7;
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0,8,0,3);
        [b setImage:ZNSymbol(self.categorySymbols[i],12.5,UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
        [b setTitle:[NSString stringWithFormat:@"  %@",self.categories[i]] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.sidebarView addSubview:b];
        [self.sidebarButtons addObject:b];
    }
    [self layoutSidebar];
    [self updateSidebar];
    [self renderPage];
}

- (void)zn40_updateSubtitle {
    if (!self.uiReady || !self.subtitleLabel) return;
    NSString *value = [ZNDeveloperGate sharedGate].observedUDID ?: @"";
    self.subtitleLabel.text = value.length ? value : @"";
    self.subtitleLabel.adjustsFontSizeToFitWidth = YES;
    self.subtitleLabel.minimumScaleFactor = 0.42;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
}

- (void)zn40_makeUI:(UIWindow *)window {
    [self zn40_makeUI:window];
    [self zn40_refreshDeveloperCategories:YES];
    [self zn40_updateSubtitle];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.0    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn40_tick:(NSTimer *)timer {
    [self zn40_tick:timer];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    [self zn40_updateSubtitle];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.0    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn40_togglePanel:(id)sender {
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    [self zn40_togglePanel:sender];
    [self zn40_updateSubtitle];
}

- (CGSize)zn40_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn40_fullSizeForWindow:window];
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"]) {
        UIEdgeInsets insets = window.safeAreaInsets;
        CGFloat available = CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0;
        size.height = MIN(MAX(size.height, 470.0), MAX(300.0, available));
    }
    return size;
}

- (void)zn40_updateContentHeight:(CGFloat)y {
    CGRect frame = self.contentView.frame;
    frame.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y+8.0);
    self.contentView.frame = frame;
    self.contentScroll.contentSize = frame.size;
}

- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width {
    CGFloat lineH = 17.0;
    CGFloat h = 30.0 + lineH*lines.count + 8.0;
    UIView *card = [self cardAtY:*y height:h width:width compact:NO];
    UILabel *t = [self label:title size:12.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(13,7,card.bounds.size.width-26,19);
    [card addSubview:t];
    CGFloat ly = 28.0;
    for (NSString *line in lines) {
        UILabel *l = [self label:line size:9.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        l.frame = CGRectMake(13,ly,card.bounds.size.width-26,lineH);
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.65;
        [card addSubview:l];
        ly += lineH;
    }
    [self.contentView addSubview:card];
    *y += h+8.0;
}

- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    b.backgroundColor = self.theme.controlColor;
    b.tintColor = self.theme.accentColor;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
    b.titleLabel.font = [self menuFont:10.5 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1;
    b.layer.borderColor = self.theme.borderColor.CGColor;
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)zn40_addActionCardY:(CGFloat *)y width:(CGFloat)width titles:(NSArray<NSString *> *)titles selectors:(NSArray<NSString *> *)selectors {
    UIView *card = [self cardAtY:*y height:54 width:width compact:NO];
    CGFloat gap = 8.0;
    CGFloat inner = card.bounds.size.width-26.0;
    CGFloat bw = (inner-gap*(titles.count-1))/MAX((CGFloat)titles.count,1.0);
    for (NSInteger i=0; i<titles.count; i++) {
        CGRect f = CGRectMake(13+i*(bw+gap),10,bw,34);
        [card addSubview:[self zn40_button:titles[i] selector:NSSelectorFromString(selectors[i]) frame:f]];
    }
    [self.contentView addSubview:card];
    *y += 62.0;
}

- (void)zn40_replaceHomeVersionText {
    for (UIView *view in self.contentView.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        if ([label.text hasPrefix:@"V0.2.4 UI"]) label.text = @"V0.4.0 Runtime Foundation · No JIT";
    }
}

- (NSArray<NSString *> *)zn40_nonEmptyLines:(NSString *)text {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) if (line.length) [out addObject:line];
    return out;
}

- (void)zn40_renderDiagnostics {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = 9.0;
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    ZNPatchManager *pm = [ZNPatchManager sharedManager];
    NSDictionary *counts = pm.stateCounts;
    NSDictionary *main = [ZNModuleManager sharedManager].mainExecutable;
    NSDictionary *unity = [ZNModuleManager sharedManager].unityFramework;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"未知";
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";

    [self addSection:@"运行时诊断" subtitle:@"v0.4.0 Foundation · Stock iOS / 未越狱 / No JIT" y:&y width:width];
    [self zn40_addInfoCard:@"运行环境" lines:@[
        @"状态：基础层已就绪",
        @"核心版本：0.4.0-runtime-foundation    API：2",
        [NSString stringWithFormat:@"Bundle：%@    App：%@",bundle,version],
        [NSString stringWithFormat:@"系统：iOS %@",UIDevice.currentDevice.systemVersion],
        @"JIT：不依赖    越狱：不依赖"
    ] y:&y width:width];

    NSString *mainLine = main ? [NSString stringWithFormat:@"主程序：%@    base=0x%llx",main[@"name"],[main[@"base"] unsignedLongLongValue]] : @"主程序：未找到";
    NSString *unityLine = unity ? [NSString stringWithFormat:@"UnityFramework：已加载    base=0x%llx",[unity[@"base"] unsignedLongLongValue]] : @"UnityFramework：未加载";
    [self zn40_addInfoCard:@"模块解析" lines:@[mainLine,unityLine,[NSString stringWithFormat:@"已加载镜像：%lu",(unsigned long)[ZNModuleManager sharedManager].loadedImages.count],[NSString stringWithFormat:@"模块代数：%llu",[ZNModuleManager sharedManager].moduleGeneration]] y:&y width:width];

    [self zn40_addInfoCard:@"开发者标记" lines:@[
        [NSString stringWithFormat:@"状态：%@",gate.authorized?@"已启用":@"未启用"],
        [NSString stringWithFormat:@"来源：%@",gate.sourceDescription],
        [NSString stringWithFormat:@"文件：%@",gate.markerPath.length?gate.markerPath:@"未找到"],
        [NSString stringWithFormat:@"附加值：%@",gate.observedUDID.length?[gate maskedUDID:gate.observedUDID]:@"空白（允许）"],
        @"外部 UDID 获取：已禁用"
    ] y:&y width:width];

    [self zn40_addInfoCard:@"Feature / Action" lines:@[
        [NSString stringWithFormat:@"Feature：%@    Action：%lu",counts[@"registered"],(unsigned long)pm.actionCount],
        [NSString stringWithFormat:@"已启用：%@    已关闭：%@",counts[@"enabled"],counts[@"disabled"]],
        [NSString stringWithFormat:@"等待模块：%@    不支持：%@    失败：%@",counts[@"waiting"],counts[@"unsupported"],counts[@"failed"]],
        @"执行器：Foundation（本版本只建立模型与解析，不写真实 Patch）"
    ] y:&y width:width];

    [self zn40_addInfoCard:@"IL2CPP Resolver" lines:[self zn40_nonEmptyLines:[[ZNIL2CPPResolver sharedResolver] diagnosticReport]] y:&y width:width];
    [self zn40_addActionCardY:&y width:width titles:@[@"刷新目标解析",@"复制诊断信息"] selectors:@[@"zn40_refreshTargets:",@"zn40_copyDiagnostics:"]];
    [self zn40_addActionCardY:&y width:width titles:@[@"重新检测标记",@"运行基础自检"] selectors:@[@"zn40_validateMarker:",@"zn40_selfTest:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn40_renderDebug {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = 9.0;
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    [self addSection:@"Debug" subtitle:@"Feature / Action / 模块 / IL2CPP / 最近日志" y:&y width:width];

    [self zn40_addInfoCard:@"标记状态" lines:@[
        [NSString stringWithFormat:@"标记文件：%@",gate.markerPath.length?gate.markerPath:@"未找到"],
        [NSString stringWithFormat:@"第一行 g：%@",gate.authorized?@"有效":@"无效"],
        [NSString stringWithFormat:@"第二行附加值：%@",gate.observedUDID.length?@"已提供":@"未提供"],
        @"Host Bridge：已禁用",
        @"Local Ticket：已禁用"
    ] y:&y width:width];

    NSMutableArray<NSString *> *featureLines = [NSMutableArray array];
    for (ZNPatchDescriptor *d in [ZNPatchManager sharedManager].allDescriptors) {
        [featureLines addObject:[NSString stringWithFormat:@"%@ · %@ · %@ · value=%.2f · actions=%lu",d.identifier,ZNStringForPatchState(d.state),ZNStringForControlType(d.controlType),d.value,(unsigned long)d.actions.count]];
    }
    [self zn40_addInfoCard:@"Feature 描述" lines:featureLines y:&y width:width];

    NSArray<NSString *> *logs = [[ZNRuntimeLogger sharedLogger] recentLines:10];
    if (!logs.count) logs = @[@"暂无运行日志"];
    [self zn40_addInfoCard:@"最近日志" lines:logs y:&y width:width];
    [self zn40_addActionCardY:&y width:width titles:@[@"刷新目标解析",@"清空日志"] selectors:@[@"zn40_refreshTargets:",@"zn40_clearLogs:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn40_renderFullPage {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"]) { [self zn40_renderDiagnostics]; return; }
    if ([cat isEqualToString:@"Debug"]) { [self zn40_renderDebug]; return; }
    [self zn40_renderFullPage];
    if ([cat isEqualToString:@"首页"]) [self zn40_replaceHomeVersionText];
}

- (NSString *)zn40_fullReport {
    NSMutableString *report = [NSMutableString string];
    [report appendString:[[ZNPatchManager sharedManager] diagnosticReport]];
    [report appendString:@"\n"];
    [report appendString:[[ZNDeveloperGate sharedGate] diagnosticReport]];
    NSArray *logs = [[ZNRuntimeLogger sharedLogger] recentLines:20];
    if (logs.count) {
        [report appendString:@"\n最近日志:\n"];
        [report appendString:[logs componentsJoinedByString:@"\n"]];
        [report appendString:@"\n"];
    }
    return report;
}

- (void)zn40_refreshTargets:(id)sender {
    (void)sender;
    [[ZNPatchManager sharedManager] refreshResolution];
    [self renderPage];
}

- (void)zn40_copyDiagnostics:(id)sender {
    (void)sender;
    UIPasteboard.generalPasteboard.string = [self zn40_fullReport];
    [[ZNRuntimeLogger sharedLogger] log:@"诊断信息已复制"];
    [self renderPage];
}

- (void)zn40_validateMarker:(id)sender {
    (void)sender;
    [[ZNDeveloperGate sharedGate] requestZonoeValidation];
    [self zn40_refreshDeveloperCategories:NO];
    [self renderPage];
}

- (void)zn40_selfTest:(id)sender {
    (void)sender;
    [[ZNPatchManager sharedManager] runSelfTest];
    [self renderPage];
}

- (void)zn40_clearLogs:(id)sender {
    (void)sender;
    [[ZNRuntimeLogger sharedLogger] clear];
    [[ZNRuntimeLogger sharedLogger] log:@"日志已清空"];
    [self renderPage];
}
@end

static void ZNSwapInstanceMethodV040(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a,b);
}

static void ZNInstallV040Swizzles(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
    if (!cls) return;
    ZNSwapInstanceMethodV040(cls,@selector(init),@selector(zn40_init));
    ZNSwapInstanceMethodV040(cls,@selector(enabledForFeature:),@selector(zn40_enabledForFeature:));
    ZNSwapInstanceMethodV040(cls,@selector(setFeature:enabled:),@selector(zn40_setFeature:enabled:));
    ZNSwapInstanceMethodV040(cls,@selector(valueForFeature:fallback:),@selector(zn40_valueForFeature:fallback:));
    ZNSwapInstanceMethodV040(cls,@selector(setFeature:value:),@selector(zn40_setFeature:value:));
    ZNSwapInstanceMethodV040(cls,@selector(renderFullPage),@selector(zn40_renderFullPage));
    ZNSwapInstanceMethodV040(cls,@selector(fullSizeForWindow:),@selector(zn40_fullSizeForWindow:));
    ZNSwapInstanceMethodV040(cls,@selector(tick:),@selector(zn40_tick:));
    ZNSwapInstanceMethodV040(cls,@selector(makeUI:),@selector(zn40_makeUI:));
    ZNSwapInstanceMethodV040(cls,@selector(togglePanel:),@selector(zn40_togglePanel:));
}

extern "C" __attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void) { return 2; }
extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void) { return "0.4.0-runtime-foundation"; }
extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void) {
    [[ZNDeveloperGate sharedGate] refresh];
    [ZNPatchManager sharedManager];
    [[ZNIL2CPPResolver sharedResolver] refresh];
    ZonoePatchStartBaselineV024();
}
extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void) { ZonoePatchShowBaselineV024(); }
extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void) { ZonoePatchHideBaselineV024(); }
extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void) { return ZonoePatchIsVisibleBaselineV024(); }
