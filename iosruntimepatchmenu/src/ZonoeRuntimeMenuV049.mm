#include "ZonoeRuntimeMenuV048.mm"
#import "ZNSharedSiteProbe.h"

// v0.4.9 Shared-Site Probe.
// Developer-only instrumentation for the known EarntoDieRogue sample. It hooks
// the patch object's -setActive: entry and records the shared UnityFramework
// site before / after each Posters(5) or Prestige(10) transition. This is a
// diagnostic probe only; it does not write target executable memory.

@interface ZNRuntimeMenuControllerV040 (V049)
- (void)zn49_renderDebug;
- (void)zn49_makeUI:(UIWindow *)window;
- (void)zn49_tick:(NSTimer *)timer;
- (void)zn49_toggleSharedSiteProbe:(id)sender;
- (void)zn49_snapshotSharedSiteProbe:(id)sender;
- (void)zn49_clearSharedSiteProbe:(id)sender;
- (void)zn49_copySharedSiteProbe:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V049)

- (void)zn49_renderDebug {
    [self zn49_renderDebug];

    CGFloat width=CGRectGetWidth(self.contentView.bounds);
    CGFloat y=MAX(CGRectGetHeight(self.contentView.frame),CGRectGetHeight(self.contentScroll.bounds))+4.0;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];

    [self addSection:@"Shared-Site Probe"
            subtitle:@"开发者专项探针 · MdhpNuX -setActive: · Posters(5) / Prestige(10) · 只读共享地址"
                   y:&y
               width:width];
    [self zn40_addInfoCard:@"0x2E25904 专项状态" lines:[probe diagnosticLines] y:&y width:width];

    NSString *toggleTitle=probe.isLoggingEnabled?@"暂停 Probe":@"启用 Probe";
    [self zn40_addActionCardY:&y width:width
                        titles:@[toggleTitle,@"记录当前状态"]
                     selectors:@[@"zn49_toggleSharedSiteProbe:",@"zn49_snapshotSharedSiteProbe:"]];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"清除 Probe 日志",@"复制 Probe 日志"]
                     selectors:@[@"zn49_clearSharedSiteProbe:",@"zn49_copySharedSiteProbe:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn49_toggleSharedSiteProbe:(id)sender {
    (void)sender;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];
    if (!probe.isInstalled || !probe.isLoggingEnabled) {
        NSString *error=nil;
        BOOL ok=[probe installAndEnable:&error];
        if (!ok) [self zn43_showMessage:@"Probe 启用失败" body:error?:@"未知错误"];
    } else {
        [probe setLoggingEnabled:NO];
    }
    [self renderPage];
}

- (void)zn49_snapshotSharedSiteProbe:(id)sender {
    (void)sender;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];
    if (!probe.isInstalled) {
        NSString *error=nil;
        if (![probe installAndEnable:&error]) {
            [self zn43_showMessage:@"Probe 未安装" body:error?:@"未知错误"];
            [self renderPage];
            return;
        }
    }
    [probe captureCurrentStateWithLabel:@"manual"];
    [self renderPage];
}

- (void)zn49_clearSharedSiteProbe:(id)sender {
    (void)sender;
    [[ZNSharedSiteProbe sharedProbe] clearLog];
    [self renderPage];
}

- (void)zn49_copySharedSiteProbe:(id)sender {
    (void)sender;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];
    UIPasteboard.generalPasteboard.string=[probe logText];
    [[ZNRuntimeLogger sharedLogger] log:@"[SSP] Probe 日志已复制"];
    [self renderPage];
}

- (void)zn49_makeUI:(UIWindow *)window {
    [self zn49_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.9    Shared-Site setActive Probe    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn49_tick:(NSTimer *)timer {
    [self zn49_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.9    Shared-Site setActive Probe    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV049(Class cls,SEL a,SEL b) {
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if (x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(114))) static void ZNInstallV049SharedSiteProbeUI(void) {
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapV049(cls,@selector(zn40_renderDebug),@selector(zn49_renderDebug));
        ZNSwapV049(cls,@selector(makeUI:),@selector(zn49_makeUI:));
        ZNSwapV049(cls,@selector(tick:),@selector(zn49_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.9 shared-site setActive probe UI installed"];
    }
}
