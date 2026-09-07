#include "ZonoeRuntimeMenuV042.mm"
#import "ZNPatchRuntimeValidator.h"

// v0.4.3 developer runtime-validation layer.
// The production target remains stock iOS / No-JIT. This page is a developer
// verification tool for the user's capable test device: it captures live OFF
// bytes, applies one temporary code patch, verifies it, and restores exactly.

static UIViewController *ZN43TopController(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).visibleViewController ?: vc;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController ?: vc;
    return vc;
}

static NSString *ZN43HexString(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = (const uint8_t *)data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02X", p[i]];
    return s;
}

// Methods implemented by the included v0.4.0/v0.4.2 layers. Keep these in a
// declaration-only category so Clang does not treat them as missing V043 methods.
@interface ZNRuntimeMenuControllerV040 (V043BaseMethods)
- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_addActionCardY:(CGFloat *)y width:(CGFloat)width titles:(NSArray<NSString *> *)titles selectors:(NSArray<NSString *> *)selectors;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V043)
- (void)zn43_renderDebug;
- (void)zn43_makeUI:(UIWindow *)window;
- (void)zn43_tick:(NSTimer *)timer;
- (void)zn43_configureRuntimePatch:(id)sender;
- (void)zn43_validateRuntimePatch:(id)sender;
- (void)zn43_applyRuntimePatch:(id)sender;
- (void)zn43_restoreRuntimePatch:(id)sender;
- (void)zn43_copyRuntimeValidation:(id)sender;
- (void)zn43_clearRuntimeValidation:(id)sender;
- (void)zn43_showMessage:(NSString *)title body:(NSString *)body;
@end

@implementation ZNRuntimeMenuControllerV040 (V043)

- (void)zn43_renderDebug {
    [self zn43_renderDebug];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = MAX(CGRectGetHeight(self.contentView.frame), CGRectGetHeight(self.contentScroll.bounds)) + 4.0;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];

    [self addSection:@"Patch 实机验证"
            subtitle:@"开发者工具 · target + offset + patch · Live Original · 临时应用 / 精确恢复"
                   y:&y
               width:width];
    [self zn40_addInfoCard:@"当前验证会话" lines:[validator diagnosticLines] y:&y width:width];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"配置 Patch", @"读取 / 验证"]
                     selectors:@[@"zn43_configureRuntimePatch:", @"zn43_validateRuntimePatch:"]];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"临时应用", @"恢复原始"]
                     selectors:@[@"zn43_applyRuntimePatch:", @"zn43_restoreRuntimePatch:"]];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"复制验证报告", @"清除会话"]
                     selectors:@[@"zn43_copyRuntimeValidation:", @"zn43_clearRuntimeValidation:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn43_makeUI:(UIWindow *)window {
    [self zn43_makeUI:window];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.3    Runtime Validation    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn43_tick:(NSTimer *)timer {
    [self zn43_tick:timer];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.3    Runtime Validation    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn43_showMessage:(NSString *)title body:(NSString *)body {
    UIViewController *presenter = ZN43TopController(self.hostWindow ?: UIApplication.sharedApplication.keyWindow);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Patch 验证"
                                                                   message:body ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)zn43_configureRuntimePatch:(id)sender {
    (void)sender;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];
    if (validator.isApplied) {
        [self zn43_showMessage:@"无法重新配置" body:@"当前临时 Patch 尚未恢复。请先点击“恢复原始”。"];
        return;
    }

    UIViewController *presenter = ZN43TopController(self.hostWindow ?: UIApplication.sharedApplication.keyWindow);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"配置运行时 Patch"
                                                                   message:@"只使用 target + offset + patch。JSON original 不参与验证，OFF 基线从当前原版进程现场读取。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Target，例如 UnityFramework";
        field.text = validator.target.length ? validator.target : @"UnityFramework";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Offset，例如 0x92AAF88";
        field.text = validator.isConfigured ? [NSString stringWithFormat:@"0x%llX", validator.rva] : @"";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Patch HEX，例如 02020014";
        field.text = validator.patchBytes.length ? ZN43HexString(validator.patchBytes) : @"";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *error = nil;
        BOOL ok = [validator configureTarget:alert.textFields[0].text ?: @""
                                offsetString:alert.textFields[1].text ?: @""
                                    patchHex:alert.textFields[2].text ?: @""
                                       error:&error];
        if (!ok) {
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] 配置失败：%@", error ?: @"未知错误"]];
            [weakSelf zn43_showMessage:@"配置失败" body:error ?: @"未知错误"];
        }
        [weakSelf renderPage];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)zn43_validateRuntimePatch:(id)sender {
    (void)sender;
    NSString *error = nil;
    BOOL ok = [[ZNPatchRuntimeValidator sharedValidator] validate:&error];
    if (!ok) [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] 读取验证失败：%@", error ?: @"未知错误"]];
    [self renderPage];
    if (!ok) [self zn43_showMessage:@"验证失败" body:error ?: @"未知错误"];
}

- (void)zn43_applyRuntimePatch:(id)sender {
    (void)sender;
    NSString *error = nil;
    BOOL ok = [[ZNPatchRuntimeValidator sharedValidator] applyTemporary:&error];
    [self renderPage];
    [self zn43_showMessage:ok ? @"临时应用成功" : @"临时应用失败"
                       body:ok ? [ZNPatchRuntimeValidator sharedValidator].lastResult : (error ?: @"未知错误")];
}

- (void)zn43_restoreRuntimePatch:(id)sender {
    (void)sender;
    NSString *error = nil;
    BOOL ok = [[ZNPatchRuntimeValidator sharedValidator] restoreOriginal:&error];
    [self renderPage];
    [self zn43_showMessage:ok ? @"恢复成功" : @"恢复失败"
                       body:ok ? [ZNPatchRuntimeValidator sharedValidator].lastResult : (error ?: @"未知错误")];
}

- (void)zn43_copyRuntimeValidation:(id)sender {
    (void)sender;
    UIPasteboard.generalPasteboard.string = [[ZNPatchRuntimeValidator sharedValidator] diagnosticReport];
    [[ZNRuntimeLogger sharedLogger] log:@"[runtime-validate] 验证报告已复制"];
    [self renderPage];
}

- (void)zn43_clearRuntimeValidation:(id)sender {
    (void)sender;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];
    if (validator.isApplied) {
        [self zn43_showMessage:@"无法清除" body:@"当前临时 Patch 尚未恢复。请先恢复原始字节。"];
        return;
    }
    [validator clearSession];
    [[ZNRuntimeLogger sharedLogger] log:@"[runtime-validate] 验证会话已清除"];
    [self renderPage];
}

@end

static void ZNSwapInstanceMethodV043(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(106))) static void ZNInstallV043RuntimeValidation(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV043(cls, @selector(zn40_renderDebug), @selector(zn43_renderDebug));
        ZNSwapInstanceMethodV043(cls, @selector(makeUI:), @selector(zn43_makeUI:));
        ZNSwapInstanceMethodV043(cls, @selector(tick:), @selector(zn43_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.3 runtime validation installed: live-original / temporary-apply / verified-restore"];
    }
}
