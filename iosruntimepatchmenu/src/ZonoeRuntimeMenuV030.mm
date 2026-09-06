#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ZNPatchCore.h"
#import "ZNDeveloperGate.h"

static void ZNInstallV030Swizzles(void);

__attribute__((constructor(101))) static void ZNRuntimeCoreBootstrapV030(void) {
    @autoreleasepool {
        [ZNPatchManager sharedManager];
        [[ZNDeveloperGate sharedGate] refresh];
        ZNInstallV030Swizzles();
        [[ZNRuntimeLogger sharedLogger] log:@"Runtime Core 0.3.1 local-ticket bootstrap"];
    }
}

// Keep v0.2.4 as an immutable UI baseline. Compile it through this translation
// unit with renamed class/API symbols, then layer v0.3 Patch Core/Diagnostics on
// top through narrow runtime method exchanges.
#define ZNRuntimeMenuControllerV024 ZNRuntimeMenuControllerV030
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

@interface ZNRuntimeMenuControllerV030 (V030Private)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)layoutSidebar;
- (void)updateSidebar;
- (void)renderPage;
- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial;
@end

@interface ZNRuntimeMenuControllerV030 (V030)
- (instancetype)zn30_init;
- (BOOL)zn30_enabledForFeature:(NSString *)featureID;
- (void)zn30_setFeature:(NSString *)featureID enabled:(BOOL)enabled;
- (CGFloat)zn30_valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback;
- (void)zn30_setFeature:(NSString *)featureID value:(CGFloat)value;
- (void)zn30_renderFullPage;
- (CGSize)zn30_fullSizeForWindow:(UIWindow *)window;
- (void)zn30_tick:(NSTimer *)timer;
- (void)zn30_makeUI:(UIWindow *)window;
- (void)zn30_togglePanel:(id)sender;
- (void)zn30_refreshDeveloperCategories:(BOOL)force;
- (void)zn31_updateIdentitySubtitle;
@end

@implementation ZNRuntimeMenuControllerV030 (V030)

- (instancetype)zn30_init {
    id obj = [self zn30_init];
    if (!obj) return nil;
    [ZNPatchManager sharedManager];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn30_refreshDeveloperCategories:NO];
    return obj;
}

- (BOOL)zn30_enabledForFeature:(NSString *)featureID {
    return [[ZNPatchManager sharedManager] enabledForFeature:featureID];
}

- (void)zn30_setFeature:(NSString *)featureID enabled:(BOOL)enabled {
    [[ZNPatchManager sharedManager] setFeature:featureID enabled:enabled];
}

- (CGFloat)zn30_valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback {
    return (CGFloat)[[ZNPatchManager sharedManager] valueForFeature:featureID fallback:fallback];
}

- (void)zn30_setFeature:(NSString *)featureID value:(CGFloat)value {
    [[ZNPatchManager sharedManager] setFeature:featureID value:value];
}

- (NSArray<NSString *> *)zn30_baseCategories {
    return @[@"首页", @"玩家", @"战斗", @"移动", @"其他", @"设置", @"主题"];
}

- (NSArray<NSString *> *)zn30_baseSymbols {
    return @[@"house.fill", @"person.fill", @"bolt.fill", @"location.north.fill", @"square.grid.2x2.fill", @"gearshape.fill", @"paintpalette.fill"];
}

- (void)zn30_refreshDeveloperCategories:(BOOL)force {
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    BOOL dev = gate.authorized;
    NSMutableArray<NSString *> *cats = [[self zn30_baseCategories] mutableCopy];
    NSMutableArray<NSString *> *symbols = [[self zn30_baseSymbols] mutableCopy];
    if (dev) {
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

- (void)zn31_updateIdentitySubtitle {
    if (!self.uiReady || !self.subtitleLabel) return;
    NSString *udid = [ZNDeveloperGate sharedGate].observedUDID ?: @"";
    self.subtitleLabel.text = udid.length ? udid : @"";
    self.subtitleLabel.adjustsFontSizeToFitWidth = YES;
    self.subtitleLabel.minimumScaleFactor = 0.42;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
}

- (void)zn30_makeUI:(UIWindow *)window {
    [self zn30_makeUI:window];
    [self zn30_refreshDeveloperCategories:YES];
    [self zn31_updateIdentitySubtitle];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.3.1    LocalTicket    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn30_tick:(NSTimer *)timer {
    [self zn30_tick:timer];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn30_refreshDeveloperCategories:NO];
    [self zn31_updateIdentitySubtitle];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.3.1    LocalTicket    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn30_togglePanel:(id)sender {
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn30_refreshDeveloperCategories:NO];
    [self zn30_togglePanel:sender];
    [self zn31_updateIdentitySubtitle];
}

- (CGSize)zn30_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn30_fullSizeForWindow:window];
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"]) {
        UIEdgeInsets insets = window.safeAreaInsets;
        CGFloat available = CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0;
        size.height = MIN(MAX(size.height, 470.0), MAX(300.0, available));
    }
    return size;
}

- (void)zn30_updateContentHeight:(CGFloat)y {
    CGRect frame = self.contentView.frame;
    frame.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y+8.0);
    self.contentView.frame = frame;
    self.contentScroll.contentSize = frame.size;
}

- (void)zn30_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width {
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
        l.minimumScaleFactor = 0.72;
        [card addSubview:l];
        ly += lineH;
    }
    [self.contentView addSubview:card];
    *y += h+8.0;
}

- (UIButton *)zn30_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
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

- (void)zn30_addActionCardY:(CGFloat *)y width:(CGFloat)width titles:(NSArray<NSString *> *)titles selectors:(NSArray<NSString *> *)selectors {
    UIView *card = [self cardAtY:*y height:54 width:width compact:NO];
    CGFloat gap = 8.0;
    CGFloat inner = card.bounds.size.width-26.0;
    CGFloat bw = (inner-gap*(titles.count-1))/MAX((CGFloat)titles.count,1.0);
    for (NSInteger i=0; i<titles.count; i++) {
        CGRect f = CGRectMake(13+i*(bw+gap),10,bw,34);
        [card addSubview:[self zn30_button:titles[i] selector:NSSelectorFromString(selectors[i]) frame:f]];
    }
    [self.contentView addSubview:card];
    *y += 62.0;
}

- (void)zn30_appendDeveloperUnlockCard {
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    if (!gate.markerPresent || gate.authorized) return;
    CGFloat y = 8.0;
    for (UIView *v in self.contentView.subviews) y = MAX(y, CGRectGetMaxY(v.frame)+8.0);
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    UIView *card = [self cardAtY:y height:88 width:width compact:NO];
    UILabel *t = [self label:@"开发者验证" size:12.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(13,7,110,20); [card addSubview:t];
    UILabel *s = [self label:gate.lastError.length?gate.lastError:@"等待 zonoe 本地票据" size:9.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    s.frame = CGRectMake(13,29,card.bounds.size.width-118,18); s.adjustsFontSizeToFitWidth=YES; s.minimumScaleFactor=0.7; [card addSubview:s];
    UIButton *verify = [self zn30_button:@"打开 zonoe" selector:@selector(zn30_validateUDID:) frame:CGRectMake(card.bounds.size.width-99,26,86,32)];
    [card addSubview:verify];
    UILabel *path = [self label:[NSString stringWithFormat:@"1: %@ · g + UDID",gate.markerPath.lastPathComponent ?: @"1"] size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    path.frame=CGRectMake(13,59,card.bounds.size.width-26,16); [card addSubview:path];
    [self.contentView addSubview:card];
    [self zn30_updateContentHeight:CGRectGetMaxY(card.frame)];
}

- (void)zn30_replaceHomeVersionText {
    for (UIView *view in self.contentView.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        if ([label.text hasPrefix:@"V0.2.4 UI"]) label.text = @"V0.3.1 Core · Local Device Ticket";
    }
}

- (void)zn30_renderDiagnostics {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = 9.0;
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    ZNPatchManager *pm = [ZNPatchManager sharedManager];
    NSDictionary *counts = pm.stateCounts;
    NSDictionary *main = [ZNModuleManager sharedManager].mainExecutable;
    NSDictionary *unity = [ZNModuleManager sharedManager].unityFramework;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";

    [self addSection:@"Runtime 诊断" subtitle:@"Developer Gate 已授权 · Local Ticket / MockBackend" y:&y width:width];
    [self zn30_addInfoCard:@"Runtime" lines:@[
        @"Status: Ready",
        @"Core Version: 0.3.1-local-ticket    API: 2",
        [NSString stringWithFormat:@"Bundle: %@  App: %@",bundle,version],
        [NSString stringWithFormat:@"iOS: %@",UIDevice.currentDevice.systemVersion]
    ] y:&y width:width];

    NSString *mainLine = main ? [NSString stringWithFormat:@"Main: %@  base=0x%llx",main[@"name"],[main[@"base"] unsignedLongLongValue]] : @"Main: Not Found";
    NSString *unityLine = unity ? [NSString stringWithFormat:@"UnityFramework: Loaded  base=0x%llx",[unity[@"base"] unsignedLongLongValue]] : @"UnityFramework: Not Loaded";
    [self zn30_addInfoCard:@"Modules" lines:@[mainLine,unityLine,[NSString stringWithFormat:@"Images: %lu",(unsigned long)[ZNModuleManager sharedManager].loadedImages.count]] y:&y width:width];

    [self zn30_addInfoCard:@"Developer Gate" lines:@[
        [NSString stringWithFormat:@"State: %@",gate.authorized?@"Authorized":@"Locked"],
        [NSString stringWithFormat:@"Source: %@",gate.sourceDescription],
        [NSString stringWithFormat:@"UDID: %@",[gate maskedUDID:gate.observedUDID]],
        [NSString stringWithFormat:@"Host Bridge: %@",gate.hostBridgeAvailable?@"Available":@"Unavailable"]
    ] y:&y width:width];

    [self zn30_addInfoCard:@"Patch Manager" lines:@[
        [NSString stringWithFormat:@"Registered: %@   Enabled: %@   Disabled: %@",counts[@"registered"],counts[@"enabled"],counts[@"disabled"]],
        [NSString stringWithFormat:@"Unsupported: %@   Failed: %@",counts[@"unsupported"],counts[@"failed"]],
        @"Backend: Mock (v0.3.1 does not patch executable code)"
    ] y:&y width:width];

    [self zn30_addActionCardY:&y width:width titles:@[@"运行完整诊断",@"复制诊断信息"] selectors:@[@"zn30_runDiagnostics:",@"zn30_copyDiagnostics:"]];
    [self zn30_addActionCardY:&y width:width titles:@[@"重新验证 UDID",@"Self Test"] selectors:@[@"zn30_validateUDID:",@"zn30_selfTest:"]];
    [self zn30_updateContentHeight:y];
}

- (void)zn30_renderDebug {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = 9.0;
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    [self addSection:@"Debug" subtitle:@"Host Bridge / Local Ticket / Patch 状态 / 最近日志" y:&y width:width];
    [self zn30_addInfoCard:@"Device Identity" lines:@[
        @"Host symbols: ZonoeHostGetUDID / ZonoeHostIsAuthorized",
        [NSString stringWithFormat:@"Host Bridge: %@",gate.hostBridgeAvailable?@"Available":@"Not Exported"],
        [NSString stringWithFormat:@"Identity Source: %@",gate.sourceDescription],
        [NSString stringWithFormat:@"Local Ticket: %@",gate.awaitingZonoe?@"Pending":@"Idle"],
        [NSString stringWithFormat:@"Marker: %@",gate.markerPath.length?gate.markerPath:@"Not Found"]
    ] y:&y width:width];

    NSMutableArray<NSString *> *patchLines = [NSMutableArray array];
    for (ZNPatchDescriptor *d in [ZNPatchManager sharedManager].allDescriptors) {
        [patchLines addObject:[NSString stringWithFormat:@"%@  %@  value=%.2f  %@",d.identifier,ZNStringForPatchState(d.state),d.value,d.backend]];
    }
    [self zn30_addInfoCard:@"Patch Descriptors" lines:patchLines y:&y width:width];

    NSArray<NSString *> *logs = [[ZNRuntimeLogger sharedLogger] recentLines:8];
    if (!logs.count) logs = @[@"No runtime logs"];
    [self zn30_addInfoCard:@"Recent Logs" lines:logs y:&y width:width];
    [self zn30_addActionCardY:&y width:width titles:@[@"Self Test",@"清空日志"] selectors:@[@"zn30_selfTest:",@"zn30_clearLogs:"]];
    [self zn30_updateContentHeight:y];
}

- (void)zn30_renderFullPage {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"]) { [self zn30_renderDiagnostics]; return; }
    if ([cat isEqualToString:@"Debug"]) { [self zn30_renderDebug]; return; }
    [self zn30_renderFullPage];
    if ([cat isEqualToString:@"首页"]) {
        [self zn30_replaceHomeVersionText];
        [self zn30_appendDeveloperUnlockCard];
    }
}

- (NSString *)zn30_fullReport {
    NSMutableString *report = [NSMutableString string];
    [report appendString:[[ZNPatchManager sharedManager] diagnosticReport]];
    [report appendString:@"\n"];
    [report appendString:[[ZNDeveloperGate sharedGate] diagnosticReport]];
    NSArray *logs = [[ZNRuntimeLogger sharedLogger] recentLines:20];
    if (logs.count) {
        [report appendString:@"\nRecent Logs:\n"];
        [report appendString:[logs componentsJoinedByString:@"\n"]];
        [report appendString:@"\n"];
    }
    return report;
}

- (void)zn30_runDiagnostics:(id)sender {
    (void)sender;
    BOOL selfTest = [[ZNPatchManager sharedManager] runSelfTest];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Full diagnostic complete: %@",selfTest?@"PASS":@"FAIL"]];
    [self renderPage];
}

- (void)zn30_copyDiagnostics:(id)sender {
    (void)sender;
    UIPasteboard.generalPasteboard.string = [self zn30_fullReport];
    [[ZNRuntimeLogger sharedLogger] log:@"Diagnostic report copied"];
    [self renderPage];
}

- (void)zn30_validateUDID:(id)sender {
    (void)sender;
    [[ZNDeveloperGate sharedGate] requestZonoeValidation];
}

- (void)zn30_selfTest:(id)sender {
    (void)sender;
    [[ZNPatchManager sharedManager] runSelfTest];
    [self renderPage];
}

- (void)zn30_clearLogs:(id)sender {
    (void)sender;
    [[ZNRuntimeLogger sharedLogger] clear];
    [[ZNRuntimeLogger sharedLogger] log:@"Logs cleared"];
    [self renderPage];
}
@end

static void ZNSwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a,b);
}

static void ZNInstallV030Swizzles(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV030");
    if (!cls) return;
    ZNSwapInstanceMethod(cls,@selector(init),@selector(zn30_init));
    ZNSwapInstanceMethod(cls,@selector(enabledForFeature:),@selector(zn30_enabledForFeature:));
    ZNSwapInstanceMethod(cls,@selector(setFeature:enabled:),@selector(zn30_setFeature:enabled:));
    ZNSwapInstanceMethod(cls,@selector(valueForFeature:fallback:),@selector(zn30_valueForFeature:fallback:));
    ZNSwapInstanceMethod(cls,@selector(setFeature:value:),@selector(zn30_setFeature:value:));
    ZNSwapInstanceMethod(cls,@selector(renderFullPage),@selector(zn30_renderFullPage));
    ZNSwapInstanceMethod(cls,@selector(fullSizeForWindow:),@selector(zn30_fullSizeForWindow:));
    ZNSwapInstanceMethod(cls,@selector(tick:),@selector(zn30_tick:));
    ZNSwapInstanceMethod(cls,@selector(makeUI:),@selector(zn30_makeUI:));
    ZNSwapInstanceMethod(cls,@selector(togglePanel:),@selector(zn30_togglePanel:));
}

extern "C" __attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void) { return 2; }
extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void) { return "0.3.1-local-ticket"; }
extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void) {
    [[ZNDeveloperGate sharedGate] refresh];
    [ZNPatchManager sharedManager];
    ZonoePatchStartBaselineV024();
}
extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void) { ZonoePatchShowBaselineV024(); }
extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void) { ZonoePatchHideBaselineV024(); }
extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void) { return ZonoePatchIsVisibleBaselineV024(); }
